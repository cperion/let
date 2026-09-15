-- Ownership is a frontend proof. Mutable flow state is kept off the ASDL nodes.
local V = require('let.vocab')
local asdl = require('asdl')
local fail = require('let.lexer').fail
local A, S = V.Syntax, V.Semantic
local O = asdl.NewContext()
O:Extern('Shape', function(x) return S.Shape:isclassof(x) end)
O:Extern('Capability', function(x) return S.Capability:isclassof(x) end)
O:Extern('Span', function(x) return V.Source.Span:isclassof(x) end)
O:Define [[
    Mode = Copy | Fresh | ReadBorrow | MutBorrow | Transfer
    Value = Data(Shape shape, Mode mode, number? origin)
          | Word(number id, number supplied) | Host(number id)
    Binding = (number id, string name, Value value, Capability capability, boolean external, Span span)
]]
local Checker = {}
Checker.__index = Checker
function Checker.new(program) return setmetatable({ program = program, next_id = 0, bindings = {} }, Checker) end
local Context = {}
Context.__index = Context
local function copy(map) local r = {}; for k, v in pairs(map) do r[k] = v end; return r end
function Context.new(checker, env)
    return setmetatable({ checker = checker, env = env, initialized = {}, reads = {}, writes = {} }, Context)
end
function Context:child(nested)
    local env = nested and setmetatable({}, { __index = self.env }) or self.env
    local child = Context.new(self.checker, env)
    child.initialized, child.reads, child.writes = copy(self.initialized), copy(self.reads), copy(self.writes)
    return child
end
function Context:bind(name, value, capability, external, span)
    if rawget(self.env, name) then fail(span, 'duplicate binding ' .. name) end
    local checker = self.checker; checker.next_id = checker.next_id + 1
    local binding = O.Binding(checker.next_id, name, value, capability, external, span)
    self.env[name] = binding; checker.bindings[binding.id] = binding; self.initialized[binding.id] = true
    return binding
end
function Context:lookup(name, span, allow_uninitialized)
    local binding = self.env[name]
    if not binding then fail(span, 'unknown name ' .. name) end
    if not allow_uninitialized and not self.initialized[binding.id] then fail(span, 'use after move or uninitialized binding ' .. name) end
    return binding
end
function Context:access(binding, span, writing)
    local id = binding.id
    if self.writes[id] or (writing and (self.reads[id] or 0) > 0) then fail(span, 'conflicting borrow of ' .. binding.name) end
end
function O.Data:read(ctx, binding, span)
    ctx:access(binding, span, false)
    return O.Data(self.shape, self.shape:is_copy() and O.Copy or O.ReadBorrow, binding.id)
end
function O.Word:read() return self end
function O.Host:read() return self end
function O.Data:data() return self end
function O.Word:data(span) fail(span, 'expected data, got word') end
function O.Host:data(span) fail(span, 'expected data, got host word') end
function Context:transfer(value, span)
    if O.Data:isclassof(value) and not value.shape:is_copy() and value.mode ~= O.Fresh and value.mode ~= O.Transfer then
        fail(span, 'non-copyable value requires move or a fresh result')
    end
end
function Context:merge(a, a_live, b, b_live)
    for id in pairs(self.initialized) do
        if a_live and b_live then self.initialized[id] = a.initialized[id] and b.initialized[id] or false
        elseif a_live then self.initialized[id] = a.initialized[id]
        elseif b_live then self.initialized[id] = b.initialized[id] end
    end
end
function Context:statements(statements)
    local live = true
    for _, statement in ipairs(statements) do
        if not live then fail(statement.span, 'unreachable statement is not supported in this slice') end
        live = statement:own(self)
    end
    return live
