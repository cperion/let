-- A template's contract: the interface construction needs before it builds a body.
--
-- Annotations are not a language requirement (§4.1, §6.3), but a host entry needs a concrete
-- parameter type to publish and a self-call needs the word's result type before the return that
-- states it has been built. This pass answers both by reading the terminal body and the
-- preparation regions, so the interface of a template does not depend on the order construction
-- happens to walk it.
--
-- It is deliberately conservative. It records a type only when the source forces exactly one: an
-- operator's other operand is a literal, a host stage declares the parameter, a conversion fixes
-- it, or an immutable alias carries a forced initializer. Anything ambiguous -- `x + y` with no
-- other constraint, `return x` alone, a word-typed stage -- yields no type, and the builder keeps
-- its existing outcome. It never rejects; construction still checks the type it is given.
return function(V)
local A,B=V.AST,V.Belt

local Contract={}

local function numeric(type_) return type_==B.Int or type_==B.Float end

-- The definition a resolved name node refers to, or nil for a literal or an unresolved form.
local function definition_of(resolved,node)
    local references=resolved.references[node]
    local use=references and references[1]
    return use and use.definition
end

-- The concrete belt type a constraint names. `Copy` and `Executable` describe a shape, not a
-- type, so they name none; the builder reports that separately.
local function constraint_type(types,constraint)
    if not constraint then return nil end
    return types[constraint.name]
end

