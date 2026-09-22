local D = require("word.diagnostic")
local Model = require("word.model")
local Data = require("word.data")
local M = {}

-- An input-only requirement is useful for known code, but cannot describe an
-- unknown runtime call until its result contract has been supplied.
function M.check_results(t, seen)
    if Model.calling_requirement(t) then
        D.reject("callable-result", "Runtime callable result is undetermined; declare results[signature] = ResultType (or a result type list)")
    end
    local def = Model.record(t)
    if not def then return end
    seen = seen or {}; if seen[t] then return end; seen[t] = true
    for _, name in ipairs(def.runtime_order) do M.check_results(def.fields[name], seen) end
end

function M.type(engine, signature, result)
    engine.callable_types = engine.callable_types or {}
    local inputs, parameters, parts = engine:call_inputs(signature), {}, {Model.key(result)}
    for i, t in ipairs(inputs) do
        inputs[i] = engine:requirement_type(t)
        parts[#parts + 1] = Model.key(inputs[i])
    end
    local key = table.concat(parts, "/")
    if engine.callable_types[key] then return engine.callable_types[key] end
    for _, t in ipairs(inputs) do
        M.check_results(t)
        if not Model.runtime_type(t) then D.reject("runtime-type", "Callable input needs a concrete runtime type") end
        if t ~= engine.Unit then parameters[#parameters + 1] = {type = t} end
    end
    local def = engine:definition(inputs, nil)
    local shape = engine:handle(engine:definition(inputs, nil), {})
    def.shape = "callable"; def.callable = {inputs = inputs, parameters = parameters, result = result, signature = shape}
    local t = engine:handle(def, {}); engine.callable_types[key] = t
    return t
end

-- A concrete closure carries its code in its type, not in a runtime function pointer.
function M.infer(engine, value)
    value = require("word.closure").lift(engine, value)
    local graph = engine:context().graph
    local target = graph:require(value, true)
    graph.concrete_callables = graph.concrete_callables or {}
    local t = graph.concrete_callables[target]
    if not t then
        local fn = graph.functions[target]
        local shape = Model.callable(M.type(engine, value, fn.result))
        local def = engine:definition(shape.inputs, nil)
        def.shape = "callable"
        def.callable = {inputs = shape.inputs, parameters = shape.parameters, result = shape.result,
            signature = shape.signature, code = graph:identity(value), environment = fn.receiver and fn.receiver.type,
            value_environment = Model.word(value).definition.capture_fields ~= nil}
        t = Model.wrap({tag = "word", engine = engine, definition = def, static = {}}, engine.word_mt)
        graph.concrete_callables[target] = t
    end
    return M.coerce(engine, t, value)
end

local function compatible(a, b)
    if a.result ~= b.result or #a.parameters ~= #b.parameters then return false end
    for i, p in ipairs(a.parameters) do if p.type ~= b.parameters[i].type then return false end end
    return true
end

function M.coerce(engine, t, value)
    local context, p = engine:context(), Model.get(value)
    local abi = Model.callable(t)
    if p and p.tag == "symbol" and Model.callable(p.type) then
        if not context or context.builder ~= p.builder then D.reject("symbol-extent", "Callable escaped its trace") end
        if p.type == t then return value end
        local actual = Model.callable(p.type)
        if not abi.code and actual.code and compatible(abi, actual) then
            local target = context.graph:require(actual.code, true)
            return engine:symbol(context.builder:emit{op = "FunctionRef", type = t, target = target,
                receiver = actual.environment and {closure = p.id, type = actual.environment, by_value = actual.value_environment}}, t, context.builder)
        end
        D.reject("callable-shape", "Callable representations have incompatible signatures or code identities")
    end
    if p and p.tag == "callable_known" then value = p.code end
    value = engine:coerce_callable(abi.signature, value)
    if not context or not context.builder then return value end
    if abi.code then value = require("word.closure").lift(engine, value) end
    if abi.code and context.graph:identity(value) ~= abi.code then D.reject("callable-shape", "Concrete closure code identity mismatch") end
    return Model.wrap({tag = "callable_known", engine = engine, type = t, code = value,
        receiver = Model.word(value).receiver}, engine.value_mt)
end

-- Materialization happens at a data/ABI boundary, never merely because a known word is called.
function M.reference(engine, value)
    local p, context = Model.get(value), engine:context()
    local abi = Model.callable(p.type)
    local code = require("word.closure").lift(engine, p.code)
    local target = context.graph:require(code, true)
    local fn = context.graph.functions[target]
    if not compatible(abi, {result = fn.result, parameters = fn.parameters}) then
        D.reject("callable-shape", "Callable implementation does not match its runtime signature")
    end
    return context.builder:emit{op = "FunctionRef", type = p.type, target = target,
        receiver = fn.receiver and engine:call_receiver(code) or nil}
end

function M.invoke(engine, value, args)
    local p = Model.get(value)
    local abi = p and Model.callable(p.type)
    if not abi then D.reject("callable-required", "Value is not a runtime callable") end
    M.coerce(engine, p.type, value)
    if args.n ~= #abi.inputs then D.reject("arity", "Runtime callable arity mismatch") end
    if p.tag == "callable_known" then
        local result = engine:invoke(p.code, args)
        if Model.callable(abi.result) then return M.coerce(engine, abi.result, result) end
        if engine:result_type(result) ~= abi.result then D.reject("callable-shape", "Known callable result does not match its signature") end
        return result
    end
    local operands = {}
    for i, t in ipairs(abi.inputs) do
        local v = engine:coerce(t, args[i])
        if t ~= engine.Unit then operands[#operands + 1] = engine:reference(v) end
    end
    local builder = engine:context().builder
    if abi.code then
        local target = engine:context().graph:require(abi.code, true)
        local receiver = abi.environment and {closure = p.id, type = abi.environment, by_value = abi.value_environment}
        local id = builder:call(abi.result, operands, target, receiver)
        if abi.result == engine.Unit then return engine:known(nil, engine.Unit) end
        local result = engine:symbol(id, abi.result, builder)
        return Model.record(abi.result) and Data.copy(engine, result) or result
    end
    local ins = {op = "IndirectCall", callable = p.id, callable_type = p.type, type = abi.result, args = operands}
    if abi.result == engine.Unit then
        builder:id(); builder.block.instructions[#builder.block.instructions + 1] = ins
        if builder.oracle then builder.oracle:event(ins) end
        return engine:known(nil, engine.Unit)
    end
    local result = engine:symbol(builder:emit(ins), abi.result, builder)
    if Model.record(abi.result) then return Data.copy(engine, result) end
    return result
end

function M.record(engine, t)
    local context = engine:context()
    if not context or not context.graph then return t end
    local cache = context.graph.callable_records or {}
    context.graph.callable_records = cache
    if cache[t] then return cache[t] end
    local def, fields, changed = Model.record(t), {}, false
    for _, name in ipairs(def.order) do
        local ft = def.fields[name]
        fields[name] = def.bindings[name] and ft or engine:requirement_type(ft)
        changed = changed or fields[name] ~= ft
    end
    local result = changed and engine:intern_schema(fields, def.order, def.bindings, def.methods, def.tuple_arity) or t
    cache[t] = result; cache[result] = result
    return result
end

function M.result(engine, requirement)
    local t
    if Model.plain(requirement) then
        local count, n = 0, #requirement
        for key in pairs(requirement) do
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > n then
                D.reject("result-constraint", "Result type lists must be dense arrays")
            end
            count = count + 1
        end
        if count ~= n then D.reject("result-constraint", "Result type lists must be dense arrays") end
        local fields, order = {}, {}
        for i, value in ipairs(requirement) do
            local name = "r" .. i; fields[name] = engine:requirement_type(value); order[i] = name
        end
        t = n == 0 and engine.Unit or (n == 1 and fields.r1 or engine:intern_schema(fields, order, nil, nil, n))
    else t = engine:requirement_type(requirement) end
    M.check_results(t)
    if not Model.runtime_type(t) then D.reject("runtime-type", "Declared result needs a concrete runtime representation") end
    return t
end

return M
