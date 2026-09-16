-- AST -> immutable belt blocks. Draft blocks, names, SSA versions, pins and ownership
-- facts are construction-context state, never annotations on source or belt nodes.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local Packet=V.Packet
local Vocabulary=V.Vocabulary
local literal=require('let.literal')
local unpack=table.unpack or unpack
local Context={}; Context.__index=Context
local function copy(t) local out={}; for k,v in pairs(t) do out[k]=v end; return out end
local function fail(span,message) error(('%s:%d:%d: %s'):format(span.file,span.line,span.column,message),0) end
local function gap(span,message) fail(span,'construction not yet implemented: ' .. message) end
-- A *refusal* is the language saying no; a *gap* is the compiler saying "not yet". They are kept
-- apart because a reader has to know which one they are looking at: one means rewrite the program,
-- the other means the compiler is missing something. Sharing a word is why `program.lua`'s
-- "That is an ownership error, not a missing lowering" sat directly above a call whose message
-- began "construction not yet implemented".
local function refuse(span,message) fail(span,message) end
local function expect(value,type_,span)
    if not value.type then refuse(span,'word values in data positions') end
    if not value.type:same(type_) then fail(span,'expected ' .. tostring(type_) .. ', got ' .. tostring(value.type)) end
end
function Context:value(type_)
    self.fn.next_value=self.fn.next_value+1; return {id=self.fn.next_value,type=type_}
end
function Context:parameter(type_,capability)
    local value=self:value(type_); local position=#self.block.parameters
    self.block.parameters:insert(B.Parameter(type_,capability or A.Read))
    self.locations[value.id]={position=position,output=0}; return value
