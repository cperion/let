-- Belt.Function* x Judge.Answer* -> C.Unit (DESIGN §12.5).
--
-- The belt is already the semantic program, so emission chooses representations only. The choices
-- here are the design's, not the emitter's:
--
--   * **Effects have no C representation.** An effect token is ordering evidence for the frontend
--     and the belt's statement order already carries that order, so dropping it removes the effect
--     parameter from every signature, the effect field from every result, and the effect argument
--     from every call. That is why `let_module_init` takes `(void)`.
--   * **A `Known` value gets no variable**: every use is the constant. A `Runtime` value that is
--     used gets a declared local. A producer nothing uses is not written at all -- so the belt's
--     `Fate` is computed here, from liveness, not prescribed.
--   * **An ordered instruction is always written**, because its effect is observable even when its
--     result is not (spec §12.2). That is what makes "pure folds, ordered schedules" hold in the
--     output and not just in the belt.
--   * **An include is demanded by a representation**: `stdbool.h` appears only if a `bool` is.
--   * **A record is one `struct` per shape**, so two residuals with the same members are one type.
return function(V)
    local C, B, J, L, S = V.C, V.Belt, V.Judge, V.List, V.Semantic

    local Emit = {}

    -- One emitter per lowering run: the structs, deduplicated by shape, and the headers used.
    local function emitter()
        return { structs = {}, by_shape = {}, includes = {}, next_struct = 0, hosts = {} }
    end

    -- An unnamed member is a positional element (§3.3: it has no declaration qualifier, because it
    -- has no declaration at all). The representation still needs a name for it, and this is the one
    -- place that invents one -- so the struct and every access to it agree by construction.
    local function field_name(field, index) return field.name or ('f' .. index) end

    local function ctype(E, type_)
        if type_ == B.Int then E.includes.stdint = true; return C.I64 end
        if type_ == B.Bool then E.includes.stdbool = true; return C.Bool end
        if type_ == B.Unit then E.includes.stdint = true; return C.U8 end
        if type_ == B.Effect then return nil end
        -- §11.3: Text is a module-lifetime literal, so its representation is a C string -- a
        -- pointer to static storage -- and never a borrowed view, because a view is a separately
        -- declared HOST type (§3.6) and not the core's `Text`. It is `const char *` and not
        -- `uint8_t *`: the literal is a `char *`, and spelling it as bytes is a signedness mismatch
        -- the compiler warns about, which is a representation disagreeing with itself.
        if type_ == B.Text or type_ == B.CString then return C.CString end
        if type_ == B.U8 then E.includes.stdint = true; return C.U8 end
        if type_ == B.U32 then E.includes.stdint = true; return C.U32 end
        if type_ == B.Float then return C.F64 end
        if type_ == B.Float32 then return C.F32 end
        if type_ == B.CPointer then return C.Pointer(C.Void) end
        -- A host type is spelled by its own name, because the definition is the host's. §S43's rule
        -- applies in reverse here: the compiler cannot derive a C struct it has never seen, so the
        -- declaration states the name and the host provides the type.
        if B.Named:isclassof(type_) then return C.Named(type_.name) end
        -- A cell is a POINTER to storage. That is the whole representation of §3.2's
        -- address-taken binding, and it is why assignment is a store rather than a rebinding: the
        -- cell value is the same object on every path, and only what it points at changes.
        if B.Cell:isclassof(type_) then return C.Pointer(ctype(E, type_.contents)) end
        -- §3.5's sum: a tag and ONE payload, so the payload is a union of the alternatives and the
        -- tag says which one is there. Two declarations are needed because C has no anonymous union
        -- member in this vocabulary -- `union let_uN` for the payload, `struct let_sumN` to carry it
        -- with the tag -- and they are deduplicated by shape like a record is, so two sums with the
        -- same alternatives are one type.
        --
        -- The union's fields are `f0`, `f1`, ... because §11.7's `Sum` has alternatives and no
        -- fields: an alternative has no name to be spelled with, which is the same reason a
        -- positional record member is `f<index>`.
        if B.Sum:isclassof(type_) then
            if #type_.alternatives == 0 then return nil end
            E.includes.stdint = true
            local parts = {}
            for _, alternative in ipairs(type_.alternatives) do
                parts[#parts + 1] = tostring(alternative)
            end
            local key = 'sum:' .. table.concat(parts, '|')
            local name = E.by_shape[key]
            if not name then
                E.next_struct = E.next_struct + 1
                name = 'let_s' .. E.next_struct
                E.by_shape[key] = name
                local union_name = 'let_u' .. E.next_struct
                local members, carried = L(), L()
                for index, alternative in ipairs(type_.alternatives) do
                    local mapped = ctype(E, alternative)
                    if not mapped then return nil end
                    members:insert(C.Parameter(mapped, 'f' .. (index - 1)))
                    carried:insert(C.Parameter(mapped, 'f' .. (index - 1)))
                end
                E.structs[#E.structs + 1] = C.Union(union_name, members)
                -- The tag is an `int64_t` rather than the `uint8_t` it could be, because §1.5's
                -- comparisons take Int and there is no `U8 -> Int` conversion word; a narrower tag
                -- would need one invented to compare against. One choice, stated once.
                E.structs[#E.structs + 1] = C.Struct(name, L{
                    C.Parameter(C.I64, 'tag'), C.Parameter(C.Named('union ' .. union_name), 'payload')})
            end
            return C.Named('struct ' .. name)
        end
        if B.Aggregate:isclassof(type_) then
            -- An empty record carries no information, and **an empty struct is not ISO C** -- so
            -- it is the unit byte. That is what makes a word with no state a value with no fields,
            -- rather than a GNU extension that happens to compile.
            if #type_.fields == 0 then E.includes.stdint = true; return C.U8 end
            local parts = {}
            for _, field in ipairs(type_.fields) do
                parts[#parts + 1] = (field.name or '') .. ':' .. tostring(field.type)
            end
            local key = table.concat(parts, '|')
            local name = E.by_shape[key]
            if not name then
                -- A counter, not `#E.structs`: the struct is appended *after* its members are
                -- built, so during that recursion the count has not grown and two shapes would
                -- be given the same name.
                E.next_struct = E.next_struct + 1
                name = 'let_s' .. E.next_struct
                E.by_shape[key] = name
                local members = L()
                for index, field in ipairs(type_.fields) do
                    members:insert(C.Parameter(ctype(E, field.type), field_name(field, index - 1)))
                end
                E.structs[#E.structs + 1] = C.Struct(name, members)
            end
            return C.Named('struct ' .. name)
        end
        return nil
    end

    -- A producer is named by its block and its position in it. The ENTRY block has no label, so it
    -- has no brand: its parameters are the function's own parameters and its instructions are the
    -- function's own locals. That is why an instance with one block still reads `p1`, `v2` -- one
    -- block is not a special case, it is the case with nothing to disambiguate from.
    local function brand_of(id) return id == 1 and '' or ('b' .. id .. '_') end

    local function entity(brand, block, position)
        if position < #block.parameters then return brand .. 'p' .. position end
        return brand .. 'v' .. position
    end

    local function type_at(block, position, output)
        if position < #block.parameters then return block.parameters[position + 1].type end
        return block.instructions[position - #block.parameters + 1].results[output + 1]
    end

    -- A known value's C expression. It takes the belt type because a record's atom is a Bundle of
    -- its members' atoms, so the mapping is recursive -- and it needs each member's type to spell
    -- the designated initializer.
    local record_expr
    local function expr_of(E, type_, atom)
        if J.Int:isclassof(atom) then
            return C.Integer(math.floor(atom.value / 4294967296) % 4294967296, atom.value % 4294967296)
        end
        -- §12.5: "an include is demanded by a REPRESENTATION". A folded constant is a use of one
        -- -- a known `true` is still spelled `true` in C -- so the include is demanded here too.
        -- Demanding it only where `ctype` runs misses every constant the folder produced, and the
        -- output then fails to compile on `true` with nothing to point at.
        if J.Bool:isclassof(atom) then
            E.includes.stdbool = true
            return C.Boolean(atom.value)
        end
        if J.Unit:isclassof(atom) then
            E.includes.stdint = true
            return C.Integer(0, 0)
        end
        if J.Text:isclassof(atom) then return C.String(atom.value) end
        if J.Bundle:isclassof(atom) then return record_expr(E, type_, atom) end
        return nil
    end

    record_expr = function(E, type_, atom)
        -- An empty record is the unit byte, so its value is zero rather than a compound literal
        -- with no members.
        if #type_.fields == 0 then return C.Integer(0, 0) end
        local designators = L()
        for i, field in ipairs(type_.fields) do
            designators:insert(C.Designator(field_name(field, i - 1),
                expr_of(E, field.type, atom.fields[i])))
        end
        return C.Init(ctype(E, type_), designators)
    end

    -- The C expression for a ref. At consumer position `p`, `Ref(distance, output)` denotes producer
    -- `p - 1 - distance` -- the same rule the belt uses, applied once more.
    local function value_expr(E, block, answers, consumer, ref, brand)
        local at = consumer - 1 - ref.distance
        local answer = answers[at + 1]
        if J.Known:isclassof(answer) then
            -- One call: `expr_of` recurses into a Bundle itself, so a record is not a special
            -- case here, and a constant needs no variable.
            return expr_of(E, type_at(block, at, ref.output), answer.atom)
        end
        -- A cell produced by `Allocate` IS its storage's address, because `body_of` declares the
        -- storage with the CONTENTS type and the cell is a pointer to it. Only that producer: a cell
        -- that arrived as a PARAMETER is already a pointer, and taking its address again is `&&`.
        if at >= #block.parameters then
            local producer = block.instructions[at - #block.parameters + 1]
            if B.Allocate:isclassof(producer.operation.operation) then
                return C.Unary('&', C.Name(entity(brand, block, at)))
            end
        end
        return C.Name(entity(brand, block, at))
    end

    -- A 64-bit constant. `C.Integer` takes the two halves because the output has to be valid C
    -- without a suffix guess, so an operator's literal goes through the same spelling as an atom's.
    local function int_expr(value)
        return C.Integer(math.floor(value / 4294967296) % 4294967296, value % 4294967296)
    end

    local function cast_to(E, name, expr)
        E.includes.stdint = true
        return C.Cast(C.Named(name), expr)
    end

    -- §1.5's integer semantics written INLINE in C. There is no helper function, and that is not
    -- style: a helper would be a second implementation of a Let operator, in C, that could drift
    -- from the one `Known` folds. So wrapping is a cast through `uint64_t`, shifts mask their count
    -- with `& 63`, and the two TRAPPING forms use `(abort(), 0)` -- a comma expression, which is
    -- what lets a void call stand where a value is wanted.
    local function binary_expr(E, operator, left, right)
        if operator == S.Add then return cast_to(E, 'int64_t', C.Binary('+', cast_to(E, 'uint64_t', left), cast_to(E, 'uint64_t', right))) end
        if operator == S.Subtract then return cast_to(E, 'int64_t', C.Binary('-', cast_to(E, 'uint64_t', left), cast_to(E, 'uint64_t', right))) end
        if operator == S.Multiply then return cast_to(E, 'int64_t', C.Binary('*', cast_to(E, 'uint64_t', left), cast_to(E, 'uint64_t', right))) end
        if operator == S.BitAnd then return C.Binary('&', left, right) end
        if operator == S.BitOr then return C.Binary('|', left, right) end
        if operator == S.BitXor then return C.Binary('^', left, right) end
        if operator == S.ShiftLeft then
            return cast_to(E, 'int64_t', C.Binary('<<', cast_to(E, 'uint64_t', left),
                C.Binary('&', cast_to(E, 'uint64_t', right), int_expr(63))))
        end
        if operator == S.ShiftRight then
            -- Arithmetic shift, which Let specifies for signed Int; a shift count is reduced modulo
            -- 64, so no shift is undefined and none traps.
            return C.Binary('>>', left, C.Binary('&', right, int_expr(63)))
        end
        if operator == S.Equal then return C.Binary('==', left, right) end
        if operator == S.NotEqual then return C.Binary('!=', left, right) end
        if operator == S.Less then return C.Binary('<', left, right) end
        if operator == S.LessEqual then return C.Binary('<=', left, right) end
        if operator == S.Greater then return C.Binary('>', left, right) end
        if operator == S.GreaterEqual then return C.Binary('>=', left, right) end
        if operator == S.Divide or operator == S.Remainder then
            E.includes.stdlib = true
            local zero = C.Binary('==', right, int_expr(0))
            local minus_one = C.Binary('==', right, int_expr(-1))
            local trap = C.Comma(L{C.Call(C.Name('abort'), L{}), int_expr(0)})
            if operator == S.Divide then
                -- §3.6: `INT_MIN / -1` wraps rather than trapping, so the wrapped quotient is
                -- computed the same way any other wrapping arithmetic is.
                local wrapped = cast_to(E, 'int64_t', C.Binary('-', cast_to(E, 'uint64_t', int_expr(0)), cast_to(E, 'uint64_t', left)))
                return C.Conditional(zero, trap, C.Conditional(minus_one, wrapped, C.Binary('/', left, right)))
            end
            return C.Conditional(zero, trap, C.Conditional(minus_one, int_expr(0), C.Binary('%', left, right)))
        end
        error('no C rule for the operator ' .. tostring(operator), 0)
    end

    -- The expression an instruction computes, from its opcode alone (V.Op owns what it reads).
    local function instruction_expr(E, block, answers, position, instruction, brand)
        local op = instruction.operation.operation
        local type_ = instruction.results[1]
        if B.TextLiteral:isclassof(op) then return C.String(op.value) end
        if B.FloatLiteral:isclassof(op) then return C.Float(S.float_value(op.spelling)) end
        -- §3.5's construction: the tag says which alternative, and only that one is written -- so
        -- the payload is a designated initializer for the union's field at that tag.
        if B.InjectSum:isclassof(op) then
            return C.Init(ctype(E, type_), L{
                C.Designator('tag', C.Integer(0, op.index)),
                C.Designator('payload', C.Init(C.Named('union ' .. ('let_u' .. tostring(ctype(E, type_)):match('%d+'))),
                    L{C.Designator('f' .. op.index,
                        value_expr(E, block, answers, position, op.payload, brand))}))})
        end
        -- §11.7's `Convert`, one C spelling per crossing. The numeric ones are casts because there
        -- are no implicit conversions in the language, so an explicit one is exactly a cast. `ToText`
        -- is absent for the reason the dictionary says: it needs a length the source does not have.
        if B.Convert:isclassof(op) then
            local value = value_expr(E, block, answers, position, op.value, brand)
            local kind = op.kind
            if kind == S.ToInt then return C.Cast(C.I64, value) end
            if kind == S.ToFloat then return C.Cast(C.F64, value) end
            if kind == S.ToU8 then return C.Cast(C.U8, value) end
            if kind == S.ToU32 then return C.Cast(C.U32, value) end
            if kind == S.ToF32 then return C.Cast(C.F32, value) end
            -- A `Text` is already a C string in this representation, so crossing to `CString` is the
            -- same pointer -- and saying so as a cast is what keeps the two types distinct in the
            -- language while they coincide here.
            if kind == S.ToCString then return C.Cast(C.CString, value) end
            if kind == S.TextSize then
                E.includes.string = true
                return C.Cast(C.I64, C.Call(C.Name('strlen'), L{value}))
            end
            if kind == S.IsNull then return C.Unary('!', value) end
            error('no C rule for the conversion ' .. tostring(getmetatable(kind) and getmetatable(kind).kind), 0)
        end
        if B.Construct:isclassof(op) then
            if #op.fields == 0 then return C.Integer(0, 0) end
            local fields = L()
            for _, ref in ipairs(op.fields) do
                fields:insert(value_expr(E, block, answers, position, ref, brand))
            end
            return C.Compound(ctype(E, type_), fields)
        end
        if B.LoadField:isclassof(op) then
            local record_type = type_at(block, position - 1 - op.record.distance, op.record.output)
            -- §3.5/§S59: a sum's field `0` is its TAG and field `1+K` is alternative `K`'s payload,
            -- so both are known offsets -- which makes this the one place that knows where either
            -- lives, and keeps every read of a sum a pure `LoadField`.
            local name
            if B.Sum:isclassof(record_type) then
                if op.field == 0 then
                    name = 'tag'
                else
                    return C.Field(C.Field(value_expr(E, block, answers, position, op.record, brand),
                        'payload'), 'f' .. (op.field - 1))
                end
            else
                name = field_name(record_type.fields[op.field + 1], op.field)
            end
            return C.Field(value_expr(E, block, answers, position, op.record, brand), name)
        end
        -- §12.4's host ops. The symbol is the callee, and the prototype is DERIVED from the Let
        -- types rather than declared by the host (§3.6): the declaration in source is the whole
        -- contract, so the C side of it is generated. A prototype is recorded once per symbol, at
        -- the first call, because that is where its argument and result types are known.
        if B.PureHostCall:isclassof(op) or B.HostCall:isclassof(op) then
            local arguments = L()
            local types = L()
            for _, ref in ipairs(op.arguments) do
                arguments:insert(value_expr(E, block, answers, position, ref, brand))
                types:insert(ctype(E, type_at(block, position - 1 - ref.distance, ref.output)))
            end
            E.hosts[op.symbol] = { parameters = types, result = ctype(E, type_) }
            return C.Call(C.Name(op.symbol), arguments)
        end
        if B.CallFunction:isclassof(op) then
            local arguments = L()
            for _, ref in ipairs(op.arguments) do
                arguments:insert(value_expr(E, block, answers, position, ref, brand))
            end
            -- The effect argument is dropped: order is statement order.
            return C.Call(C.Name(E.callees[op.target]), arguments)
        end
        -- §3.4's storage. A compound literal is what gives the cell's storage a name at its
        -- declaration; C11 gives it the enclosing block's lifetime, which is the function.
        -- §3.4's storage. The declaration IS the storage -- `body_of` declares it with the
        -- CONTENTS type -- and `value_expr` takes its address wherever the cell is named, so the
        -- expression here is simply the initial value.
        if B.Allocate:isclassof(op) then
            return value_expr(E, block, answers, position, op.initial, brand)
        end
        if B.Load:isclassof(op) then
            return C.Unary('*', value_expr(E, block, answers, position, op.cell, brand))
        end
        -- §3.1's second rule, at the point it happens: destruction is a call to the word the type's
        -- declaration named, with the value as its argument.
        if B.Destroy:isclassof(op) then
            -- §3.6/S41: a host type's DESTRUCTOR is declared in source exactly like a host word, so its
            -- prototype is DERIVED the same way -- and it was the one host symbol that never got one.
            -- The emitted unit therefore called `release` before any declaration of it, so it did not
            -- compile on its own: the host had to pre-declare what the source had already declared.
            -- That is the whole of "the declaration, not the implementation, is what the compiler holds
            -- a host to" -- the compiler had the declaration and did not use it.
            local destroyed = ctype(E, type_at(block, position - 1 - op.value.distance, op.value.output))
            E.hosts[op.destructor] = { parameters = L{destroyed}, result = nil }
            return C.Call(C.Name(op.destructor), L{value_expr(E, block, answers, position, op.value, brand)})
        end
        if B.Store:isclassof(op) then
            return C.Assign(C.Unary('*', value_expr(E, block, answers, position, op.cell, brand)),
                value_expr(E, block, answers, position, op.value, brand))
        end
        -- §S68: the address of a field, for a path that has to reach through storage. This is the
        -- only place that knows a cell's C expression is a POINTER, which is why the base needs a
        -- dereference and the field needs an address -- the two spellings `StoreField` and `Load`
        -- then consume.
        if B.FieldAddress:isclassof(op) then
            local cell_type = type_at(block, position - 1 - op.cell.distance, op.cell.output)
            local contents = cell_type.contents
            return C.Unary('&', C.Field(C.Unary('*',
                value_expr(E, block, answers, position, op.cell, brand)),
                field_name(contents.fields[op.field + 1], op.field)))
        end
        if B.StoreField:isclassof(op) then
            local record_type = type_at(block, position - 1 - op.record.distance, op.record.output)
            local contents = record_type.contents
            return C.Assign(
                C.Field(C.Unary('*', value_expr(E, block, answers, position, op.record, brand)),
                    field_name(contents.fields[op.field + 1], op.field)),
                value_expr(E, block, answers, position, op.value, brand))
        end
        if B.Unary:isclassof(op) then
            local operand = value_expr(E, block, answers, position, op.operand, brand)
            if op.operator == S.Not then return C.Unary('!', operand) end
            if op.operator == S.BitNot then return C.Unary('~', operand) end
            -- Unary minus wraps like every other Int operation.
            return cast_to(E, 'int64_t',
                C.Binary('-', cast_to(E, 'uint64_t', int_expr(0)), cast_to(E, 'uint64_t', operand)))
        end
        if B.Binary:isclassof(op) or B.CheckedBinary:isclassof(op) then
            return binary_expr(E, op.operator,
                value_expr(E, block, answers, position, op.left, brand),
                value_expr(E, block, answers, position, op.right, brand))
        end
        error('no emission rule for ' .. tostring(getmetatable(op) and getmetatable(op).kind), 0)
    end



    -- The signature: the result is the first non-effect result and the parameters are the packet
    -- minus the effect. A function with NO non-effect result prints as `void`, which is how §2.6's
    -- `unload` gets the signature the document writes without the emitter knowing about unload.
    local function signature_of(E, belt)
        local block = belt.blocks[1]
        local result, returned
        for i, type_ in ipairs(belt.signature.results) do
            if type_ ~= B.Effect then result, returned = ctype(E, type_), i break end
        end
        local parameters = L()
        for i, parameter in ipairs(block.parameters) do
            if parameter.type ~= B.Effect then
                parameters:insert(C.Parameter(ctype(E, parameter.type), entity('', block, i - 1)))
            end
        end
        -- §11.7: linkage is a property of the INSTANCE, not something the emitter infers from the
        -- name. `let_module_init` was the only exported function, so comparing the name worked; the
        -- moment a top-level word gets a host entry point (§2.6), a name comparison is a string
        -- standing in for a closed set -- and the second exported instance is what makes that a bug.
        return { result = result, returned = returned, parameters = parameters,
                 exported = belt.exported }
    end

    -- One edge: write the target's parameters from this edge's arguments, then go.
    --
    -- Those assignments ARE §S28's identity phi written out. The target's parameter IS the edge's
    -- argument, so a value that crosses a join is one plain C assignment -- and the agreement the
    -- join also requires is about PLACES, which have no representation and so write nothing.
    local function edge_statements(E, belt, block, answers, brand, exit_at, edge)
        local statements = L()
        local target = belt.blocks[edge.target]
        for index, ref in ipairs(edge.arguments) do
            local parameter = target.parameters[index]
            local type_ = parameter and ctype(E, parameter.type)
            if type_ then
                statements:insert(C.Assign(
                    C.Name(entity(brand_of(edge.target), target, index - 1)),
                    value_expr(E, block, answers, exit_at, ref, brand)))
            end
        end
        statements:insert(C.Goto('b' .. edge.target))
        return C.Block(statements)
    end

    -- The exit. A `Return` returns, a `Jump` goes, and a `Branch` does both once per edge.
    local function exit_of(E, belt, block, answers, brand, exit_at, signature)
        local exit = block.exit
        if B.Return:isclassof(exit) then
            local value = signature.returned
                and value_expr(E, block, answers, exit_at, exit.values[signature.returned], brand)
            return C.Return(value)
        end
        if B.Jump:isclassof(exit) then
            return edge_statements(E, belt, block, answers, brand, exit_at, exit.edge)
        end
        if B.Trap:isclassof(exit) then
            -- §1.5 traps where C would be undefined, and the one caller is §12.1's runtime index: an
            -- index that names no member. `abort` is the only library the emitted C needs.
            E.includes.stdlib = true
            return C.Evaluate(C.Call(C.Name('abort'), L{}))
        end
        if B.Branch:isclassof(exit) then
            return C.If(value_expr(E, block, answers, exit_at, exit.condition, brand),
                edge_statements(E, belt, block, answers, brand, exit_at, exit.yes),
                edge_statements(E, belt, block, answers, brand, exit_at, exit.no))
        end
        error('no emission rule for the exit of ' .. belt.name, 0)
    end

    -- Every reachable block, in the order `Known` walked them -- which starts at the entry.
    --
    -- An unreachable block is not emitted: reachability is §12.3's demand one level below
    -- instances (§S30). `Lower` still builds such a block, because a split's join exists before
    -- either arm -- and only the graph says whether anything arrives.
    local function body_of(E, belt, known, signature)
        local statements = L()

        -- A non-entry block's parameters are locals of the FUNCTION, declared before the first
        -- label: C forbids a `goto` that jumps into the scope of a variably modified object, and
        -- declaring them once is what lets an edge ASSIGN a parameter rather than declare it.
        for _, id in ipairs(known.order) do
            if id ~= 1 then
                local block = belt.blocks[id]
                for index, parameter in ipairs(block.parameters) do
                    local type_ = ctype(E, parameter.type)
                    if type_ then
                        statements:insert(C.Declare(type_,
                            entity(brand_of(id), block, index - 1), nil))
                    end
                end
            end
        end

        for _, id in ipairs(known.order) do
            local block = belt.blocks[id]
            local brand = brand_of(id)
            local answers, fates = known.answers[id], known.fates[id]
            local exit_at = #block.parameters + #block.instructions
            if id ~= 1 then statements:insert(C.Label('b' .. id)) end

            for position = #block.parameters, exit_at - 1 do
                -- §12.5: the fate is consumed, not recomputed. `Materialized` is the ONLY fate
                -- that writes C: `Immediate` needs no variable because every use is the constant,
                -- and `Dropped` is the belt talking about something the machine does not do.
                if J.Materialized:isclassof(fates[position + 1]) then
                    local instruction = block.instructions[position - #block.parameters + 1]
                    local type_ = instruction.results[1]
                    local op = instruction.operation.operation
                    -- §3.4's stores are STATEMENTS. C has no assignment expression in this
                    -- vocabulary, and a store writes rather than produces -- so its effect result
                    -- becomes the statement instead of wrapping one.
                    -- An `Allocate` declares its STORAGE: the belt type is `Cell(T)` but the C
                    -- object is a `T`, and the cell value is that object's address.
                    if B.Allocate:isclassof(op) then
                        statements:insert(C.Declare(ctype(E, type_.contents), entity(brand, block, position),
                            instruction_expr(E, block, answers, position, instruction, brand)))
                    elseif B.Store:isclassof(op) or B.StoreField:isclassof(op) then
                        statements:insert(
                            instruction_expr(E, block, answers, position, instruction, brand))
                    elseif type_ == B.Effect then
                        statements:insert(C.Evaluate(
                            instruction_expr(E, block, answers, position, instruction, brand)))
                    else
                        statements:insert(C.Declare(ctype(E, type_), entity(brand, block, position),
                            instruction_expr(E, block, answers, position, instruction, brand)))
                    end
                end
            end

            statements:insert(exit_of(E, belt, block, answers, brand, exit_at, signature))
        end
        return C.Block(statements)
    end

    -- The belt's instances are a list, and a call names one by index. The mapping lives here
    -- because a target is an emitter concern: the belt orders instances, the emitter spells them.
    function Emit.run(unit, belts, known, k_ok, k_diag)
        local E = emitter()
        E.callees = {}
        for index, belt in ipairs(belts) do E.callees[index] = belt.name end

        -- Signatures first, because a signature is what registers a struct a declaration names.
        local signatures = {}
        for index, belt in ipairs(belts) do signatures[index] = signature_of(E, belt) end

        -- Prototypes, because demand order is not dependency order: the root is emitted first and
        -- calls what it demanded, so a definition can precede its callee.
        local prototypes = L()
        for index, belt in ipairs(belts) do
            local signature = signatures[index]
            prototypes:insert(C.Function(belt.name, false, signature.exported,
                signature.result or C.Void, signature.parameters, nil))
        end

        local definitions = L()
        for index, belt in ipairs(belts) do
            local signature = signatures[index]
            definitions:insert(C.Function(belt.name, false, signature.exported,
                signature.result or C.Void, signature.parameters,
                body_of(E, belt, known[index], signature)))
        end

        -- Structs LAST, and this is not a style choice. A signature names the packet and the
        -- result, but a BODY can be the first place a record type appears -- a value carried
        -- across a split is a parameter of the target block, and no signature ever mentions it.
        -- Emitting the struct list before the bodies therefore leaves those structs undefined:
        -- the C still compiles for simple programs, and fails with "storage size isn't known" the
        -- moment control flow carries a record.
        local declarations = L()
        -- A host symbol is EXTERNAL: it is defined outside this translation unit, and the language
        -- promised nothing about who defines it (§3.6). `external` is what prints it without
        -- `static`, which is the same distinction that decides linkage for our own instances.
        for symbol, shape in pairs(E.hosts) do
            local parameters = L()
            for index, parameter in ipairs(shape.parameters) do
                parameters:insert(C.Parameter(parameter, 'a' .. index))
            end
            declarations:insert(C.Function(symbol, true, true, shape.result or C.Void, parameters, nil))
        end
        for _, struct in ipairs(E.structs) do declarations:insert(struct) end
        for _, prototype in ipairs(prototypes) do declarations:insert(prototype) end
        for _, definition in ipairs(definitions) do declarations:insert(definition) end

        local includes = L()
        if E.includes.stdint then includes:insert('stdint.h') end
        if E.includes.stdbool then includes:insert('stdbool.h') end
        -- A trapping division is the one place the emitted C needs a library: `abort` is the
        -- standard spelling of "leave through the host's trap hook" until the host vocabulary has
        -- one of its own. Nothing else asks for it, so nothing else includes it.
        if E.includes.stdlib then includes:insert('stdlib.h') end
        -- `TextSize` is the one conversion that is a library call rather than a cast, because a
        -- `Text` carries no length in this representation: the length is what the operation asks for.
        if E.includes.string then includes:insert('string.h') end

        local out = C.Unit(includes, declarations)
        unit.ambient.c = out
        return k_ok(unit, out)
    end

    return Emit
end
