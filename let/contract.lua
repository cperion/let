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
-- it, a word-valued callee's stage declares it, an aggregate member that the surrounding type
-- matches, or an alias carries a forced initializer. Anything ambiguous -- `x + y` with no other
-- constraint, `return x` alone, a word-typed stage with no call -- yields no type, and the
-- builder keeps its existing outcome. It never rejects; construction still checks what it is
-- given.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local scalar=require('let.scalar')

local Contract={}

local function numeric(type_) return type_==B.Int or type_==B.Float end

-- The definition a resolved name node refers to, or nil for a literal or an unresolved form.
local function definition_of(resolved,node)
    local references=resolved.references[node]
    local use=references and references[1]
    return use and use.definition
end

-- The concrete belt type a declared type word names. An unknown name names none; the builder
-- reports that separately.
local function constraint_type(types,constraint)
    if not constraint then return nil end
    return types[constraint.name]
end

-- A written integer index, or nil when the index is only known at run time. `-7` is a unary
-- negation of a literal, so both spellings are recognized (§2.2).
local function static_index(expr)
    local negative=A.Unary:isclassof(expr) and expr.operator==A.Negate
    local operand=negative and expr.operand or expr
    if not A.Integer:isclassof(operand) then return nil end
    local value=tonumber(scalar.integer(operand.spelling,function(message) error(message,0) end))
    return negative and -value or value
end

-- One template's contract, computed once per template. A cycle returns no interface rather than
-- recursing: a word that calls itself through another word simply keeps the conservative outcome.
local memo=setmetatable({},{__mode='k'})

local function compute(template,resolved,types,environment)
    local initializer={}   -- binding definition -> its initializer Chain
    local stated,returns,conflict=nil,0,false

    local function infer_binding(binding)
        -- An initializer fixes the binding's type whether or not it is mutable: assignment
        -- must match that type, so the alias still carries it to a later use.
        local definition=resolved.bindings[binding]
        if definition then initializer[definition]=binding.value end
    end

    local infer, statements, chain

    -- The template a callee names, when the callee is a word rather than a data value. A
    -- specialization (`let double = scale 2`) has a data terminal and no stages of its own, so
    -- its remaining stages are not visible here and it yields no interface.
    local function callee_template(definition)
        local callee=definition and definition.template
        if not callee then return nil end
        if #callee.steps==0 and not A.Body:isclassof(callee.source.terminal) then return nil end
        return callee
    end

    -- The stage type a callee's argument fills. `index` is the 1-based stage position.
    local function callee_stage(callee,contract,index)
        local step=callee.steps[index]
        if not step then return nil end
        return constraint_type(types,step.stage.constraint)
    end

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
                -- §11.3: a stage's type is its declared type word; there is no inference.
                return constraint_type(types,definition.node and definition.node.constraint)
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
        -- A record the surrounding type already describes: each member takes the member type.
        if A.PositionalAggregate:isclassof(expr) then
            local wanted=expected and expected:record()
            local declared,complete,copy=L(),true,true
            for i,element in ipairs(expr.elements) do
                local type_=chain(element,wanted and wanted[i] and wanted[i].type)
                if not type_ then complete=false
                else
                    declared:insert(B.Field(nil,type_,false))
                    if not type_:copyable() then copy=false end
                end
            end
            if not complete then return nil end
            return B.Aggregate(declared,copy,nil)
        end
        if A.NamedAggregate:isclassof(expr) then
            local wanted=expected and expected:record()
            local declared,complete,copy=L(),true,true
            for _,member in ipairs(expr.members) do
                local member_type
                if wanted then for _,field in ipairs(wanted) do if field.name==member.name then member_type=field.type end end end
                local type_=constraint_type(types,member.constraint) or chain(member.value,member_type)
                if not type_ then complete=false
                else
                    declared:insert(B.Field(member.name,type_,member.mutable))
                    if member.mutable or not type_:copyable() then copy=false end
                end
            end
            if not complete then return nil end
            return B.Aggregate(declared,copy,nil)
        end
        if A.Project:isclassof(expr) then
            local base=infer(expr.base,nil)
            local fields=base and base:record()
            if fields then
                for _,field in ipairs(fields) do if field.name==expr.name then return field.type end end
            end
            return nil
        end
        if A.Index:isclassof(expr) then
            local base=infer(expr.base,nil)
            local fields=base and base:record()
            if not fields then return nil end
            local index=static_index(expr.index)
            if index then
                local field=fields[index+1]
                return field and field.type or nil
            end
            -- A run-time index yields one value, so the members must share one type.
            infer(expr.index,B.Int)
            local element=fields[1] and fields[1].type
            for i=2,#fields do if not fields[i].type:same(element) then return nil end end
            return element
        end
        -- A named callee: a conversion, a registered host, or a word whose contract types the
        -- arguments. A word's own result type is known when its contract could compute one.
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
                return nil
            end
            local callee=callee_template(definition)
            if not callee then return nil end
            local contract=Contract.template(callee,resolved,types,nil)
            for i,argument in ipairs(expr.arguments) do infer(argument,callee_stage(callee,contract,i)) end
            return contract.result
        end
        -- Juxtaposition: a conversion, or the next stage of a word. The result is the more
        -- specific word value, whose type this pass does not model.
        if A.Specialize:isclassof(expr) and A.Name:isclassof(expr.word) then
            local definition=definition_of(resolved,expr.word)
            if definition and definition.kind=='dictionary' then
                if definition.name=='float' then infer(expr.argument,B.Int); return B.Float end
                if definition.name=='int' then infer(expr.argument,B.Float); return B.Int end
                return nil
            end
            local callee=callee_template(definition)
            if callee then
                local contract=Contract.template(callee,resolved,types,nil)
                infer(expr.argument,callee_stage(callee,contract,1))
            end
            return nil
        end
        return nil
    end

    function chain(chain,expected)
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
        -- §11.3: a declared `do : T` states the result; it drives callee typing and, through
        -- the entry, is checked against every return. Only a name-form type word is lowered
        -- here; the structural forms arrive with the vocabulary in the build step.
        if terminal.result then
            local declared=constraint_type(types,terminal.result)
            if declared then result=declared end
        end
    elseif A.Data:isclassof(terminal) then
        -- §11.2: a data terminal's type is the type of its terminal expression. That is the
        -- word's result, which is what a `let`-bound word named as a type denotes.
        result=infer(terminal.value,nil)
        -- An aggregate of stages is a constructor: its record carries the constructor's
        -- binding name, so the type is nominal and matches the values the constructor builds.
        if result and A.NamedAggregate:isclassof(terminal.value) and terminal.value.nominal then
            local fields=result:record()
            if fields then result=B.Aggregate(fields,result:copyable(),template.name) end
        end
    end

    return {stages={},result=result}
end

-- A template's contract. `environment` maps a binding to the type the entry packet gave it, so
-- the result a return states can be computed where those types are known. A contract computed
-- without one is remembered, because it describes the template rather than one packet.
function Contract.template(template,resolved,types,environment)
    local general=environment==nil or next(environment)==nil
    if general then
        local cached=memo[template]
        if cached==false then return {stages={},result=nil} end
        if cached then return cached end
        memo[template]=false
    end
    local contract=compute(template,resolved,types,environment or {})
    if general then memo[template]=contract end
    return contract
end

return Contract
end
