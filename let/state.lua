-- Mutable abstract store. Cells/owners have identities; their values are immutable ASDL nodes.
local V=require('let.vocab')
local E,S,C,L=V.Evaluation,V.Semantic,V.Residual,V.List
local D=require('let.domain')
local Context={}; Context.__index=Context
local function copy(t) local r={}; for k,v in pairs(t) do r[k]=v end; return r end
function Context.new(program,fn,env,state,scope)
    return setmetatable({program=program,fn=fn,env=env or {},state=state or {cells={},owners={}},scope=scope or {owners={}},output=L()},Context)
end
function Context:fresh() self.fn.next=self.fn.next+1; return self.fn.next end
function Context:emit(s) self.output:insert(s) end
function Context:child(nested,fork)
    local env=nested and setmetatable({},{__index=self.env}) or self.env
    local state=fork and {cells=copy(self.state.cells),owners=copy(self.state.owners)} or self.state
    local child=Context.new(self.program,self.fn,env,state,nested and {owners={},parent=self.scope} or self.scope)
    child.destination,child.continuation=self.destination,self.continuation; return child
end
function Context:freeze(value)
    if E.Known:isclassof(value) then return value end
    local place=C.Local(value.shape:ctype(),self:fresh()); self:emit(C.Assign(place,value:code()))
    return E.Dynamic(value.shape,place)
end
function Context:cell(shape,value,location)
    local id=self:fresh(); self.fn.cells[id]={shape=shape,location=location or C.Local(shape:ctype(),id),escaped=location~=nil}
    self.state.cells[id]=value; return E.Place(shape,id)
end
function Context:get(place)
    local value=assert(self.state.cells[place.id])
    if not place.shape:is_copy() then return E.Resource(place.shape,self.fn.cells[place.id].location,nil,false) end
    return self.fn.cells[place.id].escaped and self:freeze(value) or value
end
function Context:address(place)
    local record=self.fn.cells[place.id]; local value=self.state.cells[place.id]
    if place.shape:is_copy() then self:emit(C.Assign(record.location,value:code())) end
    record.escaped=true; return C.Address(record.location)
end
function Context:invalidate(place)
    local r=self.fn.cells[place.id]; self.state.cells[place.id]=E.Dynamic(place.shape,r.location)
end
function Context:write(place,value)
    local r=self.fn.cells[place.id]
    if not place.shape:is_copy() then self:drop(self:get(place)); value=self:take(value) end
    if r.escaped or not place.shape:is_copy() then self:emit(C.Assign(r.location,value:code())) end
    self.state.cells[place.id]=value
