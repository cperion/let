-- Signature inference uses constructor methods and unification side tables.
-- It annotates neither the source AST nor a mirrored checked AST.
local V = require('let.vocab')
require('let.integer')
local fail = require('let.lexer').fail
local A, S, I, L = V.Syntax, V.Semantic, V.Analysis, V.List
local Solver = {}
Solver.__index = Solver
function Solver.new(program)
    return setmetatable({ program = program, cells = {}, results = {}, parameters = {} }, Solver)
end
function Solver:fresh(shape)
    local id = #self.cells + 1
    self.cells[id] = { parent = id, shape = shape }
    return id
end
function Solver:root(id)
    local cell = self.cells[id]
    if cell.parent ~= id then cell.parent = self:root(cell.parent) end
    return cell.parent
end
function Solver:unify(expected, actual, span, message)
    local a, b = self:root(expected), self:root(actual)
    if a == b then return end
    local x, y = self.cells[a], self.cells[b]
    if x.shape and y.shape and x.shape ~= y.shape then
        fail(span, message or ('expected ' .. x.shape.kind .. ', got ' .. y.shape.kind))
    end
    y.parent = a; x.shape = x.shape or y.shape
end
function Solver:resolved(id, span)
    local shape = self.cells[self:root(id)].shape
    if not shape then fail(span, 'cannot resolve recursive return shape from its uses') end
    return shape
end
local Context = {}
Context.__index = Context
function Context.new(solver, env, result)
    return setmetatable({ solver = solver, env = env, result = result }, Context)
end
function Context:child()
    local child = Context.new(self.solver, setmetatable({}, { __index = self.env }), self.result)
    child.word = self.word; return child
end
function Context:lookup(name, span)
    local value = self.env[name]
    if not value then fail(span, 'unknown name ' .. name) end
    return value
end
function Context:bind(name, value, span)
    if rawget(self.env, name) then fail(span, 'duplicate binding ' .. name) end
    self.env[name] = value
end
function Context:scalar(shape) return I.Scalar(self.solver:fresh(shape)) end
function I.Scalar:scalar() return self.type end
function I.Word:scalar(span) fail(span, 'expected scalar value, got word') end
function Context:require(value, shape, span)
    self.solver:unify(self.solver:fresh(shape), value:scalar(span), span)
end
function Context:annotation(value, annotation, span)
    if not annotation then return end
    local shape = self.solver.program.shapes[annotation]
    if not shape then fail(span, 'unsupported constraint ' .. annotation) end
    self:require(value, shape, span)
end
function Context:return_value(value, span)
    self.solver:unify(self.result, value:scalar(span), span, 'inconsistent return shapes (including Unit fallthrough)')
end
function Context:statements(statements)
    local live = true
    for _, statement in ipairs(statements) do
        if not live then fail(statement.span, 'unreachable statement is not supported in this slice') end
        live = statement:infer(self)
    end
    return live
