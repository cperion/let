package.path='./?.lua;./?/init.lua;' .. package.path
local compiler,V=require('let'),require('let.vocab')
local count=0
local function check(v,message) assert(v,message); count=count+1 end
local options={resources={Box={destroy='drop_box'}},hosts={
    tick={symbol='tick',result='Int',stages={{constraint='Int'}}},
    open_box={symbol='open_box',result='Box',stages={{constraint='Int'}}}
}}
local text=[[
let classify = let n:Int do
    if n < 0 do return -1
    else if n == 0 do return 0
    else if n == 1 do return 1
    else return 2 end
end
let nested = let a:Bool let b:Bool do
    if a do if b do return 1 else return 2 end else return 3 end
end
let choose = let n:Int do
    switch n do case -1 return 10 case 0,1 return 20 case 0x2 return 30 else return 40 end
end
let folded = do return choose(1) end
let boolean = let b:Bool do switch b do case true return 1 case false return 0 end end
let no_default = let n:Int do
    let x mut=7 switch n do case 1 x=9 case 2 x=10 end return x
end
let once = let n:Int do switch tick(n) do case 0 return 10 case 1,2 return 20 else return 30 end end
let condition_order = let n:Int do
    if tick(n)==0 do return 10 else if tick(n+1)==2 do return 20 else return 30 end
end
let loop = let n:Int do
    let i mut=0 let sum mut=0
    while i<n do switch i % 3 do case 0 sum=sum+1 case 1 sum=sum+2 else sum=sum+3 end i=i+1 end
    return sum
end
let scoped = let n:Int do
    let x=42 switch n do case 0 let x=1 case 1 let x=2 else let x=3 end return x
end
let recursive = let n:Int do switch n do case 0 return 42 else return recursive(n-1) end end
let cleanup = let n:Int do
    let outer=open_box(1)
    switch n do case 0 let inner=open_box(2) return 42 else let inner=open_box(3) end
    return 7
end
let moved = let n:Int do
    let box=open_box(1)
    switch n do case 0 let consumed=move box else let consumed=move box end
end
let minimum = let n:Int do switch n do case -9223372036854775808 return 1 else return 0 end end
]]
local source,_,module=compiler.compile(text,'control.let',options)
for _,fn in ipairs(module.functions) do if fn.c_name=='let_folded' then
    local body=fn.body.statements
    check(#body==1 and V.Residual.ReturnStmt:isclassof(body[1]) and body[1].value:known()==20,'known switch must disappear before C optimization')
end end
local tokens=require('let.lexer').new(text,'control.let'):scan(); local spelling={}
for _,token in ipairs(tokens) do if token.tag~='eof' then spelling[#spelling+1]=token.text end end
for _,space in ipairs{' ','\n\t '} do check(source==compiler.compile(table.concat(spelling,space),'reflow.let',options),'control parsing must ignore whitespace') end
local function rejects(text,pattern)
    local ok,err=pcall(compiler.compile,text,'bad-control.let',options)
    check(not ok and tostring(err):find(pattern),'expected ' .. pattern .. ', got ' .. tostring(err))
end
rejects('let f=do switch 1 do case 1 return case 0x1 return end end','duplicate case')
rejects('let f=do switch 0 do case 0 return case -0 return end end','duplicate case')
rejects('let f=do switch true do case true return case true return end end','duplicate case')
rejects('let f=do switch 0 do case 1 return case false return end end','same type')
rejects('let f=do switch true do case 1 return end end','expected Int')
rejects('let f=do switch 0 do else return end end','at least one case')
rejects('let f=do switch 0 do case tick(1) return end end','expected integer')
rejects('let f=do switch 0 do case 9223372036854775808 return end end','out of Int range')
rejects('let f=let n:Int do switch n do case 0 let x=1 end return x end','unknown name x')
rejects('let f=do if true do return end else do return end end','expected')
rejects('let f=let n:Int do let b=open_box(1) switch n do case 0 let c=move b end let c=move b end','use after move')
local harness=[[
#include <assert.h>
static int ticks,log_[8],used;
int64_t tick(int64_t n) { ++ticks; return n; }
int64_t open_box(int64_t n) { return n; }
void drop_box(int64_t n) { log_[used++]=n; }
int main(void) {
  for (int n=-5;n<=5;++n) {
    assert(let_classify(n)==(n<0?-1:n==0?0:n==1?1:2));
    assert(let_choose(n)==(n==-1?10:n==0||n==1?20:n==2?30:40));
    assert(let_no_default(n)==(n==1?9:n==2?10:7));
    assert(let_scoped(n)==42);
    ticks=0; assert(let_once(n)==(n==0?10:n==1||n==2?20:30) && ticks==1);
    ticks=0; assert(let_condition_order(n)==(n==0?10:n==1?20:30) && ticks==(n==0?1:2));
  }
  assert(let_nested(true,true)==1 && let_nested(true,false)==2 && let_nested(false,true)==3);
  assert(let_boolean(true)==1 && let_boolean(false)==0);
  assert(let_folded()==20 && let_loop(100)==199 && let_recursive(1000000)==42);
  assert(let_minimum(INT64_MIN)==1 && let_minimum(INT64_MAX)==0);
  used=0; assert(let_cleanup(0)==42 && used==2 && log_[0]==2 && log_[1]==1);
  used=0; assert(let_cleanup(1)==7 && used==2 && log_[0]==3 && log_[1]==1);
  used=0; let_moved(0); assert(used==1 && log_[0]==1);
  used=0; let_moved(1); assert(used==1 && log_[0]==1);
  return 0;
}
]]
local base=os.tmpname(); os.remove(base); local paths={}
local function path(suffix) local p=base .. suffix; paths[#paths+1]=p; return p end
local function run(cmd) local status=os.execute(cmd); check(status==0 or status==true,cmd) end
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
print(('passed %d structured-control checks plus native assertions at -O0/-O2/-O3'):format(count))

