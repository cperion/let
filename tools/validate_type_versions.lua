-- Check-driven native versions, on ordinary verified dynamic-profile ABC.
local root=(arg[0]:match('^(.*)/tools/[^/]+$') or '.')
local abc=root..'/build/abc'
local temp=assert(io.popen('mktemp -d /tmp/abc-type-versions.XXXXXX'))
local tmp=assert(temp:read('*l'));assert(temp:close())
local checks=0
local function run(args)
  local words={} for i,x in ipairs(args) do words[i]=string.format('%q',tostring(x)) end
  local p=assert(io.popen(table.concat(words,' ').." 2>&1; printf '\n__STATUS__%d\n' $?"))
  local text=p:read('*a');p:close();local out,status=text:match('^(.*)\n__STATUS__(%d+)\n$')
  assert(status,text);return out,tonumber(status)
end
local function module(name,source)
  local path=tmp..'/'..name;local f=assert(io.open(path..'.abcasm','wb'));assert(f:write(source));assert(f:close())
  local out,status=run{abc,'asm',path..'.abcasm','-o',path..'.abc'};assert(status==0,out);return path..'.abc'
end
local function same(path,args,expected)
  local first,code
  for _,mode in ipairs{'interpreted','compiled','lazy'} do
    local cmd={abc,'run',path,'main'};for _,a in ipairs(args or {}) do cmd[#cmd+1]=a end;cmd[#cmd+1]='--'..mode
    local out,status=run(cmd)
    if not first then first,code=out,status else assert(out==first and status==code,path..' '..mode..': '..out..' != '..first) end
    checks=checks+1
  end
  if expected then assert(code==0 and first==expected..'\n',path..': '..first) end
  return first,code
end
local types={'u8','u16','u32','u64','i32','i64','f64','bool'}
local head='.profile dynamic\n.descriptor primitive D any\n.datazero 64\n'
for i=0,7 do head=head..'.gcroot '..(i*8)..' D\n' end
for i,t in ipairs(types) do head=head..'.descriptor primitive T'..i..' '..t..'\n' end
local ops={'DADD','DSUB','DMUL','DDIV','DREM','DPOW','DSHL','DSHR','DSAR','DAND','DOR','DXOR'}
local function result_type(a,b)
  if a==7 and b==7 then return 7 end
  if a<=4 and b<=4 or (a==5 or a==6) and (b==5 or b==6) then return math.max(a,b) end
  return 4 -- invalid operand pairs must trap before this conversion
end
for _,op in ipairs(ops) do
  for a=1,#types do for b=1,#types do
    local out=result_type(a,b);local result_kind=out==7 and 'f' or 'i'
    local text=head..'.function main 2 1 ii '..result_kind..'\n'
    for depth,t in ipairs{a,b} do
      text=text..' CGET.A '..(depth-1)..'\n'..(t==7 and ' I2FS\n' or '')..' ANY_BOX T'..t..'\n GST64 '..((depth-1)*8)..'\n'
    end
    text=text..' .loadkind any\n GLD64 0\n .loadkind any\n GLD64 8\n '..op..'\n ANY_CAST T'..out..'\n RET 2 1\n.export main\n'
    local path=module(op..'-'..a..'-'..b,text)
    for _,values in ipairs{{0,0},{7,2},{4294967295,1},{'-1',2},{'35184372088832',3},{'-9223372036854775808','-1'},{'-1','-1'},{'-1',64},{2,65}} do same(path,values) end
  end end
end

-- Stack aliases, spills, positive/negative facts, delayed predicates, and CSET.
for _,typ in ipairs{3,5} do for _,delay in ipairs{false,true} do
  local lines={head,'.function main 1 1 i i',' CGET0.A',' ANY_BOX T'..typ,' GST64 0',' PUSH.A 9',' ANY_BOX T5',' GST64 8',' .loadkind any',' GLD64 0'}
  for _=1,20 do lines[#lines+1]=' DUP.A';lines[#lines+1]=' CPUSH.A' end
  local tail={' COPY.AB',' CGET0.A',' ANY_IS T'..typ}
  if delay then tail[#tail+1]=' DUP.A';tail[#tail+1]=' DROP.A' end
  for _,line in ipairs{' JZ.A bad',' MOVE.BA',' ANY_IS T'..typ,' JZ.A bad',' ANY_IS T'..typ,' JZ.A bad',' CGET0.A',' ANY_IS T'..(typ==3 and 5 or 3),' JNZ.A bad',' .loadkind any',' GLD64 8',' CSET.A 0',' CGET0.A',' ANY_IS T3',' JNZ.A bad',' CGET0.A',' ANY_IS T5',' JZ.A bad',' CGET0.A',' ANY_IS T5',' JZ.A bad',' PUSH.A 7',' RET 21 1'} do tail[#tail+1]=line end
  local bad=0
  for _,line in ipairs(tail) do if line:match('%.A bad$') then line=line..bad;bad=bad+1 end;lines[#lines+1]=line end
  for i=0,bad-1 do lines[#lines+1]='bad'..i..':\n ABORT 6' end
  lines[#lines+1]='.export main'
  local path=module('aliases-'..typ..'-'..tostring(delay),table.concat(lines,'\n')..'\n')
  for _,value in ipairs{0,123,'35184372088832'} do same(path,{value},'7') end
end end

-- Eight independent types join repeatedly and force bounded widening.
do
  local lines={head,'.function main 8 1 iiiiiiii i'}
  for i=0,7 do lines[#lines+1]=(' CGET.A %d\n JZ.A signed%d\n PUSH.A 1\n ANY_BOX T3\n JMP store%d\nsigned%d:\n PUSH.A 1\n ANY_BOX T5\nstore%d:\n GST64 %d'):format(i,i,i,i,i,i*8) end
  for i=0,7 do lines[#lines+1]=' .loadkind any\n GLD64 '..(i*8) end
  lines[#lines+1]=' CALL.A classify 8\n RET 8 1\n.export main\n.function classify 8 1 dddddddd i\n PUSH.A 0'
  for i=0,7 do lines[#lines+1]=(' CGET.A %d\n ANY_IS T3\n JZ.A no%d\n PUSH32.B %d\n ADD.A\n JMP join%d\nno%d:\n JMP join%d\njoin%d:'):format(i,i,2^i,i,i,i,i) end
  lines[#lines+1]=' RET 8 1'
  local path=module('pressure',table.concat(lines,'\n')..'\n')
  for _,mask in ipairs{0,1,2,3,15,85,127,128,170,254,255} do
    local args={} for i=0,7 do args[#args+1]=math.floor(mask/2^i)%2 end;same(path,args,tostring(mask))
  end
end

-- Ordinary opaque opcodes, loop backedges, and alternating result types.
for _,typ in ipairs{1,2,3,4,5,6} do for _,alternate in ipairs{false,true} do
  local text=head..('.function main 0 1 - i\n PUSH.A 0\n ANY_BOX T%d\n GST64 0\n .loadkind any\n GLD64 0\n CPUSH.A\n PUSH.A 0\n CPUSH.A\nloop:\n CGET0.A\n PUSH.B 200\n BLTU body\n CGET1.A\n ANY_CAST T4\n RET 2 1\nbody:\n'):format(typ)
  if alternate then
    -- Replace (not reinterpret) the value on alternating iterations.
    local other=typ<=3 and 4 or typ==4 and 3 or typ==5 and 6 or 5
    text=text..(' CGET0.A\n PUSH.B 1\n AND.A\n JZ.A replace\n CGET0.A\n ANY_BOX T%d\n JMP reload\nreplace:\n CGET0.A\n ANY_BOX T%d\nreload:\n GST64 0\n .loadkind any\n GLD64 0\n CSET.A 1\n'):format(typ,other)
  end
  text=text..(' CGET1.A\n PUSH.A 1\n ANY_BOX T%d\n DADD\n CSET.A 1\n CGET0.A\n ADDI.A 1\n CSET.A 0\n JMP loop\n.export main\n'):format(typ)
  same(module('loop-'..typ..'-'..tostring(alternate),text),{},'200')
end end
-- Ordinary SWITCH edges with changing raw types and bounded widening.
do
  local text=head..[=[.function main 0 1 - i
 PUSH.A 0
 ANY_BOX T1
 CPUSH.A
 PUSH.A 0
 CPUSH.A
loop:
 CGET0.A
 PUSH.B 200
 BLTU body
 CGET1.A
 ANY_CAST T4
 RET 2 1
body:
 CGET0.A
 PUSH.B 3
 AND.A
 SWITCH byte short word
 CGET0.A
 ANY_BOX T4
 JMP store
byte:
 CGET0.A
 ANY_BOX T1
 JMP store
short:
 CGET0.A
 ANY_BOX T2
 JMP store
word:
 CGET0.A
 ANY_BOX T3
store:
 GST64 0
 .loadkind any
 GLD64 0
 PUSH.A 1
 ANY_BOX T1
 DADD
 CSET.A 1
 CGET0.A
 ADDI.A 1
 CSET.A 0
 JMP loop
.export main
]=]
  same(module('switch-raw',text),{},'200')
  same(module('unit',head..'.descriptor primitive Z unit\n.function main 0 1 - i\n ANY_BOX Z\n ANY_IS Z\n RET 0 1\n.export main\n'),{},'1')
end

local function optimize(path)
  local optimized=path..'.opt.abc';local out,status=run{abc,'opt',path,'-o',optimized};assert(status==0,out)
  local twice=optimized..'.abc';out,status=run{abc,'opt',optimized,'-o',twice};assert(status==0,out)
  local function bytes(p)local f=assert(io.open(p,'rb'));local b=f:read('*a');f:close();return b end
  assert(bytes(optimized)==bytes(twice),'optimizer did not reach a fixpoint: '..path)
  return optimized
end

-- Exact casts preserve payloads; immediate unsigned boxing needs a range proof.
for _,typ in ipairs{1,2,3,4,5,6} do for _,op in ipairs{'SX32.A','ZX32.A'} do for _,store in ipairs{false,true} do
  local text=head..('.function main 1 1 i i\n CGET0.A\n %s\n ANY_BOX T%d\n'):format(op,typ)
  if store then text=text..' GST64 0\n .loadkind any\n GLD64 0\n' end
  text=text..' ANY_CAST T'..typ..'\n RET 1 1\n.export main\n'
  local path=module('normalization-'..typ..'-'..op..'-'..tostring(store),text)
  local optimized=optimize(path)
  for _,n in ipairs{0,'-1',4294967295,4294967296,1099511627775} do
    local a,sa=same(path,{n});local b,sb=same(optimized,{n});assert(sa==sb)
    if sa==0 then assert(a==b,a..' != '..b) else assert(a:match('language abort %d+')==b:match('language abort %d+'),a..' != '..b) end
  end
end end end

-- Raw specialized values must become encoded cells at real call boundaries.
for _,typ in ipairs{1,2,3,4,5,6} do
  local recursive=head..('.function main 0 1 - i\n PUSH.A 20\n PUSH.A 0\n ANY_BOX T%d\n CALL.A recur 2\n ANY_CAST T4\n RET 0 1\n.function recur 2 1 id d\n CGET0.A\n JZ.A done\n CGET0.A\n SUBI.A 1\n CGET1.A\n PUSH.A 1\n ANY_BOX T%d\n DADD\n CALL.A recur 2\n RET 2 1\ndone:\n CGET1.A\n RET 2 1\n.export main\n'):format(typ,typ)
  local path=module('recursive-'..typ,recursive);same(path,{},'20');same(optimize(path),{},'20')
  for _,form in ipairs{'A','B','tail'} do
    local text=('.profile dynamic\n.descriptor primitive T %s\n.datazero 16\n.codeaddr 8 unbox\n.signature op 2 1 ad i\n.function main 0 1 - i\n GADDR.A 0\n PUSH.A 3\n ANY_BOX T\n PUSH.A 4\n ANY_BOX T\n DADD\n .loadkind addr\n GLD64 8\n MOVE.AB\n'):format(types[typ])
    if form=='tail' then text=text..' TCALLI 0 2 op\n'
    else text=text..' CALLI.'..form..' 2 op\n'..(form=='B' and ' MOVE.BA\n' or '')..' RET 0 1\n' end
    text=text..'.function unbox 2 1 ad i\n CGET1.A\n ANY_CAST T\n RET 2 1\n.export main\n'
    local path=module('indirect-'..typ..'-'..form,text);same(path,{},'7');same(optimize(path),{},'7')
  end
end
assert(os.execute(('rm -rf %q'):format(tmp))==0)
print(('validated %d type-version executions: numeric matrix, exact traps, aliases, replacement, joins, loops and real-call ABI'):format(checks))

