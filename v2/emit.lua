-- Belt to C. The belt is already the semantic program, so this pass only chooses
-- representations and prints them. It is not a second semantic IR and never decides
-- evaluation order: statements follow the belt's ordered effect chain.
return function(V)
local A,B,C,L=V.AST,V.Belt,V.C,V.List
local literal=require('v2.literal')
local Known=V.Known
local scalar=V.scalar

local Emitter={}; Emitter.__index=Emitter

local function typekey(type_)
    if B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        local parts={}
        for _,field in ipairs(type_.fields) do parts[#parts+1]=(field.name or '') .. ':' .. typekey(field.type) end
        local tag=B.Word:isclassof(type_) and ('w' .. type_.template .. '/' .. type_.supplied) or 'a'
        return tag .. '(' .. tostring(type_.is_copy) .. ';' .. table.concat(parts,',') .. ')'
    end
    if B.Address:isclassof(type_) then return '*' .. typekey(type_.pointee) end
    if B.Named:isclassof(type_) then return 'n(' .. type_.name .. ')' end
    return tostring(type_)
end

function Emitter.new(options)
    return setmetatable({options=options or {},structs={},struct_names={},results={},result_names={},
        names={},helpers={},text=false,stdbool=true,trap=false},Emitter)
end

function Emitter:error(message) error('v2 C emission: ' .. message,0) end

function Emitter:register_struct(fields)
    local key='s'
    for _,field in ipairs(fields) do key=key .. '|' .. typekey(field) end
    local existing=self.struct_names[key]
    if existing then return "struct " .. existing end
    -- Nested aggregate fields must be declared first, so the name is chosen only
    -- after this struct's own fields have registered theirs.
    local declarations=L()
    -- Field names are zero-based to match belt member indices.
    for i,field in ipairs(fields) do declarations:insert(C.Parameter(self:ctype(field.type),'f' .. (i-1))) end
    local name='let_val_' .. (#self.structs+1)
    self.struct_names[key]=name
    self.structs[#self.structs+1]=C.Struct(name,declarations)
    return 'struct ' .. name
end

function Emitter:ctype(type_)
    if type_==B.Int then return C.I64 end
    if type_==B.Bool then return C.Bool end
    if type_==B.Unit then return C.U8 end
    if type_==B.Effect then return C.U64 end
    if type_==B.Text then self.text=true; return C.Named('struct let_text') end
    if B.Named:isclassof(type_) then return C.I64 end
    if B.Address:isclassof(type_) then return C.Pointer(self:ctype(type_.pointee)) end
    if B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        -- A record with no fields carries no information, and an empty struct is not ISO C.
        if #type_.fields==0 then return C.U8 end
        return C.Named(self:register_struct(type_.fields))
    end
    self:error('no representation for ' .. tostring(type_))
end

-- Effect tokens are ordering evidence for the frontend and have no C representation: the
-- belt's statement order already carries the order. Dropping them removes the effect
-- parameter, the effect field of every result, and every effect update.
function Emitter:value_types(types)
    local values={}
    for _,type_ in ipairs(types) do if type_~=B.Effect then values[#values+1]=type_ end end
    return values
end

-- A function returning no value is `void`; one returning a single value returns that type
-- directly. Only a genuine multiple result needs a struct.
function Emitter:return_shape(types)
    local values=self:value_types(types)
    if #values==0 then return C.Void,0 end
    if #values==1 then return self:ctype(values[1]),1 end
    local key='r'
    for _,type_ in ipairs(values) do key=key .. '|' .. typekey(type_) end
    local existing=self.result_names[key]
    if existing then return C.Named('struct ' .. existing),#values end
    local name='let_ret_' .. (#self.results+1)
    self.result_names[key]=name
    local declarations=L()
    for i,type_ in ipairs(values) do declarations:insert(C.Parameter(self:ctype(type_),'r' .. (i-1))) end
    self.results[#self.results+1]=C.Struct(name,declarations)
    return C.Named('struct ' .. name),#values
end

-- `values` are the materialized results only; the effect has already been dropped.
function Emitter:return_value(type_,values)
    if type_==C.Void then return nil end
    if #values==1 then return values[1] end
    return C.Compound(type_,values)
end

-- Negation is applied in 64-bit two's-complement form here rather than in C, where
-- negating INT64_MIN would be undefined and the magnitude may exceed a Lua number.
function Emitter:literal(spelling)
    local negative=spelling:sub(1,1)=='-'
    local _,_,hi,lo=literal.integer(negative and spelling:sub(2) or spelling,negative,function(m) self:error(m) end)
    if not negative or (hi==0 and lo==0) then return C.Integer(hi,lo) end
    local borrowed=lo==0 and 0 or 1
    return C.Integer((4294967296-hi-borrowed)%4294967296, lo==0 and 0 or 4294967296-lo)
end

function Emitter:param(belt_id,index) return 'p' .. belt_id .. '_' .. index end
function Emitter:value(belt_id,index,output) return 'v' .. belt_id .. '_' .. index .. '_' .. output end

-- Answers come from the abstract evaluator. A Known answer is inlined at every use and
-- its producer is never written out, so folding removes work rather than merely hiding it.
function Emitter:answer(block_id,position,output)
    local evaluator=self.analysis[self.current_id]
    return evaluator and evaluator:answer(block_id,position,output)
end

-- The recorded answer table for one producer, indexed by output.
function Emitter:answers_at(block_id,position)
    local evaluator=self.analysis[self.current_id]
    return evaluator and evaluator.answers[block_id] and evaluator.answers[block_id][position]
end

function Emitter:parameter_answer(block_id,index)
    local evaluator=self.analysis[self.current_id]
    return evaluator and evaluator:param(block_id,index)
end

function Emitter:constant(answer)
    local type_=answer.type
    if type_==B.Int then local hi,lo=scalar.limbs(answer.value); return C.Integer(hi,lo) end
    if type_==B.Bool then return C.Boolean(answer.value) end
    if type_==B.Unit then return C.Integer(0,0) end
    if type_==B.Text then return C.Compound(self:ctype(B.Text),L{C.String(answer.value),C.Integer(0,#answer.value)}) end
    if B.Word:isclassof(type_) or B.Aggregate:isclassof(type_) then
        if #answer.value.fields==0 then return C.Integer(0,0) end
        local fields=L()
        for _,field in ipairs(answer.value.fields) do fields:insert(self:constant(field)) end
        return C.Compound(self:ctype(type_),fields)
    end
    self:error('no C constant for ' .. tostring(type_))
end

-- A call whose every value result is Known was folded away by the evaluator, which only
-- happens when the callee demanded no ordered work.
function Emitter:folded_call(function_id,block_id,position,instruction)
    local analysis=self.analysis[function_id]
    local answers=analysis and analysis:answer(block_id,position,0)
    local recorded=analysis and analysis.answers[block_id] and analysis.answers[block_id][position]
    if not recorded then return false end
    for i,type_ in ipairs(instruction.results) do
        if type_~=B.Effect and not Known.is_known(recorded[i]) then return false end
    end
    return true
end

-- Resolve a belt reference to the C expression holding that output.
function Emitter:ref(block,block_id,position,ref)
    local producer=position-1-ref.distance
    if producer<#block.parameters then
        local answer=self:parameter_answer(block_id,producer+1)
        if Known.is_known(answer) then return self:constant(answer) end
        return C.Name(self:param(block_id,producer))
    end
    local answer=self:answer(block_id,producer,ref.output)
    if Known.is_known(answer) then return self:constant(answer) end
    return C.Name(self:value(block_id,producer-#block.parameters+1,ref.output))
end

function Emitter:arglist(block,block_id,position,refs)
    local out=L() for _,ref in ipairs(refs) do out:insert(self:ref(block,block_id,position,ref)) end
    return out
end

local symbolic={[A.Add]='+',[A.Subtract]='-',[A.Multiply]='*',[A.Less]='<',[A.LessEqual]='<=',
    [A.Greater]='>',[A.GreaterEqual]='>=',[A.Equal]='==',[A.NotEqual]='!=',[A.And]='&&',[A.Or]='||'}
local arithmetic={[A.Add]={'add','LET_ADD'}, [A.Subtract]={'sub','LET_SUB'}, [A.Multiply]={'mul','LET_MUL'}}

function Emitter:effect_step(effect)
    self.helpers.add=false
    return C.Binary('+',effect,C.Integer(0,1))
end

local function statement_list(list)
    local declarations=L(); for _,entry in ipairs(list) do declarations:insert(entry) end; return declarations
end

-- Emits one instruction. Returns a statement list; output variables are named by
-- (block, instruction index, output) so relative references stay resolvable.
function Emitter:instruction(block,block_id,index,instruction)
    local position=#block.parameters+index-1
    local operation=instruction.operation
    local out={}
    local answers=self:answers_at(block_id,position)
    local function known(output) return answers and Known.is_known(answers[output+1]) end
    local function declare(output,type_,expr)
        if type_==B.Effect then return false end
        if known(output) then return false end
        out[#out+1]=C.Declare(self:ctype(type_),self:value(block_id,index,output),expr)
        return true
    end
    if B.IntegerLiteral:isclassof(operation) then
        declare(0,B.Int,self:literal(operation.spelling))
    elseif B.BooleanLiteral:isclassof(operation) then
        declare(0,B.Bool,C.Boolean(operation.value))
    elseif B.UnitLiteral:isclassof(operation) then
        declare(0,B.Unit,C.Integer(0,0))
    elseif B.TextLiteral:isclassof(operation) then
        self.text=true
        declare(0,B.Text,C.Compound(self:ctype(B.Text),L{C.String(operation.value),C.Integer(0,#operation.value)}))
    elseif B.Unary:isclassof(operation) then
        local operand=self:arglist(block,block_id,position,{operation.operand})[1]
        if operation.operator==A.Not then declare(0,B.Bool,C.Unary('!',operand))
        elseif declare(0,B.Int,C.Call(C.Name('LET_NEG'),L{operand})) then self.helpers.neg=true end
    elseif B.Binary:isclassof(operation) then
        local arguments=self:arglist(block,block_id,position,{operation.left,operation.right})
        local _,type_=block:resolve(position,operation.left)
        if known(0) then return statement_list(out) end
        if operation.operator==A.Equal or operation.operator==A.NotEqual then
            local call
            if type_==B.Text then self.helpers.text_eq=true; call=C.Call(C.Name('LET_TEXT_EQ'),L{arguments[1],arguments[2]})
            else call=C.Binary(symbolic[operation.operator],arguments[1],arguments[2]) end
            declare(0,B.Bool,operation.operator==A.Equal and call or C.Unary('!',call))
        elseif arithmetic[operation.operator] then
            local helper=arithmetic[operation.operator]
            self.helpers[helper[1]]=true
            declare(0,B.Int,C.Call(C.Name(helper[2]),L{arguments[1],arguments[2]}))
        else
            declare(0,instruction.results[1],C.Binary(symbolic[operation.operator],arguments[1],arguments[2]))
        end
    elseif B.CheckedBinary:isclassof(operation) then
        local arguments=self:arglist(block,block_id,position,{operation.left,operation.right})
        local helper=operation.operator==A.Divide and 'let_div' or 'let_rem'
        if not known(0) then self.helpers[operation.operator==A.Divide and 'div' or 'rem']=true end
        local effect=self:ref(block,block_id,position,operation.effect)
        -- §16.2: a non-zero known divisor proves the check cannot fail, so it is omitted.
        if declare(0,B.Int,C.Call(C.Name(helper),L{arguments[1],arguments[2]})) then
            self.trap=true
            declare(1,B.Effect,C.Binary('+',effect,C.Integer(0,1)))
        else declare(1,B.Effect,effect) end
    elseif B.Construct:isclassof(operation) then
        if #operation.fields==0 then declare(0,instruction.results[1],C.Integer(0,0))
        else declare(0,instruction.results[1],C.Compound(self:ctype(instruction.results[1]),self:arglist(block,block_id,position,operation.fields))) end
    elseif B.LoadField:isclassof(operation) then
        local base=self:ref(block,block_id,position,operation.record)
        declare(0,instruction.results[1],C.Field(base,'f' .. operation.field))
    elseif B.StoreField:isclassof(operation) then
        local word=self:ref(block,block_id,position,operation.record)
        local type_=instruction.results[1]
        local fields=L()
        for i=0,#type_:record()-1 do
            if i==operation.field then fields:insert(self:ref(block,block_id,position,operation.value))
            else fields:insert(C.Field(word,'f' .. i)) end
        end
        declare(0,type_,C.Compound(self:ctype(type_),fields))
    elseif B.CallFunction:isclassof(operation) then
        if self:folded_call(self.current_id,block_id,position,instruction) then return statement_list(out) end
        local callee=self.functions[operation.target]
        -- The callee's effect parameter is not part of its C signature.
        local arguments=self:arglist(block,block_id,position,operation.arguments)
        local type_,count=self:return_shape(callee.signature.results)
        if count==0 then
            out[#out+1]=C.Evaluate(C.Call(C.Name(self:function_name(operation.target)),arguments))
        elseif count==1 then
            declare(0,instruction.results[1],C.Call(C.Name(self:function_name(operation.target)),arguments))
        else
            local temporary=self:value(block_id,index,'t')
            out[#out+1]=C.Declare(type_,temporary,C.Call(C.Name(self:function_name(operation.target)),arguments))
            local output=0
            for _,result in ipairs(instruction.results) do
                if result~=B.Effect then
                    declare(output,result,C.Field(C.Name(temporary),'r' .. output))
                    output=output+1
                end
            end
        end
    elseif B.HostCall:isclassof(operation) or B.PureHostCall:isclassof(operation) then
        local host=self.hosts[operation.symbol] or self:error('missing host contract for ' .. operation.symbol)
        local arguments=self:arglist(block,block_id,position,operation.arguments)
        local call=C.Call(C.Name(operation.symbol),statement_list(arguments))
        local pure=B.PureHostCall:isclassof(operation)
        if instruction.results[1]==B.Unit then out[#out+1]=C.Evaluate(call)
        else out[#out+1]=C.Declare(self:ctype(instruction.results[1]),self:value(block_id,index,0),call) end
        if not pure then
            local effect=self:ref(block,block_id,position,operation.effect)
            declare(#instruction.results-1,B.Effect,C.Binary('+',effect,C.Integer(0,1)))
        end
    elseif B.Move:isclassof(operation) then
        local value=self:ref(block,block_id,position,operation.value)
        if declare(0,instruction.results[1],value) then
            declare(1,B.Effect,C.Binary('+',self:ref(block,block_id,position,operation.effect),C.Integer(0,1)))
        else declare(1,B.Effect,self:ref(block,block_id,position,operation.effect)) end
    elseif B.Destroy:isclassof(operation) then
        local value=self:ref(block,block_id,position,operation.value)
        out[#out+1]=C.Evaluate(C.Call(C.Name(operation.destructor),L{value}))
        declare(0,B.Effect,C.Binary('+',self:ref(block,block_id,position,operation.effect),C.Integer(0,1)))
    else
        self:error('no representation for ' .. tostring(operation))
    end
    return statement_list(out)
end

-- The entry packet is the function's ABI, so block 1 is never pruned. Other packets
-- drop fields whose output no consumer demands, together with their edge copies.
function Emitter:needed_parameter(block_id,index)
    if self.current.blocks[block_id].parameters[index].type==B.Effect then return false end
    if block_id==1 then return true end
    if Known.is_known(self:parameter_answer(block_id,index)) then return false end
    local block=self.needed[block_id]
    return (block and block[index-1] and block[index-1][0]) and true or false
end

-- Edge packets are parallel assignments, so a temporary breaks any clobber cycle.
function Emitter:edge(target_id,edge,block,block_id,position)
    local target=self.current.blocks[target_id]
    local statements=L()
    local temporaries=L()
    local live={}
    for i,ref in ipairs(edge.arguments) do
        if self:needed_parameter(target_id,i) then
            local name=self:value(block_id,position,'e' .. i)
            live[#live+1]=i
            temporaries:insert(C.Declare(self:ctype(target.parameters[i].type),name,self:ref(block,block_id,position,ref)))
        end
    end
    statements:insertall(temporaries)
    for _,i in ipairs(live) do
        statements:insert(C.Assign(C.Name(self:param(target_id,i-1)),C.Name(self:value(block_id,position,'e' .. i))))
    end
    statements:insert(C.Goto('b' .. target_id))
    return C.Block(statements)
end

function Emitter:exit(target_id,block,block_id,exit)
    local position=#block.parameters+#block.instructions
    if B.Return:isclassof(exit) then
        local types=self.functions[target_id].signature.results
        local given=self:arglist(block,block_id,position,exit.values)
        local values=L()
        for i,type_ in ipairs(types) do if type_~=B.Effect then values:insert(given[i]) end end
        local type_=self:return_shape(types)
        return C.Return(self:return_value(type_,values))
    elseif B.Jump:isclassof(exit) then
        return self:edge(exit.edge.target,exit.edge,block,block_id,position)
    elseif B.Branch:isclassof(exit) then
        local taken=self.decision[block_id]
        if taken then return self:edge(taken.target,taken,block,block_id,position) end
        local condition=self:ref(block,block_id,position,exit.condition)
        return C.If(condition,self:edge(exit.yes.target,exit.yes,block,block_id,position),self:edge(exit.no.target,exit.no,block,block_id,position))
    elseif B.TailCall:isclassof(exit) then
        local arguments=self:arglist(block,block_id,position,exit.arguments)
        if exit.target==target_id then
            -- A self tail transfer reuses this activation: assign the entry packet and
            -- jump back to the entry block instead of growing a continuation chain.
            local entry=self.current.blocks[1]
            local statements,live=L(),{}
            -- A tail call's arguments exclude the effect, so argument i lands on belt
            -- parameter i+1 (1-based for the packet, 0-based for the C name).
            for i,argument in ipairs(exit.arguments) do
                if self:needed_parameter(1,i+1) then
                    local name=self:value(block_id,position,'t' .. i)
                    live[#live+1]=i
                    statements:insert(C.Declare(self:ctype(entry.parameters[i+1].type),name,self:ref(block,block_id,position,argument)))
                end
            end
            for _,i in ipairs(live) do statements:insert(C.Assign(C.Name(self:param(1,i)),C.Name(self:value(block_id,position,'t' .. i)))) end
            statements:insert(C.Goto('b1'))
            return C.Block(statements)
        end
        return C.Return(C.Call(C.Name(self:function_name(exit.target)),arguments))
    elseif B.Trap:isclassof(exit) then
        self.trap=true
        local statements=L()
        statements:insert(C.Evaluate(C.Call(C.Name('let_trap'),L{C.String(exit.reason)})))
        local type_=self:return_shape(self.functions[target_id].signature.results)
        statements:insert(C.Return(type_==C.Void and nil or C.Integer(0,0)))
        return C.Block(statements)
    end
    self:error('no representation for ' .. tostring(exit))
end

-- C names come from the belt: the module initializer and each word entry by its source
-- name, so a reader can tell what a function is without a legend.
local function sanitize(name)
    name=name:gsub('[^%w_]','_')
    if name:match('^%d') then name='w' .. name end
    return name
end

function Emitter:function_name(id)
    local name=self.program.functions[id] and self.program.functions[id].name
    if name=='__module_init' then return 'let_module_init' end
    return 'let_' .. sanitize(name or ('fn_' .. id))
end

function Emitter:live_functions()
    local live,work={[1]=true},{1}
    while #work>0 do
        local id=table.remove(work)
        local belt=self.program.functions[id]
        local analysis=self.analysis[id]
        for block_id in pairs(analysis.live_blocks) do
            local block=belt.blocks[block_id]
            local position=#block.parameters+#block.instructions
            for index,instruction in ipairs(block.instructions) do
                local at=#block.parameters+index-1
                local operation=instruction.operation
                if B.CallFunction:isclassof(operation)
                    and not self:folded_call(id,block_id,at,instruction) and not live[operation.target] then
                    live[operation.target]=true; work[#work+1]=operation.target
                end
            end
            if B.TailCall:isclassof(block.exit) and not live[block.exit.target] then
                live[block.exit.target]=true; work[#work+1]=block.exit.target
            end
        end
    end
    return live
end


-- The C parameter list mirrors the entry block's packet, so prototypes and
-- definitions agree on every argument type.
function Emitter:function_parameters(belt)
    local parameters=L()
    for i,parameter in ipairs(belt.blocks[1].parameters) do
        if parameter.type~=B.Effect then
            parameters:insert(C.Parameter(self:ctype(parameter.type),self:param(1,i-1)))
        end
    end
    return parameters
end

function Emitter:emit_function(id,belt)
    local analysis=self.analysis[id]
    self.current=belt
    self.current_id=id
    self.live=analysis.live_blocks
    self.decision=analysis.decision
    -- Consumer demand is a frontend decision: an unneeded pure producer is never
    -- written out, so the emitted C does not rely on a C compiler to delete it.
    -- Ordered operations always carry a demanded effect output and are therefore kept.
    self.needed=belt:demands()
    local result=self:return_shape(belt.signature.results)
    local parameters=self:function_parameters(belt)
    local body=L()
    -- Non-entry block parameters are assigned only by edges, so they are declared once.
    -- The entry block's packet is the function's ABI and is never pruned.
    for block_id=2,#belt.blocks do
        for i,parameter in ipairs(belt.blocks[block_id].parameters) do
            if self:needed_parameter(block_id,i) then
                body:insert(C.Declare(self:ctype(parameter.type),self:param(block_id,i-1),nil))
            end
        end
    end
    body:insert(C.Goto('b1'))
    for block_id,block in ipairs(belt.blocks) do
        if not self.live[block_id] then goto continue_block end
        body:insert(C.Label('b' .. block_id))
        for index,instruction in ipairs(block.instructions) do
            local position=#block.parameters+index-1
            local needed=self.needed[block_id] and self.needed[block_id][position]
            local pure=true
            for _,type_ in ipairs(instruction.results) do if type_==B.Effect then pure=false end end
            if needed or not pure then body:insertall(self:instruction(block,block_id,index,instruction)) end
        end
        body:insert(self:exit(id,block,block_id,block.exit))
        ::continue_block::
    end
    local external=id==1
    return C.Function(self:function_name(id),external,external,result,parameters,C.Block(body))
end

-- Resources and hosts are foreign code: the emitter declares the symbols it calls, and
-- the embedding supplies the implementations.
function Emitter:host_declarations()
    local declarations=L()
    local names={}
    for _,descriptor in pairs(self.options.resources or {}) do
        if not names[descriptor.destroy] then
            names[descriptor.destroy]=true
            declarations:insert(C.Function(descriptor.destroy,true,false,C.Void,L{C.Parameter(C.I64,'a0')},nil))
        end
    end
    for _,host in pairs(self.hosts or {}) do if not names[host.symbol] then
        names[host.symbol]=true
        local parameters=L()
        for i,parameter in ipairs(host.signature.parameters) do
            local type_=parameter.capability==A.Mut and C.Pointer(self:ctype(parameter.type)) or self:ctype(parameter.type)
            parameters:insert(C.Parameter(type_,'a' .. i))
        end
        local result=host.signature.results[1]
        declarations:insert(C.Function(host.symbol,true,false,result==B.Unit and C.Void or self:ctype(result),parameters,nil))
    end end
    return declarations
end

function Emitter:helper_declarations()
    local declarations=L()
    if self.text or self.helpers.text_eq then declarations:insert(C.Struct('let_text',L{C.Parameter(C.Pointer(C.Named('char')),'data'),C.Parameter(C.U64,'size')})) end
    declarations:insert(C.Function('let_trap',true,false,C.Void,L{C.Parameter(C.Pointer(C.Named('char')),'reason')},nil))
    local function raw(code) declarations:insert(C.Raw(code)) end
    -- Signed overflow is undefined in C, so wrapping arithmetic must go through unsigned.
    -- These are one-line and branch-free, so a macro inlines them without adding a function.
    if self.helpers.add then raw('#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))') end
    if self.helpers.sub then raw('#define LET_SUB(a,b) ((int64_t)((uint64_t)(a)-(uint64_t)(b)))') end
    if self.helpers.mul then raw('#define LET_MUL(a,b) ((int64_t)((uint64_t)(a)*(uint64_t)(b)))') end
    if self.helpers.neg then raw('#define LET_NEG(a) ((int64_t)(0-(uint64_t)(a)))') end
    -- Division and remainder keep one shared helper each: inlining the trap check at every
    -- site would duplicate control flow rather than remove a function.
    if self.helpers.div then raw('static int64_t let_div(int64_t a,int64_t b){if(b==0)let_trap("division by zero");if(b==-1)return (int64_t)(0-(uint64_t)a);return a/b;}') end
    if self.helpers.rem then raw('static int64_t let_rem(int64_t a,int64_t b){if(b==0)let_trap("remainder by zero");if(b==-1)return 0;return a%b;}') end
    if self.helpers.text_eq then raw('#define LET_TEXT_EQ(a,b) ((a).size==(b).size&&memcmp((a).data,(b).data,(size_t)(a).size)==0)') end
    return declarations
end

function Emitter:program(program,options)
    self.program=program
    self.functions=program.functions
    self.hosts={}
    for _,host in pairs(options.hosts or {}) do self.hosts[host.symbol]=host end
    -- One shared run so call summaries are computed once and reused across callers.
    local run=Known.run(program,options)
    self.analysis={}
    for id in ipairs(program.functions) do self.analysis[id]=Known.analyze(program,id,{run=run}) end
    self.live_functions=self:live_functions()
    -- Emitting functions registers the structs and helper requirements they need.
    local functions=L()
    for id,belt in ipairs(program.functions) do
        if self.live_functions[id] then functions:insert(self:emit_function(id,belt)) end
    end
    local host_declarations=self:host_declarations()
    local helpers=self:helper_declarations()
    local includes=L{'stdint.h','stdbool.h'}
    if self.text and self.helpers.text_eq then includes:insert('string.h') end
    local declarations=L()
    declarations:insertall(helpers)
    for _,struct in ipairs(self.structs) do declarations:insert(struct) end
    for _,struct in ipairs(self.results) do declarations:insert(struct) end
    declarations:insertall(host_declarations)
    for id,belt in ipairs(program.functions) do
        if self.live_functions[id] then
            declarations:insert(C.Function(self:function_name(id),id==1,id==1,self:return_shape(belt.signature.results),self:function_parameters(belt),nil))
        end
    end
    declarations:insertall(functions)
    return C.Unit(includes,declarations)
end

function B.Program:emit(options)
    options=options or {}
    local emitter=Emitter.new(options)
    return emitter:program(self,options)
end
end
