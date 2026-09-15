-- Abstract evaluation over a verified belt: the computing half of demand.
--
-- An answer is `Known(v)` -- exact, and derived only from the rules in DEMAND.md §6 -- or
-- `Runtime(T)`. Ordered operations are never folded, because their result types include
-- Effect. That makes the purity gate structural rather than conventional.
--
-- This machine shares §13.2 scalar semantics with the concrete interpreter through
-- `v2.scalar`, so folding cannot disagree with execution.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local scalar=require('v2.scalar')

local Known={}

-- Answers -------------------------------------------------------------------------

function Known.runtime(type_) return {runtime=true,type=type_} end
function Known.value(type_,value) return {type=type_,value=value} end
function Known.is_known(answer) return answer~=nil and answer.runtime~=true end
function Known.is_runtime(answer) return answer==nil or answer.runtime==true end
function Known.bundle(type_,fields) return Known.value(type_,{fields=fields}) end

local function is_bundle(type_) return B.Word:isclassof(type_) or B.Aggregate:isclassof(type_) end

function Known.same(a,b)
    if a==nil or b==nil then return false end
    if Known.is_runtime(a) or Known.is_runtime(b) then
        return Known.is_runtime(a) and Known.is_runtime(b) and a.type:same(b.type)
    end
    if not a.type:same(b.type) then return false end
    if is_bundle(a.type) then
        local fields=a.type.fields
        for i=1,#fields do if not Known.same(a.value.fields[i],b.value.fields[i]) then return false end end
        return true
    end
    return scalar.equal(a.value,b.value)
end

function Known.join(a,b)
    if a==nil then return b end
    if b==nil then return a end
    if Known.same(a,b) then return a end
    return Known.runtime(a.type)
end

