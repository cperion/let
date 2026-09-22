-- Runtime record places and immutable snapshots. Value boundaries copy data.
local D = require("word.diagnostic")
local table = require("word.host").table
local Model = require("word.model")
local Borrow = require("word.borrow")
local M = {}

local function phase(engine)
    local context = engine:context()
    if context and context.mode == "normalize" then
        D.reject("runtime-in-normalization", "Runtime storage cannot be evaluated as static metadata")
    end
    return context
end
local function validate(engine, value)
    local p = Model.get(value)
    if not p or not Model.record(p.type) or
        (p.tag ~= "place" and p.tag ~= "symbol" and p.tag ~= "known") then
        D.reject("type", "Expected a record value")
    end
    if p.engine ~= engine then D.reject("foreign-session", "Record belongs to another session") end
    if p.tag == "known" then engine:check_static(value); return p end
    local context = phase(engine)
    local builder = p.tag == "place" and p.root.builder or p.builder
    if builder then
        if not context or context.builder ~= builder then D.reject("symbol-extent", "Record place escaped its trace") end
    elseif context and context.mode == "residualize" then
        D.reject("runtime-state", "Concrete host storage is not a residual global")
    end
    return p
end
local function wrap(engine, t, root, path)
    root.type = root.type or t
    return Model.wrap({ tag = "place", engine = engine, type = t, root = root, path = path or {} }, engine.place_mt)
end
local function at(p)
    if p.tag == "known" then return p.value end
    local data = p.root.data
    for _, name in ipairs(p.path) do data = data[name] end
    return data
end
local function clone(t, data)
    local def = Model.record(t)
    if not def then return data end -- Scalar values are immutable.
    local p = Model.get(data)
    if p then data = p.value end -- Nested immutable snapshots have typed wrappers.
    local out = {}
    for _, name in ipairs(def.runtime_order) do out[name] = clone(def.fields[name], data[name]) end
    return out
