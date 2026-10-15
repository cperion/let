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
    return setmetatable({mode=mode,optimize=options.staticOptimize~=false,serial=0,queries={},moduleData={},moduleOrder={}},Session)
end
function Session:close()
    if self.vm then self.vm:close();self.vm=nil end
end

function Session:installRoot(root,bytes)
    if not self.moduleData[root] then self.moduleOrder[#self.moduleOrder+1]=root end
    self.moduleData[root]=S.Ir.ModuleData(root,bytes)
end
function Session:data()
    local data={};for index,root in ipairs(self.moduleOrder) do data[index]=self.moduleData[root] end
    return data
end

-- Dependency discovery is state-independent only for immutable scalar definitions.
-- Reads, addresses and dynamic effects have no scalar snapshot transport contract.
local function fragment(context, expression)
    -- Module initializers own a complete ordered effect fragment. It is never
    -- reconstructed from fields or executed on a host-language heap.
    if context.initializerBody then
        local body={};for _,stmt in ipairs(context.initializerBody) do body[#body+1]=stmt end
        return body
    end
    local ordered,seen,visiting={},{},{}
    local pendingCapture=false
    local visit
    visit=function(expr)
        if expr.kind=='Const' then return true end
        if expr.kind=='Ref' then
            local value=context.values[expr.value]
            local producer=value and value.producer
            if not producer then return false end
            if producer.capturePending then pendingCapture=true;return false end
            if seen[producer] then return true end
            if visiting[producer] then return false end
            visiting[producer]=true
            local ok=true
            if producer.kind=='Let' then ok=visit(producer.expr)
            elseif producer.kind=='Call' then
                for _,arg in ipairs(producer.arguments) do
                    if arg.kind~='ValueArg' or not visit(arg.value) then ok=false;break end
                end
            elseif producer.kind=='ConstructVariant' then ok=not producer.payload or visit(producer.payload)
            elseif producer.kind=='Read' then
                local base=producer.place
                while base.kind=='Project' do base=base.base end
                ok=base.kind=='Global'
            else ok=false end
            visiting[producer]=nil
            if not ok then return false end
            seen[producer]=true;ordered[#ordered+1]=producer
            return true
        end
        if expr.kind~='Un' and expr.kind~='Bin' and expr.kind~='Convert' and expr.kind~='Make' and expr.kind~='Get' then return false end
        local ok=true;expr:each(function(child) if not visit(child) then ok=false end end)
        return ok
    end
    if not visit(expression) then return nil,pendingCapture end
    return ordered
end

function Session:known(context, expression)
    return fragment(context,expression)~=nil
end

function Session:require(context, expression, resolve, origin)
    return self:requireValues(context,{expression},resolve,origin)[1]
end

-- One accepted execution publishes a whole initializer result vector. Scalar
-- demands are the one-component form of this same verified VM boundary.
function Session:requireValues(context, expressions, resolve, origin)
    local statements,seen,constants={},{},{}
    local literals=true
    for index,expression in ipairs(expressions) do
        local part,pendingCapture=fragment(context,expression)
        if not part then
            if pendingCapture then D.reject('static-cycle','Required value depends on an unfinished capture contract',origin and origin.span) end
            D.reject('static-required','Required value depends on runtime storage or input',origin and origin.span)
        end
        for _,stmt in ipairs(part) do if not seen[stmt] then seen[stmt]=true;statements[#statements+1]=stmt end end
        local current,aliases=expression,{}
        while current.kind=='Ref' and not aliases[current.value] do
            aliases[current.value]=true
            local value=context.values[current.value]
            if not value or not value.producer or value.producer.kind~='Let' then break end
            current=value.producer.expr
        end
        constants[index]=current
        if current.kind~='Const' then literals=false end
    end
    if literals and not (context.initializerBody and #context.initializerBody>0) then return constants end
    local queryKey=#expressions==1 and expressions[1] or expressions
    if not self.mode then D.reject('execution-policy','Required source value needs an explicit staticMode',origin and origin.span) end
    local byContext=self.queries[context]
    if not byContext then byContext={};self.queries[context]=byContext end
    local previous=byContext[queryKey]
    if previous then
        if previous.state=='Ready' then return previous.value end
        D.reject('static-cycle','Static value demand depends on itself',origin and origin.span)
    end
    local query={state='Waiting'};byContext[queryKey]=query
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
                if stmt.capturePending then D.reject('static-cycle','Required word depends on an unfinished capture contract',origin and origin.span) end
                if stmt.kind=='Call' then include(stmt.target)
                elseif stmt.kind=='View' then include(stmt.entry) end
                stmt:each(inspect)
            end
            for _,stmt in ipairs(fn.body) do inspect(stmt) end
        end
        local function dependencies(stmt)
            if stmt.kind=='Call' then include(stmt.target) elseif stmt.kind=='View' then include(stmt.entry) end
            stmt:each(dependencies)
        end
        for _,stmt in ipairs(statements) do dependencies(stmt) end
        self.serial=self.serial+1
        local name='__let_static_demand_'..self.serial
        local body={} for _,stmt in ipairs(statements) do body[#body+1]=stmt end
        local types={} for index,expression in ipairs(expressions) do types[index]=expression.type end
        body[#body+1]=I.Return(L(expressions))
        local fn=I.Fn(name,I.Entry,0,L{},L(types),L{},L(body))
        functions[#functions+1]=fn
        functions.moduleData=self:data()
        local program=require('let.program').analyze(functions)
        local artifact=require('let.abc').lower(program,{profile='slet',exports={name}})
        if not self.vm then self.vm=require('let.stage').open{mode=self.mode,optimize=self.optimize} end
        local executed=self.vm:prepare(artifact,functions):call{entry=name}
        local constants={}
        for index,expression in ipairs(expressions) do
            local constant
            if expression.type==S.Unit then constant=IR.builder():const(S.Unit,I.UInt(0))
            else constant=require('let.specialize').constant(IR.builder(),executed.values[index],expression.type) end
            constant.span=origin and origin.span;constants[index]=constant
        end
        -- Publish accepted bytes only after transport of every component succeeds.
        for _,data in ipairs(executed.moduleData) do self:installRoot(data.root,data.bytes) end
        return constants
    end)
    if not ok then byContext[queryKey]=nil;error(result,0) end
    query.state='Ready';query.value=result
    for index,expression in ipairs(expressions) do context:value(expression,expression.type).knowledge={kind='Exact',value=result[index]} end
    return result
end

return M
