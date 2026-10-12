-- Source identities and callable supply metadata. No source operation executes here.
-- A callable is not an Ir.View: materialization belongs to its consuming boundary.
local S = require('let.schema')
local M = {}
local Context = {}; Context.__index = Context

function M.context(identity)
    return setmetatable({identity=identity, values={}, places={}, nextValue=0},Context)
end

function Context:value(definition, ty, origins)
    local previous=self.values[definition]
    if previous then return previous end
    self.nextValue=self.nextValue+1
    local value={context=self,ordinal=self.nextValue,definition=definition,type=ty,
        origins=origins,knowledge={kind='Runtime'}}
    self.values[definition]=value
    return value
end

function Context:emit(body, statement)
    if statement.kind=='Let' or statement.kind=='Read' or statement.kind=='View' then
        local value=self:value(statement.value,statement.type)
        value.producer=statement;value.body=body
    elseif statement.kind=='Call' or statement.kind=='Indirect' or statement.kind=='Dynamic' then
        for _,id in ipairs(statement.results) do
            local value=self:value(id,nil);value.producer=statement;value.body=body
        end
    elseif statement.kind=='Var' then self:place(statement.storage,statement.type) end
end

function Context:place(storage, ty)
    local previous=self.places[storage]
    if previous then return previous end
    local place={context=self,storage=storage,type=ty}
    place.root=place
    self.places[storage]=place
    return place
end

-- Computation has an identity and source contract, but no lexical name. Binding
-- contexts decide visibility/recursion/receiver placement before elaborating it.
function M.word(syntax, identity)
    return {id=identity,params=syntax.params,keyed=syntax.keyed or {},
        result=syntax.result,body=syntax.body,origin=syntax}
end

-- Requirement identities are original signature positions, never supply order.
function M.callable(target, name)
    if target.sourceCallable then return target end
    local requirements={}
    for index,input in ipairs(target.inputs) do
        requirements[index]={identity=index,input=input,name=target.keyed and target.keyed[index]}
    end
    return {sourceCallable=true,definition=target.definition,target=target.target or name,requirements=requirements,
        original=requirements,supplied={},captures=target.prefixArgs or {},
        inputs=target.inputs,keyed=target.keyed,results=target.results,
        resultSchemas=target.resultSchemas,foreign=target.foreign}
end

function M.supply(callable, supplies)
    local supplied={}
    for id,arg in pairs(callable.supplied) do supplied[id]=arg end
    for index,arg in pairs(supplies) do
        supplied[callable.requirements[index].identity]=arg
    end
    local remaining,inputs,keys={},{},callable.keyed and {} or nil
    for _,requirement in ipairs(callable.original) do
        if not supplied[requirement.identity] then
            remaining[#remaining+1]=requirement
            inputs[#inputs+1]=requirement.input
            if keys then keys[#keys+1]=requirement.name end
        end
    end
    return {sourceCallable=true,definition=callable.definition,target=callable.target,original=callable.original,
        requirements=remaining,supplied=supplied,captures=callable.captures,
        inputs=inputs,keyed=keys,results=callable.results,resultSchemas=callable.resultSchemas,
        foreign=callable.foreign}
end

function M.arguments(callable)
    assert(#callable.requirements==0,'unsaturated source callable')
    local args={}
    for _,arg in ipairs(callable.captures) do args[#args+1]=arg end
    for _,requirement in ipairs(callable.original) do
        args[#args+1]=assert(callable.supplied[requirement.identity])
    end
    return args
end

function M.value(callable, span)
    return {kind='SourceCallable',sourceCallable=callable,type=S.view(S.sig(callable.inputs,callable.results)),span=span}
end

-- Definition namespaces are compile-time identities, never runtime tables or
-- environments. Aliases reuse the same member definitions.
function M.namespace(members, origin)
    return {kind='namespace',members=members,origin=origin}
end
function M.typeDefinition(ty, schema, origin)
    return {kind='type',type=ty,schema=schema,origin=origin,constructors={}}
end
function M.member(definition, name)
    if not definition then return nil end
    if definition.kind=='namespace' then return definition.members[name] end
    if definition.kind=='type' and definition.type:isSum() then
        local payload=S.caseOf(definition.type,name)
        if not payload then return nil end
        local constructor=definition.constructors[name]
        if not constructor then
            constructor={kind='constructor',sum=definition.type,tag=name,payload=payload,origin=definition.origin}
            definition.constructors[name]=constructor
        end
        return constructor
    end
end
function M.definitionValue(definition, span)
    return {kind='SourceDefinition',sourceDefinition=definition,span=span}
end

return M
