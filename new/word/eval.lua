local D = require("word.diagnostic")
local Host = require("word.host")
local table, math = Host.table, Host.math
local Model = require("word.model")
local Scope = require("word.scope")
local Ops = require("word.ops")
local IR = require("word.ir")
local Data = require("word.data")
local Trace = require("word.trace")
local Callable = require("word.callable")
local Owner = require("word.owner")
local E = {}
E.__index = E

function E.new(options)
    if options == nil then options = {} end
    if not Model.plain(options) then D.reject("options", "Expected a plain options table") end
    for key, value in pairs(options) do
        if key ~= "max_values" and key ~= "max_normalizations" and key ~= "max_paths" and key ~= "max_functions" then
            D.reject("options", "Unknown option: " .. tostring(key))
        end
        if math.type(value) ~= "integer" or value < 1 then D.reject("options", "Budgets must be positive integers") end
    end
    local self = setmetatable({ next_definition = 0, specializations = {},
        schemas = {}, max_normalizations = options.max_normalizations or 1000, max_paths = options.max_paths or 128,
        max_values = options.max_values or 10000, max_functions = options.max_functions or 128,
        scope = Scope.new() }, E)
    self.word_mt, self.value_mt, self.place_mt = Ops.metatables(self)
    for _, name in ipairs({ "U32", "Bool", "Unit", "Type" }) do
        local def = self:definition({}, nil)
        def.primitive = name
        self[name] = self:handle(def, {})
        -- Types double as constructors. Bootstrap their self-typed input only
        -- after the canonical type handle exists; Unit has no input.
        if name ~= "Unit" then def.inputs = {self[name]} end
        def.terminal = function(value) return value end
    end
    self.word = function(...) return self:define(table.pack(...)) end
    self.prelude = { word = self.word, U32 = self.U32, Bool = self.Bool, Unit = self.Unit, Type = self.Type }
    return self
end

function E:definition(inputs, terminal)
    self.next_definition = self.next_definition + 1
    return { id = self.next_definition, shape = "ordered", inputs = inputs, terminal = terminal,
        source = terminal and Model.source(terminal) or nil }
end
function E:handle(def, static)
    local key = self:key(def, static)
    local cache = self.specializations
    if def.staged then
        local context = self:context()
        context.staged_handles = context.staged_handles or {}
        cache = context.staged_handles
    elseif def.transient then
        def.handles = def.handles or {}
        cache = def.handles -- Owned by the runtime definition, not the session.
    end
    if not cache[key] then
        cache[key] = Model.wrap({tag = "word", engine = self, definition = def, static = static}, self.word_mt)
    end
    return cache[key]
end
function E:word_payload(w)
    local p = Model.word(w)
    if not p then D.reject("expected-word", "Expected a word") end
    if p.engine ~= self then D.reject("foreign-session", "Word belongs to a different session") end
    return p
end
function E:context()
    local frame = self.scope:current()
    return frame and frame.context
end
function E:staged_definition(def)
    local context = self:context()
    if not context or context.mode ~= "residualize" then
        def.transient = context and context.mode == "run" and self.scope:current().invoked ~= nil or nil
        return def
    end
    context.definition_index = (context.definition_index or 0) + 1
    local prototype = def.terminal and (Host.lua_terminal(def.terminal) and Host.code_identity(def.terminal) or tostring(def.terminal)) or def.shape
    local key = tostring(prototype) .. "/" .. context.definition_index .. "/" .. #context.oracle.events
    local sites = context.definition_sites
    if not sites[key] then sites[key] = def.id end
    def.id, def.staged = sites[key], true
    context.oracle:event{op = "Definition", identity = def.id, shape = def.shape}
    return def
end

