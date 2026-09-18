-- Tokens -> Syntax.Program (spec §3.1).
--
-- A program **is** a binding chain (spec §2.6): its items are the top-level bindings and its
-- terminal, if written, replaces the namespace. So the program and a binding value are parsed by
-- the same rule, and a chain item is the same in both positions:
--
--     let NAME [own] [mut] [: type]        a stage -- an unsatisfied input
--     let NAME [mut] [: type] = <chain>    a prelude -- a completed binding
--
-- The split is decided by the `=` alone, and that is not a convenience: spec §3.1 gives a stage no
-- terminal to read a type from, so a stage **must** declare its type word, and its absence is an
-- error rather than an inference.
--
-- **Items are greedy; expressions are not.** Items are consumed while the next token can begin one
-- (`let`, `extern`, `host`), and the first token that cannot begins the terminal -- so the boundary
-- between two ITEMS needs no separator, because the keywords delimit themselves.
--
-- An APPLICATION, by contrast, is the keyword `with` and never adjacency (§S88). Two expressions in a
-- row are a mistake the parser reports, which is what lets a parenthesized expression AFTER `with` be
-- a group (`sum with (square with 3)`) -- unreachable while a word followed by `(` was an invocation.
-- And `;` means exactly one thing now: an item's value is an expression and so is a written terminal,
-- so THAT boundary needs a separator. `f(x); g(y)` is not why it exists.
return function(V)
    local Syntax, Source, Semantic, L = V.Syntax, V.Source, V.Semantic, V.List

    return function(tokens, file, text)
        local at = 1
        local function peek() return tokens[at] end
        local function kind() local t = tokens[at]; return t and t.kind end
        local function what()
            local t = tokens[at]
            return t and (t.spelling ~= '' and t.spelling or t.kind) or 'EOF'
        end
        local function locate(t) return t and ('%s:%d:%d'):format(file, t.span.line, t.span.column) or file end
        local function take(want)
            local t = tokens[at]
            if not t or t.kind ~= want then
                error(('%s: expected %s, found %s'):format(locate(t), want, what()), 0)
            end
            at = at + 1
            return t
        end
        local function accept(want)
            if kind() == want then local t = tokens[at]; at = at + 1; return t end
        end
        -- §12.0 makes `true` and `false` lexical NAMES rather than keywords, so every place that
        -- needs to know whether a name IS a Bool literal asks here. One owner, because a place that
        -- forgets is a place that reads `true` as a type name or as a dictionary word.
        local function is_boolean(spelling)
            return spelling == 'true' or spelling == 'false'
        end
        -- §3.4's assignment needs a lookahead, and this is why: a name can begin an expression, so
        -- `let n = 0` followed by `n = 1` would read that `n` as the start of a second expression and
        -- then choke on the `=`. A name followed by `=` therefore begins a STATEMENT.
        --
        -- `let y = x` followed by `y` is the other side of the same coin: two expressions in a row,
        -- which is a mistake (§S88) rather than an application -- so `let y = x; y` still needs its
        -- `;`, and the reason is that an item's value and a written TERMINAL are both expressions.
        -- None of this is about how application is spelled.
        -- Whether an expression could begin here -- which is what the parser has to know in two
        -- places: to report two expressions in a row (§S88), and to see an assignment's `=`.
        --
        -- A name normally continues one -- `f x` is a single application -- except when it is the
        -- destination of §3.4's assignment, and that is not a one-token question: `n = 1` is easy,
        -- but `r.x = 1` has its `=` past the suffixes. So the lookahead IS the postfix grammar, run
        -- forward without consuming: a name, then any sequence of `.name` and `[...]`, then `=`.
        -- Anything else means the name is an argument, as before.
        local function assignment_ahead()
            if kind() ~= 'name' then return false end
            local ahead = at + 1
            while true do
                local token = tokens[ahead]
                if not token then return false end
                if token.kind == '.' then
                    if not (tokens[ahead + 1] and tokens[ahead + 1].kind == 'name') then return false end
                    ahead = ahead + 2
                elseif token.kind == '[' then
                    local depth, scan = 1, ahead + 1
                    while depth > 0 do
                        local inner = tokens[scan]
                        if not inner then return false end
                        if inner.kind == '[' then depth = depth + 1
                        elseif inner.kind == ']' then depth = depth - 1 end
                        scan = scan + 1
                    end
                    ahead = scan
                else
                    return token.kind == '='
                end
            end
        end

        -- §3.4's `specialization_atom`: "literal | NAME { postfix_suffix } | aggregate_literal".
        -- So the tokens that continue an expression are exactly the ones that can BEGIN one as an
        -- argument -- and leaving one out inverts the grammar silently: `f "x"` stopped being an
        -- application the moment Text literals existed, and the file parser then read the `"x"` as
        -- its own terminal and failed on the next `let`.
        -- §11.2's `TypeExpr`, all six alternatives. `->` is the loosest and right-nested -- §11.1
        -- reads a word's type as "unary right-nested arrows" -- and `|` sits inside it, so
        -- `A -> B | C` is `A -> (B | C)`. A record's fields are `name : T` with an optional `mut`,
        -- which is §3.7's interior mutability in a TYPE; a tuple's members have no names at all,
        -- because §3.3 gives a positional element no declaration to be named by.
        -- The three levels are mutually recursive -- a record's field is a type and a record IS a
        -- type -- so they are declared together and assigned in order.
        local parse_type, parse_type_sum, parse_type_atom

        parse_type = function()
            local from = parse_type_sum()
            if accept('->') then return Syntax.Arrow(from, parse_type(), from.span) end
            return from
        end

        parse_type_sum = function()
            local left = parse_type_atom()
            while accept('|') do left = Syntax.Sum(left, parse_type_atom(), left.span) end
            return left
        end

        parse_type_atom = function()
            local t = peek()
            if t.kind == 'name' then
                at = at + 1
                return Syntax.Ref(t.spelling, t.span)
            end
            if t.kind == '{' then
                at = at + 1
                local fields = L()
                if not accept('}') then
                    repeat
                        -- `name mut : T`, the same order a STAGE uses (`x own : Int`), because
                        -- §3.7's mutability is a qualifier on the declaration and not on the type.
                        local name = take('name')
                        local mutable = accept('mut') ~= nil
                        take(':')
                        fields:insert(Syntax.TypeField(name.spelling, mutable, parse_type(),
                            name.span))
                    until not accept(',')
                    take('}')
                end
                return Syntax.Record(fields, t.span)
            end
            -- §11.2's `Do(TypeExpr result)`: the type of a chain whose terminal is a body. In TYPE
            -- position `do` cannot begin anything else, so it needs no lookahead.
            if t.kind == 'do' then
                at = at + 1
                return Syntax.Do(parse_type(), t.span)
            end
            if t.kind == '(' then
                at = at + 1
                local elements = L{parse_type()}
                while accept(',') do elements:insert(parse_type()) end
                take(')')
                return Syntax.Tuple(elements, t.span)
            end
            error(('%s: expected a type, found %s'):format(locate(t), what()), 0)
        end

        local function parse_annotation()
            if accept(':') then return parse_type() end
            return nil
        end

        -- A primary is a literal or a name. `true` and `false` are lexical names, not keywords.
        -- Forward declaration: an aggregate's members are chain items, which are parsed below.
        -- Forward declarations, because the grammar is a cycle: an aggregate's members are chain
        -- items, an index is an expression and an expression may be an index, and `(` groups an
        -- expression inside a primary. Every one of them is declared before the first use rather
        -- than being left to resolve as a global -- which is a silent nil call, not an error.
        local parse_aggregate, parse_postfix, separate, parse_if, parse_while, parse_switch, parse_expr

        local function parse_primary()
            local t = peek()
            if t.kind == 'int' then
                at = at + 1
                return Syntax.Integer(t.spelling, t.span)
            end
            if t.kind == 'float' then
                at = at + 1
                return Syntax.Float(t.spelling, t.span)
            end
            -- §11.3's Text literal. The token's VALUE is the unescaped text, so the spelling of an
            -- escape never reaches the judgment -- which is why `Syntax.Text` carries the value and
            -- not the source text.
            if t.kind == 'text' then
                at = at + 1
                return Syntax.Text(t.value, t.span)
            end
            if t.kind == 'name' and is_boolean(t.spelling) then
                at = at + 1
                return Syntax.Boolean(t.spelling == 'true', t.span)
            end
            if t.kind == 'name' then
                at = at + 1
                return Syntax.Name(t.spelling, t.span)
            end
            -- §1.4's call-site form: `move place` transfers ownership. It is a prefix on a place,
            -- so it sits with the primaries rather than with the application.
            if t.kind == 'move' then
                at = at + 1
                return Syntax.Move(parse_postfix(), t.span)
            end
            -- §3.4's `primary` includes prefix parentheses. `(` is ALSO the invocation suffix, and
            -- the two never collide: an invocation is parsed by `parse_postfix` on a value it
            -- already has, while grouping is reached only where a primary can begin.
            if t.kind == '(' then
                at = at + 1
                local inner = parse_expr()
                take(')')
                return inner
            end
            if t.kind == '{' then
                at = at + 1
                return parse_aggregate(t)
            end
            error(('%s: expected an expression, found %s'):format(locate(t), what()), 0)
        end

        -- `with` is application, ONE argument at a time and left-associated, so `f with a with b` is
        -- the chain adjacency used to mean. A prefix operator binds tighter than `with` -- `f with -x`
        -- is one argument and not a negative application -- which is why the argument is parsed by
        -- `parse_operator` and not by `parse_postfix`: the latter would refuse the `-`.
        -- Forward declaration: an item's value is a chain, and a chain's item is an item.
        local parse_chain

        -- §3.4's tightest level: `.` and `[]` are postfix, so a place is one expression and binds
        -- tighter than the `with` that supplies stages.
        -- §3.4's postfix suffix: `.`, `[]` and invocation. They bind tighter than everything, so
        -- a place is one expression and `f(x).y[0]` is a place too.
        parse_postfix = function()
            local value = parse_primary()
            while true do
                if accept('.') then
                    local name = take('name')
                    value = Syntax.Project(value, name.spelling,
                        Source.Range(name.span, name.span), value.span)
                elseif accept('[') then
                    local index = parse_expr()
                    take(']')
                    value = Syntax.Index(value, index, value.span)
                elseif accept('(') then
                    -- §1.2's invocation. It saturates transiently, and `f()` -- no arguments at
                    -- all -- is the one thing `with` cannot write: it runs the word's
                    -- terminal without supplying a stage.
                    local arguments = L()
                    if not accept(')') then
                        arguments:insert(parse_expr())
                        while accept(',') do arguments:insert(parse_expr()) end
                        take(')')
                    end
                    value = Syntax.Invoke(value, arguments, value.span)
                else
                    return value
                end
            end
        end

        -- §3.4's precedence, taken from the spec's own table and written as DATA rather than as a
        -- chain of twelve functions. Each level is `{ associativity, { token = operator } }`, the
        -- levels run loosest to tightest, and a non-associative level stops after one operator --
        -- so `a < b < c` is a parse error rather than a silent `(a < b) < c`.
        local LEVELS = {
            { 'left', { ['or'] = Syntax.Or } },
            { 'left', { ['and'] = Syntax.And } },
            { 'none', { ['=='] = Syntax.Equal, ['!='] = Syntax.NotEqual } },
            { 'none', { ['<'] = Syntax.Less, ['<='] = Syntax.LessEqual,
                        ['>'] = Syntax.Greater, ['>='] = Syntax.GreaterEqual } },
            { 'left', { ['|'] = Syntax.BitOr } },
            { 'left', { ['^'] = Syntax.BitXor } },
            { 'left', { ['&'] = Syntax.BitAnd } },
            { 'left', { ['<<'] = Syntax.ShiftLeft, ['>>'] = Syntax.ShiftRight } },
            { 'left', { ['+'] = Syntax.Add, ['-'] = Syntax.Subtract } },
            { 'left', { ['*'] = Syntax.Multiply, ['/'] = Syntax.Divide, ['%'] = Syntax.Remainder } },
        }
        local PREFIX = { ['not'] = Syntax.Not, ['-'] = Syntax.Negate, ['~'] = Syntax.BitNot }

        local parse_prefix, parse_specialization

        local function parse_level(level)
            if level > #LEVELS then return parse_prefix() end
            local associativity, operators = LEVELS[level][1], LEVELS[level][2]
            local value = parse_level(level + 1)
            while true do
                local operator = operators[kind()]
                if not operator then return value end
                at = at + 1
                local right = parse_level(level + 1)
                value = Syntax.Binary(operator, value, right, value.span)
                if associativity == 'none' then return value end
            end
        end

        -- Level 3 is PREFIX, and it binds tighter than every operator but looser than `with` -- so
        -- `f with x + 1` is `(f with x) + 1`, and a prefix operator is an ARGUMENT rather than part
        -- of the application: `f with -1` applies `f` to a negative literal. Adjacency could not
        -- write that -- `f -1` had to be the subtraction -- which is another way of saying that an
        -- application with no spelling makes the grammar guess.
        parse_prefix = function()
            local operator = PREFIX[kind()]
            if not operator then return parse_specialization() end
            local t = peek()
            at = at + 1
            return Syntax.Unary(operator, parse_prefix(), t.span)
        end

        -- Prefix operators and postfix suffixes, with NO application: the thing `with` takes.
        parse_operator = function()
            local operator = PREFIX[kind()]
            if not operator then return parse_postfix() end
            local t = peek()
            at = at + 1
            return Syntax.Unary(operator, parse_operator(), t.span)
        end

        -- Two adjacent expressions WERE an application and are now a mistake, so this is where the
        -- parser says so. It is the predicate the old greediness used -- §S40's `starts_expression`,
        -- which had to be taught `{` and `text` -- kept for the one job it can still do: telling a
        -- writer what they meant. A name that is an assignment TARGET is not one of these (`x = 1` is
        -- a statement), which is why the lookahead matters.
        local function continues_an_expression()
            if kind() == 'int' or kind() == 'text' or kind() == '{' then return true end
            if kind() ~= 'name' then return false end
            return not assignment_ahead()
        end

        parse_specialization = function()
            local value = parse_operator()
            while accept('with') do
                value = Syntax.Specialize(value, parse_operator(), value.span)
            end
            if continues_an_expression() then
                error(('%s: two adjacent expressions. An application is `with` (`f with a`), and a '
                    .. 'chain\'s TERMINAL is separated from the items before it by `;`')
                    :format(locate(peek())), 0)
            end
            return value
        end

        parse_expr = function() return parse_level(1) end

        -- §11.2's `Item.Extern`, and §3.6's reason for it: the host's vocabulary is DECLARED in
        -- source rather than registered by an embedding. The declaration is the whole contract --
        -- stages, their capabilities and types, the result, and purity -- because that is what the
        -- compiler holds a host to. The optional quoted symbol is the C name when it differs from
        -- the Let name, which is `Extern.symbol` and not a second name.
        local function parse_extern()
            local kw = take('extern')
            local pure = accept('pure') ~= nil
            local name = take('name')
            local name_range = Source.Range(name.span, name.span)
            local symbol
            if kind() == 'text' then symbol = take('text').value end
            take('(')
            local parameters = L()
            if not accept(')') then
                repeat
                    local spec = take('name')
                    local own = accept('own') ~= nil
                    local mutable = accept('mut') ~= nil
                    local constraint = parse_annotation()
                    if not constraint then
                        error(("%s: a host stage must declare its type: %s")
                            :format(locate(kw), spec.spelling), 0)
                    end
                    local capability = own and (mutable and Semantic.OwnMut or Semantic.Own)
                                               or (mutable and Semantic.Mut or Semantic.Read)
                    parameters:insert(Syntax.StageSpec(spec.spelling, capability, constraint,
                        spec.span, Source.Range(spec.span, spec.span)))
                until not accept(',')
                take(')')
            end
            local result
            if accept(':') then result = parse_type() end
            return Syntax.Extern(name.spelling, pure, symbol, parameters, result, kw.span, name_range)
        end

        -- §3.6: "a view is a SEPARATELY DECLARED HOST TYPE", and §3.6 makes the declaration the
        -- whole contract. So `host Handle close` declares a type whose values the host owns and
        -- which `close` destroys. The destructor is optional: a host type with none is one whose
        -- values Let holds and never releases, which is exactly §3.6's "foreign" row.
        local function parse_host()
            local kw = take('host')
            local name = take('name')
            local name_range = Source.Range(name.span, name.span)
            -- §3.6: "a host type may declare that it borrows argument i", which is what makes a value
            -- of it a BORROWED type -- and §3.1 rule 4 propagates that structurally. The index is a
            -- declared fact and never inferred, and it is carried as a SPELLING because §S38 makes
            -- `Semantic.integer_value` the one owner of an integer's value.
            local borrows
            if accept('borrows') then
                local index = take('int')
                borrows = index.spelling
            end
            local destroys
            if kind() == 'name' then destroys = take('name').spelling end
            return Syntax.Host(name.spelling, destroys, borrows, kw.span, name_range)
        end

        local function parse_item()
            local kw = take('let')
            local name = take('name')
            local own = accept('own') ~= nil
            local mutable = accept('mut') ~= nil
            local constraint = parse_annotation()
            local name_range = Source.Range(name.span, name.span)

            if kind() == '=' then
                if own then
                    error(("%s: an initialized binding cannot carry `own`"):format(locate(kw)), 0)
                end
                at = at + 1
                return Syntax.Prelude(Syntax.Binding(name.spelling, mutable, constraint,
                    parse_chain(), kw.span, name_range))
            end

            if not constraint then
                error(("%s: a stage must declare its type: %s"):format(locate(kw), name.spelling), 0)
            end
            local capability = own and (mutable and Semantic.OwnMut or Semantic.Own)
                                       or (mutable and Semantic.Mut or Semantic.Read)
            return Syntax.Stage(Syntax.StageSpec(name.spelling, capability, constraint,
                kw.span, name_range))
        end

        -- A statement list. It ends where the enclosing form resumes, so the terminators are the
        -- keywords that continue one: `end` closes it, `else` is the next arm of an `if`, and
        -- `case` is the next arm of a `switch`. A form that is not here is not silently skipped --
        -- it is a parse error, and the forms the compiler cannot lower yet are named by Lower.
        local function parse_statements()
            local statements = L()
            while true do
                separate()
                local t = peek()
                if t.kind == 'end' or t.kind == 'else' or t.kind == 'case' or t.kind == 'eof' then
                    return statements
                end
                if t.kind == 'let' then
                    local kw = take('let')
                    local name = take('name')
                    local mutable = accept('mut') ~= nil
                    local constraint = parse_annotation()
                    take('=')
                    statements:insert(Syntax.Local(Syntax.Binding(name.spelling, mutable,
                        constraint, parse_chain(), kw.span, Source.Range(name.span, name.span)),
                        kw.span))
                elseif t.kind == 'return' then
                    at = at + 1
                    local value
                    if not (kind() == ';' or kind() == 'end' or kind() == 'eof') then
                        value = parse_expr()
                    end
                    statements:insert(Syntax.Return(value, t.span))
                elseif t.kind == 'if' then
                    statements:insert(parse_if())
                elseif t.kind == 'while' then
                    statements:insert(parse_while())
                elseif t.kind == 'switch' then
                    statements:insert(parse_switch())
                elseif t.kind == 'break' or t.kind == 'continue' then
                    at = at + 1
                    statements:insert(t.kind == 'break' and Syntax.Break(t.span)
                        or Syntax.Continue(t.span))
                else
                    -- A bare `=` after an expression is §3.4's assignment, and nothing else in
                    -- the grammar puts one there: `let` consumes its own. So one token of
                    -- lookahead is the whole decision, and no place-vs-value check is needed
                    -- here -- whether the left side IS a place is Resolve's question.
                    local place = parse_expr()
                    if kind() == '=' then
                        at = at + 1
                        statements:insert(Syntax.Assign(place, parse_expr(), t.span))
                    else
                        statements:insert(Syntax.Discard(place, t.span))
                    end
                end
            end
        end

        -- §3.2: `if`/`else if`/`else` is ONE chain closed by one `end`, so the arms are folded into
        -- a single `If` whose else arm holds the next condition. `else if` is therefore a nesting
        -- in the tree and a chain in the source, which is what the grammar says.
        parse_if = function()
            local kw = take('if')
            local arms = {}
            arms[1] = { condition = parse_expr() }
            take('do')
            arms[1].body = parse_statements()
            while kind() == 'else' do
                at = at + 1
                if kind() == 'if' then
                    at = at + 1
                    local arm = { condition = parse_expr() }
                    take('do')
                    arm.body = parse_statements()
                    arms[#arms + 1] = arm
                else
                    arms[#arms + 1] = { body = parse_statements() }
                    break
                end
            end
            take('end')
            -- Folded inward-out, so `else if` becomes the `no` list of the arm before it and the
            -- whole chain is ONE statement. The `no` slot holds a list, so the nested `If` is the
            -- single statement in it -- which is what makes the tree uniform. A bare `else` replaces
            -- the fold's tail with its own body rather than nesting under another condition.
            local otherwise = L{}
            for i = #arms, 1, -1 do
                local arm = arms[i]
                if arm.condition then
                    otherwise = L{Syntax.If(arm.condition, arm.body, otherwise, kw.span)}
                else
                    otherwise = arm.body
                end
            end
            return otherwise[1]
        end

        -- §12.0: the subject is evaluated EXACTLY ONCE, arms are `case` label lists, and one `end`
        -- closes the whole form. There is no fallthrough, so an arm's body simply ends. A `switch`
        -- is not a loop, which is why `break` inside an arm belongs to the enclosing `while`.
        parse_switch = function()
            local kw = take('switch')
            local subject = parse_expr()
            take('do')
            local cases = L()
            while kind() == 'case' do
                local t = take('case')
                -- §S60: a label names what the arm matches, and the label SAYS which kind it is:
                -- a SHAPE (a type, which the arm may then bind) or a CONSTANT (a value compared
                -- against the subject). A type is tried FIRST, because a structural shape has no
                -- expression spelling at all -- `{ x : Int }` is a type and nothing else -- and the
                -- position is restored on failure the way §S27 restores it for an ambiguous `{`.
                --
                --     A Bool literal is a NAME lexically, so the guard below is what keeps
                --     `case true` from being read as a type named `true`.
                local function parse_label()
                    local token = peek()
                    if token.kind == 'name' and is_boolean(token.spelling) then
                        return Syntax.Constant(parse_expr())
                    end
                    local mark = at
                    local parsed, type_ = pcall(parse_type)
                    if parsed then return Syntax.Shape(type_) end
                    at = mark
                    return Syntax.Constant(parse_expr())
                end
                local labels = L{parse_label()}
                while accept(',') do labels:insert(parse_label()) end
                -- §S59: an arm that matches by SHAPE names what it matched. The binder is a
                -- NAME rather than a binding, because a match does not compute anything.
                local binds
                if kind() == 'as' then
                    take('as')
                    binds = take('name').spelling
                end
                cases:insert(Syntax.Case(labels, binds, parse_statements(), t.span))
            end
            local otherwise = L()
            if kind() == 'else' then
                at = at + 1
                otherwise = parse_statements()
            end
            take('end')
            return Syntax.Switch(subject, cases, otherwise, kw.span)
        end

        parse_while = function()
            local kw = take('while')
            local condition = parse_expr()
            take('do')
            local body = parse_statements()
            take('end')
            return Syntax.While(condition, body, kw.span)
        end

        -- §3.1: a terminal is a `do ... end` region or a transfer value. A `do` terminal states its
        -- result, and an unstated one is refused by Resolve rather than defaulted.
        local function parse_terminal()
            local t = peek()
            if t.kind == 'do' then
                at = at + 1
                local result
                if accept(':') then result = parse_type() end
                local statements = parse_statements()
                take('end')
                return Syntax.Body(statements, result, t.span)
            end
            return Syntax.Data(parse_expr(), t.span)
        end

        -- `;` SEPARATES A PRELUDE FROM A WRITTEN TERMINAL, and it stays (§S88's first draft said it
        -- had nothing left to do, and the test suite was the counterexample within one run). Both sides
        -- of that boundary are EXPRESSIONS -- `let secret = 8` and then `{ … }` -- so a separator is
        -- needed however application is spelled; greedy juxtaposition was never the reason. What `;`
        -- was never needed for is between two ITEMS, because `let`, `extern` and `host` delimit
        -- themselves, and that is why eating it here and requiring it there is the whole rule.
        -- `;` separates chain items from each other and from the terminal: the grammar requires it
        -- exactly where adjacent expressions would otherwise run together.
        separate = function() while accept(';') do end end

        local function parse_items(items)
            while true do
                separate()
                if kind() == 'extern' then
                    items:insert(parse_extern())
                elseif kind() == 'host' then
                    items:insert(parse_host())
                elseif kind() ~= 'let' then
                    return
                else
                    items:insert(parse_item())
                end
            end
        end

        -- A chain is zero or more items and then a terminal. This slice's terminal is a data
        -- expression; `do ... end` is the next alternative and needs statements.
        parse_chain = function()
            local first = peek().span
            local items = L()
            parse_items(items)
            separate()
            return Syntax.Chain(items, parse_terminal(), first)
        end

        -- §3.3: `{}` is Unit, `{ let x = v }` is a named aggregate, `{ v, v }` is positional, and
        -- the forms cannot mix. A `let` after `{` is genuinely ambiguous -- it can begin a named
        -- member or a positional element that is itself a chain -- so the named form is tried
        -- first and the position restored on failure. This is the one place the parser backtracks
        -- (§S27); the grammar states the constraint but not a decision procedure.
        --
        -- §3.7 + §S26: inside braces `mut` is *interior mutability of the member*, not a supply
        -- qualifier. A `mut` member is supplied like a read one, and any stage member makes the
        -- whole form a `Word` whose chain carries the stages -- which is exactly "a record type
        -- and a value aggregate are the same form" (§3.1).
        parse_aggregate = function(open)
            if accept('}') then return Syntax.Unit(open.span) end

            local mark = at
            local items = L()
            local named = pcall(function()
                parse_items(items)
                if kind() ~= '}' or #items == 0 then error('not a named aggregate', 0) end
            end)
            if named then
                take('}')
                local members, stages = L(), L()
                local staged = false
                for _, item in ipairs(items) do
                    if Syntax.Stage:isclassof(item) then
                        staged = true
                        local spec = item.stage
                        local mutable = spec.capability == Semantic.Mut
                            or spec.capability == Semantic.OwnMut
                        local supplied = spec.capability
                        if supplied == Semantic.Mut then supplied = Semantic.Read
                        elseif supplied == Semantic.OwnMut then supplied = Semantic.Own end
                        stages:insert(Syntax.Stage(Syntax.StageSpec(spec.name, supplied,
                            spec.constraint, spec.span, spec.name_range)))
                        members:insert(Syntax.Binding(spec.name, mutable, spec.constraint,
                            Syntax.Chain(L{}, Syntax.Data(Syntax.Name(spec.name, spec.span), spec.span), spec.span),
                            spec.span, spec.name_range))
                    else
                        members:insert(item.binding)
                    end
                end
                if staged then
                    return Syntax.Word(Syntax.Chain(stages,
                        Syntax.Data(Syntax.NamedAggregate(members, open.span), open.span), open.span), open.span)
                end
                return Syntax.NamedAggregate(members, open.span)
            end

            at = mark
            local elements = L{parse_chain()}
            while accept(',') do
                if kind() == '}' then break end
                elements:insert(parse_chain())
            end
            take('}')
            return Syntax.PositionalAggregate(elements, open.span)
        end

        -- The program is the same shape with the terminal optional (spec §2.6).
        local items = L()
        parse_items(items)
        separate()
        local terminal
        if kind() ~= 'eof' then terminal = parse_terminal() end
        take('eof')
        return Syntax.Program(Syntax.Chain(items, terminal, Source.Span(file, 1, 1)))
    end
end
