-- Source AST to verified ASDL IR. This pass resolves names and types but never executes user code.
local S = require("let.schema")
local IR = require("let.ir")
local Check = require("let.check")
local D = require("let.diag")

local M = {}
local I, L = S.Ir, S.ASDL.List

local BUILTIN_TYPES = {
    u8=S.u8, u16=S.u16, u32=S.u32, u64=S.u64,
    i32=S.i32, i64=S.i64, f64=S.f64, bool=S.bool, unit=S.unit, any=S.any,
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

local function typeExpr(node)
    if node and node.kind=="Reference" then
        local ty=BUILTIN_TYPES[node.name.text]
        if ty then return ty end
    end
    reject("type-required", "Expected a concrete scalar type", node)
end

local function literalType(node)
    local kind=node and node.kind
    if kind=="U32Literal" then return S.u32 end
    if kind=="U64Literal" then return S.u64 end
    if kind=="FloatLiteral" then return S.f64 end
    if kind=="BoolLiteral" then return S.bool end
    if kind=="UnitLiteral" then return S.unit end
end

local function resultTypes(spec)
    if not spec then return nil end
    local out={}
    if spec.kind=="Single" then out[1]=typeExpr(spec.type)
    else for _,node in ipairs(spec.types) do out[#out+1]=typeExpr(node) end end
    return out
end

local function signature(def,dynamic)
    if #def.keyed>0 then reject("semantic-todo", "Keyed requirements are not implemented by source-to-IR construction", def) end
    local inputs={}
    for _,param in ipairs(def.params) do
        if not param.annotation and not dynamic then reject("parameter-type", "Parameter `"..param.name.text.."` needs a type annotation", param) end
        inputs[#inputs+1]=S.inValue(param.annotation and typeExpr(param.annotation) or S.any)
    end
    local results=resultTypes(def.result)
    if not results then reject("result-type", "Word `"..def.name.text.."` needs an explicit result type", def) end
    return inputs,results
end

local Function = {}
Function.__index = Function

function Function.new(def, id, signatures, globals, dynamic)
    local inputs,results=signature(def,dynamic)
    local self=setmetatable({def=def,id=id,signatures=signatures,globals=globals,builder=IR.builder(),body={},scope={},inputs=inputs,results=results,params={}},Function)
    for index,param in ipairs(def.params) do
        local value=self.builder:valueId(); local ty=inputs[index].type
        self.params[#self.params+1]=located(I.ValueParam(index-1,value,ty),param)
        self.scope[param.name.text]={value=value,type=ty}
    end
    return self
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
    local indirect=binding and binding.callable and binding or nil
    if name=="is" then
        if #node.arguments~=2 then reject("arity","is expects a value and a type",node) end
        local operand=self:coerce(self:expr(node.arguments[1]),S.any,node.arguments[1]);local tested=typeExpr(node.arguments[2])
        return located(self.builder:isType(operand,tested),node)
    end
    local target=indirect and {inputs=indirect.type.visible.inputs,results=indirect.type.visible.results} or self.signatures[name]
    if not target then
        local conversion=BUILTIN_TYPES[name]
        if conversion and #node.arguments==1 then return self:coerce(self:expr(node.arguments[1]),conversion,node) end
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
    elseif kind=="Reference" then
        local binding=self.scope[node.name.text]
        if binding then expr=self.builder:ref(binding.value,binding.type)
        else
            local global=self.globals[node.name.text]
            if not global then reject("unknown-name", "Unknown value `"..node.name.text.."`", node) end
            expr=self:expr(global.node,global.type)
        end
    elseif kind=="Apply" then return self:call(node,expected)
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
    if #nodes==1 and nodes[1].kind=="Apply" and #self.results>1 then
        local values=self:call(nodes[1],nil,false,true)
        if #values~=#self.results then reject("return-arity", "Expected "..#self.results.." return values",owner) end
        for index,value in ipairs(values) do values[index]=self:coerce(value,self.results[index],nodes[1]) end
        self.builder:return_(self.body,values);located(self.body[#self.body],owner);return
    end
    if #nodes~=#self.results then reject("return-arity", "Expected "..#self.results.." return values",owner) end
    local values={} for index,node in ipairs(nodes) do values[index]=self:coerce(self:expr(node,self.results[index]),self.results[index],node) end
    self.builder:return_(self.body,values); located(self.body[#self.body],owner)
end

function Function:statements(statements)
    for _,stmt in ipairs(statements) do
        local kind=stmt.kind
        if kind=="ValueStmt" then
            if #stmt.def.binders~=#stmt.def.values then reject("binding-arity","A value declaration needs one value per binder",stmt) end
            local pending={}
            for index,valueNode in ipairs(stmt.def.values) do
                local binder=stmt.def.binders[index]; local wanted=binder.annotation and typeExpr(binder.annotation) or nil
                local target=valueNode.kind=="Reference" and self.signatures[valueNode.name.text] or nil
                if target then
                    if wanted then reject("type-mismatch","Callable aliases do not yet accept source signature annotations",binder) end
                    local ty=S.view(S.sig(target.inputs,target.results))
                    pending[index]={binder=binder,callableTarget=target.target or valueNode.name.text,type=ty}
                else pending[index]={binder=binder,expr=self:expr(valueNode,wanted)} end
            end
            for _,entry in ipairs(pending) do
                local name=entry.binder.name.text;if self.scope[name] then reject("duplicate-name","Local name `"..name.."` is declared twice",entry.binder) end
                local value=self.builder:valueId()
                if entry.callableTarget then
                    self.builder:emit(self.body,located(I.View(value,entry.type,entry.callableTarget,L{},nil),stmt))
                    self.scope[name]={value=value,type=entry.type,callable=true}
                else
                    self.builder:emit(self.body,located(I.Let(value,entry.expr.type,entry.expr),stmt));self.scope[name]={value=value,type=entry.expr.type}
                end
            end
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
    local signatures,globals,order={},{},{}
    for name,entry in pairs(options.imports or {}) do signatures[name]=entry end
    for _,decl in ipairs(unit.ast.declarations) do
        if decl.kind=="WordDecl" then
            local inputs,results=signature(decl.def,dynamic);local id=prefix..decl.def.name.text;signatures[decl.def.name.text]={inputs=inputs,results=results,target=id};order[#order+1]={def=decl.def,id=id}
        elseif decl.kind=="ValueDecl" then
            if #decl.def.binders~=#decl.def.values then reject("binding-arity","A top-level value declaration needs one value per binder",decl) end
            for index,binder in ipairs(decl.def.binders) do
                local node=decl.def.values[index];local inferred=literalType(node)
                if not inferred then reject("semantic-todo","Only literal top-level values are implemented; initializer computation must run through ABC",node) end
                local ty=binder.annotation and typeExpr(binder.annotation) or inferred
                if inferred~=ty and ty~=S.any and not (inferred:isInteger() and ty:isInteger()) then reject("type-mismatch","Top-level initializer does not match its annotation",node) end
                globals[binder.name.text]={node=node,type=ty}
            end
        elseif decl.kind=="UseDecl" then if not options.importsResolved then reject("import-input","A source string cannot resolve imports; compile a file",decl) end
        else reject("semantic-todo", "Top-level "..decl.kind.." is not implemented by source-to-IR construction",decl) end
    end
    local functions={} for _,entry in ipairs(order) do functions[#functions+1]=Function.new(entry.def,entry.id,signatures,globals,dynamic):build() end
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

