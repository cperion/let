-- The evaluator: one walker for concrete, normalization and residual execution.
--
-- Modes: "normalize" has no builder at all, so a static attempt cannot leave partial IR behind;
-- "residual" emits statements into the current Ir.Fn. Both share every expression rule.
local D = require("wordlet.diag")
local S = require("wordlet.schema")
local IR = require("wordlet.ir")
local V = require("wordlet.value")

local M = {}
local Eval = {}
Eval.__index = Eval

local Ir = S.Ir

local ARITH = {
    ["+"] = "Add", ["-"] = "Sub", ["*"] = "Mul", ["/"] = "Div", ["%"] = "Rem", ["^"] = "Pow",
    ["<<"] = "Shl", [">>"] = "Shr", ["&"] = "BitAnd", ["|"] = "BitOr", ["~"] = "BitXor",
}
local COMPARE = { ["=="] = "Eq", ["!="] = "Ne", ["<"] = "Lt", ["<="] = "Le", [">"] = "Gt", [">="] = "Ge" }

-- Scopes --------------------------------------------------------------------------------------

local function scope(parent) return { parent = parent, names = {} } end

local function declare(sc, name, slot, span)
    if sc.names[name] then D.reject("duplicate", "Duplicate declaration of " .. name, span) end
    sc.names[name] = slot
    return slot
end

local function lookup(sc, name)
    local current = sc
    while current do
        local slot = current.names[name]
        if slot then return slot end
        current = current.parent
    end
end

-- Context: the statement list under construction plus the lexical scope.
local Ctx = {}
Ctx.__index = Ctx
function Ctx:arm(list)
    return setmetatable({ session = self.session, mode = self.mode, scope = self.scope,
        span = self.span, fn = self.fn, builder = self.builder, body = list }, Ctx)
end
function Ctx:withScope(sc)
    return setmetatable({ session = self.session, mode = self.mode, scope = sc,
        span = self.span, fn = self.fn, builder = self.builder, body = self.body }, Ctx)
end

-- Session -------------------------------------------------------------------------------------

function M.session(options)
    options = options or {}
    local limits = options.limits or {}
    return setmetatable({
        options = options,
        limits = limits,
        definitions = {},
        instances = {},
        order = {},
        nextDef = 0,
        nextFn = 0,
        steps = 0,
        maxSteps = limits.steps or 1000000,
    }, Eval)
end

function Eval:step(span)
    self.steps = self.steps + 1
    if self.steps > self.maxSteps then D.resource("steps", "Static evaluation budget exhausted", span) end
end

function Eval:context(mode, sc, span)
    return setmetatable({ session = self, mode = mode, scope = sc, span = span }, Ctx)
end

-- Top level -----------------------------------------------------------------------------------

function Eval:load(program)
    local top = scope(nil)
    self.top = top
    for _, decl in ipairs(program.declarations) do
        if decl.kind == "WordDecl" then
            local slot = declare(top, decl.def.name.text, { kind = "word", name = decl.def.name.text }, decl.span)
            slot.def = self:define(decl.def, top, nil)
        else
            local binder = decl.def.binders[1]
            declare(top, binder.name.text, { kind = "value", name = binder.name.text, decl = decl, scope = top }, decl.span)
        end
    end
    for _, name in ipairs({ "U32", "Bool", "Unit", "Type" }) do
        declare(top, name, { kind = "value", name = name, value = V.type(S[name]) })
    end
    return top
end

