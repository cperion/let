-- Partial evaluation must erase known structure, never observable runtime effects.
package.path = './?.lua;./?/init.lua;' .. package.path
local compiler, V = require('let'), require('let.vocab')
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local text = {[[
let choose = let flag : Bool; let x : Int; do
    if flag do return x * 6 end
    return x * 7
end
let pending = choose true
let folded = do return pending(7) end
let affine = let x : Int; do return 3 * x + 7 end
let effect = let x : Int; do let ignored = tick(x); return x + 1 end
let delayed = effect 41
let bump = let x mut : Int; do x = x + 1; return x end
let alter = let x own mut : Int; do x = x + 1; return x end
let owned_copy = do return alter(41) end
let frozen = do
    let x mut = 10
    let stable = x + 1
    let next = bump(mut x)
    return stable * 100 + x
end
let ordered = do let x mut = 10; return x + bump(mut x) end
let skipped = do return false and (tick(99) == 0) end
let skipped_return = do if true do return 42 end; return tick(99) end
let bad = do return 1 / 0 end
]]}
local options = {hosts = {tick = {symbol = 'probe_tick', result = 'Int', stages = {{constraint = 'Int'}}}}}
local values = {'0', '1', '-1', '7', '-7', '3', '-3', '9007199254740993', '-9007199254740993',
    '9223372036854775807', '-9223372036854775808', '6364136223846793005'}
local ops = {{'add','+'}, {'sub','-'}, {'mul','*'}, {'div','/'}, {'mod','%'}}
local assertions = {}
local function cvalue(value)
    return value == '-9223372036854775808' and 'INT64_MIN' or 'INT64_C(' .. value .. ')'
end
for _, operation in ipairs(ops) do
    local name, op = unpack(operation)
    text[#text + 1] = ('let rt_%s = let a : Int; let b : Int; do return a %s b end'):format(name, op)
    for i, a in ipairs(values) do
        for _, j in ipairs{3, 6, 11} do
            local b = values[j]
            local fn = ('ct_%s_%d_%d'):format(name, i, j)
            text[#text + 1] = ('let %s = do return (%s) %s (%s) end'):format(fn, a, op, b)
            local ca, cb = cvalue(a), cvalue(b)
            local expected
            if op == '/' or op == '%' then
                local exceptional = op == '/' and 'INT64_MIN' or '0'
                expected = ('((%s == INT64_MIN && %s == -1) ? %s : (%s %s %s))'):format(ca, cb, exceptional, ca, op, cb)
            else expected = ('((uint64_t)%s %s (uint64_t)%s)'):format(ca, op, cb) end
            assertions[#assertions + 1] = ('assert((uint64_t)let_%s() == (uint64_t)(%s));'):format(fn, expected)
            assertions[#assertions + 1] = ('assert(let_%s() == let_rt_%s(%s, %s));'):format(fn, name, ca, cb)
        end
    end
end
local source, _, residual, stats = compiler.compile(table.concat(text, '\n'), 'residual.let', options)
check(not package.loaded.cblock, 'CBlock must not be loaded')
local functions = {}; for _, fn in ipairs(residual.functions) do functions[fn.c_name] = fn end
for name, info in pairs(stats) do
    if name:match('^let_ct_') or name == 'let_folded' or name == 'let_skipped_return' then
        check(info.locals == 0 and info.labels == 0 and info.calls == 0, name .. ' must be fully folded')
        local body = functions[name].body.statements
        check(#body == 1 and V.Residual.ReturnStmt:isclassof(body[1]) and body[1].value:known() ~= nil, 'expected literal residual return')
    end
end
check(stats.let_affine.locals == 0 and stats.let_affine.labels == 0, 'affine must be a single expression')
check(stats.let_delayed.calls == 1, 'known arguments must not erase ordered host effects')
check(stats.let_skipped.calls == 0, 'short-circuiting must erase unreachable host work')
for _, bad in ipairs{
    'let bad = do return false and (9223372036854775808 == 0) end',
    'let bad = do if true do return 1 end; return 9223372036854775808 end',
    'let bad = do return not (9223372036854775808 == 0) end',
} do
    local ok, err = pcall(compiler.compile, bad, 'dead-invalid.let')
    check(not ok and tostring(err):match('integer literal out of Int range'), 'checking must precede partial evaluation')
end
local harness = [[
#include <assert.h>
static int count; static int64_t last;
int64_t probe_tick(int64_t x) { ++count; last = x; return x; }
int main(int argc, char **argv) {
  (void)argv;
  if (argc > 1) { let_bad(); return 0; }
  assert(let_folded() == 42);
  assert(let_owned_copy() == 42);
  assert(let_frozen() == 1111);
  assert(let_ordered() == 21);
  assert(!let_skipped() && count == 0);
  assert(let_skipped_return() == 42 && count == 0);
  assert(let_delayed() == 42 && count == 1 && last == 41);
]] .. table.concat(assertions, '\n') .. '\nreturn 0;\n}\n'
local base = os.tmpname(); os.remove(base)
local paths = {}
local function path(suffix) local value = base .. suffix; paths[#paths + 1] = value; return value end
local function command(cmd) local status = os.execute(cmd); check(status == 0 or status == true, cmd) end
local function run()
    local cfile = path('.c'); local file = assert(io.open(cfile, 'wb')); file:write(source, harness); file:close()
    local cc = os.getenv('CC') or 'cc'
    for _, opt in ipairs{'-O0', '-O2', '-O3'} do
        local exe = path(opt)
        command(cc .. ' -std=c99 ' .. opt .. ' -Werror=parentheses -fsanitize=undefined -fsanitize-undefined-trap-on-error ' .. string.format('%q', cfile) .. ' -o ' .. string.format('%q', exe))
        command(string.format('%q', exe))
        local status = os.execute('ulimit -c 0; ' .. string.format('%q', exe) .. ' trap >/dev/null 2>&1')
        check(status ~= 0 and status ~= true, 'constant zero divisor must trap at runtime')
    end
end
local ok, err = pcall(run)
for _, p in ipairs(paths) do os.remove(p) end
assert(ok, err)
print(('passed %d residualization checks plus %d native assertions at each of -O0/-O2/-O3'):format(checks, #assertions + 7))