end
function Context:adopt(shape,expression,alive)
    local slot=C.Local(shape:ctype(),self:fresh()); self:emit(C.Assign(slot,expression))
    local owner=self:fresh(); self.fn.owners[owner]={shape=shape,slot=slot,flag=C.Local(C.Bool,self:fresh())}
    self.scope.owners[#self.scope.owners+1]=owner; self.state.owners[owner]=alive or D.boolean(true)
    return E.Resource(shape,slot,owner,true)
end
function Context:mark(owner,value)
    self.state.owners[owner]=value; local r=self.fn.owners[owner]
    if r.flagged then self:emit(C.Assign(r.flag,value:code())) end
end
function Context:take(value)
    if E.Resource:isclassof(value) then
        if value.owner then self:mark(value.owner,D.boolean(false)) end
        return E.Resource(value.shape,value.expression,nil,true)
    end
    return value
end
function Context:before_effect()
    -- Unknown host effects can invalidate escaped storage. Synchronize abstract
    -- values first; private, unescaped cells remain entirely compile-time.
    for id,value in pairs(self.state.cells) do
        local record=self.fn.cells[id]
        if record.escaped and record.shape:is_copy() and (not E.Dynamic:isclassof(value) or value.expression~=record.location) then
            self:emit(C.Assign(record.location,value:code()))
        end
    end
end
function Context:after_effect()
    for id in pairs(self.state.cells) do
        local record=self.fn.cells[id]
        if record.escaped then self.state.cells[id]=E.Dynamic(record.shape,record.location) end
    end
end
function Context:drop(value)
    if not E.Resource:isclassof(value) then return end
    local alive=value.owner and self.state.owners[value.owner] or D.boolean(true)
    if alive:known()==false then return end
    self:before_effect()
    local call=C.VoidCall(assert(self.program.drop_ids[value.shape]),L{value.expression})
    if alive:known()==true then self:emit(call) else self:emit(C.IfStmt(alive:code(),C.SeqStmt(L{call}),C.SeqStmt(L()))) end
    self:after_effect()
    if value.owner then self:mark(value.owner,D.boolean(false)) end
end
function Context:cleanup_scope(scope)
    for i=#scope.owners,1,-1 do local owner=scope.owners[i]; local r=self.fn.owners[owner]; self:drop(E.Resource(r.shape,r.slot,owner,false)) end
end
function Context:cleanup() local scope=self.scope; while scope do self:cleanup_scope(scope); scope=scope.parent end end
function E.Value:read() return self end
function E.Place:read(ctx) return ctx:get(self) end
function E.Resource:read() return E.Resource(self.shape,self.expression,self.owner,false) end
function E.Place:borrow() return self end
function E.Resource:borrow(ctx)
    local record=self.owner and ctx.fn.owners[self.owner]
    if record and record.borrow then return record.borrow end
    local place=ctx:cell(self.shape,E.Dynamic(self.shape,self.expression),self.expression)
    if record then record.borrow=place end; return place
end
function E.Place:assign(ctx,value) ctx:write(self,value) end
function E.Resource:assign(ctx,value)
    ctx:drop(self); value=ctx:take(value); ctx:emit(C.Assign(self.expression,value:code())); ctx:mark(assert(self.owner),D.boolean(true))
end
function E.Dynamic:same(other) return E.Dynamic:isclassof(other) and self.shape==other.shape and self.expression==other.expression end
function Context:merge(a,al,b,bl)
    for _, domain in ipairs{'cells','owners'} do
        for id,value in pairs(self.state[domain]) do
            local av,bv=a.state[domain][id],b.state[domain][id]
            if al and bl then
                if av:same(bv) then self.state[domain][id]=av
                else
                    local record=domain=='cells' and self.fn.cells[id] or self.fn.owners[id]
                    local location=domain=='cells' and record.location or record.flag
                    if domain=='cells' then record.escaped=true else record.flagged=true end
                    a:emit(C.Assign(location,av:code())); b:emit(C.Assign(location,bv:code()))
                    self.state[domain][id]=E.Dynamic(domain=='cells' and record.shape or S.Bool,location)
                end
            elseif al then self.state[domain][id]=av elseif bl then self.state[domain][id]=bv end
        end
    end
end
function Context:finish(value)
    if self.terminated then return E.Stopped end
    value=self:take(value); self:cleanup(); return E.Returned(value)
end
function Context:destination_()
    return {label=self:fresh(),values=L(),returns={},entry={cells=copy(self.state.cells),owners=copy(self.state.owners)}}
end
-- Resolve continuation builders by reconstruction, never by mutating ASDL children.
function C.Stmt:only_exits() return false end
function C.Exit:only_exits(label) return self.label==label end
function C.SeqStmt:only_exits(label)
    for _,statement in ipairs(self.statements) do if not statement:only_exits(label) then return false end end
    return true
end
function C.IfStmt:only_exits(label) return self.yes:only_exits(label) and self.no:only_exits(label) end
function C.Stmt:seal() return self end
function C.PendingExit:seal(destination)
    assert(self.label==destination.label, 'unresolved foreign continuation')
    return C.SeqStmt(destination.returns[self.edge].output)
end
function C.SeqStmt:seal(destination) return C.SeqStmt(self.statements:map(function(s)return s:seal(destination)end)) end
function C.IfStmt:seal(destination) return C.IfStmt(self.condition,self.yes:seal(destination),self.no:seal(destination)) end
function C.WhileStmt:seal(destination) return C.WhileStmt(self.test:seal(destination),self.condition,self.body:seal(destination)) end
function C.Region:seal(destination) return C.Region(self.label,self.result,self.body:seal(destination)) end
function Context:send(flow)
    if E.Returned:isclassof(flow) then
        local output=L()
        self.destination.values:insert(flow.value)
        local returns=self.destination.returns
        returns[#returns+1]={output=output,state={cells=copy(self.state.cells),owners=copy(self.state.owners)},value=flow.value}
        self:emit(C.PendingExit(self.destination.label,#returns))
    end
end
function Context:complete(flow,shape)
    if flow==E.Continue then flow=self:finish(D.unit()) end
    local values=self.destination.values
    if #values==0 and E.Returned:isclassof(flow) then return flow.value end
    if E.Returned:isclassof(flow) then self:send(flow) end
    -- A return is not a dead state at a call boundary: its mutations reach the
    -- caller. Join all returning paths before closing their residual exits.
    local returns=self.destination.returns
    if #returns>0 then
        for _,domain in ipairs{'cells','owners'} do
            for id in pairs(self.destination.entry[domain]) do
                local value=returns[1].state[domain][id]; local same=true
                for i=2,#returns do if not value:same(returns[i].state[domain][id]) then same=false end end
                if same then self.state[domain][id]=value
                else
                    local record=domain=='cells' and self.fn.cells[id] or self.fn.owners[id]
                    local place=domain=='cells' and record.location or record.flag
                    if domain=='cells' then record.escaped=true else record.flagged=true end
                    for _,exit in ipairs(returns) do exit.output:insert(C.Assign(place,exit.state[domain][id]:code())) end
                    self.state[domain][id]=E.Dynamic(domain=='cells' and record.shape or S.Bool,place)
                end
            end
        end
        for _,exit in ipairs(returns) do exit.output:insert(C.Exit(self.destination.label,exit.value:code())) end
    end
    self.output=self.output:map(function(statement) return statement:seal(self.destination) end)
    local value=values[1]
    local known=value and E.Known:isclassof(value)
    for i=2,#values do known=known and value:same(values[i]) end
    if known and C.SeqStmt(self.output):only_exits(self.destination.label) then self.output=L(); return value end
    if #values>0 then
        self.output=L{C.Region(self.destination.label,not known and shape:ctype() or nil,C.SeqStmt(self.output))}
        return known and value or E.Dynamic(shape,C.Local(shape:ctype(),self.destination.label))
    end
    return E.Stopped
end
return Context

