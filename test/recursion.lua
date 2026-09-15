-- Native recursion and structural tail-transfer regressions.
package.path = './?.lua;./?/init.lua;' .. package.path
local compiler, V, ffi = require('let'), require('let.vocab'), require('ffi')
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, (label or 'assertion') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    checks = checks + 1
end
local function rejects(text, pattern)
    local ok, err = pcall(compiler.compile, text, 'recursion-negative.let')
    assert(not ok and tostring(err):match(pattern), tostring(err))
    assert(tostring(err):match('recursion%-negative%.let:%d+:%d+:'), tostring(err))
    checks = checks + 1
end
local text = [[
let factorial = let n : Int; do
    if n <= 1 do return 1 end
    return n * factorial(n - 1)
end
let backward = let n : Int; do
    if n > 1 do return backward(n - 1) * n end
    return 1
end
let fib = let n : Int; do
    if n < 2 do return n end
    return fib(n - 1) + fib(n - 2)
end
let sum = let n : Int; let acc : Int; do
    if n == 0 do return acc end
    return sum(n - 1, acc + n)
end
let swap = let n : Int; let a : Int; let b : Int; do
    if n == 0 do return a * 100 + b end
    return swap(n - 1, b, a)
end
let power = let base : Int; let n : Int; let acc : Int; do
    if n == 0 do return acc end
    let next = power with base
    return next(n - 1, acc * base)
end
let two_power = power with 2
let countdown = let n : Int; do
    if n > 0 do return countdown(n - 1) end
end
let parity = let n : Int; do
    if n == 0 do return true end
    return not parity(n - 1)
end
let nested = let n : Int; do
    if n == 0 do return 0 end
    return nested(nested(n - 1)) + 1
end
let mixed = let n : Int; do
    if n == 0 do return 0 end
    if n % 2 == 0 do return mixed(n - 1) end
    return mixed(n - 1) + 1
end
let wrapper = do return factorial(factorial(3)) end
let partial_fact = factorial with 6
let wrapped_partial = do return partial_fact() end
let previous = let n : Int; do return factorial(n) end
let shadow = let shadow : Int; do return shadow end
let loop_tail = let n : Int; do
    while n > 0 do return loop_tail(n - 1) end
    return 42
end
let mutate_then_tail = let n : Int; let acc : Int; do
    let x mut = acc
    if n == 0 do return x end
    x = x + 1
    return mutate_then_tail(n - 1, x)
end
]]
local source, manifest, residual, statistics = compiler.compile(text, 'recursion.let')
equal(source, compiler.compile(text, 'recursion.let'), 'deterministic helpers and signatures')
equal(manifest.parity.result, V.Semantic.Bool, 'recursive Bool inference')
equal(manifest.countdown.result, V.Semantic.Unit, 'recursive Unit inference')
equal(manifest.factorial.result, V.Semantic.Int, 'recursive Int inference')
for _, name in ipairs{'sum', 'swap', 'power', 'two_power', 'countdown', 'loop_tail', 'mutate_then_tail'} do
    equal(statistics['let_' .. name].calls, 0, name .. ' has no native recursive call')
end
assert(statistics.let_factorial.calls > 0, 'non-tail recursion must use a native helper')
local helpers = {}
for _, function_ in ipairs(residual.functions) do
    if not function_.exported then
        assert(not helpers[function_.c_name], 'duplicate helper')
        helpers[function_.c_name] = true
    end
