-- Signature inference uses constructor methods and unification side tables.
-- It annotates neither the source AST nor a mirrored checked AST.
local V = require('let.vocab')
require('let.integer')
local fail = require('let.lexer').fail
local A, S, I, L = V.Syntax, V.Semantic, V.Analysis, V.List
local Solver = {}
Solver.__index = Solver
function Solver.new(program)
    return setmetatable({ program = program, cells = {}, results = {}, parameters = {}, links = {}, calls = {} }, Solver)
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
    if (x.shape and y.executable) or (y.shape and x.executable) or (x.data_only and y.executable) or (y.data_only and x.executable) then
        fail(span, 'expected scalar data, got Executable (continuation constraint mismatch)')
    end
    y.parent = a; x.shape = x.shape or y.shape
    x.executable=x.executable or y.executable; x.data_only=x.data_only or y.data_only
    self:merge_functions(x,y,span)
end
function Solver:resolved(id, span)
    local shape = self:shape(id,span)
    if not shape:resolved() then fail(span, 'cannot resolve recursive return shape from its uses') end
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
    if annotation=='Executable' then self.solver:callable(value:argument_type(self.solver,span),span); return end
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
        if not live then fail(statement.span, 'unreachable statement is not yet accepted by the compiler') end
        live = statement:infer(self)
    end
    return live
end
function S.Scalar:abstract(solver) return I.Scalar(solver:fresh(self.shape)) end
function S.Word:abstract(solver)
    local span=solver.program.words[self.id].chain.span
    for i,value in ipairs(self.bound) do solver:unify(solver.parameters[self.id][i],value:abstract(solver):argument_type(solver,span),span) end
    return I.Word(self.id,#self.bound)
end
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
function I.Word:specialize(ctx, argument, span)
    local parameters = ctx.solver.parameters[self.id]
    if self.supplied == #parameters then fail(span, 'oversaturated specialization') end
    ctx.solver:unify(parameters[self.supplied + 1], argument:argument_type(ctx.solver,span), span)
    return I.Word(self.id, self.supplied + 1)
end
function A.Specialize:infer(ctx)
    local word = self.word:infer(ctx)
    return word:specialize(ctx, self.argument:infer(ctx), self.span)
end
function I.Word:invoke(ctx, arguments, span)
    ctx.solver.calls[#ctx.solver.calls+1]={caller=ctx.word,word=self.id}
    local parameters = ctx.solver.parameters[self.id]
    if self.supplied + #arguments ~= #parameters then fail(span, 'invocation must exactly saturate remaining stages') end
    for i, argument in ipairs(arguments) do
        ctx.solver:unify(parameters[self.supplied + i], argument:infer(ctx):argument_type(ctx.solver,span), span)
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
    if self.mutable then
        local cell=ctx.solver.cells[ctx.solver:root(value:scalar(self.span))]
        if cell.executable then fail(self.span,'mutable continuation bindings are not supported') end
        cell.data_only=true
    end
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
function A.Switch:infer(ctx) return ctx:child():statements(self.body) end
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
            if stage.annotation and stage.annotation~='Executable' and not shape then fail(stage.span,'unsupported constraint ' .. stage.annotation) end
            local parameter=self:fresh(shape)
            if stage.annotation=='Executable' then self:callable(parameter,stage.span) end
            parameters:insert(parameter)
        end
        self.parameters[id] = parameters
    end
    for _,export in ipairs(self.program.exports) do export.word:abstract(self) end
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
    self:link_suffixes()
    for id, definition in ipairs(self.program.words) do
        local parameters=L(); local generic=false
        for i,parameter in ipairs(self.parameters[id]) do
            local shape=self:shape(parameter,definition.chain.span)
            if S.Executable:isclassof(shape) then
                generic=true
                if definition.stages[i].capability:is_mutable() then fail(definition.stages[i].span,'mutable continuation stages are not supported') end
            elseif not definition.stages[i].annotation then fail(definition.stages[i].span,'exported remaining stages require Int, Bool, or Unit annotations') end
            parameters:insert(shape)
        end
        local result=generic and self:shape(self.results[id],definition.chain.span) or self:resolved(self.results[id],definition.chain.span)
        if S.Executable:isclassof(result) then fail(definition.chain.span,'returned words are not supported yet') end
        definition.signature=S.Signature(parameters,result)
        definition.frame=definition.frame:map(function(field) return field.value:resolve_field(self,field) end)
    end
    self:recursion()
    local exports=L(); self.program.templates=L()
    for _,export in ipairs(self.program.exports) do
        local def=self.program.words[export.word.id]; local native=true
        for i=#export.word.bound+1,#def.stages do if S.Executable:isclassof(def.signature.parameters[i]) then native=false end end
        if native then
            if not def.signature.result:resolved() then fail(export.span,'cannot resolve recursive return shape from its uses') end
            exports:insert(export)
        else self.program.templates:insert(export) end
    end
    self.program.exports=exports
end
function I.Scalar:resolve_field(solver,field)
    local shape=solver:shape(self.type,field.span)
    local ctor=S.Executable:isclassof(shape) and S.ContinuationField or S.DataField
    return ctor(shape,field.name,field.capability,field.span)
end
function I.Word:resolve_field(_, field) return S.WordField(self.id, self.supplied, field.name, field.capability, field.span) end
function I.Host:resolve_field(_, field) return S.HostField(self.id, field.name, field.capability, field.span) end
require('let.callable').install(Solver)
return Solver