end
function Context:ref(value)
    local location=assert(self.locations[value.id],'producer was not carried across a control boundary')
    return B.Ref(#self.block.parameters+#self.block.instructions-1-location.position,location.output)
end
function Context:refs(values) local out=L(); for _,v in ipairs(values) do out:insert(self:ref(v)) end; return out end
function Context:emit(operation,types,span)
    assert(not self.block.exit,'emission after block exit')
    local position=#self.block.parameters+#self.block.instructions
    self.block.instructions:insert(B.Instruction(operation,types,span)); local values={}
    for i,type_ in ipairs(types) do
        local v=self:value(type_); self.locations[v.id]={position=position,output=i-1}; values[i]=v
    end
    return unpack(values)
end
function Context:ordered(operation,type_,span)
    if type_ then local value,effect=self:emit(operation,L{type_,B.Effect},span); self.effect=effect; return value end
    self.effect=self:emit(operation,L{B.Effect},span)
end
function Context:boolean(value,span) return self:emit(B.BooleanLiteral(value),L{B.Bool},span) end
function Context:pin(value) self.pins[#self.pins+1]=value; return value end
function Context:pin_moved(moved)
    local count=0
    if moved then for _,state in pairs(moved) do if state~=true then self:pin(state); count=count+1 end end end
    return count
end
function Context:unpin_moved(count) for _=1,count do self:unpin() end end
function Context:unpin() self.pins[#self.pins]=nil end
function Context:push() self.scopes[#self.scopes+1]={names={},ids={}} end
-- A retained scope keeps its initialized state under the caller's ownership: it is
-- neither destroyed nor invalidated when the region exits. Field scopes owned by a
-- word value and invocation-saturation scopes are retained.
function Context:retain() local scope=self.scopes[#self.scopes]; assert(scope); scope.retained=true end
function Context:find(name)
    for i=#self.scopes,1,-1 do local id=self.scopes[i].names[name]; if id then return id end end
end
function Context:binding(name,span)
    local id=self:find(name); if not id then fail(span,'unknown name ' .. name) end
    return id,self.fn.bindings[id],self.cells[id]
end
function Context:access(id,writing,span)
    local lock=self.locks[id]
    if lock and (lock.write or (writing and lock.read>0)) then fail(span,'conflicting borrow of ' .. self.fn.bindings[id].name) end
end
-- §12.4: a view of a Let value borrows it, and the borrow lasts as long as the scope that made
-- the view -- which is the binding that holds it in every ordinary case. Moving or writing the
-- owner while the view is live is then a conflicting borrow. Two things are deliberately not
-- claimed: a view of a literal or a temporary views storage Let never owned, and a foreign side
-- that invalidates the bytes is beyond any check.
function Context:hold_view(value,source,span)
    local id=source.origin
    if not id then
        -- A non-Copy temporary is destroyed at the end of the statement, so a view of it could
        -- never be used. That is worth naming rather than leaving to the foreign side.
        if not source.type:copyable() then
            fail(span,'a view of a temporary cannot outlive it; bind the value first')
        end
        return value
    end
    self:access(id,false,span)
    local lock=self.locks[id] or {read=0}
    self.locks[id]=lock; lock.read=lock.read+1
    local scope=self.scopes[#self.scopes]
    local held=scope.views
    if not held then held={}; scope.views=held end
    held[#held+1]=id
    -- The view borrows the same value, so a view of a view is held against the original owner.
    value.origin=id
    return value
end
function Context:read(name,span)
    local id,binding,cell=self:binding(name,span)
    if not cell.initialized then fail(span,'use after move or uninitialized binding ' .. name) end
    -- §9.2: a whole-place read crosses every subplace, so any moved subplace forbids it.
    if next(cell.moved) then fail(span,'use of a partially initialized aggregate ' .. name) end
    return self:read_place(id,name,binding,cell,span)
end

-- Reads a place's contents without deciding whether reading the whole place is legal,
-- because a projection decides that from the path it names.
function Context:read_place(id,name,binding,cell,span)
    if not cell.initialized then fail(span,'use after move or uninitialized binding ' .. name) end
    self:access(id,false,span)
    local value=cell.value
    if binding.address then value=self:ordered(B.Load(self:ref(self.effect),self:ref(value)),binding.type,span) end
    local meaning=copy(value); meaning.origin=id; meaning.mode=binding.type:copyable() and 'copy' or 'borrow'
    return meaning
end

-- Names are found by search and indices are written by the source, so both describe the
-- member position: a path key is the sequence of those positions.
function Context:path_key(type_,steps,span,allow_dynamic)
    local key,indices='',{}
    for _,step in ipairs(steps) do
        local index,leaf=self:member_step(type_,step,span,'a partial move requires an aggregate path')
        if index==nil then
            if allow_dynamic then return nil end
            refuse(step.span,'a partial move needs a statically known path')
        end
        key=(key=='' and tostring(index)) or (key .. '.' .. tostring(index))
        indices[#indices+1]=index
        type_=leaf
    end
    return key,indices,type_
end

-- Two paths conflict when either contains the other: a moved subplace makes every place
-- that contains it, and every place inside it, unusable until a value is assigned.
local function contains(outer,inner)
    if outer==inner or outer=='' then return true end
    return inner:sub(1,#outer+1)==outer..'.'
end
function Context:check_moved(id,key,span)
    local name=self.fn.bindings[id].name
    for was,state in pairs(self.cells[id].moved) do
        if contains(was,key) or contains(key,was) then
            fail(span,state==true and ('use of an uninitialized subplace of ' .. name)
                or ('use of a subplace of ' .. name .. ' that may be uninitialized'))
        end
    end
end
function Context:check_readable(id,key,span,intermediate)
    local name=self.fn.bindings[id].name
    for was,state in pairs(self.cells[id].moved) do
        if was==key or contains(was,key) then
            fail(span,state==true and ('use of an uninitialized subplace of ' .. name)
                or ('use of a subplace of ' .. name .. ' that may be uninitialized'))
        end
        if not intermediate and contains(key,was) then
            fail(span,state==true and ('use of a partially initialized subplace of ' .. name)
                or ('use of a subplace of ' .. name .. ' that may be partially initialized'))
        end
    end
end
-- Assigning a place replaces it whole, so a hole *inside* it is destroyed with it, while a
-- hole that contains it has no value to write into.
function Context:check_writable(id,key,span)
    local name=self.fn.bindings[id].name
    for was,state in pairs(self.cells[id].moved) do
        if was~=key and contains(was,key) then
            fail(span,state==true and ('assignment inside an uninitialized subplace of ' .. name)
                or ('assignment inside a subplace of ' .. name .. ' that may be uninitialized'))
        end
    end
end

function Context:nested_moved(id,key,span)
    for was,state in pairs(self.cells[id].moved) do
        if contains(key,was) then
            fail(span,state==true and 'a runtime index over a partially initialized aggregate'
                or 'a runtime index over an aggregate that may be partially initialized')
        end
    end
end

-- §9.2: moving out of a subplace leaves it uninitialized and the aggregate partially
-- initialized, so only that path becomes unusable.
function Context:take_member(name,steps,span)
    local id,binding,cell=self:binding(name,span)
    if not cell.initialized then fail(span,'use after move or uninitialized binding ' .. name) end
    local key,indices,type_=self:path_key(binding.type,steps,span)
    self:check_moved(id,key,span)
    local value=cell.value
    if binding.address then
        value=self:ordered(B.Load(self:ref(self.effect),self:ref(value)),binding.type,span)
    end
    local at=binding.type
    for _,index in ipairs(indices) do
        -- §11.5: a payload is consumed by matching its tag, so a projection is not a place to
        -- move out of. The tag would keep naming a value that is no longer there.
        -- §11.5: a payload is consumed by moving it out, and the tag keeps naming the value
        -- that is no longer there, so the drop is told through `moved`. Nothing to add here.
        at=at:record()[index+1].type
        value=self:emit(B.LoadField(self:ref(value),index),L{at},span)
    end
    -- §9.2: a Copy member owns no state to remove either, so the path stays initialized.
    if type_:copyable() then
        local read=copy(value); read.mode='copy'; read.origin=id
        return read
    end
    if not binding.owned then fail(span,'cannot move from a borrowed stage') end
    self:access(id,true,span)
    local taken=self:ordered(B.Move(self:ref(self.effect),self:ref(value)),type_,span)
    taken.mode='fresh'; taken.origin=id
    self.cells[id].moved[key]=true
    return taken
end
function Context:resource(type_,span)
    local destroy=B.Named:isclassof(type_) and self.fn.vocabulary:destructor(type_.name)
    if not destroy then refuse(span,'ownership representation for ' .. tostring(type_)) end
    return {destroy=destroy}
end

-- Validate that every resource reachable inside a type has a declared representation.
-- A type that owns no resource needs no destruction story, so this is not a Copy check.
function Context:validate_ownership(type_,span)
    if B.Named:isclassof(type_) then self:resource(type_,span)
    elseif B.Sum:isclassof(type_) then
        -- §11.5: every alternative needs a destruction story, whether or not it is the active
        -- one, because which alternative is live is a run-time fact.
        for _,alternative in ipairs(type_.alternatives) do self:validate_ownership(alternative,span) end
    elseif B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        for _,field in ipairs(type_:record()) do self:validate_ownership(field.type,span) end
    end
end
-- The concrete belt type a type word names. Primitives and registered types come from the
-- vocabulary; a `let`-bound word is a type word too, and denotes the type of its terminal result
-- (§11.2). An unknown name names no type and returns nil.
-- §11.3: lower a declared type word to a belt type. A `Ref` is a vocabulary type or a
-- `let`-bound word; an `Apply` is a type word applied to type words by juxtaposition (`List Int`).
function Context:constraint_type(annotation)
    return self:resolve_type_expr(annotation,{})
end
function Context:resolve_type_expr(node,env)
    if not node then return nil end
    if A.Ref:isclassof(node) then
        if env[node.name] then return env[node.name] end
        local type_=self.fn.vocabulary:resolve_type(node)
        if type_ then return type_ end
        return self:bound_type(node,env)
    end
    -- §11.5: a sum type literal (`Int | Text`) names its alternatives as expressions.
    if A.Name:isclassof(node) then
        if env[node.name] then return env[node.name] end
        return self.fn.vocabulary.types[node.name] or self:bound_type(node,env)
    end
    -- §11.2: a generic type word applied to type words by juxtaposition. The word's stages must
    -- be `Type` parameters; each argument is substituted and the terminal is evaluated as a type.
    if A.Apply:isclassof(node) then
        local args={}; local base=node
        while A.Apply:isclassof(base) do table.insert(args,1,base.argument); base=base.constructor end
        if not A.Ref:isclassof(base) then return nil end
        local definition=self.resolved and self.resolved.type_refs[base]
        local template=definition and definition.template
        if not (template and self.builder) then return nil end
        local layout=self.builder:layout(template)
        if #layout.steps~=#args then return nil end
        local bound={}
        for i,step in ipairs(layout.steps) do
            if self.fn.vocabulary:resolve_type(step.item.constraint)~=B.TypeWord then return nil end
            local argument=self:resolve_type_expr(args[i],env)
            if not argument then return nil end
            bound[step.item.name]=argument
        end
        return self:word_terminal_type(template,bound)
    end
    if A.Arrow:isclassof(node) then
        local from,to=self:resolve_type_expr(node.from,env),self:resolve_type_expr(node.to,env)
        if not (from and to) then return nil end
        return B.Arrow(from,to)
    end
    if A.Do:isclassof(node) then
        local result=self:resolve_type_expr(node.result,env)
        if not result then return nil end
        return B.Do(result)
    end
    if A.Sum:isclassof(node) or A.SumType:isclassof(node) or self:is_union(node) then
        local nodes={}; self:flatten_sum(node,nodes)
        local alternatives,copy=L(),true
        for _,element in ipairs(nodes) do
            local type_=self:resolve_type_expr(element,env)
            if not type_ then return nil end
            alternatives:insert(type_); if not type_:copyable() then copy=false end
        end
        return B.Sum(alternatives,copy)
    end
    if A.Record:isclassof(node) then
        local fields,complete=L(),true
        for _,field in ipairs(node.fields) do
            local type_=self:resolve_type_expr(field.type,env)
            if not type_ then complete=false else fields:insert(B.Field(field.name,type_,field.mutable)) end
        end
        if not complete then return nil end
        local copy=true
        for _,field in ipairs(fields) do if field.mutable or not field.type:copyable() then copy=false end end
        return B.Aggregate(fields,copy,nil)
    end
    if A.Tuple:isclassof(node) then
        local fields,complete=L(),true
        for _,element in ipairs(node.elements) do
            local type_=self:resolve_type_expr(element,env)
            if not type_ then complete=false else fields:insert(B.Field(nil,type_,false)) end
        end
        if not complete then return nil end
        local copy=true
        for _,field in ipairs(fields) do if not field.type:copyable() then copy=false end end
        return B.Aggregate(fields,copy,nil)
    end
    return nil
end
-- §11.5: an `or` whose two operands resolved to type words is a union type literal, not a
-- condition. The resolver records that; everything downstream asks here.
function Context:is_union(node)
    if not (A.Binary:isclassof(node) and node.operator==A.Or) then return false end
    return (self.resolved and self.resolved.unions[node]) and true or false
end
function Context:flatten_sum(node,into)
    if A.Sum:isclassof(node) or A.SumType:isclassof(node) or self:is_union(node) then self:flatten_sum(node.left,into); self:flatten_sum(node.right,into)
    else into[#into+1]=node end
end
-- §11.2: a `let`-bound word as a type denotes its terminal result type.
function Context:bound_type(node,env)
    local definition=self.resolved and self.resolved.type_refs[node]
    local template=definition and definition.template
    local terminal=template and template.source.terminal
    if terminal and A.Data:isclassof(terminal) then
        local value=terminal.value
        if A.Word:isclassof(value) then
            local inner=self.resolved.chains[value.chain]
            if inner then template=inner end
        elseif A.SumType:isclassof(value) or A.Sum:isclassof(value) or self:is_union(value) then
            return self:resolve_type_expr(value,env or {})
        end
    end
    if template and V.Contract then
        return V.Contract.template(template,self.resolved,self.fn.vocabulary.types).result
    end
    return nil
end
-- The type a type word's terminal denotes: a stage aggregate is the record of its stages, with
-- the type parameters substituted.
function Context:word_terminal_type(template,env)
    local terminal=template.source.terminal
    if not (terminal and A.Data:isclassof(terminal) and A.Word:isclassof(terminal.value)) then return nil end
    -- §8.3: the mutability of a member is declared on the member, so it is read from the record the
    -- terminal builds rather than from the stage that supplies it. The stage answers the type, and
    -- the member answers whether it is an interior mutable place.
    local writable={}
    local record=terminal.value.chain.terminal
    if record and A.Data:isclassof(record) and A.NamedAggregate:isclassof(record.value) then
        for _,member in ipairs(record.value.members) do writable[member.name]=member.mutable end
    end
    local fields,copy=L(),true
    for _,item in ipairs(terminal.value.chain.items) do
        if A.Stage:isclassof(item) then
            local type_=self:resolve_type_expr(item.constraint,env)
            if not type_ then return nil end
            local mutable=writable[item.name]==true
            fields:insert(B.Field(item.name,type_,mutable))
            if mutable or not type_:copyable() then copy=false end
        end
    end
    if #fields==0 then return nil end
    return B.Aggregate(fields,copy,nil)
end
function Context:check(annotation,type_,span)
    if not annotation then return type_ end
    local name=A.Ref:isclassof(annotation) and annotation.name or nil
    if name and #annotation.arguments>0 then gap(span,'specialized type words') end
    local declared=self:constraint_type(annotation)
    if not declared then gap(span,'type ' .. (name or 'expression')) end
    -- §11.3: a word-typed stage holds a word. Its declared arrow (or runtime terminal) is the
    -- word's signature; the supplied word's remaining signature must match. The stage keeps its
    -- concrete word type, so invocation still works.
    if B.Arrow:isclassof(declared) or B.Do:isclassof(declared) then
        if not type_ then return nil end
        if not B.Word:isclassof(type_) then fail(span,'a word-typed stage needs a word') end
        local actual=self:word_signature(type_)
        if not (actual and actual:same(declared)) then
            fail(span,'word signature mismatch: expected ' .. tostring(declared) .. ', got ' .. tostring(actual))
        end
        return type_
    end
    if type_ then expect({type=type_},declared,span) end; return declared
end
-- The signature of a word value: its remaining stages as unary arrows, ending in its terminal.
-- This is what a word-typed stage's declaration is checked against (§11.1).
function Context:word_signature(type_)
    local builder=self.builder
    if not builder then return nil end
    local template=builder.resolved.templates[type_.template]
    if not template then return nil end
    local layout=builder:layout(template)
    local tail
    if A.Body:isclassof(template.source.terminal) then tail=B.Do(layout.contract.result or B.Unit)
    else tail=layout.contract.result end
    if not tail then return nil end
    for i=#layout.steps,type_.supplied+1,-1 do
        local item=layout.steps[i].item
        local stage_type=self:constraint_type(item.constraint)
        if not stage_type then return nil end
        tail=B.Arrow(stage_type,tail)
    end
    return tail
end
function Context:bind(name,value,mutable,owned,external,address,span)
    local scope=self.scopes[#self.scopes]
    if scope.names[name] then fail(span,'duplicate binding ' .. name) end
    local id=#self.fn.bindings+1
    local type_=address and value.type.pointee or value.type
    self.fn.bindings[id]={name=name,type=type_,mutable=mutable,owned=owned,external=external,
        address=address,span=span,lifetime=self.lifetime or 'activation'}
    scope.names[name]=id; scope.ids[#scope.ids+1]=id
    self.cells[id]={value=value,initialized=true,alive=owned,moved={}}; return id
end
-- Field/parameter scopes mirror lexical shadowing: a later field of the same name
-- replaces the earlier one in the current region instead of being a duplicate.
function Context:force_bind(name,value,mutable,owned,external,address,span)
    local scope=self.scopes[#self.scopes]
    local existing=scope.names[name]
    -- A rebind must drop the id it replaces, not whichever id happens to be last.
    if existing then
        for i=#scope.ids,1,-1 do
            if scope.ids[i]==existing then table.remove(scope.ids,i) end
        end
    end
    local id=#self.fn.bindings+1
    local type_=address and value.type.pointee or value.type
    self.fn.bindings[id]={name=name,type=type_,mutable=mutable,owned=owned,external=external,address=address,span=span}
    scope.names[name]=id; scope.ids[#scope.ids+1]=id
    self.cells[id]={value=value,initialized=true,alive=owned,moved={}}; return id
end

function Context:take(name,span)
    local id,binding,cell=self:binding(name,span)
    if not cell.initialized then fail(span,'use after move or uninitialized binding ' .. name) end
    if next(cell.moved) then fail(span,'use of a partially initialized aggregate ' .. name) end
    if binding.type:copyable() then return self:read_place(id,name,binding,cell,span) end
    self:access(id,true,span)
    if not binding.owned then fail(span,'cannot move from a borrowed stage') end
    -- Moving out of a place reads its contents first; the cell itself stays.
    local source=cell.value
    if binding.address then
        source=self:ordered(B.Load(self:ref(self.effect),self:ref(source)),binding.type,span)
    end
    local value=self:ordered(B.Move(self:ref(self.effect),self:ref(source)),binding.type,span)
    self.cells[id]={value=cell.value,initialized=false,alive=false,moved={}}
    value.mode='fresh'; value.origin=id; return value
end
function Context:accept_owned(value,span)
    if not value.type then refuse(span,'stored or returned words') end
    if value.mode=='mut' then fail(span,'a mutable borrow cannot be stored or returned') end
    if not value.type:copyable() and value.mode~='fresh' then fail(span,'non-copyable value requires move or a fresh result') end
end
function Context:new_block()
    local block={parameters=L(),instructions=L(),id=#self.fn.blocks+1}
    self.fn.blocks[#self.fn.blocks+1]=block; return block
end

-- One place that establishes a construction context. The order matters: the entry block, the
-- scope holding its parameters, and the effect parameter every ordered operation threads must
-- exist before the first instruction, or a parameter would land next to one and collide with it.
function Context.new_function(spec)
    local fn={name=spec.name,span=spec.span,blocks={},bindings={},next_value=0,
        result=spec.result,state=spec.state,
        vocabulary=spec.vocabulary}
    local ctx=setmetatable({fn=fn,locations={},cells={},scopes={},pins={},locks={},
        builder=spec.builder,resolved=spec.resolved,lifetime=spec.lifetime},Context)
    ctx.block=ctx:new_block(); ctx:push(); ctx.effect=ctx:parameter(B.Effect)
    ctx.function_id=spec.function_id
    return ctx
end
-- The fields that describe the construction rather than the current block. A child carries
-- them unchanged; the state fields -- block, locations, cells, scopes, pins, effect -- are the
-- ones a child creates for itself. Listing the ambient fields is deliberate: a new one must be
-- added here, so forgetting it is a nil error rather than a fact silently shared by every
-- block, which is what the old exclusion list allowed.
local function ambient(frame)
    return {
        fn=frame.fn, locks=frame.locks, builder=frame.builder, resolved=frame.resolved,
        lifetime=frame.lifetime, function_id=frame.function_id,
        self_name=frame.self_name, self_definition=frame.self_definition,
        module_pending=frame.module_pending, module_preludes=frame.module_preludes,
        mutable_state=frame.mutable_state, intermediate=frame.intermediate, finish=frame.finish,
        loops=frame.loops,
    }
end
function Context:clone()
    local child=setmetatable(ambient(self),Context)
    child.block=self:new_block(); child.locations={}; child.cells={}; child.pins={}; child.scopes={}
    child.effect=self.effect
    for i,scope in ipairs(self.scopes) do child.scopes[i]={names=copy(scope.names),ids=copy(scope.ids),retained=scope.retained} end
    return child
end
-- A target interface carries each source binding independently: two aliases can
-- diverge after assignment. Expression pins carry earlier operands across CFG splits.
function Context:interface(endpoints,extras,loop_head)
    local target=self:clone(); local args={}; for i in ipairs(endpoints) do args[i]={} end; local slots={}
    local function parameter(type_,get)
        local value=target:parameter(type_)
        for i,endpoint in ipairs(endpoints) do args[i][#args[i]+1]=get(endpoint) end
        slots[#slots+1]=get
        return value
    end
    target.effect=parameter(B.Effect,function(e) return e.effect end)
    for id=1,#self.fn.bindings do if self.cells[id] then
        local base=self.cells[id]; local initialized=true
        for _,e in ipairs(endpoints) do initialized=initialized and e.cells[id].initialized end
        -- A subplace moved out before the boundary is uninitialized after it. Paths the
        -- endpoints disagree about become dynamic facts, one Bool parameter each: a
        -- destruction can then be guarded, while reading such a path stays impossible.
        local keys={}
        for _,e in ipairs(endpoints) do for key in pairs(e.cells[id].moved) do keys[key]=true end end
        local moved={}
        for key in pairs(keys) do
            local constant=endpoints[1].cells[id].moved[key]==true and not loop_head
            for _,e in ipairs(endpoints) do constant=constant and e.cells[id].moved[key]==true end
            if constant then moved[key]=true
            else
                moved[key]=parameter(B.Bool,function(e)
                    local state=e.cells[id].moved[key]
                    if state==nil then return e:boolean(false,self.fn.bindings[id].span) end
                    if state==true then return e:boolean(true,self.fn.bindings[id].span) end
                    return state
                end)
            end
        end
        local value=parameter(base.value.type,function(e) return e.cells[id].value end)
        local alive=false
        if self.fn.bindings[id].owned then
            alive=endpoints[1].cells[id].alive
            local constant=type(alive)=='boolean' and not loop_head
            for _,e in ipairs(endpoints) do constant=constant and e.cells[id].alive==alive end
            if not constant then
                alive=parameter(B.Bool,function(e) local a=e.cells[id].alive; return type(a)=='boolean' and e:boolean(a,self.fn.bindings[id].span) or a end)
            end
        end
        target.cells[id]={value=value,initialized=initialized,alive=alive,moved=moved}
    end end
    for i,pin in ipairs(self.pins) do
        local value=parameter(pin.type,function(e) return e.pins[i] end)
        target.locations[pin.id]=target.locations[value.id]; target.pins[i]=pin
    end
    local outputs={}
    for i,type_ in ipairs(extras or {}) do outputs[i]=parameter(type_,function(e) return e.extra[i] end) end
    target.packet_slots=slots
    return target,args,outputs
end

-- The values a block hands to an interface it already declared: the same slots `interface`
-- recorded, asked of this endpoint. A branch and a loop backedge therefore use one order, and
-- cannot disagree about which fact is which parameter.
function Context:pack(endpoint)
    local values=L()
    for _,slot in ipairs(self.packet_slots) do values:insert(slot(endpoint)) end
    return values
end
function Context:edge(target,values) return B.Edge(target.block.id,self:refs(values)) end
function Context:adopt(other)
    self.block,self.locations,self.cells,self.scopes,self.pins,self.effect=other.block,other.locations,other.cells,other.scopes,other.pins,other.effect
end
function Context:branch(condition,yes_fn,no_fn,result_type)
    expect(condition,B.Bool,self.fn.span)
    local yes,ya=self:interface({self}); local no,na=self:interface({self})
    -- Freeze references only after interface creation: it can append flag literals.
    self.block.exit=B.Branch(self:ref(condition),self:edge(yes,ya[1]),self:edge(no,na[1]))
    yes:push(); yes.extra={yes_fn(yes)}; if not yes.block.exit then yes:pop() end
    no:push(); no.extra={no_fn(no)}; if not no.block.exit then no:pop() end
    local live={}; if not yes.block.exit then live[#live+1]=yes end; if not no.block.exit then live[#live+1]=no end
    if #live==0 then return end
    local join,args,values=self:interface(live,result_type and {result_type} or nil)
    for i,e in ipairs(live) do e.block.exit=B.Jump(e:edge(join,args[i])) end
    self:adopt(join); return values[1]
end

function Context:destroy(value,span,moved,prefix)
    local type_=value.type
    if B.Address:isclassof(type_) then
        -- Destroying a place destroys what it contains. A module's owned state lives in
        -- places so that a captured word can borrow it (§10.1).
        self:destroy(self:ordered(B.Load(self:ref(self.effect),self:ref(value)),type_.pointee,span),span,moved,prefix)
    elseif B.Named:isclassof(type_) then
        self:ordered(B.Destroy(self:ref(self.effect),self:ref(value),self:resource(type_,span).destroy),nil,span)
    elseif B.Sum:isclassof(type_) then
        -- §11.5: only the active alternative holds a value, and the tag says which one it is, so
        -- the drop dispatches on the tag. An inactive alternative is never read.
        if type_:owns() then
            self:pin(value)
            local tag=self:emit(B.LoadField(self:ref(value),0),L{B.Int},span)
            self:pin(tag)
            local alternatives=type_.alternatives
            local function choose(c,at)
                if at>#alternatives then return end
                local alternative=alternatives[at]
                local key=(prefix and prefix~='') and (prefix .. '.' .. at) or tostring(at)
                local state=moved and moved[key]
                if not alternative:owns() or state==true then return choose(c,at+1) end
                local function release(target)
                    local function drop(inner)
                        inner:destroy(inner:emit(B.LoadField(inner:ref(value),at),L{alternative},span),span,moved,key)
                    end
                    if state==nil then drop(target)
                    else
                        -- A dynamic hole: release the payload only where it still holds a value.
                        target:pin(state)
                        target:branch(state,function() end,drop)
                        target:unpin()
                    end
                end
                local matches=c:emit(B.IntegerLiteral(tostring(at-1)),L{B.Int},span)
                local test=c:emit(B.Binary(A.Equal,c:ref(tag),c:ref(matches)),L{B.Bool},span)
                return c:branch(test,release,function(n) return choose(n,at+1) end)
            end
            choose(self,1)
            self:unpin()
            self:unpin()
        end
    elseif B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        for index=#type_:record(),1,-1 do
            local field=type_:record()[index]
            local key=(prefix and prefix~='') and (prefix .. '.' .. (index-1)) or tostring(index-1)
            local state=moved and moved[key]
            if field.type:owns() and state~=true then
                local function release(target)
                    target:destroy(target:emit(B.LoadField(target:ref(value),index-1),L{field.type},span),span,moved,key)
                end
                if state==nil then release(self)
                else
                    -- A dynamic hole: release the member only where it still holds a value.
                    self:pin(value); self:pin(state)
                    self:branch(state,function(c) end,release)
                    self:unpin(); self:unpin()
                end
            end
        end
    else
        refuse(span,'destruction of ' .. tostring(type_))
    end
end
function Context:release(id)
    local binding,cell=self.fn.bindings[id],self.cells[id]
    if not binding.owned or cell.alive==false then return end
    self:access(id,true,binding.span)
    self.cells[id]={value=cell.value,initialized=false,alive=false,moved={}}
    if cell.alive==true then
        -- For a place, the owned value is the cell's contents, not the address.
        local contents=cell.value
        if binding.address then
            contents=self:ordered(B.Load(self:ref(self.effect),self:ref(contents)),binding.type,binding.span)
        end
        self:destroy(contents,binding.span,cell.moved,'')
    elseif binding.address then
        gap(binding.span,'conditional destruction of an address-taken binding')
    else
        -- Pin the old value: conditional destruction introduces new block parameters.
        self:pin(cell.value); local crossed=self:pin_moved(cell.moved)
        self:branch(cell.alive,
            function(ctx) ctx:destroy(cell.value,binding.span,cell.moved,'') end,function() end)
        self:unpin_moved(crossed); self:unpin()
    end
end
-- A view's hold ends with the scope that made it, so both scope exits release it: `pop`, which
-- closes one scope, and `cleanup`, which closes the whole activation before a return or a tail
-- call. Clearing the list makes the release idempotent, because a cleanup can be followed by the
-- pops that would otherwise release the same hold twice.
function Context:release_views(scope)
    local held=scope.views
    if not held then return end
    scope.views=nil
    for _,id in ipairs(held) do
        local lock=self.locks[id]
        if lock then lock.read=lock.read-1 end
    end
end
function Context:pop()
    local scope=self.scopes[#self.scopes]
    if scope.retained then
        for i=#scope.ids,1,-1 do self.cells[scope.ids[i]]=nil end
    else
        -- A view's hold ends before the cells it holds are released.
        self:release_views(scope)
        for i=#scope.ids,1,-1 do self:release(scope.ids[i]); self.cells[scope.ids[i]]=nil end
    end
    self.scopes[#self.scopes]=nil
end
function Context:cleanup()
    for i=#self.scopes,1,-1 do
        if not self.scopes[i].retained then
            self:release_views(self.scopes[i])
            local ids=self.scopes[i].ids; for j=#ids,1,-1 do self:release(ids[j]) end
        end
    end
end
-- `break` and `continue` reach their loop through the frame, like the locks and the resolved
-- module do: a child sees the loops its enclosing regions published. Entering a loop prepends
-- its target so the nearest enclosing loop wins, copying the list so a sibling is unaffected.
function Context:loop(target)
    local outer=self.loops; local loops={target}
    if outer then for i=1,#outer do loops[#loops+1]=outer[i] end end
    self.loops=loops
end
-- Leaving a loop body for `break` or `continue` destroys the locals its iteration created,
-- exactly as reaching the end of the body would; scopes outside the loop are untouched.
function Context:unwind(depth)
    while #self.scopes>=depth do self:pop() end
end
-- A module initializer returns the namespace plus the state that owns it (§15.1).
function Context:finish_pair(namespace,state,span)
    self.fn.result=namespace.type; self.fn.state=state.type
    self:pin(namespace); self:pin(state); self:cleanup()
    self.block.exit=B.Return(L{self:ref(namespace),self:ref(state),self:ref(self.effect)}); self:unpin(); self:unpin()
end

function Context:finish(value,span)
    if value.type:borrows() then
        fail(span,'a word that borrows activation state cannot be returned from the invocation that owns it')
    end
    -- A module initializer written as a do body returns its namespace from wherever the
    -- body returns, and every such return must also hand the host the state (§15.1).
    if self.fn.module_pending then return self.fn.module_pending(self,value,span) end
    self:accept_owned(value,span)
    if self.fn.result then expect(value,self.fn.result,span) else self.fn.result=value.type end
    self:pin(value); self:cleanup(); self.block.exit=B.Return(L{self:ref(value),self:ref(self.effect)}); self:unpin()
end
function Context:statements(statements)
    for _,statement in ipairs(statements) do
        if self.block.exit then gap(statement.span,'unreachable statements') end
        statement:build(self)
    end
end

-- The immutable blocks of the function under construction. One place turns a construction
-- context into the belt, so no driver can collect blocks in a different order or skip an exit.
function Context:blocks(message)
    local blocks=L()
    for _,block in ipairs(self.fn.blocks) do
        assert(block.exit,message or 'unfinished block')
        blocks:insert(B.Block(block.parameters,block.instructions,block.exit))
    end
    return blocks
end

-- Run a terminal body and build its function. `extra` are result types after the returned
-- value and before the final effect; a program entry passes the mutable fields it hands
-- back. Every engine that builds a terminal body goes through here.
function Context:finish_function(body,extra)
    self:push()
    self:statements(body)
    if not self.block.exit then self:finish(self:emit(B.UnitLiteral,L{B.Unit},self.fn.span),self.fn.span) end
    local results=L{self.fn.result}
    for _,type_ in ipairs(extra or {}) do results:insert(type_) end
    results:insert(B.Effect)
    local blocks=self:blocks()
    return B.Function(self.fn.name,B.Signature(blocks[1].parameters,results),blocks)
end
function A.Expr:build(ctx)
    if A.SumType:isclassof(self) then return A.Sum.build(self,ctx) end
    gap(self.span,'this expression form')
end
function A.Expr:tail(ctx) ctx:finish(self:build(ctx),self.span) end
function A.Stmt:build() gap(self.span,'this statement form') end
function A.Name:build(ctx)
    if ctx:find(self.name) then return ctx:word_value(ctx:read(self.name,self.span),self.span,true) end
    -- The defining runtime word is visible only inside its own terminal body (§4.2).
    if ctx.self_name==self.name and ctx.builder then return ctx.builder:self_value(ctx,ctx.self_definition) end
    if ctx.resolved and ctx.resolved.import_words[self] then return {construction='import'} end
    if self.name==ctx.fn.name then gap(self.span,'source-word invocation and recursion') end
    local host=ctx.fn.vocabulary:host(self.name); if host then return {host=host} end
    -- The core numeric conversions are ordinary names (§13.3), so a binding or host above
    -- shadows them like any other dictionary entry.
    if self.name=='float' or self.name=='int' or self.name=='u8' or self.name=='u32' or self.name=='f32' then return {conversion=self.name} end
    if ctx.fn.vocabulary:type(self.name) then fail(self.span,'constraint word is not a runtime value') end
    fail(self.span,'unknown name ' .. self.name)
end
function A.Integer:build(ctx)
    local spelling=literal.integer(self.spelling,false,function(m) fail(self.span,m) end)
    return ctx:emit(B.IntegerLiteral(spelling),L{B.Int},self.span)
end
function A.Float:build(ctx) return ctx:emit(B.FloatLiteral(self.spelling),L{B.Float},self.span) end
function A.Boolean:build(ctx) return ctx:boolean(self.value,self.span) end
function A.Unit:build(ctx) return ctx:emit(B.UnitLiteral,L{B.Unit},self.span) end
-- §11.5: a sum type word. Its value is a compile-time handle carrying the sum type; a module
-- may carry it in state, and annotations and injections read the handle.
function A.Sum:build(ctx)
    local sum=ctx:resolve_type_expr(self,{})
    if not sum then refuse(self.span,'a sum type needs type words') end
    local value=ctx:emit(B.Construct(L(),false),L{B.TypeWord},self.span)
    value.sum=sum
    value.mode='fresh'
    return value
end
-- §11.5: the same sum type in expression position (`let Opt = Int | Text`).
function A.SumType:build(ctx) return A.Sum.build(self,ctx) end
function A.Text:build(ctx) return ctx:emit(B.TextLiteral(self.value),L{B.Text},self.span) end
function A.Unary:build(ctx)
    if self.operator==A.Negate and A.Integer:isclassof(self.operand) then
        local spelling=literal.integer(self.operand.spelling,true,function(m) fail(self.span,m) end)
        return ctx:emit(B.IntegerLiteral(spelling),L{B.Int},self.span)
    end
    local value=self.operand:build(ctx)
    local type_
    if self.operator==A.Not then type_=B.Bool
    elseif self.operator==A.BitNot then type_=(value.type==B.U8 or value.type==B.U32) and value.type or B.Int
    else type_=(value.type==B.Float or value.type==B.Float32) and value.type or B.Int end
    expect(value,type_,self.span)
    return ctx:emit(B.Unary(self.operator,ctx:ref(value)),L{type_},self.span)
end
function A.BinaryOp:apply(ctx,left,right,span)
    if left.type==B.Float or left.type==B.Float32 then expect(right,left.type,span)
    elseif left.type==B.U8 or left.type==B.U32 then expect(right,left.type,span)
    else expect(left,B.Int,span); expect(right,B.Int,span) end
    return ctx:emit(B.Binary(self,ctx:ref(left),ctx:ref(right)),L{left.type},span)
end
local function comparison(self,ctx,left,right,span)
    if left.type==B.Float or left.type==B.Float32 then expect(right,left.type,span)
    elseif left.type==B.U8 or left.type==B.U32 then expect(right,left.type,span)
    else expect(left,B.Int,span); expect(right,B.Int,span) end
    return ctx:emit(B.Binary(self,ctx:ref(left),ctx:ref(right)),L{B.Bool},span)
end
A.Less.apply=comparison; A.LessEqual.apply=comparison; A.Greater.apply=comparison; A.GreaterEqual.apply=comparison
local function equality(self,ctx,left,right,span)
    expect(right,left.type,span)
    if not left.type:copyable() then fail(span,'equality requires explicit vocabulary for this type') end
    return ctx:emit(B.Binary(self,ctx:ref(left),ctx:ref(right)),L{B.Bool},span)
end
A.Equal.apply=equality; A.NotEqual.apply=equality
local function checked(self,ctx,left,right,span)
    if self==A.Divide and (left.type==B.Float or left.type==B.Float32) then
        expect(right,left.type,span)
        return ctx:emit(B.Binary(self,ctx:ref(left),ctx:ref(right)),L{left.type},span)
    end
    local type_=(left.type==B.U8 or left.type==B.U32) and left.type or B.Int
    expect(left,type_,span); expect(right,type_,span)
    return ctx:ordered(B.CheckedBinary(self,ctx:ref(ctx.effect),ctx:ref(left),ctx:ref(right)),type_,span)
end
A.Divide.apply=checked; A.Remainder.apply=checked
-- `& | ^ << >>` take two Ints and produce an Int. They are pure: no operand and no shift count
-- can trap, because a count is reduced modulo the width and `<<` keeps the low bits (§13.3).
local function bitwise(self,ctx,left,right,span)
    local type_=(left.type==B.U8 or left.type==B.U32) and left.type or B.Int
    expect(left,type_,span); expect(right,type_,span)
    return ctx:emit(B.Binary(self,ctx:ref(left),ctx:ref(right)),L{type_},span)
end
A.BitAnd.apply=bitwise; A.BitOr.apply=bitwise; A.BitXor.apply=bitwise
A.ShiftLeft.apply=bitwise; A.ShiftRight.apply=bitwise
function A.BinaryOp:build(ctx,expression)
    local left=expression.left:build(ctx)
    if not left.type then gap(expression.left.span,'word values in data positions') end
    ctx:pin(left); local right=expression.right:build(ctx)
    ctx:unpin(); return self:apply(ctx,left,right,expression.span)
end
local function short(self,ctx,expression)
    -- §3.1: a literal on the left already decides the outcome, so the operator is not a branch at
    -- all and the right-hand side is not evaluated -- which is exactly what short-circuiting is.
    local deciding=self==A.And and false or true
    if A.Boolean:isclassof(expression.left) then
        local left=expression.left:build(ctx); expect(left,B.Bool,expression.span)
        if expression.left.value==deciding then return left end
        local right=expression.right:build(ctx); expect(right,B.Bool,expression.span); return right
    end
    local left=expression.left:build(ctx); expect(left,B.Bool,expression.span)
    local function rhs(child) local right=expression.right:build(child); expect(right,B.Bool,expression.span); return right end
    local function skip(child) return child:boolean(self==A.Or,expression.span) end
    return ctx:branch(left,self==A.And and rhs or skip,self==A.And and skip or rhs,B.Bool)
end
A.And.build=short
-- §11.5: `or` between type words is the tagged union; between values it is the logical or.
function A.Or.build(self,ctx,expression)
    if ctx:is_union(expression) then return A.Sum.build(expression,ctx) end
    return short(self,ctx,expression)
end
function A.Binary:build(ctx) return self.operator:build(ctx,self) end
function A.Specialize:build(ctx)
    -- §11.5: `T.left v` injects `v` into the sum type `T`. The member `T.left` builds an
    -- injection handle, not a runtime word.
    local word=self.word:build(ctx)
    if word and word.injection then
        local payload=self.argument:build(ctx)
        if not payload.type then refuse(self.argument.span,'a word value in a sum injection') end
        return ctx:sum_inject(word.injection.sum,word.injection.index,payload,self.span,self.argument.span)
    end
    local builder=ctx.builder
    if not builder then gap(self.span,'word specialization requires a program builder') end
    return builder:specialize(ctx,self)
end
-- §11.5: a sum value is a tagged record; injection fills the tag and the active field, and
-- zero-fills the inactive ones.
function Context:sum_inject(sum,index,payload,span,payload_span)
    local fields=sum:record()
    local alternative=fields[index+2].type
    expect(payload,alternative,payload_span or span)
    -- §11.5: only the tag and the active alternative are written; C leaves the other
    -- alternatives alone, so an alternative no longer has to be Copy (zero-fillable).
    if alternative:owns() then
        if payload.mode=='borrow' then
            fail(payload_span or span,'a non-Copy sum alternative takes an owned value; move it in')
        end
        -- While a module terminal is being built, owned state may only be *moved in* from a
        -- top-level prelude (§15.1), exactly as for an aggregate member.
        if self.module_preludes and not (payload.origin and self.module_preludes[payload.origin]) then
            fail(span,'a module terminal may not construct new owned state; move an owned prelude into it')
        end
    end
    local value=self:emit(B.InjectSum(index,self:ref(payload)),L{sum},span)
    value.mode='fresh'
    return value
end
local place_path
function A.Move:build(ctx)
    if A.Name:isclassof(self.place) then return ctx:take(self.place.name,self.span) end
    -- §9.2: `move place` may name a subplace. The path must be statically known.
    local root,steps,reason=place_path(self.place)
    if not root then gap(self.span,reason or 'this move place') end
    if not ctx:find(root) then refuse(self.span,'moving out of ' .. tostring(root)) end
    return ctx:take_member(root,steps,self.span)
end
-- A compile-time index, or nil when the index is only known at run time. `-7` is a
-- unary negation of a literal, so both spellings are recognized (§2.2).
local function constant_index(node)
    local negative=A.Unary:isclassof(node) and node.operator==A.Negate
    local operand=negative and node.operand or node
    if not A.Integer:isclassof(operand) then return nil end
    local value=tonumber(V.scalar.integer(operand.spelling,function(m) error(m,0) end))
    return negative and -value or value
end

-- A place expression is a root binding plus the path of members that reaches it. Borrowing
-- `a.b` makes `a` address-taken, which resolution already recorded, so the root is a cell and
-- the path is walked as field addresses.
function place_path(node)
    local steps={}
    local current=node
    while true do
        if A.Project:isclassof(current) then
            table.insert(steps,1,{name=current.name,span=current.span}); current=current.base
        elseif A.Index:isclassof(current) then
            local index=constant_index(current.index)
            table.insert(steps,1,index and {index=index,span=current.span}
                or {expression=current.index,span=current.span})
            current=current.base
        elseif A.Name:isclassof(current) then
            return current.name,steps
        else
            return nil,nil,'this place form'
        end
    end
end

-- `mut place` yields a borrow: the same storage as the place, viewed as temporary access
-- rather than as something the borrower owns (§1.3, §9.3).
function A.Borrow:build(ctx)
    local root,steps,reason=place_path(self.place)
    if not root then gap(self.span,reason) end
    local id,binding,cell=ctx:binding(root,self.span)
    if not binding.mutable then fail(self.span,'mutable borrow of immutable binding') end
    if not cell.initialized then fail(self.span,'borrow of uninitialized binding') end
    if not binding.address then gap(self.span,'address-taken locals') end
    ctx:access(id,true,self.span)
    local stable=binding.lifetime=='module'
    local value=cell.value
    if #steps==0 then
        value=ctx:emit(B.BorrowPlace(ctx:ref(value),stable),L{B.Borrow(binding.type,stable)},self.span)
    else
        local type_=binding.type
        for _,step in ipairs(steps) do
            -- Names are found by search and indices are written by the source, so both
            -- describe the member position; field access is zero-based.
            local index,leaf=ctx:member_step(type_,step,step.span,'a borrow path requires an aggregate')
            if index then
                type_=leaf
                value=ctx:emit(B.FieldAddress(ctx:ref(value),index,stable),L{B.Borrow(type_,stable)},step.span)
            else
                -- A runtime index in a borrowed path selects a *place*, so the selection joins
                -- field addresses rather than values, and its members must share a type.
                local fields=type_:record()
                local key=step.expression:build(ctx); expect(key,B.Int,step.span)
                local element=fields[1].type
                local borrowed=B.Borrow(element,stable)
                ctx:pin(value); ctx:pin(key)
                value=ctx:select_member(key,fields,borrowed,step.span,
                    function(y,at) return y:emit(B.FieldAddress(y:ref(value),at,stable),L{borrowed},step.span) end)
                ctx:unpin(); ctx:unpin()
                type_=element
            end
        end
    end
    value.mode='mut'; value.origin=id
    return value
end
function A.Data:build(ctx) return self.value:build(ctx) end
-- A complete binding chain is also a value, so aggregates and delimited arguments can
-- hold runtime words without lambda syntax (§7.1).
local function chain_value(ctx,chain)
    if #chain.items==0 and A.Data:isclassof(chain.terminal) then return chain.terminal.value:build(ctx) end
    local builder=ctx.builder; if not builder then gap(chain.span,'word construction without a program builder') end
    local template=ctx.resolved.chains[chain]
    if not template then gap(chain.span,'unresolved word construction') end
    return builder:instantiate(ctx,{template=template})
end
A.Chain.value=chain_value
-- A record value is built from its fields. `fields` are builder records carrying a name,
-- type and mutability, so the record's own type states its shape: projection, interior
-- assignment and word-member invocation all read it from there (§8, §10.3, §11.3).
function Context:construct_record(values,fields,span)
    -- §11.2: a stage aggregate's constructor brands the record it builds, so a value carries the
    -- constructor's identity and two same-shaped constructors are distinct types.
    local nominal=self.nominal_constructor
    self.nominal_constructor=nil
    local declared,copy=L(),true
    for i,field in ipairs(fields) do
        declared:insert(B.Field(field.name,field.type,field.mutable))
        if not field.type:copyable() or field.mutable then copy=false end
    end
    -- While a module terminal is being built, owned state may only be *moved in* from a
    -- top-level prelude. New owned state would have no place in the module's own state
    -- record, so the unload function could never destroy it (§15.1).
    if self.module_preludes then
        for i,value in ipairs(values) do
            local owns=fields[i].type:owns()
            if owns and not (value.origin and self.module_preludes[value.origin]) then
                fail(span,'a module terminal may not construct new owned state; move an owned prelude into it')
            end
        end
    end
    local result=self:emit(B.Construct(self:refs(values),copy),L{B.Aggregate(declared,copy,nominal)},span)
    result.mode='fresh'
    return result
end

function Context:record_field(record,name,span)
    local fields=record:record()
    if not fields then fail(span,'this value has no members') end
    for index,field in ipairs(fields) do if field.name==name then return index,field end end
    fail(span,'no member ' .. name)
end

-- Resolve one member step against an aggregate type. A named member or a constant index
-- becomes a position; a run-time index has none and returns nil, leaving the caller to decide
-- what the selection means. `span` locates a non-aggregate failure (some callers blame the
-- whole path) and `message` is theirs because each place form names itself.
function Context:member_step(type_,step,span,message)
    local fields=type_:record()
    if not fields then fail(span,message) end
    local index
    if step.name then
        index=select(1,self:record_field(type_,step.name,step.span))-1
    elseif step.index then
        index=step.index
        if index<0 or index>=#fields then
            fail(step.span,('index %d is outside the valid range 0..%d'):format(index,#fields-1))
        end
    end
    if index==nil then return nil end
    local field=fields[index+1]
    return index,field.type,field.mutable
end

-- A run-time index yields one value, so the alternatives must have one type.
function Context:member_type(fields,span)
    local element=fields[1].type
    for i=2,#fields do
        if not fields[i].type:same(element) then fail(span,'a runtime index needs members of one type') end
    end
    return element
end

-- Lower a run-time index: compare the key against each member position, branch to the first
-- match, and trap past the end. `key` and whatever the arm reads must already be pinned.
-- `build(c,at)` says what the selection yields for member `at` -- a loaded member, a field
-- address, or a store chain.
function Context:select_member(key,fields,result,span,build)
    local element=self:member_type(fields,span)
    local function choose(c,at)
        if at>=#fields then
            c.block.exit=B.Trap(c:ref(c.effect),'index out of range')
            return nil
        end
        local matches=c:emit(B.IntegerLiteral(tostring(at)),L{B.Int},span)
        local test=c:emit(B.Binary(A.Equal,c:ref(key),c:ref(matches)),L{B.Bool},span)
        return c:branch(test,function(y) return build(y,at) end,function(n) return choose(n,at+1) end,result)
    end
    return choose(self,0)
end

function A.PositionalAggregate:build(ctx)
    local values,fields=L(),{}
    for index,chain in ipairs(self.elements) do
        local value=chain_value(ctx,chain)
        if value.host then refuse(self.span,'stored host words') end
        values:insert(value); fields[index]={type=value.type,mutable=false}
    end
    return ctx:construct_record(values,fields,self.span)
end

function A.NamedAggregate:build(ctx)
    ctx:push()
    local values,fields=L(),{}
    for index,member in ipairs(self.members) do
        member:build(ctx)
        local id=ctx:find(member.name)
        local value=ctx.cells[id].value
        if value.host then gap(member.span,'stored host words') end
        values:insert(value)
        fields[index]={name=member.name,type=value.type,mutable=ctx.fn.bindings[id].mutable}
    end
    -- The aggregate owns its members, so the member scope must not destroy them.
    ctx:retain(); ctx:pop()
    return ctx:construct_record(values,fields,self.span)
end

-- The word identity lives in the type, so a bundle can always be rebuilt from a record.
-- That is what lets a stored word cross a block interface (a loop packet field, for
-- instance) and still be invoked. `writable` says whether the record has an owner that
-- can receive interior state back; a read-only view cannot.
function Context:ensure_word(record,span,writable)
    local type_=record.type
    if not B.Word:isclassof(type_) then return nil end
    for _,field in ipairs(type_:record()) do
        if field.mutable and not writable then
            refuse(span,'invoking a word with mutable state through a read-only view')
        end
    end
    local template=self.builder and self.builder.resolved.templates[type_.template]
    if not template then gap(span,'word value with an unknown template') end
    local fields={}
    for i,field in ipairs(type_:record()) do
        fields[i]={name=field.name,type=field.type,mutable=field.mutable,owned=false,retained=true,span=span,
            value=self:emit(B.LoadField(self:ref(record),i-1),L{field.type},span)}
    end
    return {template=template,fields=fields,supplied=type_.supplied}
end

-- A word value that arrived as a block parameter has no bundle yet; rebuild it.
function Context:word_value(value,span,writable)
    if not value.word then value.word=self:ensure_word(value,span,writable) end
    return value
end

-- §8.3: projection selects a statically known named member and never invokes it.
function A.Project:build(ctx)
    -- A namespace member is a dictionary entry, not a field of a value.
    local member=ctx.resolved and ctx.resolved.namespace_members and ctx.resolved.namespace_members[self]
    if member then
        if member.conversion then return {conversion=member.conversion} end
        if member.signature then return {host=member} end
        refuse(self.span,'a namespace member here is not a runtime word')
    end
    -- §11.5: a member of a sum type word is an injection (`left`/`right`/`f<i>`).
    if A.Name:isclassof(self.base) then
        -- The base is a type word, so the sum is found through the resolved definition rather
        -- than the cell: a word that captured the binding has no cell for it of its own.
        local occurrences=ctx.resolved and ctx.resolved.references[self.base]
        local definition=occurrences and occurrences[1] and occurrences[1].definition
        -- The registry lives on the resolved table because every function shares that table and
        -- nothing else: a word that captured the binding is built in a context of its own.
        local sums=ctx.resolved and ctx.resolved.sums
        local sum=sums and definition and sums[definition]
        if sum then
            if self.name=='tag' then fail(self.span,'a sum tag is read from a value, not a type word') end
            for index,field in ipairs(sum:record()) do
                if field.name==self.name then return {injection={sum=sum,index=index-2}} end
            end
            fail(self.span,'no sum member ' .. self.name)
        end
    end
    local root,steps=place_path(self)
    local id=root and ctx:find(root)
    local key=id and ctx:path_key(ctx.fn.bindings[id].type,steps,self.span,true)
    if id and key then ctx:check_readable(id,key,self.span,ctx.intermediate) end
    local base
    if id and A.Name:isclassof(self.base) then
        base=ctx:read_place(id,root,ctx.fn.bindings[id],ctx.cells[id],self.span)
    else
        ctx.intermediate=true; base=self.base:build(ctx); ctx.intermediate=nil
    end
    if base.host then refuse(self.span,'projection requires a value') end
    local index,field=ctx:record_field(base.type,self.name,self.span)
    local value=ctx:emit(B.LoadField(ctx:ref(base),index-1),L{field.type},self.span)
    ctx:word_value(value,self.span,false)
    -- A projected non-Copy member is a read-only view: the aggregate still owns it.
    value.mode=field.type:copyable() and 'copy' or 'borrow'
    return value
end

-- §8.4: the index must be a non-negative Int below the length, and anything else traps. A
-- constant index resolves statically; a runtime index selects among the members, which must
-- share one type because the selection yields one value. An aggregate is a record with as many
-- members as the source wrote, so this costs one comparison per member.
function A.Index:build(ctx)
    local root,steps=place_path(self)
    local id=root and ctx:find(root)
    local static=constant_index(self.index)
    local key
    if id then
        if static then
            key=ctx:path_key(ctx.fn.bindings[id].type,steps,self.span,true)
            if key then ctx:check_readable(id,key,self.span,ctx.intermediate) end
        else
            -- A runtime index reads whichever subplace it names, so the base must be whole.
            local prefix={}
            for _,step in ipairs(steps) do
                if not (step.name or step.index) then break end
                prefix[#prefix+1]=step
            end
            key=ctx:path_key(ctx.fn.bindings[id].type,prefix,self.span,true) or ''
            ctx:nested_moved(id,key,self.span); ctx:check_readable(id,key,self.span,true)
        end
    end
    local base
    if id and static and A.Name:isclassof(self.base) then
        base=ctx:read_place(id,root,ctx.fn.bindings[id],ctx.cells[id],self.span)
    else
        ctx.intermediate=true; base=self.base:build(ctx); ctx.intermediate=nil
    end
    if base.host then refuse(self.span,'indexing requires a value') end
    local fields=base.type:record()
    if not fields then fail(self.span,'indexing requires an aggregate value') end
    local index=static
    if index then
        if index<0 or index>=#fields then
            fail(self.span,('index %d is outside the valid range 0..%d'):format(index,#fields-1))
        end
        local value=ctx:emit(B.LoadField(ctx:ref(base),index),L{fields[index+1].type},self.span)
        value.mode=fields[index+1].type:copyable() and 'copy' or 'borrow'
        return value
    end
    local key=self.index:build(ctx); expect(key,B.Int,self.index.span)
    local element=fields[1].type
    ctx:pin(base); ctx:pin(key)
    local value=ctx:select_member(key,fields,element,self.span,
        function(y,at) return y:emit(B.LoadField(y:ref(base),at),L{element},self.span) end)
    ctx:unpin(); ctx:unpin()
    if value then value.mode=element:copyable() and 'copy' or 'borrow' end
    return value
end


function A.Binding:build(ctx)
    local value
    if (#self.value.items>0 or not A.Data:isclassof(self.value.terminal)) and ctx.builder then
        local definition=ctx.resolved.bindings[self]
        if not definition then gap(self.span,'unresolved word construction') end
        value=ctx.builder:instantiate(ctx,definition)
    elseif #self.value.items>0 or not A.Data:isclassof(self.value.terminal) then
        gap(self.span,'local word construction without a program builder')
    else
        value=self.value.terminal:build(ctx)
    end
    if value.host then gap(self.span,'stored host words') end
    -- A sum type word carries the sum the injections and projections need; remembering it by the
    -- resolved definition keeps it reachable from a word that captured the binding.
    if value.sum and ctx.resolved and ctx.resolved.bindings[self] then
        ctx.resolved.sums=ctx.resolved.sums or {}
        ctx.resolved.sums[ctx.resolved.bindings[self]]=value.sum
    end
    ctx:check(self.constraint,value.type,self.span); ctx:accept_owned(value,self.span)
    ctx:validate_ownership(value.type,self.span)
    local definition=ctx.resolved and ctx.resolved.bindings[self]
    -- A binding becomes a place when its address is asked for, and also when a nested word
    -- captures it: §10.1 makes that capture a borrow, and a borrow of a value is its
    -- storage. Either way the binding is a cell, and read, assign, borrow, move and
    -- destruction already go through an address when the binding has one.
    local captured=definition and definition.captured and not value.type:copyable()
    if definition and (definition.address_taken or captured) then
        if definition.address_taken and not self.mutable then
            fail(self.span,'a mutable borrow requires a mutable binding ' .. self.name)
        end
        local address=ctx:ordered(B.Allocate(ctx:ref(ctx.effect),ctx:ref(value)),B.Address(value.type),self.span)
        ctx:bind(self.name,address,self.mutable,not value.type:copyable(),false,address,self.span)
        return
    end
    ctx:bind(self.name,value,self.mutable,not value.type:copyable(),false,false,self.span)
end
function A.Local:build(ctx) self.binding:build(ctx) end
-- §4.3: assignment evaluates the destination place, then the right-hand side, then
-- replaces. For a record member the place is the aggregate binding plus a static member
-- index, and replacement is a functional record update rebound to that owner.
-- A record updated in place goes back into the storage that holds it. Replacing the cell's
-- value would put a record where the cell's address belongs.
function Context:rebind(id,binding,cell,updated,span)
    if binding.address then
        self:ordered(B.Store(self:ref(self.effect),self:ref(self.cells[id].value),self:ref(updated)),nil,span)
    else
        local current=self.cells[id]
        current.value=updated; current.initialized=true; current.alive=binding.owned
    end
end

-- §8.4 positional elements have no individual qualifier, so their write capability comes
-- from the base place. §4.3 evaluates the destination first, then the right-hand side.
-- §9.4 Assignment establishes the destination place first, then evaluates the right-hand
-- side, then replaces whatever the place still holds. A destination is any place path from a
-- binding: names and constant indices resolve to member positions, one index may be computed
-- at run time, and each level of the path is rebuilt from the leaf up.
function A.Assign:assign_place(ctx)
    local root,steps=place_path(self.place)
    if not root then gap(self.span,'this assignment place') end
    local id,binding,cell=ctx:binding(root,self.span)
    if not cell.initialized then fail(self.span,'assignment to uninitialized binding ' .. binding.name) end
    ctx:access(id,true,self.span)
    -- Walk the steps written in the source. The first index computed at run time stops the
    -- walk, because which member it names is only known per arm.
    local positions,interior={},false
    local records={ctx:read_place(id,root,binding,cell,self.span)}
    local path,type_,dynamic='',binding.type,0
    for i,step in ipairs(steps) do
        -- §11.5: the tag decides which alternative is live, so writing one directly would
        -- contradict it. Replace the whole sum by injecting instead.
        if B.Sum:isclassof(type_) then fail(step.span,'a sum alternative is selected by the tag, not assigned to') end
        local index,leaf,mutable=ctx:member_step(type_,step,step.span,'a place path requires an aggregate value')
        if index==nil then dynamic=i; break end
        if mutable then interior=true end
        positions[i]=index
        path=(path=='' and tostring(index)) or (path .. '.' .. tostring(index))
        type_=leaf
        if i<#steps then
            records[i+1]=ctx:emit(B.LoadField(ctx:ref(records[i]),index),L{type_},step.span)
        end
    end
    -- The steps after a run-time index are resolved against the member's type, so the
    -- alternatives have to look alike. `levels[i]` is the record type that `suffix[i]`
    -- indexes, which is what makes each load and store below well typed.
    local suffix,levels,leaf={}, {},type_
    if dynamic>0 then
        local members=records[dynamic].type:record()
        leaf=ctx:member_type(members,self.span)
        for i=dynamic+1,#steps do
            local step=steps[i]
            local index,next_leaf,mutable=ctx:member_step(leaf,step,step.span,'a place path requires an aggregate value')
            if index==nil then gap(step.span,'two runtime indices in one place path') end
            if mutable then interior=true end
            suffix[#suffix+1]=index; levels[#levels+1]=leaf; leaf=next_leaf
        end
        ctx:nested_moved(id,path,self.span); ctx:check_writable(id,path,self.span)
    else
        ctx:check_writable(id,path,self.span)
    end
    -- §8.3 interior mutable state stays writable through an immutable owning binding, while
    -- §8.4 positional elements take their write capability from the base place instead.
    if not (binding.mutable or interior) then
        if A.Project:isclassof(self.place) then
            fail(self.span,'assignment to an immutable member ' .. self.place.name)
        end
        fail(self.span,'assignment to an immutable binding ' .. binding.name)
    end
    local key
    if dynamic>0 then
        key=steps[dynamic].expression:build(ctx); expect(key,B.Int,steps[dynamic].span)
    end
    -- The destination is established before the right-hand side (§4.3), and every level of
    -- it must survive any control flow that the right-hand side builds.
    local parent=records[dynamic>0 and dynamic or #steps]
    for i=1,#records do ctx:pin(records[i]) end
    local crossed=ctx:pin_moved(ctx.cells[id].moved)
    if key then ctx:pin(key) end
    local value=self.value:build(ctx)
    expect(value,leaf,self.span); ctx:accept_owned(value,self.span)
    ctx:pin(value)
    -- A hole holds no value, so replacing one releases nothing. Only a path the source wrote
    -- completely can be a hole, and its state may be a run-time fact (see `destroy`).
    local hole=(dynamic==0) and ctx.cells[id].moved[path] or nil
    local function replace(c,at,target)
        local position=(dynamic>0) and at or positions[#steps]
        -- Rebuild from the leaf up: the suffix inside the selected member, then the member
        -- itself, then the levels the source wrote before the run-time index.
        local chain={}
        if dynamic>0 then
            chain[1]=c:emit(B.LoadField(c:ref(parent),at),L{levels[1] or leaf},self.span)
        else
            chain[1]=parent
        end
        for i=1,#suffix do
            chain[i+1]=c:emit(B.LoadField(c:ref(chain[i]),suffix[i]),L{levels[i]:record()[suffix[i]+1].type},self.span)
        end
        -- The value being replaced is the member itself when the path stops at the index,
        -- and the last level the suffix reached otherwise. Releasing the container instead
        -- would destroy the wrong thing.
        local old
        if #suffix==0 then
            old=c:emit(B.LoadField(c:ref(parent),position),L{leaf},self.span)
        else
            old=chain[#suffix+1]
        end
        local function store()
            local updated=target
            for i=#suffix,1,-1 do
                updated=c:emit(B.StoreField(c:ref(chain[i]),suffix[i],c:ref(updated)),L{levels[i]},self.span)
            end
            local joined=c:emit(B.StoreField(c:ref(parent),position,c:ref(updated)),L{parent.type},self.span)
            for i=(dynamic>0 and dynamic or #steps)-1,1,-1 do
                joined=c:emit(B.StoreField(c:ref(records[i]),positions[i],c:ref(joined)),L{records[i].type},self.span)
            end
            return joined
        end
        if not (leaf:owns() and hole~=true) then return store() end
        local function release(t)
            t:destroy(old,self.span,dynamic==0 and ctx.cells[id].moved or nil,dynamic==0 and path or nil)
        end
        if hole==nil then
            release(c)
            return store()
        end
        -- The place may already be a hole, so the old value goes only where one is there.
        -- Everything the store still needs must cross the branch with it.
        for i=1,#chain do c:pin(chain[i]) end
        c:pin(old); c:pin(hole)
        c:branch(hole,function() end,release)
        c:unpin(); c:unpin()
        for i=1,#chain do c:unpin() end
        return store()
    end
    local updated
    if dynamic==0 then
        updated=replace(ctx,positions[#steps],value)
    else
        updated=ctx:select_member(key,parent.type:record(),records[1].type,self.span,
            function(c,at) return replace(c,at,value) end)
    end
    if updated then
        ctx:rebind(id,binding,cell,updated,self.span)
        if dynamic==0 then
            for was in pairs(ctx.cells[id].moved) do
                if contains(path,was) then ctx.cells[id].moved[was]=nil end
            end
        end
    end
    if key then ctx:unpin() end
    ctx:unpin_moved(crossed)
    for i=1,#records do ctx:unpin() end
    ctx:unpin()
end

function A.Assign:assign_binding(ctx)
    local id,binding=ctx:binding(self.place.name,self.span)
    if not binding.mutable then fail(self.span,'assignment to immutable binding ' .. binding.name) end
    local value=self.value:build(ctx); expect(value,binding.type,self.span); ctx:accept_owned(value,self.span); ctx:access(id,true,self.span)
    ctx:pin(value)
    if binding.address then
        ctx:ordered(B.Store(ctx:ref(ctx.effect),ctx:ref(ctx.cells[id].value),ctx:ref(value)),nil,self.span)
        ctx.cells[id].moved={}
    else
        ctx:release(id); ctx.cells[id]={value=value,initialized=true,alive=binding.owned,moved={}}
    end
    ctx:unpin()
end
function A.Assign:build(ctx)
    if A.Name:isclassof(self.place) then return self:assign_binding(ctx) end
    return self:assign_place(ctx)
end

function A.Discard:build(ctx)
    local value=self.value:build(ctx)
    if value.host or value.mode=='mut' then refuse(self.span,'discard of word/borrow values') end
    if not value.type:copyable() and value.mode=='fresh' then ctx:destroy(value,self.span) end
end
function A.Return:build(ctx)
    if self.value then self.value:tail(ctx) else ctx:finish(ctx:emit(B.UnitLiteral,L{B.Unit},self.span),self.span) end
end
function A.If:build(ctx)
    local condition=self.condition:build(ctx); expect(condition,B.Bool,self.span)
    ctx:branch(condition,function(c) c:statements(self.yes) end,function(c) c:statements(self.no) end)
end
function A.While:build(ctx)
    local head,args=ctx:interface({ctx},nil,true); local header=head.block
    ctx.block.exit=B.Jump(ctx:edge(head,args[1]))
    -- Keep the original header even if the condition itself creates control blocks.
    local condition=self.condition:build(head); expect(condition,B.Bool,self.span)
    local body,ba=head:interface({head}); local exit,ea=head:interface({head})
    head.block.exit=B.Branch(head:ref(condition),head:edge(body,ba[1]),head:edge(exit,ea[1]))
    body:push()
    -- `depth` is the loop body's own scope, so a `break` or `continue` unwinds to it and
    -- destroys exactly the locals one iteration created (§9.3).
    body:loop({head=head,exit=exit,depth=#body.scopes})
    body:statements(self.body)
    if not body.block.exit then
        body:pop()
        for id=1,#ctx.fn.bindings do if ctx.cells[id] then
            if body.cells[id].initialized~=ctx.cells[id].initialized then gap(self.span,'loop ownership states that require initialization fixed-point analysis') end
            for key in pairs(body.cells[id].moved) do
                if not ctx.cells[id].moved[key] then
                    -- The header's fact must be dynamic for a backedge to carry a hole,
                    -- yet the body's own move needs it statically initialized. Breaking
                    -- that circle needs path-sensitive facts (or peeling the first
                    -- iteration), not a bigger parameter list.
                    gap(self.span,'a partial move inside a loop needs path-sensitive initialization analysis')
                end
            end
        end end
        body.block.exit=B.Jump(B.Edge(header.id,body:refs(head:pack(body))))
    end
    ctx:adopt(exit)
end
-- A `break` leaves the nearest enclosing loop; a `continue` re-evaluates its condition.
-- Both carry the current state to the loop's exit or header interface, so the loop-carried
-- facts and the effect thread cross the edge like any other branch.
function A.Break:build(ctx)
    local target=ctx.loops and ctx.loops[1]
    if not target then refuse(self.span,'break outside a loop') end
    ctx:unwind(target.depth)
    ctx.block.exit=B.Jump(ctx:edge(target.exit,target.exit:pack(ctx)))
end
function A.Continue:build(ctx)
    local target=ctx.loops and ctx.loops[1]
    if not target then refuse(self.span,'continue outside a loop') end
    ctx:unwind(target.depth)
    ctx.block.exit=B.Jump(ctx:edge(target.head,target.head:pack(ctx)))
end
function A.Expr:case_label() fail(self.span,'case labels must be Int or Bool literals') end
function A.Integer:case_label() local _,key=literal.integer(self.spelling,false,function(m) fail(self.span,m) end); return B.Int,key end
function A.Boolean:case_label() return B.Bool,tostring(self.value) end
function A.Unary:case_label()
    if self.operator~=A.Negate or not A.Integer:isclassof(self.operand) then fail(self.span,'case labels must be Int or Bool literals') end
    local _,key=literal.integer(self.operand.spelling,true,function(m) fail(self.span,m) end); return B.Int,key
end
function A.Switch:build(ctx)
    local subject=ctx:pin(self.subject:build(ctx)); local seen={}
    if #self.cases==0 then fail(self.span,'switch requires at least one case') end
    for _,arm in ipairs(self.cases) do
        if #arm.labels==0 then fail(arm.span,'case requires a label') end
        for _,label in ipairs(arm.labels) do
            local type_,key=label:case_label(); expect(subject,type_,label.span)
            if seen[key] then fail(label.span,'duplicate case label') end; seen[key]=true
        end
    end
    local function arm_at(c,index)
        local arm=self.cases[index]
        if not arm then c:statements(self.otherwise); return end
        if index==#self.cases and subject.type==B.Bool and seen['true'] and seen['false'] and #self.otherwise==0 then c:statements(arm.body); return end
        local condition
        for _,label in ipairs(arm.labels) do
            local test=A.Equal:apply(c,subject,label:build(c),label.span)
            -- All labels are pure literals; combine eagerly without introducing source effects.
            condition=condition and c:emit(B.Binary(A.Or,c:ref(condition),c:ref(test)),L{B.Bool},label.span) or test
        end
        c:branch(condition,function(child) child:statements(arm.body) end,function(child) arm_at(child,index+1) end)
    end
    ctx:push(); arm_at(ctx,1); if not ctx.block.exit then ctx:pop() end; ctx:unpin()
end
-- The explicit conversions between Let and C values: one pure argument, one pure result, no
-- ownership to move. The same definition serves an invocation and a juxtaposition, so they
-- cannot lower differently.
local conversions={
    float={arity=1,from={B.Int},to=B.Float,operator=A.ToFloat},
    int={arity=1,from={B.Float},to=B.Int,operator=A.ToInt},
-- §13.2 the fixed-width conversions truncate the low bits of an Int; they are the explicit
-- crossings, so no value changes width implicitly.
    u8={arity=1,from={B.Int},to=B.U8,operator=A.ToU8},
    u32={arity=1,from={B.Int},to=B.U32,operator=A.ToU32},
-- §13.3 Float32 narrows a binary64 to binary32; there is no implicit Float/Float32 conversion.
    f32={arity=1,from={B.Float},to=B.Float32,operator=A.ToF32},
    -- `borrows` names the argument whose storage the result views. The distinction from a host's
    -- `ownership` is real: `ownership='borrowed'` says Let must not free the result, while
    -- `borrows=i` says the result is a view of argument i, so argument i must stay put while the
    -- view is live.
    cstring={arity=1,from={B.Text},to=B.CString,operator=A.ToCString,borrows=1},
    ctext={arity=1,from={B.CString},to=B.Text,operator=A.ToText,borrows=1},
    byte_length={arity=1,from={B.Text},to=B.Int,operator=A.TextSize},
    null={arity=1,from='pointer',to=B.Bool,operator=A.IsNull},
    -- A Text view over a pointer and a length; the only conversion that takes two arguments.
    text_of={arity=2,from='pointer',from2={B.Int},to=B.Text,borrows=1},
}
function Context:convert(kind,arguments,span)
    local conversion=conversions[kind]
    if #arguments~=conversion.arity then
        fail(span,('a %s conversion takes %d argument%s'):format(kind,conversion.arity,conversion.arity==1 and '' or 's'))
    end
    -- A borrowed pointer is one of the pointer types or a resource that declares a pointer
    -- representation; the marker `'pointer'` says so without listing resource names.
    local function is_pointer(type_)
        if type_==B.CString or type_==B.CPointer then return true end
        return B.Named:isclassof(type_) and self.fn.vocabulary:representation(type_.name)=='pointer'
    end
    local built={}
    local function build(index,accepted)
        local value=arguments[index]:build(self)
        local ok=accepted=='pointer' and is_pointer(value.type)
        if accepted~='pointer' then
            for _,type_ in ipairs(accepted) do if value.type:same(type_) then ok=true end end
        end
        if not ok then fail(span,'a ' .. kind .. ' conversion is not defined for ' .. tostring(value.type)) end
        built[index]=value
        return value
    end
    local operation
    if conversion.arity==1 then
        operation=B.Unary(conversion.operator,self:ref(build(1,conversion.from)))
    else
        local pointer=build(1,conversion.from)
        local size=build(2,conversion.from2)
        operation=B.TextOf(self:ref(pointer),self:ref(size))
    end
    local result=self:emit(operation,L{conversion.to},span)
    result.mode='copy'
    -- `borrows` names the argument the result views, so that argument is held for as long as the
    -- view is. A conversion with no view borrows nothing.
    local source=conversion.borrows and built[conversion.borrows]
    if source then return self:hold_view(result,source,span) end
    return result
end
function Context:call(expression,tail)
    local callee=expression.word:build(self)
    if callee.conversion then
        return self:convert(callee.conversion,expression.arguments,expression.span)
    end
    if not callee.host then
        if callee.type and not B.Callable:isclassof(callee.type) then fail(expression.span,'invocation requires a runtime word') end
        gap(expression.span,'source/indirect word invocation')
    end
    local host=callee.host; local sig=host.signature
    self:validate_ownership(sig.results[1],expression.span)
    if #expression.arguments~=#sig.parameters then fail(expression.span,'invocation must exactly saturate remaining stages') end
    local values,locks={},{}; self:push()
    for i,argument in ipairs(expression.arguments) do
        local parameter=sig.parameters[i]; local value=argument:build(self)
        if not value.type then gap(argument.span,'word values in data positions') end
        local access,temporary=parameter.capability:bind_argument(value,B.Transient,function(message) fail(argument.span,message) end)
        if access==B.MutAccess then
            assert(B.Borrow:isclassof(value.type) and value.type.pointee:same(parameter.type),'a mutable stage requires a mutable place')
        else
            expect(value,parameter.type,argument.span)
        end
        if temporary then
            -- §6.5: the callee and every borrowed argument must outlive this activation's
            -- cleanup, and a value the callee only borrows for the call cannot. That is an
            -- ownership error, not a missing lowering.
            if tail then
                fail(argument.span,'a tail invocation cannot borrow an argument for the call')
            end
            local id=self:bind('$argument' .. i,value,false,true,false,false,argument.span)
            value=copy(value); value.origin=id; value.mode='borrow'
        end
        local borrowing=access==B.MutAccess or access==B.ReadAccess
        if borrowing then
            local id=assert(value.origin); local binding=self.fn.bindings[id]
            if tail and not binding.external then fail(argument.span,'tail invocation borrow does not outlive caller cleanup') end
            local writing=parameter.capability==A.Mut; self:access(id,writing,argument.span)
            local lock=self.locks[id] or {read=0}; self.locks[id]=lock
            if writing then lock.write=true else lock.read=lock.read+1 end
            locks[#locks+1]={id=id,writing=writing}
        end
        values[i]=self:pin(value)
    end
    if tail then self:cleanup() end
    local pure=host.purity=='pure' and sig.results[1]:copyable()
    for _,parameter in ipairs(sig.parameters) do pure=pure and parameter.type:copyable() and parameter.capability~=A.Mut end
    local result
    if pure then result=self:emit(B.PureHostCall(host.symbol,self:refs(values)),L{sig.results[1]},expression.span)
    else result=self:ordered(B.HostCall(host.symbol,self:ref(self.effect),self:refs(values)),sig.results[1],expression.span) end
    result.mode=result.type:copyable() and 'copy' or 'fresh'
    for _,lock in ipairs(locks) do local entry=self.locks[lock.id]; if lock.writing then entry.write=false else entry.read=entry.read-1 end end
    for _=1,#values do self:unpin() end
    self:pin(result); self:pop(); self:unpin()
    -- A host view outlives the call, so its hold is taken in the caller's scope, after the call's
    -- own scope has released the borrows it made for the arguments.
    if host.borrows then
        local source=values[host.borrows]
        if source then result=self:hold_view(result,source,expression.span) end
    end
    return result
end
function A.Invoke:build(ctx)
    local builder=ctx.builder
    if builder then return builder:invoke(ctx,self,false) end
    return ctx:call(self,false)
end
function A.Invoke:tail(ctx)
    local builder=ctx.builder
    if builder then builder:invoke(ctx,self,true) else ctx:finish(ctx:call(self,true),self.span) end
end
-- A stage binds through the one capability rule in `Packet`, so the generic builder and a host
-- entry deliver the same shape and ownership for `mut` and `own mut`.
-- and a host entry deliver the same shape and ownership for `mut` and `own mut`.
function A.Stage:bind_parameter(ctx,index,options)
    local type_=ctx:check(self.constraint,nil,self.span)
    if not type_ then refuse(self.span,'stage type inference from uses; supply a concrete parameter type') end
    if self.capability==A.Mut and not type_:copyable() then gap(self.span,'mutable borrowed resource stages') end
    ctx:validate_ownership(type_,self.span)
    Packet.bind_parameter(ctx,Packet.stage_field(self.capability,self.name,self.span,type_),self.name,self.span)
end
function A.Prelude:bind_parameter() gap(self.binding.span,'stage preparation: preludes must run between arguments, not at terminal entry') end
-- A foreign declaration has no parameter of its own; the host entry is an ordinary call site.
function A.Extern:bind_parameter() end
function A.Chain:build_function(name,options)
    options=options or {}
    if not A.Body:isclassof(self.terminal) then refuse(self.span,'data-terminal construction (not a runtime function)') end
    -- One validated vocabulary, the same one a program build uses.
    local vocabulary=Vocabulary.new(options)
    local ctx=Context.new_function{name=name,span=self.span,result=options.result,
        vocabulary=vocabulary}
    local fn=ctx.fn
    for i,item in ipairs(self.items) do item:bind_parameter(ctx,i,options) end
    fn.self_visible=true
    return ctx:finish_function(self.terminal.statements):verify_flow(vocabulary.hosts)
end
V.Build={Context=Context,expect=expect,fail=fail,gap=gap,refuse=refuse,copy=copy}
end

