-- Source AST to verified ASDL IR. This pass resolves names and types but never executes user code.
local S = require("let.schema")
local IR = require("let.ir")
local Check = require("let.check")
local Walk = require("let.walk")
local Resolve = require("let.resolve")
local D = require("let.diag")

local M = {}
local I, L = S.Ir, S.ASDL.List

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

local STATIC_LITERAL={U32Literal=true,U64Literal=true,FloatLiteral=true,BoolLiteral=true,UnitLiteral=true,StringLiteral=true}
local function staticSupply(node)
    if STATIC_LITERAL[node.kind] then return true end
    if node.kind=="Apply" and node.callee.kind=="Reference" and BUILTIN_TYPES[node.callee.name.text] then for _,argument in ipairs(node.arguments) do if not staticSupply(argument) then return false end end;return true end
    return false
end

local function schemaName(node,schemas)
    if not node then return nil end
    local name
    if node.kind=="Reference" then name=node.name.text
    elseif node.kind=="FieldSelect" and node.base.kind=="Reference" then name=node.base.name.text.."."..node.field.text
    elseif node.kind=="Apply" and node.callee.kind=="Reference" and (node.callee.name.text=="ref" or node.callee.name.text=="ptr") then return schemaName(node.arguments[1],schemas) end
    return name and schemas[name] and name or nil
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

local function typeExpr(node, types)
    if node and node.kind=="Reference" then
        local ty=BUILTIN_TYPES[node.name.text] or (types and types[node.name.text])
        if ty then return ty end
    elseif node and node.kind=="FieldSelect" and node.base.kind=="Reference" then
        local ty=types and types[node.base.name.text.."."..node.field.text]
        if ty then return ty end
    elseif node and node.kind=="SchemaExpr" then
        local fields={}
        for _,member in ipairs(node.members) do
            if member.kind=="MethodMember" then
                -- Methods belong to the schema interface, not its runtime record layout.
            else
                if fields[member.name.text] then reject("duplicate-name","Schema field `"..member.name.text.."` is declared twice",member) end
                fields[member.name.text]=typeExpr(member.type,types)
            end
        end
        return S.record(fields)
    elseif node and node.kind=="Apply" and node.callee.kind=="Reference" then
        local name=node.callee.name.text
        if name=="ref" or name=="ptr" or name=="slice" then
            if #node.arguments~=1 then reject("arity",name.." type expects one argument",node) end
            local child=typeExpr(node.arguments[1],types)
            return name=="ref" and S.ref(child) or name=="ptr" and S.ptr(child) or S.slice(child)
        elseif name=="array" then
            if #node.arguments~=2 or node.arguments[2].kind~="U32Literal" or node.arguments[2].value<1 then reject("array-length","array expects a type and a positive literal length",node) end
            return S.array(typeExpr(node.arguments[1],types),node.arguments[2].value)
        elseif name=="oneof" then
            if #node.arguments~=1 or node.arguments[1].kind~="SchemaExpr" then reject("type-required","oneof expects one schema",node) end
            local record=typeExpr(node.arguments[1],types);return S.sum(S.fieldsOf(record))
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