-- One template's contract. `resolved` is the resolve context, `types` the name -> Belt.Type
-- vocabulary (base scalars and registered resources). Returns
-- `{stages = definition -> Belt.Type, result = Belt.Type or nil}`.
function Contract.template(template,resolved,types,environment)
    environment=environment or {}
    local inferred={}      -- stage definition -> Belt.Type, or false once two uses disagree
    local initializer={}   -- immutable-binding definition -> its initializer Chain
    local stated,returns,conflict=nil,0,false

    -- A stage is recorded only once, and only toward one type. A disagreement is a program the
    -- builder will reject anyway, so it just means "no usable type here".
    local function record(definition,type_)
        if not definition or not type_ then return nil end
        local was=inferred[definition]
        if was==nil then inferred[definition]=type_; return type_ end
        if was==false or not was:same(type_) then inferred[definition]=false; return nil end
        return type_
    end

    local function infer_binding(binding)
        -- An initializer fixes the binding's type whether or not it is mutable: assignment
        -- must match that type, so the alias still carries it to a later use.
        local definition=resolved.bindings[binding]
        if definition then initializer[definition]=binding.value end
    end

    local infer, statements

    -- The type of `expr`, recording a forced type on any stage name it reaches. `expected` is
    -- what the surrounding form requires of this expression, or nil when nothing does.
    function infer(expr,expected)
        if not expr then return nil end
        if A.Integer:isclassof(expr) then return B.Int end
        if A.Float:isclassof(expr) then return B.Float end
        if A.Boolean:isclassof(expr) then return B.Bool end
        if A.Text:isclassof(expr) then return B.Text end
        if A.Unit:isclassof(expr) then return B.Unit end
        if A.Name:isclassof(expr) then
            local definition=definition_of(resolved,expr)
            if not definition then return nil end
            if definition.kind=='stage' then
                if expected then return record(definition,expected) end
                local known=inferred[definition]
                return known~=false and known or nil
            end
            -- A capture's type comes from the packet the entry was handed, not from this body.
            local captured=environment[definition]
            if captured then return captured end
            -- `let y = x` is an alias of the same value, so a use of `y` constrains `x`.
            local value=initializer[definition]
            if value and #value.items==0 and A.Data:isclassof(value.terminal) then
                return infer(value.terminal.value,expected)
            end
            return nil
        end
        if A.Move:isclassof(expr) then return infer(expr.place,expected) end
        if A.Unary:isclassof(expr) then
            local operator=expr.operator
            if operator==A.Not then infer(expr.operand,B.Bool); return B.Bool end
            if operator==A.ToFloat then infer(expr.operand,B.Int); return B.Float end
            if operator==A.ToInt then infer(expr.operand,B.Float); return B.Int end
            -- Negate: the operand has the expression's type.
            local type_=infer(expr.operand,expected)
            if type_ then return type_ end
            if numeric(expected) then infer(expr.operand,expected); return expected end
            return nil
        end
        if A.Binary:isclassof(expr) then
            local operator=expr.operator
            if operator==A.And or operator==A.Or then
                infer(expr.left,B.Bool); infer(expr.right,B.Bool); return B.Bool
            end
            if operator==A.Equal or operator==A.NotEqual then
                local type_=expected or infer(expr.left,nil) or infer(expr.right,nil)
                if type_ then infer(expr.left,type_); infer(expr.right,type_) end
                return B.Bool
            end
            -- Comparison and arithmetic both require one numeric type on both sides.
            local type_=(numeric(expected) and expected) or infer(expr.left,nil) or infer(expr.right,nil)
            if type_ and numeric(type_) then infer(expr.left,type_); infer(expr.right,type_) end
            if operator==A.Less or operator==A.LessEqual or operator==A.Greater or operator==A.GreaterEqual then
                return B.Bool
            end
            return type_ and numeric(type_) and type_ or nil
        end
        if A.Invoke:isclassof(expr) and A.Name:isclassof(expr.word) then
            local definition=definition_of(resolved,expr.word)
            if definition and definition.kind=='dictionary' then
                -- The core conversions (§13.3) fix their argument and their result.
                if definition.name=='float' then infer(expr.arguments[1],B.Int); return B.Float end
                if definition.name=='int' then infer(expr.arguments[1],B.Float); return B.Int end
                local host=definition.node
                local signature=host and host.signature
                if signature then
                    for i,argument in ipairs(expr.arguments) do
                        local parameter=signature.parameters[i]
                        if parameter then infer(argument,parameter.type) end
                    end
                    return signature.results[1]
                end
            end
            return nil
        end
        return nil
    end

    local function chain(chain,expected)
        if chain and #chain.items==0 and A.Data:isclassof(chain.terminal) then
            return infer(chain.terminal.value,expected)
        end
        return nil
    end

    -- A return states the result type. Every return must agree; one the pass cannot type is
    -- simply absent, and a returned self-call is the case that stays unknown.
    local function returned(statement)
        returns=returns+1
        local type_
        if statement.value then type_=infer(statement.value,nil) else type_=B.Unit end
        if type_ then
            if stated==nil then stated=type_
            elseif not stated:same(type_) then conflict=true end
        end
    end

    statements=function(list)
        for _,statement in ipairs(list) do
            if A.Local:isclassof(statement) then
                infer_binding(statement.binding); chain(statement.binding.value,constraint_type(types,statement.binding.constraint))
            elseif A.Assign:isclassof(statement) then
                -- The place's type is the expectation for the value, which is how `y = x`
                -- constrains a stage `x` once `y` is typed.
                local place_type=A.Name:isclassof(statement.place) and infer(statement.place,nil) or nil
                local type_=infer(statement.value,place_type)
                if A.Name:isclassof(statement.place) then record(definition_of(resolved,statement.place),type_) end
            elseif A.Return:isclassof(statement) then
                returned(statement)
            elseif A.Discard:isclassof(statement) then
                infer(statement.value,nil)
            elseif A.If:isclassof(statement) then
                infer(statement.condition,B.Bool); statements(statement.yes); statements(statement.no)
            elseif A.While:isclassof(statement) then
                infer(statement.condition,B.Bool); statements(statement.body)
            elseif A.Switch:isclassof(statement) then
                -- Case labels must be Int or Bool literals (§7.2), so a subject that names a
                -- stage takes that type.
                local label_type
                for _,arm in ipairs(statement.cases) do
                    for _,label in ipairs(arm.labels) do
                        if A.Boolean:isclassof(label) then label_type=label_type or B.Bool
                        else label_type=label_type or B.Int end
                    end
                end
                infer(statement.subject,label_type)
                for _,arm in ipairs(statement.cases) do statements(arm.body) end
                statements(statement.otherwise)
            end
        end
    end

    -- The chain items in source order, then the terminal: a prelude may use an earlier stage,
    -- and the terminal may use any of them.
    for _,item in ipairs(template.source.items) do
        if A.Prelude:isclassof(item) then
            infer_binding(item.binding); chain(item.binding.value,constraint_type(types,item.binding.constraint))
        end
    end
    local terminal=template.source.terminal
    local result
    if A.Body:isclassof(terminal) then
        statements(terminal.statements)
        result=conflict and nil or (returns==0 and B.Unit or stated)
    elseif A.Data:isclassof(terminal) then
        infer(terminal.value,nil)
    end

    local stages={}
    for definition,type_ in pairs(inferred) do if type_ then stages[definition]=type_ end end
    return {stages=stages,result=result}
end

return Contract
end
