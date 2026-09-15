-- AST -> immutable belt blocks. Draft blocks, names, SSA versions, pins and ownership
-- facts are construction-context state, never annotations on source or belt nodes.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local literal=require('v2.literal')
local Context={}; Context.__index=Context
local function copy(t) local out={}; for k,v in pairs(t) do out[k]=v end; return out end
local function fail(span,message) error(('%s:%d:%d: %s'):format(span.file,span.line,span.column,message),0) end
local function gap(span,message) fail(span,'v2 construction not yet implemented: ' .. message) end
function B.Type:same(other) return self==other end
function B.Named:same(other) return B.Named:isclassof(other) and self.name==other.name end
function B.Address:same(other) return B.Address:isclassof(other) and self.pointee:same(other.pointee) end
local function fields_same(a,b)
    if #a~=#b then return false end
    for i,field in ipairs(a) do
        if field.name~=b[i].name or field.mutable~=b[i].mutable or not field.type:same(b[i].type) then return false end
    end
    return true
end
function B.Aggregate:same(other)
    return B.Aggregate:isclassof(other) and self.is_copy==other.is_copy and fields_same(self.fields,other.fields)
end
function B.Word:same(other)
    return B.Word:isclassof(other) and self.template==other.template and self.supplied==other.supplied
        and self.is_copy==other.is_copy and fields_same(self.fields,other.fields)
end
function B.Type:copyable() return false end
function B.Int:copyable() return true end
function B.Bool:copyable() return true end
function B.Unit:copyable() return true end
function B.Text:copyable() return true end
-- §8.5: an aggregate is Copy exactly when every contained value is Copy and it declares
-- no mutable member. Both facts are recorded in the type, because member types alone
-- cannot express a declared mutable member.
function B.Aggregate:copyable() return self.is_copy end

-- Word records and aggregates are both ordered fields; only words carry a template.
function B.Type:record() return nil end
function B.Aggregate:record() return self.fields end
function B.Word:record() return self.fields end
function B.Word:copyable() return self.is_copy end
local function expect(value,type_,span)
    if not value.type then gap(span,'word values in data positions') end
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
function Context:read(name,span)
    local id,binding,cell=self:binding(name,span)
    if not cell.initialized then fail(span,'use after move or uninitialized binding ' .. name) end
    self:access(id,false,span)
    local value=cell.value
    if binding.address then value=self:ordered(B.Load(self:ref(self.effect),self:ref(value)),binding.type,span) end
    local meaning=copy(value); meaning.origin=id; meaning.mode=binding.type:copyable() and 'copy' or 'borrow'
    return meaning
end
function Context:resource(type_,span)
    local r=B.Named:isclassof(type_) and self.fn.resources[type_.name]
    if not r then gap(span,'ownership representation for ' .. tostring(type_)) end
    return r
end

-- Validate that every resource reachable inside a type has a declared representation.
-- A type that owns no resource needs no destruction story, so this is not a Copy check.
function Context:validate_ownership(type_,span)
    if B.Named:isclassof(type_) then self:resource(type_,span)
    elseif B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        for _,field in ipairs(type_.fields) do self:validate_ownership(field.type,span) end
    end
end
function Context:constraint(annotation,type_,span)
    if not annotation then return type_ end
    if #annotation.arguments>0 then gap(span,'specialized constraint words') end
    if self:find(annotation.name) or self.fn.hosts[annotation.name] or (self.fn.self_visible and annotation.name==self.fn.name) then
        fail(span,'constraint name is shadowed by a runtime binding')
    end
    if annotation.name=='Copy' and type_ then
        if not type_:copyable() then fail(span,'constraint Copy is not satisfied') end; return type_
    end
    local declared=self.fn.types[annotation.name]
    if not declared then gap(span,'constraint ' .. annotation.name) end
    if type_ then expect({type=type_},declared,span) end; return declared
