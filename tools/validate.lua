-- Differential conformance runner. This is tooling, not a VM implementation path.
local root=(arg[0]:match('^(.*)/tools/[^/]+$') or '.')
local abc=root..'/build/abc'
package.path=root..'/gen/?.lua;'..root..'/tools/?.lua;'..package.path
local cache=require('cache')
local opcode_manifest=require('opcodes')
local opcode_coverage={}
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
local tmp=('/tmp/abc-vm-validate-%d'):format(os.time())
assert(os.execute(('mkdir -p %q'):format(tmp))==0)

local function write(name,text)
  local p=tmp..'/'..name..'.abcasm'; local f=assert(io.open(p,'wb')); assert(f:write(text)); assert(f:close())
  local out=tmp..'/'..name..'.abc'
  assert(os.execute(('%q asm %q -o %q'):format(abc,p,out))==0)
  local bf=assert(io.open(out,'rb')); local bytes=bf:read('*a'); bf:close()
  local function u32(at) local a,b,c,d=bytes:byte(at,at+3); return a+b*256+c*65536+d*16777216 end
  local sections=u32(9); local at=17; local code
  for _=1,sections do local tag,n=u32(at),u32(at+4); at=at+8; if tag==2 then code=bytes:sub(at,at+n-1) end; at=at+n end
  assert(code,'assembled module has no code section')
  local pc=1; while pc<=#code do local info=assert(opcode_manifest.ops[code:byte(pc)+1]); opcode_coverage[info.name]=true; local len=info.len;if info.name=='SWITCH' then local a,b=code:byte(pc+1,pc+2);len=3+4*(a+b*256) end;pc=pc+len end
  return out
end
local function capture(command)
  local p=assert(io.popen(command..' 2>&1','r')); local out=p:read('*a'):gsub('%s+$',''); local ok=p:close(); return out,ok~=nil
end
local checks=0
local function same(module,tail,expected)
  local i,io=capture(('%q run %q %s --interpreted'):format(abc,module,tail or ''))
  local c,co=capture(('%q run %q %s --compiled'):format(abc,module,tail or ''))
  local l,lo=capture(('%q run %q %s --lazy'):format(abc,module,tail or ''))
  assert(i==c and i==l,('mode mismatch\ninterpreter: %s\ncompiled: %s\nlazy: %s'):format(i,c,l))
  assert(io==co and io==lo,'mode status mismatch')
  if expected then assert(i==expected,('oracle mismatch\nactual: %s\nexpected: %s'):format(i,expected)) end
  checks=checks+1
end

