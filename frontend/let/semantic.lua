-- Source AST to verified ASDL IR. This pass resolves names and types but never executes user code.
local S = require("let.schema")
local IR = require("let.ir")
local Check = require("let.check")
local Walk = require("let.walk")
local D = require("let.diag")
local Source = require("let.source_state")

local M = {}
local I, L = S.Ir, S.ASDL.List
local DEFINITION_LOOKUP = {}
local RECEIVER_SCOPE = {}
local VOCABULARY_BUILTINS={Ref=true,Ptr=true,Slice=true,Array=true,null=true,is=true}
local DYNAMIC_VOCABULARY={open=true,has=true,remove=true,count=true,key=true,freeze=true}

local BUILTIN_TYPES = {
    U8=S.U8, U16=S.U16, U32=S.U32, U64=S.U64,
    I32=S.I32, I64=S.I64, F64=S.F64, Bool=S.Bool, Unit=S.Unit, Any=S.Any, String=S.String, Type=S.Type,
}

local UNARY = { ["-"]="Neg", ["~"]="BitNot", ["not"]="Not" }
local BINARY = {
    ["+"]="Add", ["-"]="Sub", ["*"]="Mul", ["/"]="Div", ["%"]="Rem", ["^"]="Pow",
    ["&"]="BitAnd", ["|"]="BitOr", ["~"]="BitXor", ["<<"]="Shl", [">>"]="Shr",
    ["=="]="Eq", ["!="]="Ne", ["<"]="Lt", ["<="]="Le", [">"]="Gt", [">="]="Ge",
}
local COMPARISON = { ["=="]=true, ["!="]=true, ["<"]=true, ["<="]=true, [">"]=true, [">="]=true }


local function schemaName(node,schemas)
    if not node then return nil end
    if node.kind=='Group' then return schemaName(node.value,schemas) end
    local name
    if node.kind=="Reference" then name=node.name.text
    elseif node.kind=='FieldSelect' and schemas[DEFINITION_LOOKUP] then
        local definition=schemas[DEFINITION_LOOKUP](node)
        return definition and definition.kind=='type' and definition.schema or nil
    elseif node.kind=="Apply" and node.callee.kind=="Reference" and (node.callee.name.text=="Ref" or node.callee.name.text=="Ptr") then return schemaName(node.arguments[1],schemas) end
    return name and schemas[name] or nil
end
local function reject(code, message, node) D.reject(code, message, node and node.span) end
local function located(value, node) if type(value)=="table" and node and node.span then value.span=node.span end return value end
local function copy(scope) local out={} for k,v in pairs(scope) do out[k]=v end return out end
local function ungroup(node)
    while node and node.kind=='Group' do node=node.value end
    return node
end

