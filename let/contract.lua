-- Judge.Resolved -> Judge.Program (DESIGN §12.2, §S25).
--
-- Contract **checks** rather than infers. Spec §3.1 and §11.3 require a stage to declare its type
-- word and a runtime terminal to state its result, and "reading a type off a term is not
-- inference": no type unknown is solved. So it reads a type off each declaration and checks every
-- use against it.
--
-- **A word value's type is nominal**: `Semantic.Word(template, prefix)`, where the prefix counts the
-- stages already supplied. That is what §S3 requires -- if `square` and `cube` shared a type, a
-- word-typed stage would admit either and the callee would need a uniform calling convention, which
-- is a vtable. So a reference to a word is `Word(id, 0)`, and an application either consumes the
-- last stage (yielding the terminal's type) or leaves `Word(id, prefix + 1)`.
--
-- Every definition gets an interface, value bindings included, because a data terminal with no
-- stages *is* a value (spec §11.1): the interface is a zero-stage data word.
--
-- `same` is deliberately identity here (`~=`): the primitive types are ASDL singletons, so identity
-- *is* structural equality. A structural `same` arrives with aggregates.
return function(V)
    local Syntax, Semantic, Chain, Judge, Report, L =
        V.Syntax, V.Semantic, V.Chain, V.Judge, V.Report, V.List

    local Contract = {}

    -- The stage items of a template, in order.
    local function stages_of(template)
        local stages = {}
        for _, item in ipairs(template.items) do
            if Chain.Stage:isclassof(item) then stages[#stages + 1] = item end
        end
        return stages
    end

    function Contract.run(unit, resolved, k_ok, k_diag)
        -- Declared here and assigned below, because the checks ask it and the table it needs is built
        -- after them -- the same shape `borrow_of` has.
        local copyable
        local names, declarations, types, typed = {}, {}, {}, L()
        for _, definition in ipairs(resolved.definitions) do
            names[definition.id] = definition.name
            declarations[definition.id] = definition.declaration
        end

        local diagnostic
        -- The FIRST failure is the one that matters. Once an interface cannot be built, everything
        -- that depends on it fails too -- so keeping the last would report a CONSEQUENCE and name
        -- the wrong thing. This is the difference between "`s.Text` is not an alternative" and "the
        -- function that mentions it does not return the right type", and only one of them is useful.
        local function fail(d)
            diagnostic = diagnostic or d
            return nil
        end

        -- The binding a destination place starts at, with its declaration. §3.4's writability is
        -- a property of that binding, so this is the one place the question is answered -- a
        -- projection or an index inherits it from its base rather than restating it.
        local function root_of(place)
            if Judge.Reference:isclassof(place) then return declarations[place.definition] end
            if Judge.Project:isclassof(place) then return root_of(place.base) end
            if Judge.Index:isclassof(place) or Judge.Element:isclassof(place) then
                return root_of(place.base)
            end
            return nil
        end

        -- Forward declarations: `type_of` asks for a definition's interface, and computing that
        -- interface asks `type_of` for the term a declaration is built from. The cycle is the point --
        -- and it is why the interface is PUBLISHED before a body is checked (§S74), so there is no
        -- cycle stack and nothing to re-enter -- so both are declared before either is used.
        -- The type words by NAME, built from DECLARATIONS rather than interfaces -- §S52's rule --
        -- because a declaration owns its fact and the interface may not be computed yet. This is what
        -- lets a sum's alternative be named, which is what a projection on a sum is (§S54).
        local word_by_name = {}
        for name, type_ in pairs(Semantic.primitive) do word_by_name[name] = type_ end
        for _, definition in ipairs(resolved.definitions) do
            local declaration = definition.declaration
            if Judge.Type:isclassof(declaration) then
                word_by_name[definition.name] = declaration.denotes
            elseif Judge.Host:isclassof(declaration) then
                word_by_name[definition.name] = Semantic.Named(definition.name)
            end
        end

        -- §3.5 says a value whose type equals exactly ONE alternative of a sum is INJECTED into it.
        -- So the question a site asks when a value meets an expected type is not "equal" but "equal
        -- OR injectable" -- and it is ONE rule, asked at every such site: a stage argument, a
        -- binding, a return, an assignment, a record member. Asking `equals` at each of them is how
        -- a sum-typed stage came to refuse the very values it exists to hold.
        -- §3.6's table, for the ONE row that is refused where the argument is supplied. The other
        -- three are decidable and fine: a literal is static storage that outlives every view, a place
        -- outlives the view as long as the view stays inside its scope (which is where an escape is
        -- caught), and a HOST call's result is foreign -- "the host's contract; Let holds nothing and
        -- checks nothing". Everything else is a temporary, and a view of a temporary outlives nothing.
        -- Being narrow here is the point: a row that refuses too much calls a correct program wrong,
        -- which is worse than a row that is not yet checked at all.
        local borrow_of

        -- §3.2: a capture is a second NAME for somebody else's storage, so asking what a name denotes
        -- has to follow it to the binding it captures -- exactly as `word_of` does in `Lower`. Without
        -- this, a host word a chain captures stops looking like a host word, and §3.6's foreign row
        -- silently becomes the temporary row: a correct program refused, which is the one outcome a
        -- check must never produce. Note that this does NOT answer `chain_owned`, which needs the
        -- capture to be visible AS a capture rather than followed.
        local function declaration_of(definition)
            local declaration = declarations[definition]
            while declaration and Judge.Value:isclassof(declaration)
                    and Judge.Reference:isclassof(declaration.value) do
                declaration = declarations[declaration.value.definition]
            end
            return declaration
        end

        local function check_borrowed_storage(interface, at, argument, span)
            if not interface.borrowed then return true end
            if borrow_of(interface.result) ~= at then return true end
            if Judge.Literal:isclassof(argument) then return true end
            if Judge.Reference:isclassof(argument) or Judge.Project:isclassof(argument)
                    or Judge.Index:isclassof(argument) or Judge.Element:isclassof(argument) then
                return true
            end
            local callee = nil
            if Judge.Apply:isclassof(argument) or Judge.Invoke:isclassof(argument) then
                callee = argument.callee
            end
            if callee and Judge.Reference:isclassof(callee) then
                local declaration = declaration_of(callee.definition)
                if declaration and Judge.Word:isclassof(declaration)
                        and Chain.Host:isclassof(declaration.word.terminal) then
                    return true
                end
            end
            return fail(Report.reject(Report.BorrowOfTemporary, span))
        end

        local function accepts(expected, actual)
            if expected:equals(actual) then return true end
            if not Semantic.Sum:isclassof(expected) then return false end
            local index, count = expected:alternative(actual)
            return index ~= nil and count == 1
        end

        local type_of, interface_of
        type_of = function(initializer)
            if Judge.Literal:isclassof(initializer) then
                local expr = initializer.value
                if Syntax.Integer:isclassof(expr) then return Semantic.Int end
                if Syntax.Unit:isclassof(expr) then return Semantic.Unit end
                if Syntax.Boolean:isclassof(expr) then return Semantic.Bool end
                if Syntax.Text:isclassof(expr) then return Semantic.Text end
                -- §11.3's `Float`: a float literal's type is its own form, the same rule the other
                -- literals follow. It was declared in every layer and produced by none, so `Float` and
                -- `Float32` were unwritable -- a type nothing can name a value of.
                if Syntax.Float:isclassof(expr) then return Semantic.Float end
                return fail(Report.bug(Report.NoLowering('literal'), expr.span))
            end

            if Judge.Reference:isclassof(initializer) then
                -- A word name denotes the *word value*, not its result, so its type is the whole
                -- arrow spine at prefix 0 -- spec §11.1 read through §S3's nominality.
                if Judge.Word:isclassof(declarations[initializer.definition]) then
                    return Semantic.Word(initializer.definition, 0)
                end
                -- Asked for, not read: `interface_of` computes it on demand, so a stage whose
                -- owning word has not been reached yet is no longer a hole.
                local interface = interface_of(initializer.definition)
                if not interface then return nil end
                return interface.result
            end

            if Judge.Apply:isclassof(initializer) then
                local callee = type_of(initializer.callee)
                if not callee then return nil end
                if not Semantic.Word:isclassof(callee) then
                    return fail(Report.reject(Report.NotExecutable, initializer.span))
                end
                local stages = stages_of(declarations[callee.template].word)
                local at = callee.prefix + 1
                if at > #stages then
                    return fail(Report.reject(Report.Oversaturated, initializer.span))
                end
                local argument = type_of(initializer.argument)
                if not argument then return nil end
                if not accepts(stages[at].type, argument) then
                    return fail(Report.reject(Report.MismatchedType, initializer.span))
                end
                local interface = interface_of(callee.template)
                if not interface then return nil end
                if not check_borrowed_storage(interface, at, initializer.argument, initializer.span) then
                    return nil
                end
                if at == #stages then return interface.result end
                return Semantic.Word(callee.template, at)
            end

            -- §3.4 and §1.5/§1.5: operators have no implicit conversions, so every rule is a
            -- statement about operand types. Arithmetic and bitwise are Int -> Int, comparisons are
            -- Int -> Bool, and `and`/`or` are Bool -> Bool. `not` is the one unary Bool.
            if Judge.Unary:isclassof(initializer) then
                local operand = type_of(initializer.operand)
                if not operand then return nil end
                local operator = initializer.operator
                if operator == Semantic.Not then
                    if not operand:equals(Semantic.Bool) then
                        return fail(Report.reject(Report.MismatchedType, initializer.span))
                    end
                    return Semantic.Bool
                end
                if not operand:equals(Semantic.Int) then
                    return fail(Report.reject(Report.MismatchedType, initializer.span))
                end
                return Semantic.Int
            end
            if Judge.Binary:isclassof(initializer) then
                local left = type_of(initializer.left)
                if not left then return nil end
                local right = type_of(initializer.right)
                if not right then return nil end
                local operator = initializer.operator
                if operator == Semantic.And or operator == Semantic.Or then
                    if not left:equals(Semantic.Bool) or not right:equals(Semantic.Bool) then
                        return fail(Report.reject(Report.MismatchedType, initializer.span))
                    end
                    return Semantic.Bool
                end
                if not left:equals(Semantic.Int) or not right:equals(Semantic.Int) then
                    return fail(Report.reject(Report.MismatchedType, initializer.span))
                end
                if operator == Semantic.Equal or operator == Semantic.NotEqual
                    or operator == Semantic.Less or operator == Semantic.LessEqual
                    or operator == Semantic.Greater or operator == Semantic.GreaterEqual then
                    return Semantic.Bool
                end
                return Semantic.Int
            end

            -- §1.2: invocation is transient saturation, so it must reach the terminal. An
            -- invocation that stops short is undersaturated -- the residual would be a temporary,
            -- and a temporary is not a value (§1.2), so there is nothing to give a type to.
            if Judge.Invoke:isclassof(initializer) then
                local callee = type_of(initializer.callee)
                if not callee then return nil end
                if not Semantic.Word:isclassof(callee) then
                    return fail(Report.reject(Report.NotExecutable, initializer.span))
                end
                local stages = stages_of(declarations[callee.template].word)
                local interface = interface_of(callee.template)
                if not interface then return nil end
                local at = callee.prefix
                for _, argument in ipairs(initializer.arguments) do
                    local argument_type = type_of(argument)
                    if not argument_type then return nil end
                    if at + 1 > #stages then
                        return fail(Report.reject(Report.Oversaturated, initializer.span))
                    end
                    if not accepts(stages[at + 1].type, argument_type) then
                        return fail(Report.reject(Report.MismatchedType, initializer.span))
                    end
                    if not check_borrowed_storage(interface, at + 1, argument, initializer.span) then
                        return nil
                    end
                    at = at + 1
                end
                if at < #stages then
                    return fail(Report.reject(Report.Undersaturated, initializer.span))
                end
                return interface_of(callee.template).result
            end

            -- Naming the class is what makes an unhandled form actionable instead of a search.
            local class = getmetatable(initializer)
            -- A move's type is the place's type: `move` transfers a value, it does not make one.
            if Judge.Move:isclassof(initializer) then
                -- A place is a name, a member or a constant index; anything else is a value, and a
                -- value is not something a move can take.
                local place = initializer.place
                if not (Judge.Reference:isclassof(place) or Judge.Project:isclassof(place)
                        or Judge.Index:isclassof(place) or Judge.Element:isclassof(place)) then
                    return fail(Report.reject(Report.ReadOnlyDestination, initializer.span))
                end
                return type_of(initializer.place)
            end

            -- A projection's type is the member's, read off the base. A RECORD's member is a field
            -- and its type is right there. A SUM has no members -- it has ALTERNATIVES, and an
            -- alternative is reached by the arm that MATCHED it (§S59), so `s.Int` is not a
            -- program: there is no way to ask for a payload without having established which
            -- alternative is there, which is exactly why a payload read cannot fail.
            if Judge.Project:isclassof(initializer) then
                local base = type_of(initializer.base)
                if not base then return nil end
                if Semantic.Sum:isclassof(base) then
                    return fail(Report.reject(Report.UnknownName, initializer.span))
                end
                if not Semantic.Aggregate:isclassof(base) then
                    return fail(Report.reject(Report.UnknownName, initializer.span))
                end
                for _, field in ipairs(base.fields) do
                    if field.name == initializer.name then return field.type end
                end
                return fail(Report.reject(Report.UnknownName, initializer.span))
            end

            -- §3.3: indexing a positional place yields an element place. The index is constant,
            -- so an out-of-range one is a diagnostic rather than a runtime trap.
            if Judge.Element:isclassof(initializer) then
                -- §12.1's derivation: `a[i]` with a RUNTIME `i` has one type only if every member of
                -- the aggregate has that type -- the offset names one of them and the compiler cannot
                -- know which, so a mixed tuple is a `MismatchedType` rather than a hole. It is the same
                -- question §3.5 asks of a sum's alternatives, asked of a record's members.
                local base = type_of(initializer.base)
                if not base then return nil end
                local index = type_of(initializer.index)
                if not index then return nil end
                if not index:equals(Semantic.Int) then
                    return fail(Report.reject(Report.MismatchedType, initializer.span))
                end
                if not Semantic.Aggregate:isclassof(base) or #base.fields == 0 then
                    return fail(Report.reject(Report.IndexOutOfRange, initializer.span))
                end
                local element = base.fields[1].type
                for _, field in ipairs(base.fields) do
                    if not field.type:equals(element) then
                        return fail(Report.reject(Report.MismatchedType, initializer.span))
                    end
                end
                return element
            end
            if Judge.Index:isclassof(initializer) then
                local base = type_of(initializer.base)
                if not base or not Semantic.Aggregate:isclassof(base) then
                    return fail(Report.reject(Report.IndexOutOfRange, initializer.span))
                end
                local field = base.fields[initializer.offset + 1]
                if not field then
                    return fail(Report.reject(Report.IndexOutOfRange, initializer.span))
                end
                return field.type
            end

            if Judge.Aggregate:isclassof(initializer) then
                local fields = L()
                for _, member in ipairs(initializer.members) do
                    local type_ = type_of(member.value)
                    if not type_ then return nil end
                    -- §3.7: a member's mutability is part of the record's *type*, not of how the
                    -- member was supplied, which is why it lands on the field.
                    fields:insert(Semantic.Field(member.name, type_, member.mutable))
                end
                return Semantic.Aggregate(fields, nil)
            end

            return fail(Report.bug(Report.NoLowering('initializer ' .. tostring(class and class.kind)),
                resolved.definitions[1].span))
        end

        -- §11.3: "a runtime terminal `do : R` is checked against every `return`", and a discarded
        -- value is dropped, so it must be Copy -- a destruction is an ownership action, and a
        -- discarded expression's required destruction stays observable (§7.3).
        -- §7.2: a condition is `Bool` -- "there is no implicit truthiness" (§12.3).
        -- §12.2's label identity. A label must be a literal, and two labels collide by VALUE
        -- than by spelling -- which is why this returns a key rather than comparing text.
        -- §S60: a label is a SHAPE or a CONSTANT, and which one it is is what the label SAYS. That
        -- is the difference from §S51 -- which read a label as an expression and therefore had to
        -- ask what a NAME denoted -- and it is why nothing below reads a declaration.
        --
        -- A SHAPE must be an alternative of a sum subject. A CONSTANT must be a literal of the
        -- subject's own type, and two constants collide by VALUE rather than by spelling: `1` and
        -- `0x1` are one label. Either way the key is what the label MEANS, and a repeat is a
        -- rejection rather than a silent second arm.
        local function case_key(label, subject)
            if Judge.Shape:isclassof(label) then
                if not Semantic.Sum:isclassof(subject) then return nil end
                for index, alternative in ipairs(subject.alternatives) do
                    if alternative:equals(label.denotes) then
                        return 'alt:' .. tostring(index - 1), index - 1
                    end
                end
                return nil
            end
            -- A CONSTANT label: a literal of the subject's own type, keyed by VALUE.
            local constant = label.value
            if not Judge.Literal:isclassof(constant) then return nil end
            local label_type = type_of(constant)
            if not label_type or not label_type:equals(subject) then return nil end
            local expr = constant.value
            if Syntax.Integer:isclassof(expr) then
                return 'Int:' .. tostring(Semantic.integer_value(expr.spelling))
            end
            if Syntax.Boolean:isclassof(expr) then return 'Bool:' .. tostring(expr.value) end
            return nil
        end

        local function check_condition(condition, span)
            local type_ = type_of(condition)
            if not type_ then return nil end
            if type_ ~= Semantic.Bool then
                return fail(Report.reject(Report.MismatchedType, span))
            end
            return true
        end

        -- Whether a statement list GUARANTEES an exit. A syntactic approximation, and the honest
        -- one: a `while` may not run and an `if` without an `else` may fall through, so neither
        -- terminates on its own -- which is exactly §12.3's "falling through the end returns Unit".
        -- Only the body's own list is asked; an arm that falls through merely continues after the
        -- `if`, so termination is not a property of an arm.
        local function terminates(statements)
            local last = statements[#statements]
            if not last then return false end
            if Judge.Return:isclassof(last) then return true end
            if Judge.If:isclassof(last) then
                return #last.no > 0 and terminates(last.yes) and terminates(last.no)
            end
            -- An arm that does not match falls through to after the switch, so a `switch`
            -- terminates only when every value is caught -- an `else`, or a Bool subject whose
            -- labels are `true` and `false`, which the spec calls exhaustive. Without this the
            -- statement below a `switch` looks like a fall-through and the word is rejected.
            if Judge.Switch:isclassof(last) then
                local every_arm = true
                local seen = {}
                -- `case_key` needs the subject's type, because what a label may be follows from it
                -- (§S51): a constant for a scalar subject, an alternative for a sum one.
                local subject_type = type_of(last.subject)
                for _, arm in ipairs(last.cases) do
                    if not terminates(arm.body) then every_arm = false end
                    for _, label in ipairs(arm.labels) do
                        local key = subject_type and case_key(label, subject_type)
                        if key then seen[key] = true end
                    end
                end
                if not every_arm then return false end
                if #last.otherwise > 0 then return terminates(last.otherwise) end
                -- Exhaustive means every VALUE is caught, and what that takes depends on the
                -- subject. A SUM always holds one of its alternatives, so labelling all of them is
                -- exhaustive -- which is the mirror of the Bool rule below, and the reason a sum
                -- `switch` can be a word's whole body.
                if subject_type and Semantic.Sum:isclassof(subject_type) then
                    local labelled = 0
                    for key in pairs(seen) do
                        if key:sub(1, 4) == 'alt:' then labelled = labelled + 1 end
                    end
                    return labelled == #subject_type.alternatives
                end
                if not subject_type or not subject_type:equals(Semantic.Bool) then return false end
                return seen['Bool:true'] and seen['Bool:false'] and true or false
            end
            return false
        end

        -- Every `return` is checked against the stated result, wherever it sits (§11.3, §7.2).
        -- §3.6's containment row -- "the view's scope must be inside the owner's" -- compares two
        -- SCOPES, and the fact that decides which scope the owner lives in is already in source. A
        -- `Judge.Bound` is a stage the CALLER supplies and a capture reaches storage the enclosing
        -- instance owns (a module prelude is one, because §S76 made it a capture), while a
        -- `Judge.Value` with its own initializer is a PRELUDE of the chain being lowered, which dies
        -- when the chain returns. So this READS A DECLARATION instead of carrying a lifetime, which is
        -- what §1.4 means by "every extent is a construct the compiler already computes".
        local function chain_owned(declaration)
            if not declaration or not Judge.Value:isclassof(declaration) then return false end
            return not Judge.Reference:isclassof(declaration.value)
        end

        -- §3.1 rule 4, on VALUES: a borrow travels with the value, so a view made from this chain's
        -- storage is still this chain's once it is bound, moved, projected or put in an aggregate. The
        -- answer is read from DECLARATIONS and never accumulated while a body is walked, so it cannot
        -- depend on the order the checks happen to run in.
        local function borrows_chain_storage(initializer)
            if initializer == nil then return false end
            if Judge.Reference:isclassof(initializer) then
                local declaration = declarations[initializer.definition]
                if declaration and Judge.Value:isclassof(declaration) then
                    return borrows_chain_storage(declaration.value)
                end
                return false
            end
            if Judge.Project:isclassof(initializer) or Judge.Index:isclassof(initializer)
                    or Judge.Element:isclassof(initializer) then
                return borrows_chain_storage(initializer.base)
            end
            if Judge.Move:isclassof(initializer) then
                return borrows_chain_storage(initializer.place)
            end
            if Judge.Aggregate:isclassof(initializer) then
                for _, member in ipairs(initializer.members) do
                    if borrows_chain_storage(member.value) then return true end
                end
                return false
            end
            -- The call that MAKES the view. §3.6's index names the storage it views, so this is where
            -- a view of a chain-owned place is born -- and it is the only place, because the core has
            -- no view type and only a host declaration can name a borrow.
            if Judge.Apply:isclassof(initializer) or Judge.Invoke:isclassof(initializer) then
                local callee = type_of(initializer.callee)
                if not callee or not Semantic.Word:isclassof(callee) then return false end
                local interface = interface_of(callee.template)
                if not interface or not interface.borrowed then return false end
                local index = borrow_of(interface.result)
                if not index then return false end
                local argument
                if Judge.Apply:isclassof(initializer) then
                    if index == callee.prefix + 1 then argument = initializer.argument end
                else
                    argument = initializer.arguments[index - callee.prefix]
                end
                if not argument then return false end
                return chain_owned(root_of(argument))
            end
            return false
        end

        local function check_body(statements, result)
            for _, statement in ipairs(statements) do
                if Judge.Return:isclassof(statement) then
                    local value = statement.value and type_of(statement.value) or Semantic.Unit
                    if not value then return nil end
                    if not value:equals(result) then
                        return fail(Report.reject(Report.MismatchedType, statement.span))
                    end
                    -- §3.1 rule 3: "no use may place it in a longer-lived position". A return is the
                    -- way out of a chain, so a view of this chain's own storage that leaves here
                    -- outlives what it views.
                    if borrows_chain_storage(statement.value) then
                        return fail(Report.reject(Report.BorrowedEscapes, statement.span))
                    end
                elseif Judge.Discard:isclassof(statement) then
                    local value = type_of(statement.value)
                    if not value then return nil end
                    if not copyable(value) then
                        return fail(Report.reject(Report.NeedsMove, statement.span))
                    end
                elseif Judge.If:isclassof(statement) then
                    if not check_condition(statement.condition, statement.span) then return nil end
                    if not check_body(statement.yes, result) then return nil end
                    if not check_body(statement.no, result) then return nil end
                elseif Judge.While:isclassof(statement) then
                    if not check_condition(statement.condition, statement.span) then return nil end
                    if not check_body(statement.body, result) then return nil end
                elseif Judge.Switch:isclassof(statement) then
                    -- Labels and the subject share a type, and a label is a literal -- see S50 for why
                    -- or Bool LITERALS, and "duplicate labels are errors, including numerically
                    -- equal spellings such as 1 and 0x1". So the key is the VALUE, not the text.
                    local subject = type_of(statement.subject)
                    if not subject then return nil end
                    local seen = {}
                    -- An arm that binds a non-Copy payload MOVES the subject (§3.5), and the arms
                    -- binding a non-Copy payload does. Every other arm leaves it alive.
                    for _, arm in ipairs(statement.cases) do
                        for _, label in ipairs(arm.labels) do
                            -- `case_key` answers the whole question for the subject's kind, so a
                            -- label that is not a constant of a scalar subject, or not an
                            -- alternative of a sum subject, is one rejection rather than two.
                            local key, alternative = case_key(label, subject)
                            if not key or seen[key] then
                                return fail(Report.reject(Report.InvalidCaseLabel, statement.span))
                            end
                            seen[key] = true
                            -- §S60: "a label is a SHAPE or a CONSTANT and SAYS WHICH" -- and this is the
                            -- phase that can say it, because it is the phase that has the SUBJECT's
                            -- type. `Lower` cannot: the belt representation of two alternatives can be
                            -- ONE type (two word values with empty packets are both `uint8_t`), so
                            -- re-deriving it there matched the LAST alternative and every arm
                            -- dispatched to one body. A label is where the answer belongs, and it is
                            -- the same answer the binder's payload comes from.
                            if Judge.Shape:isclassof(label) then label.alternative = alternative end
                        end
                        -- §S59: an arm that binds is an arm that matched by SHAPE, so the subject
                        -- must be a sum and the label one of its alternatives -- and the binder
                        -- must carry that alternative's type, since it IS the payload. A payload
                        -- that cannot be copied has to be MOVED out of the sum, and moving a
                        -- payload moves the whole sum; that spelling does not exist yet, so this
                        -- refuses rather than copying something that cannot be copied.
                        if arm.binds then
                            local declaration = declarations[arm.binds]
                            local type_ = declaration and declaration.declared
                            local index = type_ and Semantic.Sum:isclassof(subject)
                                and subject:alternative(type_)
                            if not index then
                                return fail(Report.reject(Report.InvalidCaseLabel, statement.span))
                            end
                            -- §S65: whether a binder COPIES or TAKES is DERIVED from the payload's
                            -- type (§1.4), exactly as a stage's declared capability decides whether
                            -- it borrows (§S45) -- so there is nothing to refuse here. A payload that
                            -- cannot be copied is moved, and §3.5 makes moving a payload a move of the
                            -- WHOLE sum, which is why the arms of a mixed sum disagree about it and
                            -- §3.3 rejects them rather than this line.
                        end
                        -- §S65: taking a payload TAKES the subject -- but nothing is REPORTED for
                        -- that here any more, because the rule became a MECHANISM. A path that leaves
                        -- the sum alive does not need an arm to dispose of it: §3.5's destructor is
                        -- chosen by the TAG and `Lower` builds that dispatch, so a sum nobody takes is
                        -- destroyed at its scope exit like anything else. What remains is the divergence
                        -- that is OBSERVABLE -- a join something reaches and then uses -- and that is
                        -- `Lower`'s `agree`, where the places are known.
                        if not check_body(arm.body, result) then return nil end
                    end
                    if not check_body(statement.otherwise, result) then return nil end
                elseif Judge.Assign:isclassof(statement) then
                    -- §3.4: "Assignment requires a writable destination place", and "assigning
                    -- through a read-only binding ... is an error". Writability is a property of
                    -- the binding the place STARTS at, so that is where the question is answered.
                    local root = root_of(statement.place)
                    if not root then
                        return fail(Report.reject(Report.ReadOnlyDestination, statement.span))
                    end
                    -- §3.7: a `mut` MEMBER is interior mutability, so a place is writable if the
                    -- binding it starts at is `mut` OR any step of its path names a mutable field.
                    -- That is one rule and not two: a `mut` binding makes everything under it
                    -- writable, and a `mut` member does the same for its own subtree.
                    local function writes_through_a_member(place)
                        if Judge.Reference:isclassof(place) then return false end
                        local base = type_of(place.base)
                        local fields = base and Semantic.Aggregate:isclassof(base) and base.fields
                        if not fields then return false end
                        local field
                        if Judge.Project:isclassof(place) then
                            for _, candidate in ipairs(fields) do
                                if candidate.name == place.name then field = candidate end
                            end
                        else
                            field = fields[place.offset + 1]
                        end
                        if field and field.mutable then return true end
                        return writes_through_a_member(place.base)
                    end
                    if not (Judge.Value:isclassof(root) and root.mutable)
                        and not writes_through_a_member(statement.place) then
                        return fail(Report.reject(Report.ReadOnlyDestination, statement.span))
                    end
                    local target = type_of(statement.place)
                    if not target then return nil end
                    local value = type_of(statement.value)
                    if not value then return nil end
                    -- §3.4: "Assignment of an EXISTING non-copyable value requires `move`." The word
                    -- is existing: a FRESH value -- a call's result, an aggregate, a literal -- owns
                    -- itself and is stored as it stands, while an existing PLACE of a non-Copy type has
                    -- to be taken, because reading a place is a borrow and a borrow is not a value
                    -- (§1.4). Reading the TYPE alone refused `h = made(n)`, which is a store of
                    -- something new and has nothing to move.
                    local existing = Judge.Reference:isclassof(statement.value)
                        or Judge.Project:isclassof(statement.value)
                        or Judge.Index:isclassof(statement.value)
                        or Judge.Element:isclassof(statement.value)
                    if existing and not copyable(value) and not Judge.Move:isclassof(statement.value) then
                        return fail(Report.reject(Report.NeedsMove, statement.span))
                    end
                    if not accepts(target, value) then
                        return fail(Report.reject(Report.MismatchedType, statement.span))
                    end
                end
            end
            return true
        end

        -- §12.2 says the state of this phase is "interface table, cycle stack" -- and that is what
        -- it now is: an interface is computed ON DEMAND and memoized, not filled in by a walk.
        --
        -- A walk has an ORDER, and a definition routinely references one with a HIGHER id: a word's
        -- stages are created inside the word's own chain, and so is any type word a `case` names. So
        -- a walk leaves holes that depend on which definition was visited first -- which is not a
        -- fact about the program, and it produced three separate defects of the same shape. The
        -- cycle stack is the other half, and it is what turns a reference cycle into a diagnostic
        -- rather than a hang (§1.4 defers mutual recursion, so "no interface" is the honest answer).
        local by_id, building = {}, {}

        -- §2.5: `Copy` is derived, and a WORD's value is its PACKET, so a word type is Copy exactly
        -- when every member of that packet is -- the rule a record follows, asked of the declaration
        -- because that is where the members are named. `Semantic.Word(template, prefix)` cannot answer
        -- it (its template is a NUMBER and `Semantic` sits below `Chain`, §11.4), so each layer derives
        -- the fact from the declaration and NEITHER ASKS THE OTHER -- §S61's shape exactly. Without it a
        -- word value the design calls Copy -- an imported file's namespace, whose only member is an
        -- `Int`-staged word -- was refused with `NeedsMove`, so `import` could not be bound at all.
        copyable = function(type_)
            if not type_ then return false end
            if Semantic.Word:isclassof(type_) then
                local definition = by_id[type_.template]
                if not definition or not Judge.Word:isclassof(definition.declaration) then return false end
                for _, id in ipairs(definition.declaration.word:members(type_.prefix)) do
                    local interface = types[id]
                    if not interface or not copyable(interface.result) then return false end
                end
                return true
            end
            -- ... and THROUGH a record or a sum, for the reason `Lower` does the same: the semantic
            -- derivation asks `Semantic.Word`, which cannot see a template, so a namespace containing a
            -- word would be reported non-Copy.
            if Semantic.Aggregate:isclassof(type_) then
                for _, field in ipairs(type_.fields) do
                    if not copyable(field.type) then return false end
                end
                return true
            end
            if Semantic.Sum:isclassof(type_) then
                for _, alternative in ipairs(type_.alternatives) do
                    if not copyable(alternative) then return false end
                end
                return true
            end
            return type_:copyable()
        end
        for _, definition in ipairs(resolved.definitions) do by_id[definition.id] = definition end

        -- §3.6: a host type may declare that it borrows argument i, and a value of such a type is a
        -- BORROWED type -- which §3.1 rule 4 propagates structurally, because a record holding a view
        -- holds the borrow too. `borrow_of` answers WHICH argument, because that is what §3.6's table
        -- needs in order to classify the storage; `Interface.borrowed` is this same question asked for
        -- a yes, so there is one owner for it and not two.
        local host_borrows = {}
        for _, definition in ipairs(resolved.definitions) do
            local declaration = definition.declaration
            if Judge.Host:isclassof(declaration) and declaration.borrows then
                host_borrows[definition.name] = declaration.borrows
            end
        end
        borrow_of = function(type_)
            if Semantic.Named:isclassof(type_) then return host_borrows[type_.name] end
            if Semantic.Aggregate:isclassof(type_) then
                for _, field in ipairs(type_.fields) do
                    local index = borrow_of(field.type)
                    if index then return index end
                end
            elseif Semantic.Sum:isclassof(type_) then
                for _, alternative in ipairs(type_.alternatives) do
                    local index = borrow_of(alternative)
                    if index then return index end
                end
            end
        end

        interface_of = function(id)
            local memoized = types[id]
            if memoized then return memoized end
            local definition = by_id[id]
            if not definition then
                return fail(Report.bug(Report.NoLowering('definition'), resolved.definitions[1].span))
            end
            -- A CYCLE in the derivation, which §12.1's acyclic resolution says cannot happen: a name
            -- There is no re-entry check here, and that is the design: an interface is a fact about a
            -- DECLARATION (§S52), so it is PUBLISHED into `types` as soon as the declaration determines
            -- it, before any body is checked. A body that names its own word -- recursion -- then finds
            -- it on the way in and never re-enters. The guard that used to live here was a guess about
            -- the future; what replaces it is a PLACE, and the place is the publish (§S74).
            local declaration = definition.declaration
            local interface
            if Judge.Bound:isclassof(declaration) then
                interface = Judge.Interface(L{}, declaration.declared, Chain.Data, false)
            elseif Judge.Type:isclassof(declaration) or Judge.Host:isclassof(declaration) then
                -- §2.4: "a type word is a chain with `Type` domains and a data terminal", evaluated
                -- at construction time and erased. So a declared type's NAME is a value of type
                -- `TypeWord` -- which is what lets `Handle` be a type and a name without either
                -- being a special case.
                interface = Judge.Interface(L{}, Semantic.TypeWord, Chain.Data, false)
            elseif Judge.Value:isclassof(declaration) then
                local type_ = type_of(declaration.value)
                if not type_ then return nil end
                -- A DECLARED annotation is a claim the compiler checks (§12.2 "checks rather than
                -- infers"), and until now it was simply dropped: `let x : Int = true` was accepted
                -- because the type was read off the value and the annotation never looked at.
                -- §3.5: a sum is inhabited by a member whose type matches exactly ONE alternative.
                -- "None" and "more than one" are different refusals, which is why the alternative
                -- rule reports a count rather than a bare index.
                if declaration.declared then
                    if Semantic.Sum:isclassof(declaration.declared) then
                        local index, count = declaration.declared:alternative(type_)
                        if not index then
                                return fail(Report.reject(Report.MismatchedType, definition.span))
                        end
                        if count > 1 then
                            return fail(Report.reject(Report.InvalidConversion, definition.span))
                        end
                    elseif not declaration.declared:equals(type_) then
                        return fail(Report.reject(Report.MismatchedType, definition.span))
                    end
                end
                interface = Judge.Interface(L{}, declaration.declared or type_, Chain.Data, false)
            elseif Judge.Word:isclassof(declaration) then
                local stages = L()
                for _, item in ipairs(declaration.word.items) do
                    if Chain.Stage:isclassof(item) then
                        -- §11.1/§S3's boundary, checked where the DECLARATION is: a stage is a value
                        -- the CALLER supplies, so its type must be one a value can have. An ARROW and
                        -- a `do` are SHAPES and have no representation at all -- `rep` maps both to
                        -- nil -- so a stage declared with one reached `Belt.Parameter` with a nil and
                        -- CRASHED the compiler. It is the program's fault, and `NotExecutable` is the
                        -- same refusal that invoking such a stage already gets (§S99).
                        if Semantic.Arrow:isclassof(item.type) or Semantic.Do:isclassof(item.type) then
                            return fail(Report.reject(Report.NotExecutable, definition.span))
                        end
                        stages:insert(Judge.Parameter(names[item.binder], item.capability, item.type))
                    end
                end
                -- A data terminal's type is read off its value; a `do` terminal's is DECLARED,
                -- which is why §3.1 makes the annotation mandatory for it -- there is no term to
                -- read the type from. A HOST terminal has no term at all: the declaration's stages
                -- and result ARE the contract (§3.6), so its result is the template's.
                local result, body
                if not declaration.terminal then
                    result = declaration.word.result
                elseif Judge.Data:isclassof(declaration.terminal) then
                    result = type_of(declaration.terminal.value)
                else
                    result = declaration.word.result
                    body = declaration.terminal.statements
                end
                if not result then return nil end
                -- §S52: the interface is what the DECLARATION says, so it is published BEFORE the body
                -- is checked. That is the whole of what recursion needs -- a declaration is complete
                -- even while its definition is not -- and it is why the checks below can name this
                -- very word without re-entering this derivation (§S74).
                interface = Judge.Interface(stages, result, declaration.word.terminal,
                    borrow_of(result) ~= nil)
                types[id] = interface
                if body then
                    if not check_body(body, result) then return nil end
                    if not terminates(body) and result ~= Semantic.Unit then
                        return fail(Report.reject(Report.MismatchedType, definition.span))
                    end
                end
            else
                return fail(Report.bug(Report.NoLowering('declaration'), definition.span))
            end
            types[id] = interface
            typed:insert(Judge.Typed(id, interface))
            return interface
        end

        -- The drive. Every definition is ASKED for, so every one is checked -- but the order no
        -- longer matters, because each interface is computed on demand and memoized.
        for _, definition in ipairs(resolved.definitions) do
            if not interface_of(definition.id) then return k_diag(unit, diagnostic) end
        end

        -- A written terminal replaces the namespace (§2.6), and its type is the module's result.
        local namespace_type
        if resolved.namespace then
            namespace_type = type_of(resolved.namespace)
            if not namespace_type then return k_diag(unit, diagnostic) end
        end

        local program = Judge.Program(resolved.definitions, resolved.namespace, namespace_type, typed)
        unit.ambient.program = program
        return k_ok(unit, program)
    end

    return Contract
end
