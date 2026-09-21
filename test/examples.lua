-- The corpus: REAL programs, compiled and RUN.
--
-- The other suites check constructs -- one program per form. This one checks that a program somebody wrote
-- for a purpose still works, which is a different question and the one that found the `or` MISCOMPILE
-- (§S121): its answer was wrong, nothing else was. So a file here goes through the real pipeline, is
-- linked with the host it needs, and its OUTPUT is compared.
--
-- Every `.let` in `examples/` is run here. They were written against older surfaces (`Int -> do Int`,
-- application by juxtaposition, `c.puts`, an undeclared host type, `let_answer` as an entry point), and
-- reviving them was part of the work rather than a reason to skip them: a stale example is worse than none.
local H = require('test.harness')
H.suite = 'examples'
local runs = H.runs

local function read(path)
    local file = assert(io.open(path, 'rb'), path .. ' is missing')
    local text = file:read('*a')
    file:close()
    return text
end

local function example(name) return read('examples/' .. name .. '.let') end

-- 1. THE CALCULATOR (examples/calc.let). Tokenless precedence climbing over a C string: `mut` cells for the
--    position and the accumulator, self-recursion for the three levels (a parenthesised expression, a
--    unary minus, a number), `switch` with case LISTS to read the operator's precedence, and a sum of two
--    type words (`Result : Type = Ok | Err`) for the outcome. An error is a negative number -- `0 -
--    1000000 - position`, and `0 - 999999` for trailing junk -- so the answer and the diagnostic are one
--    value the host can print. Its one host word is `byte_at`, so the host below supplies it.
runs(example('calc'), [[
int64_t byte_at(const char *s, int64_t i) { return (int64_t)(unsigned char)s[i]; }
int main(void) {
    struct let_s1 m = let_module_init();
    const char *cases[] = {"1+2*3", "(1+2)*3", " 2 * (3 + 4) - 10 / 5", "-3*-(2+1)",
                           "1-2-3", "1+", "(1+2", "42 x"};
    for (int i = 0; i < 8; i++)
        printf("%s => %lld\n", cases[i], (long long)let_eval_entry(m, cases[i]));
    return 0;
}
]], [[
1+2*3 => 7
(1+2)*3 => 9
 2 * (3 + 4) - 10 / 5 => 12
-3*-(2+1) => 9
1-2-3 => -4
1+ => -1000002
(1+2 => -1000004
42 x => -999999
]], 'the calculator: precedence, parentheses, unary minus, and errors that carry a position')

-- 2. CONTROL (examples/control.let): an `if`/`else if` chain and a `switch` with case LISTS, both as words
--    the host calls -- the other half of what a real program needs from the surface.
runs(example('control'), [[
int main(void) {
    struct let_s1 m = let_module_init();
    printf("%lld %lld %lld\n", (long long)let_sign_entry(m, 0 - 5), (long long)let_sign_entry(m, 0),
        (long long)let_sign_entry(m, 7));
    printf("%lld %lld %lld %lld\n", (long long)let_classify_entry(m, 0),
        (long long)let_classify_entry(m, 1), (long long)let_classify_entry(m, 2),
        (long long)let_classify_entry(m, 3));
    return 0;
}
]], '-1 0 1\n10 20 20 30\n', 'control: an if chain and a switch with case lists, called by the host')

-- 3. CONTINUATIONS (examples/continuations.let): a dictionary of policy words, invoked only where the policy
--    says so -- and typed by the words' own NAMES, so the callee is known at the call site (§3.2).
runs(example('continuations'), [[
int main(void) { struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_answer_entry(m)); return 0; }
]], '42\n', 'continuations: policies as words, invoked only on the selected path')

-- 4. RECURSION (examples/recursion.let): a word's own name is visible in its body, so a self call is direct;
--    a second accumulating parameter is a second STAGE, because mutual recursion is not available.
--    `factorial(5)` is 120 and `sum_to(1_000_000, 0)` is 500000500000.
runs(example('recursion'), [[
int main(void) { struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_answer_entry(m)); return 0; }
]], '500000500120\n', 'recursion: a self call is direct, and a second accumulator is a second stage')

-- 5. SCALARS (examples/scalars.let): `mut` bindings are storage, a loop needs no special treatment, and a
--    partial application is a word. `double(21)` is 42 and `fibonacci(10)` is 55.
runs(example('scalars'), [[
int main(void) { struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_answer_entry(m)); return 0; }
]], '97\n', 'scalars: cells, a loop, and a partial application')

-- 6. HELLO (examples/hello.let): the host owns the world (§3.6), so `say` is the host's word and a `Text`
--    reaches it through the dictionary conversion `ToCString`.
runs(example('hello'), [[
#include <stdio.h>
int64_t say(const char *s) { puts(s); return 0; }
int main(void) { struct let_s1 m = let_module_init(); let_main_entry(m); return 0; }
]], 'hello, world\n', 'hello: the host owns output, and a conversion is a word')

-- 7. RESOURCES (examples/resources.let, with the host beside it): a declared host type whose destructor is
--    the host's, an `own` stage that takes what it is given, and a module that owns what it opened until
--    `unload`. The host ASSERTS the buffers are closed, so the ownership claim is checked, not described.
runs(example('resources'), read('examples/resources-host.c'), '48\n',
    'resources: ownership across the host boundary, destroyed at unload',
    'typedef int64_t Buffer;\n')   -- the host DECLARES the type, and a type precedes the unit

H.finish()