end
function S.Scalar:abstract(solver) return I.Scalar(solver:fresh(self.shape)) end
function S.Word:abstract() return I.Word(self.id, #self.bound) end
function A.Integer:infer(ctx) self:parts(false); return ctx:scalar(S.Int) end
function A.Boolean:infer(ctx) return ctx:scalar(S.Bool) end
function A.Unit:infer(ctx) return ctx:scalar(S.Unit) end
function A.Name:infer(ctx) return ctx:lookup(self.name, self.span) end
function A.Move:infer(ctx) return ctx:lookup(self.name, self.span) end
function A.Borrow:infer(ctx) return ctx:lookup(self.name, self.span) end
function A.Unary:infer(ctx)
    if self.operator == '-' and A.Integer:isclassof(self.operand) then
        self.operand:parts(true); return ctx:scalar(S.Int)
    end
    local shape = self.operator == 'not' and S.Bool or S.Int
    ctx:require(self.operand:infer(ctx), shape, self.span)
    return ctx:scalar(shape)
end
function A.Binary:infer(ctx)
    local left, right = self.left:infer(ctx), self.right:infer(ctx)
    local op = self.operator
    if op == '==' or op == '!=' then
        ctx.solver:unify(left:scalar(self.span), right:scalar(self.span), self.span)
        return ctx:scalar(S.Bool)
    end
    local logical = op == 'and' or op == 'or'
    local shape = logical and S.Bool or S.Int
    ctx:require(left, shape, self.span); ctx:require(right, shape, self.span)
    local comparison = op == '<' or op == '<=' or op == '>' or op == '>='
    return ctx:scalar((logical or comparison) and S.Bool or S.Int)
end
function I.Scalar:specialize(_, _, span) fail(span, 'specialization requires a word') end
function I.Word:specialize(ctx, argument, span)
    local parameters = ctx.solver.parameters[self.id]
    if self.supplied == #parameters then fail(span, 'oversaturated specialization') end
    ctx.solver:unify(parameters[self.supplied + 1], argument:scalar(span), span)
    return I.Word(self.id, self.supplied + 1)
end
function A.Specialize:infer(ctx)
    local word = self.word:infer(ctx)
    return word:specialize(ctx, self.argument:infer(ctx), self.span)
end
function I.Scalar:invoke(_, _, span) fail(span, 'invocation requires a runtime word') end
function I.Word:invoke(ctx, arguments, span)
    if ctx.word == self.id then ctx.solver.program.words[self.id].recursive = true end
    local parameters = ctx.solver.parameters[self.id]
    if self.supplied + #arguments ~= #parameters then fail(span, 'invocation must exactly saturate remaining stages') end
    for i, argument in ipairs(arguments) do
        ctx.solver:unify(parameters[self.supplied + i], argument:infer(ctx):scalar(span), span)
    end
    return I.Scalar(ctx.solver.results[self.id])
end
function A.Invoke:infer(ctx) return self.word:infer(ctx):invoke(ctx, self.arguments, self.span) end
function A.Chain:infer_value(ctx)
    if #self.items ~= 0 then fail(self.span, 'local word construction is not supported yet') end
    return self.terminal:infer_value(ctx, self.span)
end
function A.Data:infer_value(ctx) return self.value:infer(ctx) end
function A.Body:infer_value(_, span) fail(span, 'local word construction is not supported yet') end
function A.Binding:infer_binding(ctx)
    local value = self.value:infer_value(ctx)
    ctx:annotation(value, self.annotation, self.span)
    if self.mutable then value:scalar(self.span) end
    ctx:bind(self.name, value, self.span)
    if ctx.frame then ctx.frame:insert({ name = self.name, value = value, capability = self.mutable and S.OwnMut or S.Own, span = self.span }) end
end
function A.Local:infer(ctx) self.binding:infer_binding(ctx); return true end
function A.Assign:infer(ctx)
    local left = ctx:lookup(self.name, self.span)
    ctx.solver:unify(left:scalar(self.span), self.value:infer(ctx):scalar(self.span), self.span)
    return true
end
function A.Return:infer(ctx)
    local value = self.value and self.value:infer(ctx) or ctx:scalar(S.Unit)
    ctx:return_value(value, self.span)
    return false
end
function A.Discard:infer(ctx) self.value:infer(ctx); return true end
function A.If:infer(ctx)
    ctx:require(self.condition:infer(ctx), S.Bool, self.span)
    local yes, no = ctx:child():statements(self.yes), ctx:child():statements(self.no)
    return yes or no
end
function A.While:infer(ctx)
    ctx:require(self.condition:infer(ctx), S.Bool, self.span)
    ctx:child():statements(self.body)
    return true
end
function A.Stage:infer_item(ctx, parameters, ordinal)
    local value = I.Scalar(parameters[ordinal + 1])
    ctx:bind(self.name, value, self.span)
    ctx.frame:insert({ name = self.name, value = value, capability = self.capability, span = self.span })
    return ordinal + 1
end
function A.Prelude:infer_item(ctx, _, ordinal)
    self.binding:infer_binding(ctx)
    return ordinal
end
function A.Body:infer_body(ctx) return ctx:statements(self.statements) end
function Solver:run()
    -- Allocate every result variable before visiting bodies: recursive uses
    -- constrain the same variable regardless of source order within the body.
    for id, definition in ipairs(self.program.words) do
        self.results[id] = self:fresh()
        local parameters = L()
        for _, stage in ipairs(definition.stages) do
            local shape = self.program.shapes[stage.annotation or '']
            if not shape then fail(stage.span, 'exported remaining stages require Int, Bool, or Unit annotations') end
            parameters:insert(self:fresh(shape))
        end
        self.parameters[id] = parameters
    end
    for id, definition in ipairs(self.program.words) do
        local outer = {}
        for name, binding in pairs(definition.env) do outer[name] = binding.value:abstract(self) end
        local ctx = Context.new(self, setmetatable({}, { __index = outer }), self.results[id])
        ctx.word = id
        ctx.frame = L(); definition.frame = ctx.frame
        local ordinal = 0
        for _, item in ipairs(definition.chain.items) do ordinal = item:infer_item(ctx, self.parameters[id], ordinal) end
        ctx.frame = nil
        -- The self name is unavailable to its own specialization prelude.
        outer[definition.self_name] = I.Word(id, 0)
        if definition.chain.terminal:infer_body(ctx) then ctx:return_value(ctx:scalar(S.Unit), definition.chain.span) end
    end
    for id, definition in ipairs(self.program.words) do
        local parameters = L()
        for _, parameter in ipairs(self.parameters[id]) do parameters:insert(self:resolved(parameter, definition.chain.span)) end
        definition.signature = S.Signature(parameters, self:resolved(self.results[id], definition.chain.span))
        definition.frame = definition.frame:map(function(field) return field.value:resolve_field(self, field) end)
    end
end
function I.Scalar:resolve_field(solver, field) return S.DataField(solver:resolved(self.type, field.span), field.name, field.capability, field.span) end
function I.Word:resolve_field(_, field) return S.WordField(self.id, self.supplied, field.name, field.capability, field.span) end
function I.Host:resolve_field(_, field) return S.HostField(self.id, field.name, field.capability, field.span) end
return Solver

