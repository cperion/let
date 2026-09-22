-- Immutable capture conversion. Code templates never retain a trace's values.
local Model = require("word.model")
local Data = require("word.data")
local Borrow = require("word.borrow")
local D = require("word.diagnostic")
local M = {}

local function clone(fn)
    return require("word.host").clone(fn)
end
local function static_capture(value, seen)
    local p = Model.get(value)
    if not p then return end
    seen = seen or {}; if seen[value] then return end; seen[value] = true
    if p.tag == "symbol" or p.tag == "place" or p.tag == "callable_known" or
        (p.receiver and Model.get(p.receiver).tag ~= "known") then
        D.reject("capture-type", "Static captured metadata cannot retain runtime values; capture a concrete immutable value instead")
    end
    if p.tag == "word" then
        local terminal = p.definition.terminal
        if terminal then
            local i = 1
            while true do
                local name, captured = debug.getupvalue(terminal, i)
                if not name then break end
                static_capture(captured, seen); i = i + 1
            end
        end
        for _, fields in ipairs({p.definition.fields or {}, p.definition.methods or {}, p.definition.inputs or {}, p.static}) do
            for _, child in pairs(fields) do static_capture(child, seen) end
        end
    elseif p.tag == "known" and Model.record(p.type) then
        static_capture(p.type, seen)
        for _, child in pairs(p.value) do static_capture(child, seen) end
    end
end
local function token(value)
    local p = Model.get(value)
    if p then return p.owner and p.engine:demand_key(value) or Model.key(value) end
    if type(value) == "number" then return string.format("number:%.17g", value) end
    return type(value) .. ":" .. tostring(value)
end

