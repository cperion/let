local D = require("word.diagnostic")
local Host = require("word.host")
local table, bit = Host.table, Host.bit
local Model = require("word.model")
local M = {}

local function operand(engine, value)
    value = engine:scalar(value)
    local p = Model.get(value)
    if p and p.engine ~= engine then D.reject("foreign-session", "Cannot combine values from different sessions") end
    return value, p
end

function M.binary(engine, op, a, b)
    local pa, pb
    a, pa = operand(engine, a); b, pb = operand(engine, b)
    local t = (pa and pa.type) or (pb and pb.type)
    if t ~= engine.U32 then D.reject("arithmetic-type", "Arithmetic requires U32 operands") end
    a, b = engine:coerce(t, a), engine:coerce(t, b)
    pa, pb = Model.get(a), Model.get(b)
    if (op == "Div" or op == "Mod") and pb.tag == "known" and pb.value == 0 then
        D.reject("division-zero", "U32 quotient and remainder require a nonzero divisor")
    end
    if pa.tag == "known" and pb.tag == "known" then
        local value
        if op == "Add" then value = pa.value + pb.value
        elseif op == "Sub" then value = pa.value - pb.value
        elseif op == "Mul" then value = Host.mul32(pa.value, pb.value)
        elseif op == "Div" then value = math.floor(pa.value / pb.value)
        elseif op == "Mod" then value = pa.value % pb.value
        elseif op == "And" then value = bit.band(pa.value, pb.value)
        elseif op == "Or" then value = bit.bor(pa.value, pb.value)
        elseif op == "Xor" then value = bit.bxor(pa.value, pb.value)
        elseif op == "Shl" then value = pb.value >= 32 and 0 or bit.lshift(pa.value, pb.value)
        elseif op == "Shr" then value = pb.value >= 32 and 0 or bit.rshift(pa.value, pb.value)
        elseif op == "Pow" then
            local base, exponent = pa.value, pb.value; value = 1
            while exponent ~= 0 do
                if exponent % 2 ~= 0 then value = Host.mul32(value, base) end
                exponent = math.floor(exponent / 2); base = Host.mul32(base, base)
            end
        else D.bug("operator", "Unknown arithmetic operation") end
        return engine:known(value % 4294967296, t)
    end
    local builder = engine:context().builder
    return engine:symbol(builder:binary(op, t, engine:reference(a), engine:reference(b)), t, builder)
end

function M.compare(engine, op, a, b)
    local pa, pb
    a, pa = operand(engine, a); b, pb = operand(engine, b)
    local t = (pa and pa.type) or (pb and pb.type)
    if not t or (op ~= "eq" and t ~= engine.U32) then
        D.reject("comparison-type", "Ordered comparison requires U32")
    end
    a, b = engine:coerce(t, a), engine:coerce(t, b)
    pa, pb = Model.get(a), Model.get(b)
    if t ~= engine.U32 and t ~= engine.Bool and t ~= engine.Unit then
        D.reject("comparison-type", "Equality requires scalar operands")
    end
    if pa.tag ~= "known" or pb.tag ~= "known" then
        local context = engine:context()
        if not context or not context.oracle then D.bug("missing-oracle", "Symbolic comparison outside a replay trace") end
        local predicate = context.builder:emit{op = "Compare", type = engine.Bool, operand_type = t,
            predicate = op, args = {engine:reference(a), engine:reference(b)}}
        return context.oracle:choose(predicate)
    end
    if op == "eq" then return pa.value == pb.value end
    if op == "lt" then return pa.value < pb.value end
    return pa.value <= pb.value
end

function M.metatables(engine)
    local operators = {
        __add = function(a, b) return M.binary(engine, "Add", a, b) end,
        __sub = function(a, b) return M.binary(engine, "Sub", a, b) end,
        __mul = function(a, b) return M.binary(engine, "Mul", a, b) end,
        __lt = function(a, b) return M.compare(engine, "lt", a, b) end,
        __le = function(a, b) return M.compare(engine, "le", a, b) end,
        __newindex = Model.immutable,
        __metatable = "immutable word value",
    }
    for name, op in pairs({__div = "Div", __idiv = "Div", __mod = "Mod", __pow = "Pow",
        __band = "And", __bor = "Or", __bxor = "Xor", __shl = "Shl", __shr = "Shr"}) do
        operators[name] = function(a, b) return M.binary(engine, op, a, b) end
    end
    operators.__unm = function(a) return M.binary(engine, "Sub", engine:known(0, engine.U32), a) end
    operators.__bnot = function(a) return M.binary(engine, "Xor", engine:known(0xffffffff, engine.U32), a) end
    -- Explicit adapters for operations this host cannot dispatch on proxies.
    local methods = {}
    for name, op in pairs({band = "And", bor = "Or", bxor = "Xor", shl = "Shl", shr = "Shr", idiv = "Div"}) do
        methods[name] = function(a, b) return M.binary(engine, op, a, b) end
    end
    methods.bnot = operators.__bnot
    methods.lt = function(a, b) return M.compare(engine, "lt", a, b) end
    methods.le = function(a, b) return M.compare(engine, "le", a, b) end
    methods.gt = function(a, b) return M.compare(engine, "lt", b, a) end
    methods.ge = function(a, b) return M.compare(engine, "le", b, a) end
    local word_mt, value_mt = {}, {}
    for key, value in pairs(operators) do word_mt[key] = value; value_mt[key] = value end
    word_mt.__call = function(w, ...) return engine:unpack_result(engine:invoke(w, table.pack(...))) end
    word_mt.__index = function(w, key)
        if key == "of" then return function(target, ...) return engine:specialize(target, table.pack(...)) end end
        if key == "eq" then return function(a, b) return M.compare(engine, "eq", a, b) end end
        if Model.word(w).definition.shape ~= "keyed" and methods[key] then return methods[key] end
        return engine:member(w, key)
    end
    word_mt.__tostring = function(w)
        local p = Model.get(w)
        if p.definition.shape == "keyed" then return "schema#" .. p.definition.id end
        return Model.primitive(w) or ("word#" .. p.definition.id .. "/" .. (#p.definition.inputs - #p.static))
    end
    value_mt.__call = function(v, ...)
        return engine:unpack_result(require("word.callable").invoke(engine, v, table.pack(...)))
    end
    value_mt.__index = function(v, key)
        local p = Model.get(v)
        if p.tag == "known" and Model.record(p.type) then return engine:read_field(v, key) end
        if key == "eq" then return function(a, b) return M.compare(engine, "eq", a, b) end end
        if methods[key] then return methods[key] end
        D.reject("unknown-member", "Unknown scalar member: " .. tostring(key))
    end
    value_mt.__newindex = function(v, key, value)
        if Model.record(Model.get(v).type) then return engine:write_field(v, key, value) end
        Model.immutable()
    end
    value_mt.__tostring = function(v)
        local p = Model.get(v)
        if Model.record(p.type) then return "record-value<" .. tostring(p.type) .. ">" end
        if Model.callable(p.type) then return "callable<" .. tostring(p.type) .. ">" end
        return Model.primitive(p.type) .. "(" .. (p.tag == "known" and tostring(p.value) or ("v" .. p.id)) .. ")"
    end
    local place_mt = {
        __index = function(p, name) return engine:read_field(p, name) end,
        __newindex = function(p, name, value) return engine:write_field(p, name, value) end,
        __tostring = function(p) return "record<" .. tostring(Model.get(p).type) .. ">" end,
        __metatable = "record place",
    }
    return word_mt, value_mt, place_mt
end

return M