local function signature(def,dynamic,types)
    local parameters={}
    for _,param in ipairs(#def.keyed>0 and def.keyed or def.params) do parameters[#parameters+1]=param end
    if #def.keyed>0 then table.sort(parameters,function(a,b) return a.name.text<b.name.text end) end
    local inputs,names,keys={},{},{}
    for _,param in ipairs(parameters) do
        local name=param.name.text
        if names[name] then reject("duplicate-name", "Parameter `"..name.."` is declared more than once", param) end
        names[name]=true
        if not param.annotation and not dynamic then reject("parameter-type", "Parameter `"..name.."` needs a type annotation", param) end
        inputs[#inputs+1]=S.inValue(param.annotation and typeExpr(param.annotation,types) or S.any)
        if #def.keyed>0 then keys[#keys+1]=name end
    end
    def._semanticParams=parameters
    local results=resultTypes(def.result,types) or def._resultTypes
    if not results then reject("result-type", "Word `"..def.name.text.."` needs an explicit result type", def) end
    return inputs,results,#keys>0 and keys or nil
end

local Function = {}
Function.__index = Function

function Function.new(def, id, signatures, globals, types, dynamic, managed, generated, lambdaState, typeCells, schemas, methodState)
    local inputs,results,keyed=signature(def,dynamic,types)
    local self=setmetatable({def=def,id=id,signatures=signatures,globals=globals,types=types,typeCells=typeCells or {},schemas=schemas or {},methodState=methodState or {},builder=IR.builder(),body={},scope={},inputs=inputs,results=results,params={},dynamic=dynamic,managed=managed,generated=generated or {},lambdaState=lambdaState or {count=0},deferScopes={}},Function)
    for index,param in ipairs(def._semanticParams or def.params) do
        local value=self.builder:valueId(); local ty=inputs[index].type
        self.params[#self.params+1]=located(I.ValueParam(index-1,value,ty),param)
        if ty:isRecord() or ty:isArray() or ty:isRef() or ty:isPtr() then
            local storage=self.builder:var(self.body,ty,self.builder:ref(value,ty));self.scope[param.name.text]={storage=storage,type=ty}
        else self.scope[param.name.text]={value=value,type=ty,callable=ty:isView() or ty:isOwned()} end
        local selectedSchema=schemaName(param.annotation,self.schemas)
        if selectedSchema then self.scope[param.name.text].schema=selectedSchema end
    end
    return self
end

function Function:knownType(node)
    if node.kind=="Reference" then local binding=self.scope[node.name.text];return binding and binding.type end
    if node.kind=="FieldSelect" or node.kind=="IndexExpr" then if self:knownType(node.base)==S.any then return S.any end end
    if node.kind=="Apply" and node.callee.kind=="Reference" then local target=self.signatures[node.callee.name.text];return target and #target.results==1 and target.results[1] or nil end
end

function Function:placeBinding(node)
    if node.kind=="Reference" then return self.scope[node.name.text] end
    if node.kind=="FieldSelect" then
        local parent=self:placeBinding(node.base);if not parent then return nil end
        local place,ty=self:place(node)
        local schema=parent.schema and self.schemas[parent.schema] or nil
        return {place=place,type=ty,schema=schema and schema.fieldSchemas and schema.fieldSchemas[node.field.text] or nil}
    end
end

function Function:sealed(ty)
    local seen={}
    while ty and ty:isNamed() do
        if seen[ty.cell] then reject("type-cycle","Recursive type cell did not seal",self.def) end
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
    local handlers={} for _,field in ipairs(node.fields) do local name=field.name.text;if handlers[name] then reject("duplicate-name","Alternative `"..name.."` is handled twice",field) end;handlers[name]=field.value end
    local resultStorage=self.builder:storageId();local resultType=expected;local cases={};local resultBorrow=false
    local parentBody,parentScope=self.body,self.scope
    local alternatives=S.alternatives(variant.type)
    for index,alternative in ipairs(alternatives) do
        local lambda=handlers[alternative.name];if not lambda then reject("missing-field","Missing handler for `"..alternative.name.."`",node) end
        if lambda.kind~="Lambda" then reject("type-mismatch","Sum handler `"..alternative.name.."` must be a lambda",lambda) end
        local list={};self.body,self.scope=list,copy(parentScope)
        local payloadExpr
        if alternative.type==S.unit then if #lambda.params~=0 then reject("arity","Unit alternative handler expects no parameter",lambda) end
        else
            if #lambda.params~=1 then reject("arity","Alternative handler expects one payload parameter",lambda) end
            local payload=self.builder:valueId();self.builder:emit(list,located(I.VariantPayload(payload,variantValue,variant.type,alternative.name),lambda))
            payloadExpr=self.builder:ref(payload,alternative.type);payloadExpr.borrowedLocal=variant.borrowedLocal
            if alternative.type:isRef() or alternative.type:isPtr() or alternative.type:isRecord() or alternative.type:isArray() then
                local storage=self.builder:var(list,alternative.type,payloadExpr);self.scope[lambda.params[1].name.text]={storage=storage,type=alternative.type,borrowedLocal=variant.borrowedLocal}
            else self.scope[lambda.params[1].name.text]={value=payload,type=alternative.type,borrowedLocal=variant.borrowedLocal} end
        end
        local ok,value=pcall(function()
            if lambda.body.kind=="Expression" then
                local result=self:expr(lambda.body.value,resultType)
                if not resultType then resultType=result.type end
                return self:coerce(result,resultType,lambda.body.value)
            end
            local inputs=alternative.type==S.unit and {} or {S.inValue(alternative.type)}
            local infer=not resultType
            local callable=self:lambda(lambda,S.view(S.sig(inputs,infer and {} or {resultType})),infer)
            if infer then
                if #callable.type.visible.results~=1 then reject("result-arity","A sum handler must return exactly one value",lambda) end
                resultType=callable.type.visible.results[1]
            end
            local result=self.builder:valueId();local args={}
            if payloadExpr then args[1]=I.ValueArg(payloadExpr) end
            self.builder:emit(list,located(I.Indirect(L({result}),callable,L(args)),lambda))
            return self.builder:ref(result,resultType)
        end)
        if ok then if value.borrowedLocal then resultBorrow=true end;self.builder:store(list,I.Local(resultStorage),value) end
        self.body,self.scope=parentBody,parentScope;if not ok then error(value,0) end
        cases[#cases+1]=I.Case(alternative.name,index==#alternatives,L(list));handlers[alternative.name]=nil
    end
    for name in pairs(handlers) do reject("unknown-field","Unknown alternative `"..name.."`",node) end
    self.builder:emit(parentBody,located(I.Var(resultStorage,resultType,nil),node));self.builder:emit(parentBody,located(I.Switch(variantValue,variant.type,L(cases)),node))
    local value=self.builder:read(parentBody,resultType,I.Local(resultStorage));local result=self.builder:ref(value,resultType);result.borrowedLocal=resultBorrow;return result
end
function Function:lambda(node, expected, inferResults)
    if not expected or not expected:isView() then reject("type-required","A lambda needs a callable signature annotation",node) end
    if not inferResults and #expected.visible.results<1 then reject("semantic-todo","Zero-result source lambdas are not implemented",node) end
    if #node.params~=#expected.visible.inputs then reject("arity","Lambda parameter count does not match its signature",node) end
    local parameterNames={} for _,param in ipairs(node.params) do
        local name=param.name.text
        if parameterNames[name] then reject("duplicate-name","Lambda parameter `"..name.."` is declared more than once",param) end
        parameterNames[name]=true
    end
    local captures,seen={},{}
    Walk.walk(node.body,{enter=function(item)
        if item.kind=="Reference" and not parameterNames[item.name.text] and self.scope[item.name.text] and not seen[item.name.text] then seen[item.name.text]=true;captures[#captures+1]=item.name.text end
    end})
    table.sort(captures)
    if not self.managed then for _,name in ipairs(captures) do if containsBorrow(self.scope[name].type) then reject("borrow-store","An escaping closure cannot retain a reference or slice capture",node) end end end
    if #captures>0 and not self.managed then reject("slet-forbidden","SLet lambdas cannot capture local values",node) end
    self.lambdaState.count=self.lambdaState.count+1;local id=self.id.."_lambda_"..self.lambdaState.count
    local lambdaResults=expected.visible.results;if inferResults then lambdaResults=nil end
    local child=setmetatable({id=id,signatures=self.signatures,globals=self.globals,types=self.types,typeCells=self.typeCells,schemas=self.schemas,methodState=self.methodState,builder=IR.builder(),body={},scope={},inputs={},results=lambdaResults,params={},dynamic=self.dynamic,managed=self.managed,generated=self.generated,lambdaState=self.lambdaState,deferScopes={}},Function)
    local slots={}
    for _,name in ipairs(captures) do
        local source=self.scope[name];local input=#child.inputs
        if source.storage and (source.type:isRecord() or source.type:isArray()) then
            child.inputs[#child.inputs+1]=S.inPlace(source.type);local storage=child.builder:storageId();child.params[#child.params+1]=I.PlaceParam(input,storage,source.type);child.scope[name]={storage=storage,type=source.type}
            slots[#slots+1]=I.BorrowArg(I.Local(source.storage))
        else
            child.inputs[#child.inputs+1]=S.inValue(source.type);local value=child.builder:valueId();child.params[#child.params+1]=I.ValueParam(input,value,source.type)
            if source.type:isRef() or source.type:isPtr() then local storage=child.builder:var(child.body,source.type,child.builder:ref(value,source.type));child.scope[name]={storage=storage,type=source.type}
            else child.scope[name]={value=value,type=source.type,callable=source.callable} end
            local captured
            if source.storage then local valueId=self.builder:read(self.body,source.type,I.Local(source.storage));captured=self.builder:ref(valueId,source.type) else captured=self.builder:ref(source.value,source.type) end
            slots[#slots+1]=I.ValueArg(captured)
        end
    end
    for index,param in ipairs(node.params) do
        local inputType=expected.visible.inputs[index].type
        if param.annotation and typeExpr(param.annotation,self.types)~=inputType then reject("type-mismatch","Lambda parameter annotation does not match its signature",param) end
        local input=#child.inputs;child.inputs[#child.inputs+1]=S.inValue(inputType);local value=child.builder:valueId();child.params[#child.params+1]=I.ValueParam(input,value,inputType);child.scope[param.name.text]={value=value,type=inputType,callable=inputType:isView() or inputType:isOwned()}
    end
    if node.body.kind=="Expression" then child:returnValues({node.body.value},node.body.value)
    else child:statements(node.body.statements);if Check.falls(child.body) then reject("missing-return","Lambda can finish without returning",node) end end
    self.generated[#self.generated+1]=located(I.Fn(id,I.Body,#captures,L(child.inputs),L(child.results),L(child.params),L(child.body)),node)
    local actual=inferResults and S.view(S.sig(expected.visible.inputs,child.results)) or expected
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.View(value,actual,id,L(slots),#slots>0 and self.builder:storageId() or nil),node))
    return self.builder:ref(value,actual)
end

function Function:methodTarget(binding, methodName, owner)
    local schema=binding.schema and self.schemas[binding.schema] or nil
    local def=schema and schema.methods[methodName] or nil
    if not def then return nil end
    local key=(schema.prefix or "")..schema.name.."."..methodName
    local descriptor=self.methodState[key]
    if not descriptor then
        local inputs,results,keyed=signature(def,self.dynamic,self.types)
        local id=(schema.prefix or "").."__method_"..schema.name.."_"..methodName
        local child=setmetatable({def=def,id=id,signatures=self.signatures,globals=self.globals,types=self.types,typeCells=self.typeCells,schemas=self.schemas,methodState=self.methodState,builder=IR.builder(),body={},scope={},inputs={S.inPlace(schema.type)},results=results,params={},dynamic=self.dynamic,managed=self.managed,generated=self.generated,lambdaState=self.lambdaState,deferScopes={}},Function)
        local receiver=child.builder:storageId();child.params[1]=I.PlaceParam(0,receiver,schema.type)
        for _,field in ipairs(schema.type.fields) do child.scope[field.name]={place=I.Project(I.Local(receiver),I.Field(field.name)),type=field.type,schema=schema.fieldSchemas and schema.fieldSchemas[field.name] or nil} end
        descriptor={localWord=true,method=true,target=id,inputs=inputs,results=results,keyed=keyed}
        child.scope[methodName]={localWord=true,method=true,target=id,inputs=inputs,results=results,keyed=keyed,prefixArgs={I.BorrowArg(I.Local(receiver))}}
        for index,param in ipairs(def._semanticParams or def.params) do
            local ty=inputs[index].type;local input=#child.inputs;child.inputs[#child.inputs+1]=S.inValue(ty);local value=child.builder:valueId();child.params[#child.params+1]=I.ValueParam(input,value,ty)
            if ty:isRecord() or ty:isArray() or ty:isRef() or ty:isPtr() then local storage=child.builder:var(child.body,ty,child.builder:ref(value,ty));child.scope[param.name.text]={storage=storage,type=ty} else child.scope[param.name.text]={value=value,type=ty,callable=ty:isView() or ty:isOwned()} end
        end
        if def.body.kind=="Expression" then child:returnValues({def.body.value},def.body.value) else child:statements(def.body.statements) end
        if Check.falls(child.body) then reject("missing-return","Method `"..methodName.."` can finish without returning",def) end
        self.generated[#self.generated+1]=located(I.Fn(id,I.Body,1,L(child.inputs),L(results),L(child.params),L(child.body)),owner)
        self.methodState[key]=descriptor
    end
    local receiver=binding.place or (binding.storage and I.Local(binding.storage))
    if receiver and (binding.type:isRef() or binding.type:isPtr()) then receiver=I.Deref(receiver,self:sealed(binding.type.target)) end
    if not receiver then reject("not-a-place","A method needs an addressable receiver",owner) end
    return {localWord=true,method=true,target=descriptor.target,inputs=descriptor.inputs,results=descriptor.results,keyed=descriptor.keyed,prefixArgs={I.BorrowArg(receiver)}}
end

function Function:boundMethod(node,expected)
    local receiver=self:placeBinding(node.base)
    local target=receiver and receiver.schema and self:methodTarget(receiver,node.field.text,node) or nil
    if not target then return nil end
    if target.keyed then reject("keyed-required","A keyed method must be supplied by key before it becomes a value",node) end
    if not self.managed then reject("slet-forbidden","SLet cannot retain a method receiver",node) end
    local ty=S.view(S.sig(target.inputs,target.results))
    if expected and expected~=ty and expected~=S.any then reject("type-mismatch","Method value does not match the expected callable signature",node) end
    local viewType=expected==S.any and S.any or ty
    local value=self.builder:valueId()
    self.builder:emit(self.body,located(I.View(value,viewType,target.target,L(target.prefixArgs),self.builder:storageId()),node))
    return self.builder:ref(value,viewType)
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
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.Dynamic(L({value}),I[operation],L(dynamic)),node))
    local ty=operation=="WordHas" and S.bool or operation=="WordCount" and S.u32 or S.any
    return self.builder:ref(value,ty)
end

function Function:localWord(def, owner)
    local name=def.name.text
    if self.scope[name] then reject("duplicate-name","Local name `"..name.."` is declared twice",owner) end
    local visibleInputs,results,keyed=signature(def,self.dynamic,self.types)
    local captureNames={}
    for _,candidate in ipairs(Resolve.captures(def)) do if candidate~=name and self.scope[candidate] then captureNames[#captureNames+1]=candidate end end
    self.lambdaState.count=self.lambdaState.count+1
    local id=self.id.."_local_"..self.lambdaState.count
    local child=setmetatable({id=id,signatures=self.signatures,globals=self.globals,types=self.types,typeCells=self.typeCells,schemas=self.schemas,methodState=self.methodState,builder=IR.builder(),body={},scope={},inputs={},results=results,params={},dynamic=self.dynamic,managed=self.managed,generated=self.generated,lambdaState=self.lambdaState,deferScopes={}},Function)
    local parentSlots,recursiveSlots={},{}
    for _,captureName in ipairs(captureNames) do
        local source=self.scope[captureName];local input=#child.inputs
        if source.storage and (source.type:isRecord() or source.type:isArray()) then
            child.inputs[#child.inputs+1]=S.inPlace(source.type)
            local storage=child.builder:storageId();child.params[#child.params+1]=I.PlaceParam(input,storage,source.type)
            child.scope[captureName]={storage=storage,type=source.type,borrowedLocal=source.borrowedLocal}
            parentSlots[#parentSlots+1]=I.BorrowArg(I.Local(source.storage));recursiveSlots[#recursiveSlots+1]=I.BorrowArg(I.Local(storage))
        else
            child.inputs[#child.inputs+1]=S.inValue(source.type)
            local value=child.builder:valueId();child.params[#child.params+1]=I.ValueParam(input,value,source.type)
            if source.type:isRef() or source.type:isPtr() then local storage=child.builder:var(child.body,source.type,child.builder:ref(value,source.type));child.scope[captureName]={storage=storage,type=source.type,borrowedLocal=source.borrowedLocal}
            else child.scope[captureName]={value=value,type=source.type,callable=source.callable} end
            local captured;if source.storage then local read=self.builder:read(self.body,source.type,I.Local(source.storage));captured=self.builder:ref(read,source.type) else captured=self.builder:ref(source.value,source.type) end
            parentSlots[#parentSlots+1]=I.ValueArg(captured);recursiveSlots[#recursiveSlots+1]=I.ValueArg(child.builder:ref(value,source.type))
        end
    end
    local descriptor={localWord=true,target=id,inputs=visibleInputs,results=results,keyed=keyed,prefixArgs=parentSlots}
    self.scope[name]=descriptor
    child.scope[name]={localWord=true,target=id,inputs=visibleInputs,results=results,keyed=keyed,prefixArgs=recursiveSlots}
    for index,param in ipairs(def._semanticParams or def.params) do
        local ty=visibleInputs[index].type;local input=#child.inputs;child.inputs[#child.inputs+1]=S.inValue(ty)
        local value=child.builder:valueId();child.params[#child.params+1]=I.ValueParam(input,value,ty)
        if ty:isRecord() or ty:isArray() or ty:isRef() or ty:isPtr() then local storage=child.builder:var(child.body,ty,child.builder:ref(value,ty));child.scope[param.name.text]={storage=storage,type=ty}
        else child.scope[param.name.text]={value=value,type=ty,callable=ty:isView() or ty:isOwned()} end
    end
    child.def=def
    if def.body.kind=="Expression" then child:returnValues({def.body.value},def.body.value) else child:statements(def.body.statements) end
    if Check.falls(child.body) then reject("missing-return","Word `"..name.."` can finish without returning",def) end
    self.generated[#self.generated+1]=located(I.Fn(id,I.Body,#captureNames,L(child.inputs),L(results),L(child.params),L(child.body)),owner)
end

function Function:coerce(expr, expected, node)
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
    if expr.type:isInteger() and expected:isInteger() then return located(self.builder:convert(expr,expected),node) end
    reject("type-mismatch", "Expected "..S.display(expected).." but found "..S.display(expr.type), node)
end

function Function:call(node, expected, discard, allResults, prepareOnly)
    local name,callable,selectedMethod
    if node.callee.kind=="FieldSelect" then
        local receiver=self:placeBinding(node.callee.base)
        if receiver and receiver.schema then selectedMethod=self:methodTarget(receiver,node.callee.field.text,node.callee) end
    end
    if selectedMethod then name="<method>"
    elseif node.callee.kind=="Reference" then name=node.callee.name.text
    elseif node.callee.kind=="FieldSelect" and node.callee.base.kind=="Reference" then name=node.callee.base.name.text.."."..node.callee.field.text
    else callable=self:expr(node.callee);name="<callable>" end
    local binding=node.callee.kind=="Reference" and self.scope[name] or nil
    local localWord=selectedMethod or (binding and binding.localWord and binding or nil)
    local indirect=not localWord and (callable and {type=callable.type,expr=callable} or binding and (binding.callable or binding.type==S.any) and binding or nil)
    if node.callee.kind=="FieldSelect" and node.callee.base.kind=="Reference" then
        local sum=self.types[node.callee.base.name.text]
        if sum and sum:isSum() then
            local payloadType=S.caseOf(sum,node.callee.field.text);if not payloadType then reject("unknown-field","Unknown sum alternative",node.callee) end
            if payloadType==S.unit then if #node.arguments~=0 then reject("arity","Unit alternative expects no payload",node) end;return located(self:constructVariant(sum,node.callee.field.text,nil,node),node) end
            if #node.arguments~=1 then reject("arity","Sum alternative expects one payload",node) end
            local payload=self:coerce(self:expr(node.arguments[1],payloadType),payloadType,node.arguments[1])
            return located(self:constructVariant(sum,node.callee.field.text,payload,node),node)
        end
    end
    if name=="ref" or name=="ptr" then
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
    if self.dynamic and not binding then
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
    if indirect and indirect.type==S.any then
        local inputs={} for index=1,#node.arguments do inputs[index]=S.inValue(S.any) end;target={inputs=inputs,results={S.any},dynamic=true}
    else
        if indirect and not indirect.type:isView() then reject("type-mismatch","Callee is not callable",node.callee) end
        target=localWord or (indirect and {inputs=indirect.type.visible.inputs,results=indirect.type.visible.results} or self.signatures[name])
    end
    if not target then
        local conversion=BUILTIN_TYPES[name]
        if conversion and #node.arguments==1 then return self:coerce(self:expr(node.arguments[1],conversion),conversion,node) end
        reject("unknown-name", "Unknown word `"..name.."`", node.callee)
    end
    if target.keyed then reject("keyed-required","Word `"..name.."` must be supplied by key",node) end
    if #node.arguments>#target.inputs then reject("arity", "Word `"..name.."` expects at most "..#target.inputs.." arguments", node) end
    local args={};if localWord then for _,slot in ipairs(localWord.prefixArgs) do args[#args+1]=slot end end;local localBorrow=false
    for index,arg in ipairs(node.arguments) do
        local value=self:coerce(self:expr(arg,target.inputs[index].type),target.inputs[index].type,arg)
        if value.borrowedLocal then localBorrow=true end
        args[#args+1]=I.ValueArg(value)
    end
    if prepareOnly then
        if #node.arguments<#target.inputs then reject("arity","A deferred action must be a saturated call",node) end
        return {target=target,name=name,indirect=indirect,args=args,node=node}
    end
    if #node.arguments<#target.inputs then
        local runtimeSupply=false for _,argument in ipairs(node.arguments) do if not staticSupply(argument) then runtimeSupply=true;break end end
        if runtimeSupply and self.dynamic and not indirect and not localWord and not target.foreign then
            local callableValue=self.builder:valueId();self.builder:emit(self.body,located(I.View(callableValue,S.any,target.target or name,L{},nil),node))
            local dynamicArgs={} for _,arg in ipairs(args) do dynamicArgs[#dynamicArgs+1]=I.ValueArg(self:coerce(arg.value,S.any,node)) end
            local result=self.builder:valueId();self.builder:emit(self.body,located(I.Indirect(L({result}),self.builder:ref(callableValue,S.any),L(dynamicArgs)),node))
            return self.builder:ref(result,S.any)
        end
        if indirect then return self:indirectPartial(node,indirect,target,args,expected) end
        for _,argument in ipairs(node.arguments) do if not staticSupply(argument) then reject("static-required","Partial application requires static values",argument) end end
        local remaining={} for index=#node.arguments+1,#target.inputs do remaining[#remaining+1]=target.inputs[index] end
        local ty=S.view(S.sig(remaining,target.results))
        if expected and expected~=ty then reject("type-mismatch","Partial application does not match the expected callable signature",node) end
        local value=self.builder:valueId();self.builder:emit(self.body,located(I.View(value,ty,target.target or name,L(args),#args>0 and self.builder:storageId() or nil),node))
        local result=self.builder:ref(value,ty);if localBorrow then result.borrowedLocal=true end
        return result
    end
    local values={} for index=1,#target.results do values[index]=self.builder:valueId() end
    if indirect then
        local callableValue=indirect.expr or self.builder:ref(indirect.value,indirect.type)
        self.builder:emit(self.body,located(I.Indirect(L(values),callableValue,L(args)),node))
    else self.builder:emit(self.body,located(I.Call(L(values),target.target or name,L(args)),node)) end
    if discard then return end
    local refs={} for index,value in ipairs(values) do
        refs[index]=located(self.builder:ref(value,target.results[index]),node);refs[index].schema=target.resultSchemas and target.resultSchemas[index] or nil
        if localBorrow and containsBorrow(target.results[index]) then refs[index].borrowedLocal=true end
    end
    if allResults then return refs end
    if #target.results~=1 then reject("result-arity", "A call used as an expression must return exactly one value", node) end
    return refs[1]
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
    local byName,keyIndex={},{}
    for index,name in ipairs(target.keyed) do keyIndex[name]=index end
    local suppliedOrder={}
    for _,field in ipairs(node.fields) do
        local name=field.name.text;if byName[name] then reject("duplicate-name","Requirement `"..name.."` is supplied twice",field) end
        local index=keyIndex[name];if not index then reject("unknown-field","Unknown requirement `"..name.."`",field) end
        local value=self:coerce(self:expr(field.value,target.inputs[index].type),target.inputs[index].type,field.value)
        byName[name]=I.ValueArg(value);suppliedOrder[#suppliedOrder+1]={name=name,arg=byName[name],node=field.value}
    end
    local missing={} for index,name in ipairs(target.keyed) do if not byName[name] then missing[#missing+1]={name=name,index=index,input=target.inputs[index]} end end
    if #missing>0 then
        if target.localWord then reject("semantic-todo","Partial keyed supply of a nested word is not implemented",node) end
        if target.method and not self.managed then reject("slet-forbidden","SLet cannot retain a partially supplied method receiver",node) end
        for _,supply in ipairs(suppliedOrder) do if not staticSupply(supply.node) then reject("static-required","Partial keyed supply requires static values",supply.node) end end
        self.lambdaState.count=self.lambdaState.count+1;local id=self.id.."_keyed_"..self.lambdaState.count
        local builder=IR.builder();local inputs,params,arguments={},{},{}
        for _,supply in ipairs(suppliedOrder) do arguments[supply.name]=supply.arg end
        local visibleInputs={}
        for _,item in ipairs(missing) do local input=#inputs;inputs[#inputs+1]=item.input;visibleInputs[#visibleInputs+1]=item.input;local value=builder:valueId();params[#params+1]=I.ValueParam(input,value,item.input.type);arguments[item.name]=I.ValueArg(builder:ref(value,item.input.type)) end
        local args={} for _,name in ipairs(target.keyed) do args[#args+1]=arguments[name] end
        local values={} for index=1,#target.results do values[index]=builder:valueId() end
        local body={I.Call(L(values),target.target,L(args))};local returned={} for index,value in ipairs(values) do returned[index]=builder:ref(value,target.results[index]) end;body[#body+1]=I.Return(L(returned))
        self.generated[#self.generated+1]=located(I.Fn(id,I.Body,0,L(inputs),L(target.results),L(params),L(body)),node)
        local ty=S.view(S.sig(visibleInputs,target.results));if expected and expected~=ty then reject("type-mismatch","Partial keyed supply does not match the expected callable signature",node) end
        local value=self.builder:valueId();self.builder:emit(self.body,located(I.View(value,ty,id,L{},nil),node));return self.builder:ref(value,ty)
    end
    local args={}
    if target.localWord then for _,arg in ipairs(target.prefixArgs) do args[#args+1]=arg end end
    for _,name in ipairs(target.keyed) do args[#args+1]=byName[name] end
    local values={} for index=1,#target.results do values[index]=self.builder:valueId() end
    self.builder:emit(self.body,located(I.Call(L(values),target.target,L(args)),node))
    if #target.results~=1 then reject("result-arity","A keyed call used as an expression must return exactly one value",node) end
    return located(self.builder:ref(values[1],target.results[1]),node)
end

function Function:expr(node, expected)
    local kind=node.kind
    local expr
    if kind=="U32Literal" then
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
            if binding.localWord then
                local ty=S.view(S.sig(binding.inputs,binding.results));if expected==S.any then ty=S.any end
                local value=self.builder:valueId();self.builder:emit(self.body,located(I.View(value,ty,binding.target,L(binding.prefixArgs),#binding.prefixArgs>0 and self.builder:storageId() or nil),node));expr=self.builder:ref(value,ty)
            elseif binding.storage or binding.place then
                local place=binding.place or I.Local(binding.storage);local value=self.builder:read(self.body,binding.type,place);expr=self.builder:ref(value,binding.type);expr.schema=binding.schema;expr.borrowedLocal=binding.borrowedLocal
            else expr=self.builder:ref(binding.value,binding.type);expr.schema=binding.schema;expr.borrowedLocal=binding.borrowedLocal end
        else
            local target=self.signatures[node.name.text]
            if target then
                local ty=expected==S.any and S.any or S.view(S.sig(target.inputs,target.results));local value=self.builder:valueId()
                self.builder:emit(self.body,located(I.View(value,ty,target.target or node.name.text,L{},nil),node));expr=self.builder:ref(value,ty)
            else
                local global=self.globals[node.name.text]
                if not global then reject("unknown-name", "Unknown value `"..node.name.text.."`", node) end
                expr=self:expr(global.node,global.type)
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
        if node.schema.kind=="Reference" then
            local binding=self.scope[node.schema.name.text];local target=binding and binding.localWord and binding or self.signatures[node.schema.name.text]
            if target and target.keyed then return self:keyedSupply(node,target,expected) end
        elseif node.schema.kind=="FieldSelect" and node.schema.base.kind=="Reference" then
            local receiver=self.scope[node.schema.base.name.text]
            local target=receiver and receiver.schema and self:methodTarget(receiver,node.schema.field.text,node.schema) or nil
            if target and target.keyed then return self:keyedSupply(node,target,expected) end
        end
        if node.schema.kind=="FieldSelect" and node.schema.base.kind=="Reference" then
            local qualified=node.schema.base.name.text.."."..node.schema.field.text
            local interface=self.schemas[qualified]
            if interface and interface.type:isRecord() then local fields=self:recordFields(interface.type,node.fields,node);expr=self.builder:make(interface.type,fields);expr.schema=qualified
            else
            local sum=self.types[node.schema.base.name.text];local tag=node.schema.field.text
            if sum and sum:isSum() then
                local payloadType=S.caseOf(sum,tag);if not payloadType or not payloadType:isRecord() then reject("type-mismatch","Keyed construction needs a record alternative",node) end
                local fields=self:recordFields(payloadType,node.fields,node);local payload=self.builder:make(payloadType,fields)
                for _,field in ipairs(fields) do if field.borrowedLocal then payload.borrowedLocal=true end end
                expr=self:constructVariant(sum,tag,payload,node)
            else reject("type-required","Unknown sum type",node.schema) end
            end
        elseif node.schema.kind=="Reference" and self.types[node.schema.name.text] and self.types[node.schema.name.text]:isRecord() then
            local ty=self.types[node.schema.name.text];local fields=self:recordFields(ty,node.fields,node);expr=self.builder:make(ty,fields);expr.schema=node.schema.name.text
            for _,field in ipairs(fields) do if field.borrowedLocal then expr.borrowedLocal=true end end
        elseif node.schema.kind=="Reference" and self.scope[node.schema.name.text] then expr=self:sumMatch(node,expected)
        else reject("type-required","Record construction needs a named schema",node.schema) end
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
            local ok,value=pcall(function() return self:expr(valueNode,wanted) end)
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
    return self:coerce(expr,expected,node)
end

function Function:returnValues(nodes, owner)
    if not self.results then
        local values={}
        if #nodes==0 then values[1]=self.builder:const(S.unit,I.UInt(0))
        elseif #nodes==1 and nodes[1].kind=="Apply" then
            local produced=self:call(nodes[1],nil,false,true)
            if produced.kind then values[1]=produced else for _,value in ipairs(produced) do values[#values+1]=value end end
        else for _,node in ipairs(nodes) do values[#values+1]=self:expr(node) end end
        if #values==0 then values[1]=self.builder:const(S.unit,I.UInt(0)) end
        self.results={} for index,value in ipairs(values) do self.results[index]=value.type end
        self:emitDefers();self.builder:return_(self.body,values);located(self.body[#self.body],owner);return
    end
    if #nodes==0 and #self.results==1 and self.results[1]==S.unit then
        local value=self.builder:const(S.unit,I.UInt(0));self.builder:return_(self.body,{value});located(self.body[#self.body],owner);return
    end
    if #nodes==1 and nodes[1].kind=="Apply" and #self.results>1 then
        local values=self:call(nodes[1],nil,false,true)
        if #values~=#self.results then reject("return-arity", "Expected "..#self.results.." return values",owner) end
        for index,value in ipairs(values) do values[index]=self:coerce(value,self.results[index],nodes[1]) end
        self.builder:return_(self.body,values);located(self.body[#self.body],owner);return
    end
    if #nodes~=#self.results then reject("return-arity", "Expected "..#self.results.." return values",owner) end
    local values={} for index,node in ipairs(nodes) do
        values[index]=self:coerce(self:expr(node,self.results[index]),self.results[index],node)
        if not self.managed and values[index].borrowedLocal and containsBorrow(values[index].type) then reject("borrow-return","A value retaining local storage cannot be returned",node) end
    end
    self:emitDefers()
    self.builder:return_(self.body,values); located(self.body[#self.body],owner)
end

function Function:statements(statements)
    local deferred={}
    self.deferScopes[#self.deferScopes+1]=deferred
    for _,stmt in ipairs(statements) do
        local kind=stmt.kind
        if kind=="WordStmt" then
            self:localWord(stmt.def,stmt)
        elseif kind=="ValueStmt" then
            local produced={}
            for index,valueNode in ipairs(stmt.def.values) do
                if index==#stmt.def.values and valueNode.kind=="Apply" then
                    local values=self:call(valueNode,nil,false,true)
                    if values.kind then produced[#produced+1]=values else for _,value in ipairs(values) do produced[#produced+1]=value end end
                else
                    local binder=#stmt.def.binders==#stmt.def.values and stmt.def.binders[index] or nil
                    local wanted=binder and binder.annotation and typeExpr(binder.annotation,self.types) or nil
                    local value=self:expr(valueNode,wanted);local selectedSchema=binder and schemaName(binder.annotation,self.schemas);if selectedSchema then value.schema=selectedSchema end
                    produced[#produced+1]=value
                end
            end
            local pending={}
            for index,binder in ipairs(stmt.def.binders) do
                local wanted=binder.annotation and typeExpr(binder.annotation,self.types) or nil
                local origin=#stmt.def.binders==#stmt.def.values and stmt.def.values[index] or nil
                local source=origin and origin.kind=="Reference" and self.scope[origin.name.text] or nil
                if source and source.storage and (source.type:isRecord() or source.type:isArray()) then
                    if wanted and wanted~=source.type then reject("type-mismatch","Aggregate alias annotation does not match",binder) end
                    pending[index]={binder=binder,alias=source.storage,type=source.type,borrowedLocal=source.borrowedLocal}
                else
                    local target=origin and origin.kind=="Reference" and self.signatures[origin.name.text] or nil
                    if target then
                        if wanted and wanted~=S.any then reject("type-mismatch","Callable alias annotation must be any or its inferred signature",binder) end
                        local ty=wanted==S.any and S.any or S.view(S.sig(target.inputs,target.results))
                        pending[index]={binder=binder,callableTarget=target.target or origin.name.text,type=ty}
                    else
                        local value=produced[index] or self.builder:const(S.unit,I.UInt(0))
                        local coerced=self:coerce(value,wanted,binder);pending[index]={binder=binder,expr=coerced,schema=schemaName(binder.annotation,self.schemas) or coerced.schema}
                    end
                end
            end
            for _,entry in ipairs(pending) do
                local name=entry.binder.name.text;if self.scope[name] then reject("duplicate-name","Local name `"..name.."` is declared twice",entry.binder) end
                local value=self.builder:valueId()
                if entry.alias then self.scope[name]={storage=entry.alias,type=entry.type,borrowedLocal=entry.borrowedLocal}
                elseif entry.callableTarget then
                    self.builder:emit(self.body,located(I.View(value,entry.type,entry.callableTarget,L{},nil),stmt))
                    self.scope[name]={value=value,type=entry.type,callable=true}
                else
                    if entry.expr.type:isView() and entry.expr.kind=="Ref" then self.scope[name]={value=entry.expr.value,type=entry.expr.type,callable=true}
                    elseif entry.expr.type:isSum() and entry.expr.kind=="Ref" then self.scope[name]={value=entry.expr.value,type=entry.expr.type,borrowedLocal=entry.expr.borrowedLocal}
                    elseif entry.expr.type:isRecord() or entry.expr.type:isArray() or entry.expr.type:isRef() or entry.expr.type:isPtr() then
                        local storage=self.builder:var(self.body,entry.expr.type,entry.expr);self.scope[name]={storage=storage,type=entry.expr.type,schema=entry.schema,borrowedLocal=entry.expr.borrowedLocal}
                    else
                        self.builder:emit(self.body,located(I.Let(value,entry.expr.type,entry.expr),stmt));self.scope[name]={value=value,type=entry.expr.type,callable=entry.expr.type:isView() or entry.expr.type:isOwned(),borrowedLocal=entry.expr.borrowedLocal}
                    end
                end
            end
        elseif kind=="StoreStmt" then
            if (stmt.target.kind=="FieldSelect" or stmt.target.kind=="IndexExpr") and self:knownType(stmt.target.base)==S.any then
                local base=self:expr(stmt.target.base)
                local key=stmt.target.kind=="FieldSelect" and self.builder:const(S.string,I.Str(stmt.target.field.text)) or self:expr(stmt.target.index)
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

function Function:build()
    if self.def.body.kind=="Expression" then self:returnValues({self.def.body.value},self.def.body.value)
    else self:statements(self.def.body.statements) end
    if Check.falls(self.body) then reject("missing-return","Word `"..self.def.name.text.."` can finish without returning",self.def) end
    return located(I.Fn(self.id,I.Entry,0,L(self.inputs),L(self.results),L(self.params),L(self.body)),self.def)
end

function M.build(unit, options)
    if type(unit)~="table" or unit.phase~="parsed" then D.reject("compiler-phase","Semantic construction needs a parsed source unit") end
    options=options or {};local prefix=options.prefix or "";local dynamic=unit.profile and unit.profile.dynamic
    local signatures,globals,types,order,foreigns,cells={},{},{},{},{},{}
    for cell,ty in pairs(options.typeCells or {}) do cells[cell]=ty end
    for _,foreign in ipairs(options.foreigns or {}) do foreigns[#foreigns+1]=foreign;signatures[foreign.target]={inputs=foreign.inputs,results=foreign.results,target=foreign.target,foreign=true} end
    for name,ty in pairs(options.types or {}) do types[name]=ty end
    for name,entry in pairs(options.imports or {}) do signatures[name]=entry end
    -- File-scope type declarations are mutually visible and resolved on demand. A recursive demand
    -- receives a stable Named cell. Sealing then checks the complete graph for by-value cycles.
    local typeDefs,typeState,typeDecl,typeOrder,schemas,schemaSerial={},{},{},{},{},0
    for name,schema in pairs(options.schemas or {}) do schemas[name]=schema;if schema.face and schema.face.id>schemaSerial then schemaSerial=schema.face.id end end
    local constructors={ref=true,ptr=true,slice=true,array=true,oneof=true}
    local function obviousType(node) return node.kind=="SchemaExpr" or node.kind=="SignatureExpr" or (node.kind=="Apply" and node.callee.kind=="Reference" and constructors[node.callee.name.text]) end
    for _,decl in ipairs(unit.ast.declarations) do
        if decl.kind=="ValueDecl" and #decl.def.binders==1 and #decl.def.values==1 and not decl.def.binders[1].annotation and obviousType(decl.def.values[1]) then
            local name=decl.def.binders[1].name.text;if rawget(types,name) or typeDefs[name] then reject("duplicate-name","Type `"..name.."` is declared twice",decl) end
            typeDefs[name]=decl.def.values[1];typeDecl[name]=decl;typeOrder[#typeOrder+1]=name;decl._typeDeclaration=true
        end
    end
    local changed=true
    while changed do
        changed=false
        for _,decl in ipairs(unit.ast.declarations) do
            if decl.kind=="ValueDecl" and #decl.def.binders==1 and #decl.def.values==1 and not decl.def.binders[1].annotation and not decl._typeDeclaration then
                local node=decl.def.values[1]
                local referenced=node.kind=="Reference" and (BUILTIN_TYPES[node.name.text] or rawget(types,node.name.text) or typeDefs[node.name.text])
                local selected=node.kind=="FieldSelect" and node.base.kind=="Reference" and rawget(types,node.base.name.text.."."..node.field.text)
                if referenced or selected then local name=decl.def.binders[1].name.text;if rawget(types,name) or typeDefs[name] then reject("duplicate-name","Type `"..name.."` is declared twice",decl) end;typeDefs[name]=node;typeDecl[name]=decl;typeOrder[#typeOrder+1]=name;decl._typeDeclaration=true;changed=true end
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
        local ty=typeExpr(node,types)
        rawset(types,name,ty);cells[cell]=ty;typeState[name]="sealed"
        if node.kind=="SchemaExpr" then
            local methods,fieldSchemas={},{}
            for _,member in ipairs(node.members) do
                if member.kind=="MethodMember" then local methodName=member.def.name.text;if methods[methodName] or S.field(ty,methodName) then reject("duplicate-name","Schema member `"..methodName.."` is declared twice",member) end;methods[methodName]=member.def
                else
                    local annotation=member.type
                    if annotation.kind=="Reference" and (typeDefs[annotation.name.text] or rawget(types,annotation.name.text)) then fieldSchemas[member.name.text]=annotation.name.text
                    elseif annotation.kind=="Apply" and annotation.callee.kind=="Reference" and (annotation.callee.name.text=="ref" or annotation.callee.name.text=="ptr") and annotation.arguments[1] and annotation.arguments[1].kind=="Reference" then fieldSchemas[member.name.text]=annotation.arguments[1].name.text end
                end
            end
            schemaSerial=schemaSerial+1;schemas[name]={face=S.Surface.Schema(schemaSerial),type=ty,methods=methods,fieldSchemas=fieldSchemas,name=name,prefix=prefix}
        end
        return ty
    end
    setmetatable(types,{__index=function(_,name) return resolveType(name) end})
    for _,name in ipairs(typeOrder) do resolveType(name) end
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
    local done={}
    for _,name in ipairs(typeOrder) do local cell=prefix.."type:"..name;if not finiteLayout(cells[cell],{[cell]=true},done) then reject("type-cycle","Type `"..name.."` has no finite layout",typeDecl[name]) end;done[cell]=true end
    local contracts={}
    for _,entry in ipairs(unit.ast.export.results) do
        if entry.target.kind~="Reference" then reject("result-contract","A results contract must name a word",entry.target) end
        local name=entry.target.name.text
        if contracts[name] then reject("duplicate-name","Word `"..name.."` has more than one results contract",entry.target) end
        contracts[name]=resultTypes(entry.result,types)
    end
    for _,decl in ipairs(unit.ast.declarations) do if decl.kind=="WordDecl" and contracts[decl.def.name.text] then
        local declared=resultTypes(decl.def.result,types);local contract=contracts[decl.def.name.text]
        if declared then
            if #declared~=#contract then reject("result-type","Results contract disagrees with word `"..decl.def.name.text.."`",decl) end
            for index,ty in ipairs(declared) do if ty~=contract[index] then reject("result-type","Results contract disagrees with word `"..decl.def.name.text.."`",decl) end end
        else decl.def._resultTypes=contract end
        contracts[decl.def.name.text]=nil
    end end
    for name in pairs(contracts) do D.reject("unknown-name","Results contract names unknown word `"..name.."`") end
    for _,decl in ipairs(unit.ast.declarations) do
        if decl.kind=="WordDecl" then
            local inputs,results,keyed=signature(decl.def,dynamic,types);local id=prefix..decl.def.name.text;signatures[decl.def.name.text]={inputs=inputs,results=results,resultSchemas=resultInterfaces(decl.def.result,schemas),keyed=keyed,target=id};order[#order+1]={def=decl.def,id=id}
        elseif decl.kind=="ForeignDecl" then
            local inputs,names={},{}
            for _,param in ipairs(decl.def.params) do local name=param.name.text;if names[name] then reject("duplicate-name","Foreign parameter `"..name.."` is declared more than once",param) end;names[name]=true;inputs[#inputs+1]=S.inValue(typeExpr(param.annotation,types)) end
            local results=resultTypes(decl.def.result,types);local target=decl.def.name.text
            if signatures[target] then reject("duplicate-name","Foreign word `"..target.."` conflicts with another word",decl) end
            local foreign=located(I.Foreign(target,L(inputs),L(results)),decl);foreigns[#foreigns+1]=foreign;signatures[target]={inputs=foreign.inputs,results=foreign.results,resultSchemas=resultInterfaces(decl.def.result,schemas),target=target,foreign=true}
        elseif decl.kind=="ValueDecl" and not decl._typeDeclaration then
            if #decl.def.binders~=#decl.def.values then reject("binding-arity","A top-level value declaration needs one value per binder",decl) end
            for index,binder in ipairs(decl.def.binders) do
                local node=decl.def.values[index];local inferred=literalType(node)
                if not inferred then reject("semantic-todo","Only literal top-level values are implemented; initializer computation must run through ABC",node) end
                local ty=binder.annotation and typeExpr(binder.annotation,types) or inferred
                if inferred~=ty and ty~=S.any and not (inferred:isInteger() and ty:isInteger()) then reject("type-mismatch","Top-level initializer does not match its annotation",node) end
                globals[binder.name.text]={node=node,type=ty}
            end
        elseif decl.kind=="ValueDecl" then -- compile-time type declaration already collected above
        elseif decl.kind=="UseDecl" then if not options.importsResolved then reject("import-input","A source string cannot resolve imports; compile a file",decl) end
        else reject("semantic-todo", "Top-level "..decl.kind.." is not implemented by source-to-IR construction",decl) end
    end
    local functions,generated,lambdaState,methodState={},{},{count=0},{}
    for _,entry in ipairs(order) do
        local fn=Function.new(entry.def,entry.id,signatures,globals,types,dynamic,unit.profile and unit.profile.managed,generated,lambdaState,cells,schemas,methodState):build();functions[#functions+1]=fn
    end
    for _,fn in ipairs(generated) do functions[#functions+1]=fn end
    for _,item in ipairs(unit.ast.export.functions) do if item.kind=="ExportAlias" then
        local source
        if item.value.kind=="Reference" then source=item.value.name.text
        elseif item.value.kind=="FieldSelect" and item.value.base.kind=="Reference" then source=item.value.base.name.text.."."..item.value.field.text
        else reject("semantic-todo","A function export alias currently requires a direct word",item.value) end
        local target=signatures[source];if not target then reject("unknown-name","Unknown exported word `"..source.."`",item.value) end
        local public=item.name.text;if signatures[public] then reject("duplicate-name","Function export alias `"..public.."` conflicts with a word",item.name) end
        local builder=IR.builder();local params,args={},{ }
        for index,input in ipairs(target.inputs) do
            if input.kind~="InValue" then reject("semantic-todo","Export aliases of borrowed-input words are not implemented",item) end
            local value=builder:valueId();params[#params+1]=I.ValueParam(index-1,value,input.type);args[#args+1]=I.ValueArg(builder:ref(value,input.type))
        end
        local results={} for index=1,#target.results do results[index]=builder:valueId() end
        local body={I.Call(L(results),target.target or source,L(args))};local returned={}
        for index,value in ipairs(results) do returned[index]=builder:ref(value,target.results[index]) end
        body[#body+1]=I.Return(L(returned))
        local id=prefix..public;local wrapper=located(I.Fn(id,I.Entry,0,L(target.inputs),L(target.results),L(params),L(body)),item)
        functions[#functions+1]=wrapper;signatures[public]={inputs=target.inputs,results=target.results,target=id}
    end end
    local checked={} for _,fn in ipairs(options.dependencies or {}) do checked[#checked+1]=fn end
    for _,fn in ipairs(functions) do checked[#checked+1]=fn end
    Check.program(checked, nil, foreigns)
    local exportedTypes,exportedSchemas={},{}
    for _,item in ipairs(unit.ast.export.types) do
        local ty
        if item.kind=="ExportName" then ty=types[item.name.text]
        else ty=typeExpr(item.value,types) end
        if not ty then reject("unknown-name","Unknown exported type `"..item.name.text.."`",item.name) end
        if exportedTypes[item.name.text] then reject("duplicate-name","Type export `"..item.name.text.."` is repeated",item.name) end
        exportedTypes[item.name.text]=ty
        local sourceName=item.kind=="ExportName" and item.name.text or schemaName(item.value,schemas)
        if sourceName and schemas[sourceName] then exportedSchemas[item.name.text]=schemas[sourceName] end
    end
    for _,item in ipairs(unit.ast.export.functions) do
        if not signatures[item.name.text] then reject("unknown-name","Unknown exported word `"..item.name.text.."`",item.name) end
    end
    unit.phase="typed-ir";unit.functions=functions;unit.signatures=signatures;unit.types=types;unit.exportedTypes=exportedTypes;unit.exportedSchemas=exportedSchemas;unit.foreigns=foreigns;unit.typeCells=cells;unit.schemas=schemas
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