function M.lift(engine, word)
    local p, context = Model.word(word), engine:context()
    if not p or not p.definition.staged or p.definition.capture_fields or p.definition.lexical_fields then return word end
    local lexical = p.owner and p.definition.lexical_owner and p.receiver
    local borrowed_receiver = lexical and Model.get(p.receiver).tag ~= "known"
    if p.owner and not lexical then return word end
    if not lexical then Borrow.check(Borrow.value(engine, word)) end
    engine:check_word(word)
    local nodes, visited, unsupported = {}, {}, false
    local function visit(value)
        if visited[value] then return visited[value] end
        local wp = Model.word(value)
        local node = {word = value, payload = wp, captures = {}, sort = require("word.host").code(wp.definition.terminal)}
        visited[value] = node; nodes[#nodes + 1] = node; node.ordinal = #nodes
        local i = 1
        while true do
            local name, captured = debug.getupvalue(wp.definition.terminal, i)
            if not name then break end
            local cp = Model.get(captured)
            local slot = {value = captured}
            if lexical and cp and cp.tag == "word" and cp.definition.lexical_owner and
                not cp.definition.lexical_fields and cp.owner == p.owner and cp.receiver == p.receiver then
                slot.link = visit(captured)
            elseif lexical and cp and Borrow.value(engine, captured) then
                unsupported = true -- Preserve valid local inlining of other borrowed captures.
            elseif not lexical and cp and cp.tag == "word" and cp.definition.staged and cp.definition.terminal and not cp.owner then
                slot.link = visit(captured)
            elseif cp and (cp.tag == "symbol" or cp.tag == "callable_known" or
                (cp.tag == "known" and Model.primitive(cp.type) and cp.type ~= engine.Type) or
                (cp.tag == "word" and (cp.definition.capture_fields or
                    lexical and cp.definition.staged))) then
                if cp.tag == "word" or cp.tag == "callable_known" then
                    captured = require("word.callable").infer(engine, cp.code or captured); cp = Model.get(captured)
                end
                if Borrow.type(cp.type) or not Model.runtime_type(cp.type) then
                    D.reject("capture-type", "An immutable environment needs concrete, non-borrowed capture types")
                end
                slot.type, slot.value = cp.type, captured
            elseif lexical and cp and (cp.tag == "place" or cp.receiver and Model.get(cp.receiver).tag ~= "known") then
                unsupported = true -- Other borrowed storage still needs a separate binding ABI.
            end
            node.captures[i] = slot; i = i + 1
        end
        return node
    end
    local root = visit(word)
    if unsupported then return word end
    -- Only recursive code links share an environment. Acyclic captured functions
    -- are ordinary immutable values, whether already materialized or still known.
    local component, changed = {[root] = true}, true
    -- Lexical siblings already share one borrowed receiver. Their code links
    -- remain static even when acyclic; immutable capture values travel together.
    if lexical then for _, node in ipairs(nodes) do component[node] = true end end
    while changed do
        changed = false
        for _, node in ipairs(nodes) do
            if not component[node] then for _, slot in ipairs(node.captures) do
                if slot.link and component[slot.link] then component[node] = true; changed = true; break end
            end end
        end
    end
    local members = {}
    for _, node in ipairs(nodes) do if component[node] then
        members[#members + 1] = node
        for _, slot in ipairs(node.captures) do
            if slot.link and not component[slot.link] then
                slot.value = require("word.callable").infer(engine, slot.link.word)
                slot.type, slot.link = Model.get(slot.value).type, nil
            end
        end
    end end
    nodes = members
    table.sort(nodes, function(a, b)
        if a.sort == b.sort then return a.ordinal < b.ordinal end
        return a.sort < b.sort
    end)
    for i, node in ipairs(nodes) do node.index = i end
    local fields, order, values, parts = {}, {}, {}, {}
    local function key(s) parts[#parts + 1] = #s .. ":" .. s end
    key(lexical and "lexical" or "owned")
    if lexical then
        key(Model.key(p.owner))
        key(borrowed_receiver and "storage" or Model.key(p.receiver))
    end
    for _, node in ipairs(nodes) do
        if lexical then key(require("word.owner").path_key(node.payload.scope_path)) end
        key(node.sort); key(tostring(getfenv(node.payload.definition.terminal)))
        for _, t in ipairs(node.payload.definition.inputs) do static_capture(t); key(Model.key(t)) end
        key("static")
        for _, v in ipairs(node.payload.static) do static_capture(v); key(token(v)) end
        key("captures")
        for i, slot in ipairs(node.captures) do
            if slot.link then key("link:" .. slot.link.index)
            elseif slot.type then
                local name = "c" .. node.index .. "_" .. i
                slot.field = name; fields[name] = slot.type; order[#order + 1] = name; values[name] = slot.value
                key("field:" .. Model.key(slot.type))
            else static_capture(slot.value); key(token(slot.value)) end
        end
    end
    local graph = context.graph
    graph.capture_templates = graph.capture_templates or {}
    local identity = table.concat(parts, "/")
    local group = graph.capture_templates[identity]
    if not group then
        group = {type = engine:intern_schema(fields, order), words = {}, paths = {}}
        for i, node in ipairs(nodes) do
            local original = node.payload.definition
            local terminal = clone(original.terminal)
            local def = engine:definition(original.inputs, terminal)
            def.staged, def.source, def.capture_group = true, original.source, group
            local descriptors = {}
            if borrowed_receiver then
                def.lexical_fields, def.lexical_owner = descriptors, p.owner
                if #order > 0 then def.lexical_environment = group.type end
                group.paths[i] = node.payload.scope_path
            else
                def.capture_fields = descriptors
                if lexical then
                    def.lexical_static = {owner = p.owner, receiver = p.receiver, scope_path = node.payload.scope_path}
                end
            end
            for j, slot in ipairs(node.captures) do
                local descriptor = {field = slot.field, link = slot.link and slot.link.index}
                descriptors[j] = descriptor
                -- Only immutable static captures survive in the code template.
                local value = slot.value
                if slot.field or slot.link then value = nil end
                debug.setupvalue(terminal, j, value)
            end
            group.words[i] = engine:handle(def, node.payload.static)
        end
        graph.capture_templates[identity] = group
    end
    local environment = #order > 0 and Data.construct(engine, group.type, values) or nil
    if borrowed_receiver then return engine:bind_method(group.words[root.index], p.owner, p.receiver, p.scope_path, environment) end
    return engine:bind_method(group.words[root.index], group.type, environment)
end

-- Rebind a fresh Lua terminal, not the source closure or any previous trace's upvalues.
function M.instantiate(engine, word)
    local p = Model.word(word)
    local def = p.definition
    local receiver = def.lexical_fields and p.capture_env or p.receiver
    local terminal, expected = clone(def.terminal), {}
    for i, slot in ipairs(def.capture_fields or def.lexical_fields) do
        local _, value = debug.getupvalue(def.terminal, i)
        if slot.field then value = Data.read(engine, receiver, slot.field)
        elseif slot.link then
            if def.lexical_fields then
                value = engine:bind_method(def.capture_group.words[slot.link], p.owner, p.receiver,
                    def.capture_group.paths[slot.link], p.capture_env)
            else value = engine:bind_method(def.capture_group.words[slot.link], p.owner, receiver) end
        end
        debug.setupvalue(terminal, i, value); expected[i] = {value = value}
    end
    return terminal, function()
        for i, item in ipairs(expected) do
            local _, value = debug.getupvalue(terminal, i)
            if not rawequal(value, item.value) then
                D.reject("capture-changed", "An immutable closure cannot reassign a captured binding")
            end
        end
    end
end

-- Captures convertible to immutable environments are lifted above. Other
-- borrowed captures can still inline, but cannot be smuggled into an outlined
-- function as construction-trace symbols or hidden retaining record fields.
function M.check_lexical_outline(word)
    local p = Model.word(word)
    if not p.definition.lexical_owner or p.definition.lexical_fields then return end
    local i = 1
    while true do
        local name, value = debug.getupvalue(p.definition.terminal, i)
        if not name then return end
        local captured = Model.get(value)
        local self_link = captured and captured.definition == p.definition and captured.owner == p.owner
        if captured and not self_link and
            (captured.tag == "symbol" or captured.tag == "place" or captured.tag == "callable_known" or
            (captured.receiver and Model.get(captured.receiver).tag ~= "known")) then
            D.todo("staged-definitions", "Outlining additional borrowed captures needs a non-retaining capture ABI (capture: " .. name .. ")")
        end
        i = i + 1
    end
end

-- A lexical self-call uses this activation's receiver, not the construction trace's place.
function M.lexical(engine, word)
    local p = Model.word(word)
    local terminal, expected, i = clone(p.definition.terminal), {}, 1
    while true do
        local name, value = debug.getupvalue(p.definition.terminal, i)
        if not name then break end
        local captured = Model.word(value)
        if captured and captured.definition == p.definition and captured.owner == p.owner then
            value = engine:bind_method(captured.method, p.owner, p.receiver, p.scope_path)
        end
        debug.setupvalue(terminal, i, value); expected[i] = {value = value}; i = i + 1
    end
    return terminal, function()
        for j, item in ipairs(expected) do
            local _, value = debug.getupvalue(terminal, j)
            if not rawequal(value, item.value) then D.reject("capture-changed", "A lexical word cannot reassign a captured binding") end
        end
    end
end

M.static = static_capture
return M
