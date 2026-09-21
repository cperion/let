-- What the analyses produce: definitions, initializers, terminals, statements, interfaces.
--
-- A `Binder` is a *reference* to a declaration; a `Definition` **is** the declaration. Resolve
-- produces definitions plus a resolved `Initializer` per declaration, Contract fills one
-- `Interface` per definition, and a value binding is not a special case -- a data terminal with no
-- stages *is* a value, so its interface is a zero-stage data word (spec §11.1, DESIGN §S20).
--
-- **A declaration carries its own payload.** A stage has a declared type, a value has an
-- initializer, a word has a template and a terminal, and nothing else does; three optional fields
-- on `Definition` would be a product with variant-specific axes, which is the smell this design
-- removes. So the alternative carries the field, and `Definition` stays flat.
--
-- `Initializer` is why a resolution is not a side table: a name use is re-shaped into
-- `Reference(id)`, so no phase re-runs lexical scoping or keys a fact by node identity. And
-- `Terminal`/`Stmt` are the *closed* set of what a word's body can be -- which is what makes them a
-- vocabulary rather than a clone of the syntax tree.
--
-- NOTE: `asdl.lua` has no comment syntax inside a `Define`, so nothing here may contain `--`.
return function(context)
    local J
    context:Define [[
module Judge {
    Binder      = Lexical(number id) | Entry(Chain.Template template)
    Declaration = Value(Initializer value, boolean mutable, Semantic.Type? declared)
                | Word(Chain.Template word, Terminal? terminal)
                | Type(Semantic.Type denotes)
                | Host(string? destroys, number? borrows)
                | Namespace
                | Bound(Semantic.Type declared)
    Definition  = (number id, string name, Declaration declaration, Binder? scope,
                   Source.Span span, Source.Range name_range)
    Resolved    = (Definition* definitions, Initializer? namespace, Chain.Capture* captures)

    Initializer = Literal(Syntax.Expr value)
                | Reference(number definition, Source.Span span)
                | Apply(Initializer callee, Initializer argument, Source.Span span)
                | Invoke(Initializer callee, Initializer* arguments, Source.Span span)
                | Unary(Semantic.UnaryOp operator, Initializer operand, Source.Span span)
                | Binary(Semantic.BinaryOp operator, Initializer left, Initializer right,
                         Source.Span span)
                | Aggregate(Member* members, Source.Span span)
                | Move(Initializer place, Source.Span span)
                | Project(Initializer base, string name, Source.Span span)
                | Index(Initializer base, number offset, Source.Span span)
                   | Element(Initializer base, Initializer index, Source.Span span)
    Member      = (string? name, Initializer value, boolean mutable)

    Terminal    = Data(Initializer value) | Body(Stmt* statements)
    Stmt        = Local(number definition)
                | Return(Initializer? value, Source.Span span)
                | Discard(Initializer value, Source.Span span)
                | If(Initializer condition, Stmt* yes, Stmt* no, Source.Span span)
                | While(Initializer condition, Stmt* body, Source.Span span)
                | Break(Source.Span span) | Continue(Source.Span span)
                | Assign(Initializer place, Initializer value, Source.Span span)
                | Switch(Initializer subject, Case* cases, Stmt* otherwise, Source.Span span)
    Label       = Shape(Semantic.Type denotes, number? alternative) | Constant(Initializer value)
    Case        = (Label* labels, number? binds, Stmt* body, Source.Span span)

    Parameter   = (string name, Semantic.Capability capability, Semantic.Type type)
    Interface   = (Parameter* stages, Semantic.Type result,
                   Chain.Terminal terminal, boolean borrowed)
    Typed       = (number definition, Interface interface)
    Program     = (Definition* definitions, Initializer? namespace,
                   Semantic.Type? namespace_type, Typed* typed)

    State       = Initialized | Moved

    Answer      = Known(Atom atom) | Runtime(Belt.Type type)
    Atom        = Int(number value) | Bool(boolean value) | Unit | Text(string value)
                | Bundle(Atom* fields)
    Fate        = Immediate | Materialized | Dropped
}
    ]]

    local J = context.Judge
    local J = context.Judge
    -- The walk below is STRUCTURAL, over `Chain.Template`'s items as well as over judge nodes, so it
    -- needs the layer that owns a stage -- and it asks whether a declared type is a WORD, which is a
    -- choice `Semantic` owns.
    local Chain, Semantic = context.Chain, context.Semantic
    -- `Answer` is a LATTICE (DESIGN §5.3), so it has a join method rather than a caller that
    -- switches on it. `Runtime` is the top and absorbs; two constants agree only if they are the
    -- same VALUE, and that is why the comparison is structural rather than by object identity --
    -- two producers that fold to the same constant agree, whichever of them produced it.
    --
    -- The fallback type is passed in rather than carried, because `Known` does not name a belt
    -- type, and a join that could not produce `Runtime` would not be a lattice.
    local function same_atom(a, b)
        if J.Int:isclassof(a) then return J.Int:isclassof(b) and a.value == b.value end
        if J.Bool:isclassof(a) then return J.Bool:isclassof(b) and a.value == b.value end
        if J.Unit:isclassof(a) then return J.Unit:isclassof(b) end
        if J.Text:isclassof(a) then return J.Text:isclassof(b) and a.value == b.value end
        if J.Bundle:isclassof(a) then
            if not J.Bundle:isclassof(b) or #a.fields ~= #b.fields then return false end
            for i = 1, #a.fields do
                if not same_atom(a.fields[i], b.fields[i]) then return false end
            end
            return true
        end
        return false
    end
    J.same_atom = same_atom

    -- §1.1's arrow spine, read off the DECLARATION rather than off a type: which word does this value
    -- denote, and how many stages does it already hold. It lives HERE because TWO layers ask it and
    -- the answer must be one answer -- `Resolve` turns a name in type position into the type of the
    -- value it denotes (§S99), and `Lower` selects the callee of an application (`word_of`, §S92).
    -- Two copies of this walk is exactly the defect this design keeps finding, and it is why
    -- `let f : add2` -- a PARTIAL application's name used as a type -- was `UnknownType` while
    -- `add2 with 3` lowered: the walk knew a word name and a plain alias, and stopped at an `Apply`.
    --
    -- It is STRUCTURAL, so it needs no types and can run before `Contract` does: a word name is at
    -- prefix 0; a value binding is a second name for its value; a capture is a second name for
    -- somebody else's storage (§3.2), which is the same step; a `move` names what it moved; a word
    -- reached through a record is the member the record holds (§2.6); a stage whose declared type is
    -- a WORD names that word (§S99, and the nominal type is what makes the callee knowable without a
    -- vtable); and an application is one prefix further along.
    --
    -- `lookup` maps a definition id to its DECLARATION, because the layers keep that table in
    -- different shapes -- Resolve's `by_id` holds the definition and the others hold the declaration
    -- -- so the question is asked through the one thing both can answer.
    local function stage_count(word)
        local count = 0
        for _, item in ipairs(word.items) do
            if Chain.Stage:isclassof(item) then count = count + 1 end
        end
        return count
    end

    function J.word_of(lookup, initializer)
        local function walk(node, hops)
            if hops > 8 or not node then return nil end
            if J.Reference:isclassof(node) then
                local declaration = lookup(node.definition)
                if J.Word:isclassof(declaration) then return node.definition, 0 end
                -- A value binding, and a capture is one -- its declaration is a `Value` holding a
                -- reference to the storage it captures -- so following it is the difference between
                -- typing the frame and typing its answer.
                if J.Value:isclassof(declaration) then return walk(declaration.value, hops + 1) end
                -- A stage whose declared type is a word: `Contract` reads the callee off the TYPE and
                -- this reads it off the declaration, which is the same answer.
                if J.Bound:isclassof(declaration) and declaration.declared
                        and Semantic.Word:isclassof(declaration.declared) then
                    return declaration.declared.template, declaration.declared.prefix
                end
                return nil
            end
            if J.Move:isclassof(node) then return walk(node.place, hops + 1) end
            if J.Project:isclassof(node) then
                -- A word reached THROUGH a record: an imported file's namespace IS one, and §2.6 makes
                -- the projection the only way to reach a word inside it (`other.twice`).
                if not J.Reference:isclassof(node.base) then return nil end
                local declaration = lookup(node.base.definition)
                while declaration and J.Value:isclassof(declaration)
                        and J.Reference:isclassof(declaration.value) and hops < 8 do
                    declaration = lookup(declaration.value.definition)
                    hops = hops + 1
                end
                if declaration and J.Value:isclassof(declaration)
                        and J.Aggregate:isclassof(declaration.value) then
                    for _, member in ipairs(declaration.value.members) do
                        if member.name == node.name and J.Reference:isclassof(member.value) then
                            return walk(member.value, hops + 1)
                        end
                    end
                end
                -- §S110: and a projection whose base is a STAGE -- `let p : { op : inc1 }` then `p.op(x)`
                -- -- names the field's word through the DECLARED TYPE. That is the dictionary-as-a-record
                -- pattern, and it works for the same reason a `Bound` does (§S99): a field whose type is
                -- a WORD names that word, and the type is in the declaration, so nothing here needs
                -- `Contract` to have run. The value path above and this one are the two ways a record
                -- can be known: by what it HOLDS (an aggregate value) and by what it IS (a record type).
                local declared = declaration and declaration.declared
                if Semantic.Aggregate:isclassof(declared) then
                    for _, field in ipairs(declared.fields) do
                        if field.name == node.name and Semantic.Word:isclassof(field.type) then
                            return field.type.template, field.type.prefix
                        end
                    end
                end
                return nil
            end
            if not J.Apply:isclassof(node) then return nil end
            local template, prefix = walk(node.callee, hops + 1)
            if not template then return nil end
            local declaration = lookup(template)
            local word = declaration and declaration.word
            if not word then return nil end
            if prefix + 1 < stage_count(word) then return template, prefix + 1 end
            -- The application SATURATES the word, so what it denotes is the word's own RESULT -- and
            -- that is a word exactly when the terminal yields one (§S3): a data terminal's result is
            -- the type of its value, and a `do` or host terminal DECLARES it, so the declaration
            -- already says. `Pair with 5` above is the first case and `do : square` is the second.
            if prefix + 1 > stage_count(word) then return nil end
            local result
            local terminal = declaration.terminal
            if terminal and J.Data:isclassof(terminal) then
                local inner, at = walk(terminal.value, hops + 1)
                if inner then result = Semantic.Word(inner, at) end
            else
                result = word.result
            end
            if result and Semantic.Word:isclassof(result) then
                return result.template, result.prefix
            end
            return nil
        end
        return walk(initializer, 0)
    end

    function J.Answer:join(other, type) return J.Runtime(type) end
    function J.Runtime:join(other, type) return self end
    function J.Known:join(other, type)
        if J.Known:isclassof(other) and same_atom(self.atom, other.atom) then return self end
        return J.Runtime(type)
    end
end
