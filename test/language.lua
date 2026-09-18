-- The language: one program per construct, compiled and RUN, with its stdout compared.
--
-- Every program here is written in the surface §S88 settled: an application is `with` (`f with a`), a
-- parenthesized expression after it GROUPS, and invocation `f(a, b)` is the transient form. The host text
-- is the part the compiler does not own -- the type, the destructor, `main` -- and §2.6 says so.
local H = require('test.harness')
H.suite = 'language'
local runs, refuses, R = H.runs, H.refuses, H.R

-- The host for a program that has no host of its own: print the named members of the module value. §2.6
-- makes the host a separate thing, so this is the smallest honest one -- and `let_s1` is the namespace
-- the emitter names first, which is a fact about the ABI a test is allowed to know.
local function show(fields)
    local values, formats = {}, {}
    for index, field in ipairs(fields) do
        values[index] = '(long long)m.' .. field
        formats[index] = '%lld'
    end
    return 'int main(void){ struct let_s1 m = let_module_init();\n'
        .. ('    printf("%s\\n", %s);\n'):format(table.concat(formats, ' '), table.concat(values, ', '))
        .. '    return 0; }\n'
end

-- 1. THE WIN OF §S88, end to end: a grouped argument. `sum (square 3) (square 4)` was `Undersaturated`
--    before, because `(` after a word is the invocation suffix and a grouped stage was unreachable.
runs([[
let square = let x : Int do : Int
    return x * x
end
let sum = let a : Int let b : Int do : Int
    return a + b
end
let answer = sum with (square with 3) with (square with 4)
]], show{ 'answer' }, '25\n', 'a grouped argument is an argument, not an invocation')

-- 2. ... and the same chain by invocation is the SAME thing (§S13): one program, both spellings.
runs([[
let square = let x : Int do : Int
    return x * x
end
let sum = let a : Int let b : Int do : Int
    return a + b
end
let juxtaposed = sum with (square with 3) with (square with 4)
let invoked = sum((square(3)), (square(4)))
]], show{ 'juxtaposed', 'invoked' }, '25 25\n',
    '`with` and invocation are the same operations, differing only in residual lifetime')

-- 3. A PRELUDE BETWEEN TWO STAGES runs after the first is supplied and before the second (§1.2). Both
--    orders typecheck, so the NUMBER is the only evidence, and `g(1, 2)` must agree with `g with 1 with 2`.
runs([[
let g = let a : Int
    let p = a * 10
    let b : Int
do : Int
    return p + b
end
let staged = g with 1 with 2
let invoked = g(1, 2)
]], show{ 'staged', 'invoked' }, '12 12\n',
    'a prelude between stages runs in the middle, and invocation interleaves the same way')