function Eval:compile(program)
    local top = self:load(program)

    local exports = { functions = {}, types = {} }
    local top2 = top
    local resolve = function(item) return self:resolveExportItem(item, top2) end

    for _, item in ipairs(program.export.functions) do
        local value = resolve(item)
        if V.tag(value) ~= "word" then
            D.reject("function-required", "Exported function " .. item.name.text .. " is not a word", item.name.span)
        end
        exports.functions[#exports.functions + 1] = { name = item.name.text, word = value, span = item.span }
    end
    for _, item in ipairs(program.export.types) do
        local value = resolve(item)
        if V.tag(value) ~= "type" then
            D.reject("type-required", "Exported type " .. item.name.text .. " is not a type", item.span)
        end
        exports.types[#exports.types + 1] = { name = item.name.text, type = value.value, span = item.span }
    end

    local compilation = { session = self, exports = exports, functions = {}, types = exports.types }
    for _, export in ipairs(exports.functions) do
        local instance = self:instanceFor(export.word.def, export.span, export.word.args)
        compilation.functions[#compilation.functions + 1] = { name = export.name, instance = instance, span = export.span }
    end
    return compilation
end

-- Resolve one export item to a frontend value: a name lookup or an alias expression.
function Eval:resolveExportItem(item, top)
    if item.kind == "ExportAlias" then
        return self:evalExpr(self:context("normalize", top, item.span), item.value)
    end
    local name = item.name.text
    local slot = lookup(top, name)
    if not slot then D.reject("unknown-name", "Unknown exported name: " .. name, item.name.span) end
    if slot.kind == "word" then return V.word(slot.def, {}, item.span) end
    return self:demand(slot, item.span).value
end

-- Find an exported function by its public name, including aliases.
function Eval:exportedValue(program, name, top)
    for _, item in ipairs(program.export.functions) do
        if item.name.text == name then return self:resolveExportItem(item, top) end
    end
    D.reject("unknown-name", "Unknown exported function: " .. tostring(name))
end

function Eval:exportedWord(slot, span, name)
    if slot.kind == "word" then return V.word(slot.def, {}, span) end
    local demanded = self:demand(slot, span)
    local value = demanded.value
    if V.tag(value) ~= "word" then
        D.reject("function-required", "Exported function " .. tostring(name) .. " is not a word", span)
    end
    return value
end

function Eval:define(node, lexical, fields)
    self.nextDef = self.nextDef + 1
    local def = {
        id = self.nextDef, name = node.name.text, node = node, span = node.name.span,
        params = node.params, result = node.result, body = node.body,
        lexical = lexical, fields = fields,
    }
    self.definitions[#self.definitions + 1] = def
    return def
end

-- Lazy top-level value bindings ----------------------------------------------------------------

function Eval:demand(slot, span)
    if slot.kind ~= "value" or slot.value ~= nil then return slot end
    if slot.demanding then
        D.reject("initializer-cycle", "Eager value cycle through " .. slot.name, span)
    end
    slot.demanding = true
    local ctx = self:context("normalize", slot.scope, slot.decl.span)
    local ok, result = pcall(self.evalValueDef, self, ctx, slot.decl.def)
    slot.demanding = nil
    if not ok then error(result, 0) end
    slot.value = result
    return slot
end

-- Expression helpers --------------------------------------------------------------------------

-- Source result adjustment: a non-final expression contributes one value, the final one expands.
function Eval:first(value)
    if V.tag(value) == "results" then
        return value.values[1] or V.unit()
    end
    return value
end

function Eval:expand(value)
    if V.tag(value) == "results" then return value.values end
    return { value }
end

function Eval:evalList(ctx, exprs)
    local values = {}
    for index, expr in ipairs(exprs) do
        local value = self:evalExpr(ctx, expr)
        if index < #exprs then
            values[#values + 1] = self:first(value)
        else
            for _, item in ipairs(self:expand(value)) do values[#values + 1] = item end
        end
    end
    return values
end

function Eval:expression(value, ctx)
    if V.tag(value) == "ir" then return value.expr end
    if value.ty == S.U32 then return ctx.builder:u32(value.n) end
    if value.ty == S.Bool then return ctx.builder:bool(value.b) end
    D.reject("residual-value", "A " .. S.encode(value.ty) .. " value cannot cross into runtime storage", ctx.span)
end

function Eval:requireType(value, ty, span)
    if value.ty ~= ty then
        D.reject("type-mismatch", "Expected " .. S.encode(ty) .. " but found " .. S.encode(value.ty), span)
    end
end

-- Expressions ---------------------------------------------------------------------------------

function Eval:evalExpr(ctx, expr)
    self:step(expr.span)
    local kind = expr.kind
    if kind == "U32Literal" then return V.u32(expr.value)
    elseif kind == "BoolLiteral" then return V.bool(expr.value)
    elseif kind == "Reference" then return self:evalReference(ctx, expr)
    elseif kind == "UnaryExpr" then return self:evalUnary(ctx, expr)
    elseif kind == "BinaryExpr" then return self:evalBinary(ctx, expr)
    elseif kind == "Condition" then return self:evalCondition(ctx, expr)
    elseif kind == "Apply" then return self:evalApply(ctx, expr)
    end
    D.todo("expression", "Unsupported expression form: " .. tostring(kind), expr.span)
end

function Eval:evalReference(ctx, expr)
    local name = expr.name.text
    local slot = lookup(ctx.scope, name)
    if not slot then D.reject("unknown-name", "Unknown name: " .. name, expr.name.span) end
    if slot.kind == "value" then
        local demanded = self:demand(slot, expr.name.span)
        if demanded.value == nil then
            D.reject("value-required", name .. " has no value", expr.name.span)
        end
        return demanded.value
    elseif slot.kind == "word" then
        return V.word(slot.def, {}, expr.name.span)
    end
    D.bug("binding", "Unknown binding kind " .. tostring(slot.kind))
end

function Eval:evalUnary(ctx, expr)
    local value = self:evalExpr(ctx, expr.operand)
    local op = expr.operator
    if op == "not" then
        self:requireType(value, S.Bool, expr.operand.span)
        if V.tag(value) == "bool" then return V.bool(not value.b) end
        return V.ir(ctx.builder:un("Not", self:expression(value, ctx), S.Bool), S.Bool)
    end
    self:requireType(value, S.U32, expr.operand.span)
    if V.tag(value) == "u32" then
        local U = require("wordletkit.u32")
        return V.u32(op == "-" and U.neg(value.n) or U.bnot(value.n))
    end
    return V.ir(ctx.builder:un(op == "-" and "Neg" or "BitNot", self:expression(value, ctx), S.U32), S.U32)
end

function Eval:evalBinary(ctx, expr)
    local op = expr.operator
    if op == "and" or op == "or" then return self:evalShortCircuit(ctx, expr) end
    local left = self:evalExpr(ctx, expr.left)
    local right = self:evalExpr(ctx, expr.right)
    if COMPARE[op] then
        self:requireType(left, S.U32, expr.left.span)
        self:requireType(right, S.U32, expr.right.span)
        if V.tag(left) == "u32" and V.tag(right) == "u32" then
            local a, b = left.n, right.n
            local result
            if op == "==" then result = a == b
            elseif op == "!=" then result = a ~= b
            elseif op == "<" then result = a < b
            elseif op == "<=" then result = a <= b
            elseif op == ">" then result = a > b
            else result = a >= b end
            return V.bool(result)
        end
        return V.ir(ctx.builder:bin(COMPARE[op], self:expression(left, ctx), self:expression(right, ctx), S.Bool), S.Bool)
    end
    local irOp = ARITH[op]
    if not irOp then D.bug("operator", "Unknown binary operator " .. tostring(op)) end
    self:requireType(left, S.U32, expr.left.span)
    self:requireType(right, S.U32, expr.right.span)
    if (op == "/" or op == "%") and V.tag(right) == "u32" and right.n == 0 then
        -- A statically known zero divisor is a source rejection regardless of the left operand.
        D.reject("division-zero", "Known zero divisor", expr.right.span)
    end
    if V.tag(left) == "u32" and V.tag(right) == "u32" then
        local U = require("wordletkit.u32")
        local x, y = left.n, right.n
        local result
        if op == "+" then result = U.add(x, y)
        elseif op == "-" then result = U.sub(x, y)
        elseif op == "*" then result = U.mul(x, y)
        elseif op == "/" then result = U.div(x, y)
        elseif op == "%" then result = U.mod(x, y)
        elseif op == "^" then result = U.pow(x, y)
        elseif op == "<<" then result = U.shl(x, y)
        elseif op == ">>" then result = U.shr(x, y)
        elseif op == "&" then result = U.band(x, y)
        elseif op == "|" then result = U.bor(x, y)
        else result = U.bxor(x, y) end
        return V.u32(result)
    end
    local builder = ctx.builder
    local leftExpr, rightExpr = self:expression(left, ctx), self:expression(right, ctx)
    if op == "/" or op == "%" then
        -- Only a genuinely dynamic divisor needs a guard; a known nonzero one is already safe.
        if V.tag(right) ~= "u32" then
            builder:emit(ctx.body, Ir.Trap(builder:bin("Eq", rightExpr, builder:u32(0), S.Bool), "division-zero"))
        end
    end
    return V.ir(builder:bin(irOp, leftExpr, rightExpr, S.U32), S.U32)
end

function Eval:evalShortCircuit(ctx, expr)
    local left = self:evalExpr(ctx, expr.left)
    self:requireType(left, S.Bool, expr.left.span)
    local isOr = expr.operator == "or"
    if V.tag(left) == "bool" then
        local short = isOr and left.b or (not isOr and not left.b)
        if short then return V.bool(isOr) end
        local right = self:evalExpr(ctx, expr.right)
        self:requireType(right, S.Bool, expr.right.span)
        return right
    end
    local test = self:expression(left, ctx)
    local yesList, noList = {}, {}
    local yesValue = self:evalExpr(ctx:arm(yesList), expr.right)
    self:requireType(yesValue, S.Bool, expr.right.span)
    local builder = ctx.builder
    local storage = builder:var(ctx.body, S.Bool, nil)
    local place = Ir.Local(storage)
    builder:store(yesList, place, self:expression(yesValue, ctx))
    builder:store(noList, place, builder:bool(isOr))
    builder:emit(ctx.body, Ir.If(test, S.list(yesList), S.list(noList)))
    return V.ir(builder:ref(builder:read(ctx.body, S.Bool, place), S.Bool), S.Bool)
end

function Eval:evalCondition(ctx, expr)
    local test = self:evalExpr(ctx, expr.test)
    self:requireType(test, S.Bool, expr.test.span)
    if V.tag(test) == "bool" then
        return test.b and self:evalExpr(ctx, expr.yes) or self:evalExpr(ctx, expr.no)
    end
    local builder = ctx.builder
    local testExpr = self:expression(test, ctx)
    local yesList, noList = {}, {}
    local yesValue = self:evalExpr(ctx:arm(yesList), expr.yes)
    local noValue = self:evalExpr(ctx:arm(noList), expr.no)
    if yesValue.ty ~= noValue.ty then
        D.reject("branch-result", "Conditional arms have different types: "
            .. S.encode(yesValue.ty) .. " and " .. S.encode(noValue.ty), expr.span)
    end
    local ty = yesValue.ty
    local storage = builder:var(ctx.body, ty, nil)
    local place = Ir.Local(storage)
    builder:store(yesList, place, self:expression(yesValue, ctx))
    builder:store(noList, place, self:expression(noValue, ctx))
    builder:emit(ctx.body, Ir.If(testExpr, S.list(yesList), S.list(noList)))
    return V.ir(builder:ref(builder:read(ctx.body, ty, place), ty), ty)
end

-- Bodies --------------------------------------------------------------------------------------

function Eval:execBlock(ctx, statements)
    for _, stmt in ipairs(statements) do
        self:step(stmt.span)
        local kind = stmt.kind
        if kind == "ValueStmt" then
            local values = self:expand(self:evalValueDef(ctx, stmt.def))
            for index, binder in ipairs(stmt.def.binders) do
                declare(ctx.scope, binder.name.text,
                    { kind = "value", name = binder.name.text, value = values[index] or V.unit() }, binder.span)
            end
        elseif kind == "WordStmt" then
            local def = self:define(stmt.def, ctx.scope, nil)
            declare(ctx.scope, stmt.def.name.text, { kind = "word", name = stmt.def.name.text, def = def }, stmt.def.name.span)
        elseif kind == "ReturnStmt" then
            local values = self:evalList(ctx, stmt.values)
            if ctx.mode == "residual" then
                ctx.builder:emit(ctx.body, Ir.Return(S.list(self:materializeAll(ctx, values))))
                ctx.resultTypes = {}
                for index, value in ipairs(values) do ctx.resultTypes[index] = value.ty end
            else
                ctx.result = values
            end
            return true
        elseif kind == "IfStmt" then
            if self:execIfStatement(ctx, stmt) then return true end
        elseif kind == "CallStmt" then
            self:evalApply(ctx, stmt.call)
        else
            D.todo("statement", "Unsupported statement form: " .. tostring(kind), stmt.span)
        end
    end
    return false
end

function Eval:materializeAll(ctx, values)
    local out = {}
    for index, value in ipairs(values) do out[index] = self:expression(value, ctx) end
    return out
end

function Eval:execIfStatement(ctx, stmt)
    local test = self:evalExpr(ctx, stmt.test)
    self:requireType(test, S.Bool, stmt.test.span)
    if V.tag(test) == "bool" then
        if test.b then return self:execBlock(ctx, stmt.yes) end
        return self:execBlock(ctx, stmt.no)
    end
    local testExpr = self:expression(test, ctx)
    local yesList, noList = {}, {}
    local yesReturned = self:execBlock(ctx:arm(yesList), stmt.yes)
    local noReturned = self:execBlock(ctx:arm(noList), stmt.no)
    ctx.builder:emit(ctx.body, Ir.If(testExpr, S.list(yesList), S.list(noList)))
    return yesReturned and noReturned
end

-- Value definitions and annotations -----------------------------------------------------------

function Eval:evalValueDef(ctx, def)
    local values = self:evalList(ctx, def.values)
    local bound = {}
    for index, binder in ipairs(def.binders) do
        bound[index] = self:checkAnnotation(ctx, binder, values[index] or V.unit())
    end
    if #bound == 1 then return bound[1] end
    return V.results(bound)
end

function Eval:checkAnnotation(ctx, binder, value)
    if not binder.annotation then return value end
    local annotation = self:evalExpr(self:context("normalize", ctx.scope, binder.span), binder.annotation)
    if V.tag(annotation) ~= "type" then
        D.reject("type-required", "A binding annotation must be a type", binder.annotation.span)
    end
    self:requireType(value, annotation.value, binder.span)
    return value
end

-- Application ---------------------------------------------------------------------------------

function Eval:requirement(def, index, sc, span)
    local param = def.params[index]
    if not param.annotation then
        D.reject("type-required", "Parameter " .. param.name.text .. " needs a type annotation", param.span)
    end
    local value = self:evalExpr(self:context("normalize", sc, param.span), param.annotation)
    if V.tag(value) ~= "type" then
        D.reject("type-required", "Parameter annotations must be types", param.annotation.span)
    end
    return value.value
end

function Eval:evalApply(ctx, expr)
    local callee = self:evalExpr(ctx, expr.callee)
    local args = self:evalList(ctx, expr.arguments)
    if V.tag(callee) ~= "word" then
        D.reject("callable-required", "Only words can be applied", expr.callee.span)
    end
    return self:apply(ctx, callee, args, expr.span)
end

function Eval:apply(ctx, word, args, span)
    local def = word.def
    local bound = {}
    for _, value in ipairs(word.args) do bound[#bound + 1] = value end
    for _, value in ipairs(args) do bound[#bound + 1] = value end
    if #bound > #def.params then D.reject("arity", "Overapplication is not supported", span) end
    if #bound < #def.params then
        for index, value in ipairs(bound) do
            if not V.isKnown(value) then
                D.reject("static-required",
                    "Partial application needs a static value for parameter " .. def.params[index].name.text, span)
            end
        end
        return V.word(def, bound, span)
    end
    local allKnown = true
    for _, value in ipairs(bound) do
        if not V.isKnown(value) then allKnown = false break end
    end
    if allKnown then return self:applyStatically(def, bound, span) end
    return self:applyResidual(ctx, def, bound, span)
end

function Eval:applyStatically(def, values, span)
    local sc = scope(def.lexical)
    for index, param in ipairs(def.params) do
        declare(sc, param.name.text, { kind = "value", name = param.name.text, value = values[index] }, param.span)
    end
    local result = self:execBody(self:context("normalize", sc, span), def.body, span)
    local declared = self:declaredResult(def, sc, span)
    if declared then
        if #declared ~= #result then
            D.reject("branch-result", "Word " .. def.name .. " returned " .. #result
                .. " values but declares " .. #declared, span)
        end
        for index, ty in ipairs(declared) do
            self:requireType(result[index], ty, span)
        end
    end
    if #result == 0 then return V.unit() end
    if #result == 1 then return result[1] end
    return V.results(result)
end

function Eval:applyResidual(ctx, def, values, span)
    local instance = self:instanceFor(def, span, values)
    if instance.status == "building" and not instance.results then
        D.reject("recursive-result", "Recursive word " .. def.name .. " needs an explicit result annotation", span)
    end
    return self:emitCall(ctx, instance, values, span)
end

function Eval:emitCall(ctx, instance, values, span)
    local builder = ctx.builder
    local args = {}
    for _, position in ipairs(instance.inputPositions) do
        args[#args + 1] = Ir.ValueArg(self:expression(values[position], ctx))
    end
    local results = {}
    for _ = 1, #instance.results do results[#results + 1] = builder:valueId() end
    builder:emit(ctx.body, Ir.Call(S.list(results), instance.target, S.list(args)))
    if #instance.results == 0 then return V.unit() end
    if #instance.results == 1 then
        return V.ir(builder:ref(results[1], instance.results[1]), instance.results[1])
    end
    local out = {}
    for index, ty in ipairs(instance.results) do
        out[index] = V.ir(builder:ref(results[index], ty), ty)
    end
    return V.results(out)
end

-- Instance construction ------------------------------------------------------------------------

function Eval:instanceKey(def, values)
    local parts = { tostring(def.id) }
    for _, value in ipairs(values) do
        if V.isKnown(value) then
            local encoded = V.encode(value)
            if not encoded then
                D.bug("instance-key", "A known argument has no canonical encoding")
            end
            parts[#parts + 1] = S.encode(value.ty) .. "=" .. encoded
        else
            parts[#parts + 1] = "*"
        end
    end
    return table.concat(parts, "/")
end

function Eval:instanceFor(def, span, values)
    values = values or {}
    local key = self:instanceKey(def, values)
    local existing = self.instances[key]
    if existing then return existing end
    local count = 0
    for _ in pairs(self.instances) do count = count + 1 end
    if count >= (self.limits.keys or 1024) then D.resource("keys", "Residual instance budget exhausted", span) end
    return self:buildInstance(key, def, values, span)
end

-- One body per static key. Parameters with a static value are bound directly and erased from the
-- ABI; the rest become runtime inputs in original order.
function Eval:buildInstance(key, def, values, span)
    self.nextFn = self.nextFn + 1
    local instance = { key = key, def = def, target = "wordletfn_" .. self.nextFn,
        status = "building", args = values, inputPositions = {} }
    self.instances[key] = instance
    self.order[#self.order + 1] = instance

    local sc = scope(def.lexical)
    local builder = IR.builder({ id = instance.target })
    local params, paramTypes, inputs = {}, {}, {}
    for index, param in ipairs(def.params) do
        local ty = self:requirement(def, index, sc, span)
        S.checkRuntime(ty, param.span)
        local supplied = values[index]
        if supplied ~= nil and V.isKnown(supplied) then
            self:requireType(supplied, ty, param.span)
            declare(sc, param.name.text, { kind = "value", name = param.name.text, value = supplied }, param.span)
        else
            -- A residual argument becomes an input here; the caller supplies it positionally.
            local value = builder:valueId()
            params[#params + 1] = Ir.ValueParam(#inputs, value, ty)
            inputs[#inputs + 1] = S.inValue(ty)
            paramTypes[#paramTypes + 1] = ty
            instance.inputPositions[#instance.inputPositions + 1] = index
            declare(sc, param.name.text, { kind = "value", name = param.name.text,
                value = V.ir(Ir.Ref(value, ty), ty) }, param.span)
        end
    end

    instance.results = self:declaredResult(def, sc, span)
    local body = {}
    local ctx = setmetatable({ session = self, mode = "residual", scope = sc, span = span,
        builder = builder, body = body, fn = { id = instance.target } }, Ctx)
    self:execBodyResidual(ctx, def.body, span)
    if not instance.results then instance.results = ctx.resultTypes end
    if not instance.results then
        D.reject("recursive-result", "Word " .. def.name .. " has no returning path", span)
    end
    instance.fn = Ir.Fn(instance.target, Ir.Body, 0, S.list(inputs), S.list(instance.results),
        S.list(params), S.list(body))
    instance.paramTypes = paramTypes
    instance.status = "done"
    return instance
end

function Eval:declaredResult(def, sc, span)
    local result = def.result
    if not result then return nil end
    sc = sc or def.lexical
    local types = {}
    if result.kind == "Single" then
        types[1] = self:typeOf(result.type, sc, span)
    else
        for index, item in ipairs(result.types) do types[index] = self:typeOf(item, sc, span) end
    end
    for _, ty in ipairs(types) do S.checkRuntime(ty, span) end
    return types
end

function Eval:typeOf(expr, sc, span)
    local value = self:evalExpr(self:context("normalize", sc, span), expr)
    if V.tag(value) ~= "type" then D.reject("type-required", "Expected a type", expr.span) end
    return value.value
end

-- Body execution ------------------------------------------------------------------------------

function Eval:execBody(ctx, body, span)
    if body.kind == "Expression" then
        local value = self:evalExpr(ctx, body.value)
        return self:expand(value)
    end
    ctx.result = nil
    local returned = self:execBlock(ctx, body.statements)
    if not returned then
        D.reject("no-return", "Every reachable path must return a value", span)
    end
    return ctx.result
end

function Eval:execBodyResidual(ctx, body, span)
    if body.kind == "Expression" then
        local value = self:evalExpr(ctx, body.value)
        local values = self:expand(value)
        ctx.builder:return_(ctx.body, self:materializeAll(ctx, values))
        ctx.resultTypes = {}
        for index, item in ipairs(values) do ctx.resultTypes[index] = item.ty end
        return
    end
    local returned = self:execBlock(ctx, body.statements)
    if not returned then
        D.reject("no-return", "Every reachable path must return a value", span)
    end
end

return M
