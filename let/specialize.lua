-- Memoized recursive specialization. Known inputs stay known; widening is explicit.
local V=require('let.vocab')
local A,E,S,C,L=V.Syntax,V.Evaluation,V.Semantic,V.Residual,V.List
local D=require('let.domain')
local Program=require('let.program')
local M={}
local function pattern(values)
    local p={}
    for i,value in ipairs(values) do p[i]={known=E.Known:isclassof(value) and value or false,shape=value.shape,pointer=E.Place:isclassof(value),type=value:abi()} end
    return p
end
local function key(word,p) local parts={tostring(word)}; for _,slot in ipairs(p) do parts[#parts+1]=slot.known and slot.known:key() or '?' end; return table.concat(parts,'|') end
local function widen(p,ancestors)
    local result={}
    for i,slot in ipairs(p) do
        local known=slot.known
        for _,ancestor in ipairs(ancestors) do known=known and ancestor.pattern[i].known and known:same(ancestor.pattern[i].known) and known or false end
        result[i]={known=known,shape=slot.shape,pointer=slot.pointer,type=slot.type}
    end
    return result
end
function Program:helper(word,p)
    local k=key(word,p); if self.helpers[k] then return self.helpers[k] end
    local variants={}; for _,item in ipairs(self.queue) do if item.word==word then variants[#variants+1]=item end end
    if #variants>=self.specialization_limit then p=widen(p,variants); k=key(word,p); if self.helpers[k] then return self.helpers[k] end end
    self.next_function=self.next_function+1
    local item={word=word,pattern=p,id=self.next_function,key=k,name='letbody_' .. word .. '_' .. (#variants+1)}
    self.helpers[k]=item; self.queue:insert(item); return item
end
function E.Value:evaluate() return self end
function A.Stage:prepare(ctx,supply) ctx.env[self.name]=supply(self) end
function A.Prelude:prepare(ctx) self.binding:evaluate(ctx) end
function S.DataField:pack(ctx,value,values)
    if self.capability==S.Mut then values:insert(value); return end
    value=value:read(ctx); values:insert(self.shape:is_copy() and value or ctx:freeze(value))
    if self.capability:is_owned() and not self.shape:is_copy() then
        values:insert(ctx:freeze(ctx.state.owners[assert(value.owner)])); ctx:take(value)
    end
end
function S.WordField:pack(_,value,values) for _,bound in ipairs(value.bound) do values:insert(bound) end end
function S.HostField:pack() end
function S.DataField:unpack(ctx,next_value)
    local value=next_value()
    if self.capability==S.Mut then return value end
    if not self.shape:is_copy() then
        if self.capability:is_owned() then return ctx:adopt(self.shape,value:code(),next_value()) end
        return E.Resource(self.shape,value:code(),nil,false)
    end
    if self.capability==S.OwnMut then return ctx:cell(self.shape,value) end
    return value
end
function S.WordField:unpack(_,next_value) local bound=L(); for _=1,self.supplied do bound:insert(next_value()) end; return E.Word(self.word,bound) end
function S.HostField:unpack() return E.Host(self.host) end
local function globals(def)
    local env={}; for name,binding in pairs(def.env) do env[name]=binding.value:evaluation() end
    return env
end
local function scope() return {owners={}} end
function M.install(Context)
    local function decoded(ctx,slot,expression)
        if slot.pointer then
            local place=C.Deref(slot.shape:ctype(),expression)
            return ctx:cell(slot.shape,E.Dynamic(slot.shape,place),place)
        end
        return E.Dynamic(slot.shape,expression)
    end
    function Context:packet_code(value)
        if E.Place:isclassof(value) then return self:address(value) end
        return value:code()
    end
    function Context:unpack(def,values)
        local index=0; local function next_value() index=index+1; return assert(values[index]) end
        for _,field in ipairs(def.frame) do self.env[field.name]=field:unpack(self,next_value) end
    end
    function E.Word:prepare(caller,arguments)
        local def=caller.program.words[self.id]; local outer=globals(def)
        local callee=Context.new(caller.program,caller.fn,setmetatable({},{__index=outer}),caller.state)
        local args=Context.new(caller.program,caller.fn,caller.env,caller.state,scope())
        args.output,callee.output=caller.output,caller.output; args.continuation=caller.continuation
        local ordinal=0
        for _,item in ipairs(def.chain.items) do item:prepare(callee,function(stage)
            ordinal=ordinal+1; local value=self.bound[ordinal] or arguments[ordinal-#self.bound]:evaluate(args)
            if args.terminated then return nil end
            if stage.capability==S.Mut then return value end
            if stage.capability:is_owned() and not value.shape:is_copy() then value=args:take(value); return callee:adopt(value.shape,value:code()) end
            if stage.capability==S.OwnMut then return callee:cell(value.shape,value) end
            if E.Resource:isclassof(value) then return E.Resource(value.shape,value.expression,nil,false) end
            return value
        end)
            if args.terminated or callee.terminated then caller.terminated=true; return nil,args end
        end
        outer[def.self_name]=E.Word(self.id,L())
        local values=L(); for _,field in ipairs(def.frame) do field:pack(callee,callee.env[field.name],values) end
        return values,args
    end
    local function invalidate(ctx,values) for _,v in ipairs(values) do if E.Place:isclassof(v) then ctx:invalidate(v) end end end
    function E.Word:enter(caller,values,continuation,tail)
        local def=caller.program.words[self.id]
        local p=pattern(values); local k=key(self.id,p); local ancestors,candidate={},nil
        local cached=caller.program.constants[k]
        if cached then caller.program.cache_hits=(caller.program.cache_hits or 0)+1; return cached end
        for _,entry in ipairs(caller.fn.active) do if entry.word==self.id then ancestors[#ancestors+1]=entry; if entry.key==k then candidate=entry end end end
        if not candidate and #ancestors>0 and (#ancestors>=caller.program.specialization_limit or caller.program.fuel==0) then
            p=widen(p,ancestors); k=key(self.id,p)
            for _,entry in ipairs(ancestors) do if entry.key==k then candidate=entry end end
        end
        if candidate then
            if tail and candidate.continuation==continuation then
                candidate.used=true; local places,args=L(),L()
                for i,slot in ipairs(candidate.pattern) do if not slot.known then places:insert(candidate.places[i]); args:insert(caller:packet_code(values[i])) end end
                caller:emit(C.Jump(candidate.label,places,args)); return E.Stopped
            end
            local helper=caller.program:helper(self.id,p); local args=L()
            for i,slot in ipairs(helper.pattern) do if not slot.known then args:insert(caller:packet_code(values[i])) end end
            caller:before_effect()
            local result=caller:freeze(E.Dynamic(def.signature.result,C.Call(helper.id,args)))
            caller:after_effect(); invalidate(caller,values)
            return result
        end
        if def.recursive then caller.program.fuel=math.max(0,caller.program.fuel-1) end
        local outer=globals(def); outer[def.self_name]=E.Word(self.id,L())
        local body=Context.new(caller.program,caller.fn,setmetatable({},{__index=outer}),caller.state)
        body.continuation=continuation; body.destination=body:destination_()
        local entry={word=self.id,pattern=p,key=k,label=body:fresh(),places={},continuation=continuation}
        local inputs=L(); local setup=L()
        for i,slot in ipairs(p) do
            if slot.known then inputs:insert(slot.known)
            elseif def.recursive then
                local place=C.Local(slot.type,body:fresh()); entry.places[i]=place
                setup:insert(C.Assign(place,caller:packet_code(values[i]))); inputs:insert(decoded(body,slot,place))
            else inputs:insert(values[i]) end
        end
        caller.output:insertall(setup)
        if def.recursive then invalidate(caller,values) end -- packet pointers may alias these cells
        body:unpack(def,inputs)
        if def.recursive then caller.fn.active[#caller.fn.active+1]=entry end
        local flow=def.chain.terminal:evaluate(body)
        if def.recursive then caller.fn.active[#caller.fn.active]=nil end
        if entry.used then body.output:insert(1,C.Label(entry.label)) end
        local result=body:complete(flow,def.signature.result); caller.output:insertall(body.output)
        local all_known=true; for _,slot in ipairs(p) do if not slot.known then all_known=false end end
        -- No addresses/resources, no residual effects, and a known answer: replay is
        -- observationally empty. Never cache the result of an effectful invocation.
        if all_known and #body.output==0 and E.Known:isclassof(result) then caller.program.constants[k]=result end
        if def.recursive then invalidate(caller,values) end
        return result
    end
    function E.Word:invoke(caller,arguments,span,tail)
        local values,temps=self:prepare(caller,arguments)
        if not values then return E.Bottom(caller.program.words[self.id].signature.result) end
        local continuation=tail and caller.continuation or {}
        if tail then caller:cleanup() end
        local result=self:enter(caller,values,continuation,tail)
        if result~=E.Stopped then temps.output=caller.output; temps:cleanup() end
        local shape=caller.program.words[self.id].signature.result
        if result==E.Stopped then
            if tail then return result end
            caller.terminated=true; return E.Bottom(shape)
        end
        if not shape:is_copy() then return caller:adopt(shape,result:code()) end
        return result
    end
    function E.Host:invoke(ctx,arguments,span,tail)
        local host=ctx.program.hosts[self.id]
        local args=Context.new(ctx.program,ctx.fn,ctx.env,ctx.state,scope()); args.output=ctx.output; args.continuation=ctx.continuation
        local values,borrows=L(),{}
        for i,arg in ipairs(arguments) do
            local value=arg:evaluate(args); local cap=host.stages[i].capability
            if args.terminated then ctx.terminated=true; return E.Bottom(host.result) end
            if cap==S.Mut then values:insert(args:address(value)); borrows[#borrows+1]=value
            else if cap:is_owned() then value=args:take(value) end; values:insert(value:code()) end
        end
        if tail then ctx:cleanup() end
        local result
        ctx:before_effect()
        if host.result==S.Unit then ctx:emit(C.VoidCall(host.callable,values)); result=D.unit()
        else result=ctx:freeze(E.Dynamic(host.result,C.Call(host.callable,values))) end
        ctx:after_effect(); invalidate(ctx,borrows); args:cleanup()
        if not host.result:is_copy() then result=ctx:adopt(host.result,result:code()) end
        return result
    end
    local function new_function(program) return Context.new(program,{next=0,cells={},owners={},active={}}) end
    function Program:compile()
        local functions,manifest=L(),{}
        for index,export in ipairs(self.exports) do
            local ctx=new_function(self); ctx.continuation={}
            local word=export.word:evaluation(); local def=self.words[word.id]; local args,types=L(),L()
            for i=#word.bound+1,#def.stages do
                local shape,cap=def.signature.parameters[i],def.stages[i].capability
                local type_=cap:abi(shape); local expression=C.Argument(type_,#types+1); types:insert(type_)
                if cap==S.Mut then local place=C.Deref(shape:ctype(),expression); args:insert(ctx:cell(shape,E.Dynamic(shape,place),place))
                elseif not shape:is_copy() then args:insert(E.Resource(shape,expression,nil,true))
                else args:insert(E.Dynamic(shape,expression)) end
            end
            local result=word:invoke(ctx,args,export.span,false)
            if not ctx.terminated then result=ctx:take(result); ctx:cleanup(); ctx:emit(C.ReturnStmt(result:code())) end
            functions:insert(C.Function(index,'let_' .. export.name,true,false,types,def.signature.result:ctype(),C.SeqStmt(ctx.output)))
            manifest[export.name]={symbol='let_' .. export.name,result=def.signature.result,parameters=types}
        end
        functions:insertall(self.external)
        local index=1
        while index<=#self.queue do
            local item=self.queue[index]; local ctx=new_function(self); ctx.continuation={}
            local values,types=L(),L()
            for _,slot in ipairs(item.pattern) do
                if slot.known then values:insert(slot.known)
                else types:insert(slot.type); values:insert(decoded(ctx,slot,C.Argument(slot.type,#types))) end
            end
            local word=E.Word(item.word,L()); local result=word:enter(ctx,values,ctx.continuation,false)
            if result~=E.Stopped then ctx:emit(C.ReturnStmt(result:code())) end
            functions:insert(C.Function(item.id,item.name,false,false,types,self.words[item.word].signature.result:ctype(),C.SeqStmt(ctx.output)))
            index=index+1
        end
        local report={cache_hits=self.cache_hits or 0,constants=0,fuel_remaining=self.fuel,specializations={}}
        for _ in pairs(self.constants) do report.constants=report.constants+1 end
        for _,item in ipairs(self.queue) do
            local known,dynamic={},0
            for i,slot in ipairs(item.pattern) do if slot.known then known[i]=slot.known:key() else dynamic=dynamic+1 end end
            report.specializations[#report.specializations+1]={word=item.word,symbol=item.name,known=known,dynamic=dynamic}
        end
        return C.Module(functions),manifest,report
    end
end
return M

