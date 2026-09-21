-- Syntax -> Judge.Resolved (DESIGN §12.1, §S24).
--
-- Resolve answers one question per name: **which declaration does it denote?** It produces a
-- `Definition` per declaration, and for each a resolved `Initializer` -- so no later phase re-runs
-- lexical scoping or keys a fact by node identity.
--
-- Resolution is **post-order**: a declaration is entered only after its body resolves, because spec
-- §1.4 makes a binding visible after its initializer completes. That single ordering rule is what
-- makes `let a = a` an unknown name rather than a self-reference, and a forward reference unknown
-- rather than deferred.
--
-- The enclosing chain's id is reserved *before* its items resolve, because those items are scoped
-- to it -- even though its own name is not yet visible inside them.
return function(V)
    local Syntax, Chain, Semantic, Judge, Report, Source, L =
        V.Syntax, V.Chain, V.Semantic, V.Judge, V.Report, V.Source, V.List

    local Resolve = {}

    -- The primitive type words, by name. A `let`-bound type word joins them when type resolution
    -- reaches definitions and not just the vocabulary.
    -- §11.3's scalar type words, by name -- owned by `Semantic`, because the names of the type words
    -- are a semantic fact and `Contract` needs the same table (§S54).
    local PRIMITIVE = Semantic.primitive

    function Resolve.run(unit, program, k_ok, k_diag)
        local definitions = L()
        local scopes = {}
        local next_id, diagnostic = 0, nil

        local function push() scopes[#scopes + 1] = {} end
        local function pop() scopes[#scopes] = nil end
        local function bind(name, id) scopes[#scopes][name] = id end
        -- The LEVEL is part of the answer, because it is what makes a reference a capture: §1.4's
        -- table gives a word's capture the enclosing lexical scope as its extent, so a name found
        -- BELOW the current chain's level crosses a chain boundary and one found at or above it is
        -- ordinary -- the current chain's own items, or its body's own bindings.
        local function find(name)
            for i = #scopes, 1, -1 do
                local id = scopes[i][name]
                if id then return id, i end
            end
        end
        local function reserve() next_id = next_id + 1; return next_id end
        -- Every declaration, by id. A CAPTURE has to ask what it captures -- its own declaration's
        -- value is a reference to the outer binding (§3.2) and the mode it carries is that binding's
        -- mutability -- so the resolver needs the id -> definition map its consumers already do.
        local by_id = {}
        local function declare(definition)
            definitions:insert(definition)
            by_id[definition.id] = definition
            return definition
        end
        local function fail(d) diagnostic = d; return nil end
        -- Spec §1.4: defining the same name twice in one scope is an error, and shadowing is not
        -- -- a nested chain has its own scope, so the same name there is a different declaration.
        local function duplicate(name, span)
            if scopes[#scopes][name] then
                fail(Report.reject(Report.DuplicateBinding, span))
                return true     -- truthy on failure: `fail` itself returns nil, which is falsy
            end
        end

        -- The declared host types, by name: what exists, and what destroys one.
        local host_types = {}
        -- A type word, once per name: §2.4 makes a type an expression, so `Int` is a VALUE.
        local type_words = {}
        -- §2.4: a TYPE word's body is a type expression that mentions its `Type` stages, so it cannot
        -- be resolved when the word is DECLARED -- the stages have no meaning yet -- and is resolved
        -- per APPLICATION instead, with `type_env` binding the stage names to the argument types.
        -- "Evaluated at construction time" is exactly this: the application happens here, in the type
        -- language, and nothing about `Box with Int` reaches the belt.
        local type_bodies, type_env = {}, nil
        -- §S110: a GENERIC word's syntax, the scope it was declared in, and the variables already bound.
        -- An INSTANCE is built by resolving that chain again with the parameter bound -- not by copying
        -- the resolved tree -- because then every nested binding, capture and annotation comes out with
        -- the substitution applied, from the same code that made the original. The scope is only READ
        -- during a re-resolution (a `resolve_value` pushes its own), so a shallow copy is enough, and the
        -- env ACCUMULATES so that a second parameter sees what the first one bound.
        local generic_bodies, instance_cache = {}, {}
        -- What a NAME denotes as a type: a primitive (§3.4), or a declared host type (§3.6).
        -- ONE owner, because this is asked wherever a name meets a type -- a written `: T`, a type
        -- name used as a value, and a `case` label -- and those must not disagree about `Int`.
        -- The declared type must be the interned instance: a nominal type equals only itself.
        local function type_of_name(name)
            return PRIMITIVE[name] or (host_types[name] and host_types[name].type)
        end
        local function resolve_type(expr)
            -- §2.4/§11.2: **type application is `with`**, evaluated at construction time -- so it is
            -- resolved HERE, in the type language, and never reaches the belt. The spine is flattened
            -- first, so `Box with Int with Text` is one application of two arguments, and the word's
            -- body (kept UNRESOLVED in `type_bodies`) is resolved with its `Type` stages bound.
            if Syntax.TypeApply:isclassof(expr) then
                local arguments, callee = {}, expr
                while Syntax.TypeApply:isclassof(callee) do
                    table.insert(arguments, 1, callee.argument)
                    callee = callee.word
                end
                local id = Syntax.Ref:isclassof(callee) and find(callee.name)
                local body = id and type_bodies[id]
                if not body or #arguments > #body.stages then
                    return fail(Report.reject(Report.UnknownType, expr.span))
                end
                local env = {}
                for index, name in ipairs(body.stages) do
                    local argument = arguments[index]
                    if not argument then return fail(Report.reject(Report.UnknownType, expr.span)) end
                    local type_ = resolve_type(argument)
                    if not type_ then return nil end
                    env[name] = type_
                end
                local saved = type_env
                type_env = env
                local resolved = resolve_type(body.body)
                type_env = saved
                if not resolved then return nil end
                return resolved
            end
            -- §11.2's `TypeExpr`, all six alternatives, because a type is a WORD: `Box with Int` is
            -- `with` and a record type is a record. These are structural, so they are built
            -- here rather than looked up -- and a record type's `mut` field lands on the FIELD, since
            -- that is what §3.7's interior mutability is a property of.
            if Syntax.Record:isclassof(expr) then
                local fields = L()
                for _, field in ipairs(expr.fields) do
                    local type_ = resolve_type(field.type)
                    if not type_ then return nil end
                    fields:insert(Semantic.Field(field.name, type_, field.mutable))
                end
                return Semantic.Aggregate(fields, nil)
            end
            -- §3.3: a positional element has no declaration, so a tuple's fields are unnamed and it
            -- is a record like any other -- which is why a tuple and a same-shaped record are one
            -- type rather than two.
            if Syntax.Tuple:isclassof(expr) then
                local fields = L()
                for _, element in ipairs(expr.elements) do
                    local type_ = resolve_type(element)
                    if not type_ then return nil end
                    fields:insert(Semantic.Field(nil, type_, false))
                end
                return Semantic.Aggregate(fields, nil)
            end
            if Syntax.Arrow:isclassof(expr) then
                local from = resolve_type(expr.from)
                if not from then return nil end
                local to = resolve_type(expr.to)
                if not to then return nil end
                return Semantic.Arrow(from, to)
            end
            if Syntax.Sum:isclassof(expr) then
                local left = resolve_type(expr.left)
                if not left then return nil end
                local right = resolve_type(expr.right)
                if not right then return nil end
                -- Two alternatives per node, so `A | B | C` is a nesting rather than a flat list.
                -- That keeps the surface and the type in step, and a sum of sums is still a sum.
                return Semantic.Sum(L{left, right})
            end
            if Syntax.Do:isclassof(expr) then
                local result = resolve_type(expr.result)
                if not result then return nil end
                return Semantic.Do(result)
            end
            if not Syntax.Ref:isclassof(expr) then
                -- §S102: a program the grammar accepts is never the compiler's own fault. `parse_type`
                -- can only build the six alternatives above, so this is reached by a caller that fed a
                -- VALUE where a type was expected -- `divide with { … }` before deduction existed -- and
                -- the honest answer is that the argument is not a type, not an internal error.
                return fail(Report.reject(Report.UnknownType, expr.span))
            end
            -- A DECLARED host type (§3.6) is a type word like any other. It is `Named` rather than a
            -- new alternative because that is what it is: a type whose meaning the host owns, which
            -- is also why Copy cannot be derived for it (§2.5) and why it needs a destructor.
            --
            -- The type is built here and compared BY NAME (`Semantic.Named:equals`), so a fresh
            -- `Named('Handle')` is the same type as the declared one: `equals` is what makes
            -- nominality work, not the identity of the node. (This comment claimed the opposite --
            -- "two `Named('Handle')` values compare unequal" -- which was true before the `equals`
            -- existed and stayed after it: prose describing a mechanism the code no longer has.)
            -- §1.1 read through §S3's nominality: a word's type is `Semantic.Word(template, prefix)`,
            -- so a name that denotes a WORD may be used as a TYPE, and it means the type of that
            -- word's VALUE -- exactly the rule `Int` already follows, where the name denotes a type
            -- word and the annotation means the type it NAMES. `let f : square` was `UnknownType`
            -- because this asked `type_of_name`, which knows only primitives and host types.
            --
            -- It is `Judge.word_of` (§S101), the SAME function `Lower` selects a callee with: `Resolve`
            -- runs before `Contract`, so the type cannot be asked for -- it is derived from the
            -- DECLARATION, which is structural and therefore available now. That is what makes a
            -- PARTIAL application a type too: `let add2 = add with 2` has the nominal type
            -- `Word(add, 1)`, and a stage typed `add2` is invocable exactly as one typed `square` is
            -- (§S99). A hand-rolled walk here stopped at the `Apply`, so `f : add2` was `UnknownType`
            -- while `add2 with 3` lowered -- one question with two answers.
            -- A `Type` stage's name is bound while its word's body is being resolved (§2.4), and it is
            -- a TYPE -- the only thing that can shadow a name from the type side.
            if type_env and type_env[expr.name] then return type_env[expr.name] end
            local word_id = find(expr.name)
            if word_id then
                local template, prefix = Judge.word_of(function(id)
                    local definition = by_id[id]
                    return definition and definition.declaration
                end, Judge.Reference(word_id, expr.span))
                if template then return Semantic.Word(template, prefix) end
            end
            -- A name that denotes a TYPE WORD denotes the type it NAMES, so `let P = Int` makes `P`
            -- usable as a type -- the same rule `Int` itself follows, where the name denotes a value
            -- and the annotation means the type that value NAMES. This is "types are words" at the
            -- level of NAMING, and it is where the rule stops: only what the DECLARATION already
            -- says can be answered here, because this phase runs before `Contract`. A type word, a
            -- host type's name, a stage's declared type -- yes; the type of a DATUM -- no, because
            -- that is what the checker computes (`let origin = Point with 0 with 0` then `p : origin`
            -- is `UnknownType`). The reference's type section states the boundary and the workaround.
            local function type_of_binding(name)
                local id = find(name)
                local hops = 0
                while id and hops < 8 do
                    local definition = by_id[id]
                    local declaration = definition and definition.declaration
                    if not declaration then return nil end
                    if Judge.Type:isclassof(declaration) then return declaration.denotes end
                    if Judge.Host:isclassof(declaration) then
                        return Semantic.Named(definition.name)
                    end
                    if Judge.Bound:isclassof(declaration) then
                        -- §S110: a stage whose DECLARED type is a type word is a TYPE PARAMETER, so its
                        -- name denotes a VARIABLE -- the place an instantiation will put the argument.
                        -- That is what lets a generic word's body say `let x : T` and mean it.
                        if Semantic.TypeWord:isclassof(declaration.declared) then
                            return Semantic.Variable(id)
                        end
                        return declaration.declared
                    end
                    -- A binding is a second name for its value, so the walk follows it -- and stops
                    -- at anything whose type is not known until `Contract` has run.
                    if not (Judge.Value:isclassof(declaration)
                            and Judge.Reference:isclassof(declaration.value)) then
                        return nil
                    end
                    id, hops = declaration.value.definition, hops + 1
                end
                return nil
            end
            local denoted = type_of_binding(expr.name)
            if denoted then return denoted end
            local type_ = type_of_name(expr.name)
            if type_ then return type_ end
            return fail(Report.reject(Report.UnknownType, expr.span))
        end

        local function resolve_host(item)
            if duplicate(item.name, item.name_range.start) then return nil end
            if PRIMITIVE[item.name] or host_types[item.name] then
                return fail(Report.reject(Report.DuplicateBinding, item.name_range.start))
            end
            -- §3.6: the declaration is the whole contract, so the borrow index is read ONCE here --
            -- and §S38 makes `Semantic.integer_value` the one owner of an integer's value.
            local borrows
            if item.borrows then
                borrows = Semantic.integer_value(item.borrows)
                if not borrows or borrows < 1 then
                    return fail(Report.reject(Report.InvalidCaseLabel, item.name_range.start))
                end
            end
            host_types[item.name] = { destroys = item.destroys, borrows = borrows,
                                      type = Semantic.Named(item.name) }
            local id = reserve()
            -- The DECLARATION carries the destructor, because §3.6 makes the declaration the whole
            -- contract and §3.3 says destruction is inserted by `Lower` at scope exits -- which
            -- means `Lower` has to be able to ask a type what destroys it.
            declare(Judge.Definition(id, item.name, Judge.Host(item.destroys, borrows), nil,
                item.span, item.name_range))
            bind(item.name, id)
            return id
        end

        local resolve_initializer
        local resolve_body

        -- One chain -> its declaration. The chain's items are declarations in their own scope.
        -- `mutable` is §3.4's writable destination: a binding declared `mut` is assignable, and
        -- Lower makes it a `Cell` for exactly that reason. It rides on the DECLARATION because
        -- that is what mutability belongs to -- the same way `Judge.Member` already carries it.
        -- `own` is the definition being constructed, present only when the caller has already
        -- reserved its id. It is what the self name denotes: §1.4's "self name / recursion" row makes
        -- recursion a lexical, compile-time fact with no runtime reference, so a word that names
        -- itself is an ordinary reference to an ordinary definition -- which is what makes the call a
        -- call to the SAME belt instance rather than a second specialization of it (§S74).
        -- §12.1's table asks "which bindings does this word capture, in what order?" and this pair is
        -- what answers it: `level` is the scope depth of the chain being resolved and `captures` is
        -- its list. §2.2's residual is "captures + stage values 0…k-1 + prelude bindings", so the
        -- captures come first because they are the FRAME the rest of the packet lives in. A FILE is a
        -- chain too (§2.6), which is why the stack starts at the file's scope: a reference within the
        -- file is ordinary and a reference from a word in it is a capture.
        local current_level, current_captures = 1, L()

        -- §3.2: "captured state lives in a cell". A binding a word uses but does not OWN is a capture.
        -- It is a declaration of its own -- a binder, like a stage -- so a reference to it denotes the
        -- BINDER and not the outer definition, and its value IS the outer definition: that is what
        -- makes its value the ENCLOSING instance's, computed where that instance can compute it. One
        -- binder per (chain, outer binding), so two mentions are one capture and the order is first
        -- mention -- which is what makes the packet's layout deterministic.
        local function capture_of(outer, name, span, name_range, scope)
            local captures = current_captures
            for _, capture in ipairs(captures) do
                local definition = by_id[capture.binder]
                if definition and definition.declaration.value.definition == outer then
                    return capture.binder
                end
            end
            local binder = reserve()
            local declaration = by_id[outer] and by_id[outer].declaration
            -- §3.7: interior mutability is a property of the STORAGE and the storage belongs to the
            -- owner, so a `mut` binding is written through its capture and nothing else is. The
            -- declaration's own `mutable` is what `Contract` reads to allow that write.
            local mutable = declaration and declaration.mutable and true or false
            declare(Judge.Definition(binder, name,
                Judge.Value(Judge.Reference(outer, span), mutable, nil), scope, span, name_range))
            captures:insert(Chain.Capture(binder, name,
                mutable and Semantic.Mut or Semantic.Read))
            return binder
        end

        -- A binding's annotation, in ONE place, because there were two and the body's passed `nil`:
        -- `let s : Int | Handle = 5` inside a body was typed as the PAYLOAD and never injected, so the
        -- annotation was not merely unchecked, it changed what the value WAS. The second return says
        -- whether resolution succeeded, because "no annotation" and "a bad one" are different answers.
        local function annotation_of(binding)
            if not binding.constraint then return nil, true end
            local type_ = resolve_type(binding.constraint)
            if not type_ then return nil, false end
            return type_, true
        end

        local function resolve_value(chain, scope, name, mutable, annotation, own)
            push()
            local outer_level, outer_captures = current_level, current_captures
            local items, stages, group, members = L(), 0, L(), L()
            -- Is this chain a WORD -- an instance of its own -- or a VALUE, which is INLINED where it
            -- stands? §1.4's table gives a capture the enclosing lexical scope as its extent, so a
            -- reference crosses a boundary only when it enters a DIFFERENT instance: a chain with
            -- stages or a `do` terminal becomes a `Chain.Template` with a `run` of its own, while one
            -- with neither is lowered in the enclosing scope and captures nothing. `let a = f 1` is
            -- the second kind, and treating it as the first made every file-level binding a capture.
            local is_word = chain.terminal ~= nil and not Syntax.Data:isclassof(chain.terminal)
            if not is_word then
                for _, item in ipairs(chain.items) do
                    if Syntax.Stage:isclassof(item) then is_word = true break end
                end
            end
            if is_word then current_level, current_captures = #scopes, L() end
            local transient_from
            for _, item in ipairs(chain.items) do
                if Syntax.Stage:isclassof(item) then
                    -- A group is flushed when the stage that ends it arrives.
                    if #group > 0 then items:insert(Chain.Group(stages, group)); group = L() end
                    local spec = item.stage
                    local type_ = resolve_type(spec.constraint)
                    if not type_ then pop(); return nil end
                    if duplicate(spec.name, spec.name_range.start) then pop(); return nil end
                    local id = reserve()
                    if spec.capability == Semantic.Mut and not transient_from then
                        transient_from = stages
                    end
                    declare(Judge.Definition(id, spec.name, Judge.Bound(type_), scope,
                        spec.span, spec.name_range))
                    bind(spec.name, id)
                    items:insert(Chain.Stage(stages, spec.capability, type_, id))
                    stages = stages + 1
                elseif Syntax.Extern:isclassof(item) then
                    if duplicate(item.name, item.name_range.start) then pop(); return nil end
                    local template = resolve_extern(item, scope)
                    if not template then pop(); return nil end
                    local id = reserve()
                    declare(Judge.Definition(id, item.name, Judge.Word(template, nil),
                        scope, item.span, item.name_range))
                    bind(item.name, id)
                elseif Syntax.Prelude:isclassof(item) then
                    local binding = item.binding
                    if duplicate(binding.name, binding.name_range.start) then pop(); return nil end
                    local id = reserve()
                    local declared, ok = annotation_of(binding)
                    if not ok then pop(); return nil end
                    local declaration = resolve_value(binding.value, Judge.Lexical(id),
                        binding.name, binding.mutable, declared, id)
                    if not declaration then pop(); return nil end
                    declare(Judge.Definition(id, binding.name, declaration, scope,
                        binding.span, binding.name_range))
                    bind(binding.name, id)
                    group:insert(id)
                    members:insert(Judge.Member(binding.name, Judge.Reference(id, binding.span),
                        binding.mutable))
                else
                    pop()
                    return fail(Report.bug(Report.NoLowering('chain item'), chain.span))
                end
            end
            if #group > 0 then items:insert(Chain.Group(stages, group)) end

            -- `data` is the terminal's expression and `terminal` its judgment: a declaration whose
            -- chain has no stages is a VALUE and takes the expression, while a word takes the
            -- terminal -- which is why both are kept here.
            local terminal, data, kind, declared
            -- §S110: the `Type` stages' NAMES, in source order -- they are the parameters a generic
            -- word's body may mention. Computed ONCE because two readers need it: a chain that is a TYPE
            -- word (its terminal is a type) and one that is a GENERIC word (its terminal is a body).
            local type_names = {}
            for _, item in ipairs(chain.items) do
                local constraint = Syntax.Stage:isclassof(item) and item.stage.constraint
                if constraint and Syntax.Ref:isclassof(constraint)
                        and constraint.name == 'Type' then
                    type_names[#type_names + 1] = item.stage.name
                end
            end
            if not chain.terminal then
                -- §2.6: "A file with no written terminal exposes the named aggregate of its own
                -- prelude bindings, in source order." Read through §S26 -- an aggregate IS a chain
                -- -- that is the rule for any chain with no terminal, and this is its ONE owner:
                -- the entry file below builds its namespace the same way.
                kind = Chain.Data
                data = Judge.Aggregate(members, chain.span)
                terminal = Judge.Data(data)
            elseif chain.terminal then
                if Syntax.Data:isclassof(chain.terminal) then
                    -- §2.4 read through S106's decision: a chain with `Type` domains and a data terminal
                    -- that IS a type is a TYPE word -- "evaluated at construction time and erased" -- so
                    -- its body is NOT resolved here. It is kept in `type_bodies` and resolved per
                    -- APPLICATION, which is what makes `Box with Int` a type rather than an operation.
                    -- `Judge.Word(template, nil)` is what a word with no runtime terminal already is (a
                    -- host word is one), so this needs no new judge vocabulary -- and §S107's erasure
                    -- keeps it out of every namespace and every packet.
                    -- The stages the body may mention, in source order: a chain with a `Type` DOMAIN is
                    -- a TYPE word, and one with none is a type VALUE (`let P : Type = { x : Int }`), which
                    -- is the ordinary data path below.
                    local type_value = Syntax.TypeValue:isclassof(chain.terminal.value)
                        and chain.terminal.value or nil
                    local names = type_names
                    if type_value and #names > 0 then
                        kind = Chain.Data
                        declared = Semantic.TypeWord
                        type_bodies[own] = { body = type_value.type, stages = names }
                    else
                        kind = Chain.Data
                        data = resolve_initializer(chain.terminal.value, scope)
                        if not data then pop(); return nil end
                        terminal = Judge.Data(data)
                    end
                else
                    -- §3.1: "a runtime terminal MUST state its result" -- there is no term to read a
                    -- type from, so an unstated one is the program's fault, not a missing feature.
                    kind = Chain.Do
                    if not chain.terminal.result then
                        pop()
                        return fail(Report.reject(Report.UnstatedResult, chain.terminal.span))
                    end
                    declared = resolve_type(chain.terminal.result)
                    if not declared then pop(); return nil end
                    -- The self name must not be read by its own initializer or its stages, which run
                    -- while the word is being CONSTRUCTED -- and §1.4 makes it visible inside the
                    -- terminal `do` body, which runs after. So it is bound HERE, for the body alone:
                    -- the items above were resolved without it, an anonymous word has no self name,
                    -- and a data terminal (`let a = a`) never reaches this branch at all.
                    if own then
                        -- A stage of the same name and the self name are declarations in ONE scope,
                        -- so they cannot share it: binding one over the other makes a name silently
                        -- mean the wrong thing, which is worse than either answer. So it is what any
                        -- other duplicate is -- and the check is here rather than at the top because
                        -- the self name exists only for this branch.
                        if duplicate(name, chain.terminal.span) then pop(); return nil end
                        bind(name, own)
                    end
                    local statements = resolve_body(chain.terminal.statements, scope)
                    if not statements then pop(); return nil end
                    terminal = Judge.Body(statements)
                end
            end
            -- The chain ends here, and this is the ONE place it does: every early return above pops
            -- the scope and returns nil, so a failed resolve never continues -- which is why reading
            -- the captures here, before the restore, is enough.
            local captures = current_captures
            pop()
            if is_word then current_level, current_captures = outer_level, outer_captures end

            -- Spec §11.1: a chain with no stages and a data terminal *is* a value.
            if stages == 0 and kind ~= Chain.Do then
                if not terminal then
                    return fail(Report.bug(Report.NoLowering('namespace'), chain.span))
                end
                return Judge.Value(data, mutable and true or false, annotation)
            end
            local template = Chain.Template(name or '', items, stages, transient_from or stages,
                -- The declared result of a `do` terminal is what §11.3 makes the terminal's type:
                -- "a runtime terminal `do : R` is checked against every `return`".
                kind, declared, captures, Semantic.Runtime, Semantic.Ordered)
            -- §S110: a chain with `Type` stages and a BODY terminal is a GENERIC word. It has no runtime
            -- form -- the erasure keeps it out of every namespace and packet (§S107 as extended) -- and
            -- each application of a TYPE to it builds an INSTANCE (`instantiate`, below). That is why the
            -- SYNTAX, the SCOPE and the ENV are kept here: re-resolving is the whole mechanism.
            if #type_names > 0 then
                local snapshot, env = {}, {}
                for index = 1, #scopes do snapshot[index] = scopes[index] end
                for key, value in pairs(type_env or {}) do env[key] = value end
                generic_bodies[own] = { items = chain.items, terminal = chain.terminal,
                    scopes = snapshot, env = env, name = name }
            end
            return Judge.Word(template, terminal)
        end

        -- §11.2: conversions are DICTIONARY words, so a name that no lexical binding denotes may be
        -- one of them. §12.1: "Names ultimately resolve to lexical bindings or dictionary entries. A
        -- lexical binding wins over an entry" -- which is why this is the fallback and not the first
        -- test, and why `let ToInt = ...` shadows the conversion.
        --
        -- Each is a one-stage word whose terminal is the conversion itself, so it is applied,
        -- advanced and run by the machinery that already exists. The definitions are built once per
        -- resolver, because two uses of `ToInt` are two occurrences of one word.
        local dictionary = {}
        local function resolve_conversion(name, span, name_range, scope)
            local shape = Semantic.conversions[name]
            if not shape then return nil end
            if not dictionary[name] then
                push()
                -- The stage is a definition because the packet machinery needs one, and it needs a
                -- NAME because the packet's field is named from the binder. A conversion's argument
                -- has no source name, so it gets one -- and it must be a valid identifier, because
                -- that name reaches the emitted C as a struct member.
                local stage_id = reserve()
                declare(Judge.Definition(stage_id, 'value', Judge.Bound(shape.from),
                    scope, span, name_range))
                bind('value', stage_id)
                pop()
                local template = Chain.Template(name, L{Chain.Stage(0, Semantic.Read, shape.from,
                        stage_id)}, 1, 1, Chain.Convert(Semantic[name]), shape.to, L{},
                    Semantic.Runtime, Semantic.Pure)
                local id = reserve()
                declare(Judge.Definition(id, name, Judge.Word(template, nil), scope, span,
                    name_range))
                dictionary[name] = id
            end
            return dictionary[name]
        end

        -- §11.2's `Extern` -> a WORD whose terminal is a host symbol. The declaration IS the
        -- contract (§3.6): the ordered stages with their capabilities and types, the result, and
        -- purity -- because that is what the compiler holds a host to, and nothing else about the
        -- host is knowable. The stages are definitions like any other, so a host word's packet is
        -- built by the same machinery as a source word's.
        local function resolve_extern(item, scope)
            push()
            local items, stages, transient_from = L(), 0, nil
            for _, spec in ipairs(item.parameters) do
                local type_ = resolve_type(spec.constraint)
                if not type_ then pop(); return nil end
                if duplicate(spec.name, spec.name_range.start) then pop(); return nil end
                local stage_id = reserve()
                declare(Judge.Definition(stage_id, spec.name, Judge.Bound(type_), scope,
                    spec.span, spec.name_range))
                bind(spec.name, stage_id)
                if spec.capability == Semantic.Mut and not transient_from then transient_from = stages end
                items:insert(Chain.Stage(stages, spec.capability, type_, stage_id))
                stages = stages + 1
            end
            pop()
            local result = Semantic.Unit
            if item.result then
                result = resolve_type(item.result)
                if not result then return nil end
            end
            -- The terminal is `Chain.Host` and the JUDGE terminal is nil, because a host word has no
            -- body and no data to judge: the symbol is on the template, and the declaration's stages
            -- and result are the whole contract. That is why `Judge.Word`'s terminal is optional.
            local template = Chain.Template(item.name, items, stages, transient_from or stages,
                Chain.Host(item.symbol or item.name), result, L{}, Semantic.Runtime,
                item.pure and Semantic.Pure or Semantic.Ordered)
            return template
        end

        -- The stack of files whose chains are being resolved, so a cycle is a diagnostic rather
        -- than a hang: §2.6 makes a file that imports itself "a construction cycle".
        local importing = {}

        -- §2.6's import. One expression slot -- the path -- which must be a constant `Text`, so the
        -- spelling is the path and there is nothing to evaluate. The file's stages are supplied by
        -- the specialization arguments that FOLLOW, which is why this only needs the path: the
        -- result is a word whose stages the surrounding chain advances.
        local function resolve_import(expr, scope)
            local path = expr.argument
            local span = expr.span
            if not Syntax.Text:isclassof(path) then
                return fail(Report.reject(Report.ImportPath, span))
            end
            if importing[path.value] then
                return fail(Report.reject(Report.ImportCycle, span))
            end
            -- §13's kinds, and a diagnostic must not be dropped on the way out: `V.load` returns
            -- `Reject(MissingModule)` for a file that is not there, and returning nil WITHOUT it left
            -- the door with no diagnostic at all -- "the compiler stopped without a diagnostic", exit
            -- 2, which says the compiler is broken when the program named a file that is not there.
            local program, load_diagnostic = V.load(unit, path.value, span)
            if not program then return fail(load_diagnostic) end
            if not program then return nil end
            importing[path.value] = true
            local declaration = resolve_value(program.file, scope, '<import ' .. path.value .. '>', false)
            importing[path.value] = nil
            if not declaration then return nil end
            local id = reserve()
            declare(Judge.Definition(id, '<import ' .. path.value .. '>', declaration,
                Judge.Lexical(id), span, Source.Range(span, span)))
            return Judge.Reference(id, span)
        end

        -- §S110/§S112: the INSTANTIATION, in ONE place, because two forms must ask it -- `f with T` and
        -- the call form `f(T, ...)`. It answers TWO things: whether the argument was a TYPE argument at
        -- all (`is_type`, which stays true when the instantiation FAILED, so a caller never falls back
        -- to reading a type as a value), and the node the expression denotes (the INSTANCE).
        --
        -- A `Type` stage's argument is read AS A TYPE, exactly like the value of a `: Type` binding: a
        -- NAME is the common case (`id with Int`), a type VALUE arrives as `TypeValue`, and a type
        -- application as `TypeApply`. An instance is built by resolving the generic word's stored SYNTAX
        -- again with the parameter bound -- exact by construction, and the reason the syntax and the
        -- scope are kept -- and nothing about a type application reaches the belt: what runs is the
        -- instance, and an instance is concrete.
        -- §S114: the type of a VALUE when it can be read without `Contract` -- a word (nominal, §S99), a
        -- record of those, or a literal. This is the derivation `word_of` already does, extended to an
        -- aggregate; anything else has a type only the checker knows, and there the type is WRITTEN.
        -- Nothing here reads an interface (§S52): every fact comes from a declaration.
        local function derived_type(node)
            if not node then return nil end
            if Judge.Reference:isclassof(node) or Judge.Move:isclassof(node)
                    or Judge.Project:isclassof(node) or Judge.Apply:isclassof(node) then
                local template, prefix = Judge.word_of(function(id)
                    local definition = by_id[id]
                    return definition and definition.declaration
                end, node)
                if template then return Semantic.Word(template, prefix) end
                return nil
            end
            if Judge.Literal:isclassof(node) then
                local expr = node.value
                if Syntax.Integer:isclassof(expr) then return Semantic.Int end
                if Syntax.Boolean:isclassof(expr) then return Semantic.Bool end
                if Syntax.Float:isclassof(expr) then return Semantic.Float end
                if Syntax.Text:isclassof(expr) then return Semantic.Text end
                if Syntax.Unit:isclassof(expr) then return Semantic.Unit end
                return nil
            end
            if not Judge.Aggregate:isclassof(node) then return nil end
            local fields = L()
            for _, member in ipairs(node.members) do
                local field_type = derived_type(member.value)
                if not field_type then return nil end
                fields:insert(Semantic.Field(member.name, field_type, member.mutable))
            end
            return Semantic.Aggregate(fields, nil)
        end

        -- §S114: fill the type parameters from a later stage's DECLARED type -- the reader's rule: "a
        -- `Type` stage that appears in the declared type of a later stage is deduced from that stage's
        -- argument". A `Variable` is the hole to fill; a record matches a record field by field, names
        -- included; anything else must already be equal.
        local function deduce_into(declared, derived, env, depth)
            if not declared or not derived or depth > 8 then return false end
            if Semantic.Variable:isclassof(declared) then
                local definition = by_id[declared.stage]
                if not definition then return false end
                local bound = env[definition.name]
                if bound then return bound:equals(derived) end
                env[definition.name] = derived
                return true
            end
            if Semantic.Aggregate:isclassof(declared) then
                if not Semantic.Aggregate:isclassof(derived) then return false end
                if #declared.fields ~= #derived.fields then return false end
                for index, field in ipairs(declared.fields) do
                    local peer = derived.fields[index]
                    if field.name ~= peer.name then return false end
                    if not deduce_into(field.type, peer.type, env, depth + 1) then return false end
                end
                return true
            end
            return declared:equals(derived)
        end

        -- §S110/§S114: the INSTANTIATION, in ONE place, because two forms must ask it -- `f with T` and
        -- the call form `f(T, ...)` -- and it answers FOUR states, which is what the callers need:
        --
        --   'none'      not an instantiation: the caller resolves the argument as a VALUE and applies it
        --   'consumed'  the argument WAS the type argument: `node` is the instance and nothing is left to
        --               apply. `node == nil` means the type argument FAILED (a diagnostic is set), so the
        --               caller must NOT fall back to reading a type as a value.
        --   'deduced'   the parameters were filled from this argument's TYPE, so `node` is the instance
        --               and the caller must STILL apply this argument to it -- `id(true)` is this case,
        --               and getting it wrong is what made it `Undersaturated`.
        --
        -- A `Type` stage's argument is read AS A TYPE when it is written (a NAME, a type VALUE, a type
        -- application); otherwise its type is DEDUCED -- the same argument, one mention per value. An
        -- instance is built by resolving the generic word's stored SYNTAX again with the parameters
        -- bound, exact by construction, and nothing about a type application reaches the belt.
        instantiate = function(callee, argument_syntax, span, scope)
            local template, prefix = nil, 0
            if Judge.Reference:isclassof(callee) then
                template, prefix = Judge.word_of(function(id)
                    local definition = by_id[id]
                    return definition and definition.declaration
                end, callee)
            end
            local declaration = template and by_id[template] and by_id[template].declaration
            local word = declaration and Judge.Word:isclassof(declaration) and declaration.word
            local stage, ordinal = nil, 0
            if word then
                for _, item in ipairs(word.items) do
                    if Chain.Stage:isclassof(item) then
                        ordinal = ordinal + 1
                        if ordinal == (prefix or 0) + 1 then stage = item break end
                    end
                end
            end
            if not (stage and Semantic.TypeWord:isclassof(stage.type)) then return nil, 'none' end
            local body = generic_bodies[template]
            if not body then return nil, 'none' end
            -- EXPLICIT first: a written type argument names itself. NOTE which item list is which:
            -- `word.items` are CHAIN stages (`.type`, `.binder`), while `body.items` below are SYNTAX
            -- (`.stage.constraint`, `.stage.name`) -- mixing them is a crash, not a diagnostic.
            local syntax = argument_syntax
            if Syntax.Name:isclassof(syntax) then
                syntax = Syntax.Ref(syntax.name, syntax.span)
            elseif Syntax.TypeValue:isclassof(syntax) then
                syntax = syntax.type
            end
            local bindings, argument, value = {}, nil, nil
            if Syntax.Ref:isclassof(syntax) or Syntax.TypeApply:isclassof(syntax) then
                argument = resolve_type(syntax)
                if not argument then return nil, 'consumed' end
                -- One written argument fills the FIRST `Type` stage that is not already bound.
                for _, item in ipairs(word.items) do
                    if Chain.Stage:isclassof(item) and Semantic.TypeWord:isclassof(item.type) then
                        local definition = by_id[item.binder]
                        local name = definition and definition.name
                        if name and not (bindings[name] or body.env[name]) then
                            bindings[name] = argument
                            break
                        end
                    end
                end
                if not next(bindings) then return nil, 'none' end
            else
                -- DEDUCED: the argument is a VALUE and its type is read off it.
                value = resolve_initializer(argument_syntax, scope)
                if not value then return nil, 'consumed' end
                local derived = derived_type(value)
                if not derived then return nil, 'none' end
                local later
                for _, item in ipairs(word.items) do
                    if Chain.Stage:isclassof(item) and item.type:mentions_variable() then
                        later = item break
                    end
                end
                if not later then return nil, 'none' end
                local env = {}
                if not deduce_into(later.type, derived, env, 0) then return nil, 'none' end
                bindings, argument = env, derived
            end
            local instance
            local cached = instance_cache[template]
            for _, entry in ipairs(cached or {}) do
                if entry.type:equals(argument) then instance = entry.id break end
            end
            if not instance then
                -- A `Type` stage WITH A BINDING is not a stage of the instance -- which is what makes a
                -- deduced parameter disappear exactly as a written one does, and what leaves a
                -- partially applied generic word generic.
                local items = L()
                for _, item in ipairs(body.items) do
                    local constraint = Syntax.Stage:isclassof(item) and item.stage.constraint
                    local name = constraint and constraint.name == 'Type' and item.stage.name or nil
                    if not (name and (bindings[name] or body.env[name])) then items:insert(item) end
                end
                local id = reserve()
                local saved_scopes, saved_env = scopes, type_env
                scopes = {}
                for index = 1, #saved_scopes do scopes[index] = saved_scopes[index] end
                type_env = {}
                for key, bound in pairs(body.env) do type_env[key] = bound end
                for key, bound in pairs(bindings) do type_env[key] = bound end
                local made = resolve_value(Syntax.Chain(items, body.terminal, span),
                    Judge.Lexical(id), body.name or '', false, nil, id)
                scopes, type_env = saved_scopes, saved_env
                if not made then return nil, 'consumed' end
                declare(Judge.Definition(id, (body.name or 'word') .. '_' .. tostring(id),
                    made, nil, span, Source.Range(span, span)))
                instance = id
                cached = instance_cache[template] or {}
                cached[#cached + 1] = { type = argument, id = id }
                instance_cache[template] = cached
            end
            local node = Judge.Reference(instance, span)
            if value then return node, 'deduced', value end
            return node, 'consumed'
        end

        resolve_initializer = function(expr, scope)
            -- §2.4/S106: a TYPE used as a value. It becomes a `Judge.Type` declaration like a bare type
            -- NAME (`Int`), because that is what it is -- a type word -- and everything downstream already
            -- knows what to do with one: `interface_of` gives it `Semantic.TypeWord`, `Contract` compares
            -- that against the `: Type` annotation, the ERASURE keeps it out of every namespace and
            -- packet (§S107), and `type_of_binding` reads the type back out of the declaration, which is
            -- what makes `let Point : Type = { x : Int }` then `p : Point` work.
            if Syntax.TypeValue:isclassof(expr) then
                local type_ = resolve_type(expr.type)
                if not type_ then return nil end
                local id = reserve()
                declare(Judge.Definition(id, '<type>', Judge.Type(type_), scope, expr.span,
                    Source.Range(expr.span, expr.span)))
                return Judge.Reference(id, expr.span)
            end
            -- §3.3/§S26: an aggregate's members are declarations with their own names, visible to
            -- later members. The aggregate is not a scope-bearing definition, so the members record
            -- the *enclosing* scope; only the name scope below is the aggregate's.
            if Syntax.NamedAggregate:isclassof(expr) then
                push()
                local members = L()
                for _, binding in ipairs(expr.members) do
                    if duplicate(binding.name, binding.name_range.start) then pop(); return nil end
                    -- §3.1: "a record type and a value aggregate are the same form", so a member's
                    -- value is a CHAIN -- and a chain is exactly what `resolve_value` resolves: items,
                    -- stages, terminal. So a member with preludes, or with stages (which make it a
                    -- WORD), is not a special case at all: it is a binding whose value is a chain, the
                    -- same thing a file's prelude is. It was `Missing(MemberPrelude)` because the
                    -- member path resolved the TERMINAL and refused anything before it.
                    --
                    -- `false` for the declaration's mutability and not `binding.mutable`: §3.7's `mut`
                    -- inside braces is interior mutability of the MEMBER, and `Judge.Member` carries
                    -- it -- the declaration's flag means §3.4 assignability, which a member of a
                    -- record does not have in its own right.
                    local id = reserve()
                    local declaration = resolve_value(binding.value, scope, binding.name, false, nil, id)
                    if not declaration then pop(); return nil end
                    declare(Judge.Definition(id, binding.name, declaration, scope,
                        binding.span, binding.name_range))
                    bind(binding.name, id)
                    -- The member's value is the *definition*, so the record's shape is written
                    -- once: a name, a type from the definition, and §3.7's mutability.
                    members:insert(Judge.Member(binding.name,
                        Judge.Reference(id, binding.span), binding.mutable))
                end
                pop()
                return Judge.Aggregate(members, expr.span)
            end

            if Syntax.PositionalAggregate:isclassof(expr) then
                local members = L()
                for _, element in ipairs(expr.elements) do
                    -- The positional form of the same sentence: an element is a chain too, so an
                    -- element with items is resolved as one -- and it has no name, because a positional
                    -- member has none (§11.6's `Member(string? name, ...)`).
                    if #element.items > 0 then
                        local id = reserve()
                        local declaration = resolve_value(element, scope, nil, false, nil, id)
                        if not declaration then return nil end
                        declare(Judge.Definition(id, '', declaration, scope, element.span,
                            Source.Range(element.span, element.span)))
                        members:insert(Judge.Member(nil, Judge.Reference(id, element.span), false))
                    else
                        local value = resolve_initializer(element.terminal.value, scope)
                        if not value then return nil end
                        members:insert(Judge.Member(nil, value, false))
                    end
                end
                return Judge.Aggregate(members, expr.span)
            end

            -- §1.4/§3.1: braces around STAGES are a WORD -- and §11.1 makes a chain with stages an
            -- instance of its own, so a word literal in value position is a VALUE and denotes a
            -- definition holding it, exactly as a positional element's chain does. This branch was
            -- MISSING, so `let Pair = let T : Int { let a : Int let b : Int }` was a
            -- `Bug(NoLowering('initializer'))`: an internal error about a shape the parser produces on
            -- purpose (parse.lua turns a stage list into this word, with the aggregate of the stage
            -- names as its data terminal). A program the grammar accepts is not the compiler's own
            -- fault, whatever the spelling turns out to mean.
            --
            -- The name is GENERATED because an anonymous word is named by nothing -- and a word's
            -- name is not only a diagnostic: `Lower` builds `let_<name>_construct`, `_advance_k` and
            -- `_run` from it, so two anonymous words sharing `''` would be one C function defined
            -- twice. The `id` is what makes them two definitions in the first place.
            if Syntax.Word:isclassof(expr) then
                local id = reserve()
                local declaration = resolve_value(expr.chain, scope, nil, false, nil, id)
                if not declaration then return nil end
                declare(Judge.Definition(id, 'word' .. id, declaration, scope, expr.span,
                    Source.Range(expr.span, expr.span)))
                return Judge.Reference(id, expr.span)
            end

            -- `{}` is the empty aggregate and the Unit value (§3.3), so it is a literal too.
            -- §3.4's operators. Syntax and Semantic each own a `UnaryOp`/`BinaryOp` sum -- they are
            -- separate vocabularies and Semantic sits below Syntax -- so the names are MAPPED here
            -- rather than shared, and the mapping is data because the two lists are the same list.
            if Syntax.Unary:isclassof(expr) then
                local operand = resolve_initializer(expr.operand, scope)
                if not operand then return nil end
                local operator = Semantic[getmetatable(expr.operator).kind]
                if not operator then return fail(Report.bug(Report.NoLowering('unary op'), expr.span)) end
                return Judge.Unary(operator, operand, expr.span)
            end
            if Syntax.Binary:isclassof(expr) then
                local left = resolve_initializer(expr.left, scope)
                if not left then return nil end
                local right = resolve_initializer(expr.right, scope)
                if not right then return nil end
                local operator = Semantic[getmetatable(expr.operator).kind]
                if not operator then return fail(Report.bug(Report.NoLowering('binary op'), expr.span)) end
                return Judge.Binary(operator, left, right, expr.span)
            end

            -- §1.4: `move place` transfers ownership. The place is resolved like any other
            -- expression; whether the transfer is legal is the ownership scan's question.
            if Syntax.Move:isclassof(expr) then
                local place = resolve_initializer(expr.place, scope)
                if not place then return nil end
                return Judge.Move(place, expr.span)
            end

            -- §1.4: a partial move's path must be statically known, so a subplace is named by a
            -- constant. A runtime index names no subplace -- that is a gap in the compiler, not a
            -- fault in the program, which is why it is `Missing` and not `Reject`.
            if Syntax.Project:isclassof(expr) then
                local base = resolve_initializer(expr.base, scope)
                if not base then return nil end
                return Judge.Project(base, expr.name, expr.span)
            end

            if Syntax.Index:isclassof(expr) then
                local base = resolve_initializer(expr.base, scope)
                if not base then return nil end
                -- §12.1's row, DERIVED: "is this step a constant or a runtime index?" A CONSTANT one
                -- names a member by offset, which is a `Judge.Index`; anything else is a
                -- `Judge.Element`, whose offset is an EXPRESSION -- and which member it names is then a
                -- runtime fact, which is why `Contract` checks the members can be one type.
                if Syntax.Integer:isclassof(expr.index) then
                    return Judge.Index(base, tonumber((expr.index.spelling:gsub('_', ''))), expr.span)
                end
                local index = resolve_initializer(expr.index, scope)
                if not index then return nil end
                return Judge.Element(base, index, expr.span)
            end

            -- §11.3's literals. They are one case because they are one case everywhere else: a
            -- `Judge.Literal` carries the syntax expression, and it is Contract that reads a type
            -- off it and Lower that turns it into a belt literal.
            if Syntax.Integer:isclassof(expr) or Syntax.Float:isclassof(expr)
                or Syntax.Boolean:isclassof(expr)
                or Syntax.Unit:isclassof(expr) or Syntax.Text:isclassof(expr) then
                return Judge.Literal(expr)
            end
            if Syntax.Name:isclassof(expr) then
                local id, level = find(expr.name)
                if id and level and level < current_level then
                    id = capture_of(id, expr.name, expr.span, Source.Range(expr.span, expr.span), scope)
                end
                if not id then
                    -- §2.4: "a type word is a chain with `Type` domains and a data terminal" -- so a
                    -- TYPE NAME is an expression like any other, which is what lets `case Int` be a
                    -- label (§S51) without a new vocabulary. One definition per name, because a type
                    -- word is a value and two mentions of `Int` are two mentions of one value.
                    local type_ = type_of_name(expr.name)
                    if type_ then
                        type_words[expr.name] = type_words[expr.name] or (function()
                            local type_id = reserve()
                            -- The declaration carries what the name DENOTES, because a type name
                            -- is a value of the type it names: `Int` denotes `Semantic.Int`, not a
                            -- `Named('Int')`. A label for a sum subject is compared against the
                            -- alternatives, so this is the difference between `case Int` working and
                            -- not (§S51).
                            declare(Judge.Definition(type_id, expr.name,
                                Judge.Type(type_), scope, expr.span, Source.Range(expr.span, expr.span)))
                            return { id = type_id, type = type_ }
                        end)()
                        id = type_words[expr.name].id
                    end
                end
                if not id then
                    id = resolve_conversion(expr.name, expr.span,
                        Source.Range(expr.span, expr.span), scope)
                end
                if not id then return fail(Report.reject(Report.UnknownName, expr.span)) end
                return Judge.Reference(id, expr.span)
            end
            -- `with` is left-associative, so the callee is itself an initializer: `f with a with b`
            -- is `Apply(Apply(f, a), b)` and the callee of the outer one is not a name.
            -- §2.6: `import` is "a dictionary entry in the construction phase, not a reserved
            -- spelling, so a lexical binding of that name still wins". That is why this tests the
            -- SCOPE before the name: `let import = ...` shadows it, and then the form is not an
            -- import at all.
            --
            -- Its one expression slot is the path, which must be a constant Text. The result is the
            -- imported file's TERMINAL -- which is exactly what `resolve_value` already returns for
            -- a chain, because a file IS a chain. So the import introduces one definition holding
            -- the file's declaration and the expression denotes it: a zero-stage word for a data
            -- terminal (which §S20 makes a value), or a word the importer advances and invokes.
            if Syntax.Specialize:isclassof(expr) and Syntax.Name:isclassof(expr.word)
                and expr.word.name == 'import' and not find('import') then
                return resolve_import(expr, scope)
            end
            if Syntax.Specialize:isclassof(expr) then
                local callee = resolve_initializer(expr.word, scope)
                if not callee then return nil end
                -- §S110/§S112: an application whose NEXT STAGE is a `Type` stage is an INSTANTIATION,
                -- and `instantiate` is where that lives -- because the call form asks it too.
                local node, disposition, value = instantiate(callee, expr.argument, expr.span, scope)
                if disposition == 'consumed' then return node end
                if disposition == 'deduced' then
                    if not node then return nil end
                    return Judge.Apply(node, value, expr.span)
                end
                local argument = resolve_initializer(expr.argument, scope)
                if not argument then return nil end
                return Judge.Apply(callee, argument, expr.span)
            end
            -- §1.2's invocation stays its own form through resolution rather than being rewritten
            -- into an application here, because the two are NOT interchangeable: `f()` supplies no
            -- stage and is legal only where the word has none. Lower folds the arguments, so the
            -- operations are identical for a non-empty list, and `f()` is the one case that has no
            -- `with` spelling at all.
            if Syntax.Invoke:isclassof(expr) then
                local callee = resolve_initializer(expr.word, scope)
                if not callee then return nil end
                local arguments = L()
                for _, argument in ipairs(expr.arguments) do
                    -- §S112: a TYPE argument instantiates in the CALL form too -- `id(Bool, true)` is
                    -- `id with Bool with true` (§S88). What the call form does NOT become is a partial
                    -- application: §1.2 makes invocation transient SATURATION, so every stage is supplied
                    -- or the program is `Undersaturated` (§S62) -- which is why this instantiates in
                    -- place instead of desugaring into `Specialize`.
                    local node, disposition, value = instantiate(callee, argument, expr.span, scope)
                    if disposition == 'consumed' then
                        if not node then return nil end
                        callee = node
                    elseif disposition == 'deduced' then
                        if not node then return nil end
                        callee = node
                        arguments:insert(value)
                    else
                        local resolved = resolve_initializer(argument, scope)
                        if not resolved then return nil end
                        arguments:insert(resolved)
                    end
                end
                return Judge.Invoke(callee, arguments, expr.span)
            end
            return fail(Report.bug(Report.NoLowering('initializer'), expr.span))
        end

        -- A `do` body: a scope of statements. Each `let` is a declaration in it (§1.4), and the
        -- alternatives are the language's statement forms -- a closed set, which is what makes
        -- this a vocabulary and not a clone of the syntax tree.
        resolve_body = function(statements, scope)
            push()
            local resolved = L()
            for _, statement in ipairs(statements) do
                if Syntax.Local:isclassof(statement) then
                    local binding = statement.binding
                    if duplicate(binding.name, binding.name_range.start) then pop(); return nil end
                    local id = reserve()
                    local declared, ok = annotation_of(binding)
                    if not ok then pop(); return nil end
                    local declaration = resolve_value(binding.value, Judge.Lexical(id),
                        binding.name, binding.mutable, declared, id)
                    if not declaration then pop(); return nil end
                    declare(Judge.Definition(id, binding.name, declaration, scope,
                        binding.span, binding.name_range))
                    bind(binding.name, id)
                    resolved:insert(Judge.Local(id))
                elseif Syntax.Return:isclassof(statement) then
                    local value
                    if statement.value then
                        value = resolve_initializer(statement.value, scope)
                        if not value then pop(); return nil end
                    end
                    resolved:insert(Judge.Return(value, statement.span))
                elseif Syntax.Discard:isclassof(statement) then
                    local value = resolve_initializer(statement.value, scope)
                    if not value then pop(); return nil end
                    resolved:insert(Judge.Discard(value, statement.span))
                elseif Syntax.Switch:isclassof(statement) then
                    -- §12.1: the subject is resolved once, and each label is an EXPRESSION that
                    -- Contract will check against the subject's type. An arm is its own lexical
                    -- scope for the same reason an `if` arm is (§7.2).
                    local subject = resolve_initializer(statement.subject, scope)
                    if not subject then pop(); return nil end
                    local cases = L()
                    for _, arm in ipairs(statement.cases) do
                        -- §S60: a label SAYS which kind it is, so resolving one is a case over two
                        -- kinds rather than a guess about what a name denotes. A SHAPE is a type --
                        -- §2.4 makes a type an expression, and a structural shape has no other
                        -- spelling -- and a CONSTANT is a value.
                        local labels = L()
                        for _, label in ipairs(arm.labels) do
                            if Syntax.Shape:isclassof(label) then
                                local type_ = resolve_type(label.type)
                                if not type_ then pop(); return nil end
                                labels:insert(Judge.Shape(type_, nil))
                            else
                                local value = resolve_initializer(label.value, scope)
                                if not value then pop(); return nil end
                                labels:insert(Judge.Constant(value))
                            end
                        end
                        -- §S59: an arm that matched by SHAPE binds what it matched. A binder needs
                        -- exactly ONE shape -- two labels would bind two types -- and its own type
                        -- is that shape's, read straight off the label rather than derived from a
                        -- name, which is what `type_of_name` was being asked to do here.
                        local binds
                        if arm.binds then
                            local shape = #arm.labels == 1 and arm.labels[1]
                            if not (shape and Syntax.Shape:isclassof(shape)) then
                                pop()
                                return fail(Report.reject(Report.InvalidCaseLabel, arm.span))
                            end
                            local id = reserve()
                            declare(Judge.Definition(id, arm.binds,
                                Judge.Bound(labels[1].denotes), scope, arm.span,
                                Source.Range(arm.span, arm.span)))
                            -- Visible in the arm and nowhere else, so the arm's scope is pushed
                            -- around the body alone.
                            push()
                            bind(arm.binds, id)
                            binds = id
                        end
                        local body = resolve_body(arm.body, scope)
                        if not body then pop(); return nil end
                        if binds then pop() end
                        cases:insert(Judge.Case(labels, binds, body, arm.span))
                    end
                    local otherwise = resolve_body(statement.otherwise, scope)
                    if not otherwise then pop(); return nil end
                    resolved:insert(Judge.Switch(subject, cases, otherwise, statement.span))
                elseif Syntax.Assign:isclassof(statement) then
                    -- §3.4: the destination is evaluated first, "establishing the place without
                    -- replacing it", and then the right-hand side. That order is why both are
                    -- resolved here, left to right, and why Lower stores rather than rebinds.
                    local place = resolve_initializer(statement.place, scope)
                    if not place then pop(); return nil end
                    local value = resolve_initializer(statement.value, scope)
                    if not value then pop(); return nil end
                    resolved:insert(Judge.Assign(place, value, statement.span))
                elseif Syntax.If:isclassof(statement) then
                    local condition = resolve_initializer(statement.condition, scope)
                    if not condition then pop(); return nil end
                    -- §7.2: each arm has its own lexical scope, so each is a body of its own.
                    local yes = resolve_body(statement.yes, scope)
                    if not yes then pop(); return nil end
                    local no = resolve_body(statement.no, scope)
                    if not no then pop(); return nil end
                    resolved:insert(Judge.If(condition, yes, no, statement.span))
                elseif Syntax.While:isclassof(statement) then
                    local condition = resolve_initializer(statement.condition, scope)
                    if not condition then pop(); return nil end
                    local body = resolve_body(statement.body, scope)
                    if not body then pop(); return nil end
                    resolved:insert(Judge.While(condition, body, statement.span))
                elseif Syntax.Break:isclassof(statement) then
                    resolved:insert(Judge.Break(statement.span))
                elseif Syntax.Continue:isclassof(statement) then
                    resolved:insert(Judge.Continue(statement.span))
                else
                    -- Every statement form is handled now, so reaching here is a broken invariant
                    -- rather than a gap: a new form costs a constructor AND a case, and forgetting
                    -- the case is a Bug rather than a silently dropped statement.
                    pop()
                    return fail(Report.bug(Report.NoLowering('statement'), statement.span))
                end
            end
            pop()
            return resolved
        end

        push()     -- the module scope
        local members = L()
        for _, item in ipairs(program.file.items) do
            -- A top-level name is a namespace member whether it is written or DECLARED, because
            -- §2.6 is about names and not about where the name came from.
            if Syntax.Host:isclassof(item) then
                if not resolve_host(item) then pop(); return k_diag(unit, diagnostic) end
            elseif Syntax.Extern:isclassof(item) then
                if duplicate(item.name, item.name_range.start) then
                    pop(); return k_diag(unit, diagnostic)
                end
                local template = resolve_extern(item, nil)
                if not template then pop(); return k_diag(unit, diagnostic) end
                local id = reserve()
                declare(Judge.Definition(id, item.name, Judge.Word(template, nil), nil,
                    item.span, item.name_range))
                bind(item.name, id)
                members:insert(Judge.Member(item.name, Judge.Reference(id, item.span), false))
            elseif Syntax.Prelude:isclassof(item) then
                local binding = item.binding
                if duplicate(binding.name, binding.name_range.start) then
                    pop()
                    return k_diag(unit, diagnostic)
                end
                local id = reserve()
                -- §11.3 reads a type off a term where permitted, but a DECLARED annotation is a
                -- claim, not a reading -- so it is resolved here and CARRIED, because only Contract
                -- knows the value's type and only Contract can compare the two.
                local declared, ok = annotation_of(binding)
                if not ok then pop(); return k_diag(unit, diagnostic) end
                local declaration = resolve_value(binding.value, Judge.Lexical(id), binding.name,
                    binding.mutable, declared, id)
                if not declaration then pop(); return k_diag(unit, diagnostic) end
                declare(Judge.Definition(id, binding.name, declaration, nil,
                    binding.span, binding.name_range))
                bind(binding.name, id)
                members:insert(Judge.Member(binding.name, Judge.Reference(id, binding.span),
                    binding.mutable))
            else
                pop()
                return k_diag(unit, Report.bug(Report.NoLowering('top-level item'), program.file.span))
            end
        end
        -- The entry file's namespace is left to `Lower`, which assembles it from the definitions it
        -- can see (they are the ones with no `scope`). This is the SAME rule `resolve_value` applies
        -- to an imported file's chain -- "a file with no written terminal exposes the named aggregate
        -- of its own prelude bindings" -- and it has two implementations for one reason: the entry
        -- file is a module and not a definition, so its namespace is a `Belt` record rather than a
        -- `Judge.Initializer`, and building it here would need `rep` to map a WORD type, which is
        -- `Lower`'s `residual_type` and not `rep`'s business. Unifying them is a change to the
        -- semantic-to-belt mapping, not to this rule.
        local namespace
        if program.file.terminal then
            namespace = resolve_initializer(program.file.terminal.value, nil)
            if not namespace then pop(); return k_diag(unit, diagnostic) end
        end
        pop()

        local resolved = Judge.Resolved(definitions, namespace, L{})
        unit.ambient.resolved = resolved
        return k_ok(unit, resolved)
    end

    return Resolve
end