-- 4. THE OPERATORS, with §1.5's division: `and`, `or`, `not` are Bool to Bool, comparisons are Int to
--    Bool, everything else is Int to Int, and precedence is data in the parser.
runs([[
let a = 2 + 3 * 4
let b = (2 + 3) * 4
let c = 10 % 3
let d = 1 < 2
let e = true and false
let f = not false
let g = 0 - 5
let h = 1 << 4
]], show{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' }, '14 20 1 1 0 1 -5 16\n',
    'arithmetic binds tighter than comparison, and truth is Bool to Bool')

-- 5. AGGREGATES: a record is a chain (§3.1), a member is read by name, a tuple member by constant index.
runs([[
let make = let n : Int do : Int
    let r = { let x = n let y = n * 2 }
    return r.x + r.y
end
let tuple = let n : Int do : Int
    let t = { 10, 20, 30 }
    return t[1] + n
end
let a = make with 3
let b = tuple with 5
]], show{ 'a', 'b' }, '9 25\n', 'a record member is named and a positional member is indexed')

-- 6. CONTROL FLOW, with the one thing that is easy to get wrong: `continue` belongs to the loop, not the
--    `if` it is written inside.
runs([[
let total = let n : Int do : Int
    let i mut = 0
    let sum mut = 0
    while i < n do
        i = i + 1
        if i == 3 do
            continue
        end
        sum = sum + i
    end
    return sum
end
let answer = total with 5
]], show{ 'answer' }, '12\n', 'a loop with an `if` around a `continue` skips exactly one turn')

-- 7. `switch` on constants, with the fall-through: a subject no arm catches CONTINUES after the switch
--    (§12.3), which is what `else` is for.
runs([[
let describe = let n : Int do : Int
    switch n do
    case 0
        return 100
    case 1
        return 200
    else
        return 300
    end
end
let a = describe with 0
let b = describe with 1
let c = describe with 2
]], show{ 'a', 'b', 'c' }, '100 200 300\n', 'a label is compared by value and `else` catches the rest')

-- 8. A SUM of Copy alternatives: construction is by the value's own type (§3.5), and an arm that matches
--    BINDS what it matched -- reaching a payload is not an operation.
runs([[
let describe = let v : Int | Bool do : Int
    switch v do
    case Int as n
        return n
    case Bool as b
        return 1
    end
end
let a = describe with 7
let b = describe with true
]], show{ 'a', 'b' }, '7 1\n', 'a sum is built by type match and read by the arm that matched it')

-- 9. INTERIOR MUTABILITY (§3.7): a `mut` MEMBER is writable through a binding that is not `mut`, because
--    writability is a property of the path.
runs([[
let f = let n : Int do : Int
    let r = { let x mut = 1 }
    r.x = 9
    return r.x
end
let answer = f with 0
]], show{ 'answer' }, '9\n', 'a mut member is written through a read-only binding')

-- 10. TEXT and a conversion: `Text` is a module-lifetime literal and `TextSize` is a dictionary word, so
--     it is applied like any other word (§2.4).
runs([[
let size = let n : Int do : Int
    return TextSize with "hello" + n
end
let answer = size with 1
]], show{ 'answer' }, '6\n', 'a conversion is a word, and `with` binds tighter than `+`')

-- 11. An ANNOTATION is checked, and the check is on the DECLARATION (§S82: a body `let` carries its
--     annotation, which it did not before -- and then `let x : Bool = 1` was accepted).
refuses([[
let f = let n : Int do : Int
    let x : Bool = 1
    return n
end
let a = f with 1
]], R.MismatchedType, 'a body binding whose annotation its value does not fit')

-- 13. ... while INVOCATION is transient saturation, so it has to supply every stage (§S62).
refuses([[
let sum = let a : Int let b : Int do : Int
    return a + b
end
let answer = sum(1)
]], R.Undersaturated, 'an invocation that does not saturate the chain')

-- 14. A BOUND partial application is a word, and applying it again is application: §1.2's "stable
--     specialization" makes `sum with 1` a value, so naming it and applying it is the same chain.
--     (It was `NeedsMove`, and before that `NotExecutable` and a `Bug`, because §2.5's Copy rule for a
--     word value -- its packet -- had no owner that could see the template.)
runs([[
let sum = let a : Int let b : Int do : Int
    return a + b
end
let add_one = sum with 1
let answer = add_one with 2
]], show{ 'answer' }, '3\n', 'a partially applied word is a value that can be applied again')

-- 15. IMPORT: a file IS a chain (§2.6), so importing one gives its TERMINAL -- a namespace whose members
--     are its preludes, which is the only way a word in another file is reached. The path is resolved
--     from the process's directory, which is the repository root when the suite runs.
local write = function(path, text)
    local file = assert(io.open(path, 'wb'))
    file:write(text)
    file:close()
end
write(H.directory .. '/imported.let', 'let twice = let n : Int do : Int\n    return n * 2\nend\n')
runs([[
let other = import with "test/out/imported.let"
let answer = other.twice with 21
]], show{ 'answer' }, '42\n', 'an imported file is a chain and its namespace holds its words')

-- 16. A SUM THAT OWNS SOMETHING, destroyed by its TAG. §3.5: "destroying a sum needs a destructor
--     chosen by its tag" -- and until this existed nothing was emitted for a sum at all, so the value it
--     held leaked silently, which only a host counting its own allocations can see. The `Handle` type
--     comes FIRST, as a host header: the unit names it, the host defines it.
runs([[host Handle release
extern pure made (n : Int) : Handle
let f = let n : Int do : Int
    let s : Int | Handle = made with n
    return n
end
let answer = f with 1
]], [[
int64_t made_calls = 0, release_calls = 0;
Handle made(int64_t n) { made_calls = made_calls + 1; return (Handle){n}; }
void release(Handle h) { (void)h; release_calls = release_calls + 1; }
int main(void){ struct let_s1 m = let_module_init();
    printf("%lld made=%lld released=%lld\n", (long long)m.answer, (long long)made_calls, (long long)release_calls);
    return 0; }
]], '1 made=1 released=1\n', 'a sum that owns a value is destroyed by its tag, exactly once',
    'typedef struct { int64_t tag; } Handle;\n')

-- 17. A FLOAT literal. §11.3 declares `Float` in `Syntax`, `Semantic`, `Belt` and `rep`, and until now
--     nothing produced one -- the lexer had no float token -- so `Float` and `Float32` were types no
--     value could have. Its value is `Semantic.float_value` (§S38's one owner of a literal's value), the
--     belt op is `FloatLiteral`, and `C.Float` prints with `%a`, so nothing is rounded on the way out.
--     (A leading digit is required, because `.` is the projection: `.5` is not a literal here.)
runs([[
extern pure half (x : Float) : Float
let answer = half with 5.0
]], [[
double half(double x) { return x / 2.0; }
int main(void){ struct let_s1 m = let_module_init(); printf("%g\n", m.answer); return 0; }
]], '2.5\n', 'a float literal reaches a host word and comes back')

-- 18. A MEMBER'S VALUE IS A CHAIN (§3.1: "a record type and a value aggregate are the same form"), so a
--     member with a PRELUDE is not a special case -- it is a binding whose value is a chain, the same
--     thing a file's prelude is. It was `Missing(MemberPrelude)` because the member path resolved the
--     TERMINAL and refused anything before it.
runs([[
let x = { let a = let b = 1; b let c = 2 }
let answer = x.a + x.c
]], show{ 'answer' }, '3\n', 'a member whose value is a chain: its prelude runs when the member is taken')

-- 19. And the positional form. Inside braces a leading `let` begins a NAMED aggregate (§S27), so the
--     reachable positional element-that-is-a-chain is the one where the named parse FAILS: the comma is
--     what makes it a tuple, and its first element is a chain with its own prelude.
runs([[
let t = { let a = 2; a, 3 }
let answer = t[0] + t[1]
]], show{ 'answer' }, '5\n', 'a positional element whose value is a chain')

-- 20. A RUNTIME INDEX. §12.1's row -- "is this step a constant or a runtime index?" -- is DERIVED: a
--     constant names a member by offset, and a runtime value is a DISPATCH on it, one test per member,
--     each arm reading the constant offset it is about. The value crosses in a CELL, because this design
--     has no value phi outside `and`/`or` (§S35) and §11.7 says exactly why a cell is the alternative:
--     its identity does not change across a join, only its contents, "and contents are memory, not an
--     SSA name". An index that names no member traps (§1.5).
runs([[
let pick = let i : Int do : Int
    let a = { 10, 20, 30 }
    return a[i]
end
let first = pick with 0
let last = pick with 2
]], show{ 'first', 'last' }, '10 30\n', 'an index that is a runtime value names a member at run time')

--     ... and the members have to be ONE type, or there is no type for the dispatch to produce. That is
--     the same question §3.5 asks of a sum's alternatives, asked of a record's members.
refuses([[
let f = let i : Int do : Int
    let a = { 1, true }
    return a[i]
end
let x = f with 0
]], R.MismatchedType, 'a runtime index into members that do not share one type')

-- 21. A RUNTIME INDEX AS A DESTINATION. The same dispatch with a `StoreField` in each arm, and it is the
--     one destination that is NOT a place -- a place is one address, and the index decides which address
--     at run time -- so it is answered before `lower_place` rather than by it.
runs([[
let set = let i : Int do : Int
    let a mut = { 1, 2, 3 }
    a[i] = 9
    return a[0] + a[1] + a[2]
end
let first = set with 0
let last = set with 2
]], show{ 'first', 'last' }, '14 12\n', 'storing through a runtime index writes the member it names')

-- 22. A WRITTEN TERMINAL (§2.6): the module value IS the terminal's value, and `unload` destroys what
--     the module owns. That half did not exist -- `unload` was generated only for the implicit namespace
--     -- so a written terminal holding a resource leaked it at unload in silence, which is the same
--     class as §S83's sum leak and was found the same way, by looking for what had no name.
runs([[host Handle release
extern pure made (n : Int) : Handle
let h = made with 1
; { let x = move h }
]], [[
int64_t made_calls = 0, release_calls = 0;
Handle made(int64_t n) { made_calls = made_calls + 1; return (Handle){n}; }
void release(Handle h) { (void)h; release_calls = release_calls + 1; }
int main(void){ struct let_s1 m = let_module_init(); let_module_unload(m);
    printf("made=%lld released=%lld\n", (long long)made_calls, (long long)release_calls);
    return 0; }
]], 'made=1 released=1\n', 'a written terminal owns its value and unload destroys it',
    'typedef struct { int64_t tag; } Handle;\n')

-- 23. A WORD LITERAL IS A VALUE (§1.4/§3.1): braces around STAGES are a word, and §11.1 makes a chain
--     with stages an instance of its own -- so `{ let a : Int let b : Int }` is the record CONSTRUCTOR
--     the parser means it to be, and its result is the aggregate of the stage names. It was
--     `Bug(NoLowering(form = initializer))`: an INTERNAL error for a shape the grammar produces on
--     purpose. A program the grammar accepts may not be the compiler's own fault.
runs([[let Pair = { let a : Int let b : Int }
let p = Pair with 1 with 2
; { let a = p.a let b = p.b }
]], show{ 'a', 'b' }, '1 2\n', 'a word literal is a record constructor')

-- 24. And a word whose TERMINAL is a word is a word of its own (§11.1 read through §S3): `let T : Int
--     { ... }` takes `T` and yields that constructor, so applying it names the constructor. `word_of`
--     walked the DECLARATION and stopped at the application, so this read `stages[prefix + 1]` where no
--     stage was -- a CRASH -- while `Contract`, which reads the callee off the TYPE, accepted it.
runs([[let Pair = let T : Int { let a : Int let b : Int }
let p = Pair with 5
let q = p with 1 with 2
; { let a = q.a let b = q.b }
]], show{ 'a', 'b' }, '1 2\n', 'a word whose terminal is a word yields it when it saturates')

-- 25. WORDS AS TYPES: a name that denotes a word may be used as a TYPE and it means the type of that
--     word's VALUE -- `Semantic.Word(template, 0)`, which is §S3's nominality. It was `UnknownType`
--     because the type position asked `type_of_name`, which knows primitives and host types.
runs([[let square = let x : Int do : Int return x * x end
let f : square = square
let r = f with 3
; { let r = r }
]], show{ 'r' }, '9\n', 'a word name is usable as a type')

-- 26. And nominality is the WHOLE point (§S3): the type names ONE word, so a word of the same shape is
--     not it. This is the row refusing exactly one program for exactly the right reason -- the shape is
--     not the identity, which is what "nominal in (template, prefix)" means.
refuses([[
let square = let x : Int do : Int return x * x end
let other = let y : Int do : Int return y + 1 end
let f : square = other
]], R.MismatchedType, 'a word of the same shape is not the word the type names')

-- 27. THE CALLEE IS SELECTED AT THE CALL SITE (§11.1/§S3): a stage whose type is a WORD names that word,
--     so `g(x)` has a callee with no vtable -- "words are monomorphic; polymorphism is words". It was
--     `NotExecutable`, because `word_of` had no branch for a stage and `base_of` built a packet from
--     source instead of handing over the one the caller passed.
runs([[let square = let x : Int do : Int return x * x end
let apply = let g : square let x : Int do : Int
    return g(x)
end
let r = apply with square with 3
; { let r = r }
]], show{ 'r' }, '9\n', 'a word-typed stage is called through its nominal type')

-- 28. An ARROW-typed stage is the one shape that does NOT name its word -- `Int -> Int` is a SHAPE --
--     so there is no callee to select and no vtable to select one with. Recorded rather than fixed: the
--     refusal is honest (there is nothing to execute), and `Semantic.Arrow` is produced by the type
--     position and consumed by nothing, which is exactly what makes this the boundary.
refuses([[
let square = let x : Int do : Int return x * x end
let apply = let g : Int -> Int let x : Int do : Int
    return g(x)
end
let r = apply with square with 3
]], R.NotExecutable, 'an arrow-typed stage names no word, so there is nothing to call')

-- 29. A SUM OF WORDS is where §S2's "a runtime tag is a sum plus `switch`" meets §S3's nominality.
--     `Contract` decides the injection on SEMANTIC types, where `Word(square)` and `Word(inc)` are
--     distinct; `Lower` re-derived it from the BELT, where both words' empty packets are `uint8_t`, so
--     it matched the last alternative and every arm dispatched to one body -- and at a BORROWED stage
--     it emitted no injection at all, which `cc` reported as a type error rather than the compiler.
--     Both halves are the same sentence: which alternative a value inhabits is a SEMANTIC question.
runs([[
let square = let x : Int do : Int return x * x end
let inc = let x : Int do : Int return x + 1 end
let twice = let f : square | inc let x : Int do : Int
    switch f do
    case square as g return g(g(x))
    case inc as g return g(g(x))
    end
end
let answer = twice(square, 3) + twice(inc, 3)
]], show{ 'answer' }, '86\n', 'a borrowed sum-of-words stage injects, and each arm runs its own word')

-- 30. The SAME program through a taking stage, with the SECOND alternative twice: a wrong tag here is
--     not a type error but a wrong ANSWER, so this is the check that the tag is the alternative and not
--     whichever one the representation happened to match first (or last).
runs([[
let square = let x : Int do : Int return x * x end
let inc = let x : Int do : Int return x + 1 end
let twice = let f own : square | inc let x : Int do : Int
    switch f do
    case square as g return g(g(x))
    case inc as g return g(g(x))
    end
end
let answer = twice(inc, 3) + twice(inc, 3)
]], show{ 'answer' }, '10\n', 'the tag is the alternative Contract chose, not one the belt matched')

-- 31. And the injection is asked at every site that expects a sum, not only at a stage: a BINDING whose
--     annotation is the sum, reached through a CAPTURE. `belt_type_of` followed "a Value whose value is
--     a Reference" as if it were a capture, which also matched an ordinary binding holding a word value
--     -- so the slot was typed as the PACKET and the sum was never built. `L_.capture_of_binder` is the
--     real question, and it is answered before anything is lowered.
runs([[
let square = let x : Int do : Int return x * x end
let inc = let x : Int do : Int return x + 1 end
let chosen : square | inc = inc
let twice = let f : square | inc let x : Int do : Int
    switch f do
    case square as g return g(g(x))
    case inc as g return g(g(x))
    end
end
let main = let x : Int do : Int return twice(chosen, x) end
]], [[
int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_main_entry(m, 3)); return 0; }
]], '5\n', 'a sum-typed binding injects, and a capture of it keeps the sum')