function E:define(args)
    local context = self:context()
    if args.n == 1 and Model.plain(args[1]) then
        local fields, order = {}, {}
        for name, value in pairs(args[1]) do
            if type(name) ~= "string" or name == "" or name == "of" or name == "eq" then
                D.reject("schema-key", "Schema keys must be nonempty names other than of/eq")
            end
            local fp = self:word_payload(value) -- Retain a deferred requirement; do not execute it.
            if fp.owner or fp.occurrence_owner then D.reject("static-required", "Receiver selections cannot be schema requirements") end
            fields[name] = value; order[#order + 1] = name
        end
        table.sort(order)
        local def = self:definition({}, nil)
        def.shape = "keyed"; def.fields = fields; def.order = order
        return self:handle(self:staged_definition(def), {})
    end
    local terminal
    if args.n > 0 and type(args[args.n]) == "function" then
        terminal = args[args.n]; args.n = args.n - 1
    end
    local inputs = {}
    for i = 1, args.n do
        local input = self:word_payload(args[i])
        if input.owner or input.occurrence_owner then D.reject("static-required", "Receiver selections cannot be requirements") end
        inputs[i] = args[i]
    end
    local def = self:staged_definition(self:definition(inputs, terminal))
    local word = self:handle(def, {})
    local frame = self.scope:current()
    if terminal and frame and frame.invoked and frame.has_member and
        Host.nested_terminal(frame.terminal, terminal) then
        local parent = frame.lexical_binding or self:word_payload(frame.invoked)
        for name in pairs(Host.environment_names(terminal)) do
            if parent.owner and frame.has_member(name) then
                def.lexical_owner = parent.owner
                return self:bind_method(word, parent.owner, parent.receiver, parent.scope_path)
            end
        end
    end
    return word
end

function E:known(value, t)
    return Model.wrap({ tag = "known", engine = self, type = t, value = value }, self.value_mt)
end
function E:symbol(id, t, builder)
    return Model.wrap({ tag = "symbol", engine = self, type = t, id = id, builder = builder }, self.value_mt)
end
function E:key(def, static)
    local parts = { tostring(def.id) }
    for _, value in ipairs(static) do parts[#parts + 1] = Model.key(value) end
    return table.concat(parts, "/")
end


function E:demand_key(w)
    local p = self:word_payload(w)
    local key = self:key(p.definition, p.static)
    if p.owner then
        key = "receiver/" .. Model.key(p.owner) .. "/" .. Model.key(p.receiver) .. "/" .. Owner.path_key(p.scope_path) .. "/" .. key
    end
    return key
end

function E:normal_context()
    local context = self:context()
    if context and context.mode == "normalize" then return context end
    return { mode = "normalize", work = 0, graph = context and context.graph }
end

function E:stage(source, role, identity, action)
    if self.scope:find(role, identity) then
        D.reject(role == "static_word" and "normalization-cycle" or "type-cycle", "Cyclic static demand")
    end
    if self.scope:count("stage") >= 32 then D.resource("normalization-depth", "Static demand nesting exceeds 32") end
    local context = self:normal_context()
    return self.scope:with({ context = context, source = source, stage = true, [role] = identity }, function()
        context.work = context.work + 1
        if context.work > self.max_normalizations then D.resource("normalizations", "Static instance budget exhausted") end
        return action()
    end)
end

-- One specialization record owns a successful lazy call result. No busy/error state
-- is published: active builds exist only in scoped frames and disappear on unwind.
function E:static_call(w)
    local p = self:word_payload(w)
    if p.owner and (not p.receiver or Model.get(p.receiver).tag ~= "known") then
        D.reject("runtime-in-normalization", "Mutable or missing receiver storage is not static metadata")
    end
    self:check_word(w)
    local context = self:context()
    -- A cached outer result does not retain proof of new constraints on its nested calls.
    local checking = context and context.graph and next(context.graph.constraints) ~= nil
    local classifier = self.scope:find("classifying_word", w)
    local shadowed = classifier and not p.result_names
    if classifier and p.result_names then
        for name in pairs(p.result_names) do if classifier.classifying_fields[name] then shadowed = true; break end end
    end
    if p.result and not checking and not shadowed then
        self:check_static(p.result)
        return p.result
    end
    local identity = p.owner and self:demand_key(w) or w
    local result, names = self:stage(p.definition.source, "static_word", identity, function()
        return self:execute(w, { n = 0 }, self:context())
    end)
    p.result_names = names -- Successful immediate-terminal environment reads; no trace/storage references.
    p.result = result -- Publish only a completed result.
    return result
end

function E:normalize(value, lexical_names)
    return self.scope:with({ context = self:normal_context() }, function()
        local seen = {}
        while true do
            local p = Model.get(value)
            if not p then D.reject("static-required", "Normalization requires a word or a typed static value") end
            if p.engine ~= self then D.reject("foreign-session", "Value belongs to a different session") end
            if p.tag == "known" or p.tag == "results" then self:check_static(value); return value end
            if p.tag == "symbol" or p.tag == "place" then D.reject("static-required", "Cannot normalize runtime data") end
            if p.owner and not p.receiver then self:check_word(value); return value end
            if p.owner and Model.get(p.receiver).tag ~= "known" then
                D.reject("runtime-in-normalization", "Cannot normalize mutable receiver storage")
            end
            self:check_word(value)
            local def = p.definition
            if def.shape == "keyed" then return self:as_type(value, lexical_names) end
            if Model.primitive(value) or not def.terminal or #p.static < #def.inputs then return value end
            local key = self:demand_key(value)
            if seen[key] then D.reject("normalization-cycle", "Static word results form a demand cycle") end
            seen[key] = true
            value = self:static_call(value)
        end
    end)
end

-- Schema identity includes static knowledge, not just the surviving C layout.
function E:intern_schema(fields, order, bindings, methods, tuple_arity)
    bindings, methods = bindings or {}, methods or {}
    local parts, runtime_order = {}, {}
    local method_order = {}
    for name in pairs(methods) do method_order[#method_order + 1] = name end
    table.sort(method_order)
    for _, name in ipairs(method_order) do
        require("word.closure").static(methods[name])
        local key = Model.key(methods[name])
        parts[#parts + 1] = "method:" .. #name .. ":" .. name .. ":" .. #key .. ":" .. key
    end
    for _, name in ipairs(order) do
        require("word.closure").static(fields[name])
        if bindings[name] then require("word.closure").static(bindings[name]) end
        local tk = Model.key(fields[name])
        local part = #name .. ":" .. name .. ":" .. #tk .. ":" .. tk
        if bindings[name] then
            local vk = Model.key(bindings[name]); part = part .. "=" .. #vk .. ":" .. vk
        else runtime_order[#runtime_order + 1] = name end
        parts[#parts + 1] = part
    end
    local key = (tuple_arity and ("tuple:" .. tuple_arity .. ":") or "record:") .. table.concat(parts, "/")
    if not self.schemas[key] then
        local def = self:definition({}, nil)
        def.shape = "keyed"; def.sealed = true
        def.fields = fields; def.order = order; def.bindings = bindings; def.runtime_order = runtime_order
        def.methods = methods; def.tuple_arity = tuple_arity
        self.schemas[key] = self:handle(def, {})
    end
    return self.schemas[key]
end

function E:as_type(w, lexical_names)
    local p = Model.get(w)
    if p and p.engine ~= self then D.reject("foreign-session", "Type belongs to a different session") end
    if not p or p.tag ~= "word" then D.reject("type-required", "Expected a static type word") end
    self:check_word(w)
    local def = p.definition
    if Model.primitive(w) or Model.callable(w) or Model.borrow_target(w) then return w end
    if def.sealed then return Callable.record(self, w) end
    if def.shape == "keyed" then
        return self:stage(def.source, "type_word", w, function()
            local fields, order, methods = {}, {}, {}
            local child_names = Owner.child_names(lexical_names, def.fields)
            for _, name in ipairs(def.order) do
                local field = def.fields[name]
                local fp = self:word_payload(field)
                local method, meaning = false, field
                if not Model.primitive(field) and fp.definition.shape == "ordered" then
                    if not fp.definition.terminal then meaning = field
                    elseif #fp.static < #fp.definition.inputs then method = true
                    else
                        local need_receiver = D.control()
                        local ok, result = pcall(function()
                            return self.scope:with({context = self:normal_context(), source = fp.definition.source,
                                classifying_word = field, classifying_fields = child_names, need_receiver = need_receiver},
                                function() return self:normalize(field, child_names) end)
                        end)
                        if not ok then
                            if result ~= need_receiver and not (D.is(result) and result.id == "runtime-in-normalization") then error(result, 0) end
                            method = true
                        else
                            local rp = Model.word(result)
                            if rp and (Model.primitive(result) or rp.definition.shape == "keyed") then meaning = result
                            elseif rp and not rp.definition.terminal then meaning = result
                            else method = true end
                        end
                    end
                end
                if method then methods[name] = field
                else fields[name] = self:requirement_type(meaning, child_names); order[#order + 1] = name end
            end
            return self:intern_schema(fields, order, nil, methods)
        end)
    end
    if def.terminal and #p.static == #def.inputs then
        local result = self:normalize(w, lexical_names)
        if result == w and p.owner and not p.receiver then
            D.reject("missing-receiver", "Bind the receiver before demanding the method result as a type")
        end
        local rp = Model.word(result)
        if rp and (Model.primitive(result) or rp.definition.shape == "keyed") then return self:as_type(result, lexical_names) end
    end
    D.reject("type-required", "Word does not denote a concrete static type")
end

function E:requirement_type(w, lexical_names)
    local p = self:word_payload(w)
    if not Model.primitive(w) and p.definition.shape == "ordered" and
        p.definition.terminal and #p.static == #p.definition.inputs then w = self:normalize(w, lexical_names) end
    if Model.callable(w) then return w end
    if Model.calling_requirement(w) then
        self:check_word(w)
        local context = self:context()
        local result = context and context.graph and context.graph:declared(w)
        if result then return Callable.type(self, w, result) end
        return w
    end
    return self:as_type(w, lexical_names)
end

-- Positional requirements constrain remaining inputs, not the result or behavior.
function E:call_inputs(w)
    local p = self:word_payload(w)
    local inputs = {}
    for i = #p.static + 1, #p.definition.inputs do inputs[#inputs + 1] = p.definition.inputs[i] end
    return inputs
end

function E:same_requirement(a, b, seen)
    a, b = self:requirement_type(a), self:requirement_type(b)
    if a == b then return true end
    if not Model.calling_requirement(a) or not Model.calling_requirement(b) then return false end
    seen = seen or {}
    if seen[a] and seen[a][b] then return true end
    seen[a] = seen[a] or {}; seen[a][b] = true
    local aa, bb = self:call_inputs(a), self:call_inputs(b)
    if #aa ~= #bb then return false end
    for i = 1, #aa do if not self:same_requirement(aa[i], bb[i], seen) then return false end end
    return true
end

function E:coerce_callable(requirement, value)
    if not self:context() then
        return self.scope:with({ context = { mode = "run" } }, function()
            return self:coerce_callable(requirement, value)
        end)
    end
    if not Model.word(value) then D.reject("callable-required", "Supply an executable word, not a Lua function or scalar") end
    local p = self:word_payload(value)
    self:check_word(value)
    local expected = self:call_inputs(requirement)
    -- Match the same nonempty factory-result application supported by invoke.
    if #expected > 0 and not p.owner and p.definition.shape == "ordered" and not Model.primitive(value) and
        p.definition.terminal and #p.static == #p.definition.inputs then
        value = self:normalize(value)
        if not Model.word(value) then D.reject("callable-required", "Factory does not produce a callable word") end
        p = self:word_payload(value)
    end
    if p.definition.shape ~= "ordered" or not p.definition.terminal then
        D.reject("callable-required", "A positional signature needs an ordered implementation")
    end
    if p.owner and not p.receiver then D.reject("missing-receiver", "Select the method on an instance") end
    local actual = self:call_inputs(value)
    if #actual ~= #expected then D.reject("callable-shape", "Callable has a different remaining arity") end
    for i = 1, #actual do
        if not self:same_requirement(expected[i], actual[i]) then
            D.reject("callable-shape", "Callable input " .. i .. " has a different requirement")
        end
    end
    return value
end
function E:scalar(value)
    if Model.word(value) then value = self:normalize(value) end
    if Model.word(value) then D.reject("scalar-required", "Expected a scalar result, not a type or executable word") end
    return value
end
function E:member(w, name)
    local p = self:word_payload(w)
    if p.definition.shape ~= "keyed" then
        local result = self:normalize(w)
        if not Model.word(result) or result == w then D.reject("unknown-member", "Unknown word member: " .. tostring(name)) end
        w, p = result, self:word_payload(result)
    end
    local schema = self:as_type(w)
    local def = Model.word(schema).definition
    local root = p.occurrence_owner or schema
    local path = Owner.extend_path(p.occurrence_path, name)
    if def.methods and def.methods[name] then
        if p.occurrence_owner and Owner.needs_outer(schema, root, p.occurrence_path) then
            return self:bind_method(def.methods[name], root, nil, p.occurrence_path)
        end
        return self:bind_method(def.methods[name], schema)
    end
    local field = def.fields and def.fields[name]
    if not field then D.reject("unknown-member", "Unknown schema member: " .. tostring(name)) end
    if def.bindings and def.bindings[name] then
        local bound = def.bindings[name]
        if Model.record(field) and Owner.needs_outer(field, root, path) then
            return Data.occurrence(self, bound, root, nil, path)
        end
        return bound
    end
    if Model.record(field) and Owner.needs_outer(field, root, path) then
        return self:bind_occurrence(field, root, path)
    end
    return field
end

-- An unbound nested schema selection records only the declared occurrence.
-- It carries no receiver and cannot acquire one from a dynamic caller.
function E:bind_occurrence(schema, owner, scope_path)
    local p = self:word_payload(schema)
    return Model.wrap({tag = "word", engine = self, definition = p.definition, static = p.static,
        occurrence_owner = owner, occurrence_path = {table.unpack(scope_path)}}, self.word_mt)
end

-- A transient selection, never interned with static specialization metadata.
function E:bind_method(method, owner, receiver, scope_path, capture_env)
    -- Every data input is already supplied: bind immutable metadata, not invented
    -- runtime storage. Empty namespace instances have the same erased semantics.
    if #Model.record(owner).runtime_order == 0 then receiver = Data.constant(self, owner, {}) end
    local p = self:word_payload(method)
    return Model.wrap({ tag = "word", engine = self, definition = p.definition, static = p.static,
        method = method, owner = owner, receiver = receiver,
        scope_path = scope_path and {table.unpack(scope_path)} or nil, capture_env = capture_env }, self.word_mt)
end

function E:coerce(t, value)
    t = self:requirement_type(t)
    if Model.callable(t) then return Callable.coerce(self, t, value) end
    if Model.calling_requirement(t) then return self:coerce_callable(t, value) end
    if t == self.Type then return self:as_type(value) end
    if Model.record(t) then return Data.check(self, t, value) end
    value = self:scalar(value)
    local p = Model.get(value)
    if p then
        if p.engine ~= self then D.reject("foreign-session", "Value belongs to a different session") end
        if p.type ~= t then D.reject("type", "Expected " .. tostring(t)) end
        if p.tag == "symbol" then
            local context = self:context()
            if not context or context.builder ~= p.builder then D.reject("symbol-extent", "Symbol escaped its trace") end
        end
        return value
    end
    local ok, normalized = Model.literal(t, value)
    if not ok then D.reject("type", "Expected a representable " .. tostring(t) .. " literal") end
    return self:known(normalized, t)
end
function E:reference(value)
    local p = assert(Model.get(value))
    if p.tag == "callable_known" then return Callable.reference(self, value) end
    if Model.record(p.type) then return Data.reference(self, value) end
    if p.tag == "word" then D.reject("static-runtime", "A static word has no runtime scalar representation") end
    if p.tag == "symbol" then self:coerce(p.type, value); return p.id end
    return self:context().builder:constant(p.type, p.value)
end

function E:specialize_keyed(w, args)
    if args.n ~= 1 or not Model.plain(args[1]) then
        D.reject("keyed-supply", "Keyed :of requires one plain named table")
    end
    local supply = args[1]
    if next(supply) == nil then return w end
    return self.scope:with({ context = self:normal_context() }, function()
        local schema = self:as_type(w)
        local def = Model.record(schema)
        for name in pairs(supply) do
            if not def.fields[name] then D.reject("unknown-field", "Unknown static field: " .. tostring(name)) end
        end
        local bindings = {}
        for name, value in pairs(def.bindings) do bindings[name] = value end
        for _, name in ipairs(def.order) do
            if supply[name] ~= nil then
                local value, ft = supply[name], def.fields[name]
                value = self:static_value(ft, value)
                if bindings[name] and Model.key(bindings[name]) ~= Model.key(value) then
                    D.reject("static-conflict", "Conflicting static supply for field: " .. name)
                end
                bindings[name] = value
            end
        end
        return self:intern_schema(def.fields, def.order, bindings, def.methods)
    end)
end

function E:specialize(w, args)
    local p = self:word_payload(w)
    local def = p.definition
    if def.shape == "keyed" then return self:specialize_keyed(w, args) end
    if args.n == 0 then return w end
    local remaining = #def.inputs - #p.static
    if remaining == 0 and def.terminal and not Model.primitive(w) then
        local result = self:normalize(w)
        if not Model.word(result) then D.reject("arity", "A scalar result cannot accept static arguments") end
        return self:specialize(result, args)
    end
    if args.n > remaining then D.reject("arity", "Too many static arguments") end
    local static = { table.unpack(p.static) }
    for i = 1, args.n do
        local value = self:coerce(def.inputs[#p.static + i], args[i])
        if Model.get(value).tag == "callable_known" then value = Model.get(value).code end
        if Model.get(value).tag == "symbol" or Model.get(value).tag == "place" or Model.get(value).owner then
            D.reject("static-required", ":of requires immutable static values, not runtime storage")
        end
        require("word.closure").static(value)
        static[#static + 1] = value
    end
    local specialized = self:handle(def, static)
    if p.owner then return self:bind_method(specialized, p.owner, p.receiver, p.scope_path, p.capture_env) end
    return specialized
end

-- Static aggregate literals are converted against an already resolved field type.
function E:static_value(t, value, depth)
    local p = Model.get(value)
    if p and p.engine ~= self then D.reject("foreign-session", "Static value belongs to another session") end
    if p and (p.tag == "symbol" or p.tag == "place" or p.owner or
        p.occurrence_receiver and Model.get(p.occurrence_receiver).tag ~= "known") then
        D.reject("static-required", "Static supply requires immutable values, not runtime storage")
    end
    if Model.record(t) then return Data.constant(self, t, value, depth) end
    return self:coerce(t, value)
end

function E:check_static(value, seen)
    local p = Model.get(value)
    if p and p.tag == "callable_known" then return self:check_word(p.code, seen) end
    if not p then return end
    if p.tag == "results" then
        for _, item in ipairs(p.values) do
            local payload = Model.get(item)
            if payload.tag == "symbol" or payload.tag == "place" then D.reject("static-required", "Runtime result cannot be normalized") end
            self:check_static(item, seen)
        end
        return
    end
    if p.tag == "word" then return self:check_word(value, seen) end
    local def = p.tag == "known" and Model.record(p.type)
    if not def then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    self:check_word(p.type, seen)
    for _, name in ipairs(def.runtime_order) do self:check_static(p.value[name], seen) end
end

function E:check_word(w, seen)
    local p = self:word_payload(w)
    seen = seen or {}
    if seen[w] then return end
    seen[w] = true
    self:captures(p.definition, seen, p)
    for _, t in ipairs(p.definition.inputs) do self:check_word(t, seen) end
    for _, t in pairs(p.definition.fields or {}) do self:check_word(t, seen) end
    for _, t in pairs(p.definition.methods or {}) do self:check_word(t, seen) end
    if p.owner then self:check_word(p.owner, seen) end
    if p.occurrence_owner then self:check_word(p.occurrence_owner, seen) end
    if p.definition.lexical_static then
        self:check_word(p.definition.lexical_static.owner, seen)
        self:check_static(p.definition.lexical_static.receiver, seen)
    end
    if p.receiver and Model.get(p.receiver).tag == "known" then self:check_static(p.receiver, seen) end
    for _, v in ipairs(p.static) do self:check_static(v, seen) end
    for _, v in pairs(p.definition.bindings or {}) do self:check_static(v, seen) end
end

-- Freezing remains narrow, but covers requirements and normalized result closures too.
function E:captures(def, seen, occurrence)
    if not def.terminal then return end
    seen = seen or {}
    if not Host.lua_terminal(def.terminal) then D.todo("host-captures", "C terminals require explicit registration") end
    if def.uses_environment == nil then def.uses_environment = Host.uses_environment(def.terminal) end
    if def.uses_environment then
        local env = getfenv(def.terminal)
        if not self.scope.environments[env] then D.todo("host-captures", "Load terminals with global accesses through the session loader") end
        if def.environment and def.environment ~= env then D.reject("capture-changed", "Frozen function environment changed") end
        def.environment = env
    end
    if seen[def] then return end
    seen[def] = true
    local snapshot, i = {}, 1
    while true do
        local name, value = debug.getupvalue(def.terminal, i)
        if not name then break end
        local p, kind = Model.get(value), type(value)
        if p then
            if p.engine ~= self then D.reject("foreign-session", "Captured value belongs to another session") end
            local lexical_link = def.lexical_owner and p.definition and
                p.definition.lexical_owner == def.lexical_owner and occurrence and
                p.owner == occurrence.owner and p.receiver == occurrence.receiver
            if not lexical_link and (p.tag == "symbol" or p.tag == "place" or
                (p.receiver and Model.get(p.receiver).tag ~= "known") or
                (p.occurrence_receiver and Model.get(p.occurrence_receiver).tag ~= "known")) then
                if not def.staged and not def.transient then D.todo("host-captures", "Dynamic captured value/storage/receiver") end
                local captured = p.receiver and Model.get(p.receiver) or
                    p.occurrence_receiver and Model.get(p.occurrence_receiver) or p
                local builder = captured.root and captured.root.builder or captured.builder
                if (def.staged and not builder) or (builder and (not self:context() or builder ~= self:context().builder)) then
                    D.reject("symbol-extent", "Staged capture escaped its construction trace")
                end
                def.dynamic_captures = true
            end
            self:check_static(value, seen)
        elseif value == self.word then
            -- A local alias of the registered constructor is as static as _ENV.word.
        elseif kind ~= "nil" and kind ~= "boolean" and kind ~= "number" and kind ~= "string" then
            D.todo("host-captures", "Unsupported upvalue: " .. name .. " (" .. kind .. ")")
        end
        if kind == "number" and value ~= value then D.reject("capture", "NaN is not a supported static capture") end
        snapshot[i] = { name = name, value = value }; i = i + 1
    end
    if def.captures then
        for index, capture in ipairs(snapshot) do
            if capture.name ~= def.captures[index].name or not rawequal(capture.value, def.captures[index].value) then
                D.reject("capture-changed", "Frozen Lua upvalue changed: " .. capture.name)
            end
        end
    else def.captures = snapshot end
end

function E:result(results)
    if results.n > 1 then
        local values = {}
        for i = 1, results.n do values[i] = self:result({n = 1, [1] = results[i]}) end
        return Model.wrap({tag = "results", engine = self, values = values}, {__metatable = "word results", __newindex = Model.immutable})
    end
    local value = results[1]
    local p = Model.get(value)
    if p then
        if p.tag == "word" then
            local Borrow = require("word.borrow")
            Borrow.check(Borrow.value(self, value))
            self:check_word(value); return value
        end
        if Model.record(p.type) then
            value = self:coerce(p.type, value)
            if p.tag == "known" and self:context().mode == "normalize" then return Data.detach(self, value) end
            return Data.copy(self, value)
        end
        return self:coerce(p.type, value)
    end
    if value == nil then return self:known(nil, self.Unit) end
    if type(value) == "boolean" then return self:known(value, self.Bool) end
    if type(value) == "number" then return self:coerce(self.U32, value) end
    D.reject("result-type", "Unsupported terminal result: " .. type(value))
end

-- Match the current entry's erased static prefix before using its recursive ABI.
-- Different instances still inline until they encounter an unsupported cycle.
function E:recursive_args(w, args, entry)
    local p, ep = self:word_payload(w), self:word_payload(entry.word)
    if p.owner ~= ep.owner or p.definition ~= ep.definition or #p.static > #ep.static or
        Owner.path_key(p.scope_path) ~= Owner.path_key(ep.scope_path) then return nil end
    if p.owner then
        local actual, expected = Model.get(p.receiver), Model.get(ep.receiver)
        if expected and expected.tag == "known" then
            if not actual or actual.tag ~= "known" or Model.key(p.receiver) ~= Model.key(ep.receiver) then return nil end
        elseif actual and actual.tag == "known" then return nil end
    end
    -- Method selections are transient; their underlying supplied handles are interned.
    if #p.static == #ep.static and (p.method or w) ~= (ep.method or entry.word) then return nil end
    local function supplied(i)
        if i <= #p.static then return p.static[i] end
        return args[i - #p.static]
    end
    for i, expected in ipairs(ep.static) do
        local value = supplied(i)
        local vp = Model.get(value)
        if Model.plain(value) or (vp and (vp.tag == "symbol" or vp.tag == "place" or vp.owner)) then return nil end
        value = self:coerce(ep.definition.inputs[i], value)
        if Model.key(value) ~= Model.key(expected) then return nil end
    end
    local values = {}
    for i = #ep.static + 1, #ep.definition.inputs do
        values[#values + 1] = self:coerce(ep.definition.inputs[i], supplied(i))
    end
    return values
end

function E:call_receiver(w)
    local p = self:word_payload(w)
    if p.receiver and Model.get(p.receiver).tag ~= "known" then return Data.address(self, p.receiver) end
end

function E:call_captures(w)
    local p = self:word_payload(w)
    return p.capture_env and Data.reference(self, p.capture_env) or nil
end

function E:residual_call(values, context, result_type, target, receiver, captures)
    local args = {}
    for _, value in ipairs(values) do
        if Model.get(value).type ~= self.Unit then args[#args + 1] = self:reference(value) end
    end
    local id = context.builder:call(result_type, args, target, receiver, captures)
    if result_type == self.Unit then return self:known(nil, self.Unit) end
    local result = self:symbol(id, result_type, context.builder)
    if Model.record(result_type) then return Data.copy(self, result) end
    return result
end

local function dynamic(values)
    for _, value in ipairs(values) do
        local p = Model.get(value)
        if p.tag == "symbol" or p.tag == "place" then return true end
    end
    return false
end

function E:execute(w, args, context)
    local p = self:word_payload(w)
    local def = p.definition
    if not def.terminal then D.reject("signature-call", "A positional signature has no implementation") end
    if context.mode == "residualize" and def.staged then
        local lifted = require("word.closure").lift(self, w)
        if lifted ~= w then return self:execute(lifted, args, context) end
    end
    if p.owner and not p.receiver then D.reject("missing-receiver", "Select the method on an instance") end
    if p.receiver then Data.check(self, p.owner, p.receiver) end
    if p.capture_env then Data.check(self, def.lexical_environment, p.capture_env) end
    local identity = context.graph and context.graph:identity(w) or (p.method or w)
    self:check_word(w)
    if context.mode == "residualize" then
        if context.entry and self.scope:find("executing", context.entry.word) then
            local values = self:recursive_args(w, args, context.entry)
            if values then
                if not context.entry.result then error(context.entry.need_result, 0) end
                return self:residual_call(values, context, context.entry.result, "self", self:call_receiver(w), self:call_captures(w))
            end
        end
        if context.helpers then
            -- Keep each first activation inline. Only close a repeated activation
            -- with a call, so outlining elsewhere cannot erase known call-site facts.
            local stack = self.scope:stack()
            for i = #stack, 1, -1 do
                local active = stack[i]
                if active.context == context and active.invoked then
                    local values = self:recursive_args(w, args, {word = active.invoked})
                    if values then
                        if dynamic(values) or (context.oracle and context.oracle.index > active.decisions) then
                            local key = context.graph:identity(active.invoked)
                            local helper = context.helpers[key] or context.graph:known(key)
                            if helper then return self:residual_call(values, context, helper.result, helper.target, self:call_receiver(w), self:call_captures(w)) end
                            for _, t in ipairs(self:call_inputs(active.invoked)) do
                                t = self:requirement_type(t)
                                if t == self.Type then D.reject("static-required", "Bind helper Type inputs with :of before outlining recursion") end
                                Callable.check_results(t)
                            end
                            context.need_helper.word = key
                            error(context.need_helper, 0)
                        end
                        break -- Known calls can unfold, still subject to invocation/work budgets.
                    end
                end
            end
        elseif self.scope:find("executing", identity) then
            D.bug("recursive-context", "Recursive residual call has no compilation graph")
        end
    end
    if self.scope:count("executing") >= 32 then D.resource("call-depth", "Word invocation nesting exceeds 32") end
    local terminal, check_captures = def.terminal
    if def.capture_fields or def.lexical_fields or def.borrowed_fields then terminal, check_captures = require("word.closure").instantiate(self, w)
    elseif def.lexical_owner then terminal, check_captures = require("word.closure").lexical(self, w) end
    local frame = { context = context, source = def.source, executing = identity, terminal = terminal,
        invoked = w, decisions = context.oracle and context.oracle.index or 0,
        lookup_names = context.mode == "normalize" and {} or nil }
    if def.lexical_static or p.owner and not def.capture_fields and not def.borrowed_fields then
        local binding = def.lexical_static or p
        if not binding.receiver then D.reject("missing-receiver", "Select the method on an instance") end
        frame.lexical_binding = binding
        local function member_scope(name) return Data.member_scope(self, binding.receiver, binding.scope_path, name) end
        frame.has_member = function(name) return member_scope(name) ~= nil end
        frame.read_member = function(name) return Data.read(self, member_scope(name), name) end
        frame.write_member = function(name, value) return Data.write(self, member_scope(name), name, value) end
    else
        local classifier = self.scope:find("classifying_word", w)
        if classifier then
            frame.has_member = function(name) return classifier.classifying_fields[name] ~= nil end
            frame.read_member = function() error(classifier.need_receiver, 0) end
            frame.write_member = frame.read_member
        end
    end
    return self.scope:with(frame, function()
        if p.receiver then Data.check(self, p.owner, p.receiver) end
        local bound = {}
        for i = 1, #def.inputs do
            local value = p.static[i]
            if i > #p.static then value = self:coerce(def.inputs[i], args[i - #p.static]) end
            -- A bound snapshot still crosses the ordinary by-value parameter boundary.
            if Model.record(Model.get(value).type) then value = Data.copy(self, value) end
            bound[i] = value
        end
        if context.oracle then context.oracle:enter(w, bound) end
        local results = table.pack(pcall(terminal, table.unpack(bound, 1, #def.inputs)))
        if check_captures then check_captures() end
        self:check_word(w) -- Check host mutations even when a replay fork unwinds the terminal.
        if not results[1] then error(results[2], 0) end
        local result = self:result(table.pack(table.unpack(results, 2, results.n)))
        local declared = context.graph and context.graph:declared(w)
        if Model.callable(declared) then result = self:coerce(declared, result)
        elseif declared and self:result_type(result) ~= declared then D.reject("branch-result", "Return does not match the declared result type/arity") end
        local Borrow = require("word.borrow")
        Borrow.check(Borrow.value(self, result))
        if context.oracle then context.oracle:leave(result) end
        return result, frame.lookup_names
    end)
end

function E:invoke(w, args)
    local p = self:word_payload(w)
    local def = p.definition
    if Model.primitive(w) then
        local expected = #def.inputs
        if args.n ~= expected then D.reject("arity", "Wrong scalar constructor arity") end
        if w == self.Type then return self:as_type(args[1]) end
        return self:coerce(w, args[1])
    end
    if def.shape == "keyed" then
        if args.n ~= 1 then D.reject("arity", "Keyed construction requires one named supply table") end
        -- Constructing through a nested type selection is a by-value boundary;
        -- the new child has no enclosing root unless it is selected from one.
        if p.occurrence_owner then w = self:handle(def, p.static) end
        return Data.construct(self, w, args[1])
    end
    local remaining = #def.inputs - #p.static
    if remaining == 0 and args.n > 0 and def.terminal and not p.owner then
        local result = self:normalize(w)
        if not Model.word(result) then D.reject("arity", "A scalar result is not callable") end
        return self:invoke(result, args)
    end
    if args.n ~= remaining then D.reject("arity", "Runtime calls must supply every remaining input") end
    local context = self:context() or { mode = "run" }
    if context.mode == "normalize" then
        local result = self:static_call(self:specialize(w, args))
        local declared = context.graph and context.graph:declared(w)
        if Model.callable(declared) then result = self:coerce(declared, result)
        elseif declared and self:result_type(result) ~= declared then D.reject("branch-result", "Static call does not match the declared result type/arity") end
        return result
    end
    -- Ordinary empty calls return their word result without implicitly calling it again.
    return (self:execute(w, args, context))
end

-- Only the Lua call boundary expands a result pack; internal demand keeps one immutable handle.
function E:unpack_result(result)
    local p = Model.get(result)
    if p.tag == "results" then return table.unpack(p.values, 1, #p.values) end
    local def = Model.record(p.type)
    if def and def.tuple_arity then
        local values = {}
        for i = 1, def.tuple_arity do values[i] = Data.read(self, result, "r" .. i) end
        return table.unpack(values, 1, def.tuple_arity)
    end
    return result
end

function E:result_type(result)
    local p = Model.get(result)
    if p.tag ~= "results" then return p.type end
    local fields, order = {}, {}
    for i, value in ipairs(p.values) do
        local t = Model.get(value).type
        if not t then return nil end
        local name = "r" .. i; fields[name] = t; order[i] = name
    end
    return self:intern_schema(fields, order, nil, nil, #p.values)
end

function E:materialize_result(result)
    local p = Model.get(result)
    if p.tag ~= "results" then return result end
    local fields, order, values = {}, {}, {}
    for i, value in ipairs(p.values) do
        local item = Model.get(value)
        if item.tag == "word" then
            if Model.primitive(value) or item.definition.shape == "keyed" then D.reject("static-runtime", "Type words cannot be runtime results") end
            value = Callable.infer(self, value); item = Model.get(value)
        end
        local name = "r" .. i
        fields[name] = item.type; order[i] = name; values[name] = value
    end
    local t = self:intern_schema(fields, order, nil, nil, #p.values)
    return Data.construct(self, t, values)
end

function E:finish(builder, result)
    result = self:materialize_result(result)
    local r = Model.get(result)
    if r.tag == "word" then
        if Model.primitive(result) or r.definition.shape == "keyed" then
            D.reject("static-runtime", "Type words cannot be runtime results")
        end
        result = Callable.infer(self, result); r = Model.get(result)
    end
    local id
    if r.type ~= self.Unit then
        id = self:reference(result)
    end
    return builder:finish(r.type, id)
end

function E:export_entry(w, graph)
    local context = self:normal_context(); context.graph = graph
    return self.scope:with({ context = context }, function()
        local seen = {}
        while true do
            self:check_word(w)
            local p = self:word_payload(w); local def = p.definition
            if p.owner then return w end -- The method export path checks or supplies its receiver ABI.
            if Model.primitive(w) or def.shape == "keyed" then D.reject("export-word", "Export an executable word, not a type") end
            if not def.terminal then D.reject("signature-call", "Cannot export an unimplemented signature") end
            if #p.static < #def.inputs then return w end
            if seen[w] then D.reject("normalization-cycle", "Cyclic export demand") end
            seen[w] = true
            local ok, result = pcall(function() return self:static_call(w) end)
            if not ok then
                if D.is(result) and result.id == "runtime-in-normalization" then return w end
                error(result, 0)
            end
            if not Model.word(result) then return nil, result end
            w = result -- Keep the actual runtime producer reached through static factories.
        end
    end)
end

function E:compile_word(w, graph, one_call, reservation)
    local constant
    if not one_call and not reservation.declared and not Model.word(w).owner then w, constant = self:export_entry(w, graph) end
    if not w then
        local builder = IR.builder(self.max_values)
        return self.scope:with({context = {mode = "residualize", builder = builder}}, function()
            return self:finish(builder, constant)
        end)
    end
    local declared = graph:declared(w)
    if declared then graph:grounded(reservation, declared) end
    local p = self:word_payload(w); local def = p.definition
    return self.scope:with({ context = {mode = "compile"}, source = def.source }, function()
        local helpers, definition_sites = {}, {}
        local need_helper = D.control()
        local function infer()
            local entry = {word = w, need_result = D.control(), result = reservation.signature.result}
            local function run(oracle)
                local builder = IR.builder(self.max_values, oracle, graph.functions)
                oracle.builder = builder
                local context = { mode = "residualize", builder = builder, oracle = oracle, entry = entry,
                    helpers = helpers, need_helper = need_helper, graph = graph, definition_sites = definition_sites }
                return self.scope:with({ context = context, source = def.source }, function()
                    local invoked = w
                    if p.owner then
                        local owner = p.receiver and p.owner or self:requirement_type(p.owner)
                        local receiver = p.receiver or Data.receiver(self, owner, builder)
                        local captures = p.capture_env or (def.lexical_environment and Data.captures(self, def.lexical_environment, builder))
                        invoked = self:bind_method(p.method, owner, receiver, p.scope_path, captures)
                    end
                    local args = { n = #def.inputs - #p.static }
                    for i = 1, args.n do
                        local t = self:requirement_type(def.inputs[#p.static + i])
                        if t == self.Type then D.reject("static-required", "Bind Type inputs with :of before C export") end
                        Callable.check_results(t)
                        if not Model.runtime_type(t) then D.reject("runtime-type", "Parameter has no runtime representation") end
                        if t == self.Unit then args[i] = self:known(nil, t)
                        else args[i] = self:symbol(builder:parameter(t), t, builder) end
                    end
                    graph:parameters(reservation, builder.fn.parameters, builder.fn.receiver, builder.fn.captures)
                    local result = self:invoke(invoked, args)
                    if Model.callable(entry.result) then result = self:coerce(entry.result, result) end
                    result = self:materialize_result(result)
                    local r = Model.get(result)
                    if r.tag ~= "word" and entry.result and r.type ~= entry.result then
                        D.reject("branch-result", "Recursive entry paths disagree on the result type")
                    end
                    local fn = self:finish(builder, result)
                    entry.result = fn.result -- Grounded by a completed path, never guessed from input types.
                    graph:grounded(reservation, fn.result)
                    return fn
                end)
            end
            reservation.probe = function()
                -- Unknown self/helper results suspend paths, not the whole search.
                -- Known pending signatures can propagate grounding through the group.
                return Trace.ground(run, entry.need_result, self.max_paths, need_helper)
            end
            local function build() return Trace.explore(run, self.max_paths, self.max_values, graph.functions) end
            local ok, result = pcall(build)
            if ok then return result end
            if result ~= entry.need_result then error(result, 0) end
            -- A recursive arm may precede the base arm in source/replay order.
            -- Suspend at unknown calls, find a real return, then replay the whole tree.
            if not Trace.ground(run, entry.need_result, self.max_paths) then
                D.reject("recursive-result", "No return path determines this result; declare results[word] = Type (or a result-type list) in the compile specification")
            end
            return build()
        end
        while true do
            local ok, result = pcall(infer)
            if ok then return result end
            if result ~= need_helper then error(result, 0) end
            local word = need_helper.word
            local target = graph:require(word, true)
            local helper = {word = word, target = target, result = graph.functions[target].result}
            helpers[word] = helper
            -- Retry from fresh builders and tentative result facts after changing call boundaries.
        end
    end)
end

E.read_field = Data.read
E.write_field = Data.write
E.unbox_record = Data.unbox

function E:compile(spec)
    if not self:context() then
        return self.scope:with({ context = { mode = "compile" } }, function() return self:compile(spec) end)
    end
    if not Model.plain(spec) then D.reject("exports", "Expected an export specification") end
    for key in pairs(spec) do
        if key ~= "functions" and key ~= "types" and key ~= "results" then D.reject("exports", "Unknown export section: " .. tostring(key)) end
    end
    if spec.types ~= nil then
        if not Model.plain(spec.types) then D.reject("exports", "types must be a named table") end
    end
    local roots = spec.functions
    if roots == nil then roots = {} end
    if not Model.plain(roots) then D.reject("exports", "functions must be a named table") end
    local names = {}
    for name in pairs(roots) do
        if type(name) ~= "string" or name == "" then D.reject("exports", "Export names must be nonempty strings") end
        names[#names + 1] = name
    end
    table.sort(names)
    local program = { functions = {}, exports = {}, types = {} }
    local type_names = {}
    for name in pairs(spec.types or {}) do
        if type(name) ~= "string" or name == "" then D.reject("exports", "Type export names must be nonempty strings") end
        type_names[#type_names + 1] = name
    end
    table.sort(type_names)
    local engine = self
    local graph = {functions = program.functions, entries = {}, factories = {}, records = {}, methods = {}, constraints = {}, depth = 0}
    graph.declarations, graph.resolving = {}, {}
    function graph:declared(word)
        local key = self:identity(word)
        if self.constraints[key] then return self.constraints[key] end
        local declarations = self.declarations[key]
        if not declarations then return nil end
        if self.resolving[key] then D.reject("result-constraint", "Recursive callable result layout needs an explicit indirection") end
        self.resolving[key] = true
        local result = engine.scope:with({context = {mode = "compile", graph = self}}, function()
            local result
            for _, requirement in ipairs(declarations) do
                local t = Callable.result(engine, requirement)
                if result and result ~= t then D.reject("result-constraint", "Conflicting result declarations for one callable instance") end
                result = t
            end
            return result
        end)
        self.resolving[key] = nil; self.constraints[key] = result
        return result
    end
    function graph:identity(word)
        local p = engine:word_payload(word)
        if not p.owner then return word end
        local receiver = p.receiver and Model.get(p.receiver).tag == "known" and p.receiver or nil
        local key = Model.key(p.owner) .. ":" .. Model.key(p.method) .. ":" .. Owner.path_key(p.scope_path) .. ":" .. (receiver and Model.key(receiver) or "storage")
        if not self.methods[key] then self.methods[key] = engine:bind_method(p.method, p.owner, receiver, p.scope_path) end
        return self.methods[key]
    end
    function graph:parameters(entry, parameters, receiver, captures)
        local previous = entry.signature.parameters
        if previous then
            if (entry.signature.receiver and entry.signature.receiver.type) ~= (receiver and receiver.type) then
                D.reject("replay-diverged", "Function receiver ABI changed during inference")
            end
            if (entry.signature.captures and entry.signature.captures.type) ~= (captures and captures.type) then
                D.reject("replay-diverged", "Function capture ABI changed during inference")
            end
            if #previous ~= #parameters then D.reject("replay-diverged", "Function parameter arity changed during inference") end
            for i, parameter in ipairs(parameters) do
                if previous[i].type ~= parameter.type then D.reject("replay-diverged", "Function parameter type changed during inference") end
            end
        else
            local copy = {}
            for i, parameter in ipairs(parameters) do copy[i] = {id = parameter.id, type = parameter.type} end
            entry.signature.parameters = copy
            if receiver then entry.signature.receiver = {id = receiver.id, type = receiver.type} end
            if captures then entry.signature.captures = {id = captures.id, type = captures.type} end
        end
    end
    function graph:grounded(entry, result)
        if entry.signature.result and entry.signature.result ~= result then
            D.reject("branch-result", "Recursive group returns disagree on a function's result type")
        end
        entry.signature.result = result
    end
    function graph:known(word)
        local entry = self.entries[word]
        if entry and entry.signature.result then return {target = entry.target, result = entry.signature.result} end
    end
    function graph:ground(goal)
        -- Monotone type facts: every new result comes from a completed path using
        -- only already-grounded callees. No circular assumption seeds this search.
        repeat
            local progress = false
            for _, entry in ipairs(self.records) do
                if not entry.fn and not entry.signature.result and entry.probe then
                    entry.probe()
                    if entry.signature.result then progress = true end
                end
                if goal.signature.result then return true end
            end
            if not progress then return false end
        until false
    end
    function graph:require(word, one_call)
        local p = engine:word_payload(word)
        require("word.closure").check_lexical_outline(word)
        if p.owner then
            if not one_call and p.receiver and Model.get(p.receiver).tag ~= "known" then
                D.reject("bound-method-export", "Export the unbound Type.method with a receiver parameter, not a method bound to mutable Lua storage")
            end
            word = self:identity(word)
        end
        -- Export demand can follow an unowned factory; methods and outlined calls invoke once.
        local entries = not one_call and not p.owner and #p.static == #p.definition.inputs and self.factories or self.entries
        local entry = entries[word]
        if entry then
            if not entry.fn and not entry.signature.result and not self:ground(entry) then
                D.reject("recursive-result", "No return path determines this recursive group's result; declare results[word] = Type (or a result-type list)")
            end
            return entry.target
        end
        if #self.functions >= engine.max_functions then D.resource("function-instances", "Residual function instance budget exhausted") end
        if self.depth >= 32 then D.resource("function-depth", "Residual helper demand nesting exceeds 32") end
        local declared = self:declared(word)
        entry = {target = #self.functions + 1, signature = {result = declared}, declared = declared}; entries[word] = entry
        self.records[#self.records + 1] = entry
        self.functions[entry.target] = entry.signature -- A declaration, never a fabricated function body.
        self.depth = self.depth + 1
        local fn = engine:compile_word(word, self, one_call, entry)
        self.depth = self.depth - 1
        self.functions[entry.target] = fn; entry.fn = fn; entry.probe = nil
        return entry.target
    end
    if spec.results ~= nil then
        if not Model.plain(spec.results) then D.reject("result-constraint", "results must map ordered words to result requirements") end
        for word, requirement in pairs(spec.results) do
            local p = self:word_payload(word)
            if Model.primitive(word) or p.definition.shape ~= "ordered" then
                D.reject("result-constraint", "A result declaration requires an ordered word or signature")
            end
            local key = graph:identity(word)
            graph.declarations[key] = graph.declarations[key] or {}
            graph.declarations[key][#graph.declarations[key] + 1] = requirement
        end
        for word in pairs(graph.declarations) do graph:declared(word) end
    end
    self.scope:with({context = {mode = "compile", graph = graph}}, function()
        for _, name in ipairs(type_names) do
            local t = self:requirement_type(spec.types[name])
            if not Model.runtime_type(t) then D.reject("runtime-type", "Exported type has no runtime representation") end
            program.types[#program.types + 1] = {name = name, type = t}
        end
    end)
    for _, name in ipairs(names) do
        local target = graph:require(roots[name])
        program.exports[#program.exports + 1] = { name = name, target = target }
    end
    program.callable_targets = {}
    local seen_types = {}
    local function register_type(t)
        if not t or seen_types[t] then return end
        seen_types[t] = true
        local abi, record = Model.callable(t), Model.record(t)
        if abi then
            if abi.code then program.callable_targets[t] = graph:require(abi.code, true) end
            register_type(abi.result); register_type(abi.environment)
            for _, parameter in ipairs(abi.parameters) do register_type(parameter.type) end
        elseif record then
            for _, name in ipairs(record.runtime_order) do register_type(record.fields[name]) end
        end
    end
    for _, fn in ipairs(program.functions) do
        register_type(fn.result)
        for _, p in ipairs(fn.parameters) do register_type(p.type) end
        for _, block in ipairs(fn.blocks) do for _, ins in ipairs(block.instructions) do register_type(ins.type) end end
    end
    IR.verify(program)
    require("word.borrow").verify(program)
    return program
end

return E
