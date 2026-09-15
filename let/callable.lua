-- Structural continuation contracts. Mutable unification terms stay in the solver.
local V=require('let.vocab')
local S,I,L=V.Semantic,V.Analysis,V.List
local fail=require('let.lexer').fail
local M={}
function S.Shape:resolved() return true end
function S.Unknown:resolved() return false end
function S.Executable:resolved()
    if not self.signature or #self.capabilities~=#self.signature.parameters then return false end
    if not self.signature.result:resolved() then return false end
    for _,shape in ipairs(self.signature.parameters) do if not shape:resolved() then return false end end
    return true
end
function M.install(Solver)
    function Solver:callable(id,span,arity,minimum)
        local cell=self.cells[self:root(id)]
        if cell.shape or cell.data_only then
            fail(span,arity~=nil and 'invocation requires a runtime word' or minimum~=nil and 'specialization requires a word' or 'expected Executable word')
        end
        cell.executable=true
        if not cell.fn then cell.fn={parameters=L(),result=self:fresh(),caps={}} end
        local fn=cell.fn
        if arity then
            if fn.arity and fn.arity~=arity then fail(span,'continuation invocation must exactly saturate remaining stages') end
            if #fn.parameters>arity then fail(span,'oversaturated continuation specialization') end
            fn.arity=arity
        end
        local count=math.max(arity or 0,minimum or 0,#fn.parameters)
        if fn.arity and count>fn.arity then fail(span,'oversaturated continuation specialization') end
        while #fn.parameters<count do fn.parameters:insert(self:fresh()) end
        return fn
    end
    function Solver:function_type(parameters,result,caps)
        local id=self:fresh(); self.cells[id].executable=true
        self.cells[id].fn={parameters=parameters,result=result,arity=#parameters,caps=caps or {}}
        return id
    end
    function Solver:merge_functions(x,y,span)
        if not y.fn then return end
        if not x.fn then x.fn=y.fn; return end
        local a,b=x.fn,y.fn
        a.targets=a.targets or {}; for word in pairs(b.targets or {}) do a.targets[word]=true end
        if a.arity and b.arity and a.arity~=b.arity then fail(span,'continuation arity mismatch') end
        local n=math.max(#a.parameters,#b.parameters)
        a.arity=a.arity or b.arity
        if a.arity and n>a.arity then fail(span,'oversaturated continuation specialization') end
        for i=1,n do
            if not a.parameters[i] then a.parameters:insert(self:fresh()) end
            if b.parameters[i] then self:unify(a.parameters[i],b.parameters[i],span) end
            if a.caps[i] and b.caps[i] and a.caps[i]~=b.caps[i] then fail(span,'continuation capability mismatch') end
            a.caps[i]=a.caps[i] or b.caps[i]
        end
        self:unify(a.result,b.result,span,'inconsistent continuation result shapes')
    end
    function Solver:recursion()
        local graph={}
        for _,call in ipairs(self.calls) do if call.caller then
            graph[call.caller]=graph[call.caller] or {}
            if call.word then graph[call.caller][call.word]=true
            else local fn=self.cells[self:root(call.type)].fn; for word in pairs(fn and fn.targets or {}) do graph[call.caller][word]=true end end
        end end
        for id,definition in ipairs(self.program.words) do
            local seen={}
            local function reaches(word)
                if seen[word] then return false end; seen[word]=true
                for next_ in pairs(graph[word] or {}) do if next_==id or reaches(next_) then return true end end
                return false
            end
            definition.recursive=reaches(id)
        end
    end
    function Solver:suffix(id,supplied,span)
        self:callable(id,span,nil,supplied)
        local target=self:fresh(); self:callable(target,span)
        self.links[#self.links+1]={source=id,supplied=supplied,target=target,span=span}
        return target
    end
    function Solver:link_suffixes()
        for _=1,#self.links+1 do for _,link in ipairs(self.links) do
            local a=self:callable(link.source,link.span,nil,link.supplied)
            local b=self:callable(link.target,link.span)
            if a.arity then b=self:callable(link.target,link.span,a.arity-link.supplied)
            elseif b.arity then a=self:callable(link.source,link.span,b.arity+link.supplied) end
            a=self:callable(link.source,link.span,nil,link.supplied+#b.parameters)
            for i,parameter in ipairs(b.parameters) do
                self:unify(a.parameters[link.supplied+i],parameter,link.span)
                local cap=a.caps[link.supplied+i]
                if cap and b.caps[i] and cap~=b.caps[i] then fail(link.span,'continuation capability mismatch') end
                b.caps[i]=b.caps[i] or cap; a.caps[link.supplied+i]=cap or b.caps[i]
            end
            self:unify(a.result,b.result,link.span)
            a.targets=a.targets or {}; b.targets=b.targets or {}
            for word in pairs(a.targets) do b.targets[word]=true end
            for word in pairs(b.targets) do a.targets[word]=true end
        end end
    end
    function Solver:shape(id,span,visiting)
        id=self:root(id); local cell=self.cells[id]
        if cell.shape then return cell.shape end
        if not cell.executable then return S.Unknown end
        if not cell.fn or not cell.fn.arity then return S.Executable(nil,L()) end
        visiting=visiting or {}; if visiting[id] then fail(span,'recursive continuation shapes are not supported') end
        visiting[id]=true
        local fn=cell.fn; local params,caps=L(),L(); local complete=true
        for i=1,fn.arity do
            params:insert(self:shape(fn.parameters[i],span,visiting))
            if fn.caps[i] then caps:insert(fn.caps[i]) else complete=false end
        end
        local result=self:shape(fn.result,span,visiting); visiting[id]=nil
        return S.Executable(S.Signature(params,result),complete and caps or L())
    end
end
function I.Scalar:argument_type() return self.type end
function I.Partial:argument_type(solver,span) return solver:suffix(self.type,self.supplied,span) end
function I.Partial:scalar(span) fail(span,'expected scalar value, got word') end
function I.Word:argument_type(solver)
    local def=solver.program.words[self.id]; local params,caps=L(),{}
    for i=self.supplied+1,#def.stages do params:insert(solver.parameters[self.id][i]); caps[#caps+1]=def.stages[i].capability end
    local type_=solver:function_type(params,solver.results[self.id],caps)
    solver.cells[type_].fn.targets={[self.id]=true}; return type_
end
function I.Host:argument_type(solver)
    local host=solver.program.hosts[self.id]; local params,caps=L(),{}
    for _,stage in ipairs(host.stages) do params:insert(solver:fresh(stage.shape)); caps[#caps+1]=stage.capability end
    return solver:function_type(params,solver:fresh(host.result),caps)
end
function I.Scalar:specialize(ctx,argument,span)
    local fn=ctx.solver:callable(self.type,span,nil,1)
    ctx.solver:unify(fn.parameters[1],argument:argument_type(ctx.solver,span),span)
    return I.Partial(self.type,1)
end
function I.Partial:specialize(ctx,argument,span)
    local fn=ctx.solver:callable(self.type,span,nil,self.supplied+1)
    ctx.solver:unify(fn.parameters[self.supplied+1],argument:argument_type(ctx.solver,span),span)
    return I.Partial(self.type,self.supplied+1)
end
function I.Partial:invoke(ctx,arguments,span)
    local fn=ctx.solver:callable(self.type,span,self.supplied+#arguments)
    ctx.solver.calls[#ctx.solver.calls+1]={caller=ctx.word,type=self.type}
    for i,arg in ipairs(arguments) do ctx.solver:unify(fn.parameters[self.supplied+i],arg:infer(ctx):argument_type(ctx.solver,span),span) end
    return I.Scalar(fn.result)
end
function I.Scalar:invoke(ctx,arguments,span) return I.Partial(self.type,0):invoke(ctx,arguments,span) end
function I.Partial:resolve_field(solver,field)
    local type_=self:argument_type(solver,field.span); solver:link_suffixes()
    return S.ContinuationField(solver:shape(type_,field.span),field.name,field.capability,field.span)
end
return M

