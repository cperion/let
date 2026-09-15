package.path='./?.lua;./?/init.lua;' .. package.path
local compiler,V=require('let'),require('let.vocab')
local C=V.Residual
local count=0
local function check(value,message) assert(value,message); count=count+1 end
local options={resources={Box={destroy='probe_close'}},hosts={
    open_box={symbol='probe_open',result='Box',stages={{constraint='Int'}}},
    size={symbol='probe_size',result='Int',stages={{constraint='Box'}}},
    tick={symbol='probe_tick',result='Int',stages={{constraint='Int'}}},
    notify={symbol='probe_notify',result='Unit',stages={{constraint='Int'}}}
}}
local text=[[
let identity = let x : Int do return x end
let failure = let code : Int do return -code end
let checked = let ok : Executable let bad : Executable let a : Int let b : Int do
    if b == 0 do return bad(1) else return ok(a / b) end
end
let divide = checked identity failure
let answer = do return divide(84,2) end
let add = let a : Int let b : Int do return a+b end
let apply = let k let x : Int do return k(x) end
let host_callback = apply tick
let dynamic_capture = let n : Int do let k = add n return apply(k,2) end
let curry = let k : Executable let a : Int let pending = k a let b : Int do return pending(b) end
let curried = do return curry(add,20,22) end
let curry_body = let k : Executable let a : Int let b : Int do let pending = k a return apply(pending,b) end
let curried_body = do return curry_body(add,20,22) end
let compose = let k : Executable let x : Int do return apply(k,x) end
let nested = let n : Int do let k = add n let next = compose k return apply(next,2) end
let bounce = let k : Executable let n : Int do return k(n) end
let loop = let n : Int do if n <= 0 do return 42 end return bounce(loop,n-1) end
let recursive = let n : Int do if n <= 0 do return 0 end return bounce(recursive,n-1)+1 end
let bump = let x mut : Int do x=x+1 end
let mutable_apply = let k : Executable let x mut : Int do return k(mut x) end
let bump_once = mutable_apply bump
let local_bump = do let x mut=41 let ignored=mutable_apply(bump,mut x) return x end
let notify_apply = let k : Executable let x : Int do return k(x) end
let notification = notify_apply notify
let finish = let box own : Box do let n=size(box) return n end
let transfer = let k : Executable do let a=open_box(1) let b=open_box(2) return k(move b) end
let transfer_later = let k : Executable do let a=open_box(1) let b=open_box(2) let n=k(move b) return n end
let tail_resource = transfer finish
let normal_resource = transfer_later finish
let success_effect = let n : Int do return tick(n) end
let failure_effect = let n : Int do return tick(0-n) end
let effectful = checked success_effect failure_effect
]]
local source,manifest,module,stats=compiler.compile(text,'continuations.let',options)
local functions={}
for _,fn in ipairs(module.functions) do functions[fn.c_name]=fn end
for _,name in ipairs{'checked','apply','curry','curry_body','compose','bounce','transfer','mutable_apply'} do
    check(not manifest[name],'unsupplied continuation templates must not expose a C callback ABI: ' .. name)
