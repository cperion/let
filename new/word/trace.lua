-- Replay creates fresh traces. Only checked prefixes become shared branch blocks.
local D = require("word.diagnostic")
local table = require("word.host").table
local Model = require("word.model")
local IR = require("word.ir")
local M = {}
local Oracle = {}
Oracle.__index = Oracle

local function equal(a, b)
    if rawequal(a, b) then return true end
    if type(a) ~= "table" or type(b) ~= "table" or Model.get(a) or Model.get(b) then return false end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function M.describe(value)
    local p = assert(Model.get(value))
    if p.tag == "results" then
        local values = {}; for i, item in ipairs(p.values) do values[i] = M.describe(item) end
        return {tag = "results", values = values}
    end
    if p.tag == "callable_known" then return {tag = p.tag, type = p.type, code = M.describe(p.code)} end
    if p.tag == "word" then
        return {tag = "word", key = Model.key(p.method or value), owner = p.owner,
            scope_path = require("word.owner").path_key(p.scope_path),
            receiver = p.receiver and M.describe(p.receiver) or nil}
    elseif p.tag == "place" then
        return {tag = "place", type = p.type, root = p.root.id, path = {table.unpack(p.path)}}
    end
    if p.tag == "known" and Model.record(p.type) then
        return {tag = "known", type = p.type, key = Model.key(value)}
    end
    return {tag = p.tag, type = p.type, id = p.id, value = p.value}
end

function Oracle:event(event) self.events[#self.events + 1] = event end
function Oracle:enter(word, arguments)
    local args = {}
    for i, value in ipairs(arguments) do args[i] = M.describe(value) end
    self:event{op = "Enter", word = M.describe(word), args = args}
end
function Oracle:leave(value) self:event{op = "Leave", value = M.describe(value)} end
function Oracle:choose(predicate)
    self.index = self.index + 1
    local entry = self.tape[self.index]
    if entry then
        if not equal(self.events, entry.prefix) then
            D.reject("replay-diverged", "Re-execution changed a previously recorded trace prefix")
        end
        self:event{op = "Decision", predicate = predicate, choice = entry.choice}
        return entry.choice
    end
    if self.index > 32 then D.resource("trace-depth", "Symbolic decision nesting exceeds 32") end
    self.predicate = predicate
    error(self.fork, 0)
end

local function copy(t)
    local out = {}; for k, v in pairs(t) do out[k] = v end; return out
end

-- Result discovery executes only recursion-free prefixes. An unknown call
-- suspends its path; it never supplies a fabricated value to the terminal.
function M.ground(run, blocked, max_paths, other_blocked)
    local paths = 1
    local function visit(tape)
        local oracle = setmetatable({tape = tape, index = 0, events = {}, fork = D.control()}, Oracle)
        local ok, result = pcall(run, oracle)
        local suspended = not ok and (result == blocked or (other_blocked ~= nil and result == other_blocked))
        if not ok and result ~= oracle.fork and not suspended then error(result, 0) end
        if oracle.index < #tape then D.reject("replay-diverged", "Result discovery changed its decision prefix") end
        if ok then return result.result end
        if suspended then return nil end
        paths = paths + 1
        if paths > max_paths then D.resource("trace-paths", "Result discovery path budget exhausted") end
        for _, choice in ipairs({true, false}) do
            local next_tape = copy(tape)
            next_tape[#next_tape + 1] = {choice = choice, prefix = oracle.events}
            local t = visit(next_tape)
            if t then return t end
        end
    end
    return visit({})
end

function M.explore(run, max_paths, max_values, functions)
    local fn = {parameters = {}, blocks = {}}
    local serial, paths = 0, 1
    local function fresh()
        serial = serial + 1
        if serial > max_values then D.resource("ir-values", "Assembled branch tree exceeds the residual budget") end
        return serial
    end
    local function explore(tape, skip, inherited)
        local oracle = setmetatable({tape = tape, index = 0, events = {}, fork = D.control()}, Oracle)
        local ok, result = pcall(run, oracle)
        if not ok and result ~= oracle.fork then error(result, 0) end
        if oracle.index < #tape then D.reject("replay-diverged", "Replay returned before consuming its decision tape") end
        local trace = oracle.builder.fn
        local map = copy(inherited)
        if #tape == 0 then
            if trace.receiver then
                local p = trace.receiver
                map[p.id] = fresh(); fn.receiver = {id = map[p.id], type = p.type}
            end
            for _, p in ipairs(trace.parameters) do
                map[p.id] = fresh(); fn.parameters[#fn.parameters + 1] = {id = map[p.id], type = p.type}
            end
        end
        local function use(id)
            if id == nil then return nil end
            if not map[id] then D.bug("trace-id", "Missing prefix value during trace assembly") end
            return map[id]
        end
        local block = {id = #fn.blocks + 1, instructions = {}}
        fn.blocks[block.id] = block
        local instructions = trace.blocks[1].instructions
        for i = skip + 1, #instructions do
            local ins = instructions[i]
            local out = copy(ins)
            local id = fresh() -- Stores also consume budget.
            if ins.args then
                out.args = {}; for j, operand in ipairs(ins.args) do out.args[j] = use(operand) end
            end
            if ins.fields then
                out.fields = {}; for name, value in pairs(ins.fields) do out.fields[name] = use(value) end
            end
            if ins.callable then out.callable = use(ins.callable) end
            if ins.initial then out.initial = use(ins.initial) end
            if ins.root then out.root = use(ins.root) end
            if ins.receiver then
                out.receiver = copy(ins.receiver)
                out.receiver.root = use(ins.receiver.root)
                out.receiver.closure = use(ins.receiver.closure)
                out.receiver.path = ins.receiver.path and copy(ins.receiver.path)
            end
            if ins.op == "Store" then out.value = use(ins.value) end
            if ins.id then map[ins.id] = id; out.id = id end
            block.instructions[#block.instructions + 1] = out
        end
        if ok then
            if fn.result and fn.result ~= trace.result then
                D.reject("branch-result", "All residual paths must return the same concrete type")
            end
            fn.result = trace.result
            block.exit = {op = "Return", value = use(trace.blocks[1].exit.value)}
        else
            paths = paths + 1
            if paths > max_paths then D.resource("trace-paths", "Symbolic path budget exhausted") end
            fresh() -- Branches consume the assembled instruction budget too.
            local function arm(choice)
                local next_tape = copy(tape)
                next_tape[#next_tape + 1] = {choice = choice, prefix = oracle.events}
                return explore(next_tape, #instructions, map)
            end
            local yes, no = arm(true), arm(false)
            block.exit = {op = "Branch", condition = use(oracle.predicate), yes = yes, no = no}
        end
        return block.id
    end
    explore({}, 0, {})
    IR.verify_function(fn, functions)
    return fn
end

return M
