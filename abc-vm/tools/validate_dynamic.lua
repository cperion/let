local root=(arg[0]:match('^(.*)/tools/[^/]+$') or '.')
local abc=root..'/build/abc'
local tmp='/tmp/abc-vm-dynamic-'..tostring(os.time())
assert(os.execute(('mkdir -p %q'):format(tmp))==0)
local function capture(cmd)local p=assert(io.popen(cmd..' 2>&1','r'));local out=p:read('*a'):gsub('%s+$','');p:close();return out,not out:match('^abc:') end
local function module(name,body)
  local source=tmp..'/'..name..'.abcasm';local binary=tmp..'/'..name..'.abc';local f=assert(io.open(source,'wb'));assert(f:write(body));assert(f:close())
  local out,ok=capture(('%q asm %q -o %q'):format(abc,source,binary));assert(ok,out);return binary
end
local function same(path,export,expected)
  local first,status
  for _,mode in ipairs{'interpreted','compiled','lazy'} do local out,ok=capture(('%q run %q %s --%s'):format(abc,path,export or '',mode));if not first then first,status=out,ok else assert(out==first and ok==status,('dynamic mode mismatch: %s != %s'):format(first,out))end end
  assert(first==expected,('dynamic result %s != %s'):format(first,expected))
end
local scalar=module('scalar',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor primitive B bool
.descriptor primitive W u64
.descriptor primitive F f64
.descriptor primitive D any
.constant Seven u8 07 literal
.datazero 8
.gcroot 0 D
.function main 0 6 - iiiiff
  PUSH.A 5
  ANY_BOX U
  PUSH.A 7
  ANY_BOX U
  DADD
  ANY_CAST U
  PUSH.A 5
  ANY_BOX U
  DADDL Seven 0
  ANY_CAST U
  PUSH.A 1
  ANY_BOX B
  DREQUIRE_BOOL
  PUSH64.A 18446744073709551615
  ANY_BOX W
  ANY_CAST W
  PUSH.A 0
  I2FU
  FNEG
  ANY_BOX F
  ANY_CAST F
  PUSH.A 0
  I2FU
  MOVE.AB
  PUSH.A 0
  I2FU
  FDIV.A
  ANY_BOX F
  ANY_CAST F
  RET 0 6
.export main
]=])
same(scalar,'main','12 12 1 -1 -9223372036854775808 9221120237041090560')
local loop_home=module('loop-home',[=[
.profile dynamic
.descriptor primitive U u32
.function main 0 1 - i
  PUSH.A 0
  ANY_BOX U
  CPUSH.A
  PUSH.A 0
  CPUSH.A
loop:
  CGET0.A
  PUSH.B 10
  BLTU body
  CGET1.A
  ANY_CAST U
  RET 2 1
body:
  CGET1.A
  PUSH.A 1
  ANY_BOX U
  DADD
  CSET.A 1
  CGET0.A
  ADDI.A 1
  CSET.A 0
  JMP loop
.export main
]=])
same(loop_home,'main','10')
local word=module('word',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor primitive W u64
.descriptor signature Empty 0 0
.function main 0 2 - ii
  WORD_NEW Empty
  PUSH.A 1
  ANY_BOX U
  PUSH.A 42
  ANY_BOX U
  WORD_SET
  CPUSH.A
  CGET0.A
  PUSH.A 1
  ANY_BOX W
  WORD_GET
  ANY_CAST U
  CGET0.A
  WORD_COUNT
  CPOP
  RET 0 2
.export main
]=])
same(word,'main','42 1')
local supplied_word=module('supplied-word',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Empty 0 0
.function main 0 2 - ii
  WORD_NEW Empty
  PUSH.A 1
  ANY_BOX U
  PUSH.A 10
  ANY_BOX U
  WORD_SET
  WORD_NEW Empty
  PUSH.A 1
  ANY_BOX U
  PUSH.A 20
  ANY_BOX U
  WORD_SET
  PUSH.A 2
  ANY_BOX U
  PUSH.A 30
  ANY_BOX U
  WORD_SET
  WORD_SUPPLY
  CPUSH.A
  CGET0.A
  PUSH.A 1
  ANY_BOX U
  WORD_GET
  ANY_CAST U
  CGET0.A
  WORD_COUNT
  CPOP
  RET 0 2
.export main
]=])
same(supplied_word,'main','20 2')
local method_word=module('method-word',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Empty 0 0
.descriptor signature Get 0 1 U
.function nine 0 1 - i
  PUSH.A 9
  RET 0 1
.function main 0 1 - i
  WORD_NEW Empty
  PUSH.A 1
  ANY_BOX U
  WORD_DIRECT nine Get
  WORD_METHOD
  PUSH.A 1
  ANY_BOX U
  WORD_GET
  DCALL 0 1 exact
  ANY_CAST U
  RET 0 1
.export main
]=])
same(method_word,'main','9')
local callable=module('callable-object',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Sig 1 1 U U
.function id 1 1 i i
  CGET0.A
  RET 1 1
.function main 0 1 - i
  PUSH.A 7
  PUSH.B 8
  WORD_DIRECT id Sig
  PUSH.A 41
  ANY_BOX U
  DCALL 1 1 exact
  ANY_CAST U
  DROP.A
  DROP.B
  RET 0 1
.export main
]=])
same(callable,'main','7')
local dynamic_tail=module('dynamic-tail',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Sig 1 1 U U
.function id 1 1 i i
  CGET0.A
  RET 1 1
.function tail 2 1 dd d
  CGET0.A
  CGET1.A
  DTCALL 1 1 exact
.function main 0 1 - i
  WORD_DIRECT id Sig
  PUSH64.A 4294967337
  ANY_BOX U
  CALL.A tail 2
  ANY_CAST U
  RET 0 1
.export main
]=])
same(dynamic_tail,'main','4294967337')
local dynamic_i32=module('dynamic-i32',[=[
.profile dynamic
.descriptor primitive I i32
.function main 0 1 - i
  PUSH64.A 4294967295
  SX32.A
  ANY_BOX I
  PUSH.A 2
  ANY_BOX I
  DADD
  ANY_CAST I
  RET 0 1
.export main
]=])
same(dynamic_i32,'main','1')
local dynamic_u64=module('dynamic-u64',[=[
.profile dynamic
.descriptor primitive W u64
.function d2_u64 0 1 - i
  PUSH.A 2
  ANY_BOX W
  ANY_CAST W
  RET 0 1
.function f_w_add_w 0 1 - i
  PUSH.A 19
  ANY_BOX W
  PUSH.A 23
  ANY_BOX W
  DADD
  ANY_CAST W
  RET 0 1
.function f_w_overflow 0 1 - i
  PUSH64.A 549755813888
  ANY_BOX W
  PUSH64.A 549755813888
  ANY_BOX W
  DADD
  ANY_CAST W
  RET 0 1
.export d2_u64
.export f_w_add_w
.export f_w_overflow
]=])
same(dynamic_u64,'d2_u64','2')
same(dynamic_u64,'f_w_add_w','42')
same(dynamic_u64,'f_w_overflow','1099511627776')
local dynamic_return=module('dynamic-return',[=[
.profile dynamic
.datazero 8
.descriptor primitive U u32
.function maker 0 1 - d
  PUSH.A 7
  ANY_BOX U
  RET 0 1
.function main 0 1 - i
  .loadkind addr
  GLD64 0
  DROP.A
  CALL.A maker 0
  ANY_CAST U
  RET 0 1
.export main
.codeaddr 0 maker
]=])
same(dynamic_return,'main','7')
local closure=module('closure-call',[=[
.profile dynamic
.data 0500000000000000
.rodata 78
.descriptor primitive U u64
.descriptor signature Sig 1 1 U U
.descriptor record Captures 8 1 0 1 0 U
.descriptor closure Closure Sig Captures
.function add_capture 2 1 ai i
  CGET0.A
  LD64.A 0
  CGET1.B
  ADD.A
  RET 2 1
.function main 0 1 - i
  GADDR.A 0
  CLOSURE_NEW add_capture Closure
  PUSH.A 37
  ANY_BOX U
  DCALL 1 1 exact
  ANY_CAST U
  RET 0 1
.export main
]=])
same(closure,'main','42')
local adjusted=module('adjusted-call',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Pair 0 2 U U
.function pair 0 2 - ii
  PUSH.A 10
  PUSH.A 20
  RET 0 2
.function main 0 1 - i
  WORD_DIRECT pair Pair
  DCALL 0 1 adjust
  ANY_CAST U
  RET 0 1
.export main
]=])
same(adjusted,'main','10')
local partial=module('partial-call',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Two 2 1 U U U
.function first 2 1 ii i
  CGET0.A
  RET 2 1
.function main 0 1 - i
  WORD_DIRECT first Two
  PUSH.A 11
  ANY_BOX U
  DCALL 1 1 exact
  PUSH.A 22
  ANY_BOX U
  DCALL 1 1 exact
  ANY_CAST U
  RET 0 1
.export main
]=])
same(partial,'main','11')
local partial_word=module('partial-word',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor primitive W word
.descriptor signature Two 2 1 U U U
.function first 2 1 ii i
  CGET0.A
  RET 2 1
.function main 0 1 - i
  WORD_DIRECT first Two
  PUSH.A 11
  ANY_BOX U
  DCALL 1 1 exact
  ANY_IS W
  RET 0 1
.export main
]=])
same(partial_word,'main','1')
local exact_bad=module('exact-call',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Pair 0 2 U U
.function pair 0 2 - ii
  PUSH.A 10
  PUSH.A 20
  RET 0 2
.function main 0 1 - i
  WORD_DIRECT pair Pair
  DCALL 0 1 exact
  DROP.A
  PUSH.A 1
  RET 0 1
.export main
]=])
local exact_out,exact_ok=capture(('%q run %q main --lazy'):format(abc,exact_bad));assert(not exact_ok and exact_out:match('language abort 12'),'exact dynamic result mismatch did not abort before call')
local function aborts_all(path,reason,label)for _,mode in ipairs{'interpreted','compiled','lazy'} do local text,success=capture(('%q run %q main --%s'):format(abc,path,mode));assert(not success and text:match('language abort '..reason),label..' did not abort in '..mode..': '..text)end end
local no_terminal=module('no-terminal',[=[
.profile dynamic
.descriptor signature Empty 0 0
.function main 0 1 - i
  WORD_NEW Empty
  DCALL 0 0 exact
  PUSH.A 1
  RET 0 1
.export main
]=])
aborts_all(no_terminal,9,'open word without terminal')
local over_call=module('over-call',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Empty 0 0
.function zero 0 0
  RET 0 0
.function main 0 1 - i
  WORD_DIRECT zero Empty
  PUSH.A 1
  ANY_BOX U
  DCALL 1 0 exact
  PUSH.A 1
  RET 0 1
.export main
]=])
aborts_all(over_call,11,'dynamic overapplication')
local bad_partial=module('bad-partial',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Two 2 1 U U U
.function first 2 1 ii i
  CGET0.A
  RET 2 1
.function main 0 1 - i
  WORD_DIRECT first Two
  PUSH.A 1
  ANY_BOX U
  DCALL 1 0 exact
  PUSH.A 1
  RET 0 1
.export main
]=])
aborts_all(bad_partial,12,'partial call result contract')
local aggregate=module('aggregate',[=[
.profile dynamic
.data 2a00000000000000
.rodata 78
.descriptor primitive U u64
.descriptor record R 8 1 0 1 0 U
.function main 0 1 - i
  GADDR.A 0
  ANY_BOX R
  ANY_CAST R
  LD64.A 0
  RET 0 1
.export main
]=])
same(aggregate,'main','42')
local aggregate_result=module('aggregate-result',[=[
.profile dynamic
.data 2a00000000000000
.rodata 78
.descriptor primitive U u64
.descriptor record R 8 1 0 1 0 U
.descriptor signature Make 0 1 R
.function make 0 1 - a
  GADDR.A 0
  RET 0 1
.function main 0 1 - i
  WORD_DIRECT make Make
  DCALL 0 1 exact
  ANY_CAST R
  LD64.A 0
  RET 0 1
.export main
]=])
same(aggregate_result,'main','42')
local managed=module('managed-storage',[=[
.profile dynamic
.rodata 78
.descriptor primitive U u64
.descriptor record R 8 1 0 1 0 U
.descriptor pointer Ref managed R
.function main 0 1 - i
  MANAGED_NEW R
  DUP.A
  PUSH.B 42
  ST64 0
  ANY_BOX Ref
  ANY_CAST Ref
  LD64.A 0
  RET 0 1
.export main
]=])
same(managed,'main','42')
local string_key=module('string-key',[=[
.profile dynamic
.rodata 6b6579
.descriptor primitive U u32
.descriptor primitive S string
.descriptor signature Empty 0 0
.function main 0 1 - i
  WORD_NEW Empty
  CPUSH.A
  CGET0.A
  GADDR.A 0
  PUSH.A 3
  ANY_BOX S
  PUSH.A 42
  ANY_BOX U
  WORD_SET
  DROP.A
  CGET0.A
  GADDR.A 0
  PUSH.A 3
  ANY_BOX S
  WORD_GET
  ANY_CAST U
  CPOP
  RET 0 1
.export main
]=])
same(string_key,'main','42')
local churn_lines={'.profile dynamic','.descriptor primitive U u32','.descriptor signature Empty 0 0','.function main 0 2 - ii','  WORD_NEW Empty','  CPUSH.A'}
for i=1,1000 do churn_lines[#churn_lines+1]='  CGET0.A';churn_lines[#churn_lines+1]=('  PUSH.A %d'):format(i);churn_lines[#churn_lines+1]='  ANY_BOX U';churn_lines[#churn_lines+1]=('  PUSH.A %d'):format(i*10);churn_lines[#churn_lines+1]='  ANY_BOX U';churn_lines[#churn_lines+1]='  WORD_SET';churn_lines[#churn_lines+1]='  DROP.A' end
for i=2,998 do churn_lines[#churn_lines+1]='  CGET0.A';churn_lines[#churn_lines+1]=('  PUSH.A %d'):format(i);churn_lines[#churn_lines+1]='  ANY_BOX U';churn_lines[#churn_lines+1]='  WORD_REMOVE';churn_lines[#churn_lines+1]='  DROP.A' end
for _,line in ipairs{'  CGET0.A','  WORD_COUNT','  CGET0.A','  PUSH.A 1','  ANY_BOX U','  WORD_KEY','  ANY_CAST U','  CPOP','  RET 0 2','.export main'} do churn_lines[#churn_lines+1]=line end
local churn=module('word-churn',table.concat(churn_lines,'\n'))
same(churn,'main','3 999')
local frozen=module('frozen-cycle',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor signature Empty 0 0
.function main 0 0
  WORD_NEW Empty
  CPUSH.A
  CGET0.A
  PUSH.A 1
  ANY_BOX U
  CGET0.A
  WORD_SET
  DROP.A
  CGET0.A
  WORD_FREEZE
  DROP.A
  CGET0.A
  PUSH.A 1
  ANY_BOX U
  PUSH.A 2
  ANY_BOX U
  WORD_SET
  DROP.A
  CPOP
  RET 0 0
.export main
]=])
local frozen_out,frozen_ok=capture(('%q run %q main --lazy'):format(abc,frozen));assert(not frozen_ok and frozen_out:match('language abort 10'),'cyclic deep freeze did not reject mutation')
local mismatch=module('mismatch',[=[
.profile dynamic
.descriptor primitive U u32
.descriptor primitive B bool
.function main 0 0
  PUSH.A 1
  ANY_BOX U
  DREQUIRE_BOOL
  DROP.A
  RET 0 0
.export main
]=])
local out,ok=capture(('%q run %q main --lazy'):format(abc,mismatch));assert(not ok and out:match('language abort 6'),'dynamic type mismatch did not abort with reason 6')
local bad=tmp..'/abi-any.abcasm';local f=assert(io.open(bad,'wb'));f:write('.profile dynamic\n.function main 0 1 - d\n PUSH.A 0\n RET 0 1\n.export main\n');f:close()
out,ok=capture(('%q asm %q -o %q'):format(abc,bad,tmp..'/bad.abc'));assert(not ok and out:match('abi%-any'),'dynamic export was accepted')
local function rejected(name,source,pattern)local path=tmp..'/'..name..'.abcasm';local h=assert(io.open(path,'wb'));assert(h:write(source));assert(h:close());local text,success=capture(('%q asm %q -o %q'):format(abc,path,tmp..'/'..name..'.abc'));assert(not success and text:match(pattern),name..' was accepted: '..text)end
rejected('nan-constant','.profile dynamic\n.constant Bad f64 010000000000f07f\n.function main 0 0\n RET 0 0\n.export main\n','noncanonical NaN')
rejected('borrow-box','.profile dynamic\n.datazero 8\n.descriptor primitive U u32\n.descriptor pointer P strict U\n.function main 0 0\n GADDR.A 0\n ANY_BOX P\n DROP.A\n RET 0 0\n.export main\n','unmanaged borrowed')
assert(os.execute(('rm -rf %q'):format(tmp))==0)
print('validated profile-5 scalar/aggregate/managed boxing, dynamic calls/tail calls, direct/captured and partial/open-word calls, result adjustment, canonical nonallocating floats, generic arithmetic, ordered-map growth/removal, traps, roots, and three execution policies')