end
for _,name in ipairs{'answer','curried','curried_body','local_bump'} do
    local body=functions['let_' .. name].body.statements
    check(#body==1 and C.ReturnStmt:isclassof(body[1]) and body[1].value:known()==42,'known continuation must disappear before C optimization: ' .. name)
end
for _,name in ipairs{'divide','dynamic_capture','nested','loop'} do
    check(stats['let_' .. name].calls==0,'known continuation must leave no calls: ' .. name)
end
check(source:find('goto ',1,true),'indirect tail cycle needs an explicit backedge')
check(not source:find('%(%*[%a_][%w_]*%)%s*%('),'no residual function pointer ABI')
check(#source<40000,'recursive specialization must remain bounded')
local tokens=require('let.lexer').new(text,'reflow.let'):scan()
local spelling={}
for _,token in ipairs(tokens) do if token.tag~='eof' then spelling[#spelling+1]=token.text end end
for _,whitespace in ipairs{' ','\n\t','\r\n\v\f '} do
    check(source==compiler.compile(table.concat(spelling,whitespace),'reflow.let',options),'token-preserving whitespace changes must not change generated C')
end
local function rejects(text,pattern)
    local ok,err=pcall(compiler.compile,text,'negative.let',options)
    check(not ok and tostring(err):find(pattern),'expected ' .. pattern .. ', got ' .. tostring(err))
end
rejects('let bad = let k : Executable do return k(1) end let use = do return bad(42) end','Executable')
rejects('let f = let x : Int do return x end let k = let cb : Executable do return cb() end let use = k f','continuation')
rejects('let f = let x : Bool do return x end let k = let cb : Executable do return cb(1) end let use = k f','expected')
rejects('let f = let x : Int do return x end let k = let cb mut : Executable do return cb(1) end let use = do return k(f) end','mutable continuation')
rejects('let f = let x : Int do return x end let k = let cb : Executable do return cb end let use = k f','returned words')
rejects('let f = let box : Box do return 1 end let use = do let box=open_box(1) let cb=f box return cb() end','persistent owned resource')
rejects('let f = let box : Box do return 1 end let k = let cb : Executable do let box=open_box(1) return cb(box) end let use=k f','tail invocation borrow')
-- One inferred callback contract per source template is an explicit current limit.
rejects('let a=let x:Int do return x end let b=let x:Int do return true end let k=let cb:Executable do return cb(1) end let x=k a let y=k b','return shapes')
local harness=[[
#include <assert.h>
static int events[32], used, live[3];
static void record(int n) { assert(used<32); events[used++]=n; }
int64_t probe_open(int64_t n) { assert(n>0 && n<3 && !live[n]); live[n]=1; record(10+n); return n; }
void probe_close(int64_t n) { assert(n>0 && n<3 && live[n]); live[n]=0; record(100+n); }
int64_t probe_size(int64_t n) { assert(live[n]); record(200+n); return n*10; }
int64_t probe_tick(int64_t n) { record(300+n); return n+10; }
void probe_notify(int64_t n) { record(400+n); }
int main(void) {
  assert(let_answer()==42 && let_curried()==42 && let_curried_body()==42);
  assert(let_local_bump()==42);
  for (int n=-100; n<=100; ++n) {
    assert(let_divide(n,0)==-1); assert(let_divide(n,2)==n/2);
    assert(let_dynamic_capture(n)==n+2 && let_nested(n)==n+2);
  }
  assert(let_loop(1000000)==42); assert(let_recursive(100)==100);
  int64_t x=41; assert(let_bump_once(&x)==0 && x==42);
  assert(let_host_callback(4)==14 && used==1 && events[0]==304); used=0;
  assert(let_notification(4)==0 && used==1 && events[0]==404); used=0;
  assert(let_effectful(84,2)==52 && used==1 && events[0]==342); used=0;
  assert(let_effectful(84,0)==9 && used==1 && events[0]==299); used=0;
  assert(let_tail_resource()==20 && used==5);
  assert(events[0]==11 && events[1]==12 && events[2]==101 && events[3]==202 && events[4]==102); used=0;
  assert(let_normal_resource()==20 && used==5);
  assert(events[0]==11 && events[1]==12 && events[2]==202 && events[3]==102 && events[4]==101);
  assert(!live[1] && !live[2]);
  return 0;
}
]]
local base=os.tmpname(); os.remove(base); local paths={}
local function path(suffix) local p=base .. suffix; paths[#paths+1]=p; return p end
local function run(command) local status=os.execute(command); check(status==0 or status==true,command) end
local ok,err=pcall(function()
    local file=path('.c'); local f=assert(io.open(file,'wb')); f:write(source,harness); f:close()
    for _,opt in ipairs{'-O0','-O2','-O3'} do
        local exe=path(opt)
        run((os.getenv('CC') or 'cc') .. ' -std=c99 ' .. opt .. ' -fsanitize=undefined -fsanitize-undefined-trap-on-error ' .. string.format('%q',file) .. ' -o ' .. string.format('%q',exe))
        run('sh -c ' .. string.format('%q','ulimit -s 256; exec ' .. string.format('%q',exe)))
    end
end)
for _,p in ipairs(paths) do os.remove(p) end
assert(ok,err)
print(('passed %d continuation/whitespace checks plus native assertions at -O0/-O2/-O3'):format(count))

