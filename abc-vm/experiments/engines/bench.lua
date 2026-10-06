local bit=require('bit')
local name,N,trials=arg[1],tonumber(arg[2]),tonumber(arg[3]) or 9
local band,bxor,lshift,rshift=bit.band,bit.bxor,bit.lshift,bit.rshift
local function next32(s) s=bxor(s,lshift(s,13)); s=bxor(s,rshift(s,17)); return bxor(s,lshift(s,5)) end
local function step32(x) if band(x,1)~=0 then return bit.tobit(x*3+1) else return rshift(x,1) end end
local function loop(n,acc) if n==0 then return acc end return loop(n-1,bxor(next32(acc),n)) end
local function skip(n,s) if n==0 then return s end return skip(n-1,next32(s)) end
local function branch(n,x,acc) if n==0 then return acc end local y=step32(x); return branch(n-1,y,bit.tobit(acc+band(y,255))) end
local function fib(n) if n<2 then return n end return fib(n-1)+fib(n-2) end
local function run()
  if name=='loop' then return loop(N,0) elseif name=='skip' then return skip(N,bit.tobit(2463534242)) elseif name=='branch' then return branch(N,0x12345678,0) else return fib(N) end
end
local result=run(); local times={}
for i=1,trials do local t=os.clock(); result=run(); times[i]=os.clock()-t end
table.sort(times)
if result<0 then result=result+4294967296 end
io.write(string.format('%.0f %.9f\n',result,times[math.floor(trials/2)+1]))