end
function Context:bind(name,value,mutable,owned,external,address,span)
    local scope=self.scopes[#self.scopes]
    if scope.names[name] then fail(span,'duplicate binding ' .. name) end
    local id=#self.fn.bindings+1
    local type_=address and value.type.pointee or value.type
    self.fn.bindings[id]={name=name,type=type_,mutable=mutable,owned=owned,external=external,address=address,span=span}
    scope.names[name]=id; scope.ids[#scope.ids+1]=id
    self.cells[id]={value=value,initialized=true,alive=owned}; return id
end
-- Field/parameter scopes mirror lexical shadowing: a later field of the same name
-- replaces the earlier one in the current region instead of being a duplicate.
function Context:force_bind(name,value,mutable,owned,external,address,span)
    local scope=self.scopes[#self.scopes]
    local existing=scope.names[name]
    if existing then scope.ids[#scope.ids]=nil end
    local id=#self.fn.bindings+1
    local type_=address and value.type.pointee or value.type
    self.fn.bindings[id]={name=name,type=type_,mutable=mutable,owned=owned,external=external,address=address,span=span}
    scope.names[name]=id; scope.ids[#scope.ids+1]=id
    self.cells[id]={value=value,initialized=true,alive=owned}; return id
end
-- §10.1: a value borrows when its type holds an address, because an address is how a
-- borrow is represented. Such a value may not leave the activation that owns the storage,
-- so escape points can be decided from the type alone, with no value-level tracking.
function Context:borrows(type_)
    if B.Address:isclassof(type_) then return true end
    if B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        for _,field in ipairs(type_.fields) do if self:borrows(field.type) then return true end end
    end
    return false
end

function Context:take(name,span)
    local id,binding,cell=self:binding(name,span)
    if not cell.initialized then fail(span,'use after move or uninitialized binding ' .. name) end
    self:access(id,true,span)
    if binding.type:copyable() then gap(span,'move of Copy bindings') end
    if not binding.owned then fail(span,'cannot move from a borrowed stage') end
    -- Moving out of a place reads its contents first; the cell itself stays.
    local source=cell.value
    if binding.address then
        source=self:ordered(B.Load(self:ref(self.effect),self:ref(source)),binding.type,span)
    end
    local value=self:ordered(B.Move(self:ref(self.effect),self:ref(source)),binding.type,span)
    self.cells[id]={value=cell.value,initialized=false,alive=false}
    value.mode='fresh'; value.origin=id; return value
end
function Context:accept_owned(value,span)
    if not value.type then gap(span,'stored or returned words') end
    if value.mode=='mut' then fail(span,'a mutable borrow cannot be stored or returned') end
    if not value.type:copyable() and value.mode~='fresh' then fail(span,'non-copyable value requires move or a fresh result') end
end
function Context:new_block()
    local block={parameters=L(),instructions=L(),id=#self.fn.blocks+1}
    self.fn.blocks[#self.fn.blocks+1]=block; return block
end
-- A cloned context is the same construction, one block later, so it must carry the
-- builder/resolution it resolves word identities and templates against.
function Context:clone()
    local child=setmetatable({fn=self.fn,block=self:new_block(),locations={},cells={},pins={},locks=self.locks,scopes={},
        builder=self.builder,resolved=self.resolved,mutable_state=self.mutable_state},Context)
    for i,scope in ipairs(self.scopes) do child.scopes[i]={names=copy(scope.names),ids=copy(scope.ids),retained=scope.retained} end
    return child
end
-- A target interface carries each source binding independently: two aliases can
-- diverge after assignment. Expression pins carry earlier operands across CFG splits.
function Context:interface(endpoints,extras,loop_head)
    local target=self:clone(); local args={}; for i in ipairs(endpoints) do args[i]={} end
    local function parameter(type_,get)
        local value=target:parameter(type_)
        for i,endpoint in ipairs(endpoints) do args[i][#args[i]+1]=get(endpoint) end
        return value
    end
    target.effect=parameter(B.Effect,function(e) return e.effect end)
    for id=1,#self.fn.bindings do if self.cells[id] then
        local base=self.cells[id]; local initialized=true
        for _,e in ipairs(endpoints) do initialized=initialized and e.cells[id].initialized end
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
        target.cells[id]={value=value,initialized=initialized,alive=alive}
    end end
    for i,pin in ipairs(self.pins) do
        local value=parameter(pin.type,function(e) return e.pins[i] end)
        target.locations[pin.id]=target.locations[value.id]; target.pins[i]=pin
    end
    local outputs={}
    for i,type_ in ipairs(extras or {}) do outputs[i]=parameter(type_,function(e) return e.extra[i] end) end
    return target,args,outputs
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
-- A non-Copy value carries ownership: a resource by its declared destructor, a record by
-- destroying its owned fields in reverse initialization order (§8.5, §9.5).
function Context:owns(type_)
    if B.Address:isclassof(type_) then return self:owns(type_.pointee) end
    if type_:copyable() then return false end
    if B.Named:isclassof(type_) then return true end
    if B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        for _,field in ipairs(type_.fields) do if self:owns(field.type) then return true end end
        return false
    end
    return false
end

function Context:destroy(value,span)
    local type_=value.type
    if B.Address:isclassof(type_) then
        -- Destroying a place destroys what it contains. A module's owned state lives in
        -- places so that a captured word can borrow it (§10.1).
        self:destroy(self:ordered(B.Load(self:ref(self.effect),self:ref(value)),type_.pointee,span),span)
    elseif B.Named:isclassof(type_) then
        self:ordered(B.Destroy(self:ref(self.effect),self:ref(value),self:resource(type_,span).destroy),nil,span)
    elseif B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        for index=#type_.fields,1,-1 do
            local field=type_.fields[index]
            if self:owns(field.type) then
                self:destroy(self:emit(B.LoadField(self:ref(value),index-1),L{field.type},span),span)
            end
        end
    else
        gap(span,'destruction of ' .. tostring(type_))
    end
end
function Context:release(id)
    local binding,cell=self.fn.bindings[id],self.cells[id]
    if not binding.owned or cell.alive==false then return end
    self:access(id,true,binding.span)
    self.cells[id]={value=cell.value,initialized=false,alive=false}
    if cell.alive==true then
        -- For a place, the owned value is the cell's contents, not the address.
        local contents=cell.value
        if binding.address then
            contents=self:ordered(B.Load(self:ref(self.effect),self:ref(contents)),binding.type,binding.span)
        end
        self:destroy(contents,binding.span)
    elseif binding.address then
        gap(binding.span,'conditional destruction of an address-taken binding')
    else
        -- Pin the old value: conditional destruction introduces new block parameters.
        self:pin(cell.value)
        self:branch(cell.alive,function(ctx) ctx:destroy(cell.value,binding.span) end,function() end)
        self:unpin()
    end
end
function Context:pop()
    local scope=self.scopes[#self.scopes]
    if scope.retained then
        for i=#scope.ids,1,-1 do self.cells[scope.ids[i]]=nil end
    else
        for i=#scope.ids,1,-1 do self:release(scope.ids[i]); self.cells[scope.ids[i]]=nil end
    end
    self.scopes[#self.scopes]=nil
end
function Context:cleanup()
    for i=#self.scopes,1,-1 do
        if not self.scopes[i].retained then
            local ids=self.scopes[i].ids; for j=#ids,1,-1 do self:release(ids[j]) end
        end
    end
end
-- A module initializer returns the namespace plus the state that owns it (§15.1).
function Context:finish_pair(namespace,state,span)
    self.fn.result=namespace.type; self.fn.state=state.type
    self:pin(namespace); self:pin(state); self:cleanup()
    self.block.exit=B.Return(L{self:ref(namespace),self:ref(state),self:ref(self.effect)}); self:unpin(); self:unpin()
end

function Context:finish(value,span)
    if not self.allow_borrow_escape and self:borrows(value.type) then
        fail(span,'a word that borrows enclosing state cannot be returned from the invocation that owns it')
    end
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
function A.Expr:build() gap(self.span,'this expression form') end
function A.Expr:tail(ctx) ctx:finish(self:build(ctx),self.span) end
function A.Stmt:build() gap(self.span,'this statement form') end
function A.Name:build(ctx)
    if ctx:find(self.name) then return ctx:word_value(ctx:read(self.name,self.span),self.span,true) end
    -- The defining runtime word is visible only inside its own terminal body (§4.2).
    if ctx.self_name==self.name and ctx.builder then return ctx.builder:self_value(ctx,ctx.self_definition) end
    if ctx.resolved and ctx.resolved.import_words[self] then return {construction='import'} end
    if self.name==ctx.fn.name then gap(self.span,'source-word invocation and recursion') end
    local host=ctx.fn.hosts[self.name]; if host then return {host=host} end
    if ctx.fn.types[self.name] or self.name=='Copy' or self.name=='Executable' then fail(self.span,'constraint word is not a runtime value') end
    fail(self.span,'unknown name ' .. self.name)
end
function A.Integer:build(ctx)
    local spelling=literal.integer(self.spelling,false,function(m) fail(self.span,m) end)
    return ctx:emit(B.IntegerLiteral(spelling),L{B.Int},self.span)
end
function A.Boolean:build(ctx) return ctx:boolean(self.value,self.span) end
function A.Unit:build(ctx) return ctx:emit(B.UnitLiteral,L{B.Unit},self.span) end
function A.Text:build(ctx) return ctx:emit(B.TextLiteral(self.value),L{B.Text},self.span) end
function A.Unary:build(ctx)
    if self.operator==A.Negate and A.Integer:isclassof(self.operand) then
        local spelling=literal.integer(self.operand.spelling,true,function(m) fail(self.span,m) end)
        return ctx:emit(B.IntegerLiteral(spelling),L{B.Int},self.span)
    end
    local value=self.operand:build(ctx); expect(value,self.operator==A.Not and B.Bool or B.Int,self.span)
    return ctx:emit(B.Unary(self.operator,ctx:ref(value)),L{value.type},self.span)
end
function A.BinaryOp:apply(ctx,left,right,span)
    expect(left,B.Int,span); expect(right,B.Int,span)
    return ctx:emit(B.Binary(self,ctx:ref(left),ctx:ref(right)),L{B.Int},span)
end
local function comparison(self,ctx,left,right,span)
    expect(left,B.Int,span); expect(right,B.Int,span)
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
    expect(left,B.Int,span); expect(right,B.Int,span)
    return ctx:ordered(B.CheckedBinary(self,ctx:ref(ctx.effect),ctx:ref(left),ctx:ref(right)),B.Int,span)
end
A.Divide.apply=checked; A.Remainder.apply=checked
function A.BinaryOp:build(ctx,expression)
    local left=expression.left:build(ctx)
    if not left.type then gap(expression.left.span,'word values in data positions') end
    ctx:pin(left); local right=expression.right:build(ctx)
    ctx:unpin(); return self:apply(ctx,left,right,expression.span)
end
local function short(self,ctx,expression)
    local left=expression.left:build(ctx); expect(left,B.Bool,expression.span)
    local function rhs(child) local right=expression.right:build(child); expect(right,B.Bool,expression.span); return right end
    local function skip(child) return child:boolean(self==A.Or,expression.span) end
    return ctx:branch(left,self==A.And and rhs or skip,self==A.And and skip or rhs,B.Bool)
end
A.And.build=short; A.Or.build=short
function A.Binary:build(ctx) return self.operator:build(ctx,self) end
function A.Specialize:build(ctx)
    local builder=ctx.builder
    if not builder then gap(self.span,'word specialization requires a program builder') end
    return builder:specialize(ctx,self)
end
function A.Move:build(ctx)
    if not A.Name:isclassof(self.place) then gap(self.span,'partial moves') end
    return ctx:take(self.place.name,self.span)
end
function A.Borrow:build(ctx)
    if not A.Name:isclassof(self.place) then gap(self.span,'projected/indexed borrows') end
    local id,binding,cell=ctx:binding(self.place.name,self.span)
    if not binding.mutable then fail(self.span,'mutable borrow of immutable binding') end
    if not cell.initialized then fail(self.span,'borrow of uninitialized binding') end
    if not binding.address then gap(self.span,'address-taken locals') end
    ctx:access(id,true,self.span); local value=copy(cell.value); value.mode='mut'; value.origin=id; return value
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
            local owns=self:owns(fields[i].type)
            if owns and not (value.origin and self.module_preludes[value.origin]) then
                fail(span,'a module terminal may not construct new owned state; move an owned prelude into it')
            end
        end
    end
    local result=self:emit(B.Construct(self:refs(values),copy),L{B.Aggregate(declared,copy)},span)
    result.mode='fresh'
    return result
end

function Context:record_field(record,name,span)
    local fields=record.fields
    if not fields then fail(span,'this value has no members') end
    for index,field in ipairs(fields) do if field.name==name then return index,field end end
    fail(span,'no member ' .. name)
end

function A.PositionalAggregate:build(ctx)
    local values,fields=L(),{}
    for index,chain in ipairs(self.elements) do
        local value=chain_value(ctx,chain)
        if value.host then gap(self.span,'stored host words') end
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

-- A compile-time index, or nil when the index is only known at run time. `-7` is a
-- unary negation of a literal, so both spellings are recognized (§2.2).
local function constant_index(node)
    local negative=A.Unary:isclassof(node) and node.operator==A.Negate
    local operand=negative and node.operand or node
    if not A.Integer:isclassof(operand) then return nil end
    local value=tonumber(V.scalar.integer(operand.spelling,function(m) error(m,0) end))
    return negative and -value or value
end

-- The word identity lives in the type, so a bundle can always be rebuilt from a record.
-- That is what lets a stored word cross a block interface (a loop packet field, for
-- instance) and still be invoked. `writable` says whether the record has an owner that
-- can receive interior state back; a read-only view cannot.
function Context:ensure_word(record,span,writable)
    local type_=record.type
    if not B.Word:isclassof(type_) then return nil end
    for _,field in ipairs(type_.fields) do
        if field.mutable and not writable then
            gap(span,'invoking a word with mutable state through a read-only view')
        end
    end
    local template=self.builder and self.builder.resolved.templates[type_.template]
    if not template then gap(span,'word value with an unknown template') end
    local fields={}
    for i,field in ipairs(type_.fields) do
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
    local base=self.base:build(ctx)
    if base.host then gap(self.span,'projection requires a value') end
    local index,field=ctx:record_field(base.type,self.name,self.span)
    local value=ctx:emit(B.LoadField(ctx:ref(base),index-1),L{field.type},self.span)
    ctx:word_value(value,self.span,false)
    -- A projected non-Copy member is a read-only view: the aggregate still owns it.
    value.mode=field.type:copyable() and 'copy' or 'borrow'
    return value
end

-- §8.4: the index must be a non-negative Int below the known length. A constant index is
-- resolved statically; a dynamic one needs address-taken aggregate storage.
function A.Index:build(ctx)
    local base=self.base:build(ctx)
    if base.host then gap(self.span,'indexing requires a value') end
    local fields=base.type.fields
    if not fields then fail(self.span,'indexing requires an aggregate value') end
    local index=constant_index(self.index)
    if not index then gap(self.span,'dynamic positional indexing requires address-taken aggregate storage') end
    if index<0 or index>=#fields then
        fail(self.span,('index %d is outside the valid range 0..%d'):format(index,#fields-1))
    end
    local value=ctx:emit(B.LoadField(ctx:ref(base),index),L{fields[index+1].type},self.span)
    value.mode=fields[index+1].type:copyable() and 'copy' or 'borrow'
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
    ctx:constraint(self.constraint,value.type,self.span); ctx:accept_owned(value,self.span)
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
function A.Assign:assign_member(ctx)
    local place=self.place
    if not A.Name:isclassof(place.base) then gap(self.span,'assignment through a nested place') end
    local id,binding,cell=ctx:binding(place.base.name,self.span)
    if not cell.initialized then fail(self.span,'assignment to uninitialized binding ' .. binding.name) end
    ctx:access(id,true,self.span)
    local base=ctx:read(place.base.name,self.span)
    local index,field=ctx:record_field(base.type,place.name,self.span)
    -- §8.3: a member declared mut is an interior mutable place and stays writable through
    -- an immutable owning binding; otherwise the binding itself must be mutable.
    if not (binding.mutable or field.mutable) then
        fail(self.span,'assignment to an immutable member ' .. place.name)
    end
    local value=self.value:build(ctx)
    expect(value,field.type,self.span); ctx:accept_owned(value,self.span)
    ctx:pin(base); ctx:pin(value)
    -- §9.4: the old value is destroyed only once the right-hand side has completed.
    if ctx:owns(field.type) then
        ctx:destroy(ctx:emit(B.LoadField(ctx:ref(base),index-1),L{field.type},self.span),self.span)
    end
    local updated=ctx:emit(B.StoreField(ctx:ref(base),index-1,ctx:ref(value)),L{base.type},self.span)
    updated.mode='fresh'
    ctx.cells[id]={value=updated,initialized=true,alive=binding.owned}
    ctx:unpin(); ctx:unpin()
end

function A.Assign:build(ctx)
    if A.Project:isclassof(self.place) then return self:assign_member(ctx) end
    if not A.Name:isclassof(self.place) then gap(self.span,'indexed assignment') end
    local id,binding=ctx:binding(self.place.name,self.span)
    if not binding.mutable then fail(self.span,'assignment to immutable binding ' .. binding.name) end
    local value=self.value:build(ctx); expect(value,binding.type,self.span); ctx:accept_owned(value,self.span); ctx:access(id,true,self.span)
    ctx:pin(value)
    if binding.address then ctx:ordered(B.Store(ctx:ref(ctx.effect),ctx:ref(ctx.cells[id].value),ctx:ref(value)),nil,self.span)
    else ctx:release(id); ctx.cells[id]={value=value,initialized=true,alive=binding.owned} end
    ctx:unpin()
end

function A.Discard:build(ctx)
    local value=self.value:build(ctx)
    if value.host or value.mode=='mut' then gap(self.span,'discard of word/borrow values') end
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
    body:push(); body:statements(self.body)
    if not body.block.exit then
        body:pop(); local values={body.effect}
        for id=1,#ctx.fn.bindings do if ctx.cells[id] then
            if body.cells[id].initialized~=ctx.cells[id].initialized then gap(self.span,'loop ownership states that require initialization fixed-point analysis') end
            values[#values+1]=body.cells[id].value
            if ctx.fn.bindings[id].owned then local alive=body.cells[id].alive; values[#values+1]=type(alive)=='boolean' and body:boolean(alive,self.span) or alive end
        end end
        for _,pin in ipairs(body.pins) do values[#values+1]=pin end
        body.block.exit=B.Jump(B.Edge(header.id,body:refs(values)))
    end
    ctx:adopt(exit)
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
function Context:call(expression,tail)
    local callee=expression.word:build(self)
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
        expect(value,access==B.MutAccess and B.Address(parameter.type) or parameter.type,argument.span)
        if temporary then
            if tail then gap(argument.span,'tail invocation with a borrowed resource temporary') end
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
function A.Stage:entry(ctx,index,options)
    local type_=ctx:constraint(self.constraint,options.parameters and options.parameters[index],self.span)
    if not type_ then gap(self.span,'stage type inference from uses; supply a concrete parameter type') end
    local address=self.capability==A.Mut
    if address and not type_:copyable() then gap(self.span,'mutable borrowed resource stages') end
    ctx:validate_ownership(type_,self.span)
    local value=ctx:parameter(address and B.Address(type_) or type_,self.capability)
    local owned=not type_:copyable() and (self.capability==A.Own or self.capability==A.OwnMut)
    local external=address or (not owned and not type_:copyable())
    ctx:bind(self.name,value,self.capability==A.Mut or self.capability==A.OwnMut,owned,external,address,self.span)
end
function A.Prelude:entry() gap(self.binding.span,'stage preparation: preludes must run between arguments, not at terminal entry') end
function A.Chain:build_function(name,options)
    options=options or {}
    if not A.Body:isclassof(self.terminal) then gap(self.span,'data-terminal construction (not a runtime function)') end
    local fn={name=name,span=self.span,blocks={},bindings={},next_value=0,result=options.result,resources=options.resources or {},hosts=options.hosts or {},types={Int=B.Int,Bool=B.Bool,Unit=B.Unit,Text=B.Text}}
    for resource,descriptor in pairs(fn.resources) do
        assert(type(descriptor.destroy)=='string' and descriptor.destroy:match('^[A-Za-z_][A-Za-z_0-9]*$'),'resource requires a destructor symbol')
        fn.types[resource]=B.Named(resource)
    end
    for _,host in pairs(fn.hosts) do
        assert(host.phase=='runtime' and (host.purity=='ordered' or host.purity=='pure'),'host must declare runtime phase and purity')
        assert(type(host.symbol)=='string' and host.symbol:match('^[A-Za-z_][A-Za-z_0-9]*$'),'host requires a symbol')
        assert(B.Signature:isclassof(host.signature) and #host.signature.results==1,'host requires one Let result')
    end
    local ctx=setmetatable({fn=fn,locations={},cells={},scopes={},pins={},locks={}},Context)
    ctx.block=ctx:new_block(); ctx:push(); ctx.effect=ctx:parameter(B.Effect)
    for i,item in ipairs(self.items) do item:entry(ctx,i,options) end
    fn.self_visible=true; ctx:push()
    ctx:statements(self.terminal.statements)
    if not ctx.block.exit then ctx:finish(ctx:emit(B.UnitLiteral,L{B.Unit},self.span),self.span) end
    local blocks=L()
    for _,block in ipairs(fn.blocks) do assert(block.exit,'unfinished block'); blocks:insert(B.Block(block.parameters,block.instructions,block.exit)) end
    return B.Function(name,B.Signature(blocks[1].parameters,L{fn.result,B.Effect}),blocks):verify_flow(fn.hosts)
end
V.Build={Context=Context,expect=expect,fail=fail,gap=gap,copy=copy,literal=literal}
end

