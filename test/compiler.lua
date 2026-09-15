-- Run from the repository root: luajit test/compiler.lua
package.path = './?.lua;./?/init.lua;' .. package.path
local compiler = require('let')
local V = require('let.vocab')
local ffi = require('ffi')
local cases = 0
local function equal(actual, expected, label)
    assert(actual == expected, (label or 'assertion') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    cases = cases + 1
end
local function rejects(source, pattern)
    local ok, message = pcall(compiler.compile, source, 'negative.let')
    assert(not ok, 'unexpected acceptance: ' .. source)
    assert(tostring(message):match(pattern), tostring(message) .. ' did not match ' .. pattern)
    assert(tostring(message):match('negative%.let:%d+:%d+:'), 'diagnostic lacks source location: ' .. tostring(message))
    cases = cases + 1
end
local text = [[
let add = let a : Int; let b : Int; do return a + b end
let subtract = let a : Int; let b : Int; do return a - b end
let multiply = let a : Int; let b : Int; do return a * b end
let divide = let a : Int; let b : Int; do return a / b end
let modulo = let a : Int; let b : Int; do return a % b end
let negate = let a : Int; do return -a end
let less = let a : Int; let b : Int; do return a < b end
let double = multiply 2
let pending = multiply 6 7
let answer = do return pending() end
let minimum = do return -9_223_372_036_854_775_808 end
let maximum = do return 0x7fff_ffff_ffff_ffff end
let precise = do return 9_007_199_254_740_993 end
let short_and = do return false and (divide(1, 0) == 0) end
let short_or = do return true or (divide(1, 0) == 0) end
let logic = let a : Bool; let b : Bool; do return not a or b end
let empty = do return end
let unit_equal = do return {} == {} end
let precedence = do return -2 * 3 + 20 / 2 end
let shadow = do
    let x mut = 10
    if true do
        let x = x + 1
        if x != 11 do return 0 end
    end
    return x
end
let snapshot = do
    let x mut = 2
    let copied = x
    let scaled = multiply x
    x = 100
    return copied + scaled(20)
end
let staged =
    let a : Int
    let p = a + 10
    let b : Int
    do return p + b end
let call_staged = do return staged(12, 20) end
let local_after = do
    let x = 0
    if false do return 100 end
    let y = 42
    return x + y
end
let choose = let x : Bool; do
    if x do return 42 else return 7 end
end
let sum = let n : Int; do
    let i mut = 0
    let result mut = 0
    while i < n do
        result = result + i
        i = i + 1
    end
    return result
end
let early_loop = let n : Int; do
    let i mut = 0
    while i < n do
        if i == 3 do return i end
        i = i + 1
    end
    return n
end
let call_precedence = do return add (20, 22) end
let bare = multiply 6 7
let bare_call = do return bare() end
let nested_call = do return add(add(10, 11), add(10, 11)) end
let read_before_write = do
    let n mut = 10
    n = n + 1
    return n
end
]]
local source, manifest = compiler.compile(text, 'positive.let')
equal(manifest.answer.symbol, 'let_answer', 'manifest')
equal(manifest.maximum.result, V.Semantic.Int, 'result shape')
equal(source, compiler.compile(text, 'positive.let'), 'deterministic emission')
ffi.cdef[[
int64_t let_add(int64_t, int64_t); int64_t let_subtract(int64_t, int64_t);
int64_t let_multiply(int64_t, int64_t); int64_t let_divide(int64_t, int64_t);
int64_t let_modulo(int64_t, int64_t); int64_t let_negate(int64_t);
bool let_less(int64_t, int64_t); int64_t let_double(int64_t);
int64_t let_answer(void); int64_t let_minimum(void); int64_t let_maximum(void);
int64_t let_precise(void); bool let_short_and(void); bool let_short_or(void);
bool let_logic(bool, bool); uint8_t let_empty(void); bool let_unit_equal(void);
int64_t let_precedence(void); int64_t let_shadow(void); int64_t let_snapshot(void);
int64_t let_call_staged(void); int64_t let_local_after(void); int64_t let_choose(bool);
int64_t let_sum(int64_t); int64_t let_early_loop(int64_t);
int64_t let_call_precedence(void); int64_t let_bare_call(void); int64_t let_read_before_write(void);
int64_t let_nested_call(void);
]]
local function write(path, contents)
    local f = assert(io.open(path, 'wb')); f:write(contents); f:close()
end
local function command(text)
    local ok = os.execute(text)
    assert(ok == true or ok == 0, 'command failed: ' .. text)
end
local temporary = os.tmpname()
os.remove(temporary)
local cpath, library = temporary .. '.c', temporary .. '.so'
local function native_tests()
    write(cpath, source)
    for _, optimization in ipairs{'-O0', '-O2'} do
        command((os.getenv('CC') or 'cc') .. ' -std=c99 ' .. optimization .. ' -fsanitize=undefined -fsanitize-undefined-trap-on-error -fno-sanitize-recover=all -fPIC -shared ' .. string.format('%q', cpath) .. ' -o ' .. string.format('%q', library .. optimization))
        local m = ffi.load(library .. optimization)
        equal(tonumber(m.let_answer()), 42, 'specialized zero-input word')
        equal(tonumber(m.let_double(21)), 42, 'partial specialization')
        local minimum, maximum = m.let_minimum(), m.let_maximum()
        equal(tostring(minimum), '-9223372036854775808LL', 'minimum literal')
        equal(tostring(maximum), '9223372036854775807LL', 'maximum literal')
        equal(tostring(m.let_precise()), '9007199254740993LL', 'exact large literal')
        equal(m.let_add(maximum, 1), minimum, 'add wraps')
        equal(m.let_subtract(minimum, 1), maximum, 'subtract wraps')
        equal(tonumber(m.let_multiply(maximum, 2)), -2, 'multiply wraps')
        equal(m.let_negate(minimum), minimum, 'negate wraps')
        equal(m.let_divide(minimum, -1), minimum, 'division exceptional pair')
        equal(tonumber(m.let_modulo(minimum, -1)), 0, 'remainder exceptional pair')
        equal(tonumber(m.let_divide(-7, 3)), -2, 'signed division')
        equal(tonumber(m.let_modulo(-7, 3)), -1, 'signed remainder')
        equal(m.let_less(minimum, maximum), true, 'signed comparison')
        equal(m.let_short_and(), false, 'and skips trap')
        equal(m.let_short_or(), true, 'or skips trap')
        equal(m.let_logic(true, false), false, 'boolean logic')
        equal(m.let_logic(false, false), true, 'boolean logic')
        equal(m.let_empty(), 0, 'Unit fallthrough')
        equal(m.let_unit_equal(), true, 'Unit equality')
        equal(tonumber(m.let_precedence()), 4, 'precedence')
        equal(tonumber(m.let_shadow()), 10, 'lexical shadowing')
        equal(tonumber(m.let_snapshot()), 42, 'specialization captures a copy')
        equal(tonumber(m.let_call_staged()), 42, 'transient prelude')
        equal(tonumber(m.let_local_after()), 42, 'if without else preserves separator')
        equal(tonumber(m.let_choose(true)), 42, 'if true')
        equal(tonumber(m.let_choose(false)), 7, 'if false')
        equal(tonumber(m.let_sum(10)), 45, 'loop')
        equal(tonumber(m.let_early_loop(100)), 3, 'return exits invocation from loop')
        equal(tonumber(m.let_early_loop(2)), 2, 'loop exit')
        equal(tonumber(m.let_call_precedence()), 42, 'whitespace before invocation')
        equal(tonumber(m.let_bare_call()), 42, 'bare specialization')
        equal(tonumber(m.let_read_before_write()), 11, 'assignment RHS reads old value')
        equal(tonumber(m.let_nested_call()), 42, 'nested argument calls are not recursion')
        for i = -20, 20 do
            for j = -20, 20 do
                equal(tonumber(m.let_add(i, j)), i + j)
                equal(tonumber(m.let_subtract(i, j)), i - j)
                equal(tonumber(m.let_multiply(i, j)), i * j)
            end
        end
    end
    -- A violated divisor contract must terminate, not run undefined division.
    write(cpath, source .. '\nint main(void) { return (int)let_divide(1, 0); }\n')
    command((os.getenv('CC') or 'cc') .. ' -std=c99 -O2 ' .. string.format('%q', cpath) .. ' -o ' .. string.format('%q', temporary))
    local status = os.execute('(ulimit -c 0; ' .. string.format('%q', temporary) .. ') >/dev/null 2>&1')
    assert(status ~= 0 and status ~= true, 'zero divisor did not trap')
    cases = cases + 1
end
local ok, err = pcall(native_tests)
for _, path in ipairs{cpath, library .. '-O0', library .. '-O2', temporary} do os.remove(path) end
assert(ok, err)
rejects('let x = do return missing end', 'unknown name')
rejects('let x = 1\nlet x = 2', 'duplicate binding')
rejects('let x = do let a = 1; a = 2 end', 'immutable')
rejects('let x = do if 1 do return end end', 'expected Bool')
rejects('let x = do return true + 1 end', 'expected Int')
rejects('let x = do return 1 < 2 < 3 end', 'chained comparison')
rejects('let x = do return 9223372036854775808 end', 'out of Int range')
rejects('let x = do return -9223372036854775809 end', 'out of Int range')
rejects('let x = 0x_', 'invalid integer')
rejects('let x = 1__0', 'invalid integer')
rejects('let x = "text"', 'Text is not supported')
rejects('let x own = 1', 'own is only valid on an unsatisfied stage')
rejects('let x = let a mut own : Int; do return a end', 'qualifier order')
rejects('let x = do return x() end', 'cannot resolve recursive return shape')
rejects('let x = do return y() end\nlet y = do return 42 end', 'unknown name')
rejects('let f = let a : Int; do return a end\nlet x = do return f() end', 'exactly saturate')
rejects('let f = let a : Int; do return a end\nlet x = do return f(1,2) end', 'exactly saturate')
rejects('let f = do return 1 end\nlet x = f 1', 'oversaturated')
rejects('let x = do let a = 1; return a() end', 'invocation requires')
rejects('let x = do let a = 1; return a 2 end', 'specialization requires')
rejects('let f = let a : Int; let b : Int; do return a end\nlet x = f with 2', 'unknown name with')
rejects('let x = do if true do return 1 end end', 'inconsistent return shapes')
rejects('let x = do return 1; return 2 end', 'unreachable statement')
rejects('let x = let a; do return a end', 'require Int, Bool, or Unit annotations')
rejects('let x = let a = 1; do return a end', 'initial construction preludes')
rejects('let x = do let f = do return 1 end; return f() end', 'local word construction')
rejects('let x = let a : Int; let p = a + 1; do return p end\nlet y = x 1', 'persistent specialization with preludes')
print(('passed %d compiler checks (native -O0/-O2 + UBSan + diagnostics)'):format(cases))

