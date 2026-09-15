-- Binding-time guarantees, checked on the residual BEFORE invoking any C compiler.
package.path='./?.lua;./?/init.lua;' .. package.path
local compiler,V=require('let'),require('let.vocab')
local C,E=V.Residual,V.Evaluation
local count=0
local function check(ok,message) assert(ok,message); count=count+1 end
local text=[[
let power = let base : Int; let n : Int; do
    if n == 0 do return 1 end
    return base * power(base,n-1)
end
let power3 = power with 3
let folded_recursive = do return power3(6) end
let memoized = do return power3(6) + power3(6) end
let static_store = do
    let x mut = 10
    x = x + 1
    let frozen = x
    x = 100
    return frozen
end
let static_loop = do
    let i mut = 0
    let sum mut = 0
    while i < 5 do sum=sum+i; i=i+1 end
    return sum
end
let and_false = let b : Bool; do return b and false end
let or_true = let b : Bool; do return b or true end
let same_return = let b : Bool; do if b do return 7 end; return 7 end
let divide3 = let n : Int; do return n/3 end
let same_join = let b : Bool; do
    let x mut=0
    if b do x=7 end else do x=7 end
    return x
end
let change = let x mut : Int; let b : Bool; do
    if b do x=20; return 7 end
    x=30; return 7
end
let return_store_join = let b : Bool; do
    let x mut=1
    let y=change(mut x,b)
    return x+y
end
let static_borrow = do
    let x mut=1
    let y=change(mut x,true)
    return x+y
end
let grow = let step : Int; let n : Int; do
    if n <= 0 do return step end
    return grow(step+1,n-1)+step
end
let grow1 = grow with 1
let large_loop = do
    let i mut=0
    let sum mut=0
    while i < 10000 do sum=sum+i; i=i+1 end
    return sum
end
let advance = let x mut : Int; do x=x+1; return x end
let loop_borrow = let n : Int; do
    let i mut=0
    while i<n do let ignored=advance(mut i) end
    return i
end
let effect = let x : Int; do let ignored=tick(x); return x+1 end
let ordered_known = do let a=effect(41); let b=effect(41); return a+b end
let prelude = let x : Int; let ignored=touch(x); do return x+1 end
let cached_prelude = do let a=prelude(41); let b=prelude(41); return a+b end
let stop = do let value=open_box(5); let bad=1/0; let never=tick(99) end
let consume = let value own : Box; let n : Int; do return n end
let bottom_arg = do return consume(open_box(5),1/0) end
let no_box = do return no_box() end
let dead_resource = do return consume(no_box(),42) end
let escaped = let x mut : Int; do x=10; clobber(); return x end
let private_state = do let x mut=41; let ignored=tick(2); return x+1 end
let simple_cleanup = do let value=open_box(5) end
let conditional_cleanup = let b : Bool; do
    let value=open_box(5)
    if b do let consumed=move value end
end
let both_cleanup = let b : Bool; do
    let value=open_box(5)
    if b do let yes=move value end else do let no=move value end
end
]]
local options={resources={Box={destroy='probe_close'}},hosts={
    open_box={symbol='probe_open',result='Box',stages={{constraint='Int'}}},
    tick={symbol='probe_tick',result='Int',stages={{constraint='Int'}}},
    touch={symbol='probe_touch',result='Unit',stages={{constraint='Int'}}},
    clobber={symbol='probe_clobber',result='Unit'}
}}
local source,_,module,stats=compiler.compile(text,'partial.let',options)
local functions,symbols={},{}
for _,fn in ipairs(module.functions) do functions[fn.c_name]=fn; symbols[fn.id]=fn.c_name end
for name,value in pairs{folded_recursive=729,memoized=1458,static_store=11,static_loop=10,same_join=7,static_borrow=27,and_false=false,or_true=true,same_return=7} do
    local fn=functions['let_' .. name]; local statements=fn.body.statements
    check(#statements==1 and C.ReturnStmt:isclassof(statements[1]),name .. ' must have only a residual return')
    check(statements[1].value:known()==value,name .. ' must return an exact literal')
end
local report=stats.partial_evaluation
check(report.cache_hits>0 and report.constants>0,'pure known invocations must be memoized')
local specialized=false
for _,entry in ipairs(report.specializations) do
    if entry.word==1 and entry.known[1]=='Int:3LL' then
        check(entry.dynamic==1,'invariant base must not occupy a residual parameter')
        check(#functions[entry.symbol].parameters==1,'specialized helper ABI must omit the known base')
        specialized=true
    end
end
check(specialized,'expected a memoized recursive specialization for base 3')
check(#module.functions<80,'changing known recursive arguments must generalize, not generate endless variants')
check(#source<100000,'generalization must bound residual size for this fixture')
check(stats.let_large_loop.locals>0,'large static loops must generalize at the evaluation budget')
check(stats.let_ordered_known.calls==2,'known arguments must retain both ordered calls')
check(stats.let_cached_prelude.calls==2,'memoization must not skip or replay ordered preludes')
check(stats.let_stop.calls==1 and stats.let_bottom_arg.calls==1,'known traps must stop evaluation without cleanup or later effects')
check(stats.let_dead_resource.calls==0,'bottom resource values must not manufacture owners or calls')
local private_body=functions.let_private_state.body.statements
check(private_body[#private_body].value:known()==42,'unknown effects must not erase private unescaped state')
local plain=functions.let_simple_cleanup:emit(symbols)
local conditional=functions.let_conditional_cleanup:emit(symbols)
local both=functions.let_both_cleanup:emit(symbols)
check(not plain:find('bool v',1,true),'known initialization must not get a runtime alive flag')
check(conditional:find('bool v',1,true),'genuinely conditional initialization requires an alive flag')
check(not both:find('bool v',1,true),'equal moved states must join without an alive flag')
check(E.Known:isclassof(require('let.domain').integer(42)),'known values must have an explicit binding-time constructor')
check(require('let.domain').integer(42):same(require('let.domain').integer(42)),'known equality is value equality, not allocation identity')
for _,path in ipairs{'let/residualize.lua','let/lifetime.lua','let/residual.lua','let/lower.lua','cblock.lua'} do
    local file=io.open(path,'rb'); if file then file:close() end
    check(not file,'obsolete implementation still present: ' .. path)
end
local harness=[[
#include <assert.h>
static int live, opened, closed, ticks, touches;
void probe_touch(int64_t n) { assert(n==41); ++touches; }
static int64_t external_value;
void probe_clobber(void) { external_value=99; }
int64_t probe_open(int64_t n) { ++live; ++opened; return n; }
void probe_close(int64_t n) { assert(n==5 && live>0); --live; ++closed; }
int64_t probe_tick(int64_t n) { ++ticks; return n; }
int main(void) {
  assert(let_folded_recursive()==729); assert(let_memoized()==1458);
  assert(let_power3(10)==59049); assert(let_static_store()==11);
  assert(let_static_loop()==10); assert(let_large_loop()==49995000);
  assert(let_same_join(true)==7 && let_same_join(false)==7);
  assert(!let_and_false(true) && !let_and_false(false));
  assert(let_or_true(true) && let_or_true(false));
  assert(let_same_return(true)==7 && let_same_return(false)==7);
  assert(let_divide3(-7)==-2);
  assert(let_static_borrow()==27);
  assert(let_return_store_join(true)==27 && let_return_store_join(false)==37);
  assert(let_grow1(20)==231); assert(let_loop_borrow(100)==100);
  assert(let_loop_borrow(0)==0); assert(let_loop_borrow(-1)==0);
  assert(let_ordered_known()==84 && ticks==2);
  assert(let_cached_prelude()==84 && touches==2);
  assert(let_escaped(&external_value)==99 && external_value==99);
  assert(let_private_state()==42 && ticks==3);
  let_simple_cleanup();
  let_conditional_cleanup(true); let_conditional_cleanup(false);
  let_both_cleanup(true); let_both_cleanup(false);
  assert(live==0 && opened==5 && closed==5);
  return 0;
}
]]
local base=os.tmpname(); os.remove(base)
local paths={}
local function path(suffix) local p=base .. suffix; paths[#paths+1]=p; return p end
local function run(command) local status=os.execute(command); check(status==0 or status==true,command) end
local ok,err=pcall(function()
    local file=path('.c'); local f=assert(io.open(file,'wb')); f:write(source,harness); f:close()
    for _,opt in ipairs{'-O0','-O2','-O3'} do
        local exe=path(opt)
        run((os.getenv('CC') or 'cc') .. ' -std=c99 ' .. opt .. ' -fsanitize=undefined -fsanitize-undefined-trap-on-error ' .. string.format('%q',file) .. ' -o ' .. string.format('%q',exe))
        run(string.format('%q',exe))
    end
end)
for _,p in ipairs(paths) do os.remove(p) end
assert(ok,err)
print(('passed %d partial-evaluation checks plus native assertions at -O0/-O2/-O3'):format(count))

