-- Runtime type descriptors (Ty) over ir.asdl. Structural interning is the ASDL context's job;
-- canonical ordering and validation are ours.
local ASDL = require("vendor.asdl")
local D = require("wordlet.diag")
local M = {}

M.ASDL = ASDL
M.List = ASDL.List
M.ctx = ASDL.NewContext()
M.ctx:Define(require("wordlet.schema.ir"))
M.Ty = M.ctx.Ty
M.Ir = M.ctx.Ir

local Ty = M.Ty
M.U32, M.Bool, M.Unit, M.Type = Ty.U32, Ty.Bool, Ty.Unit, Ty.Type

function M.list(items) return ASDL.List(items) end

function M.isU32(t) return t == Ty.U32 end
function M.isBool(t) return t == Ty.Bool end
function M.isUnit(t) return t == Ty.Unit end
function M.isType(t) return t == Ty.Type end
function M.isRecord(t) return type(t) == "table" and t.kind == "Record" end
function M.isSig(t) return type(t) == "table" and t.kind == "Sig" end

-- A record type is the runtime data layout: methods and static supplies live in the source
-- definition, never in Ty. Fields are canonicalised by name.
function M.record(fields)
    local names = {}
    for name in pairs(fields) do names[#names + 1] = name end
    table.sort(names)
    local list = {}
    for _, name in ipairs(names) do list[#list + 1] = Ty.Field(name, fields[name]) end
    local meaning = M.encodeFields(list)
    return Ty.Record(meaning, ASDL.List(list))
end

function M.encodeFields(fields)
    local parts = {}
    for _, field in ipairs(fields) do
        parts[#parts + 1] = field.name .. ":" .. M.encode(field.type)
    end
    return table.concat(parts, ",")
end

function M.fieldsOf(t)
    local map = {}
    for _, field in ipairs(t.fields) do map[field.name] = field.type end
    return map
end

function M.field(t, name)
    if not M.isRecord(t) then return nil end
    for _, field in ipairs(t.fields) do if field.name == name then return field.type end end
end

function M.fieldNames(t)
    local names = {}
    for _, field in ipairs(t.fields) do names[#names + 1] = field.name end
    return names
end

function M.sig(inputs, results)
    return Ty.Sig(ASDL.List(inputs), ASDL.List(results))
end
function M.inValue(t) return Ty.InValue(t) end
function M.inPlace(t) return Ty.InPlace(t) end

-- Canonical textual encoding of a Ty/Ir descriptor; used for instance keys and caches.
function M.encode(value, seen)
    local tv = type(value)
    if tv == "number" then return "n" .. string.format("%.17g", value) end
    if tv == "string" then return "s" .. #value .. ":" .. value end
    if tv == "boolean" then return value and "T" or "F" end
    if tv ~= "table" then return tv end
    if getmetatable(value) == ASDL.List then
        local parts = {}
        for _, item in ipairs(value) do parts[#parts + 1] = M.encode(item) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local mt = getmetatable(value)
    local name = value.kind or (mt and mt.__tostring and mt.__tostring(value)) or "?"
    local fields = mt and mt.__fields
    -- Fieldless variants (U32, Unit, Ir.Add, ...) carry only their constructor name.
    if not fields then return name end
    local parts = {}
    for _, field in ipairs(fields) do
        local item = value[field.name]
        parts[#parts + 1] = field.name .. "=" .. M.encode(item)
    end
    return name .. "(" .. table.concat(parts, ",") .. ")"
end

-- Validate that a type can appear as a runtime value type.
function M.runtime(t, visiting)
    if t == Ty.U32 or t == Ty.Bool or t == Ty.Unit then return true end
    if t == Ty.Type then return false end
    if M.isRecord(t) then
        visiting = visiting or {}
        if visiting[t] then return false end
        visiting[t] = true
        for _, field in ipairs(t.fields) do
            if not M.runtime(field.type, visiting) then visiting[t] = nil; return false end
        end
        visiting[t] = nil
        return true
    end
    return false
end

function M.checkRuntime(t, span)
    if not M.runtime(t) then
        D.reject("runtime-type", "A runtime value cannot have type " .. M.encode(t), span)
    end
    return t
end

return M
