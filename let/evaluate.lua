-- Source evaluation over an explicit binding-time domain and abstract store.
local V=require('let.vocab')
local A,E,S,C,L=V.Syntax,V.Evaluation,V.Semantic,V.Residual,V.List
local D=require('let.domain')
local Context=require('let.state')
local fail=require('let.lexer').fail
local function lookup(ctx,name,span) local v=ctx.env[name]; if not v then fail(span,'unknown name ' .. name) end; return v end
function Context:sequence(statements)
    for _, statement in ipairs(statements) do
        local flow=statement:evaluate(self)
        if self.terminated then return E.Stopped end
        if flow~=E.Continue then return flow end
    end
    return E.Continue
end
function A.Integer:evaluate() local hi,lo=self:parts(false); return E.Known(S.Int,E.Bits(hi,lo)) end
function A.Boolean:evaluate() return D.boolean(self.value) end
function A.Unit:evaluate() return D.unit() end
function A.Name:evaluate(ctx) return lookup(ctx,self.name,self.span):read(ctx) end
function A.Borrow:evaluate(ctx) return lookup(ctx,self.name,self.span):borrow(ctx) end
function A.Move:evaluate(ctx)
    local value=lookup(ctx,self.name,self.span):read(ctx)
    if E.Resource:isclassof(value) then
        local frozen=ctx:freeze(value); ctx:take(value); return E.Resource(value.shape,frozen.expression,nil,true)
    end
    return value
end
function A.Unary:evaluate(ctx)
    local value
    if self.operator=='-' and A.Integer:isclassof(self.operand) then local hi,lo=self.operand:parts(true); value=E.Known(S.Int,E.Bits(hi,lo))
    else value=self.operand:evaluate(ctx) end
    if ctx.terminated then return value end
    if self.operator=='not' then return value:binary(ctx,'==',D.boolean(false)) end
    return D.integer(0):binary(ctx,'-',value)
end
local function joined_value(ctx,a,av,b,bv)
    if av:same(bv) then return av end
    local slot=C.Local(av.shape:ctype(),ctx:fresh())
    a:emit(C.Assign(slot,av:code())); b:emit(C.Assign(slot,bv:code()))
    return E.Dynamic(av.shape,slot)
end
function A.Binary:evaluate(ctx)
    local left=self.left:evaluate(ctx); local op=self.operator
    if ctx.terminated then return left end
    if op~='and' and op~='or' then
        local right=self.right:evaluate(ctx); if ctx.terminated then return right end
        return left:binary(ctx,op,right)
    end
    local known=left:known()
    if known~=nil then
        if (op=='and' and not known) or (op=='or' and known) then return left end
        return self.right:evaluate(ctx)
    end
    local right,skip=ctx:child(false,true),ctx:child(false,true)
    local value=self.right:evaluate(right)
    if right.terminated then
        ctx:merge(right,false,skip,true)
        ctx:emit(C.IfStmt(left:code(),C.SeqStmt(op=='and' and right.output or skip.output),C.SeqStmt(op=='and' and skip.output or right.output)))
        return D.boolean(op=='or')
    end
    local result
    if value:known()~=nil then
        result=value:known()==(op=='and') and left or value
    else result=joined_value(ctx,right,value,skip,D.boolean(op=='or')) end
    ctx:merge(right,true,skip,true)
    if #right.output>0 or #skip.output>0 then
        ctx:emit(C.IfStmt(left:code(),C.SeqStmt(op=='and' and right.output or skip.output),C.SeqStmt(op=='and' and skip.output or right.output)))
    end
    return result
end
function E.Word:specialize(ctx,value,span)
    local def=ctx.program.words[self.id]
    if def.has_preludes then fail(span,'persistent specialization with preludes is not supported yet') end
    local bound=L(); bound:insertall(self.bound); bound:insert(value); return E.Word(self.id,bound)
end
function A.Specialize:evaluate(ctx)
    local word=self.word:evaluate(ctx); if ctx.terminated then return word end
    local argument=self.argument:evaluate(ctx); if ctx.terminated then return argument end
    return word:specialize(ctx,argument,self.span)
end
function A.Invoke:evaluate(ctx)
    local word=self.word:evaluate(ctx); if ctx.terminated then return word end
    return word:invoke(ctx,self.arguments,self.span,false)
end
function A.Expr:tail(ctx) return ctx:finish(self:evaluate(ctx)) end
function A.Invoke:tail(ctx)
    local word=self.word:evaluate(ctx); if ctx.terminated then return E.Stopped end
    local value=word:invoke(ctx,self.arguments,self.span,true)
    return value==E.Stopped and E.Stopped or ctx:finish(value)
end
function A.Data:evaluate(ctx) return self.value:evaluate(ctx) end
function A.Chain:evaluate(ctx) return self.terminal:evaluate(ctx) end
function A.Binding:evaluate(ctx)
    local value=self.value:evaluate(ctx); if ctx.terminated then return end
    if self.mutable and value.shape:is_copy() then value=ctx:cell(value.shape,value)
    elseif E.Resource:isclassof(value) then
        if not value.owner then value=ctx:adopt(value.shape,value:code()) end
        value=value:read(ctx)
    end
    ctx.env[self.name]=value
end
function A.Local:evaluate(ctx) self.binding:evaluate(ctx); return E.Continue end
function A.Assign:evaluate(ctx)
    local value=self.value:evaluate(ctx); if ctx.terminated then return E.Stopped end
    lookup(ctx,self.name,self.span):assign(ctx,value); return E.Continue