local function typeExpr(node, types)
    node=ungroup(node)
    if node and node.kind=="Reference" then
        local ty=BUILTIN_TYPES[node.name.text] or (types and types[node.name.text])
        if ty then return ty end
    elseif node and node.kind=='FieldSelect' and types and types[DEFINITION_LOOKUP] then
        local definition=types[DEFINITION_LOOKUP](node)
        if definition and definition.kind=='type' then return definition.type end
    elseif node and (node.kind=='SchemaExpr' or node.kind=='SumSchema') then
        local fields={}
        for _,member in ipairs(node.members) do
            if member.kind=="MethodMember" then
                if node.kind=='SumSchema' then reject('type-required','Sum alternatives must be name: Type entries',member) end
                -- Methods belong to the schema interface, not its runtime record layout.
            else
                if fields[member.name.text] then reject("duplicate-name","Schema field `"..member.name.text.."` is declared twice",member) end
                fields[member.name.text]=typeExpr(member.type,types)
            end
        end
        return node.kind=='SumSchema' and S.Sum(fields) or S.Record(fields)
    elseif node and node.kind=="Apply" and node.callee.kind=="Reference" then
        local name=node.callee.name.text
        if name=="Ref" or name=="Ptr" or name=="Slice" then
            if #node.arguments~=1 then reject("arity",name.." type expects one argument",node) end
            local child=typeExpr(node.arguments[1],types)
            return name=="Ref" and S.Ref(child) or name=="Ptr" and S.Ptr(child) or S.Slice(child)
        elseif name=="Array" then
            local length=ungroup(node.arguments[2])
            if #node.arguments~=2 or length.kind~='U32Literal' or length.value<1 then reject('array-length','array expects a type and a positive literal length',node) end
            return S.Array(typeExpr(node.arguments[1],types),length.value)
        end
    elseif node and node.kind=="SignatureExpr" then
        local inputs={} for _,input in ipairs(node.inputs) do inputs[#inputs+1]=S.inValue(typeExpr(input,types)) end
        local results={} if node.results.kind=="Single" then results[1]=typeExpr(node.results.type,types) else for _,result in ipairs(node.results.types) do results[#results+1]=typeExpr(result,types) end end
        return S.View(S.Sig(inputs,results))
    end
    reject("type-required", "Expected a concrete runtime type", node)
end

local function resultInterfaces(spec,schemas)
    local out={} if not spec then return out end
    if spec.kind=="Single" then out[1]=schemaName(spec.type,schemas) else for index,node in ipairs(spec.types) do out[index]=schemaName(node,schemas) end end
    return out
end

local function resultTypes(spec,types)
    if not spec then return nil end
    local out={}
    if spec.kind=="Single" then out[1]=typeExpr(spec.type,types)
    else for _,node in ipairs(spec.types) do out[#out+1]=typeExpr(node,types) end end
    return out
end

local function staticTypeParameter(param,types,formals)
    local annotation=param.annotation and ungroup(param.annotation)
    if not annotation then return false end
    local root=annotation
    while root.kind=='FieldSelect' do root=ungroup(root.base) end
    -- Dependent annotations refer to preceding formals, not same-spelled globals.
    if root.kind=='Reference' and formals[root.name.text] then return false end
    if annotation.kind=='Reference' then return (BUILTIN_TYPES[annotation.name.text] or types[annotation.name.text])==S.Type end
    if annotation.kind=='FieldSelect' and types[DEFINITION_LOOKUP] then
        local definition=types[DEFINITION_LOOKUP](annotation)
        return definition and definition.kind=='type' and definition.type==S.Type or false
    end
    return false
end

local function wordContract(word,types,dynamic,expected,inferResults)
    if expected and not expected:isView() then reject('type-required','A word needs a callable signature',word.origin) end
    local parameters={}
    for _,param in ipairs(#word.keyed>0 and word.keyed or word.params) do parameters[#parameters+1]=param end
    if #word.keyed>0 then table.sort(parameters,function(a,b) return a.name.text<b.name.text end) end
    local template,names=false,{}
    local typePrefix=true
    for index,param in ipairs(parameters) do
        local name=param.name and param.name.text
        local static=staticTypeParameter(param,types,names)
        if name then
            if names[name] then reject('duplicate-name','Parameter is declared twice',param) end
            names[name]=true
        end
        if param.kind=='VocabularyParam' and (not typePrefix or static) then
            reject('vocabulary-position','An opened parameter must be the first runtime requirement after leading Type requirements',param)
        end
        if not static then typePrefix=false end
        if param.kind=='RestParam' then
            if #word.keyed>0 or index~=#parameters then reject('rest-position','Rest must be the final ordered requirement',param) end
            template=true
        elseif static then template=true end
    end
    if template then
        if expected then reject('template-use','An unspecialized template has no erased callable signature',word.origin) end
        local contract={sourceTemplate=true,definition=word,target=word.id,parameters=parameters,supplied={}}
        word.contract=contract;return contract
    end
    if expected and #parameters~=#expected.visible.inputs then reject('arity','Word parameter count does not match its signature',word.origin) end
    local inputs,names,keys={},{},{}
    for index,param in ipairs(parameters) do
        local name=param.name and param.name.text
        if name then
            if names[name] then reject('duplicate-name','Parameter `'..name..'` is declared more than once',param) end
            names[name]=true
        end
        local contextual=expected and expected.visible.inputs[index].type
        local declared=param.annotation and typeExpr(param.annotation,types)
        if declared and contextual and declared~=contextual then reject('type-mismatch','Word parameter annotation does not match its signature',param) end
        local ty=declared or contextual or (dynamic and name and S.Any)
        if not ty then reject('parameter-type',(name and 'Parameter `'..name..'`' or 'Unnamed context parameter')..' needs a type annotation or context',param) end
        inputs[index]=S.inValue(ty)
        if #word.keyed>0 then keys[index]=name end
    end
    local results=resultTypes(word.result,types)
    local contextual=expected and not inferResults and expected.visible.results
    if results and contextual then
        if #results~=#contextual then reject('type-mismatch','Word result annotation does not match its context',word.origin) end
        for index,ty in ipairs(results) do if ty~=contextual[index] then reject('type-mismatch','Word result annotation does not match its context',word.origin) end end
    end
    results=results or contextual
    if results and #results<1 then reject('semantic-todo','Zero-result source words are not implemented',word.origin) end
    local contract={definition=word,target=word.id,parameters=parameters,inputs=inputs,results=results,
        keyed=#keys>0 and keys or nil}
    word.contract=contract
    return contract
end

local Function = {}
Function.__index = Function

local function wordScope(environment,word,results)
    local child=setmetatable({definition=word,id=word.id,signatures=environment.signatures,
        globals=environment.globals,types=environment.types,typeCells=environment.typeCells,
        schemas=environment.schemas,namespaces=environment.namespaces,
        methodState=environment.methodState,builder=IR.builder(),
        body={},scope={},inputs={},results=results,params={},dynamic=environment.dynamic,
        managed=environment.managed,generated=environment.generated,lambdaState=environment.lambdaState,
        visible=copy(environment.visible or {}),deferScopes={}},Function)
    child.types=setmetatable({[DEFINITION_LOOKUP]=function(node) return child:resolveDefinition(node) end},{__index=function(_,name)
        local binding=child:peekBinding(name);local definition=binding and binding.sourceDefinition
        if not binding and child.globals[name] then definition=child.lambdaState.resolveGlobal(name).sourceDefinition end
        if definition and definition.kind=='type' then return definition.type end
        return environment.types[name]
    end})
    child.schemas=setmetatable({[DEFINITION_LOOKUP]=function(node) return child:resolveDefinition(node) end},{__index=function(_,name)
        local binding=child:peekBinding(name);local definition=binding and binding.sourceDefinition
        if not binding and child.globals[name] then definition=child.lambdaState.resolveGlobal(name).sourceDefinition end
        if definition and definition.kind=='type' then return definition.schema end
        return environment.schemas[name]
    end})
    return child
end

-- Definition selection is shared by qualified access, aliases, and expansion.
-- A namespace has no runtime type and cannot be smuggled into an ABI argument.
function Function:resolveDefinition(node)
    node=ungroup(node)
    if node.kind=='Reference' then
        local name=node.name.text
        local localBinding=self:peekBinding(name)
        if localBinding then return localBinding.sourceDefinition end
        if self.namespaces and self.namespaces[name] then return self.namespaces[name] end
        if self.signatures[name] then return {kind='word',target=self.signatures[name],origin=self.signatures[name].origin} end
        local global=self.globals[name]
        if global then return self.lambdaState.resolveGlobal(name).sourceDefinition end
        local ty=BUILTIN_TYPES[name] or self.types[name]
        if ty then
            self.lambdaState.typeDefinitions=self.lambdaState.typeDefinitions or {}
            local key=self.schemas[name] or ty
            local definition=self.lambdaState.typeDefinitions[key]
            if not definition then definition=Source.typeDefinition(ty,self.schemas[name],node);self.lambdaState.typeDefinitions[key]=definition end
            return definition
        end
    elseif node.kind=='FieldSelect' then
        local base=self:resolveDefinition(node.base)
        local member=Source.member(base,node.field.text)
        if base and not member then reject('unknown-field','Definition has no public member `'..node.field.text..'`',node) end
        return member
    end
end

function Function:constructorTarget(definition,owner)
    if definition.target then
        if not self.lambdaState.resolve(definition.target.target) then self.generated[#self.generated+1]=definition.fn end
        return definition.target
    end
    self.lambdaState.count=self.lambdaState.count+1
    local id=self.id..'__constructor_'..self.lambdaState.count
    local child=wordScope(self,{id=id}, {definition.sum})
    child:context()
    local payload,inputs
    if definition.payload==S.Unit then inputs={}
    else
        inputs={S.inValue(definition.payload)}
        payload=child:wordParameter('__payload',inputs[1],nil,owner).value
    end
    local value=child:constructVariant(definition.sum,definition.tag,payload,owner)
    child.builder:return_(child.body,{value})
    local fn=located(I.Fn(id,I.Body,0,L(inputs),L{definition.sum},L(child.params),L(child.body)),owner)
    self.generated[#self.generated+1]=fn
    definition.fn=fn;definition.target={target=id,inputs=inputs,results={definition.sum}}
    return definition.target
end

function Function:definitionValue(definition,owner,allowDefinition)
    if definition.kind=='word' then return Source.value(Source.callable(self:requireContract(definition.target,owner)),owner.span) end
    if definition.kind=='constructor' then
        local value=Source.value(Source.callable(self:constructorTarget(definition,owner)),owner.span)
        value.constructorDefinition=definition;return value
    end
    if not allowDefinition then reject('definition-value','Compile-time definitions have no runtime representation',owner) end
    return Source.definitionValue(definition,owner.span)
end

function Function:requireContract(target,origin)
    local word=target.definition
    if target.ensure then target.ensure() end
    if target.sourceTemplate then return target end
    if word then
        if not word.contract.results then
            if word.state=='checking' then reject('result-type','Recursive word use needs an explicit result contract',origin or word.origin) end
            self.lambdaState.resolve(word.id)
        end
        target.results=word.contract.results
    end
    return target
end

function Function:knownType(node)
    if node.kind=='Group' then return self:knownType(node.value) end
    if node.kind=="Reference" then local binding=self:peekBinding(node.name.text);return binding and binding.type end
    if node.kind=='CurrentContext' then local receiver=self:peekBinding(RECEIVER_SCOPE);return receiver and receiver.binding.type end
    if node.kind=="FieldSelect" or node.kind=="IndexExpr" then if self:knownType(node.base)==S.Any then return S.Any end end
    if node.kind=='Apply' then
        local definition=self:resolveDefinition(node.callee)
        local target=definition and definition.kind=='word' and definition.target
        if target then self:requireContract(target,node);return target.results and #target.results==1 and target.results[1] or nil end
    end
end

function Function:placeBinding(node)
    if node.kind=='Group' then return self:placeBinding(node.value) end
    if node.kind=="Reference" then return self:lookupBinding(node.name.text) end
    if node.kind=='CurrentContext' then return self:currentContextBinding(node) end
    if node.kind=='FieldSelect' or node.kind=='IndexExpr' then
        local pack=node.kind=='IndexExpr' and self:packBinding(node.base)
        if pack then return self:packIndex(pack,node) end
        local parent=self:placeBinding(node.base);if not parent then return nil end
        if not (parent.place or parent.storage or parent.getPlace) or not parent.type then return nil end
        local ty=parent.type
        if node.kind=='IndexExpr' then
            local element=(ty:isArray() or ty:isSlice()) and ty.element or ty:isPtr() and ty.target
            if not element then return nil end
            return {getPlace=function() return self:place(node) end,type=element}
        end
        if ty:isRef() or ty:isPtr() then ty=self:sealed(ty.target) end
        local field=S.field(ty,node.field.text);if not field then return nil end
        local schema=parent.schema
        return {getPlace=function() return self:place(node) end,type=field,
            schema=schema and schema.fieldSchemas and schema.fieldSchemas[node.field.text] or nil}
    end
end

-- Interface discovery must not evaluate an index/address. Realize an occurrence's
-- existing place expression once, only when its consumer actually needs it.
function Function:bindingPlace(binding)
    if binding.getPlace then binding.place=binding.getPlace();binding.getPlace=nil end
    return binding.place or (binding.storage and I.Local(binding.storage))
end

function Function:sealed(ty)
    local seen={}
    while ty and ty:isNamed() do
        if seen[ty.cell] then reject("type-cycle","Recursive type cell did not seal",self.definition and self.definition.origin) end
        seen[ty.cell]=true;ty=self.typeCells[ty.cell]
    end
    return ty
end

function Function:sameType(left,right,seen)
    left,right=self:sealed(left),self:sealed(right)
    if left==right then return true end
    if not left or not right or left.kind~=right.kind then return false end
    seen=seen or {};seen[left]=seen[left] or {};if seen[left][right] then return true end;seen[left][right]=true
    if left:isRef() or left:isPtr() then return self:sameType(left.target,right.target,seen) end
    if left:isSlice() then return self:sameType(left.element,right.element,seen) end
    if left:isArray() then return left.length==right.length and self:sameType(left.element,right.element,seen) end
    if left:isRecord() or left:isTaggedType() then
        local a=left:isRecord() and left.fields or S.alternatives(left);local b=right:isRecord() and right.fields or S.alternatives(right)
        if #a~=#b then return false end
        for index,field in ipairs(a) do if field.name~=b[index].name or not self:sameType(field.type,b[index].type,seen) then return false end end
        return true
    end
    return false
end

function Function:place(node)
    if node.kind=='Group' then return self:place(node.value) end
    if node.kind=='CurrentContext' then
        local binding=self:currentContextBinding(node)
        -- The retained reference is a value, not a public mutable pointer cell.
        -- Its referent's field places remain writable under ordinary borrow rules.
        if binding.type:isRef() then reject('not-a-place','The retained home reference has no addressable holder; use its value or a field place',node) end
        local place=self:bindingPlace(binding)
        if not place then reject('not-a-place','The current context is not addressable',node) end
        return place,binding.type
    elseif node.kind=="Reference" then
        local binding=self:lookupBinding(node.name.text)
        if binding and binding.sourcePack then reject('pack-use','A pack is not a writable place',node) end
        if not binding or (not binding.storage and not binding.place) then reject("not-a-place","`"..node.name.text.."` is not addressable",node) end
        return binding.place or I.Local(binding.storage),binding.type
    elseif node.kind=="FieldSelect" then
        local base,ty
        if ungroup(node.base).kind=='CurrentContext' then
            local binding=self:currentContextBinding(node.base);base,ty=self:bindingPlace(binding),binding.type
        else base,ty=self:place(node.base) end
        if ty:isRef() or ty:isPtr() then local target=self:sealed(ty.target);base,ty=I.Deref(base,target),target end
        local field=S.field(ty,node.field.text);if not field then reject("unknown-field","Type has no field `"..node.field.text.."`",node.field) end
        return I.Project(base,I.Field(node.field.text)),field
    elseif node.kind=="IndexExpr" then
        local index=self:coerce(self:expr(node.index,S.U32),S.U32,node.index)
        if node.base.kind=="Reference" or node.base.kind=="FieldSelect" or node.base.kind=="IndexExpr" then
            local binding=node.base.kind=="Reference" and self:lookupBinding(node.base.name.text) or true
            if binding and (binding==true or binding.storage or binding.place) then
                local base,ty=self:place(node.base)
                if ty:isArray() then return I.Index(base,index,ty.element),ty.element end
            end
        end
        local view=self:expr(node.base)
        if view.type:isSlice() then return self.builder:sliceIndex(view,index,view.type.element),view.type.element end
        if view.type:isPtr() then return self.builder:ptrIndex(view,index,view.type.target),view.type.target end
        reject("not-indexable","Indexing needs an array, slice, or pointer",node.base)
    end
    reject("not-a-place","Expression is not an addressable place",node)
end

function Function:readPlace(node)
    local occurrence=self:placeBinding(node)
    local place,ty
    if occurrence and (occurrence.place or occurrence.storage or occurrence.getPlace) then place=self:bindingPlace(occurrence);ty=occurrence.type
    else place,ty=self:place(node) end
    local value=self.builder:read(self.body,ty,place);local result=self.builder:ref(value,ty)
    result.schema=occurrence and occurrence.schema or nil
    return result
end

-- Evaluate contributions before selecting overrides. Canonical requirement order
-- never becomes computation order; discarded contributions retain their occurrences.
function Function:keyedContributions(items,typeAt,evaluate)
    local explicit,spread,ordered,explicitNames={},{},{},{}
    for _,item in ipairs(items) do if item.kind=='FieldSupply' then explicitNames[item.name.text]=true end end
    local function contribute(name,value,origin,isSpread)
        local wanted=typeAt(name,origin)
        -- Override choice is structural; checks/conversions of effective supplies
        -- still execute at their own source occurrence, before later operands.
        if not isSpread or not explicitNames[name] then
            value=self:snapshotArgument(self:coerce(value,wanted,origin),origin)
        end
        local entry={name=name,value=value,node=origin,wanted=wanted}
        ordered[#ordered+1]=entry
        if isSpread then
            if spread[name] then reject('spread-overlap','Two spreads supply `'..name..'`',origin) end
            spread[name]=entry
        else
            if explicit[name] then reject('duplicate-name','Field `'..name..'` is supplied twice',origin) end
            explicit[name]=entry
        end
    end
    for _,item in ipairs(items) do
        if item.kind=='FieldSpread' then
            local source=self:snapshotArgument(self:expr(item.value),item.value)
            if not source.type:isRecord() then reject('spread-source','Keyed spread needs a statically shaped record',item) end
            for _,field in ipairs(source.type.fields) do
                local value=self:snapshotArgument(self.builder:get(source,field.name,field.type),item)
                contribute(field.name,value,item,true)
            end
        else
            local name=item.name.text;local wanted=typeAt(name,item)
            local value=evaluate and evaluate(item,wanted) or self:expr(item.value,wanted)
            value=self:snapshotArgument(value,item.value)
            contribute(name,value,item.value,false)
        end
    end
    local effective={}
    for _,entry in ipairs(ordered) do
        if (explicit[entry.name] or spread[entry.name])==entry then
            effective[#effective+1]=entry
        end
    end
    return effective
end

function Function:recordFields(ty, supplies, owner)
    local contributions=self:keyedContributions(supplies,function(name,origin)
        local fieldType=S.field(ty,name)
        if not fieldType then reject('unknown-field','Unknown field `'..name..'`',origin) end
        return fieldType
    end)
    local supplied={} for _,entry in ipairs(contributions) do supplied[entry.name]=entry.value end
    local fields={} for _,field in ipairs(ty.fields) do local value=supplied[field.name];if not value then reject("missing-field","Missing field `"..field.name.."`",owner) end;fields[#fields+1]=value end
    return fields
end

function Function:constructVariant(sum, tag, payload, owner)
    local payloadType=S.caseOf(sum,tag);if not payloadType then reject("unknown-field","Sum has no alternative `"..tag.."`",owner) end
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.ConstructVariant(value,sum,tag,payload),owner))
    local result=self.builder:ref(value,sum)
    return result
end

function Function:sumMatch(node, expected)
    local variant=self:expr(node.schema);if not variant.type:isSum() then reject("type-mismatch","Keyed matching needs a sum value",node.schema) end
    local variantValue=variant.kind=="Ref" and variant.value or self.builder:let(self.body,variant.type,variant)
    local handlers={};local resultType=expected
    -- Handler expressions are ordinary supplies: evaluate once in written order,
    -- before dispatch. Only invocation is conditional on the variant's tag.
    local contributions=self:keyedContributions(node.fields,function(name,origin)
        if not S.caseOf(variant.type,name) then reject('unknown-field','Unknown alternative `'..name..'`',origin) end
    end,function(field)
        local payloadType=S.caseOf(variant.type,field.name.text)
        local inputs=payloadType==S.Unit and {} or {S.inValue(payloadType)}
        local valueNode=ungroup(field.value)
        if valueNode.kind=='Lambda' then
            return self:lambda(valueNode,S.View(S.Sig(inputs,resultType and {resultType} or {})),not resultType)
        end
        return self:expr(field.value)
    end)
    for _,field in ipairs(contributions) do
        local name=field.name
        local payloadType=S.caseOf(variant.type,name)
        local inputs=payloadType==S.Unit and {} or {S.inValue(payloadType)}
        local value=field.value
        if not value.type:isView() then reject('type-mismatch','A sum handler must be a callable value',field.node) end
        local signature=value.type.visible
        if #signature.inputs~=#inputs then reject('arity','Sum handler payload arity does not match',field) end
        for index,input in ipairs(inputs) do
            if signature.inputs[index]~=input then reject('type-mismatch','Sum handler payload type does not match',field) end
        end
        if #signature.results~=1 then reject('result-arity','A sum handler must return exactly one value',field) end
        if resultType and signature.results[1]~=resultType then reject('type-mismatch','Sum handler result type does not match',field) end
        resultType=resultType or signature.results[1]
        handlers[name]={value=value,origin=field.node}
    end
    local resultStorage=self.builder:storageId();local cases={}
    local alternatives=S.alternatives(variant.type)
    for index,alternative in ipairs(alternatives) do
        local handler=handlers[alternative.name]
        if not handler then reject('missing-field','Missing handler for `'..alternative.name..'`',node) end
        local list={};local args={}
        if alternative.type~=S.Unit then
            local payload=self.builder:valueId()
            self.builder:emit(list,located(I.VariantPayload(payload,variantValue,variant.type,alternative.name),handler.origin))
            args[1]=I.ValueArg(self.builder:ref(payload,alternative.type))
        end
        local result=self.builder:valueId();local callable=handler.value
        if callable.sourceCallable then
            local application=Source.supply(callable.sourceCallable,args)
            self:emitSourceCall({result},application,handler.origin,list)
        else
            self.builder:emit(list,located(I.Indirect(L({result}),callable,L(args)),handler.origin))
        end
        self.builder:store(list,I.Local(resultStorage),self.builder:ref(result,resultType))
        cases[#cases+1]=I.Case(alternative.name,index==#alternatives,L(list))
    end
    self.builder:emit(self.body,located(I.Var(resultStorage,resultType,nil),node))
    self.builder:emit(self.body,located(I.Switch(variantValue,variant.type,L(cases)),node))
    local value=self.builder:read(self.body,resultType,I.Local(resultStorage));return self.builder:ref(value,resultType)
end
-- Visibility queries do not capture. Only a selected runtime binding crosses a
-- lexical frame boundary. The outer lookup is pinned at word formation time.
function Function:peekBinding(name)
    return self.scope[name] or (self.outerLookup and self.outerLookup(name))
        or (self.globals[name] and self.globals[name].binding)
end

function Function:lookupBinding(name)
    local source=self:peekBinding(name)
    if not source and self.globals[name] and self.lambdaState.resolveGlobal then
        self.lambdaState.resolveGlobal(name);source=self.globals[name].binding
    end
    if not source then return nil end
    if self.globals[name] and source==self.globals[name].binding then return source end
    local binding=self:importBinding(source)
    self.scope[name]=binding
    return binding
end

function Function:finishTransport()
    if not self.baseInputs then return end
    local inputs,params={},{}
    local function add(input,param)
        param.input=#inputs;inputs[#inputs+1]=input;params[#params+1]=param
    end
    for index=1,self.fixedHidden do add(self.baseInputs[index],self.baseParams[index]) end
    for index,entry in ipairs(self.captureEntries) do add(self.captureSlots.inputs[index],entry.param) end
    for index=self.fixedHidden+1,#self.baseInputs do add(self.baseInputs[index],self.baseParams[index]) end
    self.inputs,self.params=inputs,params
    if self.fn then
        self.fn.inputs=L(inputs);self.fn.params=L(params)
        self.fn.hidden=self.fixedHidden+#self.captureEntries
    end
end

function Function:captureArgument(argument,input)
    if argument.kind=='ValueArg' and argument.value.kind=='Const' then return argument end
    local key=argument.kind=='ValueArg' and argument.value or 'place:'..S.encode(argument.place)
    local previous=self.captureArguments[key]
    if previous then return previous end
    local param,localArgument
    if input.kind=='InPlace' then
        local storage=self.builder:storageId();param=I.PlaceParam(0,storage,input.type)
        localArgument=I.BorrowArg(I.Local(storage))
    else
        local value=self.builder:valueId();param=I.ValueParam(0,value,input.type)
        localArgument=I.ValueArg(self.builder:ref(value,input.type))
    end
    self.captureArguments[key]=localArgument
    self.captureEntries[#self.captureEntries+1]={param=param}
    Source.addCapture(self.captureSlots,argument,input)
    Source.addCapture(self.recursiveSlots,localArgument,input)
    return localArgument
end

function Function:importBinding(source)
    if source.sourceDefinition or source.staticValue or source.sourceTemplate or not source.owner or source.owner==self or source.owner==self.sourceOwner then return source end
    if source.sourcePack then
        local components={}
        for index,binding in ipairs(source.sourcePack) do components[index]=self:importBinding(binding) end
        return {sourcePack=components,owner=self,origin=source.origin}
    end
    local existing=self.capturedBindings[source]
    if existing then return existing end
    local parent=assert(self.lexicalParent,'runtime binding without lexical parent')
    local original=parent:importBinding(source)
    local binding={owner=self,type=original.type,schema=original.schema,origin=original.origin,
        localCallable=original.localCallable,callable=original.callable,
        openedField=original.openedField}
    self.capturedBindings[source]=binding
    if original.sourceCallable then
        local callable=original.sourceCallable
        parent:requireContract(callable)
        local captured=copy(callable)
        captured.captures=Source.captureStream(self.capturePlan);captured.supplied={}
        binding.sourceCallable=captured
        Source.followCaptures(callable.captures,captured.captures,function(arg,input)
            input=input or (arg.kind=='ValueArg' and S.inValue(arg.value.type))
            assert(input,'missing captured place contract')
            Source.addCapture(captured.captures,self:captureArgument(arg,input),input)
        end)
        for _,requirement in ipairs(callable.original) do
            local arg=callable.supplied[requirement.identity]
            if arg then captured.supplied[requirement.identity]=self:captureArgument(arg,requirement.input) end
        end
    else
        local place=parent:bindingPlace(original)
        local byPlace=place and (original.openedField or original.type:isRecord() or original.type:isArray())
        local input=byPlace and S.inPlace(original.type) or S.inValue(original.type)
        local argument=byPlace and I.BorrowArg(place) or I.ValueArg(parent:formationValue(original,self.capturePoint))
        local held=self:captureArgument(argument,input)
        if held.kind=='BorrowArg' then binding.storage=held.place.storage
        elseif original.type:isRef() or original.type:isPtr() then
            binding.storage=self.builder:var(self.prologue,original.type,held.value)
        elseif held.value.kind=='Const' then binding.staticValue=held.value
        else binding.value=held.value.value end
    end
    return binding
end

function Function:activeReceiver()
    local receiver=self:peekBinding(RECEIVER_SCOPE)
    if not receiver then return nil end
    return {binding=self:importBinding(receiver.binding),origin=receiver.origin}
end
function Function:currentContextBinding(node)
    local receiver=self:activeReceiver()
    if not receiver then reject('context-required','Bare `...` requires an opened runtime context',node) end
    return receiver.binding
end

function Function:emitSourceCall(values,application,origin,body)
    local statement=located(I.Call(L(values),application.target,L{}),origin)
    statement.capturePending=true
    Source.whenCapturesClosed(application,function()
        statement.arguments=L(Source.arguments(application));statement.capturePending=nil
    end)
    self.builder:emit(body or self.body,statement)
end

-- Parameter transport and local storage are independent of the spelling that
-- introduced the word. The returned argument refers to this frame's input.
function Function:wordParameter(name,input,annotation,origin)
    local index=#self.inputs;self.inputs[#self.inputs+1]=input
    local ty=input.type
    local binding,argument
    if input.kind=='InPlace' then
        local storage=self.builder:storageId()
        self.params[#self.params+1]=located(I.PlaceParam(index,storage,ty),origin)
        binding={storage=storage,type=ty};argument=I.BorrowArg(I.Local(storage))
    else
        local value=self.builder:valueId()
        self.params[#self.params+1]=located(I.ValueParam(index,value,ty),origin)
        local ref=self.builder:ref(value,ty)
        if ty:isRecord() or ty:isArray() or ty:isRef() or ty:isPtr() then
            binding={storage=self.builder:var(self.body,ty,ref),type=ty}
        else binding={value=value,type=ty,callable=ty:isView() or ty:isOwned()} end
        argument=I.ValueArg(ref)
    end
    binding.schema=schemaName(annotation,self.schemas)
    binding.origin=origin;binding.localCallable=true;binding.owner=self
    if name then self.scope[name]=binding end
    return argument,binding
end

-- The sole source-word elaborator. Binding policy supplies recursive visibility
-- and an optional receiver; it never selects a different computation algorithm.
function Function:elaborateWord(word,contract,binding)
    binding=binding or {}
    word.state='checking'
    contract.resultSchemas=resultInterfaces(word.result,self.schemas)
    local child=wordScope(self,word,contract.results)
    child:context()
    child.capturePlan=Source.capturePlan();child.captureEntries={};child.captureArguments={};child.capturedBindings={}
    child.captureSlots=Source.captureStream(child.capturePlan);child.recursiveSlots=Source.captureStream(child.capturePlan)
    child.prologue={};child.fixedHidden=binding.receiver and 1 or 0;child.parameterBindings={}
    child.capturePoint=binding.formationPoint or self:context():point(self.body)
    word.child=child
    local slots,recursiveSlots=child.captureSlots,child.recursiveSlots
    local lexical=binding.lexicalScope or self.scope or {}
    local snapshot=setmetatable(copy(lexical),getmetatable(lexical))
    local inheritedLookup=not binding.lexicalScope and self.outerLookup or nil
    child.lexicalParent=self
    child.outerLookup=function(name) return snapshot[name] or (inheritedLookup and inheritedLookup(name)) end
    child.visible=setmetatable({},{__index=function(_,name) return child.outerLookup(name) or (self.visible and self.visible[name]) end})
    if binding.receiver then
        local schema=binding.receiver
        local storage=child.builder:storageId();child.inputs[1]=S.inPlace(schema.type)
        child.params[1]=I.PlaceParam(0,storage,schema.type)
        Source.addCapture(recursiveSlots,I.BorrowArg(I.Local(storage)),S.inPlace(schema.type))
        for _,field in ipairs(schema.type.fields) do
            child.scope[field.name]={place=I.Project(I.Local(storage),I.Field(field.name)),type=field.type,
                schema=schema.fieldSchemas and schema.fieldSchemas[field.name],localCallable=true,owner=child}
        end
    elseif binding.dynamicReceiver then
        local value=child.builder:valueId();child.inputs[1]=S.inValue(S.Any)
        child.params[1]=I.ValueParam(0,value,S.Any);child.dynamicReceiver=child.builder:ref(value,S.Any)
    end
    if binding.recursiveTemplate then
        child.scope[binding.recursiveName]={sourceTemplate=binding.recursiveTemplate,localCallable=true,owner=child}
    elseif binding.recursiveName then
        local recursive=Source.callable({definition=word,target=word.id,inputs=contract.inputs,
            results=contract.results,resultSchemas=contract.resultSchemas,keyed=contract.keyed,prefixArgs=recursiveSlots})
        child.scope[binding.recursiveName]={sourceCallable=recursive,callable=true,localCallable=true,owner=child}
    end
    if binding.parameters then binding.parameters(child)
    else
        for index,param in ipairs(contract.parameters) do
            local _,parameter=child:wordParameter(param.name and param.name.text,contract.inputs[index],param.annotation,param)
            child.parameterBindings[param]=parameter
        end
    end
    child.baseInputs=copy(child.inputs);child.baseParams=copy(child.params)
    for _,param in ipairs(contract.parameters) do
        if param.kind=='VocabularyParam' then child:expandContext(assert(child.parameterBindings[param],'missing context parameter binding'),param) end
    end
    if word.body.kind=='Expression' then child:returnValues({word.body.value},word.body.value)
    else child:statements(word.body.statements) end
    if Check.falls(child.body) then reject('missing-return','Word can finish without returning',word.origin) end
    contract.results=child.results
    local body=child:context():sequence(child.body,child.prologue)
    child:finishTransport()
    local fn=located(I.Fn(word.id,binding.role or I.Body,child.fixedHidden+#child.captureEntries,L(child.inputs),L(child.results),L(child.params),body),binding.origin or word.origin)
    child.fn=fn
    local callable=Source.callable({definition=word,target=word.id,inputs=contract.inputs,results=child.results,
        resultSchemas=resultInterfaces(word.result,self.schemas),keyed=contract.keyed,prefixArgs=slots})
    word.state='checked';word.fn=fn
    Source.whenCapturesClosed(callable,function() child:finishTransport() end)
    Source.finishCaptures(child.capturePlan)
    return fn,callable
end

-- Deferred capture reads are ordinary IR occurrences at the original formation
-- boundary. Qualification and producer identities stay in the owning context.
function Function:atFormation(point,run)
    if not point then return run() end
    assert(point.context==self:context(),'capture point belongs to another source frame')
    local previous=self.body;local statements={};self.body=statements
    local ok,result=pcall(run);self.body=previous
    if not ok then error(result,0) end
    point.context:insert(point,statements)
    return result
end

function Function:formationValue(binding,point)
    if not point then return self:bindingValue(binding,binding.origin) end
    local value=point.values[binding]
    if not value then
        value=self:atFormation(point,function() return self:bindingValue(binding,binding.origin) end)
        point.values[binding]=value
    end
    return value
end

function Function:formTemplate(contract,binding)
    if not contract.environment then
        contract.environment=self;contract.binding=copy(binding or {})
        contract.binding.lexicalScope=setmetatable(copy(self.scope),getmetatable(self.scope))
        contract.binding.formationPoint=self:context():point(self.body)
        contract.instances={};contract.serial=0;contract.root=contract
    end
    return Source.templateValue(contract,contract.definition.origin.span)
end

function Function:packComponents(value,origin)
    local values={}
    for index,binding in ipairs(value.sourcePack) do
        values[index]=self:bindingValue(self:importBinding(binding),origin)
    end
    return values
end
function Function:packBinding(node)
    node=ungroup(node)
    if node.kind=='Reference' then
        local binding=self:peekBinding(node.name.text)
        if binding and binding.sourcePack then return binding end
    end
end
function Function:packIndex(binding,node)
    local expression=self:expr(node.index)
    if not expression.type or not expression.type:isInteger() then reject('pack-index','Pack index must be a static integer',node.index) end
    if not self.lambdaState.demands:known(self:context(),expression) then reject('pack-index','Pack index must be static',node.index) end
    local constant=self.lambdaState.demands:require(self:context(),expression,self.lambdaState.resolve,node.index)
    local literal=constant.literal
    local index=literal.kind=='UInt' and literal.value or literal.kind=='UInt64' and literal.high==0 and literal.low or nil
    if not index or index<0 or index%1~=0 or index>=#binding.sourcePack then reject('pack-index','Pack index is out of range',node.index) end
    return self:importBinding(binding.sourcePack[index+1])
end

-- Template specialization builds an ordinary parameter recipe, then invokes the
-- sole word elaborator. Recipe entries select already-evaluated components; they
-- never execute arithmetic or a source body. Known code keeps its identity while
-- its holdings travel through ordinary explicit typed parameters.
function Function:templateInstance(template,values,types,schemas)
    local root=template.root
    local keys={}
    for index,value in ipairs(values) do
        if value.sourceDefinition then keys[index]='type:'..S.encode(value.sourceDefinition.type)
        elseif value.sourceCallable then
            local callable=value.sourceCallable;local supplied={}
            for id in pairs(callable.supplied) do supplied[#supplied+1]=id end;table.sort(supplied)
            keys[index]='code:'..callable.target..':'..S.encode(value.type)..':'..table.concat(supplied,',')
        else keys[index]='value:'..S.encode(value.type) end
        local schema=value.schema or value.sourceDefinition and value.sourceDefinition.schema
        if schema then keys[index]=keys[index]..':face:'..(schema.prefix or '')..schema.name end
    end
    local key=table.concat(keys,'|')
    local instance=root.instances[key]
    if instance then
        if instance.checking and not instance.contract.results then reject('result-type','Recursive template needs a result annotation',root.definition.origin) end
        if not instance.checking then
            local seen={} for _,fn in ipairs(self.generated) do seen[fn.id]=true end
            for _,fn in ipairs(instance.functions) do if not seen[fn.id] then self.generated[#self.generated+1]=fn;seen[fn.id]=true end end
        end
        return instance
    end
    root.serial=root.serial+1
    local word=copy(root.definition);word.id=root.definition.id..'_instance_'..root.serial;word.contract=nil
    local environment=setmetatable(copy(root.environment),Function)
    environment.types=types;environment.schemas=schemas;environment.sourceOwner=root.environment
    environment.generated=self.generated
    local state=copy(root.environment.lambdaState)
    state.demands=self.lambdaState.demands
    state.resolve=function(id) return self.lambdaState.resolve(id) or root.environment.lambdaState.resolve(id) end
    environment.lambdaState=state
    local contract={definition=word,target=word.id,parameters=root.parameters,inputs={},results=resultTypes(word.result,types)}
    word.contract=contract
    instance={word=word,contract=contract,recipe={},checking=true}
    root.instances[key]=instance
    local binding=copy(root.binding);binding.recursiveTemplate=root;binding.origin=root.definition.origin
    binding.parameters=function(child)
        local function slot(input,select)
            local index=#child.inputs
            local param,argument
            if input.kind=='InPlace' then
                local storage=child.builder:storageId();param=I.PlaceParam(index,storage,input.type);argument=I.BorrowArg(I.Local(storage))
            else
                local value=child.builder:valueId();param=I.ValueParam(index,value,input.type);argument=I.ValueArg(child.builder:ref(value,input.type))
            end
            child.inputs[#child.inputs+1]=input;child.params[#child.params+1]=param
            contract.inputs[#contract.inputs+1]=input;instance.recipe[#instance.recipe+1]=select
            if child.baseInputs then
                child.baseInputs[#child.baseInputs+1]=input;child.baseParams[#child.baseParams+1]=param;child:finishTransport()
            end
            return argument
        end
        local function parameter(index,name,param)
            local value=values[index]
            local parameterBinding
            if value.sourceDefinition then
                parameterBinding={sourceDefinition=value.sourceDefinition,owner=child,origin=param}
            elseif value.sourceCallable then
                local actual=value.sourceCallable;local callable=copy(actual)
                callable.captures=Source.captureStream(child.capturePlan);callable.supplied={}
                parameterBinding={sourceCallable=callable,type=value.type,owner=child,localCallable=true,origin=param}
                Source.followCaptures(actual.captures,callable.captures,function(argument,input,at)
                    input=input or S.inValue(argument.value.type)
                    local held=slot(input,function(items) return items[index].sourceCallable.captures[at] end)
                    Source.addCapture(callable.captures,held,input)
                end)
                for _,requirement in ipairs(actual.original) do
                    if actual.supplied[requirement.identity] then
                        local identity=requirement.identity
                        callable.supplied[identity]=slot(requirement.input,function(items) return items[index].sourceCallable.supplied[identity] end)
                    end
                end
            else
                local input=S.inValue(value.type)
                local _,produced=child:wordParameter(name,input,nil,param)
                parameterBinding=produced
                parameterBinding.schema=value.schema or schemaName(param.annotation,schemas)
                contract.inputs[#contract.inputs+1]=input
                instance.recipe[#instance.recipe+1]=function(items) return I.ValueArg(items[index]) end
            end
            if name then child.scope[name]=parameterBinding end
            child.parameterBindings[param]=parameterBinding
            return parameterBinding
        end
        local fixed=#root.parameters
        if fixed>0 and root.parameters[fixed].kind=='RestParam' then fixed=fixed-1 end
        for index=1,fixed do local param=root.parameters[index];parameter(index,param.name and param.name.text,param) end
        if fixed<#root.parameters then
            local components={}
            for index=fixed+1,#values do
                components[#components+1]=parameter(index,nil,root.parameters[#root.parameters])
            end
            child.scope[root.parameters[#root.parameters].name.text]={sourcePack=components,owner=child,origin=root.definition.origin}
        end
    end
    local before=#self.generated
    local ok,fn,callable=pcall(environment.elaborateWord,environment,word,contract,binding)
    if not ok then root.instances[key]=nil;error(fn,0) end
    instance.checking=nil;instance.fn=fn;instance.callable=callable
    self.generated[#self.generated+1]=fn
    instance.functions={}
    for index=before+1,#self.generated do instance.functions[#instance.functions+1]=self.generated[index] end
    return instance
end

function Function:templateCall(node,template,expected,discard,allResults,prepareOnly,continuing,lexicalReceiver)
    local root=template.root;local values=copy(template.supplied)
    local types=setmetatable({},{__index=root.environment.types})
    local schemas=setmetatable({},{__index=root.environment.schemas})
    local fixed=#root.parameters
    local rest=fixed>0 and root.parameters[fixed].kind=='RestParam'
    if rest then fixed=fixed-1 end
    local function wanted(index)
        local param=root.parameters[index]
        if index>fixed then return nil end
        return param.annotation and typeExpr(param.annotation,types) or (self.dynamic and S.Any or nil)
    end
    local function accept(value,index,origin)
        if index<=fixed then
            local param=root.parameters[index];local ty=wanted(index)
            if ty==S.Type then
                if not value.sourceDefinition or value.sourceDefinition.kind~='type' then reject('type-required','Static Type requirement needs a concrete type definition',origin) end
                if param.name then types[param.name.text]=value.sourceDefinition.type;schemas[param.name.text]=value.sourceDefinition.schema end
            else
                if not ty then reject('parameter-type',(param.name and 'Parameter `'..param.name.text..'`' or 'Unnamed context parameter')..' needs a type annotation',param) end
                if not value.sourceCallable or value.type~=ty then value=self:coerce(value,ty,origin) end
            end
        elseif not rest then reject('arity','Template has no remaining ordered requirement',origin)
        elseif value.sourceDefinition then reject('definition-value','Compile-time definitions are not runtime pack components',origin) end
        if value.sourcePack then reject('pack-use','Expand a pack when supplying components',origin) end
        value=self:snapshotArgument(value,origin);values[index]=value
        return value
    end
    for index,value in ipairs(values) do accept(value,index,node) end
    if lexicalReceiver then
        local ty=wanted(#values+1)
        if not ty then reject('arity','Receiver call needs a fixed first requirement',node) end
        accept(self:receiverArgument(lexicalReceiver,S.inValue(ty),node),#values+1,node)
    end
    local offset=#values
    self:supplies(node.arguments,function(index)
        local ty=wanted(offset+index);return ty~=S.Type and ty or nil
    end,nil,function(value,index,origin) return accept(value,offset+index,origin) end,
    function(index) return wanted(offset+index)==S.Type end)
    if #values<fixed then
        if prepareOnly then reject('arity','A deferred action must be saturated',node) end
        for index,value in ipairs(values) do
            if not continuing and not value.sourceDefinition and not value.sourceCallable then
                values[index]=self.lambdaState.demands:require(self:context(),value,self.lambdaState.resolve,node)
            end
        end
        local partial=copy(template);partial.supplied=values
        return Source.templateValue(partial,node.span)
    end
    local instance=self:templateInstance(template,values,types,schemas)
    local callable=instance.callable
    if instance.checking then
        local child=instance.word.child
        callable=Source.callable{target=instance.word.id,inputs=instance.contract.inputs,results=instance.contract.results,prefixArgs=child.recursiveSlots}
    elseif #callable.captures>0 and self~=root.environment then
        callable=self:importBinding{sourceCallable=callable,type=S.View(S.Sig(callable.inputs,callable.results)),owner=root.environment}.sourceCallable
    end
    local target={inputs=instance.contract.inputs,results=instance.contract.results}
    local function arguments()
        local args={}
        if template.receiverArgument then args[#args+1]=template.receiverArgument end
        for _,arg in ipairs(callable.captures) do args[#args+1]=arg end
        for _,select in ipairs(instance.recipe) do args[#args+1]=select(values) end
        return args
    end
    local function emit(body)
        local ids={} for index=1,#target.results do ids[index]=self.builder:valueId() end
        local stmt=located(I.Call(L(ids),instance.word.id,L{}),node);stmt.capturePending=true
        local function ready() stmt.arguments=L(arguments());stmt.capturePending=nil end
        local function holds(index)
            if index>#values then Source.whenCapturesClosed(callable,ready);return end
            local value=values[index]
            if value.sourceCallable then Source.whenCapturesClosed(value.sourceCallable,function() holds(index+1) end)
            else holds(index+1) end
        end
        holds(1);self.builder:emit(body or self.body,stmt)
        return ids
    end
    if prepareOnly then return {target=target,node=node,templateEmit=emit} end
    local ids=emit()
    if discard then return end
    local refs={}
    local resultSchemas=instance.callable and instance.callable.resultSchemas or instance.contract.resultSchemas
    for index,id in ipairs(ids) do
        refs[index]=located(self.builder:ref(id,target.results[index]),node)
        refs[index].schema=resultSchemas and resultSchemas[index]
    end
    if allResults then return refs end
    return self:coerce(refs[1],expected,node)
end

function Function:lambda(node, expected, inferResults)
    self.lambdaState.count=self.lambdaState.count+1
    local word=Source.word(node,self.id..'_word_'..self.lambdaState.count)
    local contract=wordContract(word,self.types,self.dynamic,expected,inferResults)
    if contract.sourceTemplate then return self:formTemplate(contract) end
    local fn,callable=self:elaborateWord(word,contract)
    self.generated[#self.generated+1]=fn
    return Source.value(callable,node.span)
end

function Function:methodTarget(binding, methodName, owner)
    local schema=binding.schema
    local def=schema and schema.methods[methodName] or nil
    if not def then return nil end
    local key=(schema.prefix or "")..schema.name.."."..methodName
    local environment=schema.environment or self
    local descriptor=environment.methodState[key]
    if not descriptor then
        local word=Source.word(def,(schema.prefix or '')..'__method_'..schema.name..'_'..methodName)
        descriptor=wordContract(word,environment.types,environment.dynamic)
        environment.methodState[key]=descriptor
        if descriptor.sourceTemplate then environment:formTemplate(descriptor,{receiver=schema,recursiveName=methodName,origin=owner})
        else
            local fn=environment:elaborateWord(word,descriptor,{receiver=schema,recursiveName=methodName,lexicalScope=environment.scope,origin=owner})
            environment.generated[#environment.generated+1]=fn
        end
    end
    if environment~=self then
        for _,fn in ipairs(environment.generated) do if not self.lambdaState.resolve(fn.id) then self.generated[#self.generated+1]=fn end end
    end
    local receiver=self:bindingPlace(binding)
    if receiver and (binding.type:isRef() or binding.type:isPtr()) then receiver=I.Deref(receiver,self:sealed(binding.type.target)) end
    if not receiver then reject("not-a-place","A method needs an addressable receiver",owner) end
    if receiver.kind~='Local' then
        -- Binding a receiver evaluates its address now, not after later argument
        -- effects (or when an alias/deferred action is eventually invoked).
        local ty=S.Ptr(schema.type)
        local address=self.builder:let(self.body,ty,located(self.builder:addr(receiver,ty),owner))
        receiver=I.PtrIndex(self.builder:ref(address,ty),self.builder:u32(0),schema.type)
    end
    if descriptor.sourceTemplate then
        local bound=copy(descriptor);bound.receiverArgument=I.BorrowArg(receiver)
        return bound
    end
    return {definition=descriptor.definition,target=descriptor.target,inputs=descriptor.inputs,results=descriptor.results,keyed=descriptor.keyed,prefixArgs={I.BorrowArg(receiver)},prefixInputs={S.inPlace(schema.type)}}
end

-- Receiver selection is metadata over the ordinary value/place model. It does
-- not detach a method, build a closure, or change ordinary argument conversion.
function Function:receiverInfo(node,binding)
    if not binding then
        node=ungroup(node)
        if node.kind=='Reference' or node.kind=='CurrentContext' or node.kind=='FieldSelect' or node.kind=='IndexExpr' then binding=self:placeBinding(node) end
        if not binding and node.kind=='IndexExpr' then
            local place,ty=self:place(node);binding={place=place,type=ty}
        end
    end
    if binding and binding.type then
        return {binding=binding,type=binding.type,schema=binding.schema,
            place=self:bindingPlace(binding),origin=node}
    end
    local value=self:expr(node)
    return {value=value,type=value.type,schema=value.schema,origin=node}
end

function Function:receiverValue(receiver)
    if not receiver.value then receiver.value=self:bindingValue(receiver.binding,receiver.origin) end
    return receiver.value
end

function Function:receiverSelection(receiver,name,owner)
    local ty=self:sealed(receiver.type)
    if ty==S.Any then
        local key=self.builder:const(S.String,I.Str(name.text))
        return self:dynamicWord('WordGet',{self:receiverValue(receiver),key},owner)
    end
    local interface=receiver.schema
    if interface and interface.methods[name.text] then
        local binding=receiver.binding or {type=receiver.type,schema=interface}
        return nil,self:methodTarget(binding,name.text,owner)
    end
    local dataType=(ty:isRef() or ty:isPtr()) and self:sealed(ty.target) or ty
    local field=S.field(dataType,name.text)
    if field then
        local value
        if receiver.place then
            local place=receiver.place
            if ty:isRef() or ty:isPtr() then place=I.Deref(place,dataType) end
            value=self.builder:ref(self.builder:read(self.body,field,I.Project(place,I.Field(name.text))),field)
        else value=self.builder:get(self:receiverValue(receiver),name.text,field) end
        return located(value,owner)
    end
    if ty:isSlice() and name.text=='length' then
        return located(self.builder:sliceLength(self:receiverValue(receiver),S.U32),owner)
    end
    -- Resolve exactly one lexical binding, not candidates chosen by argument types.
    local reference={kind='Reference',name=name,span=owner.span}
    local callable=self:expr(reference)
    if callable.type==S.Any then reject('receiver-callable','Lexical receiver calls need a known callable interface',owner) end
    return callable,nil,receiver
end

function Function:receiverArgument(receiver,input,owner)
    if not input then reject('arity','Receiver call needs a first ordered parameter',owner) end
    local wanted=input.type
    local value
    if wanted:isRef() and not receiver.type:isRef() then
        if not receiver.place then
            if receiver.origin.kind=='Reference' then reject('not-a-place','Reference receiver needs a writable place',receiver.origin) end
            reject('receiver-temporary','Cannot borrow a temporary receiver; bind it first',receiver.origin)
        end
        if not self:sameType(receiver.type,wanted.target) then reject('type-mismatch','Receiver does not match the reference parameter',owner) end
        value=located(self.builder:addr(receiver.place,wanted),receiver.origin)
    else value=self:coerce(self:receiverValue(receiver),wanted,receiver.origin) end
    return self:snapshotArgument(value,receiver.origin)
end

function Function:usesImplicitReceiver(name)
    if not self:peekBinding(RECEIVER_SCOPE) then return false end
    local binding=self:peekBinding(name)
    if binding and binding.localCallable then return false end
    if not binding and not self.signatures[name] and not self.globals[name] then
        if BUILTIN_TYPES[name] or VOCABULARY_BUILTINS[name] or (self.dynamic and DYNAMIC_VOCABULARY[name]) then return false end
    end
    local definition=binding and binding.sourceDefinition
    return not definition or definition.kind=='word' or definition.kind=='constructor'
end

function Function:boundMethod(node,expected)
    local receiver=self:placeBinding(node.base)
    local target=receiver and receiver.schema and self:methodTarget(receiver,node.field.text,node) or nil
    if not target then return nil end
    if target.sourceTemplate then
        if expected then reject('template-use','A template method has no erased runtime signature',node) end
        return Source.templateValue(target,node.span)
    end
    if target.keyed then reject("keyed-required","A keyed method must be supplied by key before it becomes a value",node) end
    self:requireContract(target,node)
    local ty=S.View(S.Sig(target.inputs,target.results))
    if expected and expected~=ty and expected~=S.Any then reject("type-mismatch","Method value does not match the expected callable signature",node) end
    local value=Source.value(Source.callable(target),node.span)
    return expected==S.Any and self:coerce(value,expected,node) or value
end


function Function:indirectPartial(node,indirect,target,args,expected)
    if not self.managed then reject("slet-forbidden","SLet cannot retain a runtime callable for partial application",node) end
    self.lambdaState.count=self.lambdaState.count+1;local id=self.id.."_indirect_partial_"..self.lambdaState.count
    local builder=IR.builder();local inputs,params,slots={},{},{}
    local callableValue=indirect.expr or self.builder:ref(indirect.value,indirect.type)
    inputs[1]=S.inValue(indirect.type);local heldCallable=builder:valueId();params[1]=I.ValueParam(0,heldCallable,indirect.type);slots[1]=I.ValueArg(callableValue)
    local heldArgs={}
    for index,arg in ipairs(args) do local ty=target.inputs[index].type;inputs[#inputs+1]=S.inValue(ty);local value=builder:valueId();params[#params+1]=I.ValueParam(#inputs-1,value,ty);heldArgs[#heldArgs+1]=I.ValueArg(builder:ref(value,ty));slots[#slots+1]=arg end
    local remaining={}
    for index=#args+1,#target.inputs do local input=target.inputs[index];remaining[#remaining+1]=input;inputs[#inputs+1]=input;local value=builder:valueId();params[#params+1]=I.ValueParam(#inputs-1,value,input.type);heldArgs[#heldArgs+1]=I.ValueArg(builder:ref(value,input.type)) end
    local values={} for index=1,#target.results do values[index]=builder:valueId() end
    local body={I.Indirect(L(values),builder:ref(heldCallable,indirect.type),L(heldArgs))};local returned={} for index,value in ipairs(values) do returned[index]=builder:ref(value,target.results[index]) end;body[#body+1]=I.Return(L(returned))
    self.generated[#self.generated+1]=located(I.Fn(id,I.Body,1+#args,L(inputs),L(target.results),L(params),L(body)),node)
    local ty=S.View(S.Sig(remaining,target.results));if expected and expected~=ty then reject("type-mismatch","Partial application does not match the expected callable signature",node) end
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.View(value,ty,id,L(slots),self.builder:storageId()),node));return self.builder:ref(value,ty)
end

function Function:dynamicWord(operation,operands,node)
    local dynamic={} for index,operand in ipairs(operands or {}) do dynamic[index]=self:coerce(operand,S.Any,node) end
    local op=type(operation)=="string" and I[operation] or operation
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.Dynamic(L({value}),op,L(dynamic)),node))
    local ty=op.kind=="WordHas" and S.Bool or op.kind=="WordCount" and S.U32 or S.Any
    return self.builder:ref(value,ty)
end

function Function:openMethod(stmt)
    if not self.dynamic then reject("slet-forbidden","SLet cannot define an open-word method",stmt) end
    local binding=self:lookupBinding(stmt.receiver.text)
    if not binding then reject("unknown-name","Unknown open-word receiver `"..stmt.receiver.text.."`",stmt.receiver) end
    local receiver
    if binding.storage then local value=self.builder:read(self.body,binding.type,I.Local(binding.storage));receiver=self.builder:ref(value,binding.type)
    else receiver=self.builder:ref(binding.value,binding.type) end
    receiver=self:coerce(receiver,S.Any,stmt.receiver)
    self.lambdaState.count=self.lambdaState.count+1;local id=self.id..'_open_method_'..self.lambdaState.count
    local word=Source.word(stmt.def,id);local contract=wordContract(word,self.types,self.dynamic)
    if contract.keyed then reject('parse','An open-word method uses positional parameters',stmt.def) end
    local fn=self:elaborateWord(word,contract,{dynamicReceiver=true,lexicalScope={},origin=stmt})
    self.generated[#self.generated+1]=fn
    local callable=self.builder:valueId();self.builder:emit(self.body,located(I.View(callable,S.Any,id,L{},nil),stmt))
    local key=self.builder:const(S.String,I.Str(stmt.def.name.text))
    self:dynamicWord("WordMethod",{receiver,key,self.builder:ref(callable,S.Any)},stmt)
end

function Function:wordBinding(node,name,expected,owner)
    if self.scope[name] then reject('duplicate-name','Local name `'..name..'` is declared twice',owner) end
    self.lambdaState.count=self.lambdaState.count+1
    local word=Source.word(node,self.id..'_word_'..self.lambdaState.count)
    local contract=wordContract(word,self.types,self.dynamic,expected)
    if contract.sourceTemplate then return self:formTemplate(contract,{recursiveName=name,origin=owner}) end
    local fn,callable=self:elaborateWord(word,contract,{recursiveName=name,origin=owner})
    self.generated[#self.generated+1]=fn
    return Source.value(callable,owner and owner.span or node.span)
end

function Function:localWord(def, owner)
    local name=def.name.text
    local value=self:wordBinding(def,name,nil,owner)
    self.scope[name]={sourceTemplate=value.sourceTemplate,sourceCallable=value.sourceCallable,type=value.type,callable=true,origin=owner,localCallable=true,owner=self}
end

-- First-class transport is the only place that creates a callable environment.
-- Its ownership check and layout wait for the selected word's complete captures.
function Function:finishCallableView(view,callable,expr)
    if #callable.captures>0 and not self.managed then
        reject('slet-forbidden','Materialized word captures need an owned representation',expr)
    end
    local target,slots=callable.target,{}
    for _,arg in ipairs(callable.captures) do slots[#slots+1]=arg end
    local hasSupply=next(callable.supplied)~=nil
    if hasSupply then
        -- A boundary adapter binds arbitrary original requirement positions, including
        -- keyed holes. Direct invocation never constructs this wrapper/environment.
        target=view.entry
        local builder=IR.builder();local inputs,params,arguments={},{},{}
        local function parameter(input)
            local index=#inputs;inputs[#inputs+1]=input
            if input.kind=="InPlace" then
                local storage=builder:storageId();params[#params+1]=I.PlaceParam(index,storage,input.type)
                return I.BorrowArg(I.Local(storage))
            end
            local value=builder:valueId();params[#params+1]=I.ValueParam(index,value,input.type)
            return I.ValueArg(builder:ref(value,input.type))
        end
        -- Captures already have the ABI's original hidden-prefix order.
        for index,arg in ipairs(callable.captures) do
            local ty
            if arg.kind=="ValueArg" then ty=S.inValue(arg.value.type)
            else ty=assert(callable.captures.inputs and callable.captures.inputs[index],'missing capture layout') end
            arguments[#arguments+1]=parameter(ty)
        end
        local supplied={}
        for _,requirement in ipairs(callable.original) do
            local arg=callable.supplied[requirement.identity]
            if arg then slots[#slots+1]=arg;supplied[requirement.identity]=parameter(requirement.input) end
        end
        local hidden=#inputs
        for _,requirement in ipairs(callable.requirements) do supplied[requirement.identity]=parameter(requirement.input) end
        for _,requirement in ipairs(callable.original) do arguments[#arguments+1]=supplied[requirement.identity] end
        local values,returned={},{}
        for index,ty in ipairs(callable.results) do values[index]=builder:valueId();returned[index]=builder:ref(values[index],ty) end
        local body={I.Call(L(values),callable.target,L(arguments)),I.Return(L(returned))}
        self.generated[#self.generated+1]=I.Fn(target,I.Body,hidden,L(inputs),L(callable.results),L(params),L(body))
    end
    view.entry=target;view.slots=L(slots);view.adapter=#slots>0 and self.builder:storageId() or nil
    view.capturePending=nil
end

function Function:materializeCallable(expr)
    if expr.sourcePack then reject('pack-use','Packs have no ordinary runtime representation',expr) end
    if expr.sourceTemplate then reject('template-use','Templates have no erased runtime representation',expr) end
    if expr.sourceDefinition then reject('definition-value','Compile-time definitions have no runtime representation',expr) end
    if not expr.sourceCallable then return expr end
    local callable=expr.sourceCallable
    local value=self.builder:valueId()
    local target=callable.target
    if next(callable.supplied) then
        self.lambdaState.count=self.lambdaState.count+1
        target=self.id..'_bound_'..self.lambdaState.count
    end
    local view=located(I.View(value,expr.type,target,L{},nil),expr)
    view.capturePending=true
    Source.whenCapturesClosed(callable,function() self:finishCallableView(view,callable,expr) end)
    self.builder:emit(self.body,view)
    local result=located(self.builder:ref(value,expr.type),expr)
    return result
end

function Function:coerce(expr, expected, node)
    if expr.sourcePack then reject('pack-use','Use spread, length or static indexing on a pack',node) end
    if expr.sourceTemplate then
        if expected then reject('template-use','Templates have no erased runtime representation',node) end
        return expr
    end
    if expr.sourceDefinition then
        if expected then reject('definition-value','Compile-time definitions have no runtime representation',node) end
        return expr
    end
    if expr.sourceCallable and expected then expr=self:materializeCallable(expr) end
    if not expected or expr.type==expected then return expr end
    if self:sameType(expr.type,expected) then
        if expr.kind=="Ref" then return located(self.builder:ref(expr.value,expected),node) end
        if expr.kind=="Addr" then return located(self.builder:addr(expr.place,expected),node) end
        if expr.kind=="Null" then return located(self.builder:nullPtr(expected),node) end
    end
    if expected==S.Any and (expr.type:isRecord() or expr.type:isArray() or expr.type:isTaggedType()) then
        local storage=self.builder:var(self.body,expr.type,expr);return located(self.builder:convert(self.builder:addr(I.Local(storage),S.Ref(expr.type)),S.Any),node)
    end
    if (expr.type==S.Any and expected~=S.Type) or (expected==S.Any and expr.type~=S.Type) then return located(self.builder:convert(expr,expected),node) end
    if (expr.type:isInteger() or expr.type==S.F64) and (expected:isInteger() or expected==S.F64) then return located(self.builder:convert(expr,expected),node) end
    reject("type-mismatch", "Expected "..S.display(expected).." but found "..S.display(expr.type), node)
end

-- One source result-list rule for calls, returns and bindings. Parenthesized
-- expressions go through expr and therefore contribute exactly one value.
function Function:supplies(nodes, expectedAt, bindingAt, finishAt, allowDefinitionAt)
    local values,origins={},{}
    for index,node in ipairs(nodes) do
        local expanded=node.kind=='Spread'
        local item=expanded and node.value or node
        local expected=expectedAt and expectedAt(#values+1)
        local produced
        local binder=not expanded and bindingAt and bindingAt(#values+1)
        local instance=binder and self:instanceBinding(item,expected)
        local pack=expanded and self:packBinding(item)
        if pack then
            produced={Source.pack(pack.sourcePack,item.span)}
        elseif instance then
            produced={Source.instance(instance,node.span)}
        elseif binder and ungroup(item).kind=='Lambda' then
            produced={self:wordBinding(ungroup(item),binder.name.text,expected,item)}
        elseif (expanded or index==#nodes) and item.kind=='Apply' then
            produced=self:call(item,not expanded and expected or nil,false,true)
            if produced.kind then produced={produced} end
        else produced={self:expr(item,not expanded and expected or nil,bindingAt~=nil or allowDefinitionAt and allowDefinitionAt(#values+1))} end
        if expanded and #produced==1 then
            local source=produced[1]
            if source.sourcePack then produced=self:packComponents(source,item)
            elseif source.type and source.type:isArray() then
                source=self:snapshotArgument(source,item);produced={}
                for at=0,source.type.length-1 do produced[#produced+1]=self.builder:get(source,at,source.type.element) end
            else reject('spread-source','Ordered spread needs multiple results, a pack or a fixed array',item) end
        end
        for _,value in ipairs(produced) do
            if finishAt then value=finishAt(value,#values+1,node)
            elseif not value.instance then value=self:snapshotArgument(value,node) end
            values[#values+1]=value;origins[#origins+1]=node
        end
    end
    return values,origins
end

-- Only consecutive Apply nodes share a pending application. Group, field/index
-- selection and keyed supplies are explicit boundaries and go through expr normally.
function Function:call(node, expected, discard, allResults, prepareOnly)
    local chain={};local cursor=node
    while cursor.kind=='Apply' do chain[#chain+1]=cursor;cursor=cursor.callee end
    local value,pending
    for index=#chain,1,-1 do
        local final=index==1
        value,pending=self:callSuffix(chain[index],final and expected or nil,
            final and discard,final and allResults,final and prepareOnly,not final,pending,value)
    end
    return value
end

function Function:snapshotArgument(value,origin)
    if value.sourceCallable or value.sourceDefinition or value.sourceTemplate or value.sourcePack then return value end
    if value.kind=='Const' or value.kind=='Ref' then return value end
    local components=require('let.layout').valueComponents(value.type)
    if components~=false and #components==0 then return value end
    local id=self.builder:let(self.body,value.type,located(value,origin))
    local result=located(self.builder:ref(id,value.type),origin)
    result.schema=value.schema
    return result
end

function Function:callSuffix(node, expected, discard, allResults, prepareOnly, continuing, pending, calleeValue)
    local name,callable,selectedMethod,lexicalReceiver
    local implicit=not pending and not calleeValue and node.callee.kind=='Reference'
        and self:usesImplicitReceiver(node.callee.name.text) and self:activeReceiver()
    local definition=not implicit and not pending and not calleeValue and self:resolveDefinition(node.callee)
    if definition and definition.kind=='type' then
        local primitive=false;for _,ty in pairs(BUILTIN_TYPES) do if ty==definition.type then primitive=true end end
        if primitive and #node.arguments==1 then return self:coerce(self:expr(node.arguments[1],definition.type),definition.type,node) end
        reject('type-mismatch','A type needs its declared construction form',node)
    elseif definition and definition.kind=='namespace' then reject('type-mismatch','A namespace is not callable',node) end
    if implicit then
        callable,selectedMethod,lexicalReceiver=self:receiverSelection(
            self:receiverInfo(implicit.origin,implicit.binding),node.callee.name,node.callee)
    elseif not definition and not pending and not calleeValue and node.callee.kind=='FieldSelect' then
        callable,selectedMethod,lexicalReceiver=self:receiverSelection(
            self:receiverInfo(node.callee.base),node.callee.field,node.callee)
    end
    if pending then name=pending.name
    elseif calleeValue then callable=calleeValue;name='<callable>'
    elseif callable then name='<receiver>'
    elseif definition then callable=self:definitionValue(definition,node.callee);name='<definition>'
    elseif selectedMethod then name="<method>"
    elseif node.callee.kind=="Reference" then
        local reference=node.callee.name.text
        if self:peekBinding(reference) or self.globals[reference] or (self.dynamicReceiver and not self.signatures[reference]) then callable=self:expr(node.callee);name='<callable>' else name=reference end
    else callable=self:expr(node.callee);name="<callable>" end
    local binding=not pending and not calleeValue and node.callee.kind=="Reference" and self:lookupBinding(name) or nil
    local knownWord=pending and pending.knownWord or selectedMethod or (binding and binding.sourceCallable)
    if callable and callable.sourceCallable then knownWord=callable.sourceCallable;callable=nil end
    if callable and callable.sourceTemplate then
        return self:templateCall(node,callable.sourceTemplate,expected,discard,allResults,prepareOnly,continuing,lexicalReceiver)
    end
    if selectedMethod and selectedMethod.sourceTemplate then
        return self:templateCall(node,selectedMethod,expected,discard,allResults,prepareOnly,continuing)
    end
    local indirect=pending and pending.indirect or (not knownWord and (callable and {type=callable.type,expr=callable} or binding and binding.type and binding or nil))
    if not pending and (name=="Ref" or name=="Ptr") then
        if #node.arguments~=1 then reject("arity",name.." expects one place",node) end
        local place,ty=self:place(node.arguments[1]);return located(self.builder:addr(place,name=="Ref" and S.Ref(ty) or S.Ptr(ty)),node)
    elseif name=="null" then
        if #node.arguments~=1 then reject("arity","null expects one element type",node) end
        return located(self.builder:nullPtr(S.Ptr(typeExpr(node.arguments[1],self.types))),node)
    elseif name=="Slice" then
        if #node.arguments~=1 then reject("arity","slice expects one array",node) end
        local place,ty=self:place(node.arguments[1]);if not ty:isArray() then reject("type-mismatch","slice expects an array place",node.arguments[1]) end
        local first=I.Index(place,self.builder:u32(0),ty.element);local address=self.builder:addr(first,S.Ref(ty.element),S.Borrow.ReadAccess)
        return located(self.builder:make(S.Slice(ty.element),{address,self.builder:u32(ty.length)}),node)
    end
    if self.dynamic and not binding and not pending then
        local arities={open=0,has=2,remove=2,count=1,key=2,freeze=1}
        local arity=arities[name]
        if arity then
            if #node.arguments~=arity then reject("arity",name.." expects "..arity.." arguments",node) end
            local operands={} for index,argument in ipairs(node.arguments) do operands[index]=self:expr(argument) end
            local operations={open="WordNew",has="WordHas",remove="WordRemove",count="WordCount",key="WordKey",freeze="WordFreeze"}
            local result=self:dynamicWord(operations[name],operands,node)
            if name=="has" then return located(result,node) end
            if name=="count" then return located(result,node) end
            if name=="remove" then return located(self.builder:const(S.Unit,I.UInt(0)),node) end
            return located(result,node)
        end
    end
    if name=="is" then
        if #node.arguments~=2 then reject("arity","is expects a value and a type",node) end
        local operand=self:coerce(self:expr(node.arguments[1]),S.Any,node.arguments[1]);local tested=typeExpr(node.arguments[2],self.types)
        return located(self.builder:isType(operand,tested),node)
    end
    local target
    if pending then target=pending.target
    elseif indirect and indirect.type==S.Any then
        local inputs={} for index=1,#node.arguments do inputs[index]=S.inValue(S.Any) end;target={inputs=inputs,results={S.Any},dynamic=true}
    else
        if indirect and not indirect.type:isView() then reject("type-mismatch","Callee is not callable",node.callee) end
        target=knownWord or (indirect and {inputs=indirect.type.visible.inputs,results=indirect.type.visible.results} or self.signatures[name])
    end
    if not target then
        local conversion=BUILTIN_TYPES[name]
        if conversion and #node.arguments==1 then return self:coerce(self:expr(node.arguments[1],conversion),conversion,node) end
        reject("unknown-name", "Unknown word `"..name.."`", node.callee)
    end
    self:requireContract(target,node)
    if target.keyed and not (target.sourceCallable and next(target.supplied)) then reject("keyed-required","Word `"..name.."` must be supplied by key",node) end
    local args=pending and pending.args or {};local origins=pending and pending.origins or {}
    if lexicalReceiver then
        local receiver=self:receiverArgument(lexicalReceiver,target.inputs[1],node.callee)
        args[1]=I.ValueArg(receiver);origins[1]=lexicalReceiver.origin
    end
    local offset=#args
    local supplied,newOrigins=self:supplies(node.arguments,function(index)
        local input=target.inputs[offset+index];return input and input.type
    end,nil,function(value,index,origin)
        local at=offset+index
        if target.dynamic and not target.inputs[at] then target.inputs[at]=S.inValue(S.Any) end
        if not target.inputs[at] then reject('arity','Word `'..name..'` has only '..(#target.inputs-offset)..' remaining arguments in this suffix',node) end
        value=self:coerce(value,target.inputs[at].type,origin)
        return self:snapshotArgument(value,origin)
    end)
    for index,value in ipairs(supplied) do
        args[#args+1]=I.ValueArg(value);origins[#origins+1]=newOrigins[index]
    end
    if continuing and #args<#target.inputs then
        return nil,{target=target,name=name,knownWord=knownWord,indirect=indirect,args=args,origins=origins}
    end
    local source=not indirect and Source.callable(target,name) or nil
    local application=source and Source.supply(source,args) or nil
    if prepareOnly then
        if #args<#target.inputs then reject("arity","A deferred action must be a saturated call",node) end
        return {target=target,name=name,indirect=indirect,application=application,args=args,node=node}
    end
    if #args<#target.inputs then
        local runtimeSupply=false for _,argument in ipairs(args) do if not self.lambdaState.demands:known(self:context(),argument.value) then runtimeSupply=true;break end end
        if runtimeSupply and self.dynamic and source and #source.captures==0 and not next(source.supplied) and not target.foreign then
            local callableValue=self.builder:valueId();self.builder:emit(self.body,located(I.View(callableValue,S.Any,target.target or name,L{},nil),node))
            local dynamicArgs={} for _,arg in ipairs(args) do dynamicArgs[#dynamicArgs+1]=I.ValueArg(self:coerce(arg.value,S.Any,node)) end
            local result=self.builder:valueId();self.builder:emit(self.body,located(I.Indirect(L({result}),self.builder:ref(callableValue,S.Any),L(dynamicArgs)),node))
            return self.builder:ref(result,S.Any)
        end
        if indirect then return self:indirectPartial(node,indirect,target,args,expected) end
        for index,argument in ipairs(args) do
            args[index]=I.ValueArg(self.lambdaState.demands:require(self:context(),argument.value,self.lambdaState.resolve,origins[index]))
        end
        application=Source.supply(Source.callable(target,name),args)
        local result=Source.value(application,node.span)
        if expected and expected~=result.type then reject("type-mismatch","Partial application does not match the expected callable signature",node) end
        return result
    end
    local values={} for index=1,#target.results do values[index]=self.builder:valueId() end
    if indirect then
        local callableValue=indirect.expr or self.builder:ref(indirect.value,indirect.type)
        self.builder:emit(self.body,located(I.Indirect(L(values),callableValue,L(args)),node))
    else self:emitSourceCall(values,application,node) end
    if discard then return end
    local refs={} for index,value in ipairs(values) do
        refs[index]=located(self.builder:ref(value,target.results[index]),node);refs[index].schema=target.resultSchemas and target.resultSchemas[index] or nil
    end
    if allResults then return refs end
    return refs[1] or self.builder:const(S.Unit,I.UInt(0))
end
function Function:invokePrepared(call)
    if call.templateEmit then call.templateEmit();return end
    local values={} for index=1,#call.target.results do values[index]=self.builder:valueId() end
    if call.indirect then
        local callableValue=call.indirect.expr or self.builder:ref(call.indirect.value,call.indirect.type)
        self.builder:emit(self.body,located(I.Indirect(L(values),callableValue,L(call.args)),call.node))
    else
        self:emitSourceCall(values,call.application,call.node)
    end
end

function Function:emitDefers()
    for scopeIndex=#self.deferScopes,1,-1 do
        local actions=self.deferScopes[scopeIndex]
        for actionIndex=#actions,1,-1 do self:invokePrepared(actions[actionIndex]) end
    end
end

function Function:keyedSupply(node,target,expected)
    self:requireContract(target,node)
    if target.sourceTemplate then reject('template-use','Static Type templates require ordered supplies',node) end
    local byName,keyIndex={},{}
    for index,name in ipairs(target.keyed) do keyIndex[name]=index end
    local contributions=self:keyedContributions(node.fields,function(name,origin)
        local index=keyIndex[name]
        if not index and not self.dynamic then reject('unknown-field','Unknown requirement `'..name..'`',origin) end
        return index and target.inputs[index].type or S.Any
    end)
    local suppliedOrder,runtime={},false
    for _,entry in ipairs(contributions) do
        local name,index,value=entry.name,keyIndex[entry.name],entry.value
        byName[name]=I.ValueArg(value);suppliedOrder[#suppliedOrder+1]={name=name,index=index,arg=byName[name],node=entry.node}
        if not index or not self.lambdaState.demands:known(self:context(),value) then runtime=true end
    end
    if runtime and (#contributions<#target.inputs or self.dynamic) then
        if not self.managed then reject("slet-forbidden","SLet cannot retain a runtime keyed callable",node) end
        if target.sourceCallable or #(target.prefixArgs or {})>0 then
            reject('semantic-todo','Runtime keyed supply of source-specialized or captured words is not implemented',node)
        end
        if target.foreign then reject("static-foreign","A foreign word cannot be opened by runtime keyed supply",node) end
        if #target.inputs==0 then reject("arity","A word with no requirements cannot be opened by keyed supply",node) end
        local callable=self.builder:valueId();self.builder:emit(self.body,located(I.View(callable,S.Any,target.target,L{},nil),node))
        local opened=self.builder:valueId();self.builder:emit(self.body,located(I.Indirect(L({opened}),self.builder:ref(callable,S.Any),L{}),node))
        local word=self.builder:ref(opened,S.Any)
        for _,supply in ipairs(suppliedOrder) do
            local key=self.builder:const(S.String,I.Str(supply.name))
            word=self:dynamicWord(supply.index and I.WordBind(supply.index-1) or "WordSet",{word,key,supply.arg.value},supply.node)
        end
        return located(word,node)
    end
    local supplies={} for _,supply in ipairs(suppliedOrder) do
        supplies[supply.index]=#contributions<#target.inputs and I.ValueArg(self.lambdaState.demands:require(self:context(),supply.arg.value,self.lambdaState.resolve,supply.node)) or supply.arg
    end
    local application=Source.supply(Source.callable(target),supplies)
    if #application.requirements>0 then
        local result=Source.value(application,node.span)
        if expected and expected~=result.type then reject("type-mismatch","Partial keyed supply does not match the expected callable signature",node) end
        return result
    end
    local values={} for index=1,#target.results do values[index]=self.builder:valueId() end
    self:emitSourceCall(values,application,node)
    if #target.results~=1 then reject("result-arity","A keyed call used as an expression must return exactly one value",node) end
    return located(self.builder:ref(values[1],target.results[1]),node)
end

function Function:context()
    if not self.builder.sourceContext then self.builder.sourceContext=Source.context(self.id) end
    return self.builder.sourceContext
end

function Function:expr(node, expected, allowDefinition)
    self:context()
    local kind=node.kind
    local expr
    if allowDefinition and (kind=='SignatureExpr' or kind=='SchemaExpr' or kind=='SumSchema' or
        kind=='Apply' and node.callee.kind=='Reference' and (node.callee.name.text=='Array' or node.callee.name.text=='Ref' or node.callee.name.text=='Ptr' or node.callee.name.text=='Slice')) then
        return Source.definitionValue(Source.typeDefinition(typeExpr(node,self.types),schemaName(node,self.schemas),node),node.span)
    end
    if kind=='Group' then return self:expr(node.value,expected,allowDefinition)
    elseif kind=="U32Literal" then
        local literalType=expected==S.Any and S.I64 or expected and expected:isInteger() and expected or S.U32
        local maximum=S.maxOf(literalType)
        if maximum and node.value>maximum then reject("numeric-range","Integer literal does not fit "..S.display(literalType),node) end
        expr=self.builder:int(literalType,node.value)
    elseif kind=="U64Literal" then
        local literalType=expected and expected:isInteger() and expected or S.U64
        if not literalType:isWide() or (literalType:isSigned() and node.high>=2147483648) then reject("numeric-range","Integer literal does not fit "..S.display(literalType),node) end
        expr=self.builder:int64(literalType,node.high,node.low)
    elseif kind=="FloatLiteral" then expr=self.builder:float(S.F64,node.value)
    elseif kind=="BoolLiteral" then expr=self.builder:bool(node.value)
    elseif kind=="UnitLiteral" then expr=self.builder:const(S.Unit,I.UInt(0))
    elseif kind=="StringLiteral" then expr=self.builder:const(S.String,I.Str(node.bytes))
    elseif kind=='CurrentContext' then expr=self:bindingValue(self:currentContextBinding(node),node,allowDefinition)
    elseif kind=="Reference" then
        local binding=self:lookupBinding(node.name.text)
        if binding then
            expr=self:bindingValue(binding,node,allowDefinition)
        else
            local definition=self:resolveDefinition(node)
            if definition then
                local value=self:definitionValue(definition,node,allowDefinition)
                if value.sourceCallable and (not expected or value.type==expected) then return value end
                return self:coerce(value,expected,node)
            end
            local target=self.signatures[node.name.text]
            if target then
                expr=Source.value(Source.callable(self:requireContract(target,node),node.name.text),node.span)
                if expected==S.Any then expr=self:coerce(expr,expected,node) end
            else
                local global=self.globals[node.name.text]
                if global then expr=self.lambdaState.resolveGlobal(node.name.text)
                elseif self.dynamicReceiver then
                    local key=self.builder:const(S.String,I.Str(node.name.text));expr=self:dynamicWord("WordGet",{self.dynamicReceiver,key},node)
                else reject("unknown-name", "Unknown value `"..node.name.text.."`", node) end
            end
        end
    elseif kind=="Apply" then return self:call(node,expected)
    elseif kind=="OpenSupply" then
        for _,field in ipairs(node.fields) do if field.kind=='FieldSpread' then reject('spread-source','Runtime table-key expansion is not supported',field) end end
        if not self.dynamic then reject("slet-forbidden","SLet cannot construct an open word",node) end
        expr=self:dynamicWord("WordNew",{},node);local names={}
        for _,field in ipairs(node.fields) do
            local name=field.name.text;if names[name] then reject("duplicate-name","Open-word field `"..name.."` is supplied twice",field) end;names[name]=true
            local key=self.builder:const(S.String,I.Str(name));local value=self:expr(field.value,S.Any)
            expr=self:dynamicWord("WordSet",{expr,key,value},field)
        end
    elseif kind=="RecordSupply" then
        local runtimeKeys=self.dynamic and ((node.schema.kind=='Reference' and node.schema.name.text=='freeze') or self:knownType(node.schema)==S.Any)
        if runtimeKeys then
            for _,field in ipairs(node.fields) do if field.kind=='FieldSpread' then reject('spread-source','Runtime table-key expansion is not supported',field) end end
        end
        if self.dynamic and node.schema.kind=="Reference" and node.schema.name.text=="freeze" then
            local word=self:dynamicWord("WordNew",{},node);local names={}
            for _,field in ipairs(node.fields) do
                local name=field.name.text;if names[name] then reject("duplicate-name","Open-word field `"..name.."` is supplied twice",field) end;names[name]=true
                local key=self.builder:const(S.String,I.Str(name));local value=self:expr(field.value,S.Any);word=self:dynamicWord("WordSet",{word,key,value},field)
            end
            return located(self:dynamicWord("WordFreeze",{word},node),node)
        end
        if self.dynamic and self:knownType(node.schema)==S.Any then
            local source=self:expr(node.schema);local addition=self:dynamicWord("WordNew",{},node);local names={}
            for _,field in ipairs(node.fields) do
                local name=field.name.text;if names[name] then reject("duplicate-name","Open-word field `"..name.."` is supplied twice",field) end;names[name]=true
                local key=self.builder:const(S.String,I.Str(name));local value=self:expr(field.value,S.Any);addition=self:dynamicWord("WordSet",{addition,key,value},field)
            end
            return located(self:dynamicWord("WordSupply",{source,addition},node),node)
        end
        local definition=self:resolveDefinition(node.schema)
        local target=definition and definition.kind=='word' and definition.target
        if not definition and node.schema.kind=='Reference' then
            local binding=self:lookupBinding(node.schema.name.text);target=binding and binding.sourceCallable or self.signatures[node.schema.name.text]
        elseif not definition and node.schema.kind=='FieldSelect' then
            local receiver=self:placeBinding(node.schema.base)
            target=receiver and receiver.schema and self:methodTarget(receiver,node.schema.field.text,node.schema)
        end
        if target and target.ensure then target.ensure() end
        if target and target.keyed then return self:keyedSupply(node,target,expected) end
        if definition and definition.kind=='type' and definition.type:isRecord() then
            local fields=self:recordFields(definition.type,node.fields,node)
            expr=self.builder:make(definition.type,fields);expr.schema=definition.schema
        elseif definition and definition.kind=='constructor' then
            if not definition.payload:isRecord() then reject('type-mismatch','Keyed construction needs a record alternative',node) end
            local fields=self:recordFields(definition.payload,node.fields,node)
            local payload=self.builder:make(definition.payload,fields)
            expr=self:constructVariant(definition.sum,definition.tag,payload,node)
        elseif node.schema.kind=='Reference' and self:peekBinding(node.schema.name.text) then expr=self:sumMatch(node,expected)
        else reject('type-required','Record construction needs a schema or alternative constructor',node.schema) end
    elseif kind=="ArrayExpr" then
        local ty=expected and expected:isArray() and expected or nil
        local element=ty and ty.element
        local fields=self:supplies(node.items,function() return element end,nil,function(value,index,origin)
            if not value.type then reject('pack-use','Array elements need ordinary values',origin) end
            element=element or value.type
            return self:snapshotArgument(self:coerce(value,element,origin),origin)
        end)
        if #fields==0 then reject('array-length','Array construction needs a positive length',node) end
        ty=ty or S.Array(element,#fields)
        if #fields~=ty.length then reject("array-length","Array literal length does not match its type",node) end
        expr=self.builder:make(ty,fields)
    elseif kind=="FieldSelect" then
        local pack=self:packBinding(node.base)
        if pack then
            if node.field.text~='length' then reject('pack-use','Only pack.length is a field',node) end
            return self:coerce(located(self.builder:u32(#pack.sourcePack),node),expected,node)
        end
        local definition=self:resolveDefinition(node)
        if definition then
            local value=self:definitionValue(definition,node,allowDefinition)
            if value.sourceCallable and (not expected or value.type==expected) then return value end
            return self:coerce(value,expected,node)
        end
        expr=self:boundMethod(node,expected)
        if expr then return located(expr,node) end
        if self:knownType(node.base)==S.Any then
            local base=self:expr(node.base);local key=self.builder:const(S.String,I.Str(node.field.text));expr=self:dynamicWord("WordGet",{base,key},node)
        elseif node.field.text=="length" then local base=self:expr(node.base);if not base.type:isSlice() then reject("unknown-field","Only slices have length",node) end;expr=self.builder:sliceLength(base,S.U32)
        elseif node.base.kind=="Reference" then
            local binding=self:lookupBinding(node.base.name.text)
            if binding and binding.value and binding.type:isRecord() then
                local fieldType=S.field(binding.type,node.field.text);if not fieldType then reject("unknown-field","Unknown field `"..node.field.text.."`",node) end
                expr=self.builder:get(self.builder:ref(binding.value,binding.type),node.field.text,fieldType)
            else expr=self:readPlace(node) end
        else expr=self:readPlace(node) end
    elseif kind=="IndexExpr" then
        local pack=self:packBinding(node.base)
        if pack then
            local value=self:bindingValue(self:packIndex(pack,node),node)
            if value.sourceCallable and (not expected or expected==value.type) then return value end
            return self:coerce(value,expected,node)
        end
        if self:knownType(node.base)==S.Any then local base=self:expr(node.base);local key=self:expr(node.index);expr=self:dynamicWord("WordGet",{base,key},node)
        else expr=self:readPlace(node) end
    elseif kind=="Lambda" then return self:lambda(node,expected)
    elseif kind=="UnaryExpr" then
        local op=UNARY[node.operator]; if not op then reject("operator", "Unsupported unary operator `"..node.operator.."`",node) end
        local operand=self:expr(node.operand,expected)
        if op=="Not" then
            if operand.type~=S.Bool and operand.type~=S.Any then reject("type-mismatch","`not` needs bool or any",node) end
            expr=self.builder:un(op,operand,S.Bool)
        elseif op=="BitNot" then
            if not operand.type:isInteger() and operand.type~=S.Any then reject("type-mismatch","`~` needs an integer or any",node) end
            expr=self.builder:un(op,operand,operand.type)
        else
            if not operand.type:isInteger() and operand.type~=S.F64 and operand.type~=S.Any then reject("type-mismatch","Unary `-` needs a number or any",node) end
            expr=self.builder:un(op,operand,operand.type)
        end
    elseif kind=="BinaryExpr" then
        if node.operator=="and" or node.operator=="or" then
            local left=self:coerce(self:expr(node.left,S.Bool),S.Bool,node.left)
            local storage=self.builder:storageId();local parentBody,parentScope=self.body,self.scope
            local function arm(valueNode,constant)
                local list={};self.body,self.scope=list,copy(parentScope)
                local ok,value=pcall(function() return constant~=nil and self.builder:bool(constant) or self:coerce(self:expr(valueNode,S.Bool),S.Bool,valueNode) end)
                self.body,self.scope=parentBody,parentScope;if not ok then error(value,0) end
                self.builder:store(list,I.Local(storage),value);return list
            end
            local known=nil;if left.kind=="Const" and left.literal.kind=="Boolean" then known=left.literal.value end
            local yes,no
            if node.operator=="and" then
                yes=known==false and {} or arm(node.right,nil);no=arm(nil,false)
            else
                yes=arm(nil,true);no=known==true and {} or arm(node.right,nil)
            end
            self.builder:emit(parentBody,located(I.Var(storage,S.Bool,nil),node))
            self.builder:emit(parentBody,located(I.If(left,self:context():sequence(yes),self:context():sequence(no)),node))
            local value=self.builder:read(parentBody,S.Bool,I.Local(storage));expr=self.builder:ref(value,S.Bool)
        else
            local op=BINARY[node.operator]; if not op then reject("operator", "Operator `"..node.operator.."` is not implemented",node) end
            local leftLiteral=node.left.kind=="U32Literal" or node.left.kind=="U64Literal"
            local rightLiteral=node.right.kind=="U32Literal" or node.right.kind=="U64Literal"
            local left,right
            if leftLiteral and not rightLiteral then right=self:expr(node.right);left=self:expr(node.left,right.type)
            elseif rightLiteral and not leftLiteral then
                left=self:expr(node.left)
                local wanted=(node.operator=="<<" or node.operator==">>") and S.U32 or left.type
                right=self:expr(node.right,wanted)
            else left=self:expr(node.left);right=self:expr(node.right) end
            local resultType
            if left.type==S.Any or right.type==S.Any then
                left=self:coerce(left,S.Any,node.left);right=self:coerce(right,S.Any,node.right);resultType=COMPARISON[node.operator] and S.Bool or S.Any
            elseif node.operator=="<<" or node.operator==">>" then
                if not left.type:isInteger() then reject("type-mismatch","Shifted value must be an integer",node.left) end
                right=self:coerce(right,S.U32,node.right);resultType=left.type
            elseif left.type:isInteger() and right.type:isInteger() then
                local common=S.widerThan(left.type,right.type)
                if not common then reject("type-mismatch","Integer operands cannot mix signed and unsigned types",node) end
                left=self:coerce(left,common,node.left);right=self:coerce(right,common,node.right)
                resultType=COMPARISON[node.operator] and S.Bool or common
            elseif left.type==S.F64 and right.type==S.F64 then
                if op~="Add" and op~="Sub" and op~="Mul" and op~="Div" and not COMPARISON[node.operator] then reject("type-mismatch","Operator `"..node.operator.."` is not defined for f64",node) end
                resultType=COMPARISON[node.operator] and S.Bool or S.F64
            elseif left.type==right.type and left.type:isPtr() and (op=="Eq" or op=="Ne") then resultType=S.Bool
            elseif left.type==S.Bool and right.type==S.Bool and (op=="Eq" or op=="Ne") then resultType=S.Bool
            else reject("type-mismatch","Binary operands need compatible scalar types",node) end
            expr=self.builder:bin(op,left,right,resultType)
        end
    elseif kind=="Condition" then
        local test=self:coerce(self:expr(node.test,S.Bool),S.Bool,node.test)
        local storage=self.builder:storageId()
        local parentBody,parentScope=self.body,self.scope
        local function arm(valueNode,wanted)
            local list={};self.body,self.scope=list,copy(parentScope)
            local ok,value=pcall(function()
                local value=self:expr(valueNode,wanted)
                return self:coerce(value,wanted or value.type,valueNode)
            end)
            self.body,self.scope=parentBody,parentScope;if not ok then error(value,0) end
            self.builder:store(list,I.Local(storage),value);return list,value
        end
        local known=nil;if test.kind=="Const" and test.literal.kind=="Boolean" then known=test.literal.value end
        local yes,no,value,other
        if known==true then yes,value=arm(node.yes,expected);no={}
        elseif known==false then no,value=arm(node.no,expected);yes={}
        else
            yes,value=arm(node.yes,expected);no,other=arm(node.no,expected or value.type)
            if other.type~=value.type then reject("type-mismatch","Conditional arms need the same type",node) end
        end
        local ty=value.type
        self.builder:emit(parentBody,located(I.Var(storage,ty,nil),node))
        self.builder:emit(parentBody,located(I.If(test,self:context():sequence(yes),self:context():sequence(no)),node))
        local result=self.builder:read(parentBody,ty,I.Local(storage));expr=self.builder:ref(result,ty)
    else reject("semantic-todo", "Source expression "..tostring(kind).." is not implemented",node) end
    located(expr,node)
    if expr.sourceCallable and (not expected or expected==expr.type) then return expr end
    return self:coerce(expr,expected,node)
end

function Function:returnValues(nodes, owner)
    local values,origins=self:supplies(nodes,function(index) return self.results and self.results[index] end)
    if #values==0 then values[1]=self.builder:const(S.Unit,I.UInt(0));origins[1]=owner end
    if not self.results then
        self.results={}
        for index,value in ipairs(values) do values[index]=self:materializeCallable(value);self.results[index]=values[index].type end
    end
    if #values~=#self.results then reject('return-arity','Expected '..#self.results..' return values',owner) end
    for index,value in ipairs(values) do
        values[index]=self:coerce(value,self.results[index],origins[index])
    end
    self:emitDefers()
    self.builder:return_(self.body,values);located(self.body[#self.body],owner)
end

function Function:bindingValue(binding,origin,allowDefinition)
    if binding.sourceTemplate then return Source.templateValue(binding.sourceTemplate,origin.span) end
    if binding.sourcePack then return Source.pack(binding.sourcePack,origin.span) end
    if binding.sourceDefinition then return self:definitionValue(binding.sourceDefinition,origin,allowDefinition) end
    if binding.staticValue then return binding.staticValue end
    if binding.sourceCallable then return Source.value(self:requireContract(binding.sourceCallable,origin),origin.span) end
    local value=binding.value
    if binding.storage or binding.place then
        value=self.builder:read(self.body,binding.type,binding.place or I.Local(binding.storage))
    end
    local expr=self.builder:ref(value,binding.type)
    expr.schema=binding.schema
    return located(expr,origin)
end

-- Select a binding's actual mutable instance before requesting its value. Field
-- reads and call results are value boundaries, not aliases of their source place.
function Function:instanceBinding(node,wanted)
    local reference=ungroup(node)
    if reference.kind~='Reference' then return nil end
    local source=self:lookupBinding(reference.name.text)
    if not source or source.openedField or not (source.storage or source.place) or
        not (source.type:isRecord() or source.type:isArray()) then return nil end
    if wanted and wanted~=source.type then reject('type-mismatch','Aggregate alias annotation does not match',node) end
    return source
end

-- Ordinary value bindings retain their representation policy; opening binds places.
function Function:installBinding(entry,owner)
    local name=entry.binder.name.text
    if self.scope[name] then reject('duplicate-name','Local name `'..name..'` is declared twice',entry.binder) end
    local expr=entry.expr
    local binding
    if expr.instance then
        local source=expr.instance
        binding={storage=source.storage,place=source.place,type=source.type,schema=source.schema,moduleRoot=source.moduleRoot}
    elseif expr.sourceDefinition or expr.constructorDefinition then binding={sourceDefinition=expr.sourceDefinition or expr.constructorDefinition,type=expr.type}
    elseif expr.sourceTemplate then binding={sourceTemplate=expr.sourceTemplate,callable=true}
    elseif expr.sourcePack then reject('pack-use','A pack cannot be bound as an ordinary value',entry.binder)
    elseif expr.sourceCallable then binding={sourceCallable=expr.sourceCallable,type=expr.type,callable=true}
    elseif (expr.type:isView() or expr.type:isSum()) and expr.kind=='Ref' then
        binding={value=expr.value,type=expr.type,callable=expr.type:isView()}
    elseif expr.type:isRecord() or expr.type:isArray() or expr.type:isRef() or expr.type:isPtr() then
        binding={storage=self.builder:var(self.body,expr.type,expr),type=expr.type,schema=entry.schema}
    else
        local value=self.builder:let(self.body,expr.type,located(expr,owner))
        binding={value=value,type=expr.type,callable=expr.type:isView() or expr.type:isOwned()}
    end
    binding.origin=entry.binder;binding.localCallable=true;binding.owner=self;self.scope[name]=binding
end

function Function:bindValues(def,owner)
    local produced=self:supplies(def.values,function(index)
        local binder=def.binders[index]
        return binder and binder.annotation and typeExpr(binder.annotation,self.types) or nil
    end,function(index) return def.binders[index] end)
    local pending={}
    for index,binder in ipairs(def.binders) do
        local wanted=binder.annotation and typeExpr(binder.annotation,self.types) or nil
        local value=produced[index] or self.builder:const(S.Unit,I.UInt(0))
        local coerced=(value.instance or value.sourceCallable and (not wanted or wanted==value.type)) and value or self:coerce(value,wanted,binder)
        pending[index]={binder=binder,expr=coerced,schema=schemaName(binder.annotation,self.schemas) or coerced.schema}
    end
    for _,entry in ipairs(pending) do self:installBinding(entry,owner) end
end

local function originText(origin)
    local span=origin and origin.span
    return span and ((span.file or '<source>')..':'..tostring(span.line or '?')) or '<predefined or module binding>'
end
function Function:checkSpreadName(name,owner)
    local previous=self:peekBinding(name) or (self.visible and self.visible[name]) or self.globals[name] or self.signatures[name]
    if previous or (self.namespaces and self.namespaces[name]) or self.types[name] or BUILTIN_TYPES[name] or VOCABULARY_BUILTINS[name] or (self.dynamic and DYNAMIC_VOCABULARY[name]) then
        local origin=previous and (previous.origin or previous.node or previous.definition and previous.definition.origin)
            or (self.lambdaState.bindingOrigins and self.lambdaState.bindingOrigins[name])
        reject('spread-shadow','Expansion at '..originText(owner)..' introduces `'..name..'`, already visible from '..originText(origin),owner)
    end
end

function Function:expandBinding(name,owner)
    self:context()
    local binding=self:lookupBinding(name)
    local definition=binding and binding.sourceDefinition or self:resolveDefinition({kind='Reference',name={text=name},span=owner.span})
    if definition then binding={sourceDefinition=definition}
    elseif not binding and self.globals[name] then
        local value=self.lambdaState.resolveGlobal(name)
        binding={staticValue=value,type=value.type,schema=value.schema,origin=self.globals[name].node}
    end
    if not binding then reject('spread-source','No spreadable context `'..name..'` is visible',owner) end
    return self:expandContext(binding,owner)
end

-- Opening consumes a retained binding, not its lexical spelling. Anonymous and
-- named parameters, binding spreads and definition namespaces share this path.
function Function:expandContext(binding,owner)
    self:context()
    local definition=binding.sourceDefinition
    if definition then
        local members={}
        if definition.kind=='namespace' then members=definition.members
        elseif definition.kind=='type' and definition.type:isSum() then
            for _,field in ipairs(S.alternatives(definition.type)) do members[field.name]=Source.member(definition,field.name) end
        else reject('spread-source','Only namespaces and sum types introduce definition names',owner) end
        local names={};for member in pairs(members) do names[#names+1]=member end;table.sort(names)
        for _,member in ipairs(names) do self:checkSpreadName(member,owner) end
        for _,member in ipairs(names) do self.scope[member]={sourceDefinition=members[member],origin=owner,localCallable=not self.isModule} end
        return
    end
    local ty=binding.type and self:sealed(binding.type)
    local reference=ty and ty:isRef()
    local record=reference and self:sealed(ty.target) or ty
    if not record or not record:isRecord() then reject('spread-source','Vocabulary expansion requires a record, record reference or a compile-time definition namespace',owner) end
    for _,field in ipairs(record.fields) do self:checkSpreadName(field.name,owner) end
    -- Module opening projects its persistent root, never a per-call context copy.
    local place=self:bindingPlace(binding)
    if reference then
        -- Establish the reference once, not once per projected field or invocation.
        local storage=self.builder:var(self.body,ty,self:bindingValue(binding,owner))
        binding={storage=storage,type=ty,schema=binding.schema,origin=owner,owner=self}
        place=I.Deref(I.Local(storage),record)
    end
    if not place then reject('not-a-place','Record opening requires a retained context place',owner) end
    self.scope[RECEIVER_SCOPE]={binding=binding,origin=owner}
    local schema=binding.schema
    for _,field in ipairs(record.fields) do
        self.scope[field.name]={place=I.Project(place,I.Field(field.name)),type=field.type,
            schema=schema and schema.fieldSchemas and schema.fieldSchemas[field.name],
            origin=owner,owner=not self.isModule and self or nil,openedField=true,
            localCallable=true,callable=field.type:isView() or field.type:isOwned()}
    end
end

function Function:statements(statements)
    self:context()
    local deferred={}
    self.deferScopes[#self.deferScopes+1]=deferred
    for _,stmt in ipairs(statements) do
        local kind=stmt.kind
        if kind=="WordStmt" then
            self:localWord(stmt.def,stmt)
        elseif kind=="OpenMethodStmt" then
            self:openMethod(stmt)
        elseif kind=="ValueStmt" then
            self:bindValues(stmt.def,stmt)
        elseif kind=='SpreadStmt' then
            if stmt.initial then self:bindValues({binders={{name=stmt.name,span=stmt.span}},values={stmt.initial}},stmt) end
            self:expandBinding(stmt.name.text,stmt)
        elseif kind=="StoreStmt" then
            if ungroup(stmt.target).kind=='CurrentContext' then reject('context-use','The current home cannot be rebound; write a field place instead',stmt.target) end
            local receiverField=stmt.target.kind=="Reference" and not self:peekBinding(stmt.target.name.text) and self.dynamicReceiver
            if receiverField or ((stmt.target.kind=="FieldSelect" or stmt.target.kind=="IndexExpr") and self:knownType(stmt.target.base)==S.Any) then
                local base=receiverField and self.dynamicReceiver or self:expr(stmt.target.base)
                local key=receiverField and self.builder:const(S.String,I.Str(stmt.target.name.text)) or stmt.target.kind=="FieldSelect" and self.builder:const(S.String,I.Str(stmt.target.field.text)) or self:expr(stmt.target.index)
                local value
                if stmt.operator=="=" then value=self:expr(stmt.value,S.Any)
                else
                    local op=BINARY[stmt.operator:sub(1,-2)];if not op then reject("operator","Unsupported store operator `"..stmt.operator.."`",stmt) end
                    local current=self:dynamicWord("WordGet",{base,key},stmt.target);local right=self:expr(stmt.value,S.Any);value=self.builder:bin(op,current,right,S.Any)
                end
                self:dynamicWord("WordSet",{base,key,value},stmt)
            else
                local place,ty=self:place(stmt.target);local value
                if stmt.operator=="=" then value=self:coerce(self:expr(stmt.value,ty),ty,stmt.value)
                else
                    local op=BINARY[stmt.operator:sub(1,-2)];if not op then reject("operator","Unsupported store operator `"..stmt.operator.."`",stmt) end
                    local currentValue=self.builder:read(self.body,ty,place);local current=self.builder:ref(currentValue,ty)
                    local right=self:coerce(self:expr(stmt.value,ty),ty,stmt.value);value=self.builder:bin(op,current,right,ty)
                end
                self.builder:store(self.body,place,value)
            end
        elseif kind=="CallStmt" then
            if stmt.call.kind~="Apply" then reject("call-required","A call statement needs a call expression",stmt.call) end
            self:call(stmt.call,nil,true)
        elseif kind=="Defer" then
            if stmt.call.kind~="Apply" then reject("call-required","A deferred action needs a call expression",stmt.call) end
            deferred[#deferred+1]=self:call(stmt.call,nil,true,nil,true)
        elseif kind=="ReturnStmt" then self:returnValues(stmt.values,stmt)
        elseif kind=="IfStmt" then
            local test=self:coerce(self:expr(stmt.test,S.Bool),S.Bool,stmt.test)
            local parentBody,parentScope=self.body,self.scope
            local function arm(source)
                local list={};self.body,self.scope=list,copy(parentScope)
                local ok,why=pcall(function() self:statements(source) end)
                self.body,self.scope=parentBody,parentScope;if not ok then error(why,0) end
                return list
            end
            local known=nil;if test.kind=="Const" and test.literal.kind=="Boolean" then known=test.literal.value end
            local yes=known==false and {} or arm(stmt.yes)
            local no=known==true and {} or arm(stmt.no)
            self.builder:emit(parentBody,located(I.If(test,self:context():sequence(yes),self:context():sequence(no)),stmt))
        else reject("semantic-todo", "Source statement "..tostring(kind).." is not implemented",stmt) end
    end
    if Check.falls(self.body) then for index=#deferred,1,-1 do self:invokePrepared(deferred[index]) end end
    self.deferScopes[#self.deferScopes]=nil
end

local function declarationValues(decl)
    if decl.kind=='ValueDecl' then return decl.def end
    if decl.kind=='SpreadDecl' and decl.initial then
        return {binders={{name=decl.name,span=decl.span}},values={decl.initial}}
    end
end

function M.build(unit, options)
    if type(unit)~="table" or unit.phase~="parsed" then D.reject("compiler-phase","Semantic construction needs a parsed source unit") end
    Walk.walk(unit.ast,{enter=function(node)
        if (node.kind=='BinaryExpr' and node.operator=='..') or (node.kind=='StoreStmt' and node.operator=='..=') then
            reject('concatenation-unimplemented','Value string/list concatenation is not implemented',node)
        end
    end})
    -- Export sections describe one public namespace, not separate type/value
    -- namespaces. Validate names before resolving this module's aliases/initializers.
    local publicNames={}
    for _,section in ipairs{unit.ast.export.types,unit.ast.export.functions} do
        for _,item in ipairs(section) do
            local name=item.name.text
            if publicNames[name] then
                reject('duplicate-name','Public export `'..name..'` is repeated; types and functions share one namespace',item.name)
            end
            publicNames[name]=item
        end
    end
    options=options or {};local prefix=options.prefix or "";local dynamic=unit.profile and unit.profile.dynamic
    local signatures,globals,types,order,foreigns,cells={},{},{},{},{},{}
    for cell,ty in pairs(options.typeCells or {}) do cells[cell]=ty end
    -- Dependency foreigns are ABI declarations, not implicit source imports.
    -- Only local declarations or public namespace members expose their names.
    for _,foreign in ipairs(options.foreigns or {}) do foreigns[#foreigns+1]=foreign end
    local namespaces=options.namespaces or {}
    -- File-scope type declarations are mutually visible and resolved on demand. A recursive demand
    -- receives a stable Named cell. Sealing then checks the complete graph for by-value cycles.
    local typeDefs,typeState,typeDecl,typeOrder,schemas,schemaSerial={},{},{},{},{},0
    local function definitionPath(node)
        node=ungroup(node)
        if node.kind=='Reference' then
            if namespaces[node.name.text] then return namespaces[node.name.text] end
            local ty=types[node.name.text]
            if ty then return Source.typeDefinition(ty,schemas[node.name.text],node) end
        elseif node.kind=='FieldSelect' then return Source.member(definitionPath(node.base),node.field.text) end
    end
    types[DEFINITION_LOOKUP]=definitionPath;schemas[DEFINITION_LOOKUP]=definitionPath
    local moduleScope,scopeFor,scopedEnvironment
    local constructors={Ref=true,Ptr=true,Slice=true,Array=true}
    local function obviousType(node) node=ungroup(node);return node.kind=='SchemaExpr' or node.kind=='SumSchema' or node.kind=='SignatureExpr' or (node.kind=="Apply" and node.callee.kind=="Reference" and constructors[node.callee.name.text]) end
    for _,decl in ipairs(unit.ast.declarations) do
        local def=declarationValues(decl)
        if def and #def.binders==1 and #def.values==1 and not def.binders[1].annotation and obviousType(def.values[1]) then
            local name=def.binders[1].name.text;if rawget(types,name) or typeDefs[name] then reject('duplicate-name','Type `'..name..'` is declared twice',decl) end
            typeDefs[name]=ungroup(def.values[1]);typeDecl[name]=decl;typeOrder[#typeOrder+1]=name;decl._typeDeclaration=true
        end
    end
    local changed=true
    while changed do
        changed=false
        for _,decl in ipairs(unit.ast.declarations) do
            local def=declarationValues(decl)
            if def and #def.binders==1 and #def.values==1 and not def.binders[1].annotation and not decl._typeDeclaration then
                local node=ungroup(def.values[1])
                local referenced=node.kind=="Reference" and (BUILTIN_TYPES[node.name.text] or rawget(types,node.name.text) or typeDefs[node.name.text])
                local selected=node.kind=='FieldSelect' and definitionPath(node)
                selected=selected and selected.kind=='type'
                if referenced or selected then local name=def.binders[1].name.text;if rawget(types,name) or typeDefs[name] then reject("duplicate-name","Type `"..name.."` is declared twice",decl) end;typeDefs[name]=node;typeDecl[name]=decl;typeOrder[#typeOrder+1]=name;decl._typeDeclaration=true;changed=true end
            end
        end
    end
    local resolveType
    resolveType=function(name)
        local existing=rawget(types,name);if existing then return existing end
        local node=typeDefs[name];if not node then return nil end
        local cell=prefix.."type:"..name
        if typeState[name]=="visiting" then return S.Named(cell) end
        typeState[name]="visiting"
        local environment=scopedEnvironment and scopedEnvironment(typeDecl[name])
        local ty=typeExpr(node,environment and environment.types or types)
        rawset(types,name,ty);cells[cell]=ty;typeState[name]="sealed"
        if node.kind=="SchemaExpr" then
            local methods,fieldSchemas={},{}
            for _,member in ipairs(node.members) do
                if member.kind=="MethodMember" then local methodName=member.def.name.text;if methods[methodName] or S.field(ty,methodName) then reject("duplicate-name","Schema member `"..methodName.."` is declared twice",member) end;methods[methodName]=member.def
                else fieldSchemas[member.name.text]=member.type end
            end
            schemaSerial=schemaSerial+1;schemas[name]={face=S.Surface.Schema(schemaSerial),type=ty,methods=methods,
                fieldSchemas=setmetatable({},{__index=function(_,field) return schemaName(fieldSchemas[field],environment and environment.schemas or schemas) end}),name=name,prefix=prefix,environment=environment}
        else schemas[name]=schemaName(node,environment and environment.schemas or schemas)
        end
        return ty
    end
    setmetatable(types,{__index=function(_,name) return resolveType(name) end})
    local function finiteLayout(ty,visiting,done)
        if ty:isIndirection() then return true end
        if ty:isNamed() then
            if done[ty.cell] then return true end
            if visiting[ty.cell] then return false end
            local sealed=cells[ty.cell];if not sealed then return false end
            visiting[ty.cell]=true;local finite=finiteLayout(sealed,visiting,done);visiting[ty.cell]=nil
            if finite then done[ty.cell]=true end;return finite
        end
        if ty:isArray() then return finiteLayout(ty.element,visiting,done) end
        if ty:isRecord() or ty:isTaggedType() then
            for _,field in ipairs(ty:isRecord() and ty.fields or S.alternatives(ty)) do if not finiteLayout(field.type,visiting,done) then return false end end
        end
        return true
    end
    local contracts={}
    for _,entry in ipairs(unit.ast.export.results) do
        if entry.target.kind~="Reference" then reject("result-contract","A results contract must name a word",entry.target) end
        local name=entry.target.name.text
        if contracts[name] then reject("duplicate-name","Word `"..name.."` has more than one results contract",entry.target) end
        contracts[name]=entry.result
    end
    local function declareWord(node,name,annotation,origin)
        local word=Source.word(node,prefix..name)
        local contract={definition=word,target=word.id,origin=origin}
        local ensuring=false
        contract.ensure=function()
            if not contract.ensure then return end
            if ensuring then reject('static-cycle','Contract depends on its own unfinished binding `'..name..'`',origin) end
            ensuring=true
            local environment=scopedEnvironment(origin)
            local ready=wordContract(word,environment.types,dynamic,annotation and typeExpr(annotation,environment.types))
            if ready.sourceTemplate then environment:formTemplate(ready,{recursiveName=name,origin=origin,role=I.Body}) end
            local exported=contracts[name] and resultTypes(contracts[name],scopedEnvironment(unit.ast.export).types)
            if exported then
                if ready.results then
                    if #ready.results~=#exported then reject('result-type','Results contract disagrees with word `'..name..'`',origin) end
                    for index,ty in ipairs(ready.results) do if ty~=exported[index] then reject('result-type','Results contract disagrees with word `'..name..'`',origin) end end
                end
                ready.results=exported;contracts[name]=nil
            end
            ready.resultSchemas=resultInterfaces(word.result,environment.schemas)
            for key,value in pairs(ready) do contract[key]=value end
            contract.ensure=nil;word.contract=contract;ensuring=false
        end
        signatures[name]=contract;order[#order+1]={word=word,id=word.id,contract=contract,origin=origin}
    end
    for _,decl in ipairs(unit.ast.declarations) do
        if decl.kind=="WordDecl" then
            declareWord(decl.def,decl.def.name.text,nil,decl)
        elseif decl.kind=='ForeignDecl' then
            local target=decl.def.name.text
            if target:sub(1,9)=='__let_rt_' then reject('runtime-contract','Runtime primitives cannot be declared as source foreign words',decl) end
            if signatures[target] then reject('duplicate-name','Foreign word `'..target..'` conflicts with another word',decl) end
            local contract={target=target,foreign=true,origin=decl}
            contract.ensure=function()
                local environment=scopedEnvironment(decl)
                local inputs,names={},{}
                for _,param in ipairs(decl.def.params) do local name=param.name.text;if names[name] then reject('duplicate-name','Foreign parameter `'..name..'` is declared more than once',param) end;names[name]=true;inputs[#inputs+1]=S.inValue(typeExpr(param.annotation,environment.types)) end
                local results=resultTypes(decl.def.result,environment.types)
                local foreign=located(I.Foreign(target,L(inputs),L(results)),decl);foreigns[#foreigns+1]=foreign
                contract.inputs=foreign.inputs;contract.results=foreign.results;contract.resultSchemas=resultInterfaces(decl.def.result,environment.schemas);contract.ensure=nil
            end
            signatures[target]=contract
        elseif declarationValues(decl) and not decl._typeDeclaration then
            local def=declarationValues(decl)
            if #def.binders==1 and #def.values==1 and ungroup(def.values[1]).kind=='Lambda' then
                local binder=def.binders[1];declareWord(ungroup(def.values[1]),binder.name.text,binder.annotation,decl)
            else
                local group={definition=def,declaration=decl}
                for index,binder in ipairs(def.binders) do
                    globals[binder.name.text]={node=decl,annotation=binder.annotation,declaration=decl,group=group,index=index}
                end
            end
        elseif decl.kind=='ValueDecl' or decl.kind=='SpreadDecl' then -- types or expansion without an initializer
        elseif decl.kind=="UseDecl" then if not options.importsResolved then reject("import-input","A source string cannot resolve imports; compile a file",decl) end
        else reject("semantic-todo", "Top-level "..decl.kind.." is not implemented by source-to-IR construction",decl) end
    end
    local functions,generated,lambdaState,methodState={},{},{count=0,bindingOrigins=unit.bindings,demands=assert(options.demands,'compilation owns source demands')},{}
    moduleScope=setmetatable({signatures=signatures,globals=globals,types=types,typeCells=cells,
        schemas=schemas,namespaces=namespaces,methodState=methodState,dynamic=dynamic,managed=unit.profile and unit.profile.managed,
        generated=generated,lambdaState=lambdaState,scope={},id=prefix..'__module',isModule=true,
        builder=IR.builder(),body={},inputs={},params={},deferScopes={}},Function)
    local declarations,built,building={},{},{}
    for _,entry in ipairs(order) do declarations[entry.id]=entry end
    for _,fn in ipairs(options.dependencies or {}) do built[fn.id]=fn end
    local function resolve(id)
        if built[id] then return built[id] end
        for _,fn in ipairs(generated) do if fn.id==id then return fn end end
        local entry=declarations[id];if not entry then return nil end
        if building[id] then reject('static-cycle','A required static value depends on unfinished definition `'..id..'`',entry.origin) end
        building[id]=true
        if entry.contract.ensure then entry.contract.ensure() end
        if entry.contract.sourceTemplate then building[id]=nil;return nil end
        local environment=scopedEnvironment(entry.origin)
        local fn=environment:elaborateWord(entry.word,entry.contract,{role=I.Entry,origin=entry.origin,lexicalScope=scopeFor(entry.origin)})
        built[id]=fn;building[id]=nil
        return fn
    end
    lambdaState.resolve=resolve
    lambdaState.resolveGlobal=function(name)
        local global=assert(globals[name])
        if global.value then return global.value end
        local group=global.group
        if group.initializing then reject('static-cycle','Initializer cycle reaches `'..name..'`',global.node) end
        group.initializing=true
        local def=group.definition
        local environment=scopedEnvironment(global.declaration)
        local initializer=setmetatable({id=prefix..'__init_'..name,signatures=signatures,
            globals=globals,types=environment.types,typeCells=cells,schemas=environment.schemas,namespaces=namespaces,methodState=methodState,
            builder=IR.builder(),body={},scope=scopeFor(global.declaration),inputs={},params={},dynamic=dynamic,
            managed=unit.profile and unit.profile.managed,generated=generated,
            lambdaState=lambdaState,deferScopes={}},Function)
        initializer:context().initializerBody=initializer.body
        local function wanted(index)
            local binder=def.binders[index]
            return binder and binder.annotation and typeExpr(binder.annotation,environment.types) or nil
        end
        local produced=initializer:supplies(def.values,wanted,function(index) return def.binders[index] end)
        local pending,computed,indices={},{},{}
        for index,binder in ipairs(def.binders) do
            local value=produced[index] or initializer.builder:const(S.Unit,I.UInt(0))
            if not value.instance then value=initializer:coerce(value,wanted(index),binder) end
            pending[index]={value=value,schema=value.schema or schemaName(binder.annotation,environment.schemas)}
            if not value.instance and not value.sourceCallable and not value.sourceTemplate and not value.sourceDefinition then
                computed[#computed+1]=value;indices[#indices+1]=index
            end
        end
        -- Even discarded results retain initializer effects; publish the complete
        -- selected vector only after one accepted VM execution/transport.
        if #computed==0 and #initializer.body>0 then
            -- A definition/instance-only selected vector can still discard an
            -- effectful value item. Its effects execute once, not zero times.
            lambdaState.demands:require(initializer:context(),initializer.builder:const(S.Unit,I.UInt(0)),resolve,global.node)
        elseif #computed>0 then
            local constants=lambdaState.demands:requireValues(initializer:context(),computed,resolve,global.node)
            for index,value in ipairs(constants) do pending[indices[index]].value=value end
        end
        for index,binder in ipairs(def.binders) do
            local item=pending[index];local value=item.value;local entry=globals[binder.name.text]
            value.schema=item.schema
            if value.instance then
                local source=value.instance;assert(source.moduleRoot,'module alias without a persistent root')
                entry.binding={place=source.place,type=source.type,schema=source.schema,origin=binder,moduleRoot=source.moduleRoot}
            elseif value.type and (value.type:isRecord() or value.type:isArray() or value.type:isSum()) then
                if value.literal==nil or value.literal.kind~='Bytes' then reject('static-transport','Module aggregate needs a durable VM snapshot',binder) end
                local root=I.ModuleRoot(prefix..'data_'..binder.name.text,value.type,true)
                lambdaState.demands:installRoot(root,value.literal.bytes)
                entry.binding={place=I.Global(root),type=value.type,schema=item.schema,origin=binder,moduleRoot=root}
            end
            entry.value=value;entry.type=value.type
        end
        group.initializing=nil
        return global.value
    end
    -- Explicit declarations remain mutually visible. Expanded names are queried
    -- through immutable declaration boundaries, including during forward demands.
    local positions,expansions,environments={},{},{}
    for index,decl in ipairs(unit.ast.declarations) do
        positions[decl]=index
        if decl.kind=='SpreadDecl' or (decl.kind=='UseDecl' and decl.spread) then
            expansions[#expansions+1]={declaration=decl,position=index}
        end
    end
    positions[unit.ast.export]=#unit.ast.declarations+1
    local ensureExpansion
    scopeFor=function(decl)
        local position=assert(positions[decl],'declaration visibility boundary')
        local cache={}
        return setmetatable({},{__index=function(_,name)
            if cache[name]~=nil then return cache[name] or nil end
            -- A valid expansion cannot introduce an explicit/predefined name.
            -- Avoid demanding unrelated pending expansions to resolve such names.
            if unit.bindings[name] or BUILTIN_TYPES[name] or VOCABULARY_BUILTINS[name] or (dynamic and DYNAMIC_VOCABULARY[name]) then return nil end
            for index=#expansions,1,-1 do
                local expansion=expansions[index]
                if expansion.position<position then
                    local found=ensureExpansion(expansion)[name]
                    if found then cache[name]=found;return found end
                end
            end
            cache[name]=false
        end})
    end
    scopedEnvironment=function(decl)
        if environments[decl] then return environments[decl] end
        local environment=wordScope(moduleScope,{id=moduleScope.id},nil)
        environment.scope=scopeFor(decl);environments[decl]=environment
        return environment
    end
    ensureExpansion=function(expansion)
        if expansion.bindings then return expansion.bindings end
        local decl=expansion.declaration
        if expansion.pending then reject('static-cycle','Vocabulary discovery depends on its own unfinished context',decl) end
        expansion.pending=true
        local previous=moduleScope.scope;moduleScope.scope=scopeFor(decl)
        local ok,err=pcall(function()
            local name=decl.kind=='SpreadDecl' and decl.name.text or decl.path:match('([^.]+)$')
            moduleScope:expandBinding(name,decl)
            expansion.bindings=copy(moduleScope.scope)
        end)
        moduleScope.scope=previous;expansion.pending=nil
        if not ok then error(err,0) end
        return expansion.bindings
    end
    for _,name in ipairs(typeOrder) do resolveType(name) end
    local done={}
    for _,name in ipairs(typeOrder) do local cell=prefix..'type:'..name;if not finiteLayout(cells[cell],{[cell]=true},done) then reject('type-cycle','Type `'..name..'` has no finite layout',typeDecl[name]) end;done[cell]=true end
    -- Force declarations in source order; forward demands reuse these same states.
    for _,decl in ipairs(unit.ast.declarations) do
        local def=declarationValues(decl)
        if def and not decl._typeDeclaration then
            for _,binder in ipairs(def.binders) do if globals[binder.name.text] then lambdaState.resolveGlobal(binder.name.text) end end
        end
        for _,expansion in ipairs(expansions) do if expansion.declaration==decl then ensureExpansion(expansion) end end
    end
    for _,decl in ipairs(unit.ast.declarations) do if decl.kind=='ForeignDecl' then local target=signatures[decl.def.name.text];if target.ensure then target.ensure() end end end
    for _,entry in ipairs(order) do local fn=resolve(entry.id);if fn then functions[#functions+1]=fn end end
    for name,contract in pairs(contracts) do
        contract=resultTypes(contract,scopedEnvironment(unit.ast.export).types)
        local global=globals[name]
        if not global or not global.value.sourceCallable then D.reject('unknown-name','Results contract names unknown callable `'..name..'`') end
        local results=global.value.sourceCallable.results
        if #results~=#contract then reject('result-type','Callable binding disagrees with its result contract',global.node) end
        for index,ty in ipairs(results) do if ty~=contract[index] then reject('result-type','Callable binding disagrees with its result contract',global.node) end end
    end
    local exportEnvironment=scopedEnvironment(unit.ast.export)
    local publicSignatures,members,runtimeExports=copy(signatures),{},{}
    for _,item in ipairs(unit.ast.export.functions) do
        local source=item.name.text
        local node=item.kind=='ExportAlias' and ungroup(item.value) or {kind='Reference',name=item.name,span=item.span}
        if node.kind~='Reference' and node.kind~='FieldSelect' then reject('export-callable','Export a named callable binding or qualified word',node) end
        local definition=exportEnvironment:resolveDefinition(node)
        local value=exportEnvironment:expr(node)
        local target=value.sourceCallable or value.sourceTemplate
        if not target then reject('export-callable','Exported binding `'..source..'` is not callable',item.name) end
        local public=item.name.text
        if item.kind=='ExportAlias' and (signatures[public] or globals[public]) then reject('duplicate-name','Function export alias `'..public..'` conflicts with a binding',item.name) end
        members[public]=definition or {kind='word',target=target,origin=item}
        if not value.sourceTemplate then
        runtimeExports[#runtimeExports+1]=public
        if item.kind=='ExportAlias' or not signatures[public] then
        local builder=IR.builder();local params,args={},{ }
        for index,input in ipairs(target.inputs) do
            if input.kind~="InValue" then reject("semantic-todo","Export aliases of borrowed-input words are not implemented",item) end
            local value=builder:valueId();params[#params+1]=I.ValueParam(index-1,value,input.type);args[#args+1]=I.ValueArg(builder:ref(value,input.type))
        end
        local results={} for index=1,#target.results do results[index]=builder:valueId() end
        local application=Source.supply(Source.callable(target,source),args)
        local body={I.Call(L(results),application.target,L(Source.arguments(application)))};local returned={}
        for index,value in ipairs(results) do returned[index]=builder:ref(value,target.results[index]) end
        body[#body+1]=I.Return(L(returned))
        local id=prefix..public;local wrapper=located(I.Fn(id,I.Entry,0,L(target.inputs),L(target.results),L(params),L(body)),item)
        functions[#functions+1]=wrapper;publicSignatures[public]={inputs=target.inputs,results=target.results,target=id}
        end
        end
    end
    for _,fn in ipairs(generated) do functions[#functions+1]=fn end
    local checked={} for _,fn in ipairs(options.dependencies or {}) do checked[#checked+1]=fn end
    for _,fn in ipairs(functions) do
        Walk.walk(fn,{enter=function(node)
            if node.capturePending then D.bug('capture-open','Word transport was published before capture completion',node.span) end
        end})
        checked[#checked+1]=fn
    end
    checked.moduleData=lambdaState.demands:data()
    Check.program(checked, nil, foreigns)
    functions.moduleData=checked.moduleData
    local exportedTypes,exportedSchemas={},{}
    for _,item in ipairs(unit.ast.export.types) do
        local ty
        if item.kind=='ExportName' then ty=exportEnvironment.types[item.name.text]
        else ty=typeExpr(item.value,exportEnvironment.types) end
        if not ty then reject("unknown-name","Unknown exported type `"..item.name.text.."`",item.name) end
        exportedTypes[item.name.text]=ty
        exportedSchemas[item.name.text]=item.kind=='ExportName' and exportEnvironment.schemas[item.name.text] or schemaName(item.value,exportEnvironment.schemas)
        local node=item.kind=='ExportName' and {kind='Reference',name=item.name,span=item.span} or item.value
        local definition=exportEnvironment:resolveDefinition(node)
        members[item.name.text]=definition and definition.kind=='type' and definition or Source.typeDefinition(ty,exportedSchemas[item.name.text],item)
    end
    unit.runtimeExports=runtimeExports
    unit.namespace=Source.namespace(members,unit.ast)
    unit.phase="typed-ir";unit.functions=functions;unit.signatures=publicSignatures;unit.types=types;unit.exportedTypes=exportedTypes;unit.exportedSchemas=exportedSchemas;unit.foreigns=foreigns;unit.typeCells=cells;unit.schemas=schemas
    return unit
end

function M.exports(unit)
    if unit.runtimeExports then return copy(unit.runtimeExports) end
    local out={}
    for _,item in ipairs(unit.ast.export.functions) do
        out[#out+1]=item.name.text
    end
    return out
end

return M

