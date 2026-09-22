local D = require("word.diagnostic")
local math = require("word.host").math
local M = {}
local payload_key = {}

function M.wrap(payload, mt)
    -- Proxy-owned payloads let LuaJIT collect engine/word cycles. A weak-key
    -- registry whose values retain the engine would keep those cycles alive.
    local proxy = newproxy(true)
    local own = getmetatable(proxy)
    for key, value in pairs(mt) do own[key] = value end
    own[payload_key] = payload
    return proxy
end
function M.get(value)
    if type(value) ~= "userdata" then return nil end
    local mt = debug.getmetatable(value)
    return mt and rawget(mt, payload_key)
end
function M.word(value)
    local p = M.get(value)
    return p and p.tag == "word" and p or nil
end
function M.primitive(value)
    local p = M.word(value)
    -- A supplied constructor is a value-producing word, not the primitive type.
    return p and #p.static == 0 and p.definition.primitive or nil
end
function M.source(fn)
    local info = debug.getinfo(fn, "S")
    return info.short_src .. ":" .. info.linedefined
end
function M.plain(value) return type(value) == "table" and getmetatable(value) == nil end

function M.literal(type_word, value)
    local name = M.primitive(type_word)
    if name == "U32" then
        if type(value) ~= "number" then return false end
        local n = math.tointeger(value)
        return n ~= nil and n >= 0 and n <= 0xffffffff, n
    elseif name == "Bool" then
        return type(value) == "boolean", value
    elseif name == "Unit" then
        return value == nil, nil
    end
    return false
end

function M.key(value)
    local p = assert(M.get(value))
    if p.tag == "word" then
        if p.owner or p.occurrence_owner then D.reject("static-required", "Receiver selections are not static cache keys") end
        local parts = { "Word:" .. p.definition.id }
        for _, item in ipairs(p.static) do
            local key = M.key(item); parts[#parts + 1] = #key .. ":" .. key
        end
        return table.concat(parts, ":")
    end
    assert(p.tag == "known")
    local def = M.record(p.type)
    if def then
        local parts = {"Record", M.key(p.type)}
        for _, name in ipairs(def.runtime_order) do
            local key = M.key(p.value[name]); parts[#parts + 1] = #key .. ":" .. key
        end
        return table.concat(parts, ":")
    end
    local name = assert(M.primitive(p.type))
    if name == "Unit" then return "Unit" end
    return name .. ":" .. tostring(p.value)
end

function M.calling_requirement(w)
    local p = M.word(w)
    return p and not M.primitive(w) and p.definition.shape == "ordered" and
        (not p.definition.terminal or #p.static < #p.definition.inputs) or false
end

function M.callable(t)
    local p = M.word(t)
    return p and p.definition.callable
end
-- Compiler-only non-retaining storage references. No source Ref constructor or
-- allocation/lifetime policy is implied by this internal capture representation.
function M.borrow_target(t)
    local p = M.word(t)
    return p and p.definition.borrow_target
end
function M.borrow_type(engine, target)
    engine.borrow_types = engine.borrow_types or {}
    if not engine.borrow_types[target] then
        local def = engine:definition({}, nil)
        def.shape, def.borrow_target = "borrow", target
        engine.borrow_types[target] = engine:handle(def, {})
    end
    return engine.borrow_types[target]
end
function M.record(t)
    local p = M.word(t)
    return p and p.definition.shape == "keyed" and p.definition.sealed and p.definition or nil
end
function M.host_type(t)
    if M.calling_requirement(t) then return true end
    local def = M.record(t)
    if not def then return M.runtime_type(t) end
    for _, name in ipairs(def.runtime_order) do if not M.host_type(def.fields[name]) then return false end end
    return true
end
function M.runtime_type(t, visiting)
    if M.callable(t) then return true end
    local target = M.borrow_target(t)
    if target then return M.record(target) ~= nil and M.runtime_type(target, visiting) end
    local primitive = M.primitive(t)
    if primitive then return primitive == "U32" or primitive == "Bool" or primitive == "Unit" end
    local def = M.record(t)
    if not def then return false end
    visiting = visiting or {}
    if visiting[t] == "done" then return true end
    if visiting[t] then return false end
    visiting[t] = "visiting"
    for _, name in ipairs(def.runtime_order) do
        if not M.runtime_type(def.fields[name], visiting) then visiting[t] = nil; return false end
    end
    visiting[t] = "done" -- Visit shared type subgraphs once, without retaining a cache.
    return true
end

function M.immutable() D.reject("immutable", "Word definitions, specializations, and scalar values are immutable") end


return M
