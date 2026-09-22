-- Borrowed callables are local views, never owned result storage.
local Model = require("word.model")
local D = require("word.diagnostic")
local M = {}

function M.type(t)
    if Model.borrow_target(t) then return true end
    local abi = Model.callable(t)
    if abi then return not abi.code or (abi.environment ~= nil and not abi.value_environment) end
    local record = Model.record(t)
    if record then for _, name in ipairs(record.runtime_order) do
        if M.type(record.fields[name]) then return true end
    end end
    return false
end

function M.value(engine, value, seen)
    local p = Model.get(value)
    if not p then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    if p.tag == "callable_known" then return M.value(engine, p.code, seen) end
    if p.occurrence_receiver and Model.get(p.occurrence_receiver).tag ~= "known" then return true end
    if p.tag == "word" then
        if p.capture_env and M.type(Model.get(p.capture_env).type) then return true end
        if p.definition.borrowed_fields then return true end
        if p.receiver and Model.get(p.receiver).tag ~= "known" and not p.definition.capture_fields then return true end
        local terminal = p.definition.terminal
        if terminal then
            local i = 1
            while true do
                local name, captured = debug.getupvalue(terminal, i)
                if not name then break end
                local cp = Model.get(captured)
                if cp and (cp.tag == "place" or (cp.tag == "symbol" and Model.record(cp.type))) then return true end
                if M.value(engine, captured, seen) then return true end
                i = i + 1
            end
        end
        for _, fields in ipairs({p.definition.fields or {}, p.definition.methods or {}}) do
            for _, child in pairs(fields) do if M.value(engine, child, seen) then return true end end
        end
        return false
    end
    if p.tag == "results" then
        for _, item in ipairs(p.values) do if M.value(engine, item, seen) then return true end end
        return false
    end
    if not M.type(p.type) then return false end
    if p.tag == "symbol" or (p.root and p.root.builder) then return true end
    local record = Model.record(p.type)
    if record then
        local Data = require("word.data")
        for _, name in ipairs(record.runtime_order) do
            if M.value(engine, Data.read(engine, value, name), seen) then return true end
        end
        return false
    end
    return true
end

function M.check(borrowed)
    if borrowed then
        D.reject("borrow-escape", "Borrowed methods/callbacks cannot be returned or stored in records; return the stateful record and select its methods at the call site")
    end
end

-- A local, type-directed check: no ownership graph, output layouts or recursion fixed point.
-- Opaque signatures are borrowed contracts. Foreign implementations must not retain inputs.
function M.verify(program)
    local borrowing_calls = {}
    for _, fn in ipairs(program.functions) do
        local values = {}
        for _, p in ipairs(fn.parameters) do values[p.id] = M.type(p.type) end
        if fn.captures then values[fn.captures.id] = M.type(fn.captures.type) end
        for _, block in ipairs(fn.blocks) do
            for _, ins in ipairs(block.instructions) do
                local borrowed = M.type(ins.type)
                if ins.op == "FunctionRef" then borrowed = ins.captures ~= nil or (ins.receiver ~= nil and not Model.callable(ins.type).value_environment)
                elseif ins.op == "Construct" then
                    for _, id in pairs(ins.fields) do M.check(values[id]) end
                    borrowed = false
                elseif ins.op == "Store" then M.check(values[ins.value])
                elseif ins.op == "Local" then borrowed = values[ins.initial]
                end
                if ins.op == "Call" then
                    if ins.captures and values[ins.captures] then borrowing_calls[ins] = true end
                    for _, id in ipairs(ins.args) do
                        if values[id] then borrowing_calls[ins] = true end
                    end
                end
                if ins.id then values[ins.id] = borrowed end
            end
            if block.exit.op == "Return" then M.check(values[block.exit.value]) end
        end
    end
    return borrowing_calls
end

return M