end
function S.Scalar:ownership_value() return O.Data(self.shape, O.Copy) end
function S.Word:ownership_value() return O.Word(self.id, #self.bound) end
function S.Host:ownership_value() return O.Host(self.id) end
function A.Integer:own() return O.Data(S.Int, O.Copy) end
function A.Boolean:own() return O.Data(S.Bool, O.Copy) end
function A.Unit:own() return O.Data(S.Unit, O.Copy) end
function A.Name:own(ctx)
    local binding = ctx:lookup(self.name, self.span)
    return binding.value:read(ctx, binding, self.span)
end
function A.Move:own(ctx)
    local binding = ctx:lookup(self.name, self.span)
    ctx:access(binding, self.span, true)
    if not binding.capability:is_owned() or binding.external then fail(self.span, 'move requires an owning binding: ' .. self.name) end
    local value = binding.value:data(self.span)
    ctx.initialized[binding.id] = false
    return O.Data(value.shape, O.Transfer, binding.id)
end
function A.Borrow:own(ctx)
    local binding = ctx:lookup(self.name, self.span)
    if not binding.capability:is_mutable() then fail(self.span, 'mutable borrow requires a writable binding: ' .. self.name) end
    ctx:access(binding, self.span, true)
    return O.Data(binding.value:data(self.span).shape, O.MutBorrow, binding.id)
end
function A.Unary:own(ctx) self.operand:own(ctx):data(self.span); return O.Data(self.operator == 'not' and S.Bool or S.Int, O.Copy) end
function A.Binary:own(ctx)
    local left = self.left:own(ctx):data(self.span)
    local op = self.operator
    if op == 'and' or op == 'or' then
        local rhs, skipped = ctx:child(false), ctx:child(false)
        self.right:own(rhs):data(self.span)
        ctx:merge(rhs, true, skipped, true)
        return O.Data(S.Bool, O.Copy)
    end
    self.right:own(ctx):data(self.span)
    if (op == '==' or op == '!=') and not left.shape:is_copy() then fail(self.span, 'resource equality requires explicit vocabulary') end
    local comparison = op == '==' or op == '!=' or op == '<' or op == '<=' or op == '>' or op == '>='
    return O.Data(comparison and S.Bool or S.Int, O.Copy)
end
function O.Data:specialize(_, _, span) fail(span, 'specialization requires a word') end
function O.Host:specialize(_, _, span) fail(span, 'host specialization requires a source wrapper') end
function O.Word:specialize(ctx, argument, span)
    local definition = ctx.checker.program.words[self.id]
    local stage = definition.stages[self.supplied + 1]
    if not stage then fail(span, 'oversaturated specialization') end
    if stage.capability == S.Mut then fail(span, 'persistent mutable borrow is forbidden') end
    local value = argument:data(span)
    if not value.shape:is_copy() or stage.capability == S.OwnMut then fail(span, 'persistent owned resource or mutable word state is not supported yet') end
    return O.Word(self.id, self.supplied + 1)
end
function A.Specialize:own(ctx)
    local word = self.word:own(ctx)
    return word:specialize(ctx, self.argument:own(ctx), self.span)
end
function Context:call(stages, supplied, result, arguments, span, tail)
    if #arguments + supplied ~= #stages then fail(span, 'invocation must exactly saturate remaining stages') end
    local acquired = {}
    for i, argument in ipairs(arguments) do
        local stage = stages[supplied + i]
        local cap = stage.capability
        local value = argument:own(self):data(span)
        if cap == S.Mut then
            if value.mode ~= O.MutBorrow then fail(argument.span, 'mut stage requires explicit mut argument') end
        elseif value.mode == O.MutBorrow then fail(argument.span, 'mut argument requires a mut stage') end
        if cap:is_owned() then self:transfer(value, argument.span) end
        local read_borrow = cap == S.Read and not value.shape:is_copy()
        if cap == S.Mut or read_borrow then
            local original = value.mode ~= O.Fresh and value.mode ~= O.Transfer and value.origin or nil
            local binding = original and self.checker.bindings[original] or nil
            if tail and (not binding or not binding.external) then fail(argument.span, 'tail invocation borrow does not outlive caller cleanup') end
            if original then
                if cap == S.Mut then
                    if self.writes[original] or (self.reads[original] or 0) > 0 then fail(argument.span, 'conflicting borrow of ' .. binding.name) end
                    self.writes[original] = true
                else
                    if self.writes[original] then fail(argument.span, 'conflicting borrow of ' .. binding.name) end
                    self.reads[original] = (self.reads[original] or 0) + 1
                end
                acquired[#acquired + 1] = { id = original, capability = cap }
            end
        end
    end
    for _, lock in ipairs(acquired) do
        if lock.capability == S.Mut then self.writes[lock.id] = nil
        else self.reads[lock.id] = self.reads[lock.id] - 1 end
    end
    return O.Data(result, result:is_copy() and O.Copy or O.Fresh)
end
function O.Data:invoke(_, _, span) fail(span, 'invocation requires a runtime word') end
function O.Word:invoke(ctx, arguments, span, tail)
    local definition = ctx.checker.program.words[self.id]
    return ctx:call(definition.stages, self.supplied, definition.signature.result, arguments, span, tail)
end
function O.Host:invoke(ctx, arguments, span, tail)
    local host = ctx.checker.program.hosts[self.id]
    return ctx:call(host.stages, 0, host.result, arguments, span, tail)
end
function A.Invoke:own(ctx) return self.word:own(ctx):invoke(ctx, self.arguments, self.span, false) end
function A.Expr:own_return(ctx) ctx:transfer(self:own(ctx), self.span) end
function A.Invoke:own_return(ctx) self.word:own(ctx):invoke(ctx, self.arguments, self.span, true) end
function A.Data:own_value(ctx) return self.value:own(ctx) end
function A.Body:own_value(_, span) fail(span, 'local word construction is not supported yet') end
function A.Chain:own_value(ctx)
    if #self.items ~= 0 then fail(self.span, 'local word construction is not supported yet') end
    return self.terminal:own_value(ctx, self.span)
end
function A.Binding:own_binding(ctx)
    local value = self.value:own_value(ctx)
    ctx:transfer(value, self.span)
    ctx:bind(self.name, value, self.mutable and S.OwnMut or S.Own, false, self.span)
end
function A.Local:own(ctx) self.binding:own_binding(ctx); return true end
function A.Assign:own(ctx)
    local binding = ctx:lookup(self.name, self.span, true)
    if not binding.capability:is_mutable() then fail(self.span, 'assignment to immutable binding ' .. self.name) end
    local value = self.value:own(ctx)
    ctx:access(binding, self.span, true); ctx:transfer(value, self.span)
    ctx.initialized[binding.id] = true
    return true
end
function A.Return:own(ctx) if self.value then self.value:own_return(ctx) end; return false end
function A.Discard:own(ctx) self.value:own(ctx); return true end
function A.If:own(ctx)
    self.condition:own(ctx)
    local yes, no = ctx:child(true), ctx:child(true)
    local yl, nl = yes:statements(self.yes), no:statements(self.no)
    ctx:merge(yes, yl, no, nl)
    return yl or nl
end
function A.While:own(ctx)
    local before = copy(ctx.initialized)
    self.condition:own(ctx)
    local exit, body = ctx:child(false), ctx:child(true)
    local live = body:statements(self.body)
    if live then
        for id, initialized in pairs(before) do
            if body.initialized[id] ~= initialized then fail(self.span, 'loop backedge must restore initialization of ' .. ctx.checker.bindings[id].name) end
        end
    end
    ctx:merge(exit, true, body, live)
    return true
end
function A.Stage:own_item(ctx, definition, ordinal)
    local shape = definition.signature.parameters[ordinal + 1]
    local borrowed = self.capability == S.Mut or (self.capability == S.Read and not shape:is_copy())
    ctx:bind(self.name, O.Data(shape, shape:is_copy() and O.Copy or O.ReadBorrow), self.capability, borrowed, self.span)
    return ordinal + 1
end
function A.Prelude:own_item(ctx, _, ordinal) self.binding:own_binding(ctx); return ordinal end
function A.Body:own_body(ctx) return ctx:statements(self.statements) end
function Checker:run()
    for id, definition in ipairs(self.program.words) do
        local globals = Context.new(self, {})
        for name, binding in pairs(definition.env) do globals:bind(name, binding.value:ownership_value(), S.Read, true, definition.chain.span) end
        local ctx = globals:child(true)
        local ordinal = 0
        for _, item in ipairs(definition.chain.items) do ordinal = item:own_item(ctx, definition, ordinal) end
        local self_binding = globals:bind(definition.self_name, O.Word(id, 0), S.Read, true, definition.chain.span)
        ctx.initialized[self_binding.id] = true
        definition.chain.terminal:own_body(ctx)
    end
end
return Checker

