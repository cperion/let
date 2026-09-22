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
local COMPOUND = {
    ["+="] = "+", ["-="] = "-", ["*="] = "*", ["/="] = "/", ["%="] = "%", ["^="] = "^",
    ["&="] = "&", ["|="] = "|", ["~="] = "~", ["<<="] = "<<", [">>="] = ">>",
}

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

local Ctx = {}
Ctx.__index = Ctx
function Ctx:arm(list)
    return setmetatable({ session = self.session, mode = self.mode, scope = self.scope,
        span = self.span, builder = self.builder, body = list }, Ctx)
end

function M.session(options)
    options = options or {}
    local limits = options.limits or {}
    return setmetatable({
        options = options, limits = limits,
        definitions = {}, instances = {}, order = {},
        nextDef = 0, nextFn = 0, steps = 0,
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
    local resolve = function(item) return self:resolveExportItem(item, top) end

    for _, item in ipairs(program.export.functions) do
        local value = resolve(item)
        if V.tag(value) ~= "word" then
            D.reject("function-required", "Exported function " .. item.name.text .. " is not a word", item.name.span)
        end
        exports.functions[#exports.functions + 1] = { name = item.name.text, word = value, span = item.span }
    end
    for _, item in ipairs(program.export.types) do
        local value = resolve(item)
        local ty = self:asType(value, item.name.span)
        if not ty or not S.isRecord(ty) then
            D.reject("type-required", "Exported type " .. item.name.text .. " is not a record type", item.name.span)
        end
        exports.types[#exports.types + 1] = { name = item.name.text, type = ty, span = item.span }
    end

    local compilation = { session = self, exports = exports, functions = {}, types = exports.types }
    for _, export in ipairs(exports.functions) do
        local instance = self:instanceFor(export.word.def, export.span, export.word.args)
        compilation.functions[#compilation.functions + 1] = { name = export.name, instance = instance, span = export.span }
    end
    return compilation
end

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
    return {
        id = self.nextDef, name = node.name.text, node = node, span = node.name.span,
        params = node.params, result = node.result, body = node.body,
        lexical = lexical, fields = fields,
    }
end

-- Lazy top-level value bindings ----------------------------------------------------------------

function Eval:demand(slot, span)
    if slot.kind ~= "value" or slot.value ~= nil then return slot end
    if slot.demanding then D.reject("initializer-cycle", "Eager value cycle through " .. slot.name, span) end
    slot.demanding = true
    local ctx = self:context("normalize", slot.scope, slot.decl.span)
    local ok, result = pcall(self.evalValueDef, self, ctx, slot.decl.def)
    slot.demanding = nil
    if not ok then error(result, 0) end
    slot.value = result
    return slot
end

-- Result adjustment ---------------------------------------------------------------------------

function Eval:first(value)
    if V.tag(value) == "results" then return value.values[1] or V.unit() end
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

-- Materialisation -------------------------------------------------------------------------------

-- A record value or object becomes an immutable Make of its fields.
function Eval:recordExpr(ctx, value)
    local ty = value.ty
    local fields = {}
    for index, field in ipairs(ty.fields) do
        fields[index] = self:fieldExpr(ctx, value, field.name)
    end
    return ctx.builder:make(ty, fields)
end

function Eval:fieldExpr(ctx, value, name)
    if V.tag(value) == "record" then return self:expression(ctx, value.fields[name]) end
    local ty = S.field(value.ty, name)
    local place = Ir.Project(value.place, Ir.Field(name))
    local read = ctx.builder:read(ctx.body, ty, place)
    return ctx.builder:ref(read, ty)
end

function Eval:expression(ctx, value)
    local tag = V.tag(value)
    if tag == "ir" then return value.expr end
    if tag == "u32" then return ctx.builder:u32(value.n) end
    if tag == "bool" then return ctx.builder:bool(value.b) end
    if tag == "record" or tag == "object" then return self:recordExpr(ctx, value) end
    D.reject("residual-value", "A " .. S.encode(value.ty or S.Unit) .. " value cannot cross into runtime storage",
        ctx.span)
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
    elseif kind == "SchemaExpr" then return self:evalSchema(ctx, expr)
    elseif kind == "RecordSupply" then return self:evalSupply(ctx, expr)
    elseif kind == "FieldSelect" then return self:evalFieldSelect(ctx, expr)
    end
    D.todo("expression", "Unsupported expression form: " .. tostring(kind), expr.span)
end

function Eval:evalReference(ctx, expr)
    local name = expr.name.text
    local slot = lookup(ctx.scope, name)
    if not slot then D.reject("unknown-name", "Unknown name: " .. name, expr.name.span) end
    if slot.kind == "value" then
        local demanded = self:demand(slot, expr.name.span)
        if demanded.value == nil then D.reject("value-required", name .. " has no value", expr.name.span) end
        if ctx.mode == "residual" and V.tag(demanded.value) == "record" then
            D.todo("module-mutable-capture",
                "Mutable module state cannot be captured into runtime code yet; create the record inside the function",
                expr.name.span)
        end
        return demanded.value
    elseif slot.kind == "word" then
        return V.word(slot.def, {}, expr.name.span)
    elseif slot.kind == "field" then
        return self:readFieldValue(ctx, slot, expr.name.span)
    elseif slot.kind == "concrete-field" then
        return slot.record.fields[slot.name] or V.unit()
    end
    D.bug("binding", "Unknown binding kind " .. tostring(slot.kind))
end

-- Reads an implicit receiver field (or a bound local field place).
function Eval:readFieldValue(ctx, slot, span)
    if slot.static then return slot.static end
    if ctx.mode ~= "residual" then
        D.reject("runtime-in-normalization", "Field " .. slot.name .. " is runtime storage", span)
    end
    local read = ctx.builder:read(ctx.body, slot.ty, slot.place)
    return V.ir(ctx.builder:ref(read, slot.ty), slot.ty)
end

function Eval:evalUnary(ctx, expr)
    local value = self:evalExpr(ctx, expr.operand)
    local op = expr.operator
    if op == "not" then
        self:requireType(value, S.Bool, expr.operand.span)
        if V.tag(value) == "bool" then return V.bool(not value.b) end
        return V.ir(ctx.builder:un("Not", self:expression(ctx, value), S.Bool), S.Bool)
    end
    self:requireType(value, S.U32, expr.operand.span)
    if V.tag(value) == "u32" then
        local U = require("wordletkit.u32")
        return V.u32(op == "-" and U.neg(value.n) or U.bnot(value.n))
    end
    return V.ir(ctx.builder:un(op == "-" and "Neg" or "BitNot", self:expression(ctx, value), S.U32), S.U32)
end

function Eval:evalBinary(ctx, expr)
    local op = expr.operator
    if op == "and" or op == "or" then return self:evalShortCircuit(ctx, expr) end
    local left = self:evalExpr(ctx, expr.left)
    local right = self:evalExpr(ctx, expr.right)
    return self:binaryOp(ctx, op, left, right, expr.left.span, expr.right.span, expr.span)
end

-- One implementation of every binary operator, shared by expressions and compound stores.
function Eval:binaryOp(ctx, op, left, right, leftSpan, rightSpan, span)
    leftSpan, rightSpan, span = leftSpan or ctx.span, rightSpan or ctx.span, span or ctx.span
    if COMPARE[op] then
        self:requireType(left, S.U32, leftSpan)
        self:requireType(right, S.U32, rightSpan)
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
        return V.ir(ctx.builder:bin(COMPARE[op], self:expression(ctx, left), self:expression(ctx, right), S.Bool),
            S.Bool)
    end
    local irOp = ARITH[op]
    if not irOp then D.bug("operator", "Unknown binary operator " .. tostring(op)) end
    self:requireType(left, S.U32, leftSpan)
    self:requireType(right, S.U32, rightSpan)
    if (op == "/" or op == "%") and V.tag(right) == "u32" and right.n == 0 then
        D.reject("division-zero", "Known zero divisor", rightSpan)
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
    local leftExpr, rightExpr = self:expression(ctx, left), self:expression(ctx, right)
    if (op == "/" or op == "%") and V.tag(right) ~= "u32" then
        builder:emit(ctx.body, Ir.Trap(builder:bin("Eq", rightExpr, builder:u32(0), S.Bool), "division-zero"))
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
    local test = self:expression(ctx, left)
    local yesList, noList = {}, {}
    local yesValue = self:evalExpr(ctx:arm(yesList), expr.right)
    self:requireType(yesValue, S.Bool, expr.right.span)
    local builder = ctx.builder
    local storage = builder:var(ctx.body, S.Bool, nil)
    local place = Ir.Local(storage)
    builder:store(yesList, place, self:expression(ctx, yesValue))
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
    local testExpr = self:expression(ctx, test)
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
    builder:store(yesList, place, self:expression(ctx, yesValue))
    builder:store(noList, place, self:expression(ctx, noValue))
    builder:emit(ctx.body, Ir.If(testExpr, S.list(yesList), S.list(noList)))
    return V.ir(builder:ref(builder:read(ctx.body, ty, place), ty), ty)
end

-- Schemas and records -------------------------------------------------------------------------

-- A schema literal: data fields, methods, and no bound fields yet.
function Eval:evalSchema(ctx, expr)
    return self:newSchema(ctx, expr, nil, nil, nil)
end

-- Builds a schema, or a specialised copy of `base` with extra static (readonly) fields.
function Eval:newSchema(ctx, expr, statics, readonly, base)
    self.nextDef = self.nextDef + 1
    local def = {
        id = self.nextDef, span = expr.span, node = expr,
        statics = statics or {}, readonly = readonly or {},
        fields = {}, fieldOrder = {}, methods = {},
    }
    if base then
        for name, ty in pairs(base.fields) do def.fields[name] = ty end
        for _, name in ipairs(base.fieldOrder) do def.fieldOrder[#def.fieldOrder + 1] = name end
        for name, method in pairs(base.methods) do def.methods[name] = method end
        def.type, def.fieldNames = base.type, base.fieldNames
        return V.schema(def)
    end
    for _, member in ipairs(expr.members) do
        if member.kind == "FieldMember" then
            local name = member.name.text
            local ty = self:typeOf(member.type, ctx.scope, member.span)
            if def.fields[name] or def.methods[name] then
                D.reject("duplicate", "Duplicate schema member " .. name, member.name.span)
            end
            def.fields[name] = ty
            def.fieldOrder[#def.fieldOrder + 1] = name
        else
            local name = member.def.name.text
            if def.fields[name] or def.methods[name] then
                D.reject("duplicate", "Duplicate schema member " .. name, member.def.name.span)
            end
            local method = self:define(member.def, ctx.scope, def)
            def.methods[name] = method
        end
    end
    local names = {}
    for name in pairs(def.fields) do names[#names + 1] = name end
    local fields = {}
    for _, name in ipairs(names) do fields[name] = def.fields[name] end
    def.type = S.record(fields)
    def.fieldNames = names
    return V.schema(def)
end

-- `Schema { field = value }`: either a partial (static) supply or a construction.
function Eval:evalSupply(ctx, expr)
    local base = self:evalExpr(ctx, expr.schema)
    if V.tag(base) ~= "schema" then
        D.reject("schema-required", "Keyed supply needs a schema on the left", expr.schema.span)
    end
    local def = base.def
    local supplied = {}
    for _, field in ipairs(expr.fields) do
        local name = field.name.text
        if not def.fields[name] then
            D.reject("unknown-member", "Schema has no field " .. name, field.name.span)
        end
        if supplied[name] ~= nil or def.statics[name] ~= nil then
            D.reject("duplicate", "Field " .. name .. " is supplied twice", field.name.span)
        end
        supplied[name] = self:evalExpr(ctx, field.value)
    end

    -- A field is still runtime if the base did not bind it statically.
    local missing = {}
    for _, name in ipairs(def.fieldOrder) do
        if supplied[name] == nil and def.statics[name] == nil then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        -- Partial supply: every supplied field must be static, and becomes readonly.
        local statics, readonly = {}, {}
        for name, value in pairs(def.statics) do statics[name], readonly[name] = value, true end
        for name, value in pairs(supplied) do
            if not V.isStatic(value) then
                D.reject("static-required",
                    "Partial schema supply needs a static value for field " .. name, expr.span)
            end
            statics[name], readonly[name] = value, true
        end
        return self:newSchema(ctx, def.node, statics, readonly, def)
    end

    -- Saturated construction: the instance owns mutable storage for every data field.
    local values = {}
    for name, value in pairs(def.statics) do values[name] = value end
    for name, value in pairs(supplied) do values[name] = value end
    for _, name in ipairs(def.fieldOrder) do
        if values[name] == nil then D.bug("schema-fields", "A data field was not supplied") end
    end
    local ty = def.type
    if ctx.mode ~= "residual" then
        -- Static evaluation builds a concrete record; it is not runtime storage.
        local fields = {}
        for _, name in ipairs(def.fieldNames) do fields[name] = values[name] end
        return V.record(ty, fields, def)
    end
    local exprs = {}
    for index, field in ipairs(ty.fields) do exprs[index] = self:expression(ctx, values[field.name]) end
    local storage = ctx.builder:var(ctx.body, ty, ctx.builder:make(ty, exprs))
    return V.object(ty, Ir.Local(storage), def)
end

function Eval:evalFieldSelect(ctx, expr)
    local base = self:evalExpr(ctx, expr.base)
    local name = expr.field.text
    local tag = V.tag(base)
    if tag == "object" then
        local def = base.schema
        if def.methods[name] then return V.method(def.methods[name], base) end
        if def.fields[name] then return self:readFieldValue(ctx, self:fieldSlot(def, base, name), expr.span) end
        D.reject("unknown-member", "Value has no member " .. name, expr.field.span)
    elseif tag == "record" then
        if base.schema and base.schema.methods[name] then
            return V.method(base.schema.methods[name], base)
        end
        if base.fields[name] ~= nil then return base.fields[name] end
        D.reject("unknown-member", "Record has no field " .. name, expr.field.span)
    elseif tag == "schema" then
        if base.def.methods[name] then return V.method(base.def.methods[name], nil) end
        D.reject("unknown-member", "Schema has no member " .. name, expr.field.span)
    elseif tag == "ir" and S.isRecord(base.ty) then
        local ty = S.field(base.ty, name)
        if not ty then D.reject("unknown-member", "Record has no field " .. name, expr.field.span) end
        if ctx.mode ~= "residual" then
            D.reject("runtime-in-normalization", "Cannot read a runtime record field here", expr.span)
        end
        return V.ir(ctx.builder:get(base.expr, name, ty), ty)
    end
    D.reject("member-required", "Cannot select from " .. S.encode(base.ty or S.Unit), expr.span)
end

function Eval:fieldSlot(def, object, name)
    return { kind = "field", name = name, ty = def.fields[name], place = Ir.Project(object.place, Ir.Field(name)),
        static = def.statics[name], readonly = def.readonly[name] and true or false }
end

-- Stores -------------------------------------------------------------------------------------

function Eval:execStore(ctx, stmt)
    local slot, place = self:storeTarget(ctx, stmt.target)
    if slot.readonly then
        D.reject("readonly-field", "Field " .. slot.name .. " was bound by static supply and cannot be assigned",
            stmt.target.span)
    end
    local operator = stmt.operator
    if operator == "=" then
        local value = self:evalExpr(ctx, stmt.value)
        self:requireType(value, slot.ty, stmt.value.span)
        return self:writeSlot(ctx, slot, place, value)
    end
    local binary = COMPOUND[operator]
    if not binary then D.bug("operator", "Unknown assignment operator " .. tostring(operator)) end
    -- The target is evaluated once, the old value read once, then the RHS runs.
    local old = self:readSlot(ctx, slot, place, stmt.target.span)
    local value = self:evalExpr(ctx, stmt.value)
    local combined = self:binaryOp(ctx, binary, old, value, stmt.target.span, stmt.value.span, stmt.span)
    return self:writeSlot(ctx, slot, place, combined)
end

-- Either a residual IR place or a concrete interpreter field.
function Eval:readSlot(ctx, slot, place, span)
    if slot.kind == "concrete-field" then return slot.record.fields[slot.name] or V.unit() end
    return self:readFieldValue(ctx, slot, span)
end

function Eval:writeSlot(ctx, slot, place, value)
    if slot.kind == "concrete-field" then
        slot.record.fields[slot.name] = value
        return
    end
    ctx.builder:store(ctx.body, place, self:expression(ctx, value))
end

-- Resolves a store target to a place, plus the slot describing it.
function Eval:storeTarget(ctx, target)
    if target.kind == "Reference" then
        local slot = lookup(ctx.scope, target.name.text)
        if not slot then D.reject("unknown-name", "Unknown name: " .. target.name.text, target.name.span) end
        if slot.kind == "field" then
            if ctx.mode ~= "residual" then
                D.reject("runtime-in-normalization", "Cannot store to runtime field " .. slot.name, target.span)
            end
            return slot, slot.place
        end
        if slot.kind == "concrete-field" then return slot, nil end
        D.reject("not-a-place", "Only record fields can be assigned", target.span)
    elseif target.kind == "FieldSelect" then
        local base = self:evalExpr(ctx, target.base)
        local name = target.field.text
        if V.tag(base) == "record" then
            local ty = S.field(base.ty, name)
            if not ty then D.reject("unknown-member", "Record has no field " .. name, target.field.span) end
            return { kind = "concrete-field", name = name, record = base, ty = ty }, nil
        end
        if V.tag(base) ~= "object" then
            D.reject("not-a-place", "Only a mutable record instance has assignable fields", target.span)
        end
        local def = base.schema
        if not def.fields[name] then
            D.reject("unknown-member", "Record has no field " .. name, target.field.span)
        end
        if ctx.mode ~= "residual" then
            D.reject("runtime-in-normalization", "Cannot store to runtime field " .. name, target.span)
        end
        return self:fieldSlot(def, base, name), Ir.Project(base.place, Ir.Field(name))
    end
    D.reject("not-a-place", "Only record fields can be assigned", target.span)
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
        elseif kind == "StoreStmt" then
            self:execStore(ctx, stmt)
        else
            D.todo("statement", "Unsupported statement form: " .. tostring(kind), stmt.span)
        end
    end
    return false
end

function Eval:materializeAll(ctx, values)
    local out = {}
    for index, value in ipairs(values) do out[index] = self:expression(ctx, value) end
    return out
end

function Eval:execIfStatement(ctx, stmt)
    local test = self:evalExpr(ctx, stmt.test)
    self:requireType(test, S.Bool, stmt.test.span)
    if V.tag(test) == "bool" then
        if test.b then return self:execBlock(ctx, stmt.yes) end
        return self:execBlock(ctx, stmt.no)
    end
    local testExpr = self:expression(ctx, test)
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
    local ty = self:typeOf(binder.annotation, ctx.scope, binder.span)
    self:requireType(value, ty, binder.span)
    return value
end

-- A type expression is a Type value or a schema (which denotes its record type).
function Eval:asType(value, span)
    if V.tag(value) == "type" then return value.value end
    if V.tag(value) == "schema" then return value.def.type end
    return nil
end

function Eval:typeOf(expr, sc, span)
    local value = self:evalExpr(self:context("normalize", sc, span), expr)
    local ty = self:asType(value, span)
    if not ty then D.reject("type-required", "Expected a type", expr.span) end
    return ty
end

function Eval:requirement(def, index, sc, span)
    local param = def.params[index]
    if not param.annotation then
        D.reject("type-required", "Parameter " .. param.name.text .. " needs a type annotation", param.span)
    end
    return self:typeOf(param.annotation, sc, param.span)
end

-- Application ---------------------------------------------------------------------------------

function Eval:evalApply(ctx, expr)
    local callee = self:evalExpr(ctx, expr.callee)
    local args = self:evalList(ctx, expr.arguments)
    local tag = V.tag(callee)
    if tag == "word" then return self:apply(ctx, callee, args, expr.span) end
    if tag == "method" then return self:applyMethod(ctx, callee, args, expr.span) end
    D.reject("callable-required", "Only words can be applied", expr.callee.span)
end

function Eval:apply(ctx, word, args, span)
    local def = word.def
    local bound = {}
    for _, value in ipairs(word.args) do bound[#bound + 1] = value end
    for _, value in ipairs(args) do bound[#bound + 1] = value end
    if #bound > #def.params then D.reject("arity", "Overapplication is not supported", span) end
    if #bound < #def.params then
        for index, value in ipairs(bound) do
            if not V.isStatic(value) then
                D.reject("static-required",
                    "Partial application needs a static value for parameter " .. def.params[index].name.text, span)
            end
        end
        return V.word(def, bound, span)
    end
    local allKnown, allStatic = true, true
    for _, value in ipairs(bound) do
        if not V.isKnown(value) then allKnown = false end
        if not V.isStatic(value) then allStatic = false end
    end
    if allKnown and (ctx.mode == "normalize" or allStatic) then
        return self:applyStatically(def, bound, span, nil)
    end
    if ctx.mode ~= "residual" then
        D.reject("runtime-in-normalization", "This call needs runtime storage or values", span)
    end
    return self:applyResidual(ctx, def, bound, span)
end

function Eval:applyMethod(ctx, method, args, span)
    local def, receiver = method.def, method.receiver
    local bound = {}
    for _, value in ipairs(method.args or {}) do bound[#bound + 1] = value end
    for _, value in ipairs(args) do bound[#bound + 1] = value end
    if #bound > #def.params then D.reject("arity", "Overapplication is not supported", span) end
    if #bound < #def.params then
        for index, value in ipairs(bound) do
            if not V.isStatic(value) then
                D.reject("static-required",
                    "Partial application needs a static value for parameter " .. def.params[index].name.text, span)
            end
        end
        return setmetatable({ tag = "method", def = def, receiver = receiver, args = bound }, V.mt)
    end
    if not receiver then
        D.reject("missing-receiver", "Bind the receiver before calling " .. def.name, span)
    end
    local allKnown = true
    for _, value in ipairs(bound) do if not V.isKnown(value) then allKnown = false end end
    if allKnown and V.tag(receiver) == "record" then
        return self:applyStatically(def, bound, span, receiver)
    end
    if ctx.mode ~= "residual" then
        D.reject("runtime-in-normalization", "This method call needs runtime storage", span)
    end
    return self:applyMethodResidual(ctx, def, bound, receiver, span)
end

-- Shared scope construction: parameters, and receiver fields for methods.
function Eval:parameterScope(def, values, receiver)
    local sc = scope(def.lexical)
    if receiver then
        local rdef = receiver.schema or receiver.def
        for _, name in ipairs(rdef.fieldNames) do
            if V.tag(receiver) == "record" then
                declare(sc, name, { kind = "concrete-field", name = name, record = receiver,
                    ty = rdef.fields[name], readonly = rdef.readonly[name] and true or false }, def.span)
            else
                declare(sc, name, self:fieldSlot(rdef, receiver, name), def.span)
            end
        end
    end
    for index, param in ipairs(def.params) do
        -- Check each requirement against the supplied value before binding the next parameter,
        -- since a later annotation may depend on an earlier parameter.
        local ty = self:requirement(def, index, sc, def.span)
        local value = self:copyArgument(values[index])
        if value then self:requireType(value, ty, param.span) end
        declare(sc, param.name.text, { kind = "value", name = param.name.text, value = value }, param.span)
    end
    return sc
end

-- Ordinary parameter binding copies record data; a local alias keeps its instance, an argument
-- does not. Field values are immutable, so a shallow copy of the field table is a value copy.
function Eval:copyArgument(value)
    if V.tag(value) ~= "record" then return value end
    local fields = {}
    for name, field in pairs(value.fields) do fields[name] = field end
    return V.record(value.ty, fields, value.schema)
end

function Eval:applyStatically(def, values, span, receiver)
    local sc = self:parameterScope(def, values, receiver)
    local result = self:execBody(self:context("normalize", sc, span), def.body, span)
    local declared = self:declaredResult(def, sc, span)
    if declared then
        if #declared ~= #result then
            D.reject("branch-result", "Word " .. def.name .. " returned " .. #result
                .. " values but declares " .. #declared, span)
        end
        for index, ty in ipairs(declared) do self:requireType(result[index], ty, span) end
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
    return self:emitCall(ctx, instance, values, span, nil)
end

function Eval:applyMethodResidual(ctx, def, values, receiver, span)
    local instance = self:instanceFor(def, span, values, receiver)
    if instance.status == "building" and not instance.results then
        D.reject("recursive-result", "Recursive method " .. def.name .. " needs an explicit result annotation", span)
    end
    return self:emitCall(ctx, instance, values, span, receiver)
end

-- Builds the argument list from the instance's input plan.
function Eval:emitCall(ctx, instance, values, span, receiver)
    local builder = ctx.builder
    local args = {}
    for _, input in ipairs(instance.inputPlan) do
        if input.kind == "place" then
            args[#args + 1] = Ir.BorrowArg(receiver.place)
        else
            args[#args + 1] = Ir.ValueArg(self:expression(ctx, values[input.position]))
        end
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

function Eval:instanceKey(def, values, receiver)
    local parts = { tostring(def.id) }
    if receiver then
        local rdef = receiver.schema
        local names = {}
        for name in pairs(rdef.statics) do names[#names + 1] = name end
        table.sort(names)
        parts[#parts + 1] = "recv"
        for _, name in ipairs(names) do
            local encoded = V.encode(rdef.statics[name])
            if not encoded then D.bug("instance-key", "A static receiver field has no encoding") end
            parts[#parts + 1] = name .. "=" .. encoded
        end
    end
    for _, value in ipairs(values) do
        if V.isStatic(value) then
            local encoded = V.encode(value)
            if not encoded then D.bug("instance-key", "A static argument has no encoding") end
            parts[#parts + 1] = S.encode(value.ty) .. "=" .. encoded
        else
            parts[#parts + 1] = "*"
        end
    end
    return table.concat(parts, "/")
end

function Eval:instanceFor(def, span, values, receiver)
    values = values or {}
    local key = self:instanceKey(def, values, receiver)
    local existing = self.instances[key]
    if existing then return existing end
    local count = 0
    for _ in pairs(self.instances) do count = count + 1 end
    if count >= (self.limits.keys or 1024) then D.resource("keys", "Residual instance budget exhausted", span) end
    return self:buildInstance(key, def, values, span, receiver)
end

function Eval:buildInstance(key, def, values, span, receiver)
    self.nextFn = self.nextFn + 1
    local instance = { key = key, def = def, target = "wordletfn_" .. self.nextFn,
        status = "building", args = values, inputPlan = {} }
    self.instances[key] = instance
    self.order[#self.order + 1] = instance

    local body = {}
    local builder = IR.builder({ id = instance.target })
    local sc = scope(def.lexical)
    local params, paramTypes, inputs = {}, {}, {}

    -- A method's receiver is borrowed storage, so it is input zero and a place parameter.
    if receiver then
        local rdef = receiver.schema
        local storage = builder:storageId()
        inputs[#inputs + 1] = S.inPlace(rdef.type)
        params[#params + 1] = Ir.PlaceParam(#inputs - 1, storage, rdef.type)
        instance.inputPlan[#instance.inputPlan + 1] = { kind = "place" }
        for _, name in ipairs(rdef.fieldNames) do
            if rdef.statics[name] then
                declare(sc, name, { kind = "value", name = name, value = rdef.statics[name] }, def.span)
            else
                declare(sc, name, { kind = "field", name = name, ty = rdef.fields[name],
                    place = Ir.Project(Ir.Local(storage), Ir.Field(name)) }, def.span)
            end
        end
    end

    for index, param in ipairs(def.params) do
        local ty = self:requirement(def, index, sc, span)
        S.checkRuntime(ty, param.span)
        local supplied = values[index]
        if supplied ~= nil and V.isStatic(supplied) then
            self:requireType(supplied, ty, param.span)
            declare(sc, param.name.text, { kind = "value", name = param.name.text, value = supplied }, param.span)
        else
            local value = builder:valueId()
            params[#params + 1] = Ir.ValueParam(#inputs, value, ty)
            inputs[#inputs + 1] = S.inValue(ty)
            paramTypes[#paramTypes + 1] = ty
            instance.inputPlan[#instance.inputPlan + 1] = { kind = "value", position = index }
            if S.isRecord(ty) then
                -- A by-value record parameter owns fresh local storage, so field writes and method
                -- calls do not touch the caller's instance.
                local storage = builder:storageId()
                builder:emit(body, Ir.Var(storage, ty, Ir.Ref(value, ty)))
                declare(sc, param.name.text, { kind = "value", name = param.name.text,
                    value = V.object(ty, Ir.Local(storage), { fields = S.fieldsOf(ty),
                        fieldNames = S.fieldNames(ty), statics = {}, readonly = {}, methods = {}, type = ty }) },
                    param.span)
            else
                declare(sc, param.name.text, { kind = "value", name = param.name.text,
                    value = V.ir(Ir.Ref(value, ty), ty) }, param.span)
            end
        end
    end

    instance.results = self:declaredResult(def, sc, span)
    local ctx = setmetatable({ session = self, mode = "residual", scope = sc, span = span,
        builder = builder, body = body, fn = { id = instance.target } }, Ctx)
    self:execBodyResidual(ctx, def.body, span)
    if not instance.results then instance.results = ctx.resultTypes end
    if not instance.results then
        D.reject("recursive-result", "Word " .. def.name .. " has no returning path", span)
    end
    instance.fn = Ir.Fn(instance.target, Ir.Body, receiver and 1 or 0, S.list(inputs),
        S.list(instance.results), S.list(params), S.list(body))
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

-- Body execution ------------------------------------------------------------------------------

function Eval:execBody(ctx, body, span)
    if body.kind == "Expression" then
        local value = self:evalExpr(ctx, body.value)
        return self:expand(value)
    end
    ctx.result = nil
    local returned = self:execBlock(ctx, body.statements)
    if not returned then D.reject("no-return", "Every reachable path must return a value", span) end
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
    if not returned then D.reject("no-return", "Every reachable path must return a value", span) end
end

return M