-- 32. A PARTIAL APPLICATION IS A TYPE. `let add2 = add with 2` binds a word at prefix 1, and §S3's
--     nominality says its type is `Word(add, 1)` -- so `f : add2` is a perfectly good annotation and a
--     stage typed by it is invocable (§S99). `Resolve` runs before `Contract`, so the type cannot be
--     ASKED for; it is DERIVED from the declaration by `Judge.word_of` -- the same function `Lower`
--     selects a callee with -- and a hand-rolled walk that stopped at the `Apply` made this
--     `UnknownType` while `add2 with 3` lowered. Note what the two packets are: `add2` holds `{a: Int}`
--     and `mul3` holds `{a: Int}`, so the SUM's alternatives have one representation between them --
--     §S100's collision in its strongest form, which the semantic tag and the carried label survive.
runs([[
let add = let a : Int let b : Int do : Int return a + b end
let mul = let a : Int let b : Int do : Int return a * b end
let add2 = add with 2
let mul3 = mul with 3
let apply = let f : add2 | mul3 let x : Int do : Int
    switch f do
    case add2 as g return g(x)
    case mul3 as g return g(x)
    end
end
let answer = apply(add2, 5) + apply(mul3, 5)
]], show{ 'answer' }, '22\n', 'a partial application names a type, and two of them still inject apart')

H.finish()
