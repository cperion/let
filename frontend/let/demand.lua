-- Required scalar knowledge uses verified VM execution. This module only follows
-- existing IR definitions; it does not evaluate arithmetic, conversions or calls.
local S=require('let.schema')
local IR=require('let.ir')
local D=require('let.diag')
local M={}
local Session={};Session.__index=Session
local I,L=S.Ir,S.ASDL.List

function M.open(options)
    options=options or {}
    if type(options)~='table' then D.reject('compile-input','Source execution options must be a table') end
    if options.staticOptimize~=nil and type(options.staticOptimize)~='boolean' then D.reject('static-option','staticOptimize must be boolean') end
    local mode=options.staticMode
    if mode~=nil and mode~='interpreted' and mode~='threaded' and mode~='eager' and mode~='lazy' then
        D.reject('execution-policy','Unknown source static execution mode '..tostring(mode))
    end
    return setmetatable({mode=mode,optimize=options.staticOptimize~=false,serial=0,queries={}},Session)
end
function Session:close()
    if self.vm then self.vm:close();self.vm=nil end
end

-- Dependency discovery is state-independent only for immutable scalar definitions.
-- Reads, addresses and dynamic effects have no scalar snapshot transport contract.
local function fragment(context, expression)
    local ordered,seen,visiting={},{},{}
    local visit
    visit=function(expr)
        if expr.kind=='Const' then return true end
        if expr.kind=='Ref' then
            local value=context.values[expr.value]
            local producer=value and value.producer
            if not producer then return false end
            if seen[producer] then return true end
            if visiting[producer] then return false end
            visiting[producer]=true
            local ok=true
            if producer.kind=='Let' then ok=visit(producer.expr)
            elseif producer.kind=='Call' then
                for _,arg in ipairs(producer.arguments) do
                    if arg.kind~='ValueArg' or not visit(arg.value) then ok=false;break end
                end
            else ok=false end
            visiting[producer]=nil
            if not ok then return false end
            seen[producer]=true;ordered[#ordered+1]=producer
            return true
        end
        if expr.kind~='Un' and expr.kind~='Bin' and expr.kind~='Convert' then return false end
        local ok=true;expr:each(function(child) if not visit(child) then ok=false end end)
        return ok
    end
    if not visit(expression) then return nil end
    return ordered
end

function Session:known(context, expression)
    return fragment(context,expression)~=nil
end

function Session:require(context, expression, resolve, origin)
    if expression.kind=='Const' then return expression end
    local statements=fragment(context,expression)
    if not statements then D.reject('static-required','Required value depends on runtime storage or input',origin and origin.span) end
    -- Aliases of literals do not need a VM merely to establish their identity.
    local current=expression
    local aliases={}
    while current.kind=='Ref' and not aliases[current.value] do
        aliases[current.value]=true
        local value=context.values[current.value]
        if not value or not value.producer or value.producer.kind~='Let' then break end
        current=value.producer.expr
    end
    if current.kind=='Const' then return current end
    if not self.mode then D.reject('execution-policy','Required source value needs an explicit staticMode',origin and origin.span) end
    local byContext=self.queries[context]
    if not byContext then byContext={};self.queries[context]=byContext end
    local previous=byContext[expression]
    if previous then
        if previous.state=='Ready' then return previous.value end
        D.reject('static-cycle','Static value demand depends on itself',origin and origin.span)
    end
    local query={state='Waiting'};byContext[expression]=query
    local ok,result=pcall(function()
        local functions,seen={},{}
        local include
        include=function(id)
            if seen[id] then return end
            seen[id]=true
            local fn=resolve(id)
            if not fn then D.reject('static-foreign','Static computation cannot call foreign or unavailable word '..id,origin and origin.span) end
            functions[#functions+1]=fn
            local function inspect(stmt)
                if stmt.kind=='Call' then include(stmt.target)
                elseif stmt.kind=='View' then include(stmt.entry) end
                stmt:each(inspect)
            end
            for _,stmt in ipairs(fn.body) do inspect(stmt) end
        end
        for _,stmt in ipairs(statements) do if stmt.kind=='Call' then include(stmt.target) end end
        self.serial=self.serial+1
        local name='__let_static_demand_'..self.serial
        local body={} for _,stmt in ipairs(statements) do body[#body+1]=stmt end
        body[#body+1]=I.Return(L{expression})
        local fn=I.Fn(name,I.Entry,0,L{},L{expression.type},L{},L(body))
        functions[#functions+1]=fn
        require('let.check').program(functions)
        local artifact=require('let.abc').lower(functions,{profile='slet',exports={name}})
        if not self.vm then self.vm=require('let.stage').open{mode=self.mode,optimize=self.optimize} end
        local executed=self.vm:prepare(artifact,functions):call{entry=name}
        local constant
        if expression.type==S.unit then constant=IR.builder():const(S.unit,I.UInt(0))
        else constant=require('let.specialize').constant(IR.builder(),executed.values[1],expression.type) end
        constant.span=origin and origin.span
        return constant
    end)
    if not ok then byContext[expression]=nil;error(result,0) end
    query.state='Ready';query.value=result
    context:value(expression,expression.type).knowledge={kind='Exact',value=result}
    return result
end

return M
