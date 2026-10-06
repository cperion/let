-- Source AST to verified ASDL IR. This pass resolves names and types but never executes user code.
local S = require("let.schema")
local IR = require("let.ir")
local Check = require("let.check")
local Walk = require("let.walk")
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
    elseif node and node.kind=="SchemaExpr" then
        local fields={}
        for _,member in ipairs(node.members) do
            if member.kind~="FieldMember" then reject("semantic-todo","Methods in source schemas are not implemented",member) end
            if fields[member.name.text] then reject("duplicate-name","Schema field `"..member.name.text.."` is declared twice",member) end
            fields[member.name.text]=typeExpr(member.type,types)
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

local function resultTypes(spec,types)
    if not spec then return nil end
    local out={}
    if spec.kind=="Single" then out[1]=typeExpr(spec.type,types)
    else for _,node in ipairs(spec.types) do out[#out+1]=typeExpr(node,types) end end
    return out
end

local function signature(def,dynamic,types)
    if #def.keyed>0 then reject("semantic-todo", "Keyed requirements are not implemented by source-to-IR construction", def) end
    local inputs={}
    for _,param in ipairs(def.params) do
        if not param.annotation and not dynamic then reject("parameter-type", "Parameter `"..param.name.text.."` needs a type annotation", param) end
        inputs[#inputs+1]=S.inValue(param.annotation and typeExpr(param.annotation,types) or S.any)
    end
    local results=resultTypes(def.result,types)
    if not results then reject("result-type", "Word `"..def.name.text.."` needs an explicit result type", def) end
    return inputs,results
end

local Function = {}
Function.__index = Function

function Function.new(def, id, signatures, globals, types, dynamic, managed, generated, lambdaState)
    local inputs,results=signature(def,dynamic,types)
    local self=setmetatable({def=def,id=id,signatures=signatures,globals=globals,types=types,builder=IR.builder(),body={},scope={},inputs=inputs,results=results,params={},managed=managed,generated=generated or {},lambdaState=lambdaState or {count=0}},Function)
    for index,param in ipairs(def.params) do
        local value=self.builder:valueId(); local ty=inputs[index].type
        self.params[#self.params+1]=located(I.ValueParam(index-1,value,ty),param)
        if ty:isRecord() or ty:isArray() or ty:isRef() then
            local storage=self.builder:var(self.body,ty,self.builder:ref(value,ty));self.scope[param.name.text]={storage=storage,type=ty}
        else self.scope[param.name.text]={value=value,type=ty} end
    end
    return self
end

function Function:place(node)
    if node.kind=="Reference" then
        local binding=self.scope[node.name.text]
        if not binding or not binding.storage then reject("not-a-place","`"..node.name.text.."` is not addressable",node) end
        return I.Local(binding.storage),binding.type
    elseif node.kind=="FieldSelect" then
        local base,ty=self:place(node.base)
        if ty:isRef() then base,ty=I.Deref(base,ty.target),ty.target end
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

function Function:readPlace(node)
    local place,ty=self:place(node);local value=self.builder:read(self.body,ty,place);return self.builder:ref(value,ty)
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
    return self.builder:ref(value,sum)
end

function Function:sumMatch(node, expected)
    local variant=self:expr(node.schema);if not variant.type:isSum() then reject("type-mismatch","Keyed matching needs a sum value",node.schema) end
    local variantValue=variant.kind=="Ref" and variant.value or self.builder:let(self.body,variant.type,variant)
    local handlers={} for _,field in ipairs(node.fields) do local name=field.name.text;if handlers[name] then reject("duplicate-name","Alternative `"..name.."` is handled twice",field) end;handlers[name]=field.value end
    local resultStorage=self.builder:storageId();local resultType=expected;local cases={}
    local parentBody,parentScope=self.body,self.scope
    local alternatives=S.alternatives(variant.type)
    for index,alternative in ipairs(alternatives) do
        local lambda=handlers[alternative.name];if not lambda then reject("missing-field","Missing handler for `"..alternative.name.."`",node) end
        if lambda.kind~="Lambda" or lambda.body.kind~="Expression" then reject("semantic-todo","Sum handlers currently require expression lambdas",lambda) end
        local list={};self.body,self.scope=list,copy(parentScope)
        if alternative.type==S.unit then if #lambda.params~=0 then reject("arity","Unit alternative handler expects no parameter",lambda) end
        else
            if #lambda.params~=1 then reject("arity","Alternative handler expects one payload parameter",lambda) end
            local payload=self.builder:valueId();self.builder:emit(list,located(I.VariantPayload(payload,variantValue,variant.type,alternative.name),lambda))
            if alternative.type:isRef() or alternative.type:isRecord() or alternative.type:isArray() then
                local storage=self.builder:var(list,alternative.type,self.builder:ref(payload,alternative.type));self.scope[lambda.params[1].name.text]={storage=storage,type=alternative.type}
            else self.scope[lambda.params[1].name.text]={value=payload,type=alternative.type} end
        end
        local ok,value=pcall(function() return self:expr(lambda.body.value,resultType) end)
        if ok and not resultType then resultType=value.type end
        if ok then value=self:coerce(value,resultType,lambda.body.value);self.builder:store(list,I.Local(resultStorage),value) end
        self.body,self.scope=parentBody,parentScope;if not ok then error(value,0) end
        cases[#cases+1]=I.Case(alternative.name,index==#alternatives,L(list));handlers[alternative.name]=nil
    end
    for name in pairs(handlers) do reject("unknown-field","Unknown alternative `"..name.."`",node) end
    self.builder:emit(parentBody,located(I.Var(resultStorage,resultType,nil),node));self.builder:emit(parentBody,located(I.Switch(variantValue,variant.type,L(cases)),node))
    local value=self.builder:read(parentBody,resultType,I.Local(resultStorage));return self.builder:ref(value,resultType)
end
function Function:lambda(node, expected)
    if not expected or not expected:isView() then reject("type-required","A lambda needs a callable signature annotation",node) end
    if node.body.kind~="Expression" or #expected.visible.results~=1 then reject("semantic-todo","Source lambdas currently need an expression body and one result",node) end
    if #node.params~=#expected.visible.inputs then reject("arity","Lambda parameter count does not match its signature",node) end
    local parameterNames={} for _,param in ipairs(node.params) do parameterNames[param.name.text]=true end
    local captures,seen={},{}
    Walk.walk(node.body,{enter=function(item)
        if item.kind=="Reference" and not parameterNames[item.name.text] and self.scope[item.name.text] and not seen[item.name.text] then seen[item.name.text]=true;captures[#captures+1]=item.name.text end
    end})
    table.sort(captures)
    if not self.managed then for _,name in ipairs(captures) do if containsBorrow(self.scope[name].type) then reject("borrow-store","An escaping closure cannot retain a reference or slice capture",node) end end end
    if #captures>0 and not self.managed then reject("slet-forbidden","SLet lambdas cannot capture local values",node) end
    self.lambdaState.count=self.lambdaState.count+1;local id=self.id.."_lambda_"..self.lambdaState.count
    local child=setmetatable({id=id,signatures=self.signatures,globals=self.globals,types=self.types,builder=IR.builder(),body={},scope={},inputs={},results=expected.visible.results,params={},managed=self.managed,generated=self.generated,lambdaState=self.lambdaState},Function)
    local slots={}
    for _,name in ipairs(captures) do
        local source=self.scope[name];local input=#child.inputs
        if source.storage and (source.type:isRecord() or source.type:isArray()) then
            child.inputs[#child.inputs+1]=S.inPlace(source.type);local storage=child.builder:storageId();child.params[#child.params+1]=I.PlaceParam(input,storage,source.type);child.scope[name]={storage=storage,type=source.type}
            slots[#slots+1]=I.BorrowArg(I.Local(source.storage))
        else
            child.inputs[#child.inputs+1]=S.inValue(source.type);local value=child.builder:valueId();child.params[#child.params+1]=I.ValueParam(input,value,source.type)
            if source.type:isRef() then local storage=child.builder:var(child.body,source.type,child.builder:ref(value,source.type));child.scope[name]={storage=storage,type=source.type}
            else child.scope[name]={value=value,type=source.type,callable=source.callable} end
            local captured
            if source.storage then local valueId=self.builder:read(self.body,source.type,I.Local(source.storage));captured=self.builder:ref(valueId,source.type) else captured=self.builder:ref(source.value,source.type) end
            slots[#slots+1]=I.ValueArg(captured)
        end
    end
    for index,param in ipairs(node.params) do
        local inputType=expected.visible.inputs[index].type
        if param.annotation and typeExpr(param.annotation,self.types)~=inputType then reject("type-mismatch","Lambda parameter annotation does not match its signature",param) end
        local input=#child.inputs;child.inputs[#child.inputs+1]=S.inValue(inputType);local value=child.builder:valueId();child.params[#child.params+1]=I.ValueParam(input,value,inputType);child.scope[param.name.text]={value=value,type=inputType}
    end
    local result=child:coerce(child:expr(node.body.value,child.results[1]),child.results[1],node.body.value);child.builder:return_(child.body,{result})
    self.generated[#self.generated+1]=located(I.Fn(id,I.Body,#captures,L(child.inputs),L(child.results),L(child.params),L(child.body)),node)
    local value=self.builder:valueId();self.builder:emit(self.body,located(I.View(value,expected,id,L(slots),#slots>0 and self.builder:storageId() or nil),node))
    return self.builder:ref(value,expected)
end

function Function:coerce(expr, expected, node)
    if not expected or expr.type==expected then return expr end
    if (expr.type==S.any and expected~=S.type) or (expected==S.any and expr.type~=S.type) then return located(self.builder:convert(expr,expected),node) end
    if expr.type:isInteger() and expected:isInteger() then return located(self.builder:convert(expr,expected),node) end
    reject("type-mismatch", "Expected "..S.display(expected).." but found "..S.display(expr.type), node)
end

function Function:call(node, expected, discard, allResults)
    local name
    if node.callee.kind=="Reference" then name=node.callee.name.text
    elseif node.callee.kind=="FieldSelect" and node.callee.base.kind=="Reference" then name=node.callee.base.name.text.."."..node.callee.field.text
    else reject("semantic-todo", "Indirect source calls are not implemented", node.callee) end
    local binding=node.callee.kind=="Reference" and self.scope[name] or nil
    local indirect=binding and (binding.callable or binding.type==S.any) and binding or nil
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
    if name=="ref" then
        if #node.arguments~=1 then reject("arity","ref expects one place",node) end
        local place,ty=self:place(node.arguments[1]);local result=located(self.builder:addr(place,S.ref(ty)),node);result.borrowedLocal=true;return result
    elseif name=="slice" then
        if #node.arguments~=1 then reject("arity","slice expects one array",node) end
        local place,ty=self:place(node.arguments[1]);if not ty:isArray() then reject("type-mismatch","slice expects an array place",node.arguments[1]) end
        local first=I.Index(place,self.builder:u32(0),ty.element);local address=self.builder:addr(first,S.ref(ty.element))
        local result=located(self.builder:make(S.slice(ty.element),{address,self.builder:u32(ty.length)}),node);result.borrowedLocal=true;return result
    end
    if name=="is" then
        if #node.arguments~=2 then reject("arity","is expects a value and a type",node) end
        local operand=self:coerce(self:expr(node.arguments[1]),S.any,node.arguments[1]);local tested=typeExpr(node.arguments[2],self.types)
        return located(self.builder:isType(operand,tested),node)
    end
    local target
    if indirect and indirect.type==S.any then
        local inputs={} for index=1,#node.arguments do inputs[index]=S.inValue(S.any) end;target={inputs=inputs,results={S.any},dynamic=true}
    else target=indirect and {inputs=indirect.type.visible.inputs,results=indirect.type.visible.results} or self.signatures[name] end
    if not target then
        local conversion=BUILTIN_TYPES[name]
        if conversion and #node.arguments==1 then return self:coerce(self:expr(node.arguments[1],conversion),conversion,node) end
        reject("unknown-name", "Unknown word `"..name.."`", node.callee)
    end
    if #node.arguments~=#target.inputs then reject("arity", "Word `"..name.."` expects "..#target.inputs.." arguments", node) end
    local args={}
    for index,arg in ipairs(node.arguments) do
        args[index]=I.ValueArg(self:coerce(self:expr(arg,target.inputs[index].type),target.inputs[index].type,arg))
    end
    local values={} for index=1,#target.results do values[index]=self.builder:valueId() end
    if indirect then
        self.builder:emit(self.body,located(I.Indirect(L(values),self.builder:ref(indirect.value,indirect.type),L(args)),node))
    else self.builder:emit(self.body,located(I.Call(L(values),target.target or name,L(args)),node)) end
    if discard then return end
    local refs={} for index,value in ipairs(values) do refs[index]=located(self.builder:ref(value,target.results[index]),node) end
    if allResults then return refs end
    if #target.results~=1 then reject("result-arity", "A call used as an expression must return exactly one value", node) end
    return refs[1]
end

function Function:expr(node, expected)
    local kind=node.kind
    local expr
    if kind=="U32Literal" then
        local literalType=expected==S.any and S.i64 or expected and expected:isInteger() and expected or S.u32
        expr=self.builder:int(literalType,node.value)
    elseif kind=="U64Literal" then expr=self.builder:int64(expected and expected:isInteger() and expected or S.u64,node.high,node.low)
    elseif kind=="FloatLiteral" then expr=self.builder:float(S.f64,node.value)
    elseif kind=="BoolLiteral" then expr=self.builder:bool(node.value)
    elseif kind=="UnitLiteral" then expr=self.builder:const(S.unit,I.UInt(0))
    elseif kind=="StringLiteral" then expr=self.builder:const(S.string,I.Str(node.bytes))
    elseif kind=="Reference" then
        local binding=self.scope[node.name.text]
        if binding then
            if binding.storage then
                local value=self.builder:read(self.body,binding.type,I.Local(binding.storage));expr=self.builder:ref(value,binding.type);expr.borrowedLocal=binding.borrowedLocal
            else expr=self.builder:ref(binding.value,binding.type);expr.borrowedLocal=binding.borrowedLocal end
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
    elseif kind=="RecordSupply" then
        if node.schema.kind=="FieldSelect" and node.schema.base.kind=="Reference" then
            local sum=self.types[node.schema.base.name.text];local tag=node.schema.field.text
            if sum and sum:isSum() then
                local payloadType=S.caseOf(sum,tag);if not payloadType or not payloadType:isRecord() then reject("type-mismatch","Keyed construction needs a record alternative",node) end
                expr=self:constructVariant(sum,tag,self.builder:make(payloadType,self:recordFields(payloadType,node.fields,node)),node)
            else reject("type-required","Unknown sum type",node.schema) end
        elseif node.schema.kind=="Reference" and self.types[node.schema.name.text] and self.types[node.schema.name.text]:isRecord() then
            local ty=self.types[node.schema.name.text];expr=self.builder:make(ty,self:recordFields(ty,node.fields,node))
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
        expr=self.builder:make(ty,fields)
    elseif kind=="FieldSelect" then
        if node.field.text=="length" then local base=self:expr(node.base);if not base.type:isSlice() then reject("unknown-field","Only slices have length",node) end;expr=self.builder:sliceLength(base,S.u32)
        elseif node.base.kind=="Reference" then
            local binding=self.scope[node.base.name.text]
            if binding and binding.value and binding.type:isRecord() then
                local fieldType=S.field(binding.type,node.field.text);if not fieldType then reject("unknown-field","Unknown field `"..node.field.text.."`",node) end
                expr=self.builder:get(self.builder:ref(binding.value,binding.type),node.field.text,fieldType)
            else expr=self:readPlace(node) end
        else expr=self:readPlace(node) end
    elseif kind=="IndexExpr" then expr=self:readPlace(node)
    elseif kind=="Lambda" then return self:lambda(node,expected)
    elseif kind=="UnaryExpr" then
        local op=UNARY[node.operator]; if not op then reject("operator", "Unsupported unary operator `"..node.operator.."`",node) end
        local operand=self:expr(node.operand,expected)
        if op=="Not" then
            if operand.type~=S.bool and operand.type~=S.any then reject("type-mismatch","`not` needs bool or any",node) end;expr=self.builder:un(op,operand,operand.type==S.any and S.bool or S.bool)
        else if not operand.type:isInteger() and operand.type~=S.f64 and operand.type~=S.any then reject("type-mismatch","Unary operator needs a number or any",node) end;expr=self.builder:un(op,operand,operand.type) end
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
            local yes,no
            if node.operator=="and" then yes,no=arm(node.right,nil),arm(nil,false) else yes,no=arm(nil,true),arm(node.right,nil) end
            self.builder:emit(parentBody,located(I.Var(storage,S.bool,nil),node))
            self.builder:emit(parentBody,located(I.If(left,L(yes),L(no)),node))
            local value=self.builder:read(parentBody,S.bool,I.Local(storage));expr=self.builder:ref(value,S.bool)
        else
            local op=BINARY[node.operator]; if not op then reject("semantic-todo", "Operator `"..node.operator.."` is not implemented",node) end
            local leftExpected=expected;if COMPARISON[node.operator] then leftExpected=nil end
            local left=self:expr(node.left,leftExpected)
            local right=self:coerce(self:expr(node.right,left.type),left.type,node.right)
            if left.type~=right.type then reject("type-mismatch","Binary operands need the same type",node) end
            if not left.type:isInteger() and left.type~=S.f64 and left.type~=S.any and not (left.type==S.bool and (op=="Eq" or op=="Ne")) then reject("type-mismatch","Operator needs scalar or any operands",node) end
            expr=self.builder:bin(op,left,right,COMPARISON[node.operator] and S.bool or left.type)
        end
    elseif kind=="Condition" then
        local test=self:coerce(self:expr(node.test,S.bool),S.bool,node.test)
        local storage=self.builder:storageId()
        local parentBody,parentScope=self.body,self.scope
        local function arm(valueNode,wanted)
            local list={};self.body,self.scope=list,copy(parentScope)
            local ok,value=pcall(function() return self:expr(valueNode,wanted) end)
            self.body,self.scope=parentBody,parentScope;if not ok then error(value,0) end
            self.builder:store(list,I.Local(storage),value);return list,value.type
        end
        local yes,ty=arm(node.yes,expected)
        local no,noType=arm(node.no,expected or ty)
        if noType~=ty then reject("type-mismatch","Conditional arms need the same type",node) end
        self.builder:emit(parentBody,located(I.Var(storage,ty,nil),node))
        self.builder:emit(parentBody,located(I.If(test,L(yes),L(no)),node))
        local value=self.builder:read(parentBody,ty,I.Local(storage));expr=self.builder:ref(value,ty)
    else reject("semantic-todo", "Source expression "..tostring(kind).." is not implemented",node) end
    located(expr,node)
    return self:coerce(expr,expected,node)
end

function Function:returnValues(nodes, owner)
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
        if not self.managed and values[index].borrowedLocal and (values[index].type:isRef() or values[index].type:isSlice()) then reject("borrow-return","A view or reference to local storage cannot be returned",node) end
    end
    self.builder:return_(self.body,values); located(self.body[#self.body],owner)
end

function Function:statements(statements)
    for _,stmt in ipairs(statements) do
        local kind=stmt.kind
        if kind=="ValueStmt" then
            if #stmt.def.binders~=#stmt.def.values then reject("binding-arity","A value declaration needs one value per binder",stmt) end
            local pending={}
            for index,valueNode in ipairs(stmt.def.values) do
                local binder=stmt.def.binders[index]; local wanted=binder.annotation and typeExpr(binder.annotation,self.types) or nil
                local source=valueNode.kind=="Reference" and self.scope[valueNode.name.text] or nil
                if source and source.storage and (source.type:isRecord() or source.type:isArray()) then
                    if wanted and wanted~=source.type then reject("type-mismatch","Aggregate alias annotation does not match",binder) end
                    pending[index]={binder=binder,alias=source.storage,type=source.type}
                else
                local target=valueNode.kind=="Reference" and self.signatures[valueNode.name.text] or nil
                if target then
                    if wanted and wanted~=S.any then reject("type-mismatch","Callable alias annotation must be any or its inferred signature",binder) end
                    local ty=wanted==S.any and S.any or S.view(S.sig(target.inputs,target.results))
                    pending[index]={binder=binder,callableTarget=target.target or valueNode.name.text,type=ty}
                else pending[index]={binder=binder,expr=self:expr(valueNode,wanted)} end
                end
            end
            for _,entry in ipairs(pending) do
                local name=entry.binder.name.text;if self.scope[name] then reject("duplicate-name","Local name `"..name.."` is declared twice",entry.binder) end
                local value=self.builder:valueId()
                if entry.alias then self.scope[name]={storage=entry.alias,type=entry.type}
                elseif entry.callableTarget then
                    self.builder:emit(self.body,located(I.View(value,entry.type,entry.callableTarget,L{},nil),stmt))
                    self.scope[name]={value=value,type=entry.type,callable=true}
                else
                    if entry.expr.type:isView() and entry.expr.kind=="Ref" then self.scope[name]={value=entry.expr.value,type=entry.expr.type,callable=true}
                    elseif entry.expr.type:isSum() and entry.expr.kind=="Ref" then self.scope[name]={value=entry.expr.value,type=entry.expr.type}
                    elseif entry.expr.type:isRecord() or entry.expr.type:isArray() or entry.expr.type:isRef() then
                        local storage=self.builder:var(self.body,entry.expr.type,entry.expr);self.scope[name]={storage=storage,type=entry.expr.type,borrowedLocal=entry.expr.borrowedLocal}
                    else
                        self.builder:emit(self.body,located(I.Let(value,entry.expr.type,entry.expr),stmt));self.scope[name]={value=value,type=entry.expr.type,callable=entry.expr.type:isView() or entry.expr.type:isOwned(),borrowedLocal=entry.expr.borrowedLocal}
                    end
                end
            end
        elseif kind=="StoreStmt" then
            local place,ty=self:place(stmt.target);local value
            if stmt.operator=="=" then value=self:coerce(self:expr(stmt.value,ty),ty,stmt.value)
            else
                local op=BINARY[stmt.operator:sub(1,-2)];if not op then reject("operator","Unsupported store operator `"..stmt.operator.."`",stmt) end
                local currentValue=self.builder:read(self.body,ty,place);local current=self.builder:ref(currentValue,ty)
                local right=self:coerce(self:expr(stmt.value,ty),ty,stmt.value);value=self.builder:bin(op,current,right,ty)
            end
            self.builder:store(self.body,place,value)
        elseif kind=="CallStmt" then
            if stmt.call.kind~="Apply" then reject("call-required","A call statement needs a call expression",stmt.call) end
            self:call(stmt.call,nil,true)
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
            self.builder:emit(parentBody,located(I.If(test,L(arm(stmt.yes)),L(arm(stmt.no))),stmt))
        else reject("semantic-todo", "Source statement "..tostring(kind).." is not implemented",stmt) end
    end
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
    local signatures,globals,types,order={},{},{},{}
    for name,ty in pairs(options.types or {}) do types[name]=ty end
    for name,entry in pairs(options.imports or {}) do signatures[name]=entry end
    -- Type values are compile-time declarations. They never become Lua-executed runtime globals.
    for _,decl in ipairs(unit.ast.declarations) do
        if decl.kind=="ValueDecl" and #decl.def.binders==1 and #decl.def.values==1 and not decl.def.binders[1].annotation then
            local node=decl.def.values[1];local isType=node.kind=="SchemaExpr" or node.kind=="SignatureExpr" or (node.kind=="Apply" and node.callee.kind=="Reference" and ({ref=true,ptr=true,slice=true,array=true,oneof=true})[node.callee.name.text])
            if isType then local name=decl.def.binders[1].name.text;if types[name] then reject("duplicate-name","Type `"..name.."` is declared twice",decl) end;types[name]=typeExpr(node,types);decl._typeDeclaration=true end
        end
    end
    for _,decl in ipairs(unit.ast.declarations) do
        if decl.kind=="WordDecl" then
            local inputs,results=signature(decl.def,dynamic,types);local id=prefix..decl.def.name.text;signatures[decl.def.name.text]={inputs=inputs,results=results,target=id};order[#order+1]={def=decl.def,id=id}
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
    local functions,generated,lambdaState={},{},{count=0}
    for _,entry in ipairs(order) do
        local fn=Function.new(entry.def,entry.id,signatures,globals,types,dynamic,unit.profile and unit.profile.managed,generated,lambdaState):build();functions[#functions+1]=fn
    end
    for _,fn in ipairs(generated) do functions[#functions+1]=fn end
    local checked={} for _,fn in ipairs(options.dependencies or {}) do checked[#checked+1]=fn end
    for _,fn in ipairs(functions) do checked[#checked+1]=fn end
    Check.program(checked, nil, options.foreigns)
    unit.phase="typed-ir";unit.functions=functions;unit.signatures=signatures
    return unit
end

function M.exports(unit)
    local out={}
    for _,item in ipairs(unit.ast.export.functions) do
        if item.kind~="ExportName" then reject("semantic-todo","Computed export aliases are not implemented",item) end
        out[#out+1]=item.name.text
    end
    return out
end

return M