-- A canonical, injective-enough text form, used to intern summaries.
function Known.key(answer)
    if Known.is_runtime(answer) then return '?' .. tostring(answer.type) end
    if is_bundle(answer.type) then
        local parts={}
        for _,field in ipairs(answer.value.fields) do parts[#parts+1]=Known.key(field) end
        return '{' .. table.concat(parts,',') .. '}'
    end
    if answer.type==B.Int then local hi,lo=scalar.limbs(answer.value); return ('i%08x%08x'):format(hi,lo) end
    if answer.type==B.Bool then return answer.value and 'b1' or 'b0' end
    if answer.type==B.Unit then return 'u' end
    if answer.type==B.Text then return 't' .. #answer.value .. ':' .. answer.value end
    return '?' .. tostring(answer.type)
end

-- A run holds everything shared between a root function and its callees.
local Evaluator
local Run={}; Run.__index=Run
function Run.new(program,options)
    return setmetatable({program=program,hosts=(options or {}).hosts or {},
        summaries={},budget=(options or {}).summary_budget or 256},Run)
end

function Run:summary(target,seeded)
    local parts={}
    for _,answer in ipairs(seeded) do parts[#parts+1]=Known.key(answer) end
    local key=target .. '|' .. table.concat(parts,',')
    local cached=self.summaries[key]
    if cached~=nil then return cached or nil end
    if self.budget<=0 then self.summaries[key]=false; return nil end
    -- Marked in progress: a recursive cycle must not fold.
    self.summaries[key]=false; self.budget=self.budget-1
    local evaluator=Evaluator.new(self,self.program.functions[target],{parameters=seeded})
    evaluator:analyze()
    -- The final effect result is Runtime by construction and is not a value obligation.
    local foldable=not evaluator.residual
    if foldable then
        for i,answer in ipairs(evaluator.results) do
            local type_=self.program.functions[target].signature.results[i]
            if type_~=B.Effect and not Known.is_known(answer) then foldable=false end
        end
    end
    local summary=foldable and {results=evaluator.results} or nil
    self.summaries[key]=summary or false
    return summary
end

-- Evaluator ------------------------------------------------------------------------

Evaluator={}; Evaluator.__index=Evaluator

function Evaluator.new(run,belt,options)
    local self=setmetatable({run=run,program=run.program,hosts=run.hosts,belt=belt,options=options or {},
        answers={},params={},decision={},widened={},residual=false},Evaluator)
    self:reset()
    return self
end

-- Seeded parameters are how a call site asks about a concrete packet; anything not seeded
-- is a generic runtime input.
function Evaluator:reset()
    self.answers,self.params,self.decision,self.widened,self.residual={},{},{},{},false
    self.changed=false
    local seeded=self.options.parameters
    if seeded then
        local entry={}
        for i,answer in ipairs(seeded) do entry[i]=answer end
        self.params[1]=entry
    end
end

-- Concrete-abstract execution: follow one iteration at a time while every control decision
-- remains decidable. This is what lets a loop with a known trip count fold away entirely,
-- which widening alone cannot do because it deliberately forgets the induction variable.
-- It gives up on anything it cannot enumerate: an undecidable branch, a repeated instance,
-- demanded ordered work, or the step budget.
function Evaluator:enumerate()
    local budget=self.options.unroll_limit or 32
    local visited,steps,returns={},0,nil
    local function key_of(block_id,packet)
        local parts={block_id}
        for _,answer in ipairs(packet) do parts[#parts+1]=Known.key(answer) end
        return table.concat(parts,'|')
    end
    local function visit(block_id,packet)
        if steps>=budget then return false end
        local key=key_of(block_id,packet)
        if visited[key] then return false end
        visited[key]=true; steps=steps+1
        local block=self.belt.blocks[block_id]
        self.params[block_id]=packet
        local demanded=self.needed[block_id]
        local recorded={}
        self.answers[block_id]=recorded
        for index,instruction in ipairs(block.instructions) do
            local position=#block.parameters+index-1
            if demanded and demanded[position] then
                recorded[position]=self:instruction(block,block_id,index,instruction)
                -- Ordered work has to be emitted, so it cannot be executed here.
                if self.residual then return false end
            end
        end
        local position=#block.parameters+#block.instructions
        local exit=block.exit
        local function packet_of(edge)
            local packet={}
            for i,ref in ipairs(edge.arguments) do packet[i]=self:resolve(block,block_id,position,ref) end
            return packet
        end
        if B.Return:isclassof(exit) then
            returns=packet_of({arguments=exit.values})
            return true
        elseif B.Branch:isclassof(exit) then
            local condition=self:resolve(block,block_id,position,exit.condition)
            if not Known.is_known(condition) then return false end
            return visit((condition.value and exit.yes or exit.no).target,packet_of(condition.value and exit.yes or exit.no))
        elseif B.Jump:isclassof(exit) then
            return visit(exit.edge.target,packet_of(exit.edge))
        end
        return false
    end
    local entry={}
    for i,parameter in ipairs(self.belt.blocks[1].parameters) do entry[i]=self:parameter(1,i) end
    if not visit(1,entry) then return false end
    -- Fold only if nothing observable remains and every value result is exact.
    local types=self.belt.signature.results
    for i,type_ in ipairs(types) do
        if type_~=B.Effect and not Known.is_known(returns[i]) then return false end
    end
    self.results=returns
    return true
end

-- Blocks participating in a cycle. Without widening, a known value must not travel
-- around a backedge, so their parameters stay Runtime.
function Known.cyclic_blocks(belt)
    local on_cycle={}
    local function reaches(from,to,seen)
        if from==to then return true end
        if seen[from] then return false end
        seen[from]=true
        for _,edge in ipairs(belt.blocks[from].exit:edges()) do
            if reaches(edge.target,to,seen) then return true end
        end
        return false
    end
    for id,block in ipairs(belt.blocks) do
        for _,edge in ipairs(block.exit:edges()) do
            if edge.target<=id and reaches(edge.target,id,{}) then on_cycle[id]=true; on_cycle[edge.target]=true end
        end
    end
    return on_cycle
end

function Evaluator:parameter(block_id,index)
    local entry=self.params[block_id]
    if entry and entry[index] then return entry[index] end
    return Known.runtime(self.belt.blocks[block_id].parameters[index].type)
end

function Evaluator:param(block_id,index) return self:parameter(block_id,index) end

function Evaluator:answer(block_id,position,output)
    local block=self.answers[block_id]
    local answers=block and block[position]
    return answers and answers[output+1]
end

function Evaluator:resolve(block,block_id,position,ref)
    local producer=position-1-ref.distance
    if producer<#block.parameters then return self:parameter(block_id,producer+1) end
    local answer=self:answer(block_id,producer,ref.output)
    if answer then return answer end
    local result=block.instructions[producer-#block.parameters+1].results[ref.output+1]
    return Known.runtime(result)
end

local arithmetic={[A.Add]=scalar.add,[A.Subtract]=scalar.subtract,[A.Multiply]=scalar.multiply}
local relations={[A.Less]=scalar.less,[A.LessEqual]=scalar.less_equal,[A.Greater]=scalar.greater,[A.GreaterEqual]=scalar.greater_equal}
local equalities={[A.Equal]=scalar.equal,[A.NotEqual]=scalar.not_equal}

-- Ordered work was demanded and could not be folded, so no caller may fold this away.
function Evaluator:schedule(operation)
    self.residual=true
    self.scheduled=self.scheduled or {}
    self.scheduled[#self.scheduled+1]=tostring(operation)
end

function Evaluator:instruction(block,block_id,index,instruction)
    local position=#block.parameters+index-1
    local operation=instruction.operation
    local results={}
    local function put(output,answer) results[output+1]=answer end
    local function runtime_all()
        for i=1,#instruction.results do put(i-1,Known.runtime(instruction.results[i])) end
    end
    local function inputs(refs)
        local out={} for i,ref in ipairs(refs) do out[i]=self:resolve(block,block_id,position,ref) end
        return out
    end
    local function all_known(list)
        for _,answer in ipairs(list) do if not Known.is_known(answer) then return false end end
        return true
    end

    if B.IntegerLiteral:isclassof(operation) then
        put(0,Known.value(B.Int,scalar.integer(operation.spelling,error)))
    elseif B.BooleanLiteral:isclassof(operation) then
        put(0,Known.value(B.Bool,operation.value))
    elseif B.UnitLiteral:isclassof(operation) then
        put(0,Known.value(B.Unit,scalar.unit))
    elseif B.TextLiteral:isclassof(operation) then
        put(0,Known.value(B.Text,operation.value))
    elseif B.Unary:isclassof(operation) then
        local operand=inputs{operation.operand}[1]
        if Known.is_known(operand) then
            put(0,Known.value(instruction.results[1],operation.operator==A.Not and not operand.value or scalar.negate(operand.value)))
        else put(0,Known.runtime(instruction.results[1])) end
    elseif B.Binary:isclassof(operation) then
        local arguments=inputs{operation.left,operation.right}
        if all_known(arguments) then
            local left,right=arguments[1].value,arguments[2].value
            local value
            if arguments[1].type==B.Text then value=equalities[operation.operator](left,right)
            elseif arithmetic[operation.operator] then value=arithmetic[operation.operator](left,right)
            elseif relations[operation.operator] then value=relations[operation.operator](left,right)
            elseif equalities[operation.operator] then value=equalities[operation.operator](left,right)
            elseif operation.operator==A.And then value=left and right
            elseif operation.operator==A.Or then value=left or right end
            put(0,Known.value(instruction.results[1],value))
        else put(0,Known.runtime(instruction.results[1])) end
    elseif B.CheckedBinary:isclassof(operation) then
        local arguments=inputs{operation.left,operation.right}
        -- §16.2: omit a check only when failure is proved impossible. A known non-zero
        -- divisor proves it; anything else keeps the residual checked operation.
        if all_known(arguments) and arguments[2].value~=0 then
            local rule=operation.operator==A.Divide and scalar.divide or scalar.remainder
            put(0,Known.value(B.Int,rule(arguments[1].value,arguments[2].value)))
        else
            put(0,Known.runtime(B.Int)); self:schedule(operation)
        end
        put(1,Known.runtime(B.Effect))
    elseif B.FieldAddress:isclassof(operation) then
        put(0,Known.runtime(instruction.results[1]))
    elseif B.BorrowPlace:isclassof(operation) then
        put(0,Known.runtime(instruction.results[1]))
    elseif B.Construct:isclassof(operation) then
        local arguments=inputs(operation.fields)
        if all_known(arguments) then
            local fields={} for i,answer in ipairs(arguments) do fields[i]=answer end
            put(0,Known.bundle(instruction.results[1],fields))
        else put(0,Known.runtime(instruction.results[1])) end
    elseif B.LoadField:isclassof(operation) then
        local answer=inputs{operation.record}[1]
        if Known.is_known(answer) and answer.value.fields[operation.field+1] then put(0,answer.value.fields[operation.field+1])
        else put(0,Known.runtime(instruction.results[1])) end
    elseif B.StoreField:isclassof(operation) then
        local answer=inputs{operation.record}[1]
        if Known.is_known(answer) then
            local fields={} for i,field in ipairs(answer.value.fields) do fields[i]=field end
            fields[operation.field+1]=inputs{operation.value}[1]
            if all_known(fields) then put(0,Known.bundle(instruction.results[1],fields))
            else put(0,Known.runtime(instruction.results[1])) end
        else put(0,Known.runtime(instruction.results[1])) end
    elseif B.CallFunction:isclassof(operation) then
        local arguments=inputs(operation.arguments)
        local summary
        if all_known(arguments) then
            local seeded={Known.runtime(B.Effect)}
            for i,answer in ipairs(arguments) do seeded[i+1]=answer end
            summary=self.run:summary(operation.target,seeded)
        end
        if summary then for i,answer in ipairs(summary.results) do put(i-1,answer) end
        else runtime_all(); self:schedule(operation) end
    elseif B.HostCall:isclassof(operation) or B.PureHostCall:isclassof(operation) then
        runtime_all()
        if B.HostCall:isclassof(operation) then self:schedule(operation) end
    elseif B.Move:isclassof(operation) then
        -- Ownership is static, so a move is an identity on the value.
        put(0,self:resolve(block,block_id,position,operation.value))
        put(1,Known.runtime(B.Effect))
    elseif B.Destroy:isclassof(operation) then
        put(0,Known.runtime(B.Effect)); self:schedule(operation)
    else
        -- Load, Store, Allocate and anything not yet modeled: memory identity is
        -- observable, so the operation stays and there is no known result.
        runtime_all(); self:schedule(operation)
    end
    return results
end

-- A packet field supplied by an edge. A predecessor's own field may have no value yet
-- during the first pass; that is reported as nil so the join can stay optimistic, and
-- `verify_packets` is what makes the optimism sound.
function Evaluator:supplied(source,source_id,ref)
    local position=#source.parameters+#source.instructions
    local producer=position-1-ref.distance
    if producer<#source.parameters then
        local entry=self.params[source_id]
        return entry and entry[producer+1]
    end
    return self:answer(source_id,producer,ref.output)
end

-- The join over every live incoming edge. `optimistic` skips a contribution that does not
-- exist yet; otherwise a missing contribution is Runtime.
function Evaluator:incoming(block_id,optimistic)
    local belt=self.belt
    local joined,seen={},0
    for source_id,source in ipairs(belt.blocks) do
        if self.live_blocks[source_id] then
            local allowed=self.decision[source_id]
            for _,edge in ipairs(source.exit:edges()) do
                if edge.target==block_id and (allowed==nil or allowed==edge) then
                    seen=seen+1
                    for i,ref in ipairs(edge.arguments) do
                        local answer=self:supplied(source,source_id,ref)
                        if answer then joined[i]=Known.join(joined[i],answer)
                        elseif not optimistic then joined[i]=Known.join(joined[i],Known.runtime(self.belt.blocks[block_id].parameters[i].type)) end
                    end
                end
            end
        end
    end
    return joined,seen
end

function Evaluator:block(block_id)
    local belt=self.belt
    local block=belt.blocks[block_id]
    if block_id~=1 then
        local joined,seen=self:incoming(block_id,true)
        local previous=self.params[block_id] or {}
        local widened=self.widened[block_id]
        local next_={}
        for i,parameter in ipairs(block.parameters) do
            -- A widened packet stays widened: the iteration must move only toward Runtime,
            -- otherwise a later pass could reduce it again and oscillate.
            if widened and widened[i] then next_[i]=Known.runtime(parameter.type)
            else next_[i]=(seen>0 and joined[i]) or Known.runtime(parameter.type) end
            if not Known.same(previous[i],next_[i]) then self.changed=true end
        end
        self.params[block_id]=next_
    end
    local demanded=self.needed[block_id]
    local previous=self.answers[block_id]
    -- The table is published before it is filled so a reference to an earlier
    -- producer in the same block sees this pass's answer, not the previous pass's.
    local recorded={}
    self.answers[block_id]=recorded
    for index,instruction in ipairs(block.instructions) do
        local position=#block.parameters+index-1
        if demanded and demanded[position] then
            local answers=self:instruction(block,block_id,index,instruction)
            recorded[position]=answers
            for output,answer in ipairs(answers) do
                local was=previous and previous[position] and previous[position][output]
                if not Known.same(was,answer) then self.changed=true end
            end
        end
    end
    local exit=block.exit
    if B.Branch:isclassof(exit) then
        local condition=self:resolve(block,block_id,#block.parameters+#block.instructions,exit.condition)
        local decision=Known.is_known(condition) and (condition.value and exit.yes or exit.no) or nil
        if decision~=self.decision[block_id] then self.decision[block_id]=decision; self.changed=true end
    end
end

-- Blocks reachable through edges that were not falsified.
function Evaluator:live()
    local live,work={[1]=true},{1}
    while #work>0 do
        local id=table.remove(work)
        local allowed=self.decision[id]
        for _,edge in ipairs(self.belt.blocks[id].exit:edges()) do
            if (allowed==nil or allowed==edge) and not live[edge.target] then
                live[edge.target]=true; work[#work+1]=edge.target
            end
        end
    end
    return live
end

-- A stored packet is sound only if it equals the join of what the edges really supply.
-- An optimistic pass can guess a loop-carried value; this pass recomputes the true join
-- from the guessed answers and widens any packet that does not agree. Widening only ever
-- moves toward Runtime, so the outer loop terminates.
function Evaluator:verify_packets()
    local belt=self.belt
    local changed=false
    for block_id=2,#belt.blocks do
        if self.live_blocks[block_id] then
            local block=belt.blocks[block_id]
            local joined=self:incoming(block_id,false)
            for i,parameter in ipairs(block.parameters) do
                local stored=self:parameter(block_id,i)
                local actual=joined[i] or Known.runtime(parameter.type)
                if Known.is_known(stored) and not Known.same(stored,actual) then
                    self.params[block_id][i]=actual
                    self.widened[block_id]=self.widened[block_id] or {}
                    self.widened[block_id][i]=true
                    changed=true
                end
            end
        end
    end
    return changed
end

-- Widen every packet of a block in a cycle. The fallback when the fixed point needs more
-- iterations than the budget allows: it is always sound, and it terminates.
function Evaluator:widen_cycles()
    for block_id in pairs(Known.cyclic_blocks(self.belt)) do
        local block=self.belt.blocks[block_id]
        local next_={}
        self.widened[block_id]=self.widened[block_id] or {}
        for i,parameter in ipairs(block.parameters) do
            next_[i]=Known.runtime(parameter.type)
            self.widened[block_id][i]=true
        end
        self.params[block_id]=next_
    end
end

function Evaluator:fixpoint(limit)
    for _=1,limit do
        self.changed=false
        for block_id=1,#self.belt.blocks do
            if self.live_blocks[block_id] then self:block(block_id) end
        end
        self.live_blocks=self:live()
        if not self.changed then return true end
    end
    return false
end

function Evaluator:analyze()
    local belt=self.belt
    self.needed=self.options.demands or belt:demands()
    if self:enumerate() then
        -- Everything the function does is decided and nothing observable remains.
        self.folded=true
        self.live_blocks={}
        return self
    end
    self:reset()
    local limit=self.options.iteration_limit or 16
    self.live_blocks=self:live()
    local verified=false
    for _=1,limit do
        if not self:fixpoint(limit) then
            -- The optimistic pass did not settle; fall back to generic loop packets.
            self:widen_cycles()
            self:fixpoint(limit)
        end
        self.live_blocks=self:live()
        if not self:verify_packets() then verified=true; break end
        -- A widened packet changes the answers, so settle again before re-verifying.
        self:fixpoint(limit)
        self.live_blocks=self:live()
    end
    if not verified then self:widen_cycles(); self:fixpoint(limit); self.live_blocks=self:live() end
    local results
    for block_id in pairs(self.live_blocks) do
        local exit=belt.blocks[block_id].exit
        if B.Return:isclassof(exit) then
            local position=#belt.blocks[block_id].parameters+#belt.blocks[block_id].instructions
            local packet={}
            for i,ref in ipairs(exit.values) do packet[i]=self:resolve(belt.blocks[block_id],block_id,position,ref) end
            if results then
                for i,answer in ipairs(packet) do results[i]=Known.join(results[i],answer) end
            else results=packet end
        end
    end
    self.results=results or {}
    return self
end

Known.Evaluator=Evaluator

-- Analyze one belt function generically (all incoming parameters Runtime).
function Known.analyze(program,function_id,options)
    local run=options and options.run or Run.new(program,options)
    local evaluator=Evaluator.new(run,program.functions[function_id],options or {})
    evaluator:analyze()
    return evaluator,run
end

function Known.run(program,options) return Run.new(program,options) end

return Known
end
