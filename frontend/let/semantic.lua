-- Source AST to verified ASDL IR. This pass resolves names and types but never executes user code.
local S = require("let.schema")
local IR = require("let.ir")
local Check = require("let.check")
local Walk = require("let.walk")
local Resolve = require("let.resolve")
local D = require("let.diag")
local Source = require("let.source_state")

local M = {}
local I, L = S.Ir, S.ASDL.List
local DEFINITION_LOOKUP = {}

local BUILTIN_TYPES = {
    u8=S.u8, u16=S.u16, u32=S.u32, u64=S.u64,
    i32=S.i32, i64=S.i64, f64=S.f64, bool=S.bool, unit=S.unit, any=S.any, string=S.string,
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
    elseif node.kind=="Apply" and node.callee.kind=="Reference" and (node.callee.name.text=="ref" or node.callee.name.text=="ptr") then return schemaName(node.arguments[1],schemas) end
    return name and schemas[name] or nil
end
local function reject(code, message, node) D.reject(code, message, node and node.span) end
local function located(value, node) if type(value)=="table" and node and node.span then value.span=node.span end return value end
local function copy(scope) local out={} for k,v in pairs(scope) do out[k]=v end return out end
local function containsBorrow(ty, seen)
    if ty:isRef() or ty:isSlice() then return true end
    seen=seen or {};if seen[ty] then return false end;seen[ty]=true
    if ty:isArray() then return containsBorrow(ty.element,seen) end
    if ty:isRecord() then for _,field in ipairs(ty.fields) do if containsBorrow(field.type,seen) then return true end end end
    if ty:isSum() then for _,field in ipairs(S.alternatives(ty)) do if containsBorrow(field.type,seen) then return true end end end
    return false
end

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
                if node.kind=='SumSchema' then reject('type-required','Sum alternatives must be name: type entries',member) end
                -- Methods belong to the schema interface, not its runtime record layout.
            else
                if fields[member.name.text] then reject("duplicate-name","Schema field `"..member.name.text.."` is declared twice",member) end
                fields[member.name.text]=typeExpr(member.type,types)
            end
        end
        return node.kind=='SumSchema' and S.sum(fields) or S.record(fields)
    elseif node and node.kind=="Apply" and node.callee.kind=="Reference" then
        local name=node.callee.name.text
        if name=="ref" or name=="ptr" or name=="slice" then
            if #node.arguments~=1 then reject("arity",name.." type expects one argument",node) end
            local child=typeExpr(node.arguments[1],types)
            return name=="ref" and S.ref(child) or name=="ptr" and S.ptr(child) or S.slice(child)
        elseif name=="array" then
            local length=ungroup(node.arguments[2])
            if #node.arguments~=2 or length.kind~='U32Literal' or length.value<1 then reject('array-length','array expects a type and a positive literal length',node) end
            return S.array(typeExpr(node.arguments[1],types),length.value)
        end
    elseif node and node.kind=="SignatureExpr" then
        local inputs={} for _,input in ipairs(node.inputs) do inputs[#inputs+1]=S.inValue(typeExpr(input,types)) end
        local results={} if node.results.kind=="Single" then results[1]=typeExpr(node.results.type,types) else for _,result in ipairs(node.results.types) do results[#results+1]=typeExpr(result,types) end end
        return S.view(S.sig(inputs,results))
    end
    reject("type-required", "Expected a concrete runtime type", node)
end

local function literalType(node)
    local kind=node and node.kind
    if kind=="U32Literal" then return S.u32 end
    if kind=="U64Literal" then return S.u64 end
    if kind=="FloatLiteral" then return S.f64 end
    if kind=="BoolLiteral" then return S.bool end
    if kind=="UnitLiteral" then return S.unit end
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

local function wordContract(word,types,dynamic,expected,inferResults)
    if expected and not expected:isView() then reject('type-required','A word needs a callable signature',word.origin) end
    local parameters={}
    for _,param in ipairs(#word.keyed>0 and word.keyed or word.params) do parameters[#parameters+1]=param end
    if #word.keyed>0 then table.sort(parameters,function(a,b) return a.name.text<b.name.text end) end
    if expected and #parameters~=#expected.visible.inputs then reject('arity','Word parameter count does not match its signature',word.origin) end
    local inputs,names,keys={},{},{}
    for index,param in ipairs(parameters) do
        local name=param.name.text
        if names[name] then reject('duplicate-name','Parameter `'..name..'` is declared more than once',param) end
        names[name]=true
        local contextual=expected and expected.visible.inputs[index].type
        local declared=param.annotation and typeExpr(param.annotation,types)
        if declared and contextual and declared~=contextual then reject('type-mismatch','Word parameter annotation does not match its signature',param) end
        local ty=declared or contextual or (dynamic and S.any)
        if not ty then reject('parameter-type','Parameter `'..name..'` needs a type annotation or context',param) end
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
        local binding=child.scope[name];local definition=binding and binding.sourceDefinition
        if not binding and child.globals[name] then definition=child.lambdaState.resolveGlobal(name).sourceDefinition end
        if definition and definition.kind=='type' then return definition.type end
        return environment.types[name]
    end})
    child.schemas=setmetatable({[DEFINITION_LOOKUP]=function(node) return child:resolveDefinition(node) end},{__index=function(_,name)
        local binding=child.scope[name];local definition=binding and binding.sourceDefinition
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
        local localBinding=self.scope[name]
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
    if definition.payload==S.unit then inputs={}
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
    if node.kind=="Reference" then local binding=self.scope[node.name.text];return binding and binding.type end
    if node.kind=="FieldSelect" or node.kind=="IndexExpr" then if self:knownType(node.base)==S.any then return S.any end end
    if node.kind=='Apply' then
        local definition=self:resolveDefinition(node.callee)
        local target=definition and definition.kind=='word' and definition.target
        if target then self:requireContract(target,node);return #target.results==1 and target.results[1] or nil end
    end
end

function Function:placeBinding(node)
    if node.kind=='Group' then return self:placeBinding(node.value) end
    if node.kind=="Reference" then return self.scope[node.name.text] end
    if node.kind=="FieldSelect" then
        local parent=self:placeBinding(node.base);if not parent then return nil end
        local place,ty=self:place(node)
        local schema=parent.schema
        return {place=place,type=ty,schema=schema and schema.fieldSchemas and schema.fieldSchemas[node.field.text] or nil}
    end
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
    if node.kind=="Reference" then
        local binding=self.scope[node.name.text]
        if not binding or (not binding.storage and not binding.place) then reject("not-a-place","`"..node.name.text.."` is not addressable",node) end
        return binding.place or I.Local(binding.storage),binding.type
    elseif node.kind=="FieldSelect" then
        local base,ty=self:place(node.base)
        if ty:isRef() or ty:isPtr() then local target=self:sealed(ty.target);base,ty=I.Deref(base,target),target end
        local field=S.field(ty,node.field.text);if not field then reject("unknown-field","Type has no field `"..node.field.text.."`",node.field) end
        return I.Project(base,I.Field(node.field.text)),field
    elseif node.kind=="IndexExpr" then
        local index=self:coerce(self:expr(node.index,S.u32),S.u32,node.index)
        if node.base.kind=="Reference" or node.base.kind=="FieldSelect" or node.base.kind=="IndexExpr" then
            local binding=node.base.kind=="Reference" and self.scope[node.base.name.text] or true
            if binding and (binding==true or binding.storage) then
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

local function rootName(node)
    while node and (node.kind=="FieldSelect" or node.kind=="IndexExpr") do node=node.base end
    return node and node.kind=="Reference" and node.name.text or nil
end

function Function:readPlace(node)
    local place,ty=self:place(node);local value=self.builder:read(self.body,ty,place);local result=self.builder:ref(value,ty)
    local name=rootName(node);local binding=name and self.scope[name];local occurrence=self:placeBinding(node);result.schema=occurrence and occurrence.schema or nil
    result.borrowedLocal=binding and binding.borrowedLocal or false
    return result
end

function Function:recordFields(ty, supplies, owner)
    local supplied={}
    for _,field in ipairs(supplies) do
        local name=field.name.text;if supplied[name] then reject("duplicate-name","Field `"..name.."` is supplied twice",field) end
        local fieldType=S.field(ty,name);if not fieldType then reject("unknown-field","Unknown field `"..name.."`",field) end
        supplied[name]=self:coerce(self:expr(field.value,fieldType),fieldType,field.value)
    end
    local fields={} for _,field in ipairs(ty.fields) do local value=supplied[field.name];if not value then reject("missing-field","Missing field `"..field.name.."`",owner) end;fields[#fields+1]=value end
    return fields
end

function Function:constructVariant(sum, tag, payload, owner)
    local payloadType=S.caseOf(sum,tag);if not payloadType then reject("unknown-field","Sum has no alternative `"..tag.."`",owner) end
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.ConstructVariant(value,sum,tag,payload),owner))
    local result=self.builder:ref(value,sum);result.borrowedLocal=payload and payload.borrowedLocal or false
    return result
end

function Function:sumMatch(node, expected)
    local variant=self:expr(node.schema);if not variant.type:isSum() then reject("type-mismatch","Keyed matching needs a sum value",node.schema) end
    local variantValue=variant.kind=="Ref" and variant.value or self.builder:let(self.body,variant.type,variant)
    local handlers={};local resultType=expected
    -- Handler expressions are ordinary supplies: evaluate once in written order,
    -- before dispatch. Only invocation is conditional on the variant's tag.
    for _,field in ipairs(node.fields) do
        local name=field.name.text
        if handlers[name] then reject('duplicate-name','Alternative `'..name..'` is handled twice',field) end
        local payloadType=S.caseOf(variant.type,name)
        if not payloadType then reject('unknown-field','Unknown alternative `'..name..'`',field) end
        local inputs=payloadType==S.unit and {} or {S.inValue(payloadType)}
        local valueNode=ungroup(field.value)
        local value
        if valueNode.kind=='Lambda' then
            value=self:lambda(valueNode,S.view(S.sig(inputs,resultType and {resultType} or {})),not resultType)
        else value=self:expr(field.value) end
        if not value.type:isView() then reject('type-mismatch','A sum handler must be a callable value',field) end
        local signature=value.type.visible
        if #signature.inputs~=#inputs then reject('arity','Sum handler payload arity does not match',field) end
        for index,input in ipairs(inputs) do
            if signature.inputs[index]~=input then reject('type-mismatch','Sum handler payload type does not match',field) end
        end
        if #signature.results~=1 then reject('result-arity','A sum handler must return exactly one value',field) end
        if resultType and signature.results[1]~=resultType then reject('type-mismatch','Sum handler result type does not match',field) end
        resultType=resultType or signature.results[1]
        handlers[name]={value=value,origin=field}
    end
    local resultStorage=self.builder:storageId();local cases={}
    local alternatives=S.alternatives(variant.type)
    for index,alternative in ipairs(alternatives) do
        local handler=handlers[alternative.name]
        if not handler then reject('missing-field','Missing handler for `'..alternative.name..'`',node) end
        local list={};local args={}
        if alternative.type~=S.unit then
            local payload=self.builder:valueId()
            self.builder:emit(list,located(I.VariantPayload(payload,variantValue,variant.type,alternative.name),handler.origin))
            args[1]=I.ValueArg(self.builder:ref(payload,alternative.type))
        end
        local result=self.builder:valueId();local callable=handler.value
        if callable.sourceCallable then
            local application=Source.supply(callable.sourceCallable,args)
            self.builder:emit(list,located(I.Call(L({result}),application.target,L(Source.arguments(application))),handler.origin))
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
function Function:captureCallable(binding, child, slots, recursiveSlots)
    local original=binding.sourceCallable or Source.callable(binding)
    self:requireContract(original)
    local captured={} for key,value in pairs(original) do captured[key]=value end
    captured.captures={};captured.supplied={}
    local function transport(arg, input)
        if arg.kind=='ValueArg' and arg.value.kind=='Const' then return arg end
        local index=#child.inputs;child.inputs[#child.inputs+1]=input
        local result
        if input.kind=='InPlace' then
            local storage=child.builder:storageId();child.params[#child.params+1]=I.PlaceParam(index,storage,input.type)
            result=I.BorrowArg(I.Local(storage))
        else
            local value=child.builder:valueId();child.params[#child.params+1]=I.ValueParam(index,value,input.type)
            result=I.ValueArg(child.builder:ref(value,input.type))
        end
        slots[#slots+1]=arg
        if recursiveSlots then recursiveSlots[#recursiveSlots+1]=result end
        return result
    end
    for index,arg in ipairs(original.captures) do
        local input
        if arg.kind=='ValueArg' then input=S.inValue(arg.value.type)
        else
            local definition=original.target==self.id and self or self.lambdaState.resolve(original.target)
            input=assert(definition and definition.inputs[index],'missing captured place contract')
        end
        captured.captures[index]=transport(arg,input)
    end
    for _,requirement in ipairs(original.original) do
        local arg=original.supplied[requirement.identity]
        if arg then captured.supplied[requirement.identity]=transport(arg,requirement.input) end
    end
    return {sourceCallable=captured,type=S.view(S.sig(captured.inputs,captured.results)),callable=true}
end

-- Parameter transport and local storage are independent of the spelling that
-- introduced the word. The returned argument refers to this frame's input.
function Function:wordParameter(name,input,annotation,origin)
    local index=#self.inputs;self.inputs[#self.inputs+1]=input
    local ty=input.type
    if input.kind=='InPlace' then
        local storage=self.builder:storageId()
        self.params[#self.params+1]=located(I.PlaceParam(index,storage,ty),origin)
        self.scope[name]={storage=storage,type=ty,origin=origin}
        return I.BorrowArg(I.Local(storage))
    end
    local value=self.builder:valueId()
    self.params[#self.params+1]=located(I.ValueParam(index,value,ty),origin)
    local ref=self.builder:ref(value,ty)
    if ty:isRecord() or ty:isArray() or ty:isRef() or ty:isPtr() then
        local storage=self.builder:var(self.body,ty,ref);self.scope[name]={storage=storage,type=ty}
    else self.scope[name]={value=value,type=ty,callable=ty:isView() or ty:isOwned()} end
    self.scope[name].schema=schemaName(annotation,self.schemas)
    self.scope[name].origin=origin
    return I.ValueArg(ref)
end

-- The sole source-word elaborator. Binding policy supplies recursive visibility
-- and an optional receiver; it never selects a different computation algorithm.
function Function:elaborateWord(word,contract,binding)
    binding=binding or {}
    word.state='checking'
    contract.resultSchemas=resultInterfaces(word.result,self.schemas)
    local child=wordScope(self,word,contract.results)
    local slots,recursiveSlots={},{}
    if binding.receiver then
        local schema=binding.receiver
        local storage=child.builder:storageId();child.inputs[1]=S.inPlace(schema.type)
        child.params[1]=I.PlaceParam(0,storage,schema.type)
        recursiveSlots[1]=I.BorrowArg(I.Local(storage))
        for _,field in ipairs(schema.type.fields) do
            child.scope[field.name]={place=I.Project(I.Local(storage),I.Field(field.name)),type=field.type,
                schema=schema.fieldSchemas and schema.fieldSchemas[field.name]}
        end
    elseif binding.dynamicReceiver then
        local value=child.builder:valueId();child.inputs[1]=S.inValue(S.any)
        child.params[1]=I.ValueParam(0,value,S.any);child.dynamicReceiver=child.builder:ref(value,S.any)
    end
    local lexical=binding.lexicalScope or self.scope or {}
    for name,entry in pairs(lexical) do child.visible[name]=entry end
    local inheritedVisible=self.visible
    setmetatable(child.visible,{__index=function(_,name) return lexical[name] or (inheritedVisible and inheritedVisible[name]) end})
    for _,name in ipairs(Resolve.captureCandidates(word)) do
        local source=lexical[name]
        if source and name~=binding.recursiveName and not child.scope[name] then
            if source.sourceDefinition or source.staticValue then
                child.scope[name]=source
            elseif source.sourceCallable then
                child.scope[name]=self:captureCallable(source,child,slots,recursiveSlots)
            else
                local place=source.place or (source.storage and I.Local(source.storage))
                local byPlace=place and (source.type:isRecord() or source.type:isArray())
                local input=byPlace and S.inPlace(source.type) or S.inValue(source.type)
                local recursive=child:wordParameter(name,input,nil,word.origin)
                child.scope[name].schema=source.schema;child.scope[name].borrowedLocal=source.borrowedLocal
                local supplied
                if byPlace then supplied=I.BorrowArg(place)
                else
                    local value=source.value
                    if place then value=self.builder:read(self.body,source.type,place) end
                    supplied=I.ValueArg(self.builder:ref(value,source.type))
                end
                slots[#slots+1]=supplied;recursiveSlots[#recursiveSlots+1]=recursive
            end
            child.scope[name].origin=source.origin
        end
    end
    local hidden=binding.dynamicReceiver and 0 or #child.inputs
    if binding.recursiveName then
        local recursive=Source.callable({definition=word,target=word.id,inputs=contract.inputs,
            results=contract.results,resultSchemas=contract.resultSchemas,keyed=contract.keyed,prefixArgs=recursiveSlots})
        child.scope[binding.recursiveName]={sourceCallable=recursive,callable=true}
    end
    for index,param in ipairs(contract.parameters) do
        child:wordParameter(param.name.text,contract.inputs[index],nil,param)
        child.scope[param.name.text].schema=schemaName(param.annotation,self.schemas)
    end
    for _,param in ipairs(contract.parameters) do
        if param.kind=='VocabularyParam' then child:expandBinding(param.name.text,param) end
    end
    if word.body.kind=='Expression' then child:returnValues({word.body.value},word.body.value)
    else child:statements(word.body.statements) end
    if Check.falls(child.body) then reject('missing-return','Word can finish without returning',word.origin) end
    contract.results=child.results
    local fn=located(I.Fn(word.id,binding.role or I.Body,hidden,L(child.inputs),L(child.results),L(child.params),L(child.body)),binding.origin or word.origin)
    local callable=Source.callable({definition=word,target=word.id,inputs=contract.inputs,results=child.results,
        resultSchemas=resultInterfaces(word.result,self.schemas),keyed=contract.keyed,prefixArgs=slots})
    word.state='checked';word.fn=fn
    return fn,callable
end

function Function:lambda(node, expected, inferResults)
    self.lambdaState.count=self.lambdaState.count+1
    local word=Source.word(node,self.id..'_word_'..self.lambdaState.count)
    local contract=wordContract(word,self.types,self.dynamic,expected,inferResults)
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
        local fn=environment:elaborateWord(word,descriptor,{receiver=schema,recursiveName=methodName,lexicalScope=environment.scope,origin=owner})
        environment.generated[#environment.generated+1]=fn
    end
    if environment~=self then
        for _,fn in ipairs(environment.generated) do if not self.lambdaState.resolve(fn.id) then self.generated[#self.generated+1]=fn end end
    end
    local receiver=binding.place or (binding.storage and I.Local(binding.storage))
    if receiver and (binding.type:isRef() or binding.type:isPtr()) then receiver=I.Deref(receiver,self:sealed(binding.type.target)) end
    if not receiver then reject("not-a-place","A method needs an addressable receiver",owner) end
    if receiver.kind~='Local' then
        -- Binding a receiver evaluates its address now, not after later argument
        -- effects (or when an alias/deferred action is eventually invoked).
        local ty=S.ptr(schema.type)
        local address=self.builder:let(self.body,ty,located(self.builder:addr(receiver,ty),owner))
        receiver=I.PtrIndex(self.builder:ref(address,ty),self.builder:u32(0),schema.type)
    end
    return {definition=descriptor.definition,target=descriptor.target,inputs=descriptor.inputs,results=descriptor.results,keyed=descriptor.keyed,prefixArgs={I.BorrowArg(receiver)}}
end

function Function:boundMethod(node,expected)
    local receiver=self:placeBinding(node.base)
    local target=receiver and receiver.schema and self:methodTarget(receiver,node.field.text,node) or nil
    if not target then return nil end
    if target.keyed then reject("keyed-required","A keyed method must be supplied by key before it becomes a value",node) end
    self:requireContract(target,node)
    local ty=S.view(S.sig(target.inputs,target.results))
    if expected and expected~=ty and expected~=S.any then reject("type-mismatch","Method value does not match the expected callable signature",node) end
    local value=Source.value(Source.callable(target),node.span)
    return expected==S.any and self:coerce(value,expected,node) or value
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
    local ty=S.view(S.sig(remaining,target.results));if expected and expected~=ty then reject("type-mismatch","Partial application does not match the expected callable signature",node) end
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.View(value,ty,id,L(slots),self.builder:storageId()),node));return self.builder:ref(value,ty)
end

function Function:dynamicWord(operation,operands,node)
    local dynamic={} for index,operand in ipairs(operands or {}) do dynamic[index]=self:coerce(operand,S.any,node) end
    local op=type(operation)=="string" and I[operation] or operation
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.Dynamic(L({value}),op,L(dynamic)),node))
    local ty=op.kind=="WordHas" and S.bool or op.kind=="WordCount" and S.u32 or S.any
    return self.builder:ref(value,ty)
end

function Function:openMethod(stmt)
    if not self.dynamic then reject("slet-forbidden","SLet cannot define an open-word method",stmt) end
    local binding=self.scope[stmt.receiver.text]
    if not binding then reject("unknown-name","Unknown open-word receiver `"..stmt.receiver.text.."`",stmt.receiver) end
    local receiver
    if binding.storage then local value=self.builder:read(self.body,binding.type,I.Local(binding.storage));receiver=self.builder:ref(value,binding.type)
    else receiver=self.builder:ref(binding.value,binding.type) end
    receiver=self:coerce(receiver,S.any,stmt.receiver)
    self.lambdaState.count=self.lambdaState.count+1;local id=self.id..'_open_method_'..self.lambdaState.count
    local word=Source.word(stmt.def,id);local contract=wordContract(word,self.types,self.dynamic)
    if contract.keyed then reject('parse','An open-word method uses positional parameters',stmt.def) end
    local fn=self:elaborateWord(word,contract,{dynamicReceiver=true,lexicalScope={},origin=stmt})
    self.generated[#self.generated+1]=fn
    local callable=self.builder:valueId();self.builder:emit(self.body,located(I.View(callable,S.any,id,L{},nil),stmt))
    local key=self.builder:const(S.string,I.Str(stmt.def.name.text))
    self:dynamicWord("WordMethod",{receiver,key,self.builder:ref(callable,S.any)},stmt)
end

function Function:wordBinding(node,name,expected,owner)
    if self.scope[name] then reject('duplicate-name','Local name `'..name..'` is declared twice',owner) end
    self.lambdaState.count=self.lambdaState.count+1
    local word=Source.word(node,self.id..'_word_'..self.lambdaState.count)
    local contract=wordContract(word,self.types,self.dynamic,expected)
    local fn,callable=self:elaborateWord(word,contract,{recursiveName=name,origin=owner})
    self.generated[#self.generated+1]=fn
    return Source.value(callable,owner and owner.span or node.span)
end

function Function:localWord(def, owner)
    local name=def.name.text
    local value=self:wordBinding(def,name,nil,owner)
    self.scope[name]={sourceCallable=value.sourceCallable,type=value.type,callable=true,origin=owner}
end

-- First-class transport is the only place that creates a callable environment.
function Function:materializeCallable(expr)
    if expr.sourceDefinition then reject('definition-value','Compile-time definitions have no runtime representation',expr) end
    if not expr.sourceCallable then return expr end
    local callable=expr.sourceCallable
    if #callable.captures>0 and not self.managed then
        reject('slet-forbidden','Materialized word captures need an owned representation',expr)
    end
    local target,slots=callable.target,{}
    for _,arg in ipairs(callable.captures) do slots[#slots+1]=arg end
    local hasSupply=next(callable.supplied)~=nil
    if hasSupply then
        -- A boundary adapter binds arbitrary original requirement positions, including
        -- keyed holes. Direct invocation never constructs this wrapper/environment.
        self.lambdaState.count=self.lambdaState.count+1
        target=self.id.."_bound_"..self.lambdaState.count
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
            else
                local definition=callable.target==self.id and self or self.lambdaState.resolve(callable.target)
                ty=assert(definition and definition.inputs[index],'missing capture layout')
            end
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
    local value=self.builder:valueId()
    self.builder:emit(self.body,located(I.View(value,expr.type,target,L(slots),#slots>0 and self.builder:storageId() or nil),expr))
    local result=located(self.builder:ref(value,expr.type),expr)
    result.borrowedLocal=expr.borrowedLocal
    return result
end

function Function:coerce(expr, expected, node)
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
    if expected==S.any and (expr.type:isRecord() or expr.type:isArray() or expr.type:isTaggedType()) then
        local storage=self.builder:var(self.body,expr.type,expr);return located(self.builder:convert(self.builder:addr(I.Local(storage),S.ref(expr.type)),S.any),node)
    end
    if (expr.type==S.any and expected~=S.type) or (expected==S.any and expr.type~=S.type) then return located(self.builder:convert(expr,expected),node) end
    if (expr.type:isInteger() or expr.type==S.f64) and (expected:isInteger() or expected==S.f64) then return located(self.builder:convert(expr,expected),node) end
    reject("type-mismatch", "Expected "..S.display(expected).." but found "..S.display(expr.type), node)
end

-- One source result-list rule for calls, returns and bindings. Parenthesized
-- expressions go through expr and therefore contribute exactly one value.
function Function:supplies(nodes, expectedAt, bindingAt, finishAt)
    local values,origins={},{}
    for index,node in ipairs(nodes) do
        local expected=expectedAt and expectedAt(#values+1)
        local produced
        local binder=bindingAt and bindingAt(#values+1)
        if binder and ungroup(node).kind=='Lambda' then
            produced={self:wordBinding(ungroup(node),binder.name.text,expected,node)}
        elseif index==#nodes and node.kind=='Apply' then
            produced=self:call(node,expected,false,true)
            if produced.kind then produced={produced} end
        else produced={self:expr(node,expected,bindingAt~=nil)} end
        for _,value in ipairs(produced) do
            if finishAt then value=finishAt(value,#values+1,node) end
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
    if value.kind=='Const' or value.kind=='Ref' then return value end
    local id=self.builder:let(self.body,value.type,located(value,origin))
    local result=located(self.builder:ref(id,value.type),origin)
    result.schema=value.schema;result.borrowedLocal=value.borrowedLocal
    return result
end

function Function:callSuffix(node, expected, discard, allResults, prepareOnly, continuing, pending, calleeValue)
    local name,callable,selectedMethod
    local definition=not pending and not calleeValue and self:resolveDefinition(node.callee)
    if definition and definition.kind=='type' then
        local primitive=false;for _,ty in pairs(BUILTIN_TYPES) do if ty==definition.type then primitive=true end end
        if primitive and #node.arguments==1 then return self:coerce(self:expr(node.arguments[1],definition.type),definition.type,node) end
        reject('type-mismatch','A type needs its declared construction form',node)
    elseif definition and definition.kind=='namespace' then reject('type-mismatch','A namespace is not callable',node) end
    if not definition and not pending and not calleeValue and node.callee.kind=="FieldSelect" then
        local receiver=self:placeBinding(node.callee.base)
        if receiver and receiver.schema then selectedMethod=self:methodTarget(receiver,node.callee.field.text,node.callee) end
    end
    if pending then name=pending.name
    elseif calleeValue then callable=calleeValue;name='<callable>'
    elseif definition then callable=self:definitionValue(definition,node.callee);name='<definition>'
    elseif selectedMethod then name="<method>"
    elseif node.callee.kind=="Reference" then
        local reference=node.callee.name.text
        if self.scope[reference] or self.globals[reference] or (self.dynamicReceiver and not self.signatures[reference]) then callable=self:expr(node.callee);name='<callable>' else name=reference end
    else callable=self:expr(node.callee);name="<callable>" end
    local binding=not pending and not calleeValue and node.callee.kind=="Reference" and self.scope[name] or nil
    local knownWord=pending and pending.knownWord or selectedMethod or (binding and binding.sourceCallable)
    if callable and callable.sourceCallable then knownWord=callable.sourceCallable;callable=nil end
    local indirect=pending and pending.indirect or (not knownWord and (callable and {type=callable.type,expr=callable} or binding and binding.type and binding or nil))
    if not pending and (name=="ref" or name=="ptr") then
        if #node.arguments~=1 then reject("arity",name.." expects one place",node) end
        local place,ty=self:place(node.arguments[1]);local result=located(self.builder:addr(place,name=="ref" and S.ref(ty) or S.ptr(ty)),node);result.borrowedLocal=name=="ref";return result
    elseif name=="null" then
        if #node.arguments~=1 then reject("arity","null expects one element type",node) end
        return located(self.builder:nullPtr(S.ptr(typeExpr(node.arguments[1],self.types))),node)
    elseif name=="slice" then
        if #node.arguments~=1 then reject("arity","slice expects one array",node) end
        local place,ty=self:place(node.arguments[1]);if not ty:isArray() then reject("type-mismatch","slice expects an array place",node.arguments[1]) end
        local first=I.Index(place,self.builder:u32(0),ty.element);local address=self.builder:addr(first,S.ref(ty.element))
        local result=located(self.builder:make(S.slice(ty.element),{address,self.builder:u32(ty.length)}),node);result.borrowedLocal=true;return result
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
            if name=="remove" then return located(self.builder:const(S.unit,I.UInt(0)),node) end
            return located(result,node)
        end
    end
    if name=="is" then
        if #node.arguments~=2 then reject("arity","is expects a value and a type",node) end
        local operand=self:coerce(self:expr(node.arguments[1]),S.any,node.arguments[1]);local tested=typeExpr(node.arguments[2],self.types)
        return located(self.builder:isType(operand,tested),node)
    end
    local target
    if pending then target=pending.target
    elseif indirect and indirect.type==S.any then
        local inputs={} for index=1,#node.arguments do inputs[index]=S.inValue(S.any) end;target={inputs=inputs,results={S.any},dynamic=true}
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
    local offset=#args;local localBorrow=pending and pending.localBorrow or false
    local supplied,newOrigins=self:supplies(node.arguments,function(index)
        local input=target.inputs[offset+index];return input and input.type
    end,nil,function(value,index,origin)
        local at=offset+index
        if target.dynamic and not target.inputs[at] then target.inputs[at]=S.inValue(S.any) end
        if not target.inputs[at] then reject('arity','Word `'..name..'` has only '..(#target.inputs-offset)..' remaining arguments in this suffix',node) end
        value=self:coerce(value,target.inputs[at].type,origin)
        return self:snapshotArgument(value,origin)
    end)
    for index,value in ipairs(supplied) do
        if value.borrowedLocal then localBorrow=true end
        args[#args+1]=I.ValueArg(value);origins[#origins+1]=newOrigins[index]
    end
    if continuing and #args<#target.inputs then
        return nil,{target=target,name=name,knownWord=knownWord,indirect=indirect,args=args,origins=origins,localBorrow=localBorrow}
    end
    local source=not indirect and Source.callable(target,name) or nil
    local application=source and Source.supply(source,args) or nil
    if prepareOnly then
        if #args<#target.inputs then reject("arity","A deferred action must be a saturated call",node) end
        return {target=target,name=name,indirect=indirect,args=application and Source.arguments(application) or args,node=node}
    end
    if #args<#target.inputs then
        local runtimeSupply=false for _,argument in ipairs(args) do if not self.lambdaState.demands:known(self:context(),argument.value) then runtimeSupply=true;break end end
        if runtimeSupply and self.dynamic and source and #source.captures==0 and not next(source.supplied) and not target.foreign then
            local callableValue=self.builder:valueId();self.builder:emit(self.body,located(I.View(callableValue,S.any,target.target or name,L{},nil),node))
            local dynamicArgs={} for _,arg in ipairs(args) do dynamicArgs[#dynamicArgs+1]=I.ValueArg(self:coerce(arg.value,S.any,node)) end
            local result=self.builder:valueId();self.builder:emit(self.body,located(I.Indirect(L({result}),self.builder:ref(callableValue,S.any),L(dynamicArgs)),node))
            return self.builder:ref(result,S.any)
        end
        if indirect then return self:indirectPartial(node,indirect,target,args,expected) end
        for index,argument in ipairs(args) do
            args[index]=I.ValueArg(self.lambdaState.demands:require(self:context(),argument.value,self.lambdaState.resolve,origins[index]))
        end
        application=Source.supply(Source.callable(target,name),args)
        local result=Source.value(application,node.span)
        if expected and expected~=result.type then reject("type-mismatch","Partial application does not match the expected callable signature",node) end
        if localBorrow then result.borrowedLocal=true end
        return result
    end
    local values={} for index=1,#target.results do values[index]=self.builder:valueId() end
    if indirect then
        local callableValue=indirect.expr or self.builder:ref(indirect.value,indirect.type)
        self.builder:emit(self.body,located(I.Indirect(L(values),callableValue,L(args)),node))
    else self.builder:emit(self.body,located(I.Call(L(values),application.target,L(Source.arguments(application))),node)) end
    if discard then return end
    local refs={} for index,value in ipairs(values) do
        refs[index]=located(self.builder:ref(value,target.results[index]),node);refs[index].schema=target.resultSchemas and target.resultSchemas[index] or nil
        if localBorrow and containsBorrow(target.results[index]) then refs[index].borrowedLocal=true end
    end
    if allResults then return refs end
    return refs[1] or self.builder:const(S.unit,I.UInt(0))
end
function Function:invokePrepared(call)
    local values={} for index=1,#call.target.results do values[index]=self.builder:valueId() end
    if call.indirect then
        local callableValue=call.indirect.expr or self.builder:ref(call.indirect.value,call.indirect.type)
        self.builder:emit(self.body,located(I.Indirect(L(values),callableValue,L(call.args)),call.node))
    else
        self.builder:emit(self.body,located(I.Call(L(values),call.target.target or call.name,L(call.args)),call.node))
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
    local byName,keyIndex={},{}
    for index,name in ipairs(target.keyed) do keyIndex[name]=index end
    local suppliedOrder,runtime={},false
    for _,field in ipairs(node.fields) do
        local name=field.name.text;if byName[name] then reject("duplicate-name","Requirement `"..name.."` is supplied twice",field) end
        local index=keyIndex[name]
        if not index and not self.dynamic then reject("unknown-field","Unknown requirement `"..name.."`",field) end
        local ty=index and target.inputs[index].type or S.any
        local value=self:coerce(self:expr(field.value,ty),ty,field.value)
        byName[name]=I.ValueArg(value);suppliedOrder[#suppliedOrder+1]={name=name,index=index,arg=byName[name],node=field.value}
        if not index or not self.lambdaState.demands:known(self:context(),value) then runtime=true end
    end
    if runtime and (#node.fields<#target.inputs or self.dynamic) then
        if not self.managed then reject("slet-forbidden","SLet cannot retain a runtime keyed callable",node) end
        if target.sourceCallable or #(target.prefixArgs or {})>0 then
            reject('semantic-todo','Runtime keyed supply of source-specialized or captured words is not implemented',node)
        end
        if target.foreign then reject("static-foreign","A foreign word cannot be opened by runtime keyed supply",node) end
        if #target.inputs==0 then reject("arity","A word with no requirements cannot be opened by keyed supply",node) end
        local callable=self.builder:valueId();self.builder:emit(self.body,located(I.View(callable,S.any,target.target,L{},nil),node))
        local opened=self.builder:valueId();self.builder:emit(self.body,located(I.Indirect(L({opened}),self.builder:ref(callable,S.any),L{}),node))
        local word=self.builder:ref(opened,S.any)
        for _,supply in ipairs(suppliedOrder) do
            local key=self.builder:const(S.string,I.Str(supply.name))
            word=self:dynamicWord(supply.index and I.WordBind(supply.index-1) or "WordSet",{word,key,supply.arg.value},supply.node)
        end
        return located(word,node)
    end
    local supplies={} for _,supply in ipairs(suppliedOrder) do
        supplies[supply.index]=#node.fields<#target.inputs and I.ValueArg(self.lambdaState.demands:require(self:context(),supply.arg.value,self.lambdaState.resolve,supply.node)) or supply.arg
    end
    local application=Source.supply(Source.callable(target),supplies)
    if #application.requirements>0 then
        local result=Source.value(application,node.span)
        if expected and expected~=result.type then reject("type-mismatch","Partial keyed supply does not match the expected callable signature",node) end
        return result
    end
    local values={} for index=1,#target.results do values[index]=self.builder:valueId() end
    self.builder:emit(self.body,located(I.Call(L(values),application.target,L(Source.arguments(application))),node))
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
    if kind=='Group' then return self:expr(node.value,expected,allowDefinition)
    elseif kind=="U32Literal" then
        local literalType=expected==S.any and S.i64 or expected and expected:isInteger() and expected or S.u32
        local maximum=S.maxOf(literalType)
        if maximum and node.value>maximum then reject("numeric-range","Integer literal does not fit "..S.display(literalType),node) end
        expr=self.builder:int(literalType,node.value)
    elseif kind=="U64Literal" then
        local literalType=expected and expected:isInteger() and expected or S.u64
        if not literalType:isWide() or (literalType:isSigned() and node.high>=2147483648) then reject("numeric-range","Integer literal does not fit "..S.display(literalType),node) end
        expr=self.builder:int64(literalType,node.high,node.low)
    elseif kind=="FloatLiteral" then expr=self.builder:float(S.f64,node.value)
    elseif kind=="BoolLiteral" then expr=self.builder:bool(node.value)
    elseif kind=="UnitLiteral" then expr=self.builder:const(S.unit,I.UInt(0))
    elseif kind=="StringLiteral" then expr=self.builder:const(S.string,I.Str(node.bytes))
    elseif kind=="Reference" then
        local binding=self.scope[node.name.text]
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
                if expected==S.any then expr=self:coerce(expr,expected,node) end
            else
                local global=self.globals[node.name.text]
                if global then expr=self.lambdaState.resolveGlobal(node.name.text)
                elseif self.dynamicReceiver then
                    local key=self.builder:const(S.string,I.Str(node.name.text));expr=self:dynamicWord("WordGet",{self.dynamicReceiver,key},node)
                else reject("unknown-name", "Unknown value `"..node.name.text.."`", node) end
            end
        end
    elseif kind=="Apply" then return self:call(node,expected)
    elseif kind=="OpenSupply" then
        if not self.dynamic then reject("slet-forbidden","SLet cannot construct an open word",node) end
        expr=self:dynamicWord("WordNew",{},node);local names={}
        for _,field in ipairs(node.fields) do
            local name=field.name.text;if names[name] then reject("duplicate-name","Open-word field `"..name.."` is supplied twice",field) end;names[name]=true
            local key=self.builder:const(S.string,I.Str(name));local value=self:expr(field.value,S.any)
            expr=self:dynamicWord("WordSet",{expr,key,value},field)
        end
    elseif kind=="RecordSupply" then
        if self.dynamic and node.schema.kind=="Reference" and node.schema.name.text=="freeze" then
            local word=self:dynamicWord("WordNew",{},node);local names={}
            for _,field in ipairs(node.fields) do
                local name=field.name.text;if names[name] then reject("duplicate-name","Open-word field `"..name.."` is supplied twice",field) end;names[name]=true
                local key=self.builder:const(S.string,I.Str(name));local value=self:expr(field.value,S.any);word=self:dynamicWord("WordSet",{word,key,value},field)
            end
            return located(self:dynamicWord("WordFreeze",{word},node),node)
        end
        if self.dynamic and self:knownType(node.schema)==S.any then
            local source=self:expr(node.schema);local addition=self:dynamicWord("WordNew",{},node);local names={}
            for _,field in ipairs(node.fields) do
                local name=field.name.text;if names[name] then reject("duplicate-name","Open-word field `"..name.."` is supplied twice",field) end;names[name]=true
                local key=self.builder:const(S.string,I.Str(name));local value=self:expr(field.value,S.any);addition=self:dynamicWord("WordSet",{addition,key,value},field)
            end
            return located(self:dynamicWord("WordSupply",{source,addition},node),node)
        end
        local definition=self:resolveDefinition(node.schema)
        local target=definition and definition.kind=='word' and definition.target
        if not definition and node.schema.kind=='Reference' then
            local binding=self.scope[node.schema.name.text];target=binding and binding.sourceCallable or self.signatures[node.schema.name.text]
        elseif not definition and node.schema.kind=='FieldSelect' then
            local receiver=self:placeBinding(node.schema.base)
            target=receiver and receiver.schema and self:methodTarget(receiver,node.schema.field.text,node.schema)
        end
        if target and target.ensure then target.ensure() end
        if target and target.keyed then return self:keyedSupply(node,target,expected) end
        if definition and definition.kind=='type' and definition.type:isRecord() then
            local fields=self:recordFields(definition.type,node.fields,node)
            expr=self.builder:make(definition.type,fields);expr.schema=definition.schema
            for _,field in ipairs(fields) do if field.borrowedLocal then expr.borrowedLocal=true end end
        elseif definition and definition.kind=='constructor' then
            if not definition.payload:isRecord() then reject('type-mismatch','Keyed construction needs a record alternative',node) end
            local fields=self:recordFields(definition.payload,node.fields,node)
            local payload=self.builder:make(definition.payload,fields)
            for _,field in ipairs(fields) do if field.borrowedLocal then payload.borrowedLocal=true end end
            expr=self:constructVariant(definition.sum,definition.tag,payload,node)
        elseif node.schema.kind=='Reference' and self.scope[node.schema.name.text] then expr=self:sumMatch(node,expected)
        else reject('type-required','Record construction needs a schema or alternative constructor',node.schema) end
    elseif kind=="ArrayExpr" then
        local ty=expected and expected:isArray() and expected or nil;local fields={}
        if not ty then
            if #node.items==0 then reject("type-required","An empty array needs an array annotation",node) end
            local first=self:expr(node.items[1]);ty=S.array(first.type,#node.items);fields[1]=first
        end
        if #node.items~=ty.length then reject("array-length","Array literal length does not match its type",node) end
        for index,item in ipairs(node.items) do if not fields[index] then fields[index]=self:coerce(self:expr(item,ty.element),ty.element,item) end end
        expr=self.builder:make(ty,fields);for _,field in ipairs(fields) do if field.borrowedLocal then expr.borrowedLocal=true end end
    elseif kind=="FieldSelect" then
        local definition=self:resolveDefinition(node)
        if definition then
            local value=self:definitionValue(definition,node,allowDefinition)
            if value.sourceCallable and (not expected or value.type==expected) then return value end
            return self:coerce(value,expected,node)
        end
        expr=self:boundMethod(node,expected)
        if expr then return located(expr,node) end
        if self:knownType(node.base)==S.any then
            local base=self:expr(node.base);local key=self.builder:const(S.string,I.Str(node.field.text));expr=self:dynamicWord("WordGet",{base,key},node)
        elseif node.field.text=="length" then local base=self:expr(node.base);if not base.type:isSlice() then reject("unknown-field","Only slices have length",node) end;expr=self.builder:sliceLength(base,S.u32)
        elseif node.base.kind=="Reference" then
            local binding=self.scope[node.base.name.text]
            if binding and binding.value and binding.type:isRecord() then
                local fieldType=S.field(binding.type,node.field.text);if not fieldType then reject("unknown-field","Unknown field `"..node.field.text.."`",node) end
                expr=self.builder:get(self.builder:ref(binding.value,binding.type),node.field.text,fieldType)
            else expr=self:readPlace(node) end
        else expr=self:readPlace(node) end
    elseif kind=="IndexExpr" then
        if self:knownType(node.base)==S.any then local base=self:expr(node.base);local key=self:expr(node.index);expr=self:dynamicWord("WordGet",{base,key},node)
        else expr=self:readPlace(node) end
    elseif kind=="Lambda" then return self:lambda(node,expected)
    elseif kind=="UnaryExpr" then
        local op=UNARY[node.operator]; if not op then reject("operator", "Unsupported unary operator `"..node.operator.."`",node) end
        local operand=self:expr(node.operand,expected)
        if op=="Not" then
            if operand.type~=S.bool and operand.type~=S.any then reject("type-mismatch","`not` needs bool or any",node) end
            expr=self.builder:un(op,operand,S.bool)
        elseif op=="BitNot" then
            if not operand.type:isInteger() and operand.type~=S.any then reject("type-mismatch","`~` needs an integer or any",node) end
            expr=self.builder:un(op,operand,operand.type)
        else
            if not operand.type:isInteger() and operand.type~=S.f64 and operand.type~=S.any then reject("type-mismatch","Unary `-` needs a number or any",node) end
            expr=self.builder:un(op,operand,operand.type)
        end
    elseif kind=="BinaryExpr" then
        if node.operator=="and" or node.operator=="or" then
            local left=self:coerce(self:expr(node.left,S.bool),S.bool,node.left)
            local storage=self.builder:storageId();local parentBody,parentScope=self.body,self.scope
            local function arm(valueNode,constant)
                local list={};self.body,self.scope=list,copy(parentScope)
                local ok,value=pcall(function() return constant~=nil and self.builder:bool(constant) or self:coerce(self:expr(valueNode,S.bool),S.bool,valueNode) end)
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
            self.builder:emit(parentBody,located(I.Var(storage,S.bool,nil),node))
            self.builder:emit(parentBody,located(I.If(left,L(yes),L(no)),node))
            local value=self.builder:read(parentBody,S.bool,I.Local(storage));expr=self.builder:ref(value,S.bool)
        else
            local op=BINARY[node.operator]; if not op then reject("operator", "Operator `"..node.operator.."` is not implemented",node) end
            local leftLiteral=node.left.kind=="U32Literal" or node.left.kind=="U64Literal"
            local rightLiteral=node.right.kind=="U32Literal" or node.right.kind=="U64Literal"
            local left,right
            if leftLiteral and not rightLiteral then right=self:expr(node.right);left=self:expr(node.left,right.type)
            elseif rightLiteral and not leftLiteral then
                left=self:expr(node.left)
                local wanted=(node.operator=="<<" or node.operator==">>") and S.u32 or left.type
                right=self:expr(node.right,wanted)
            else left=self:expr(node.left);right=self:expr(node.right) end
            local resultType
            if left.type==S.any or right.type==S.any then
                left=self:coerce(left,S.any,node.left);right=self:coerce(right,S.any,node.right);resultType=COMPARISON[node.operator] and S.bool or S.any
            elseif node.operator=="<<" or node.operator==">>" then
                if not left.type:isInteger() then reject("type-mismatch","Shifted value must be an integer",node.left) end
                right=self:coerce(right,S.u32,node.right);resultType=left.type
            elseif left.type:isInteger() and right.type:isInteger() then
                local common=S.widerThan(left.type,right.type)
                if not common then reject("type-mismatch","Integer operands cannot mix signed and unsigned types",node) end
                left=self:coerce(left,common,node.left);right=self:coerce(right,common,node.right)
                resultType=COMPARISON[node.operator] and S.bool or common
            elseif left.type==S.f64 and right.type==S.f64 then
                if op~="Add" and op~="Sub" and op~="Mul" and op~="Div" and not COMPARISON[node.operator] then reject("type-mismatch","Operator `"..node.operator.."` is not defined for f64",node) end
                resultType=COMPARISON[node.operator] and S.bool or S.f64
            elseif left.type==right.type and left.type:isPtr() and (op=="Eq" or op=="Ne") then resultType=S.bool
            elseif left.type==S.bool and right.type==S.bool and (op=="Eq" or op=="Ne") then resultType=S.bool
            else reject("type-mismatch","Binary operands need compatible scalar types",node) end
            expr=self.builder:bin(op,left,right,resultType)
        end
    elseif kind=="Condition" then
        local test=self:coerce(self:expr(node.test,S.bool),S.bool,node.test)
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
        self.builder:emit(parentBody,located(I.If(test,L(yes),L(no)),node))
        local result=self.builder:read(parentBody,ty,I.Local(storage));expr=self.builder:ref(result,ty)
        expr.borrowedLocal=value.borrowedLocal or (other and other.borrowedLocal)
    else reject("semantic-todo", "Source expression "..tostring(kind).." is not implemented",node) end
    located(expr,node)
    if expr.sourceCallable and (not expected or expected==expr.type) then return expr end
    return self:coerce(expr,expected,node)
end

function Function:returnValues(nodes, owner)
    local values,origins=self:supplies(nodes,function(index) return self.results and self.results[index] end)
    if #values==0 then values[1]=self.builder:const(S.unit,I.UInt(0));origins[1]=owner end
    if not self.results then
        self.results={}
        for index,value in ipairs(values) do values[index]=self:materializeCallable(value);self.results[index]=values[index].type end
    end
    if #values~=#self.results then reject('return-arity','Expected '..#self.results..' return values',owner) end
    for index,value in ipairs(values) do
        values[index]=self:coerce(value,self.results[index],origins[index])
        if not self.managed and values[index].borrowedLocal and containsBorrow(values[index].type) then
            reject('borrow-return','A value retaining local storage cannot be returned',origins[index])
        end
    end
    self:emitDefers()
    self.builder:return_(self.body,values);located(self.body[#self.body],owner)
end

function Function:bindingValue(binding,origin,allowDefinition)
    if binding.sourceDefinition then return self:definitionValue(binding.sourceDefinition,origin,allowDefinition) end
    if binding.staticValue then return binding.staticValue end
    if binding.sourceCallable then return Source.value(self:requireContract(binding.sourceCallable,origin),origin.span) end
    local value=binding.value
    if binding.storage or binding.place then
        value=self.builder:read(self.body,binding.type,binding.place or I.Local(binding.storage))
    end
    local expr=self.builder:ref(value,binding.type)
    expr.schema=binding.schema;expr.borrowedLocal=binding.borrowedLocal
    return located(expr,origin)
end

-- Ordinary bindings and vocabulary snapshots share the same representation policy.
function Function:installBinding(entry,owner)
    local name=entry.binder.name.text
    if self.scope[name] then reject('duplicate-name','Local name `'..name..'` is declared twice',entry.binder) end
    local expr=entry.expr
    local binding
    if entry.alias then binding={storage=entry.alias,type=entry.type,schema=entry.schema,borrowedLocal=entry.borrowedLocal}
    elseif expr.sourceDefinition or expr.constructorDefinition then binding={sourceDefinition=expr.sourceDefinition or expr.constructorDefinition,type=expr.type}
    elseif expr.sourceCallable then binding={sourceCallable=expr.sourceCallable,type=expr.type,callable=true}
    elseif (expr.type:isView() or expr.type:isSum()) and expr.kind=='Ref' then
        binding={value=expr.value,type=expr.type,callable=expr.type:isView(),borrowedLocal=expr.borrowedLocal}
    elseif expr.type:isRecord() or expr.type:isArray() or expr.type:isRef() or expr.type:isPtr() then
        binding={storage=self.builder:var(self.body,expr.type,expr),type=expr.type,schema=entry.schema,borrowedLocal=expr.borrowedLocal}
    else
        local value=self.builder:let(self.body,expr.type,located(expr,owner))
        binding={value=value,type=expr.type,callable=expr.type:isView() or expr.type:isOwned(),borrowedLocal=expr.borrowedLocal}
    end
    binding.origin=entry.binder;self.scope[name]=binding
end

function Function:bindValues(def,owner)
    local produced=self:supplies(def.values,function(index)
        local binder=def.binders[index]
        return binder and binder.annotation and typeExpr(binder.annotation,self.types) or nil
    end,function(index) return def.binders[index] end)
    local pending={}
    for index,binder in ipairs(def.binders) do
        local wanted=binder.annotation and typeExpr(binder.annotation,self.types) or nil
        local origin=#def.binders==#def.values and ungroup(def.values[index]) or nil
        local source=origin and origin.kind=='Reference' and self.scope[origin.name.text] or nil
        if source and source.storage and (source.type:isRecord() or source.type:isArray()) then
            if wanted and wanted~=source.type then reject('type-mismatch','Aggregate alias annotation does not match',binder) end
            pending[index]={binder=binder,alias=source.storage,type=source.type,schema=source.schema,borrowedLocal=source.borrowedLocal}
        else
            local value=produced[index] or self.builder:const(S.unit,I.UInt(0))
            local coerced=value.sourceCallable and (not wanted or wanted==value.type) and value or self:coerce(value,wanted,binder)
            pending[index]={binder=binder,expr=coerced,schema=schemaName(binder.annotation,self.schemas) or coerced.schema}
        end
    end
    for _,entry in ipairs(pending) do self:installBinding(entry,owner) end
end

local VOCABULARY_BUILTINS={ref=true,ptr=true,slice=true,array=true,null=true,is=true}
local DYNAMIC_VOCABULARY={open=true,has=true,remove=true,count=true,key=true,freeze=true}
local function originText(origin)
    local span=origin and origin.span
    return span and ((span.file or '<source>')..':'..tostring(span.line or '?')) or '<predefined or module binding>'
end
function Function:checkSpreadName(name,owner)
    local previous=self.scope[name] or (self.visible and self.visible[name]) or self.globals[name] or self.signatures[name]
    if previous or (self.namespaces and self.namespaces[name]) or self.types[name] or BUILTIN_TYPES[name] or VOCABULARY_BUILTINS[name] or (self.dynamic and DYNAMIC_VOCABULARY[name]) then
        local origin=previous and (previous.origin or previous.node or previous.definition and previous.definition.origin)
            or (self.lambdaState.bindingOrigins and self.lambdaState.bindingOrigins[name])
        reject('spread-shadow','Expansion at '..originText(owner)..' introduces `'..name..'`, already visible from '..originText(origin),owner)
    end
end

function Function:expandBinding(name,owner)
    self:context()
    local binding=self.scope[name]
    local definition=binding and binding.sourceDefinition or self:resolveDefinition({kind='Reference',name={text=name},span=owner.span})
    if definition then
        local members={}
        if definition.kind=='namespace' then members=definition.members
        elseif definition.kind=='type' and definition.type:isSum() then
            for _,field in ipairs(S.alternatives(definition.type)) do members[field.name]=Source.member(definition,field.name) end
        else reject('spread-source','Only namespaces and sum types introduce definition names',owner) end
        local names={};for member in pairs(members) do names[#names+1]=member end;table.sort(names)
        for _,member in ipairs(names) do self:checkSpreadName(member,owner) end
        for _,member in ipairs(names) do self.scope[member]={sourceDefinition=members[member],origin=owner} end
        return
    end
    if not binding and self.globals[name] then
        local value=self.lambdaState.resolveGlobal(name)
        binding={staticValue=value,type=value.type,schema=value.schema,origin=self.globals[name].node}
    end
    if not binding then reject('spread-source','No spreadable context `'..name..'` is visible',owner) end
    local ty=binding.type and self:sealed(binding.type)
    if not ty or not ty:isRecord() then reject('spread-source','Vocabulary expansion requires a record or a compile-time definition namespace',owner) end
    for _,field in ipairs(ty.fields) do self:checkSpreadName(field.name,owner) end
    -- Read the context once; every component is a value snapshot, never a place alias.
    local value=self:bindingValue(binding,owner)
    local schema=binding.schema
    for _,field in ipairs(ty.fields) do
        local expr=self.builder:get(value,field.name,field.type)
        expr.borrowedLocal=value.borrowedLocal
        local fieldSchema=schema and schema.fieldSchemas and schema.fieldSchemas[field.name]
        if self.isModule then
            local known=self.lambdaState.demands:require(self:context(),expr,self.lambdaState.resolve,owner)
            self.scope[field.name]={staticValue=known,type=known.type,schema=fieldSchema,origin=owner}
        else
            self:installBinding({binder={name={text=field.name},span=owner.span},expr=expr,schema=fieldSchema},owner)
        end
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
            local receiverField=stmt.target.kind=="Reference" and not self.scope[stmt.target.name.text] and self.dynamicReceiver
            if receiverField or ((stmt.target.kind=="FieldSelect" or stmt.target.kind=="IndexExpr") and self:knownType(stmt.target.base)==S.any) then
                local base=receiverField and self.dynamicReceiver or self:expr(stmt.target.base)
                local key=receiverField and self.builder:const(S.string,I.Str(stmt.target.name.text)) or stmt.target.kind=="FieldSelect" and self.builder:const(S.string,I.Str(stmt.target.field.text)) or self:expr(stmt.target.index)
                local value
                if stmt.operator=="=" then value=self:expr(stmt.value,S.any)
                else
                    local op=BINARY[stmt.operator:sub(1,-2)];if not op then reject("operator","Unsupported store operator `"..stmt.operator.."`",stmt) end
                    local current=self:dynamicWord("WordGet",{base,key},stmt.target);local right=self:expr(stmt.value,S.any);value=self.builder:bin(op,current,right,S.any)
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
                if value.borrowedLocal then
                    local name=rootName(stmt.target);local binding=name and self.scope[name]
                    if binding then binding.borrowedLocal=true end
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
            local test=self:coerce(self:expr(stmt.test,S.bool),S.bool,stmt.test)
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
            self.builder:emit(parentBody,located(I.If(test,L(yes),L(no)),stmt))
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
        if node.kind=='RestParam' then reject('rest-unimplemented','Static-shape rest specialization is not implemented',node) end
        if node.kind=='Spread' or node.kind=='FieldSpread' then
            reject('spread-unimplemented','Expansion for '..node.kind..' is not implemented',node)
        end
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
    local constructors={ref=true,ptr=true,slice=true,array=true}
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
        if typeState[name]=="visiting" then return S.named(cell) end
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
            if #def.binders~=#def.values then reject('binding-arity','A top-level value declaration needs one value per binder',decl) end
            for index,binder in ipairs(def.binders) do
                local node=def.values[index]
                if ungroup(node).kind=='Lambda' then declareWord(ungroup(node),binder.name.text,binder.annotation,decl)
                else
                    globals[binder.name.text]={node=node,type=not binder.annotation and literalType(node) or nil,annotation=binder.annotation,declaration=decl}
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
        local environment=scopedEnvironment(entry.origin)
        local fn=environment:elaborateWord(entry.word,entry.contract,{role=I.Entry,origin=entry.origin,lexicalScope=scopeFor(entry.origin)})
        built[id]=fn;building[id]=nil
        return fn
    end
    lambdaState.resolve=resolve
    lambdaState.resolveGlobal=function(name)
        local global=assert(globals[name])
        if global.value then return global.value end
        if global.initializing then reject('static-cycle','Initializer cycle reaches `'..name..'`',global.node) end
        global.initializing=true
        local environment=scopedEnvironment(global.declaration)
        if global.annotation then global.type=typeExpr(global.annotation,environment.types) end
        local initializer=setmetatable({id=prefix..'__init_'..name,signatures=signatures,
            globals=globals,types=environment.types,typeCells=cells,schemas=environment.schemas,namespaces=namespaces,methodState=methodState,
            builder=IR.builder(),body={},scope=scopeFor(global.declaration),inputs={},params={},dynamic=dynamic,
            managed=unit.profile and unit.profile.managed,generated=generated,
            lambdaState=lambdaState,deferScopes={}},Function)
        local value=initializer:expr(global.node,global.type,true)
        if global.type and not value.sourceCallable then value=initializer:coerce(value,global.type,global.node) end
        if not value.sourceCallable and not value.sourceDefinition then
            value=lambdaState.demands:require(initializer:context(),value,resolve,global.node)
        elseif global.type and global.type~=value.type then reject('type-mismatch','Module callable does not match its annotation',global.node) end
        global.value=value;global.initializing=nil
        return value
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
    for _,entry in ipairs(order) do functions[#functions+1]=resolve(entry.id) end
    for name,contract in pairs(contracts) do
        contract=resultTypes(contract,scopedEnvironment(unit.ast.export).types)
        local global=globals[name]
        if not global or not global.value.sourceCallable then D.reject('unknown-name','Results contract names unknown callable `'..name..'`') end
        local results=global.value.sourceCallable.results
        if #results~=#contract then reject('result-type','Callable binding disagrees with its result contract',global.node) end
        for index,ty in ipairs(results) do if ty~=contract[index] then reject('result-type','Callable binding disagrees with its result contract',global.node) end end
    end
    local exportEnvironment=scopedEnvironment(unit.ast.export)
    local publicSignatures,members=copy(signatures),{}
    for _,item in ipairs(unit.ast.export.functions) do
        local source=item.name.text
        local node=item.kind=='ExportAlias' and ungroup(item.value) or {kind='Reference',name=item.name,span=item.span}
        if node.kind~='Reference' and node.kind~='FieldSelect' then reject('export-callable','Export a named callable binding or qualified word',node) end
        local definition=exportEnvironment:resolveDefinition(node)
        local value=exportEnvironment:expr(node)
        local target=value.sourceCallable
        if not target then reject('export-callable','Exported binding `'..source..'` is not callable',item.name) end
        local public=item.name.text
        if item.kind=='ExportAlias' and (signatures[public] or globals[public]) then reject('duplicate-name','Function export alias `'..public..'` conflicts with a binding',item.name) end
        members[public]=definition or {kind='word',target=target,origin=item}
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
    for _,fn in ipairs(generated) do functions[#functions+1]=fn end
    local checked={} for _,fn in ipairs(options.dependencies or {}) do checked[#checked+1]=fn end
    for _,fn in ipairs(functions) do checked[#checked+1]=fn end
    Check.program(checked, nil, foreigns)
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
    unit.namespace=Source.namespace(members,unit.ast)
    unit.phase="typed-ir";unit.functions=functions;unit.signatures=publicSignatures;unit.types=types;unit.exportedTypes=exportedTypes;unit.exportedSchemas=exportedSchemas;unit.foreigns=foreigns;unit.typeCells=cells;unit.schemas=schemas
    return unit
end

function M.exports(unit)
    local out={}
    for _,item in ipairs(unit.ast.export.functions) do
        out[#out+1]=item.name.text
    end
    return out
end

return M

