-- LuaJIT algorithm baseline: Lua numbers do not distinguish ABC u16/u32 tags.
local bit=require('bit')
local name,n,trials=arg[1],assert(tonumber(arg[2])),tonumber(arg[3]) or 9
assert(trials>=3 and trials%2==1)
local function run()
  if name=='f64-carried' then
    local x=1
    for _=1,n do x=x+0.5 end
    return x*2
  end
  local x=12345
  for i=0,n-1 do x=bit.band(bit.bxor(x,bit.rshift(x,7))*5+i,65535) end
  return x
end
local result=run();local times={}
for i=1,trials do local t=os.clock();result=run();times[i]=os.clock()-t end
table.sort(times)
io.write(('%.0f %.9f\n'):format(result,times[math.floor(trials/2)+1]))