end
assert(next(helpers), 'expected at least one native helper')
ffi.cdef[[
int64_t let_factorial(int64_t); int64_t let_backward(int64_t); int64_t let_fib(int64_t);
int64_t let_sum(int64_t, int64_t); int64_t let_swap(int64_t, int64_t, int64_t);
int64_t let_power(int64_t, int64_t, int64_t); int64_t let_two_power(int64_t, int64_t);
uint8_t let_countdown(int64_t); bool let_parity(int64_t); int64_t let_nested(int64_t);
int64_t let_mixed(int64_t); int64_t let_wrapper(void); int64_t let_wrapped_partial(void);
int64_t let_previous(int64_t); int64_t let_shadow(int64_t); int64_t let_loop_tail(int64_t);
int64_t let_mutate_then_tail(int64_t, int64_t);
]]
local function write(path, data) local f = assert(io.open(path, 'wb')); f:write(data); f:close() end
local function command(cmd) local ok = os.execute(cmd); assert(ok == 0 or ok == true, cmd) end
local base = os.tmpname(); os.remove(base)
local cc = os.getenv('CC') or 'cc'
local paths = {}
local function path(suffix) local p = base .. suffix; paths[#paths + 1] = p; return p end
local function run()
    local cfile = path('.c'); write(cfile, source)
    for _, opt in ipairs{'-O0', '-O2'} do
        local library = path(opt .. '.so')
        command(cc .. ' -std=c99 ' .. opt .. ' -fsanitize=undefined -fsanitize-undefined-trap-on-error -fPIC -shared ' .. string.format('%q', cfile) .. ' -o ' .. string.format('%q', library))
        local m = ffi.load(library)
        equal(tonumber(m.let_factorial(10)), 3628800, 'factorial')
        equal(tonumber(m.let_backward(10)), 3628800, 'recursive return before base return')
        equal(tonumber(m.let_fib(12)), 144, 'two non-tail recursive calls')
        equal(tonumber(m.let_sum(1000000, 0)), 500000500000, 'deep tail recursion')
        equal(tonumber(m.let_swap(1000001, 12, 34)), 3412, 'parallel argument permutation')
        equal(tonumber(m.let_swap(1000000, 12, 34)), 1234, 'even parameter permutation')
        equal(tonumber(m.let_power(3, 5, 1)), 243, 'dynamic scalar specialization on a recursive edge')
        equal(tonumber(m.let_two_power(10, 1)), 1024, 'specialized recursive export')
        equal(m.let_countdown(1000000), 0, 'Unit tail recursion')
        equal(m.let_parity(10), true, 'Bool recursive result')
        equal(m.let_parity(11), false, 'Bool recursive result')
        equal(tonumber(m.let_nested(6)), 6, 'recursive call within recursive arguments')
        equal(tonumber(m.let_mixed(20)), 10, 'tail and non-tail edges coexist')
        equal(tonumber(m.let_wrapper()), 720, 'same-word nested caller arguments')
        equal(tonumber(m.let_wrapped_partial()), 720, 'saturated recursive word')
        equal(tonumber(m.let_previous(6)), 720, 'previously defined recursive word')
        equal(tonumber(m.let_shadow(42)), 42, 'stage shadows self name')
        equal(tonumber(m.let_loop_tail(1000000)), 42, 'tail return inside while')
        equal(tonumber(m.let_mutate_then_tail(1000000, 0)), 1000000, 'fresh locals on every tail iteration')
    end
    -- Structural checks above do not rely on cc performing tail-call optimization.
    -- Also run native -O0 with a deliberately small stack and a million transfers.
    local exe = path('.exe')
    write(cfile, source .. [[
int main(void) {
    if (let_sum(1000000, 0) != 500000500000LL) return 1;
    if (let_swap(1000001, 12, 34) != 3412) return 2;
    return let_countdown(1000000);
}
]])
    command(cc .. ' -std=c99 -O0 ' .. string.format('%q', cfile) .. ' -o ' .. string.format('%q', exe))
    command('(ulimit -s 256; ' .. string.format('%q', exe) .. ')')
    checks = checks + 1
end
local ok, err = pcall(run)
for _, p in ipairs(paths) do os.remove(p) end
assert(ok, err)
rejects('let f = do return f() end', 'cannot resolve recursive return shape')
rejects('let f = let n : Int; do if n == 0 do return true end; return 1 + f(n - 1) end', 'expected Int')
rejects('let f = let n : Int; do if n == 0 do return 1 end; return f(true) end', 'expected Int')
rejects('let f = let n : Int; do if n == 0 do return 1 end; return f() end', 'exactly saturate')
rejects('let f = let n : Int; do if n == 0 do return 1 end; return f(n, n) end', 'exactly saturate')
rejects('let f = let n : Int; let p = n + 1; do if n == 0 do return p end; return f(true) end', 'expected Int')
rejects('let f = let n : Int; let p = f(n); do return p end', 'unknown name f')
rejects('let f = do return g() end\nlet g = do return f() end', 'unknown name g')
print(('passed %d recursion checks (-O0/-O2, UBSan, bounded-stack native test)'):format(checks))