-- Every two-stack arithmetic destination form, with dynamic inputs so stencils cannot fold it.
local binary={'ADD','SUB','MUL','DIVU','DIVS','REMU','REMS','AND','OR','XOR','SHL','SHR','SAR','EQ','NE','LT','LE','LTU','LEU'}
local a={('.function main 2 %d'):format(#binary*2)}
for _,op in ipairs(binary) do for _,dst in ipairs{'A','B'} do
  a[#a+1]=' CGET.A 0'; a[#a+1]=' CGET.B 1'; a[#a+1]=(' %s.%s'):format(op,dst)
  if dst=='B' then a[#a+1]=' MOVE.BA' end
end end
a[#a+1]=(' RET 2 %d'):format(#binary*2); a[#a+1]='.export main'
local arithmetic=write('arithmetic',table.concat(a,'\n')..'\n')
same(arithmetic,'main 18364758544493064720 7','-81985529216486889 -81985529216486889 -81985529216486903 -81985529216486903 -573898704515408272 -573898704515408272 2623536934927580674 2623536934927580674 -11712218459498128 -11712218459498128 2 2 0 0 0 0 -81985529216486889 -81985529216486889 -81985529216486889 -81985529216486889 7952596333999228928 7952596333999228928 143474676128852068 143474676128852068 -640511947003804 -640511947003804 0 0 1 1 1 1 1 1 0 0 0 0')

-- Typed float operations use raw IEEE-754 cell bits at the host boundary.
local float_lines={'.profile memory','.function floats 2 22 ff '..string.rep('i',22)}
for _,op in ipairs{'FADD','FSUB','FMUL','FDIV','FLT','FLE','FEQ'} do for _,dst in ipairs{'A','B'} do
  float_lines[#float_lines+1]=' CGET.A 0'; float_lines[#float_lines+1]=' CGET.B 1'; float_lines[#float_lines+1]=(' %s.%s'):format(op,dst)
  if op=='FADD' or op=='FSUB' or op=='FMUL' or op=='FDIV' then float_lines[#float_lines+1]=dst=='A' and ' F2IS' or ' MOVE.BA\n F2IS' elseif dst=='B' then float_lines[#float_lines+1]=' MOVE.BA' end
end end
for _,lines in ipairs{{' CGET.A 0',' FNEG',' F2IS'},{' PUSH.A -7',' I2FS',' F2IS'},{' PUSH.A 7',' I2FU',' F2IU'},{' CGET.A 0',' F2IS'},{' CGET.A 0',' F2IU'}} do for _,line in ipairs(lines) do float_lines[#float_lines+1]=line end end
for i,op in ipairs{'FBLT','FBLE','FBEQ'} do local yes,done='FY'..i,'FD'..i; float_lines[#float_lines+1]=' CGET.A 0';float_lines[#float_lines+1]=' CGET.B 1';float_lines[#float_lines+1]=' '..op..' '..yes;float_lines[#float_lines+1]=' PUSH.A 0';float_lines[#float_lines+1]=' JMP '..done;float_lines[#float_lines+1]=yes..': PUSH.A 1';float_lines[#float_lines+1]=done..':' end
float_lines[#float_lines+1]=' RET 2 22';float_lines[#float_lines+1]='.export floats'
local floats=write('floats',table.concat(float_lines,'\n')..'\n')
same(floats,'floats 4615063718147915776 4611686018427387904','5 5 1 1 7 7 1 1 0 0 0 0 0 0 -3 -7 7 3 3 0 0 0')
local nan=write('float-nan',[=[.profile memory
.function main 2 4 ff iiii
 CGET.A 0
 CGET.B 1
 FEQ.A
 CGET.A 0
 CGET.B 1
 FBLT N1
 PUSH.A 0
 JMP D1
N1: PUSH.A 1
D1: CGET.A 0
 CGET.B 1
 FBLE N2
 PUSH.A 0
 JMP D2
N2: PUSH.A 1
D2: CGET.A 0
 CGET.B 1
 FBEQ N3
 PUSH.A 0
 JMP D3
N3: PUSH.A 1
D3: RET 2 4
.export main
]=])
same(nan,'main 9221120237041090560 4611686018427387904','0 0 0 0')
local f2trap=write('float-conversion-trap',[=[.profile memory
.function main 1 1 f i
 CGET.A 0
 F2IS
 RET 1 1
.export main
]=])
same(f2trap,'main 9221120237041090560','abc: abort at byte 0x1: language abort 3')
local float_load=write('float-load',[=[.profile memory
.rodata 000000000000f83f0000000000000040
.function main 0 1 - i
 .loadkind float
 GLD64 0
 MOVE.AB
 .loadkind float
 GLD64 8
 FADD.A
 F2IS
 RET 0 1
.export main
]=])
same(float_load,'','3')
local bad_float_source=tmp..'/bad-float-kind.abcasm'; local bff=assert(io.open(bad_float_source,'wb'))
assert(bff:write('.profile memory\n.function main 0 1 - i\n PUSH.A 1\n PUSH.B 2\n FADD.A\n RET 0 1\n.export main\n')); assert(bff:close())
local bad_float_error=capture(('%q asm %q -o %q'):format(abc,bad_float_source,tmp..'/bad-float-kind.abc'))
assert(bad_float_error:match('float instruction given non%-float kind'),'float kind mismatch was not rejected')

local more_lines={'.function main 0 40'}
local x='18364758544493064720'
for _,op in ipairs{'NEG','NOT','LNOT','ZX32','SX32'} do for _,dst in ipairs{'A','B'} do
  more_lines[#more_lines+1]=(' PUSH.%s %s'):format(dst,x); more_lines[#more_lines+1]=(' %s.%s'):format(op,dst)
  if dst=='B' then more_lines[#more_lines+1]=' MOVE.BA' end
end end
for _,op in ipairs{'ADD','SUB','MUL','AND','OR','XOR','SHL','SHR','SAR'} do for _,dst in ipairs{'A','B'} do
  more_lines[#more_lines+1]=(' PUSH.%s %s'):format(dst,x); more_lines[#more_lines+1]=(' %sI.%s 3'):format(op,dst)
  if dst=='B' then more_lines[#more_lines+1]=' MOVE.BA' end
end end
more_lines[#more_lines+1]=' PUSH.A 5'; more_lines[#more_lines+1]=' CPUSH.A'
for _,op in ipairs{'ADD','SUB','MUL','XOR'} do for _,dst in ipairs{'A','B'} do
  more_lines[#more_lines+1]=(' PUSH.%s %s'):format(dst,x); more_lines[#more_lines+1]=(' %sC.%s 0'):format(op,dst)
  if dst=='B' then more_lines[#more_lines+1]=' MOVE.BA' end
end end
for _,line in ipairs{' CPOP',' PUSH.A 3',' PUSH.B 5',' POW',' PUSH.A 3',' PUSH.B 5',' POWS',' PUSH.A 255',' ZX8',' PUSH.A 65535',' ZX16',' RET 0 40','.export main'} do more_lines[#more_lines+1]=line end
local more=write('more',table.concat(more_lines,'\n')..'\n')
same(more,'','81985529216486896 81985529216486896 81985529216486895 81985529216486895 -81985529216486895 -81985529216486895 1985229328 1985229328 1985229328 1985229328 -81985529216486893 -81985529216486893 -81985529216486899 -81985529216486899 -245956587649460688 -245956587649460688 0 0 -81985529216486893 -81985529216486893 -81985529216486893 -81985529216486893 -655884233731895168 -655884233731895168 2295594818061633090 2295594818061633090 -10248191152060862 -10248191152060862 -81985529216486891 -81985529216486891 -81985529216486901 -81985529216486901 -409927646082434480 -409927646082434480 -81985529216486891 -81985529216486891 243 243 255 65535')

local context=write('context',[=[.function main 0 8
 PUSH.A 10
 PUSH.A 20
 PUSH.A 30
 CPUSHN 3
 CGETR.A 0 3
 CGET.A 2
 CSET.A 1
 CGET.A 1
 CGET.B 0
 MOVE.BA
 CPOP
 CPOP
 CPOP
 PUSH.B 40
 COPY.BA
 COPY.AB
 DROP.B
 MOVE.BA
 PUSH.A 7
 DUP.A
 DROP.A
 RET 0 8
.export main
]=])
same(context,'','10 20 30 30 10 40 40 7')

local cold_forms=write('cold-forms',[=[.function main 0 3
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
RET 0 3
.export main
]=])
same(cold_forms,'','10 21 32')

local branch_lines={}; local branch_count=0
local function branch_case(setup,instruction)
  local yes='Y'..branch_count; local done='D'..branch_count; branch_count=branch_count+1
  for _,line in ipairs(setup) do branch_lines[#branch_lines+1]=line end
  branch_lines[#branch_lines+1]=(' %s %s'):format(instruction,yes)
  branch_lines[#branch_lines+1]=' PUSH.A 0'; branch_lines[#branch_lines+1]=' JMP '..done
  branch_lines[#branch_lines+1]=yes..': PUSH.A 1'; branch_lines[#branch_lines+1]=done..':'
end
for _,op in ipairs{'BEQ','BNE','BLT','BLE','BLTU','BLEU'} do
  branch_case({' PUSH.A 2',' PUSH.B 3'},op); branch_case({' PUSH.A 3',' PUSH.B 2'},op)
end
for _,stack in ipairs{'A','B'} do for _,op in ipairs{'JZ','JNZ'} do for _,value in ipairs{0,4} do branch_case({(' PUSH.%s %d'):format(stack,value)},op..'.'..stack) end end end
for _,op in ipairs{'BEQI','BNEI','BLTI','BLEI','BGTI','BGEI','BLTUI','BLEUI','BGTUI','BGEUI'} do
  branch_case({' PUSH.A 2'},op..' 3'); branch_case({' PUSH.A 4'},op..' 3')
end
table.insert(branch_lines,1,('.function main 0 %d'):format(branch_count)); branch_lines[#branch_lines+1]=(' RET 0 %d'):format(branch_count); branch_lines[#branch_lines+1]='.export main'
local branches=write('branches',table.concat(branch_lines,'\n')..'\n')
same(branches,'','0 0 1 1 1 0 1 0 1 0 1 0 1 0 0 1 1 0 0 1 0 0 1 1 1 0 1 0 0 1 0 1 1 0 1 0 0 1 0 1')

local switch=write('switch',[=[.function choose 1 1
 CGET.A 0
 SWITCH S0 S1 S2
 PUSH.A 9
 JMP32 SD
S0: PUSH.A 10
 JMP32 SD
S1: PUSH.A 11
 JMP32 SD
S2: PUSH.A 12
SD: RET 1 1
.export choose
.function folded 0 1
 PUSH.A 1
 SWITCH F0 F1
 PUSH.A 19
 JMP32 FD
F0: PUSH.A 20
 JMP32 FD
F1: PUSH.A 21
FD: RET 0 1
.export folded
]=])
same(switch,'choose 0','10');same(switch,'choose 2','12');same(switch,'choose 5','9');same(switch,'folded','21')

local dynamic_lines={'.function dynamic 2 20'}; local dn=0
local function dynamic_case(setup,instruction)
  local yes='DY'..dn; local done='DD'..dn; dn=dn+1
  for _,line in ipairs(setup) do dynamic_lines[#dynamic_lines+1]=line end
  dynamic_lines[#dynamic_lines+1]=(' %s %s'):format(instruction,yes); dynamic_lines[#dynamic_lines+1]=' PUSH.A 0'; dynamic_lines[#dynamic_lines+1]=' JMP '..done
  dynamic_lines[#dynamic_lines+1]=yes..': PUSH.A 1'; dynamic_lines[#dynamic_lines+1]=done..':'
end
for _,op in ipairs{'BEQ','BNE','BLT','BLE','BLTU','BLEU'} do dynamic_case({' CGET.A 0',' CGET.B 1'},op) end
dynamic_case({' CGET.A 0'},'JZ.A'); dynamic_case({' CGET.A 0'},'JNZ.A'); dynamic_case({' CGET.B 1'},'JZ.B'); dynamic_case({' CGET.B 1'},'JNZ.B')
for _,op in ipairs{'BEQI','BNEI','BLTI','BLEI','BGTI','BGEI','BLTUI','BLEUI','BGTUI','BGEUI'} do dynamic_case({' CGET.A 0'},op..' 3') end
dynamic_lines[#dynamic_lines+1]=' RET 2 20'; dynamic_lines[#dynamic_lines+1]='.export dynamic'
local dynamic_branches=write('dynamic-branches',table.concat(dynamic_lines,'\n')..'\n')
same(dynamic_branches,'dynamic 2 3','0 1 1 1 1 1 0 1 0 1 0 1 1 1 0 0 1 1 0 0')
same(dynamic_branches,'dynamic 4 2','0 1 0 0 0 0 0 1 0 1 0 1 0 0 1 1 0 0 1 1')

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
 ST8 0
 FADDR.A 40
 LD8.A 0
 FADDR.A 38
 PUSH.B 4660
 ST16 0
 FADDR.B 38
 LD16.B 0
 MOVE.BA
 FADDR.A 32
 PUSH.B 4294967295
 ST32 0
 FADDR.A 32
 LD32S.A 0
 FADDR.A 24
 PUSH.B 1234605616436508552
 ST64 0
 FADDR.A 24
 LD64.A 0
 FADDR.A 40
 PUSH.B 1
 LDX8
 FADDR.A 40
 PUSH.B 2
 IDX 1
 LD8.A 0
 FADDR.A 16
 FADDR.B 24
 MEMCPY 8
 FADDR.A 16
 LD64.A 0
 PUSH.A 171
 GST8 0
 GLD8 0
 PUSH.A 65518
 GST16 2
 GLD16 2
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
 GST32 4
 GLD32 4
 DROP.A
 GLD32S 4
 DROP.A
 PUSH.A 1234605616436508552
 GST64 8
 GLD64 8
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
 LDX16
 DROP.A
 FADDR.A 64
 PUSH.B 0
 LDX32
 DROP.A
 FADDR.A 64
 PUSH.B 0
 LDX32S
 DROP.A
 FADDR.A 64
 PUSH.B 0
 LDX64
 DROP.A
 CFREE 64
 RET 0 14
.export main
]=])
same(memory,'','255 65535 4294967295 -1 123456789 254 4660 -1 1234605616436508552 0 52 1234605616436508552 171 65518')

local errors=write('errors',[=[.function divzero 1 1
 CGET.A 0
 PUSH.B 0
 DIVU.A
 RET 1 1
.function powsneg 1 1
 PUSH.A 2
 CGET.B 0
 POWS
 RET 1 1
.function chku8 1 1
 CGET.A 0
 CHKU8
 RET 1 1
.function explicit 0 0
 ABORT 9
.function chku16 1 1
 CGET.A 0
 CHKU16
 RET 1 1
.function chku32 1 1
 CGET.A 0
 CHKU32
 RET 1 1
.function chki32 1 1
 CGET.A 0
 CHKI32
 RET 1 1
.function chknn 1 1
 CGET.A 0
 CHKNN
 RET 1 1
.export divzero
.export powsneg
.export chku8
.export explicit
.export chku16
.export chku32
.export chki32
.export chknn
]=])
same(errors,'divzero 1','abc: abort at byte 0x3: language abort 1')
same(errors,'powsneg -1','abc: abort at byte 0xa: language abort 4')
same(errors,'chku8 256','abc: abort at byte 0xf: language abort 3')
same(errors,'explicit','abc: abort at byte 0x13: language abort 9')
same(errors,'chku16 65535','65535')
same(errors,'chku16 65536','abc: abort at byte 0x16: language abort 3')
same(errors,'chku32 4294967295','4294967295')
same(errors,'chku32 4294967296','abc: abort at byte 0x1b: language abort 3')
same(errors,'chki32 -2147483648','-2147483648')
same(errors,'chki32 2147483648','abc: abort at byte 0x20: language abort 3')
same(errors,'chknn 0','0')
same(errors,'chknn -1','abc: abort at byte 0x25: language abort 3')

local overflow=write('overflow',[=[.function main 0 1
 PUSH.A 1
 PUSH.A 2
 DROP.A
 RET 0 1
.export main
]=])
same(overflow,'--stack=1','abc: stack-limit at byte 0x0: stack limit reached')

local virtual_limit=write('virtual-limit',[=[.function main 0 1
CALL.A wide 0
RET 0 1
.function wide 0 1
PUSH.A 1
PUSH.A 2
DROP.A
RET 0 1
.export main
]=])
same(virtual_limit,'--stack=1','abc: stack-limit at byte 0x0: stack limit reached')

local tail_limit=write('tail-limit',[=[.function main 0 1
TCALL wide 0 0
.function wide 0 1
PUSH.A 1
PUSH.A 2
DROP.A
RET 0 1
.export main
]=])
same(tail_limit,'--stack=1','abc: stack-limit at byte 0x0: stack limit reached')

local recursive_limit=write('recursive-limit',[=[.function main 0 0
CALL.A recurse 0
RET 0 0
.function recurse 0 0
CALL.A recurse 0
RET 0 0
.export main
]=])
same(recursive_limit,'--stack=2','abc: stack-limit at byte 0x9: stack limit reached')
local mutual_recursion=write('mutual-recursion',[=[.function main 0 1
PUSH.A 11
CALL.A even 1
RET 0 1
.function even 1 1
CGET.A 0
JNZ.A even_step
PUSH.A 1
RET 1 1
even_step:
CGET.A 0
SUBI.A 1
CALL.A odd 1
ADDI.A 0
RET 1 1
.function odd 1 1
CGET.A 0
JNZ.A odd_step
PUSH.A 0
RET 1 1
odd_step:
CGET.A 0
SUBI.A 1
CALL.A even 1
ADDI.A 0
RET 1 1
.export main
]=])
same(mutual_recursion,'','0')

local real_b=write('real-b',[=[.function main 0 1
PUSH.B 100
PUSH.A 7
CALL.A wide 1
ADD.A
RET 0 1
.function wide 1 1
CGET.A 0
PUSH.B 3
ADD.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
PUSH.A 0
DROP.A
RET 1 1
.export main
]=])
same(real_b,'','110')

local indirect_limit=write('indirect-limit',[=[.profile callables
.datazero 8
.codeaddr 0 wide
.signature sig 1 1 a i
.function main 0 1
GADDR.A 0
.loadkind addr
GLD64 0
MOVE.AB
CALLI.A 1 sig
RET 0 1
.function wide 1 1 a i
PUSH.A 1
PUSH.A 2
PUSH.A 3
PUSH.A 4
DROP.A
DROP.A
DROP.A
RET 1 1
.export main
]=])
same(indirect_limit,'--stack=3','abc: stack-limit at byte 0xb: stack limit reached')

local indirect_b=write('indirect-b',[=[.profile callables
.datazero 8
.codeaddr 0 target
.signature sig 1 1 a i
.function main 0 1
GADDR.A 0
.loadkind addr
GLD64 0
MOVE.AB
CALLI.B 1 sig
MOVE.BA
RET 0 1
.function target 1 1 a i
PUSH.A 77
RET 1 1
.export main
]=])
same(indirect_b,'','77')

local indirect_tail_limit=write('indirect-tail-limit',[=[.profile callables
.datazero 8
.codeaddr 0 wide
.signature sig 1 1 a i
.function main 0 1
GADDR.A 0
.loadkind addr
GLD64 0
MOVE.AB
TCALLI 0 1 sig
.function wide 1 1 a i
PUSH.A 1
PUSH.A 2
PUSH.A 3
PUSH.A 4
DROP.A
DROP.A
DROP.A
RET 1 1
.export main
]=])
same(indirect_tail_limit,'--stack=3','abc: stack-limit at byte 0xb: stack limit reached')

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
d3: MOVE.AB
ADD.A
MOVE.AB
ADD.A
MOVE.AB
ADD.A
RET 4 1
.export main
]=])
same(version_cap,'main 0 0 0 0','0')
same(version_cap,'main 1 1 1 1','4')
same(version_cap,'main 1 0 1 0','2')
local obsolete_budget=capture(('%q run %q --budget=1'):format(abc,version_cap))
assert(obsolete_budget=='abc: unknown option: --budget=1','obsolete budget option was accepted')
checks=checks+1

local halt=write('halt',[=[.function main 0 1
 PUSH.A 99
 HALT
.export main
]=])
same(halt,'','99')

local direct_tail=write('direct-tail',[=[.function main 0 1
 PUSH.A 40
 PUSH.A 2
 CALL.A adapter 2
 RET 0 1
.function adapter 2 1
 CGET.A 0
 CGET.A 1
 TCALL add 2 2
.function add 2 1
 CGET.A 0
 CGET.B 1
 ADD.A
 RET 2 1
.export main
]=])
same(direct_tail,'','42')

local virtual_calls=write('virtual-calls',[=[.function main 0 1
 PUSH.A 40
 PUSH.A 2
 CALL.A outer 2
 RET 0 1
.function outer 2 1
 CGET.A 0
 CGET.A 1
 CALL.B add 2
 MOVE.BA
 RET 2 1
.function add 2 1
 CGET.A 0
 CGET.B 1
 ADD.A
 RET 2 1
.export main
]=])
same(virtual_calls,'','42')

local large_frame=write('large-frame',[=[.profile memory
.function main 0 0
 CALLOC 65535
 CFREE 65535
 RET 0 0
.export main
]=])
same(large_frame,'--stack=9000','')

-- Legacy SLet examples remain explicit bootstrap-oracle fixtures; production `.slet` source uses
-- frontend/let through `abc compile` and `abc run`. Keeping the oracle invocation here prevents the
-- CLI from silently selecting the bootstrap when production semantic construction rejects.
local function bootstrap_example(name)
  local file=assert(io.open(root..'/examples/'..name..'.slet','rb'));local source=file:read('*a');file:close()
  return write('bootstrap-'..name,require('slet_frontend').compile(source,{'main'}))
end
same(bootstrap_example('fibonacci'),'','55')
same(bootstrap_example('partial'),'','270369 67634689')
same(bootstrap_example('closures'),'','42 43')

local foreign_file=assert(io.open(root..'/examples/foreign.abcasm','rb')); local foreign_source=foreign_file:read('*a'); foreign_file:close()
write('foreign-coverage',foreign_source)

local ext_source=tmp..'/unknown-ext.abcasm'; local ef=assert(io.open(ext_source,'wb'))
assert(ef:write('.function main 0 0\n EXT 255\n RET 0 0\n.export main\n')); assert(ef:close())
local ext_error=capture(('%q asm %q -o %q'):format(abc,ext_source,tmp..'/unknown-ext.abc'))
assert(ext_error:match('dynamic EXT instruction requires profile 5'),'EXT was accepted outside profile 5')
opcode_coverage.EXT=true

local missing={}
for _,op in ipairs(opcode_manifest.ops) do if op.kind~=opcode_manifest.kind.INTERNAL and not opcode_coverage[op.name] then missing[#missing+1]=op.name end end
assert(#missing==0,'validation misses public opcodes: '..table.concat(missing,', '))
os.execute(('rm -rf %q'):format(tmp))
print(('validated %d differential cases and all public opcode forms'):format(checks))

