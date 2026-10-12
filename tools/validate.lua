-- Revision-6 differential conformance. Test generation is not an execution path.
local root=(arg[0]:match('^(.*)/tools/[^/]+$') or '.')
local abc=root..'/build/abc'
package.path=root..'/gen/?.lua;'..root..'/tools/?.lua;'..package.path
local cache=require('cache')
local manifest=require('opcodes')
local coverage={}
local states=cache.states(); assert(#states==60,'interpreter cache state count changed')
for _,s in ipairs(states) do
  local seen={}
  for depth=0,s.a-1 do local r=assert(cache.register(s,'A',depth)); assert(not seen[r]); seen[r]=true end
  for depth=0,s.b-1 do local r=assert(cache.register(s,'B',depth)); assert(not seen[r]); seen[r]=true end
  for depth=0,s.c-1 do assert(cache.register(s,'C',depth)) end
  for _,stack in ipairs{'A','B','C'} do
    local pushed,spill=cache.push(s,stack); cache.state(pushed.a,pushed.b,pushed.c,pushed.c_registers); cache.pop(s,stack)
    if spill then assert(#cache.spill_steps(s,spill)>=1) end
  end
end
local tmp=os.tmpname(); os.remove(tmp)
assert(os.execute(('mkdir -p %q'):format(tmp))==0)
local function capture(command)
  -- LuaJIT's io.popen():close() is not a reliable child exit-status oracle.
  local p=assert(io.popen(command..' 2>&1; printf "\\n__ABC_EXIT__%d\\n" "$?"','r'))
  local text=p:read('*a'); p:close()
  local output,status=text:match('^(.*)\n__ABC_EXIT__(%d+)\n$')
  assert(status,'missing process status: '..text)
  return output:gsub('%s+$',''),tonumber(status)
end
local function read(path)
  local f=assert(io.open(path,'rb')); local text=f:read('*a'); f:close(); return text
end
local function record_coverage(bytes)
  local function u32(at) local a,b,c,d=bytes:byte(at,at+3); return a+b*256+c*65536+d*16777216 end
  local sections=u32(9); local at=17; local code
  for _=1,sections do local tag,n=u32(at),u32(at+4); at=at+8; if tag==2 then code=bytes:sub(at,at+n-1) end; at=at+n end
  assert(code,'assembled module has no code section')
  local pc=1
  while pc<=#code do
    local core=assert(manifest.ops[code:byte(pc)+1]); local info,name=core,core.name
    if core.kind==manifest.kind.EXT then
      info=assert(manifest.ext_ops[assert(code:byte(pc+1))+1],'unknown EXT selector')
      name=info.name..(core.stack==manifest.stack.A and '_A' or '_B')
    end
    local length=info.len
    if info.layout_name=='SWITCH' then
      local a,b=code:byte(pc+1,pc+2); length=3+4*(a+b*256)
    end
    assert(length>0 and pc+length-1<=#code,'incomplete instruction in coverage walk')
    coverage[name]=true; pc=pc+length
  end
  assert(pc==#code+1,'coverage walk did not end on an instruction boundary')
end
local function assemble(name,text)
  local source=tmp..'/'..name..'.abcasm'; local f=assert(io.open(source,'wb')); assert(f:write(text)); assert(f:close())
  local path=tmp..'/'..name..'.abc'
  local message,status=capture(('%q asm %q -o %q'):format(abc,source,path))
  assert(status==0,name..': '..message)
  record_coverage(read(path)); return path
end
local function write(name,text)
  -- Exchange banks only in already valid new-ISA programs. This is a symmetry
  -- test, not an adapter accepting historical opcode names or meanings.
  local mirrored=text:gsub('%.([AB])',function(bank)return bank=='A' and '.B' or '.A' end)
  return {assemble(name,text),assemble(name..'-mirror',mirrored)}
end
local checks,executions=0,0
local function same(modules,tail,expected,status)
  assert(expected~=nil,'every execution needs an independent oracle')
  status=status or 0
  for _,module in ipairs(modules) do
    for _,mode in ipairs{'interpreted','compiled','lazy','jit=threaded'} do
      local output,actual=capture(('%q run %q %s --%s'):format(abc,module,tail or '',mode))
      assert(actual==status and output==expected,('%s %s: status %d, expected %d\nactual: %s\nexpected: %s'):format(module,mode,actual,status,output,expected))
      executions=executions+1
    end
  end
  checks=checks+1
end
local function other(stack)return stack=='A' and 'B' or 'A' end

-- Selected stack receives the primary operand, including noncommutative B forms.
-- Runtime inputs prevent constant folding; the ordered result vector stays on A.
local binary={'ADD','SUB','MUL','DIVU','DIVS','REMU','REMS','AND','OR','XOR','SHL','SHR','SAR','EQ','NE','LT','LE','LTU','LEU'}
local a={('.function main 2 %d'):format(#binary*2)}
for _,op in ipairs(binary) do for _,dst in ipairs{'A','B'} do
  a[#a+1]=(' CGET.%s 0'):format(dst); a[#a+1]=(' CGET.%s 1'):format(other(dst)); a[#a+1]=(' %s.%s'):format(op,dst)
  if dst=='B' then a[#a+1]=' MOVE.B' end
end end
a[#a+1]=(' RET.A 2 %d'):format(#binary*2); a[#a+1]='.export main'
local arithmetic=write('arithmetic',table.concat(a,'\n')..'\n')
same(arithmetic,'main 18364758544493064720 7','-81985529216486889 -81985529216486889 -81985529216486903 -81985529216486903 -573898704515408272 -573898704515408272 2623536934927580674 2623536934927580674 -11712218459498128 -11712218459498128 2 2 0 0 0 0 -81985529216486889 -81985529216486889 -81985529216486889 -81985529216486889 7952596333999228928 7952596333999228928 143474676128852068 143474676128852068 -640511947003804 -640511947003804 0 0 1 1 1 1 1 1 0 0 0 0')

local floats={'.profile memory','.function floats 2 22 ff '..string.rep('i',22)}
for _,op in ipairs{'FADD','FSUB','FMUL','FDIV','FLT','FLE','FEQ'} do for _,dst in ipairs{'A','B'} do
  floats[#floats+1]=(' CGET.%s 0'):format(dst); floats[#floats+1]=(' CGET.%s 1'):format(other(dst)); floats[#floats+1]=(' %s.%s'):format(op,dst)
  if op=='FADD' or op=='FSUB' or op=='FMUL' or op=='FDIV' then floats[#floats+1]=' F2IS.'..dst end
  if dst=='B' then floats[#floats+1]=' MOVE.B' end
end end
for _,lines in ipairs{{' CGET.A 0',' FNEG.A',' F2IS.A'},{' PUSH.A -7',' I2FS.A',' F2IS.A'},{' PUSH.A 7',' I2FU.A',' F2IU.A'},{' CGET.A 0',' F2IS.A'},{' CGET.A 0',' F2IU.A'}} do for _,line in ipairs(lines) do floats[#floats+1]=line end end
for i,op in ipairs{'FBLT','FBLE','FBEQ'} do
  floats[#floats+1]=(' CGET.A 0\n CGET.B 1\n %s.A FY%d\n PUSH.A 0\n JMP FD%d\nFY%d: PUSH.A 1\nFD%d:'):format(op,i,i,i,i)
end
floats[#floats+1]=' RET.A 2 22\n.export floats'
same(write('floats',table.concat(floats,'\n')..'\n'),'floats 4615063718147915776 4611686018427387904','5 5 1 1 7 7 1 1 0 0 0 0 0 0 -3 -7 7 3 3 0 0 0')
-- Independent truth tables for each fused float predicate. Compare runtime
-- inputs and scalar-folded producers, retaining live values in BOTH banks.
local float_cases={
  {'1.5','2','4609434218613702656','4611686018427387904',{1,1,0}},
  {'2','2','4611686018427387904','4611686018427387904',{0,1,1}},
  {'3.5','2','4615063718147915776','4611686018427387904',{0,0,0}},
  {'nan','2','9221120237041090560','4611686018427387904',{0,0,0}},
  {'2','nan','4611686018427387904','9221120237041090560',{0,0,0}},
  {'-0','0','9223372036854775808','0',{0,1,1}},
  {'0','-0','0','9223372036854775808',{0,1,1}},
  {'-inf','inf','18442240474082181120','9218868437227405312',{1,1,0}},
}
local function float_constant(value,bank)
  if value=='-0' then return ' PUSH.'..bank..' 0\n I2FS.'..bank..'\n FNEG.'..bank..'\n' end
  local numerator,denominator
  if value=='nan' then numerator,denominator=0,0
  elseif value=='inf' then numerator,denominator=1,0
  elseif value=='-inf' then numerator,denominator=-1,0
  elseif value=='1.5' then numerator,denominator=3,2
  elseif value=='3.5' then numerator,denominator=7,2
  else return (' PUSH.%s %s\n I2FS.%s\n'):format(bank,value,bank) end
  return (' PUSH.%s %d\n I2FS.%s\n PUSH.%s %d\n I2FS.%s\n FDIV.%s\n'):format(bank,numerator,bank,other(bank),denominator,other(bank),bank)
end
for operation,op in ipairs{'FBLT','FBLE','FBEQ'} do
  local function program(producers,arguments)
    return ('.profile memory\n.function main %d 3 %s iii\n PUSH.A 111\n PUSH.B 222\n'):format(arguments,arguments==0 and '-' or 'ff')..
      producers..(' %s.A yes\n PUSH.A 0\n JMP done\nyes: PUSH.A 1\ndone: MOVE.B\n RET.A %d 3\n.export main\n'):format(op,arguments)
  end
  local runtime=write('float-branch-'..op,program(' CGET.A 0\n CGET.B 1\n',2))
  for index,case in ipairs(float_cases) do
    local expected=('111 %d 222'):format(case[5][operation])
    same(runtime,'main '..case[3]..' '..case[4],expected)
    local folded=write('float-fold-'..op..'-'..index,program(float_constant(case[1],'A')..float_constant(case[2],'B'),0))
    same(folded,'',expected)
  end
end

local nan=write('float-nan',[=[.profile memory
.function main 2 4 ff iiii
 CGET.A 0
 CGET.B 1
 FEQ.A
 CGET.A 0
 CGET.B 1
 FBLT.A N1
 PUSH.A 0
 JMP D1
N1: PUSH.A 1
D1: CGET.A 0
 CGET.B 1
 FBLE.A N2
 PUSH.A 0
 JMP D2
N2: PUSH.A 1
D2: CGET.A 0
 CGET.B 1
 FBEQ.A N3
 PUSH.A 0
 JMP D3
N3: PUSH.A 1
D3: RET.A 2 4
.export main
]=])
same(nan,'main 9221120237041090560 4611686018427387904','0 0 0 0')
local f2trap=write('float-conversion-trap',[=[.profile memory
.function main 1 1 f i
 CGET.A 0
 F2IS.A
 RET.A 1 1
.export main
]=])
same(f2trap,'main 9221120237041090560','abc: abort at byte 0x1: language abort 3',1)
local float_load=write('float-load',[=[.profile memory
.rodata 000000000000f83f0000000000000040
.function main 0 1 - i
 .loadkind float
 GLD64.A 0
 .loadkind float
 GLD64.B 8
 FADD.A
 F2IS.A
 RET.A 0 1
.export main
]=])
same(float_load,'','3')
local bad_float_source=tmp..'/bad-float-kind.abcasm'; local bff=assert(io.open(bad_float_source,'wb'))
assert(bff:write('.profile memory\n.function main 0 1 - i\n PUSH.A 1\n PUSH.B 2\n FADD.A\n RET.A 0 1\n.export main\n')); assert(bff:close())
local bad_float_error,bad_float_status=capture(('%q asm %q -o %q'):format(abc,bad_float_source,tmp..'/bad-float-kind.abc'))
assert(bad_float_status==1 and bad_float_error:match('invalid at byte 0x4: instruction operand kind mismatch$'),
  'float kind mismatch was not rejected at FADD: '..bad_float_error)

local more={'.function main 0 40'}
local x='18364758544493064720'
for _,op in ipairs{'NEG','NOT','LNOT','ZX32','SX32'} do for _,dst in ipairs{'A','B'} do
  more[#more+1]=(' PUSH.%s %s\n %s.%s'):format(dst,x,op,dst)
  if dst=='B' then more[#more+1]=' MOVE.B' end
end end
for _,op in ipairs{'ADD','SUB','MUL','AND','OR','XOR','SHL','SHR','SAR'} do for _,dst in ipairs{'A','B'} do
  more[#more+1]=(' PUSH.%s %s\n %sI.%s 3'):format(dst,x,op,dst)
  if dst=='B' then more[#more+1]=' MOVE.B' end
end end
more[#more+1]=' PUSH.A 5\n CPUSH.A'
for _,op in ipairs{'ADD','SUB','MUL','XOR'} do for _,dst in ipairs{'A','B'} do
  more[#more+1]=(' PUSH.%s %s\n %sC.%s 0'):format(dst,x,op,dst)
  if dst=='B' then more[#more+1]=' MOVE.B' end
end end
more[#more+1]=' CPOP\n PUSH.A 3\n PUSH.B 5\n POW.A\n PUSH.A 3\n PUSH.B 5\n POWS.A\n PUSH.A 255\n ZX8.A\n PUSH.A 65535\n ZX16.A\n RET.A 0 40\n.export main'
same(write('more',table.concat(more,'\n')..'\n'),'','81985529216486896 81985529216486896 81985529216486895 81985529216486895 -81985529216486895 -81985529216486895 1985229328 1985229328 1985229328 1985229328 -81985529216486893 -81985529216486893 -81985529216486899 -81985529216486899 -245956587649460688 -245956587649460688 0 0 -81985529216486893 -81985529216486893 -81985529216486893 -81985529216486893 -655884233731895168 -655884233731895168 2295594818061633090 2295594818061633090 -10248191152060862 -10248191152060862 -81985529216486891 -81985529216486891 -81985529216486901 -81985529216486901 -409927646082434480 -409927646082434480 -81985529216486891 -81985529216486891 243 243 255 65535')

local context=write('context',[=[.function main 0 8
 PUSH.A 10
 PUSH.A 20
 PUSH.A 30
 CPUSHN.A 3
 CGETR.A 0 3
 CGET.A 2
 CSET.A 1
 CGET.A 1
 CGET.B 0
 MOVE.B
 CPOP
 CPOP
 CPOP
 PUSH.B 40
 COPY.B
 COPY.A
 DROP.B
 MOVE.B
 PUSH.A 7
 DUP.A
 DROP.A
 RET.A 0 8
.export main
]=])
same(context,'','10 20 30 30 10 40 40 7')
local cold=write('cold-forms',[=[.function main 0 3
 PUSH.A 10
 CPUSH.A
 PUSH.B 20
 CPUSH.B
 PUSH.A 30
 CPUSH.A
 PUSH.B 7
 DUP.B
 DROP.B
 DROP.B
 CGET.B 2
 DROP.B
 CGETR.B 0 2
 DROP.B
 DROP.B
 PUSH.A 31
 CSET.A 0
 PUSH.B 21
 CSET.B 1
 PUSH.B 32
 CSET.B 0
 CGET.A 2
 CGET.A 1
 CGET.A 0
 CPOP
 CPOP
 CPOP
 RET.A 0 3
.export main
]=])
same(cold,'','10 21 32')

-- Fixed and runtime-dependent conditions preserve the old independent truth vectors.
local function branch_suite(name,arguments,dynamic)
  local lines,n={},0
  local function branch(setup,instruction)
    n=n+1; lines[#lines+1]=setup
    lines[#lines+1]=(' %s Y%d\n PUSH.A 0\n JMP D%d\nY%d: PUSH.A 1\nD%d:'):format(instruction,n,n,n,n)
  end
  for _,op in ipairs{'BEQ','BNE','BLT','BLE','BLTU','BLEU'} do
    if dynamic then branch(' CGET.A 0\n CGET.B 1',op..'.A')
    else branch(' PUSH.A 2\n PUSH.B 3',op..'.A'); branch(' PUSH.A 3\n PUSH.B 2',op..'.A') end
  end
  for _,stack in ipairs{'A','B'} do for _,op in ipairs{'JZ','JNZ'} do
    if dynamic then branch(' CGET.'..stack..(stack=='A' and ' 0' or ' 1'),op..'.'..stack)
    else for _,value in ipairs{0,4} do branch((' PUSH.%s %d'):format(stack,value),op..'.'..stack) end end
  end end
  for _,op in ipairs{'BEQI','BNEI','BLTI','BLEI','BGTI','BGEI','BLTUI','BLEUI','BGTUI','BGEUI'} do
    if dynamic then branch(' CGET.A 0',op..'.A 3')
    else branch(' PUSH.A 2',op..'.A 3'); branch(' PUSH.A 4',op..'.A 3') end
  end
  table.insert(lines,1,('.function main %d %d'):format(arguments,n))
  lines[#lines+1]=(' RET.A %d %d\n.export main'):format(arguments,n)
  return write(name,table.concat(lines,'\n')..'\n')
end
same(branch_suite('branches',0,false),'','0 0 1 1 1 0 1 0 1 0 1 0 1 0 0 1 1 0 0 1 0 0 1 1 1 0 1 0 0 1 0 1 1 0 1 0 0 1 0 1')
local dynamic_branches=branch_suite('runtime-branches',2,true)
same(dynamic_branches,'main 2 3','0 1 1 1 1 1 0 1 0 1 0 1 1 1 0 0 1 1 0 0')
same(dynamic_branches,'main 4 2','0 1 0 0 0 0 0 1 0 1 0 1 0 0 1 1 0 0 1 1')
local switch=write('switch',[=[.function choose 1 1
 CGET.A 0
 SWITCH.A S0 S1 S2
 PUSH.A 9
 JMP32 SD
S0: PUSH.A 10
 JMP32 SD
S1: PUSH.A 11
 JMP32 SD
S2: PUSH.A 12
SD: RET.A 1 1
.export choose
.function folded 0 1
 PUSH.A 1
 SWITCH.A F0 F1
 PUSH.A 19
 JMP32 FD
F0: PUSH.A 20
 JMP32 FD
F1: PUSH.A 21
FD: RET.A 0 1
.export folded
]=])
same(switch,'choose 0','10'); same(switch,'choose 2','12'); same(switch,'choose 5','9'); same(switch,'folded','21')

local memory=write('memory',[=[.profile memory
.datazero 64
.function main 0 14
 CALLOC 64
 PUSH.A 255
 FST8.A 64
 FLD8.A 64
 PUSH.B 65535
 FST16.B 62
 FLD16.A 62
 PUSH.A 4294967295
 FST32.A 56
 FLD32.A 56
 FLD32S.A 56
 PUSH.B 123456789
 FST64.B 48
 FLD64.A 48
 FADDR.A 40
 PUSH.B 254
 ST8.A 0
 FADDR.A 40
 LD8.A 0
 FADDR.A 38
 PUSH.B 4660
 ST16.A 0
 FADDR.B 38
 LD16.B 0
 MOVE.B
 FADDR.A 32
 PUSH.B 4294967295
 ST32.A 0
 FADDR.A 32
 LD32S.A 0
 FADDR.A 24
 PUSH.B 1234605616436508552
 ST64.A 0
 FADDR.A 24
 LD64.A 0
 FADDR.A 40
 PUSH.B 1
 LDX8.A
 FADDR.A 40
 PUSH.B 2
 IDX.A 1
 LD8.A 0
 FADDR.A 16
 FADDR.B 24
 MEMCPY.A 8
 FADDR.A 16
 LD64.A 0
 PUSH.A 171
 GST8.A 0
 GLD8.A 0
 PUSH.A 65518
 GST16.A 2
 GLD16.A 2
 FLD8.B 64
 DROP.B
 FLD16.B 62
 DROP.B
 FLD32.B 56
 DROP.B
 FLD32S.B 56
 DROP.B
 FLD64.B 48
 DROP.B
 PUSH.B 1
 FST8.B 64
 PUSH.A 2
 FST16.A 62
 PUSH.B 3
 FST32.B 56
 PUSH.A 4
 FST64.A 48
 PUSH.A 4294967295
 GST32.A 4
 GLD32.A 4
 DROP.A
 GLD32S.A 4
 DROP.A
 PUSH.A 1234605616436508552
 GST64.A 8
 GLD64.A 8
 DROP.A
 GADDR.B 0
 DROP.B
 FADDR.A 64
 LD16.A 0
 DROP.A
 FADDR.A 64
 LD32.A 0
 DROP.A
 FADDR.B 64
 LD8.B 0
 DROP.B
 FADDR.B 64
 LD16.B 0
 DROP.B
 FADDR.B 64
 LD32.B 0
 DROP.B
 FADDR.B 64
 LD32S.B 0
 DROP.B
 FADDR.B 64
 LD64.B 0
 DROP.B
 FADDR.A 64
 PUSH.B 0
 LDX16.A
 DROP.A
 FADDR.A 64
 PUSH.B 0
 LDX32.A
 DROP.A
 FADDR.A 64
 PUSH.B 0
 LDX32S.A
 DROP.A
 FADDR.A 64
 PUSH.B 0
 LDX64.A
 DROP.A
 CFREE 64
 RET.A 0 14
.export main
]=])
same(memory,'','255 65535 4294967295 -1 123456789 254 4660 -1 1234605616436508552 0 52 1234605616436508552 171 65518')
local errors=write('errors',[=[.function divzero 1 1
 CGET.A 0
 PUSH.B 0
 DIVU.A
 RET.A 1 1
.function powsneg 1 1
 PUSH.A 2
 CGET.B 0
 POWS.A
 RET.A 1 1
.function chku8 1 1
 CGET.A 0
 CHKU8.A
 RET.A 1 1
.function explicit 0 0
 ABORT 9
.function chku16 1 1
 CGET.A 0
 CHKU16.A
 RET.A 1 1
.function chku32 1 1
 CGET.A 0
 CHKU32.A
 RET.A 1 1
.function chki32 1 1
 CGET.A 0
 CHKI32.A
 RET.A 1 1
.function chknn 1 1
 CGET.A 0
 CHKNN.A
 RET.A 1 1
.export divzero
.export powsneg
.export chku8
.export explicit
.export chku16
.export chku32
.export chki32
.export chknn
]=])
for _,case in ipairs{
 {'divzero 1',0x3,1},{'powsneg -1',0xa,4},{'chku8 256',0xf,3},{'explicit',0x13,9},
 {'chku16 65536',0x16,3},{'chku32 4294967296',0x1b,3},{'chki32 2147483648',0x20,3},{'chknn -1',0x25,3},
} do same(errors,case[1],('abc: abort at byte 0x%x: language abort %d'):format(case[2],case[3]),1) end
same(errors,'chku16 65535','65535'); same(errors,'chku32 4294967295','4294967295')
same(errors,'chki32 -2147483648','-2147483648'); same(errors,'chknn 0','0')

local overflow=write('overflow',[=[.function main 0 1
 PUSH.A 1
 PUSH.A 2
 DROP.A
 RET.A 0 1
.export main
]=])
local virtual_limit=write('virtual-limit',[=[.function main 0 1
 CALL.A wide 0
 RET.A 0 1
.function wide 0 1
 PUSH.A 1
 PUSH.A 2
 DROP.A
 RET.A 0 1
.export main
]=])
local tail_limit=write('tail-limit',[=[.function main 0 1
 TCALL.A wide 0 0
.function wide 0 1
 PUSH.A 1
 PUSH.A 2
 DROP.A
 RET.A 0 1
.export main
]=])
for _,module in ipairs{overflow,virtual_limit,tail_limit} do same(module,'--stack=1','abc: stack-limit at byte 0x0: stack limit reached',1) end
local recursive_limit=write('recursive-limit',[=[.function main 0 0
 CALL.A recurse 0
 RET.A 0 0
.function recurse 0 0
 CALL.A recurse 0
 RET.A 0 0
.export main
]=])
same(recursive_limit,'--stack=2','abc: stack-limit at byte 0x9: stack limit reached',1)
local mutual=write('mutual-recursion',[=[.function main 0 1
 PUSH.A 11
 CALL.A even 1
 RET.A 0 1
.function even 1 1
 CGET.A 0
 JNZ.A even_step
 PUSH.A 1
 RET.A 1 1
even_step:
 CGET.A 0
 SUBI.A 1
 CALL.A odd 1
 ADDI.A 0
 RET.A 1 1
.function odd 1 1
 CGET.A 0
 JNZ.A odd_step
 PUSH.A 0
 RET.A 1 1
odd_step:
 CGET.A 0
 SUBI.A 1
 CALL.A even 1
 ADDI.A 0
 RET.A 1 1
.export main
]=])
same(mutual,'','0')
local real_b=write('real-b',[=[.function main 0 1
 PUSH.B 100
 PUSH.A 7
 CALL.A wide 1
 ADD.A
 RET.A 0 1
.function wide 1 1
 CGET.A 0
 PUSH.B 3
 ADD.A
]=]..string.rep(' PUSH.A 0\n DROP.A\n',20)..' RET.A 1 1\n.export main\n')
same(real_b,'','110')
local function indirect_limit(name,transfer)
  return write(name,[=[.profile callables
.datazero 8
.codeaddr 0 wide
.signature sig 1 1 a i
.function main 0 1
 GADDR.A 0
 .loadkind addr
 GLD64.B 0
]=]..transfer..[=[
.function wide 1 1 a i
 PUSH.A 1
 PUSH.A 2
 PUSH.A 3
 PUSH.A 4
 DROP.A
 DROP.A
 DROP.A
 RET.A 1 1
.export main
]=])
end
-- Two five-byte address producers precede each call; no orientation-repair MOVE.
same(indirect_limit('indirect-limit',' CALLI.A 1 sig\n RET.A 0 1\n'),'--stack=3','abc: stack-limit at byte 0xa: stack limit reached',1)
same(indirect_limit('indirect-tail-limit',' TCALLI.A 0 1 sig\n'),'--stack=3','abc: stack-limit at byte 0xa: stack limit reached',1)
local indirect_b=write('indirect-b',[=[.profile callables
.datazero 8
.codeaddr 0 target
.signature sig 1 1 a i
.function main 0 1
 GADDR.B 0
 .loadkind addr
 GLD64.A 0
 CALLI.B 1 sig
 RET.B 0 1
.function target 1 1 a i
 PUSH.A 77
 RET.A 1 1
.export main
]=])
same(indirect_b,'','77')
local version_cap=write('version-cap',[=[.function main 4 1
 CGET.A 0
 JZ.A z0
 PUSH.A 1
 JMP d0
z0: PUSH.A 0
d0: CGET.A 1
 JZ.A z1
 PUSH.A 1
 JMP d1
z1: PUSH.A 0
d1: CGET.A 2
 JZ.A z2
 PUSH.A 1
 JMP d2
z2: PUSH.A 0
d2: CGET.A 3
 JZ.A z3
 PUSH.A 1
 JMP d3
z3: PUSH.A 0
d3: MOVE.A
 ADD.A
 MOVE.A
 ADD.A
 MOVE.A
 ADD.A
 RET.A 4 1
.export main
]=])
same(version_cap,'main 0 0 0 0','0'); same(version_cap,'main 1 1 1 1','4'); same(version_cap,'main 1 0 1 0','2')
local obsolete,status=capture(('%q run %q --budget=1'):format(abc,version_cap[1]))
assert(status~=0 and obsolete=='abc: unknown option: --budget=1','obsolete budget option was accepted')
local halt=write('halt','.function main 0 1\n PUSH.A 99\n HALT.A\n.export main\n')
same(halt,'','99')
local direct_tail=write('direct-tail',[=[.function main 0 1
 PUSH.A 40
 PUSH.A 2
 CALL.A adapter 2
 RET.A 0 1
.function adapter 2 1
 CGET.A 0
 CGET.A 1
 TCALL.A add 2 2
.function add 2 1
 CGET.A 0
 CGET.B 1
 ADD.A
 RET.A 2 1
.export main
]=])
same(direct_tail,'','42')
local virtual_calls=write('virtual-calls',[=[.function main 0 1
 PUSH.A 40
 PUSH.A 2
 CALL.A outer 2
 RET.A 0 1
.function outer 2 1
 CGET.B 0
 CGET.B 1
 CALL.B add 2
 RET.B 2 1
.function add 2 1
 CGET.A 0
 CGET.B 1
 ADD.A
 RET.A 2 1
.export main
]=])
same(virtual_calls,'','42')
local large_frame=write('large-frame','.profile memory\n.function main 0 0\n CALLOC 65535\n CFREE 65535\n RET.A 0 0\n.export main\n')
same(large_frame,'--stack=9000','')

-- Widen facts on backedges without losing cache placement or live aliases.
-- C0 is an invariant constant, C1 is the runtime counter. The pressure case
-- exceeds eight native value registers; spills must still preserve every cell.
for _,pressure in ipairs{false,true} do for _,conditional in ipairs{false,true} do
  local prefix=pressure and 'PUSH.A 11\nPUSH.A 12\nPUSH.A 13\nPUSH.A 14\n' or ''
  local other_prefix=pressure and 'PUSH.B 21\nPUSH.B 22\n' or ''
  local drain=pressure and 'MOVE.B\nMOVE.B\nMOVE.B' or 'MOVE.B'
  local backedge=conditional and 'CGET.A 1\nBNEI.A 0 loop' or 'JMP loop'
  local name='backedge-'..tostring(pressure)..'-'..tostring(conditional)
  local modules=write(name,('.function main 1 %d\n'):format(pressure and 11 or 5)..
    'PUSH.A 7\nCPUSH.A\n'..prefix..'PUSH.A 40\nDUP.A\n'..other_prefix..[=[PUSH.B 100
loop:
CGET.A 1
BEQI.A 0 done
ADDI.A 1
SUBI.B 3
CGET.A 1
SUBI.A 1
CSET.A 1
]=]..backedge..'\ndone:\n'..drain..'\nCGET.A 0\nCGET.A 1\nRET.A 2 '..(pressure and 11 or 5)..'\n.export main\n')
  for _,count in ipairs{0,1,6,2000} do
    local expected=(pressure and '11 12 13 14 ' or '')..('40 %d %d '):format(40+count,100-3*count)..(pressure and '22 21 ' or '')..'7 0'
    same(modules,'main '..count,expected)
  end
end end

-- Keep the shipped integer/memory examples executable, not just illustrative.
local example_divmod=write('example-divmod',read(root..'/examples/divmod.abcasm'))
same(example_divmod,'','3 2')
same(example_divmod,'divmod 100 7','14 2')
local example_memory=write('example-memory',read(root..'/examples/memory.abcasm'))
same(example_memory,'','99 1 72')
same(example_memory,'head','72')
same(example_memory,'frame_limit --stack=9000','')

-- Foreign execution is checked by validate-api with real bound functions. Here
-- record both selected encodings, without claiming this CLI executes the externs.
write('foreign-coverage',read(root..'/examples/foreign.abcasm'))
local missing,total={},0
local function require_opcode(name)
  total=total+1; if not coverage[name] then missing[#missing+1]=name end
end
for _,op in ipairs(manifest.ops) do if op.kind~=manifest.kind.EXT then require_opcode(op.name) end end
for _,op in ipairs(manifest.ext_ops) do for _,bank in ipairs{'A','B'} do require_opcode(op.name..'_'..bank) end end
assert(total==282,'revision-6 selected core/EXT coverage inventory changed')
assert(#missing==0,'validation misses public opcode forms: '..table.concat(missing,', '))
print(('validated %d oracle cases / %d mirrored four-mode executions; assembled all %d public core/EXT forms'):format(checks,executions,total))
-- Source integration lives in validate_slet_frontend.lua and uses only the
-- production compiler. Historical bootstrap sources/tests are archived.
assert(os.execute(('rm -rf %q'):format(tmp))==0)
