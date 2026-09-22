local D = require("word.diagnostic")
local Host = require("word.host")
local table, math = Host.table, Host.math
local Model = require("word.model")
local M = {}
local Builder = {}
Builder.__index = Builder

function M.builder(limit, oracle, functions)
    local block = { id = 1, instructions = {} }
    return setmetatable({ fn = { parameters = {}, blocks = { block } }, block = block,
        next_id = 0, limit = limit, constants = {}, oracle = oracle, functions = functions }, Builder)
end
function Builder:id()
    self.next_id = self.next_id + 1
    if self.next_id > self.limit then D.resource("ir-values", "Residual instruction/value budget exhausted") end
    return self.next_id
end
function Builder:receiver(t)
    local id = self:id()
    self.fn.receiver = {id = id, type = t}
    if self.oracle then self.oracle:event{op = "Receiver", id = id, type = t} end
    return id
end
function Builder:captures(t)
    local id = self:id()
    self.fn.captures = {id = id, type = t}
    if self.oracle then self.oracle:event{op = "Captures", id = id, type = t} end
    return id
end
function Builder:parameter(t)
    local id = self:id()
    self.fn.parameters[#self.fn.parameters + 1] = { id = id, type = t }
    if self.oracle then self.oracle:event{op = "Parameter", id = id, type = t} end
    return id
end
function Builder:emit(ins)
    ins.id = self:id(); self.block.instructions[#self.block.instructions + 1] = ins
    if self.oracle then self.oracle:event(ins) end
    return ins.id
end
function Builder:constant(t, value)
    local key = Model.primitive(t) .. ":" .. tostring(value)
    if not self.constants[key] then self.constants[key] = self:emit{ op = "Constant", type = t, value = value } end
    return self.constants[key]
end
function Builder:binary(op, t, a, b) return self:emit{ op = op, type = t, args = { a, b } } end
function Builder:construct(t, fields) return self:emit{ op = "Construct", type = t, fields = fields } end
function Builder:local_record(t, initial) return self:emit{ op = "Local", type = t, initial = initial } end
function Builder:load(t, root, path)
    return self:emit{ op = "Load", type = t, root = root, path = { table.unpack(path) } }
end
function Builder:call(t, args, target, receiver, captures)
    local ins = {op = "Call", target = target or "self", type = t, args = args, receiver = receiver, captures = captures}
    if Model.primitive(t) ~= "Unit" then return self:emit(ins) end
    self:id() -- A void call is still an ordered effect.
    self.block.instructions[#self.block.instructions + 1] = ins
    if self.oracle then self.oracle:event(ins) end
end

function Builder:store(t, root, path, value)
    self:id() -- Stores consume budget even though they define no SSA value.
    local ins = {op = "Store", type = t, root = root, path = { table.unpack(path) }, value = value}
    self.block.instructions[#self.block.instructions + 1] = ins
    if self.oracle then self.oracle:event(ins) end
end
function Builder:finish(t, id)
    self.fn.result = t; self.block.exit = { op = "Return", value = id }
    M.verify_function(self.fn, self.functions)
    return self.fn
end

local function check(ok, message) if not ok then D.bug("invalid-ir", message) end end
local function runtime_value(t) return Model.runtime_type(t) and Model.primitive(t) ~= "Unit" end

function M.verify_function(fn, functions)
    check(type(fn) == "table" and type(fn.parameters) == "table" and
        type(fn.blocks) == "table" and #fn.blocks >= 1, "Expected a function with an entry block")
    check(Model.runtime_type(fn.result), "Unsupported or unsealed result type")
    local defined, all_ids, visited = {}, {}, {}
    local function define(id, t, place)
        check(type(id) == "number" and math.type(id) == "integer" and id > 0 and not all_ids[id], "Invalid value ID")
        all_ids[id] = true
        check(runtime_value(t), "Invalid residual value type")
        defined[id] = { type = t, place = place or false }
    end
    local function value(id, t)
        local entry = defined[id]
        check(entry and not entry.place and entry.type == t, "Operand is undefined, a place, or has the wrong type")
    end
    local function target(ins)
        if ins.closure then
            local entry = defined[ins.closure]
            local abi = entry and Model.callable(entry.type)
            check(abi and abi.code and abi.environment == ins.type and not entry.place and
                not not ins.by_value == not not abi.value_environment, "Invalid concrete closure environment")
            return
        end
        local root = defined[ins.root]
        check(root and root.place and type(ins.path) == "table", "Invalid storage root/path")
        local t = root.type
        for _, name in ipairs(ins.path) do
            local def = Model.record(t)
            check(def and type(name) == "string" and def.fields[name] and not def.bindings[name], "Invalid runtime field path")
            t = def.fields[name]
        end
        check(t == ins.type and runtime_value(t), "Storage path type mismatch")
    end
    if fn.receiver then
        check(type(fn.receiver) == "table" and Model.record(fn.receiver.type), "Receiver requires a record schema")
        define(fn.receiver.id, fn.receiver.type, true)
    end
    if fn.captures then
        check(type(fn.captures) == "table" and Model.record(fn.captures.type) and
            not require("word.borrow").type(fn.captures.type), "Captures require an owned by-value record")
        define(fn.captures.id, fn.captures.type, true)
    end
    for _, p in ipairs(fn.parameters) do define(p.id, p.type) end
    local function captures(ins, callee)
        if callee.captures then value(ins.captures, callee.captures.type)
        else check(ins.captures == nil, "Unexpected capture argument") end
    end
    local function visit(id, depth)
        check(depth <= 33, "Branch tree exceeds the supported depth")
        local block = fn.blocks[id]
        check(type(block) == "table" and block.id == id and type(block.instructions) == "table" and not visited[id],
            "Invalid block, cycle, or shared suffix in branch tree")
        visited[id] = true
        for _, ins in ipairs(block.instructions) do
            if ins.op == "Constant" then
                check(Model.primitive(ins.type) and Model.literal(ins.type, ins.value), "Malformed typed constant")
            elseif ins.op == "Add" or ins.op == "Sub" or ins.op == "Mul" or ins.op == "Div" or
                ins.op == "Mod" or ins.op == "Pow" or ins.op == "And" or ins.op == "Or" or
                ins.op == "Xor" or ins.op == "Shl" or ins.op == "Shr" then
                check(Model.primitive(ins.type) == "U32" and type(ins.args) == "table" and #ins.args == 2, "Arithmetic type/arity")
                value(ins.args[1], ins.type); value(ins.args[2], ins.type)
            elseif ins.op == "Compare" then
                local t = Model.primitive(ins.operand_type)
                check(Model.primitive(ins.type) == "Bool" and type(ins.args) == "table" and #ins.args == 2 and
                    ((ins.predicate == "eq" and (t == "U32" or t == "Bool")) or
                    ((ins.predicate == "lt" or ins.predicate == "le") and t == "U32")), "Comparison type/arity")
                value(ins.args[1], ins.operand_type); value(ins.args[2], ins.operand_type)
            elseif ins.op == "Construct" then
                local def = Model.record(ins.type)
                check(def and type(ins.fields) == "table", "Invalid record construction")
                for name, operand in pairs(ins.fields) do
                    check(def.fields[name] and not def.bindings[name] and Model.primitive(def.fields[name]) ~= "Unit", "Invalid constructor field")
                    value(operand, def.fields[name])
                end
                for _, name in ipairs(def.runtime_order) do
                    if Model.primitive(def.fields[name]) ~= "Unit" then value(ins.fields[name], def.fields[name]) end
                end
            elseif ins.op == "Local" then
                check(Model.record(ins.type), "Local storage requires a record type"); value(ins.initial, ins.type)
            elseif ins.op == "Load" then target(ins)
            elseif ins.op == "FunctionRef" then
                local abi, callee = Model.callable(ins.type), functions and functions[ins.target]
                check(abi and callee and callee.result == abi.result and
                    #callee.parameters == #abi.parameters, "Invalid callable reference")
                if callee.receiver then
                    check(ins.receiver and ins.receiver.type == callee.receiver.type, "Callable environment type mismatch")
                    target(ins.receiver)
                else check(ins.receiver == nil, "Unexpected callable environment") end
                captures(ins, callee)
                check(not callee.captures or not abi.code, "Borrowed capture bundles require a non-retaining callable interface")
                for i, parameter in ipairs(abi.parameters) do
                    check(callee.parameters[i].type == parameter.type, "Callable reference parameter mismatch")
                end
            elseif ins.op == "IndirectCall" then
                local abi = Model.callable(ins.callable_type)
                check(abi and ins.type == abi.result and #ins.args == #abi.parameters, "Invalid indirect call signature")
                value(ins.callable, ins.callable_type)
                for i, parameter in ipairs(abi.parameters) do value(ins.args[i], parameter.type) end
                if Model.primitive(ins.type) == "Unit" then check(ins.id == nil, "Void call defines a value") end
            elseif ins.op == "Call" then
                local callee = fn
                if ins.target ~= "self" then
                    check(math.type(ins.target) == "integer" and ins.target > 0 and functions and functions[ins.target], "Undefined call target")
                    callee = functions[ins.target]
                end
                check(type(callee.parameters) == "table" and ins.type == callee.result and type(ins.args) == "table" and
                    #ins.args == #callee.parameters, "Invalid call result or arity")
                for i, parameter in ipairs(callee.parameters) do value(ins.args[i], parameter.type) end
                if callee.receiver then
                    check(type(ins.receiver) == "table" and Model.record(callee.receiver.type) and
                        ins.receiver.type == callee.receiver.type, "Receiver ABI mismatch")
                    target(ins.receiver)
                else check(ins.receiver == nil, "Unexpected receiver argument") end
                captures(ins, callee)
                if Model.primitive(ins.type) == "Unit" then check(ins.id == nil, "Void call must not define a value") end
            elseif ins.op == "Store" then
                target(ins); value(ins.value, ins.type); check(ins.id == nil, "Store must not define a value")
            else D.bug("invalid-ir", "Unknown residual operation") end
            if ins.op ~= "Store" and not ((ins.op == "Call" or ins.op == "IndirectCall") and Model.primitive(ins.type) == "Unit") then
                define(ins.id, ins.type, ins.op == "Local")
            end
        end
        local exit = block.exit
        check(type(exit) == "table", "Missing block exit")
        if exit.op == "Return" then
            if Model.primitive(fn.result) == "Unit" then check(exit.value == nil, "Unit has no runtime payload")
            else value(exit.value, fn.result) end
        elseif exit.op == "Branch" then
            local condition = defined[exit.condition]
            check(condition and not condition.place and Model.primitive(condition.type) == "Bool", "Invalid branch condition")
            visit(exit.yes, depth + 1); visit(exit.no, depth + 1)
        else D.bug("invalid-ir", "Unsupported block exit") end
        for _, ins in ipairs(block.instructions) do if ins.id then defined[ins.id] = nil end end
    end
    visit(1, 1)
    for i, block in ipairs(fn.blocks) do check(block.id == i and visited[i], "Unreachable or misnumbered block") end
    return true
end

function M.verify(program)
    check(type(program) == "table" and type(program.functions) == "table" and type(program.exports) == "table", "Expected program")
    for _, fn in ipairs(program.functions) do M.verify_function(fn, program.functions) end
    local names = {}
    for _, export in ipairs(program.exports) do
        check(type(export.name) == "string" and export.name ~= "" and not names[export.name], "Invalid export name")
        check(program.functions[export.target] ~= nil, "Undefined export target"); names[export.name] = true
    end
    names = {}
    for _, export in ipairs(program.types or {}) do
        check(type(export.name) == "string" and export.name ~= "" and not names[export.name], "Invalid type export name")
        check(Model.runtime_type(export.type), "Type export lacks a runtime representation"); names[export.name] = true
    end
    return true
end

return M
