-- Values: concrete (u32/bool/unit/type/record) or residual (an Ir.Expr with a Ty).
local S = require("wordlet.schema")
local D = require("wordlet.diag")
local M = {}

local V = {}
M.mt = V
V.__index = V

local function make(t) return setmetatable(t, V) end

function M.u32(n) return make{ tag = "u32", ty = S.U32, n = n } end
function M.bool(b) return make{ tag = "bool", ty = S.Bool, b = b } end
function M.unit() return make{ tag = "unit", ty = S.Unit } end
function M.type(ty) return make{ tag = "type", ty = S.Type, value = ty } end
function M.record(ty, fields) return make{ tag = "record", ty = ty, fields = fields } end
function M.ir(expr, ty) return make{ tag = "ir", ty = ty, expr = expr } end
function M.results(values) return make{ tag = "results", values = values } end
function M.callable(t, code) return make{ tag = "callable", ty = t, code = code } end
function M.word(def, args, span) return make{ tag = "word", def = def, args = args or {}, span = span } end

function M.is(v) return getmetatable(v) == V end
function M.tag(v) return M.is(v) and v.tag or nil end
function M.isConcrete(v) return M.is(v) and v.tag ~= "ir" end
function M.isIr(v) return M.is(v) and v.tag == "ir" end

function M.describe(v)
    if not M.is(v) then return tostring(v) end
    if v.tag == "type" then return "Type(" .. S.encode(v.value) .. ")" end
    if v.tag == "ir" then return "residual<" .. S.encode(v.ty) .. ">#" .. tostring(v.expr.kind) end
    if v.tag == "record" then return "record<" .. S.encode(v.ty) .. ">" end
    if v.tag == "results" then
        local parts = {}
        for index, item in ipairs(v.values) do parts[index] = M.describe(item) end
        return "(" .. table.concat(parts, ", ") .. ")"
    end
    return tostring(v.n ~= nil and v.n or v.b)
end

-- A concrete value is fully known if it contains no residual component.
function M.isKnown(v)
    if not M.is(v) then return false end
    if v.tag == "ir" then return false end
    if v.tag == "record" then
        for _, field in pairs(v.fields) do if not M.isKnown(field) then return false end end
    end
    return true
end

-- Canonical encoding of a frontend value for specialization keys. Returns nil for values that
-- cannot be part of a static key (residual values, places, borrowed callables).
function M.encode(v)
    if not M.is(v) then return S.encode(v) end
    local tag = v.tag
    if tag == "u32" then return "u32:" .. tostring(v.n) end
    if tag == "bool" then return "bool:" .. tostring(v.b) end
    if tag == "unit" then return "unit" end
    if tag == "type" then return "type:" .. S.encode(v.value) end
    if tag == "word" then
        local parts = { "word:" .. tostring(v.def.id) }
        for _, arg in ipairs(v.args) do
            local encoded = M.encode(arg)
            if not encoded then return nil end
            parts[#parts + 1] = encoded
        end
        return table.concat(parts, ",")
    end
    if tag == "record" then
        local parts = { "record:" .. S.encode(v.ty) }
        local names = {}
        for name in pairs(v.fields) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local encoded = M.encode(v.fields[name])
            if not encoded then return nil end
            parts[#parts + 1] = name .. "=" .. encoded
        end
        return table.concat(parts, ",")
    end
    if tag == "results" then
        local parts = {}
        for index, item in ipairs(v.values) do
            local encoded = M.encode(item)
            if not encoded then return nil end
            parts[index] = encoded
        end
        return "results:" .. table.concat(parts, ",")
    end
    return nil
end

return M
