-- Belt.Function -> Judge.Answer* (DEMAND §3, §4, §6).
--
-- The abstract evaluator's domain is `Known(Atom)` or `Runtime(Belt.Type)`, and it evaluates the
-- **belt**, never the source: the belt has already resolved stages, preludes, ownership, words and
-- destinations, so re-interpreting source would rebuild all of that and drift from it.
--
-- Two decisions per producer, and both belong to this phase (DESIGN §12.4):
--
--   * `Judge.Answer` -- `Known(Atom)` or `Runtime(Belt.Type)` -- one per producer, in producer
--     order, **joined by ⊔ at a merge**. A block's parameter is answered by the edges that reach
--     it, which is why the phase walks the block graph and not one block.
--   * `Judge.Fate` -- `Immediate` / `Materialized` / `Dropped` -- one per producer: whether a C
--     variable is written for it at all. §12.5 *consumes* this, and that is the whole reason it
--     is decided here rather than there: the walk that decides liveness exists once, in this
--     phase, and the emitter reads the answer instead of guessing it again.
--
-- An ordered operation is never `Known`, because its result list includes `Effect`. That is what
-- makes "pure folds, ordered schedules" structural rather than a convention.
return function(V)
    local B, J, L, S = V.Belt, V.Judge, V.List, V.Semantic

    local Known = {}

    -- §12.4's opcode semantics, shared with nothing yet because the concrete interpreter is still
    -- the legacy oracle. Folding is an OPTIMISATION, so the rule is soundness: fold only when the
    -- result is exactly representable, and leave everything else `Runtime`. That matters because
    -- §1.5's integer arithmetic WRAPS at 64 bits while a Lua number is a double -- so folding
    -- past 2^53 would produce a constant the program never computes.
    local EXACT = 9007199254740992
    local ARITHMETIC = {
        [S.Add] = function(a, b) return a + b end,
        [S.Subtract] = function(a, b) return a - b end,
        [S.Multiply] = function(a, b) return a * b end,
    }
    local COMPARISON = {
        [S.Equal] = function(a, b) return a == b end,
        [S.NotEqual] = function(a, b) return a ~= b end,
        [S.Less] = function(a, b) return a < b end,
        [S.LessEqual] = function(a, b) return a <= b end,
        [S.Greater] = function(a, b) return a > b end,
        [S.GreaterEqual] = function(a, b) return a >= b end,
    }

    -- Both operands must be Int atoms whose values are already exact, or there is nothing to do.
    local function integers(left, right)
        if not left or not right then return nil end
        if not J.Known:isclassof(left) or not J.Known:isclassof(right) then return nil end
        if not J.Int:isclassof(left.atom) or not J.Int:isclassof(right.atom) then return nil end
        return left.atom.value, right.atom.value
    end

    local function atom_of_literal(op)
        if B.IntegerLiteral:isclassof(op) then return J.Int(S.integer_value(op.spelling)) end
        if B.BooleanLiteral:isclassof(op) then return J.Bool(op.value) end
        if B.UnitLiteral:isclassof(op) then return J.Unit end
        -- A Text literal is a value the folder knows, and a module-lifetime one at that (§11.3), so
        -- a `Text`-typed constant folds and inlines like any other.
        if B.TextLiteral:isclassof(op) then return J.Text(op.value) end
        return nil
    end

    -- At consumer position `p`, `Ref(distance, output)` denotes producer `p - 1 - distance`, and the
    -- answer list is indexed by producer + 1.
    local function answer_of(instruction, answers, position)
        local op = instruction.operation
        if B.Pure:isclassof(op) then
            local atom = atom_of_literal(op.operation)
            if atom then return J.Known(atom) end
            -- §1.5: arithmetic wraps, so a folded result must still be exact; comparisons are
            -- exact for any two representable values, so they always fold when both are known.
            if B.Binary:isclassof(op.operation) then
                local a, b = integers(answers[position - op.operation.left.distance],
                    answers[position - op.operation.right.distance])
                if a then
                    local compare = COMPARISON[op.operation.operator]
                    if compare then return J.Known(J.Bool(compare(a, b))) end
                    local arithmetic = ARITHMETIC[op.operation.operator]
                    if arithmetic then
                        local value = arithmetic(a, b)
                        if math.abs(value) <= EXACT then return J.Known(J.Int(value)) end
                    end
                end
                return J.Runtime(instruction.results[1])
            end
            -- What can fold, and honestly what does not. §11.2 makes a conversion a DICTIONARY WORD,
            -- so `ToCString "x"` passes its argument through a packet: inside the word's `run` the
            -- operand is a `LoadField` of a parameter and therefore `Runtime`, which is why this
            -- folds nothing today. It is still the right rule -- it fires whenever a conversion's
            -- operand IS known, which is what an inlining pass would produce -- and `ToCString` is
            -- the same pointer while `TextSize` of a literal is a length the compiler already holds.
            -- The numeric ones cannot fold here at all, because an `Atom` has no Float.
            if B.Convert:isclassof(op.operation) then
                local operand = answers[position - op.operation.value.distance]
                if operand and J.Known:isclassof(operand) and J.Text:isclassof(operand.atom) then
                    if op.operation.kind == S.ToCString then return operand end
                    if op.operation.kind == S.TextSize then
                        return J.Known(J.Int(#operand.atom.value))
                    end
                end
                return J.Runtime(instruction.results[1])
            end
            if B.Unary:isclassof(op.operation) then
                local operand = answers[position - op.operation.operand.distance]
                if operand and J.Known:isclassof(operand) then
                    -- §1.5: `not` is the Bool-to-Bool unary, so its operand is a Bool atom, while
                    -- `Negate` and `BitNot` are the Int ones. Both fold here, and they fold in
                    -- one place because the rule that types them lives in one place too.
                    if op.operation.operator == S.Not and J.Bool:isclassof(operand.atom) then
                        return J.Known(J.Bool(not operand.atom.value))
                    end
                    if op.operation.operator == S.Negate and J.Int:isclassof(operand.atom)
                        and math.abs(operand.atom.value) <= EXACT then
                        return J.Known(J.Int(-operand.atom.value))
                    end
                end
                return J.Runtime(instruction.results[1])
            end
            if B.Construct:isclassof(op.operation) then
                local fields = L()
                for _, ref in ipairs(op.operation.fields) do
                    local field = answers[position - ref.distance]
                    if not field or not J.Known:isclassof(field) then
                        return J.Runtime(instruction.results[1])
                    end
                    fields:insert(field.atom)
                end
                return J.Known(J.Bundle(fields))
            end
        end
        return J.Runtime(instruction.results[1])
    end

    -- Where an exit can go. A `Return`, a `TailCall` and a `Trap` go nowhere: they end the walk,
    -- which is what makes "reachable" the same question as "can this ever run".
    local function successors(exit)
        if B.Jump:isclassof(exit) then return { exit.edge.target } end
        if B.Branch:isclassof(exit) then return { exit.yes.target, exit.no.target } end
        return {}
    end

    -- The reachable blocks, in reverse postorder.
    --
    -- Reachability is DESIGN §12.3's demand one level below instances: a block no edge reaches is
    -- not part of the program, so it is neither answered here nor emitted by §12.5. `Lower` must
    -- still CREATE such a block -- a split's join is built before either arm, because an `Edge`
    -- names its target by id -- and only the graph says whether anything arrives.
    --
    -- Reverse postorder because a block is answered FROM the edges into it, and this is an order
    -- in which a block's predecessors have been answered already. A backedge is the one edge that
    -- violates it, and it is skipped rather than guessed.
    local function walk(belt)
        local reachable, post = { [1] = true }, {}
        local stack = { { id = 1, at = 0 } }
        while #stack > 0 do
            local frame = stack[#stack]
            local targets = successors(belt.blocks[frame.id].exit)
            if frame.at < #targets then
                frame.at = frame.at + 1
                local target = targets[frame.at]
                if not reachable[target] then
                    reachable[target] = true
                    stack[#stack + 1] = { id = target, at = 0 }
                end
            else
                post[#post + 1] = frame.id
                stack[#stack] = nil
            end
        end
        local order = L()
        for i = #post, 1, -1 do order:insert(post[i]) end
        return reachable, order
    end

    -- The edge of `exit` that reaches `target`, or nil. `Edge.arguments[i]` answers the target's
    -- parameter `i`, one for one, because that is what an edge IS (§11.7).
    local function edge_into(exit, target)
        if B.Jump:isclassof(exit) then
            if exit.edge.target == target then return exit.edge end
        elseif B.Branch:isclassof(exit) then
            if exit.yes.target == target then return exit.yes end
            if exit.no.target == target then return exit.no end
        end
        return nil
    end

    -- §12.4's join, at one block parameter. With no assignment every edge into a merge passes the
    -- SAME value (§S28), so `⊔` is idempotent and a single pass in reverse postorder reaches the
    -- fixpoint. An edge whose source is not answered yet is skipped rather than guessed: a
    -- backedge cannot teach the header anything the header did not already know.
    local function parameter_answer(belt, answers, id, index)
        local merged
        for source = 1, #belt.blocks do
            local list = answers[source]
            if list then
                local block = belt.blocks[source]
                local edge = edge_into(block.exit, id)
                if edge and #edge.arguments >= index then
                    local ref = edge.arguments[index]
                    local exit_at = #block.parameters + #block.instructions
                    local answer = list[exit_at - ref.distance]
                    if answer then
                        merged = merged
                            and merged:join(answer, belt.blocks[id].parameters[index].type)
                            or answer
                    end
                end
            end
        end
        return merged
    end

    -- §12.5 consumes a `Judge.Fate`, so the decision belongs to the phase that already walks the
    -- block. A parameter is always materialized -- it is a C variable or a function parameter. A
    -- folded producer is a constant and gets no variable. An ordered opcode with C work is written
    -- for its effect. A pure runtime value is written only if something reads it -- including the
    -- exit, because an edge's arguments are reads too. Everything else is dropped.
    local function fates_of(belt, block, answers)
        local count = #block.parameters + #block.instructions
        local used = {}
        local exit = block.exit
        if B.Return:isclassof(exit) then
            for _, ref in ipairs(exit.values) do used[count - 1 - ref.distance] = true end
        elseif B.Jump:isclassof(exit) then
            for _, ref in ipairs(exit.edge.arguments) do used[count - 1 - ref.distance] = true end
        elseif B.Branch:isclassof(exit) then
            used[count - 1 - exit.condition.distance] = true
            for _, edge in ipairs{ exit.yes, exit.no } do
                for _, ref in ipairs(edge.arguments) do used[count - 1 - ref.distance] = true end
            end
        elseif B.TailCall:isclassof(exit) then
            used[count - 1 - exit.effect.distance] = true
            for _, ref in ipairs(exit.arguments) do used[count - 1 - ref.distance] = true end
        elseif B.Trap:isclassof(exit) then
            used[count - 1 - exit.effect.distance] = true
        end
        for position = count - 1, #block.parameters, -1 do
            local instruction = block.instructions[position - #block.parameters + 1]
            local ordered = B.Ordered:isclassof(instruction.operation)
            if (ordered and V.Op.emits(instruction.operation.operation)) or used[position] then
                for _, ref in ipairs(V.Op.inputs(instruction)) do
                    used[position - 1 - ref.distance] = true
                end
            end
        end
        local fates = L()
        for position = 0, count - 1 do
            if position < #block.parameters then
                fates:insert(J.Materialized)
            else
                local instruction = block.instructions[position - #block.parameters + 1]
                local answer = answers[position + 1]
                local ordered = B.Ordered:isclassof(instruction.operation)
                -- `ordered` is tested FIRST and alone, because an ordered opcode must not reach
                -- the `used` branch: a `Move`'s effect is consumed downstream, which would
                -- otherwise make a move look demanded and emit a variable for nothing.
                if ordered then
                    fates:insert(V.Op.emits(instruction.operation.operation)
                        and J.Materialized or J.Dropped)
                elseif J.Known:isclassof(answer) and not J.Bundle:isclassof(answer.atom) then
                    -- A SCALAR known value is spelled where it is used, and a `Bundle` is not: it is a
                    -- compound constant -- a record or a tuple whose members are all known -- and
                    -- spelling it at EVERY use duplicates the whole literal. §12.1's runtime index
                    -- dispatches over the tuple, so its record appears once per test, once per arm and
                    -- once per edge; a tuple of N members costs N^2 text. A compound value is written
                    -- ONCE and named, which is what the emitted C should look like anyway.
                    fates:insert(J.Immediate)
                elseif used[position] then
                    fates:insert(J.Materialized)
                else
                    fates:insert(J.Dropped)
                end
            end
        end
        return fates
    end

    function Known.run(region, belt, k_ok, k_diag)
        local _, order = walk(belt)
        local answers, fates = {}, {}
        for _, id in ipairs(order) do
            local block = belt.blocks[id]
            local list = L()
            for index, parameter in ipairs(block.parameters) do
                local merged = id == 1 and J.Runtime(parameter.type)
                    or parameter_answer(belt, answers, id, index)
                list:insert(merged or J.Runtime(parameter.type))
            end
            local position = #block.parameters
            for _, instruction in ipairs(block.instructions) do
                list:insert(answer_of(instruction, list, position))
                position = position + 1
            end
            answers[id] = list
            fates[id] = fates_of(belt, block, list)
        end
        region.out.answers = answers
        region.out.fates = fates
        return k_ok(region, { answers = answers, fates = fates, order = order })
    end

    return Known
end