end
local function project(p, name)
    local def = Model.record(p.type)
    local t = def and def.fields[name]
    if not t then D.reject("unknown-field", "Unknown record field: " .. tostring(name)) end
    local path = { table.unpack(p.path or {}) }; path[#path + 1] = name
    return t, path
end

local function supply(t, values)
    if not Model.plain(values) then D.reject("keyed-supply", "Record supply requires a plain named table") end
    local def = Model.record(t)
    for name in pairs(values) do
        if not def.fields[name] then D.reject("unknown-field", "Unknown supplied field: " .. tostring(name)) end
        if def.bindings[name] then D.reject("static-field", "Static field is not an input: " .. name) end
    end
    return def
end

-- Contextual conversion, not a runtime constructor or a snapshot of live storage.
function M.constant(engine, t, values, depth)
    depth = depth or 1
    if depth > 32 then D.resource("static-aggregate-depth", "Static aggregate nesting exceeds 32") end
    if Model.word(values) then values = engine:normalize(values) end
    local p = Model.get(values)
    if p then
        if p.engine ~= engine then D.reject("foreign-session", "Static value belongs to another session") end
        if p.tag == "symbol" or p.tag == "place" or p.owner then D.reject("static-required", "Cannot freeze runtime storage") end
        if p.tag ~= "known" or p.type ~= t then D.reject("type", "Expected an immutable record of the declared schema") end
        if depth + p.record_depth - 1 > 32 then D.resource("static-aggregate-depth", "Static aggregate nesting exceeds 32") end
        engine:check_static(values)
        return values
    end
    local def = supply(t, values)
    local fields, height, nodes = {}, 1, 1
    for _, name in ipairs(def.runtime_order) do
        local ft = def.fields[name]
        if values[name] == nil and ft ~= engine.Unit then D.reject("missing-field", "Missing field: " .. name) end
        local value = engine:static_value(ft, values[name], depth + 1)
        fields[name] = value
        local vp = Model.get(value)
        height = math.max(height, 1 + (vp.record_depth or 0))
        nodes = nodes + (vp.record_nodes or 1)
        if nodes > 65536 then D.resource("static-aggregate-size", "Static aggregate exceeds 65536 expanded payload nodes") end
    end
    local result = engine:known(fields, t)
    Model.get(result).record_depth = height
    Model.get(result).record_nodes = nodes
    return result
end

function M.check(engine, t, value)
    if Model.plain(value) then return M.construct(engine, t, value) end
    local p = validate(engine, value)
    if p.type ~= t then D.reject("type", "Record has a different concrete schema") end
    return value
end
function M.reference(engine, value)
    local p = validate(engine, value)
    if p.tag == "symbol" then return p.id end
    if p.tag == "known" then
        local context = phase(engine)
        if not Model.runtime_type(p.type) then D.reject("runtime-type", "Static record has no runtime representation") end
        if not context or not context.builder then D.reject("expected-symbol", "Record materialization needs a builder") end
        local fields = {}
        for _, name in ipairs(Model.record(p.type).runtime_order) do
            if Model.record(p.type).fields[name] ~= engine.Unit then fields[name] = engine:reference(p.value[name]) end
        end
        return context.builder:construct(p.type, fields)
    end
    if not p.root.builder then D.reject("expected-symbol", "Cannot emit host storage") end
    return p.root.builder:load(p.type, p.root.id, p.path)
end
-- Receiver parameters are storage, not by-value record arguments.
function M.receiver(engine, t, builder)
    if not Model.runtime_type(t) then D.reject("runtime-type", "Receiver schema has no runtime storage representation; bind its metadata with :of") end
    return wrap(engine, t, {id = builder:receiver(t), builder = builder})
end
function M.captures(engine, t, builder)
    return wrap(engine, t, {id = builder:captures(t), builder = builder})
end
function M.address(engine, value)
    local p = validate(engine, value)
    if p.tag ~= "place" or not p.root.builder then D.reject("receiver-storage", "A mutable receiver needs residual storage") end
    return {type = p.type, root = p.root.id, path = {table.unpack(p.path)}}
end

-- Capture an actual root, not a by-value snapshot or an inferred parent. The
-- lexical field path stays in code metadata and is reapplied on invocation.
function M.capture_place(engine, value)
    local p = validate(engine, value)
    if p.tag ~= "place" or not p.root.builder then D.reject("receiver-storage", "Captured storage needs a live residual root") end
    local t = Model.borrow_type(engine, p.root.type)
    local id = p.root.builder:emit{op = "Address", type = t, root = p.root.id, path = {}, target_type = p.root.type}
    return engine:symbol(id, t, p.root.builder), {table.unpack(p.path)}
end
function M.restore_place(engine, reference, path)
    local p = Model.get(reference)
    local t = p and Model.borrow_target(p.type)
    if not t then D.bug("capture-reference", "Expected a typed borrowed capture reference") end
    engine:coerce(p.type, reference)
    local builder = engine:context().builder
    local id = builder:emit{op = "Deref", type = t, reference = engine:reference(reference), reference_type = p.type}
    local root = wrap(engine, t, {id = id, builder = builder})
    for _, name in ipairs(path) do root = M.read(engine, root, name) end
    return root
end

function M.copy(engine, value)
    local p = validate(engine, value)
    local context = phase(engine)
    if not (context and context.builder and Model.runtime_type(p.type) or
        not (context and context.builder) and Model.host_type(p.type)) then D.reject("runtime-type", "Record has no runtime representation") end
    if context and context.builder then
        local id = context.builder:local_record(p.type, M.reference(engine, value))
        return wrap(engine, p.type, { id = id, builder = context.builder })
    end
    return wrap(engine, p.type, { data = clone(p.type, at(p)) })
end

local function construct(engine, t, values, captures)
    local context = phase(engine)
    if captures and not (context and context.builder) then D.bug("capture-context", "Capture environments are residual-only") end
    Borrow.check(Borrow.value(engine, t)) -- Methods cannot hide mutable captures outside their record.
    t = engine:as_type(t)
    if not (context and context.builder and Model.runtime_type(t) or
        not (context and context.builder) and Model.host_type(t)) then D.reject("runtime-type", "Record contains static-only fields") end
    local def = supply(t, values)
    local fields = {}
    for _, name in ipairs(def.runtime_order) do
        local ft = def.fields[name]
        if values[name] == nil and ft ~= engine.Unit then D.reject("missing-field", "Missing field: " .. name) end
        local value = engine:coerce(ft, values[name])
        if not captures then Borrow.check(Borrow.value(engine, value)) end
        if context and context.builder then
            if ft ~= engine.Unit then fields[name] = engine:reference(value) end
        elseif Model.record(ft) then fields[name] = clone(ft, at(Model.get(value)))
        else fields[name] = value end
    end
    if context and context.builder then
        local initial = captures and context.builder:emit{op = "Capture", type = t, fields = fields} or
            context.builder:construct(t, fields)
        return wrap(engine, t, { id = context.builder:local_record(t, initial), builder = context.builder })
    end
    return wrap(engine, t, { data = fields })
end

function M.construct(engine, t, values) return construct(engine, t, values, false) end
function M.capture_environment(engine, t, values) return construct(engine, t, values, true) end

function M.read(engine, value, name)
    local p = validate(engine, value)
    local method = Model.record(p.type).methods[name]
    if method then
        if p.tag == "place" and #p.path > 0 and require("word.owner").needs_outer(p.type, p.root.type, p.path) then
            return engine:bind_method(method, p.root.type, wrap(engine, p.root.type, p.root), p.path)
        end
        return engine:bind_method(method, p.type, value)
    end
    local t, path = project(p, name)
    local bound = Model.record(p.type).bindings[name]
    if bound then return bound end
    if p.tag == "known" then return p.value[name] end
    if Model.record(t) then return wrap(engine, t, p.root, path) end
    if t == engine.Unit then return engine:known(nil, t) end
    if p.root.builder then return engine:symbol(p.root.builder:load(t, p.root.id, path), t, p.root.builder) end
    return at(p)[name] -- A scalar snapshot, not a delayed place read.
end
-- Resolve nearest lexical scope from the selected occurrence's actual root.
-- No inverse pointer arithmetic and no caller-frame lookup is involved.
function M.member_scope(engine, receiver, path, name)
    local scopes = {receiver}
    for _, field in ipairs(path or {}) do scopes[#scopes + 1] = M.read(engine, scopes[#scopes], field) end
    for i = #scopes, 1, -1 do
        local def = Model.record(Model.get(scopes[i]).type)
        if def.fields[name] or def.methods[name] then return scopes[i] end
    end
end

function M.write(engine, value, name, incoming)
    local p = validate(engine, value)
    if Model.record(p.type).methods[name] then D.reject("method-write", "Cannot replace a method: " .. name) end
    local t, path = project(p, name)
    if p.tag == "known" or Model.record(p.type).bindings[name] then
        D.reject("static-field", "Cannot write a static field: " .. name)
    end
    incoming = engine:coerce(t, incoming)
    Borrow.check(Borrow.value(engine, incoming))
    if p.root.builder then
        if t ~= engine.Unit then p.root.builder:store(t, p.root.id, path, engine:reference(incoming)) end
    else
        local snapshot = Model.record(t) and clone(t, at(Model.get(incoming))) or incoming
        at(p)[name] = snapshot
    end
end

function M.unbox(engine, value)
    local p = validate(engine, value)
    if p.tag == "symbol" or (p.root and p.root.builder) then D.reject("expected-known", "Cannot inspect residual storage as a concrete value") end
    local function visit(t, data)
        local def, payload = Model.record(t), Model.get(data)
        if not def then
            if payload.tag == "word" then return data end
            return payload.value
        end
        if payload then data = payload.value end
        local out = {}
        for _, name in ipairs(def.order) do
            out[name] = visit(def.fields[name], def.bindings[name] or data[name])
        end
        return out
    end
    return visit(p.type, at(p))
end

-- Direct embedding operations establish the same protected context as terminal execution.
for _, name in ipairs({ "construct", "copy", "read", "write", "unbox" }) do
    local action = M[name]
    M[name] = function(engine, ...)
        if engine:context() then return action(engine, ...) end
        local args = table.pack(...)
        return engine.scope:with({ context = { mode = "run" } }, function()
            return action(engine, table.unpack(args, 1, args.n))
        end)
    end
end

return M
