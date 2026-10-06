#!/usr/bin/env luajit
local ffi=require('ffi')
ffi.cdef[[typedef long time_t; struct timespec { time_t tv_sec; long tv_nsec; }; int clock_gettime(int, struct timespec *);]]
local function now() local t=ffi.new('struct timespec[1]');assert(ffi.C.clock_gettime(4,t)==0);return tonumber(t[0].tv_sec)+tonumber(t[0].tv_nsec)*1e-9 end
local here=(arg[0]:match('^(.*)/') or '.');local top=here..'/../../..'
local abc=top..'/build/abc';local runlet=here..'/runlet';local native=here..'/native';local luajit=os.getenv('LUAJIT') or 'luajit';local cc=os.getenv('CC') or 'clang'
local trials=tonumber(os.getenv('TRIALS') or '9');if trials<3 or trials%2==0 then error('TRIALS must be odd and >=3',0) end
local sf=assert(io.open('/proc/self/status'));local status=sf:read('*a');sf:close();local core=status:match('Cpus_allowed_list:%s*(%d+)')
local function quote(s)s=tostring(s);return "'"..s:gsub("'","'\\''").."'" end
local function command(args,pin)local t={};if pin and core then t={'taskset','-c',core} end;for _,v in ipairs(args)do t[#t+1]=v end;for i,v in ipairs(t)do t[i]=quote(v)end;return table.concat(t,' ') end
local function run(args,check,pin)if check==nil then check=true end;local p=assert(io.popen(command(args,pin~=false).." 2>&1; printf '\n__ABC_STATUS__%d\n' $?"));local text=p:read('*a');p:close();local body,code=text:match('^(.*)\n__ABC_STATUS__(%d+)\n$');if not code then error('could not read command status: '..text,0)end;code=tonumber(code);if check and code~=0 then error(command(args,false)..': '..body,0)end;return body,code end
local function median(v)table.sort(v);return v[math.floor(#v/2)+1]end
local function fib(n)local a,b=0,1;for _=1,n do a,b=b,a+b end;return a end
local benches={
 {name='loop',n=5000000,units=function(n)return n end,width=32,src=[[let loop(n: u32, acc: u32): u32 = do
    if n == 0 then return acc end
    let x = acc ~ (acc << 13)
    let y = x ~ (x >> 17)
    return loop(n - 1, (y ~ (y << 5)) ~ n)
end
let main(): u32 = loop({N}, 0)
]]},
 {name='skip',n=3000000,units=function(n)return n end,width=32,src=[[let loop(n: u32, s: u32): u32 = do
    if n == 0 then return s end
    let x = s ~ (s << 13)
    let y = x ~ (x >> 17)
    return loop(n - 1, y ~ (y << 5))
end
let main(): u32 = loop({N}, 2463534242)
 ]]},
 {name='branch',n=3000000,units=function(n)return n end,width=32,src=[[let step(x: u32): u32 = if (x & 1) == 0 then x >> 1 else x * 3 + 1
let loop(n: u32, x: u32, acc: u32): u32 = do
    if n == 0 then return acc end
    let y = step(x)
    return loop(n - 1, y, acc + (y & 255))
end
let main(): u32 = loop({N}, 305419896, 0)
]]},
 {name='sum2',n=3000000,units=function(n)return n end,width=32,src=[[let loop(n: u32, a: u32, b: u32): u32 = do
    if n == 0 then return a ~ b end
    let ax = a ~ (a << 13)
    let ay = ax ~ (ax >> 17)
    let bx = b ~ (b << 13)
    let by = bx ~ (bx >> 17)
    return loop(n - 1, ay ~ (ay << 5), by ~ (by << 5))
end
let main(): u32 = loop({N}, 305419896, 2654435769)
]]},
 {name='mul',n=3000000,units=function(n)return n end,width=32,src=[[let loop(n: u32, x: u32, acc: u32): u32 = do
    if n == 0 then return acc end
    let next = x * 33 + 17
    return loop(n - 1, next, acc + (next & 65535))
end
let main(): u32 = loop({N}, 305419896, 0)
]]},
 {name='divide',n=1000000,units=function(n)return n end,width=32,src=[[let loop(n: u32, x: u32, acc: u32): u32 = do
    if n == 0 then return acc end
    let q = x / 3
    let r = x - q * 3
    return loop(n - 1, q + 2654435769, acc + r)
end
let main(): u32 = loop({N}, 1985229328, 0)
]]},
 {name='mix',n=2000000,units=function(n)return n end,width=32,src=[[let loop(n: u32, x: u32, acc: u32): u32 = do
    if n == 0 then return acc end
    let y = (x ~ (x >> 7)) * 5 + 1
    return loop(n - 1, y, acc + (y & 1023))
end
let main(): u32 = loop({N}, 305419896, 0)
]] },
 {name='fib',n=30,units=function(n)return 2*fib(n+1)-1 end,width=32,src=[[let fib(n: u32): u32 = if n < 2 then n else fib(n - 1) + fib(n - 2)
let main(): u32 = fib({N})
]]}
}
local function write_file(path,text)local f=assert(io.open(path,'wb'));assert(f:write(text));assert(f:close())end
local function compile_slet(b,n,out)local src=here..'/.bench-'..b.name..'.slet';out=out or here..'/'..b.name..'.abc';write_file(src,(b.src:gsub('{N}',tostring(n))));run({abc,'compile',src,'-o',out});return out end
local function frontend_cost(b)local v={};for i=1,7 do local out=here..'/.'..b.name..'-'..i..'.abc';local t=now();compile_slet(b,b.n,out);v[i]=now()-t;os.remove(out)end;return median(v)end
local function fields(text)local t={};for x in text:gmatch('%S+')do t[#t+1]=x end;return t end
local function abc_result(mode,module)local f=fields(run({runlet,mode,module,tostring(trials)}));return{result=tonumber(f[1]),seconds=tonumber(f[2]),read=tonumber(f[3]),prepare=tonumber(f[4]),code=tonumber(f[5]),first=tonumber(f[6])}end
local function simple(args)local f=fields(run(args));return tonumber(f[1]),tonumber(f[2])end
local function file_size(path)local f=assert(io.open(path,'rb'));local size=assert(f:seek('end'));f:close();return size end
local function compile_aot(b,module)
  local source=here..'/.'..b.name..'-aot.c';local binary=here..'/.'..b.name..'-aot'
  local started=now();run({abc,'c',module,'-o',source});local emit=now()-started
  started=now();run({cc,'-O3','-march=native','-std=c11','-Wall','-Wextra','-Wpedantic','-Werror','-Wno-unused-function',source,here..'/aot_runner.c','-o',binary});local compile=now()-started
  return binary,emit,compile,file_size(binary)
end
print(('host core=%s trials=%d'):format(core or 'unbound',trials));print((run({cc,'--version'},true,false):match('[^\n]+')));print((run({luajit,'-v'},true,false):gsub('%s+$','')))
local rows={}
for _,b in ipairs(benches)do local module=compile_slet(b,b.n);local front=frontend_cost(b);local units=b.units(b.n);local ai=abc_result('interpreted',module);local ac=abc_result('compiled',module);local al=abc_result('lazy',module);local aot,aot_emit,aot_compile,aot_bytes=compile_aot(b,module);local cr,crt=simple({aot,trials});local cj,ct=simple({native,b.name,b.n,trials});local lo,lot=simple({luajit,'-joff',here..'/bench.lua',b.name,b.n,trials});local lj,ljt=simple({luajit,here..'/bench.lua',b.name,b.n,trials});local modulus=2^b.width;local expected=cj%modulus;for _,x in ipairs{{'ABC-I',ai.result},{'ABC-E',ac.result},{'ABC-L',al.result},{'ABC-C',cr},{'LuaJIT-off',lo},{'LuaJIT',lj}}do if x[2]%modulus~=expected then error(('%s %s result %.0f != %.0f'):format(b.name,x[1],x[2]%modulus,expected),0)end end;local ns={AI=ai.seconds/units*1e9,AC=ac.seconds/units*1e9,AL=al.seconds/units*1e9,CA=crt/units*1e9,LO=lot/units*1e9,LJ=ljt/units*1e9,C=ct/units*1e9};rows[#rows+1]={b=b,front=front,ai=ai,ac=ac,al=al,ns=ns,aot_emit=aot_emit,aot_compile=aot_compile,aot_bytes=aot_bytes}end
print('\nsteady state: median ns per iteration/call (lower is better)');print(('%-8s%10s%10s%10s%10s%10s%10s%10s'):format('bench','ABC-I','ABC-E','ABC-L','ABC-C','LJ-off','LuaJIT','native C'))
for _,r in ipairs(rows)do local n=r.ns;print(('%-8s%10.3f%10.3f%10.3f%10.3f%10.3f%10.3f%10.3f'):format(r.b.name,n.AI,n.AC,n.AL,n.CA,n.LO,n.LJ,n.C))end
print('\nratios: runtime / baseline (lower is better), except I/E speedup');print(('%-8s%10s%10s%10s%10s%10s%10s'):format('bench','E/ABC-C','ABC-C/C','E/C','L/E','E/LJ','I/E'))
for _,r in ipairs(rows)do local n=r.ns;print(('%-8s%10.2f%10.2f%10.2f%10.2f%10.2f%10.2f'):format(r.b.name,n.AC/n.CA,n.CA/n.C,n.AC/n.C,n.AL/n.AC,n.AC/n.LJ,n.AI/n.AC))end
print('\nVM fixed costs: median frontend/read/load; lazy first-arrival premium and native image bytes');print(('%-8s%12s%10s%10s%10s%10s%13s%11s'):format('bench','frontend ms','read us','I load','E load','L load','L first us','native B'))
for _,r in ipairs(rows)do local premium=math.max(0,r.al.first-r.al.seconds);print(('%-8s%12.3f%10.2f%10.2f%10.2f%10.2f%13.2f%11d'):format(r.b.name,r.front*1e3,r.ac.read*1e6,r.ai.prepare*1e6,r.ac.prepare*1e6,r.al.prepare*1e6,premium*1e6,r.al.code))end
print('\nportable C pipeline costs: abc c emission, Clang compilation, executable size');print(('%-8s%12s%13s%13s'):format('bench','emit ms','compile ms','binary bytes'))
for _,r in ipairs(rows)do print(('%-8s%12.3f%13.3f%13d'):format(r.b.name,r.aot_emit*1e3,r.aot_compile*1e3,r.aot_bytes))end
print('\nNotes: ABC-C is portable C emitted from semantic residue produced by the shared symbolic executor and compiled separately with Clang -O3 -march=native. Native C is a handwritten baseline. Eager preparation residualizes all load-time-reachable contexts; lazy load publishes activation stubs. Frontend and C-pipeline costs include process launch. Recursive fib units are function calls; other units are loop iterations.')
