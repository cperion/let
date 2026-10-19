-- Source identities and callable supply metadata. No source operation executes here.
-- A callable is not an Ir.View: materialization belongs to its consuming boundary.
local S = require('let.schema')
local M = {}
local Context = {}; Context.__index = Context

function M.context(identity)
    return setmetatable({identity=identity, values={}, places={}, nextValue=0,nextPoint=0,bodies={}},Context)
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
    if statement.kind=='Let' or statement.kind=='Read' or statement.kind=='View' or statement.kind=='ConstructVariant' then
        local value=self:value(statement.value,statement.type)
        value.producer=statement;value.body=body
    elseif statement.kind=='Call' or statement.kind=='Indirect' or statement.kind=='Dynamic' then
        for _,id in ipairs(statement.results) do
            local value=self:value(id,nil);value.producer=statement;value.body=body
        end
    elseif statement.kind=='Var' then self:place(statement.storage,statement.type) end
end

-- Formation points belong to source emission, not executable IR. Selected late
-- captures splice ordinary occurrences at their definition boundary. Already
-- published statement lists follow the same sequence; no placeholder reaches IR.
function Context:sequenceState(body)
    local state=self.bodies[body]
    if not state then state={points={},copies={}};self.bodies[body]=state end
    return state
end
function Context:point(body)
    self.nextPoint=self.nextPoint+1
    local point={context=self,ordinal=self.nextPoint,body=body,position=#body,values={}}
    local points=self:sequenceState(body).points;points[#points+1]=point
    return point
end
function Context:sequence(body,prefix)
    local list=S.ASDL.List(prefix or {})
    local offset=#list
    for _,stmt in ipairs(body) do list[#list+1]=stmt end
    local copies=self:sequenceState(body).copies;copies[#copies+1]={list=list,offset=offset}
    return list
end
function Context:insert(point,statements)
    assert(point.context==self,'unqualified source point')
    local state=self:sequenceState(point.body)
    local old=point.position
    for index,stmt in ipairs(statements) do
        table.insert(point.body,old+index,stmt)
        for _,copy in ipairs(state.copies) do table.insert(copy.list,copy.offset+old+index,stmt) end
    end
    for _,other in ipairs(state.points) do
        if other.position>old or other.position==old and other.ordinal>=point.ordinal then
            other.position=other.position+#statements
        end
    end
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

-- Capture transport is completed with the word, not guessed from syntax. A word
-- can refer to an enclosing recursive word whose capture list is still growing.
-- Dependencies are finite word identities; completion closes cycles together once
-- every participating body has been elaborated. No source code executes here.
function M.capturePlan()
    return {finished=false,closed=false,dependencies={},dependents={},waiting={},streams={},ready={}}
end
function M.captureStream(plan)
    local stream={plan=plan,inputs={},listeners={}}
    plan.streams[#plan.streams+1]=stream
    return stream
end
function M.addCapture(stream,argument,input)
    assert(not stream.plan.closed,'capture added after word completion')
    local index=#stream+1
    stream[index]=argument;stream.inputs[index]=input
    for _,listener in ipairs(stream.listeners) do listener(argument,input,index) end
end
function M.followCaptures(source,destination,listener)
    local from,to=source.plan,destination.plan
    if from and not from.closed then
        assert(not to.closed,'unfinished dependency of completed word')
        if not to.waiting[from] then
            to.waiting[from]=true
            to.dependencies[#to.dependencies+1]=from;from.dependents[#from.dependents+1]=to
        end
        source.listeners[#source.listeners+1]=listener
    end
    local count=#source
    for index=1,count do listener(source[index],source.inputs and source.inputs[index],index) end
end
function M.whenCapturesClosed(callable,ready)
    local plan=callable.captures.plan
    if not plan or plan.closed then ready()
    else plan.ready[#plan.ready+1]=ready end
end
function M.finishCaptures(plan)
    plan.finished=true
    local function complete(root)
        local seen,group,pending={}, {}, {root}
        local index=1
        while index<=#pending do
            local current=pending[index];index=index+1
            if not current.closed and not seen[current] then
                if not current.finished then return nil end
                seen[current]=true;group[#group+1]=current
                for _,dependency in ipairs(current.dependencies) do pending[#pending+1]=dependency end
            end
        end
        return group
    end
    local queue={plan};local at=1
    while at<=#queue do
        local current=queue[at];at=at+1
        if not current.closed then
            local group=complete(current)
            if group then
                -- Publish the whole closed component before invoking its consumers.
                for _,member in ipairs(group) do member.closed=true end
                for _,member in ipairs(group) do
                    for _,dependent in ipairs(member.dependents) do queue[#queue+1]=dependent end
                    member.dependencies={};member.dependents={};member.waiting={}
                    for _,stream in ipairs(member.streams) do stream.listeners={} end
                    local ready=member.ready;member.ready={}
                    for _,consumer in ipairs(ready) do consumer() end
                end
            end
        end
    end
end

-- Requirement identities are original signature positions, never supply order.
function M.callable(target, name)
    if target.sourceCallable or target.sourceTemplate then return target end
    local requirements={}
    for index,input in ipairs(target.inputs) do
        requirements[index]={identity=index,input=input,name=target.keyed and target.keyed[index]}
    end
    local captures=target.prefixArgs or {}
    if target.prefixInputs then captures.inputs=target.prefixInputs end
    return {sourceCallable=true,definition=target.definition,target=target.target or name,requirements=requirements,
        original=requirements,supplied={},captures=captures,
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

-- A binding supply can retain an existing mutable instance without reading its
-- bytes. This is compiler identity metadata, never a runtime alias/namespace object.
function M.instance(binding, span)
    return {kind='SourceInstance',instance=binding,type=binding.type,schema=binding.schema,span=span}
end

function M.pack(components, span)
    return {kind='SourcePack',sourcePack=components,span=span}
end
function M.templateValue(template, span)
    return {kind='SourceTemplate',sourceTemplate=template,span=span}
end
function M.value(callable, span)
    if callable.sourceTemplate then return M.templateValue(callable,span) end
    return {kind='SourceCallable',sourceCallable=callable,type=S.View(S.Sig(callable.inputs,callable.results)),span=span}
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
