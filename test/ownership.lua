package.path = './?.lua;./?/init.lua;' .. package.path
local compiler, ffi, V = require('let'), require('ffi'), require('let.vocab')
local checks = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or 'assertion') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    checks = checks + 1
end
local function stage(constraint, capability) return { constraint = constraint, capability = capability or 'read' } end
local options = {
    resources = { Buffer = { destroy = 'test_drop' } },
    hosts = {
        new_buffer = { symbol = 'test_new', stages = {stage('Int')}, result = 'Buffer' },
        inspect = { symbol = 'test_inspect', stages = {stage('Buffer')}, result = 'Int' },
        consume = { symbol = 'test_consume', stages = {stage('Buffer', 'own')} },
        mark = { symbol = 'test_mark', stages = {stage('Int')}, result = 'Int' },
        bump = { symbol = 'test_bump', stages = {stage('Int', 'mut')} },
        compare_buffers = { symbol = 'test_compare', stages = {stage('Buffer'), stage('Buffer')}, result = 'Bool' },
    }
}
local text = [[
let basic = do
    let a = new_buffer(1)
    let b = new_buffer(2)
    return 42
end
let scoped = do
    let a = new_buffer(1)
    if true do let b = new_buffer(2) end
    mark(9)
end
let replace = do
    let a mut = new_buffer(1)
    a = new_buffer(2)
    let result = inspect(a)
    return result
end
let moved = do
    let a = new_buffer(1)
    let b = move a
    consume(move b)
end
let conditional = let flag : Bool; do
    let a = new_buffer(1)
    if flag do consume(move a) end
end
let reinitialize = do
    let a mut = new_buffer(1)
    consume(move a)
    a = new_buffer(2)
end
let self_move = do
    let a mut = new_buffer(1)
    a = move a
end
let discard = do
    new_buffer(1)
    mark(9)
end
let borrow_temporary = do
    let value = inspect(new_buffer(1))
    mark(9)
    return value
end
let give = do
    let a = new_buffer(1)
    return move a
end
let receive = do
    let a = give()
    let value = inspect(a)
    return value
end
let tail_host = do
    let a = new_buffer(1)
    return mark(9)
end
let target = let x : Int; let p = mark(7); do mark(8); return x end
let tail_source = do
    let a = new_buffer(1)
    return target(mark(6))
end
let owned = let a own : Buffer; do
    let value = inspect(a)
    return value
end
let handoff = do
    let a = new_buffer(1)
    let b = new_buffer(2)
    return owned(move a)
end
let pass = let a own : Buffer; do return move a end
let pass_caller = do let a = pass(new_buffer(1)); end
let prelude_move = let a own : Buffer; let saved = move a; do return move saved end
let prelude_move_caller = do let a = prelude_move(new_buffer(1)); end
let resource_loop = do
    let i mut = 0
    while i < 3 do
        let a = new_buffer(i + 1)
        i = i + 1
    end
end
let resource_tail = let n : Int; let held = new_buffer(n); do
    if n == 0 do return 0 end
    return resource_tail(n - 1)
end
let resource_recursive = let n : Int; let held = new_buffer(n); do
    if n == 0 do return 0 end
    let answer = resource_recursive(n - 1)
    let value = inspect(held)
    return answer + value
end
let staged = let first : Int; let p = mark(2); let second : Int; do return first + second end
let staged_caller = do return staged(mark(1), mark(3)) end
let prelude_tail = let n : Int; let p = mark(n); do
    if n == 0 do return p end
    return prelude_tail(n - 1)
end
let prelude_recursive = let n : Int; let p = mark(n); do
    if n == 0 do return p end
    return p + prelude_recursive(n - 1)
end
let add = let a : Int; let b : Int; do return a + b end
let prelude_alias = let n : Int; let add_n = add with n; do
    if n == 0 do return add_n(0) end
    return add_n(1) + prelude_alias(n - 1)
end
let borrow_walk = let n : Int; let value mut : Int; let p = mark(n); do
    if n == 0 do return {} end
    value = value + 1
    return borrow_walk(n - 1, mut value)
end
let borrow_caller = do
    let value mut = 0
    borrow_walk(3, mut value)
    bump(mut value)
    return value
end
let replace_borrowed = let value mut : Buffer; do value = new_buffer(2) end
let borrowed_owner = do
    let value mut = new_buffer(1)
    replace_borrowed(mut value)
    let result = inspect(value)
    return result
end
let replace_owned = let value own mut : Buffer; do value = new_buffer(2) end
let owned_replace_caller = do replace_owned(new_buffer(1)) end
let read_overlap = do
    let a = new_buffer(1)
    let result = compare_buffers(a, a)
    return result
end
let carry = let n : Int; let a own : Buffer; let value = inspect(a); do
    if n == 0 do return move a end
    return carry(n - 1, move a)
end
let carry_caller = do let a = carry(3, new_buffer(1)) end
let borrowed_tail = let n : Int; let a mut : Buffer; let p = mark(n); do
    if n == 0 do return {} end
    a = new_buffer(n)
    return borrowed_tail(n - 1, mut a)
end
let borrowed_tail_caller = do
    let a mut = new_buffer(0)
    borrowed_tail(3, mut a)
end
let reader = let a : Buffer; do let value = inspect(a); return value end
let source_borrow_temporary = do
    let value = reader(new_buffer(1))
    mark(9)
    return value
end
let return_branch = let condition : Bool; do
    let a = new_buffer(1)
    if condition do
        let b = new_buffer(2)
        consume(move a)
        return 42
    end
    let value = inspect(a)
    return value
end
let restored_loop = do
    let i mut = 0
    let a mut = new_buffer(1)
    while i < 2 do
        consume(move a)
        a = new_buffer(2)
        i = i + 1
    end
end
]]
local source, manifest = compiler.compile(text, 'ownership.let', options)
equal(source, compiler.compile(text, 'ownership.let', options), 'deterministic ownership lowering')
equal(manifest.give.result.name, 'Buffer', 'owned result shape')
local mock = [[
#include <assert.h>
static int64_t payload[100000];
static unsigned char alive[100000];
static int64_t events[100000];
static int event_count, next_handle, live, highwater;
static void event(int64_t value) { assert(event_count < 100000); events[event_count++] = value; }
void test_reset(void) { assert(live == 0); event_count = 0; next_handle = 0; highwater = 0; }
int test_events(void) { return event_count; }
int64_t test_event(int i) { assert(i >= 0 && i < event_count); return events[i]; }
int test_live(void) { return live; }
int test_highwater(void) { return highwater; }
int64_t test_new(int64_t value) {
    int h = ++next_handle; assert(h < 100000 && !alive[h]); alive[h] = 1; payload[h] = value;
    ++live; if (live > highwater) highwater = live; event(1000 + value); return h;
}
void test_drop(int64_t h) { assert(h > 0 && h <= next_handle && alive[h]); alive[h] = 0; --live; event(2000 + payload[h]); }
int64_t test_inspect(int64_t h) { assert(alive[h]); event(3000 + payload[h]); return payload[h]; }
void test_consume(int64_t h) { event(4000 + payload[h]); test_drop(h); }
int64_t test_mark(int64_t value) { event(value); return value; }
void test_bump(int64_t *value) { ++*value; }
bool test_compare(int64_t a, int64_t b) { assert(alive[a] && alive[b]); return payload[a] == payload[b]; }
]]
ffi.cdef[[
void test_reset(void); int test_events(void); int64_t test_event(int); int test_live(void); int test_highwater(void);
int64_t let_basic(void); uint8_t let_scoped(void); int64_t let_replace(void); uint8_t let_moved(void);
uint8_t let_conditional(bool); uint8_t let_reinitialize(void); uint8_t let_self_move(void); uint8_t let_discard(void);
int64_t let_borrow_temporary(void); int64_t let_receive(void); int64_t let_tail_host(void); int64_t let_tail_source(void);
int64_t let_handoff(void); uint8_t let_pass_caller(void); uint8_t let_prelude_move_caller(void);
uint8_t let_resource_loop(void); int64_t let_resource_tail(int64_t); int64_t let_resource_recursive(int64_t);
int64_t let_staged_caller(void); int64_t let_prelude_tail(int64_t); int64_t let_prelude_recursive(int64_t);
int64_t let_prelude_alias(int64_t); uint8_t let_borrow_walk(int64_t, int64_t*); int64_t let_borrow_caller(void);
int64_t let_borrowed_owner(void); uint8_t let_owned_replace_caller(void); bool let_read_overlap(void);
uint8_t let_restored_loop(void); uint8_t let_carry_caller(void); uint8_t let_borrowed_tail_caller(void);
int64_t let_source_borrow_temporary(void); int64_t let_return_branch(bool);
]]
local function write(path, data) local f = assert(io.open(path, 'wb')); f:write(data); f:close() end
local function command(cmd) local ok = os.execute(cmd); assert(ok == true or ok == 0, cmd) end
local base = os.tmpname(); os.remove(base)
local paths = {}
local function path(suffix) local name = base .. suffix; paths[#paths + 1] = name; return name end
local function run()
    local cfile = path('.c'); write(cfile, source .. '\n' .. mock)
    for _, opt in ipairs{'-O0', '-O2'} do
        local library = path(opt .. '.so')
        command((os.getenv('CC') or 'cc') .. ' -std=c99 ' .. opt .. ' -fsanitize=undefined -fsanitize-undefined-trap-on-error -fPIC -shared ' .. string.format('%q', cfile) .. ' -o ' .. string.format('%q', library))
        local m = ffi.load(library)
        local function trace(name, expected, ...)
            m.test_reset(); local result = m['let_' .. name](...)
            equal(m.test_events(), #expected, name .. ' event count')
            for i, value in ipairs(expected) do equal(tonumber(m.test_event(i - 1)), value, name .. ' event ' .. i) end
            equal(m.test_live(), 0, name .. ' resource balance')
            return result
        end
        equal(tonumber(trace('basic', {1001,1002,2002,2001})), 42)
        trace('scoped', {1001,1002,2002,9,2001})
        equal(tonumber(trace('replace', {1001,1002,2001,3002,2002})), 2)
        trace('moved', {1001,4001,2001})
        trace('conditional', {1001,4001,2001}, true)
        trace('conditional', {1001,2001}, false)
        trace('reinitialize', {1001,4001,2001,1002,2002})
        trace('self_move', {1001,2001})
        trace('discard', {1001,2001,9})
        trace('borrow_temporary', {1001,3001,2001,9})
        trace('receive', {1001,3001,2001})
        trace('tail_host', {1001,2001,9})
        trace('tail_source', {1001,6,7,2001,8})
        trace('handoff', {1001,1002,2002,3001,2001})
        trace('pass_caller', {1001,2001})
        trace('prelude_move_caller', {1001,2001})
        trace('resource_loop', {1001,2001,1002,2002,1003,2003})
        trace('resource_tail', {1003,1002,2003,1001,2002,1000,2001,2000}, 3)
        equal(tonumber(trace('resource_recursive', {1003,1002,1001,1000,2000,3001,2001,3002,2002,3003,2003}, 3)), 6)
        trace('staged_caller', {1,2,3})
        trace('prelude_tail', {3,2,1,0}, 3)
        equal(tonumber(trace('prelude_recursive', {3,2,1,0}, 3)), 6)
        equal(tonumber(trace('prelude_alias', {}, 3)), 9)
        local pointer = ffi.new('int64_t[1]', 0)
        trace('borrow_walk', {3,2,1,0}, 3, pointer); equal(tonumber(pointer[0]), 3, 'exported mut ABI')
        equal(tonumber(trace('borrow_caller', {3,2,1,0})), 4)
        equal(tonumber(trace('borrowed_owner', {1001,1002,2001,3002,2002})), 2)
        trace('owned_replace_caller', {1001,1002,2001,2002})
        equal(trace('read_overlap', {1001,2001}), true)
        trace('restored_loop', {1001,4001,2001,1002,4002,2002,1002,2002})
        trace('carry_caller', {1001,3001,3001,3001,3001,2001})
        trace('borrowed_tail_caller', {1000,3,1003,2000,2,1002,2003,1,1001,2002,0,2001})
        trace('source_borrow_temporary', {1001,3001,2001,9})
        equal(tonumber(trace('return_branch', {1001,1002,4001,2001,2002}, true)), 42)
        equal(tonumber(trace('return_branch', {1001,3001,2001}, false)), 1)
        m.test_reset(); equal(tonumber(m.let_resource_tail(10000)), 0); equal(m.test_live(), 0); equal(m.test_highwater(), 2, 'tail preparation overlaps at most two resource activations')
    end
end
local ok, err = pcall(run)
for _, name in ipairs(paths) do os.remove(name) end
assert(ok, err)
local function rejects(source_, pattern)
    local accepted, message = pcall(compiler.compile, source_, 'ownership-negative.let', options)
    assert(not accepted and tostring(message):match(pattern), tostring(message))
    assert(tostring(message):match('ownership%-negative%.let:%d+:%d+:'), tostring(message))
    checks = checks + 1
end
rejects('let f = do let a = new_buffer(1); let b = a end', 'requires move')
rejects('let f = do let a = new_buffer(1); return a end', 'requires move')
rejects('let f = do let a = new_buffer(1); consume(a) end', 'requires move')
rejects('let f = do let a = new_buffer(1); consume(move a); inspect(a) end', 'use after move')
rejects('let f = do let a = new_buffer(1); let b = move a; let c = move a end', 'use after move')
rejects('let f = let a : Buffer; do return move a end', 'owning binding')
rejects('let f = let a mut : Buffer; do return move a end', 'owning binding')
rejects('let f = do let a = new_buffer(1); return inspect(a) end', 'outlive caller cleanup')
rejects('let f = do return inspect(new_buffer(1)) end', 'outlive caller cleanup')
rejects('let f = do let a mut = 1; return bump(mut a) end', 'outlive caller cleanup')
rejects('let f = do let a = 1; bump(mut a) end', 'writable binding')
rejects('let f = do let a mut = 1; bump(a) end', 'explicit mut')
rejects('let f = do let a mut = 1; mark(mut a) end', 'mut argument requires')
rejects('let f = let a mut : Int; let b : Int; do return b end\nlet g = do let a mut = 1; return f(mut a, a) end', 'outlive caller cleanup')
rejects('let f = let a mut : Int; let b : Int; do return b end\nlet g = do let a mut = 1; let x = f(mut a, a); return x end', 'conflicting borrow')
rejects('let f = let a : Buffer; let b own : Buffer; do return 1 end\nlet g = do let a = new_buffer(1); let x = f(a, move a); return x end', 'conflicting borrow')
rejects('let f = let flag : Bool; do let a = new_buffer(1); if flag do consume(move a) end; inspect(a) end', 'use after move')
rejects('let f = do let a = new_buffer(1); while true do consume(move a) end end', 'loop backedge')
rejects('let f = do let a = new_buffer(1); return a == a end', 'resource equality')
rejects('let f = let a own : Buffer; do return 1 end\nlet g = do let a = new_buffer(1); let bound = f with move a end', 'persistent owned resource')
rejects('let f = let a mut : Int; do return a end\nlet g = f with 1', 'persistent mutable borrow')
print(('passed %d ownership/prelude checks (-O0/-O2 + UBSan + exact resource traces)'):format(checks))