end
function A.Return:evaluate(ctx) return self.value and self.value:tail(ctx) or ctx:finish(D.unit()) end
function A.Discard:evaluate(ctx)
    local value=self.value:evaluate(ctx); if E.Resource:isclassof(value) and value.fresh then ctx:drop(value) end
    return E.Continue
end
function A.If:evaluate(ctx)
    local condition=self.condition:evaluate(ctx); if ctx.terminated then return E.Stopped end
    local known=condition:known()
    if known~=nil then
        local branch=ctx:child(true,false); local flow=branch:sequence(known and self.yes or self.no)
        ctx.terminated=branch.terminated
        if flow==E.Continue then branch:cleanup_scope(branch.scope) end
        ctx.output:insertall(branch.output); return flow
    end
    local yes,no=ctx:child(true,true),ctx:child(true,true)
    local yf,nf=yes:sequence(self.yes),no:sequence(self.no)
    local yl,nl=yf==E.Continue,nf==E.Continue
    if yl then yes:cleanup_scope(yes.scope) else yes:send(yf) end
    if nl then no:cleanup_scope(no.scope) else no:send(nf) end
    ctx:merge(yes,yl,no,nl)
    if #yes.output>0 or #no.output>0 then ctx:emit(C.IfStmt(condition:code(),C.SeqStmt(yes.output),C.SeqStmt(no.output))) end
    return (yl or nl) and E.Continue or E.Stopped
end
-- Conservative source footprint for loop-carried mutable cells. Calls can mutate
-- caller cells only through visible borrows; local shadowing is tracked explicitly.
function A.Expr:footprint() end
function A.Stmt:footprint() end
local function mark(ctx,name,set,shadow)
    local value=not shadow[name] and ctx.env[name]
    if value and E.Place:isclassof(value) then set[value.id]=value end
end
function A.Borrow:footprint(ctx,set,shadow) mark(ctx,self.name,set,shadow) end
function A.Unary:footprint(ctx,set,shadow) self.operand:footprint(ctx,set,shadow) end
function A.Binary:footprint(ctx,set,shadow) self.left:footprint(ctx,set,shadow); self.right:footprint(ctx,set,shadow) end
function A.Specialize:footprint(ctx,set,shadow) self.word:footprint(ctx,set,shadow); self.argument:footprint(ctx,set,shadow) end
function A.Invoke:footprint(ctx,set,shadow)
    self.word:footprint(ctx,set,shadow); for _, arg in ipairs(self.arguments) do arg:footprint(ctx,set,shadow) end
end
function A.Data:footprint(ctx,set,shadow) self.value:footprint(ctx,set,shadow) end
function A.Chain:footprint(ctx,set,shadow) self.terminal:footprint(ctx,set,shadow) end
function A.Local:footprint(ctx,set,shadow) self.binding.value:footprint(ctx,set,shadow); shadow[self.binding.name]=true end
function A.Assign:footprint(ctx,set,shadow) mark(ctx,self.name,set,shadow); self.value:footprint(ctx,set,shadow) end
function A.Return:footprint(ctx,set,shadow) if self.value then self.value:footprint(ctx,set,shadow) end end
function A.Discard:footprint(ctx,set,shadow) self.value:footprint(ctx,set,shadow) end
local function scan(statements,ctx,set,shadow)
    local nested={}; for k,v in pairs(shadow) do nested[k]=v end
    for _, statement in ipairs(statements) do statement:footprint(ctx,set,nested) end
end
function A.If:footprint(ctx,set,shadow) self.condition:footprint(ctx,set,shadow); scan(self.yes,ctx,set,shadow); scan(self.no,ctx,set,shadow) end
function A.While:footprint(ctx,set,shadow) self.condition:footprint(ctx,set,shadow); scan(self.body,ctx,set,shadow) end
function A.While:evaluate(ctx)
    -- Bounded static execution. Effects are appended as residual statements, never run.
    for _=1,ctx.program.specialization_limit do
        local trial=ctx:child(true,true); local condition=self.condition:evaluate(trial)
        if trial.terminated then ctx.output:insertall(trial.output); ctx.terminated=true; return E.Stopped end
        if condition:known()==nil or (condition:known() and ctx.program.fuel==0) then break end
        ctx.state.cells,ctx.state.owners=trial.state.cells,trial.state.owners; ctx.output:insertall(trial.output)
        if not condition:known() then return E.Continue end
        ctx.program.fuel=ctx.program.fuel-1
        local step=ctx:child(true,false); local flow=step:sequence(self.body)
        if flow==E.Continue then step:cleanup_scope(step.scope) end
        ctx.output:insertall(step.output); if flow~=E.Continue then return flow end
    end
    local writes={}; self:footprint(ctx,writes,{})
    for id,place in pairs(writes) do if place.shape:is_copy() then
        local r=ctx.fn.cells[id]; ctx:emit(C.Assign(r.location,ctx.state.cells[id]:code())); r.escaped=true; ctx:invalidate(place)
    end end
    local loop=ctx:child(true,true); local test=loop:child(false,false)
    local condition=self.condition:evaluate(test)
    if test.terminated then ctx:emit(C.WhileStmt(C.SeqStmt(test.output),C.Boolean(false),C.SeqStmt(L()))); return E.Stopped end
    local flow=loop:sequence(self.body)
    if flow==E.Continue then loop:cleanup_scope(loop.scope) else loop:send(flow) end
    ctx:emit(C.WhileStmt(C.SeqStmt(test.output),condition:code(),C.SeqStmt(loop.output)))
    if condition:known()==true then return E.Stopped end
    return E.Continue
end
function A.Body:evaluate(ctx) return ctx:sequence(self.statements) end
require('let.specialize').install(Context)
return Context

