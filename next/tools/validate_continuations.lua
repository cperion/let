-- Native frame transport must compose with transfers without fused CALL/RET.
local root=arg[0]:match('^(.*)/tools/[^/]+$') or '.'
local abc=root..'/build/abc'
local temp=assert(io.popen('mktemp -d /tmp/abc-continuations.XXXXXX'))
local tmp=assert(temp:read('*l'));assert(temp:close())
local checks=0
local function run(args)
  local words={};for i,x in ipairs(args) do words[i]=string.format('%q',tostring(x)) end
  local p=assert(io.popen(table.concat(words,' ').." 2>&1; printf '\n__STATUS__%d\n' $?"))
  local text=p:read('*a');p:close()
  local out,status=text:match('^(.*)\n__STATUS__(%d+)\n$');assert(status,text)
  return out,tonumber(status)
end
local function assemble(name,lines)
  local path=tmp..'/'..name
  local f=assert(io.open(path..'.abcasm','wb'));assert(f:write(table.concat(lines,'\n'),'\n'));assert(f:close())
  local out,status=run{abc,'asm',path..'.abcasm','-o',path..'.abc'};assert(status==0,out)
  return path..'.abc'
end
local function compare(path,args,expected,stack,failure)
  local reference,reference_status
  for _,mode in ipairs{'interpreted','compiled','lazy','jit=threaded'} do
    local cmd={abc,'run',path,'main','--'..mode,'--stack='..(stack or 1024)}
    for _,v in ipairs(args) do cmd[#cmd+1]=v end
    local out,status=run(cmd)
    if mode=='interpreted' then reference,reference_status=out,status
    else assert(out==reference and status==reference_status,mode..' '..path..': '..out..' != '..reference) end
    if expected then assert(status==0 and out==expected,mode..' '..path..': '..out)
    else assert(status~=0 and out:find(failure or 'stack',1,true),out) end
    checks=checks+1
  end
end
-- Both result destinations, register/home arguments, zero/single/multi results,
-- and live caller values on both operand stacks. Nonzero A/B/C rebases are all
-- required; the one-cell return must preserve r0 while loading its continuation.
for _,n in ipairs{1,2,9} do for results=0,2 do for _,dst in ipairs{'A','B'} do for _,source in ipairs{'A','B'} do
  local lines={('.function recurse %d %d'):format(n,results),' CGET.A 0',' JZ.A base',
    ' PUSH.A 101',' PUSH.B 202',' CGET.'..dst..' 0',' SUBI.'..dst..' 1'}
  for j=1,n-1 do lines[#lines+1]=' CGET.'..dst..' '..j end
  lines[#lines+1]=(' CALL.%s recurse %d'):format(dst,n)
  local other=dst=='A' and 'B' or 'A'
  if results==2 then
    lines[#lines+1]=' PUSH.'..other..' 42';lines[#lines+1]=' BEQ.'..dst..' pair_ok';lines[#lines+1]=' ABORT 1';lines[#lines+1]='pair_ok:'
  end
  if results>=1 then
    lines[#lines+1]=' CGET.'..other..' 0';lines[#lines+1]=' SUBI.'..other..' 1'
    lines[#lines+1]=' BEQ.'..dst..' result_ok';lines[#lines+1]=' ABORT 2';lines[#lines+1]='result_ok:'
  end
  for _,line in ipairs{' PUSH.A 202',' BEQ.B b_ok',' ABORT 3','b_ok:',
    ' PUSH.B 101',' BEQ.A a_ok',' ABORT 4','a_ok:','base:'} do lines[#lines+1]=line end
  for j=1,n-1 do
    lines[#lines+1]=' CGET.A '..j;lines[#lines+1]=' PUSH.B '..(10+j)
    lines[#lines+1]=' BEQ.A arg'..j;lines[#lines+1]=' ABORT 5';lines[#lines+1]='arg'..j..':'
  end
  if results>=1 then lines[#lines+1]=' CGET.'..source..' 0' end
  if results==2 then lines[#lines+1]=' PUSH.'..source..' 42' end
  lines[#lines+1]=(' RET.%s %d %d'):format(source,n,results);lines[#lines+1]='.export main recurse'
  local path=assemble(('recursive-%d-%d-%s-%s'):format(n,results,dst,source),lines)
  for _,depth in ipairs{0,1,6} do
    local args={depth};for j=1,n-1 do args[#args+1]=10+j end
    local expected=results==0 and '\n' or tostring(depth)..(results==2 and ' 42\n' or '\n')
    compare(path,args,expected)
  end
  local args={64};for j=1,n-1 do args[#args+1]=10+j end
  compare(path,args,nil,32)
end end end end
-- A tail transfer keeps the original continuation and CALL.B destination
-- while crossing a mutually recursive SCC.
local mutual=assemble('mutual-tail',{
  '.function f 1 1',' CGET.A 0',' JZ.A base',' CGET.B 0',' SUBI.B 1',
  ' CALL.B g 1',' MOVE.B',' ADDI.A 1',' RET.A 1 1','base:',' PUSH.A 0',' RET.A 1 1',
  '.function g 1 1',' CGET.A 0',' TCALL.A f 1 1','.export main f',
})
for _,depth in ipairs{0,1,6,20} do compare(mutual,{depth},depth..'\n') end
compare(mutual,{64},nil,32)

-- Zero-argument recursive activation still needs its own continuation cell.
local zero=assemble('zero-arguments',{
  '.profile memory','.datazero 8','.function recurse 0 1 - i',
  ' .loadkind int',' GLD64.A 0',' DUP.A',' JZ.A base',' SUBI.A 1',' GST64.A 0',
  ' CALL.A recurse 0',' ADDI.A 1',' RET.A 0 1','base:',' RET.A 0 1',
  '.function main 0 1 - i',' PUSH.A 6',' GST64.A 0',' CALL.B recurse 0',
  ' MOVE.B',' RET.A 0 1','.export main',
})
compare(zero,{},'6\n')

-- More results than cache registers, through both virtual and real calls.
-- Reusing A must not change values already returned onto B: HOME(A,n) is a
-- mutable source read, not a captured result that can simply rename to B.
for _,dst in ipairs{'A','B'} do for _,source in ipairs{'A','B'} do
  local n=12
  local kinds=string.rep('i',n)
  local lines={'.profile memory',('.function main %d %d %s %s'):format(n,n,kinds,kinds)}
  for call=0,9 do
    lines[#lines+1]=' CGETR.'..dst..' 0 '..n
    lines[#lines+1]=' ADDI.'..dst..' '..call
    lines[#lines+1]=(' CALL.%s echo %d'):format(dst,n)
    if call<9 then for _=1,n do lines[#lines+1]=' DROP.'..dst end end
  end
  lines[#lines+1]=(' RET.%s %d %d'):format(dst,n,n)
  lines[#lines+1]=('.function echo %d %d %s %s'):format(n,n,kinds,kinds)
  lines[#lines+1]=' CGETR.'..source..' 0 '..n
  lines[#lines+1]=(' RET.%s %d %d'):format(source,n,n)
  lines[#lines+1]='.export main'
  local args,expected={},{}
  for i=1,n do args[i]=101+17*(i-1);expected[i]=args[i]+(i==n and 9 or 0) end
  compare(assemble('captured-wide-results-'..dst..source,lines),args,table.concat(expected,' ')..'\n')
end end

-- Both branch operands remain live after their symbolic pops. Capturing B in
-- r0 must not let materialization of a constant A operand reuse that register.
local captured_branch=assemble('captured-branch',{
  '.function main 1 1',' PUSH.A 101',' CGET.B 0',' BEQ.A equal',
  ' PUSH.A 42',' RET.A 1 1','equal:',' PUSH.A 99',' RET.A 1 1','.export main',
})
compare(captured_branch,{102},'42\n')
-- Prime structured reads before escaped/partial/overlapping writes. Both
-- direct frame reads and pointer reads must observe the new bytes after calls.
local aliases={
 {'escaped-caller-block','41\n',[[
.profile memory
.function main 0 1 - i
 CALLOC 24
 PUSH.A 17
 FST64.A 24
 FLD64.B 24
 DROP.B
 FADDR.B 24
 CALL.B writer 1
 FLD64.A 24
 CFREE 24
 RET.A 0 1
.function writer 1 0 a -
 CGET.A 0
 PUSH.B 41
 ST64.A 0
 RET.B 1 0
 ]]},
 {'partial-frame-write','287462724 287462724\n',[[
.profile memory
.function main 0 2 - ii
 CALLOC 24
 PUSH.A 287454020
 FST64.A 24
 FLD64.B 24
 DROP.B
 FADDR.A 24
 PUSH.B 85
 ST8.A 1
 FADDR.B 24
 LD64.B 0
 FLD64.B 24
 CFREE 24
 RET.B 0 2
 ]]},
 {'overlapping-frame-copy','11 11 22\n',[[
.profile memory
.function main 0 3 - iii
 CALLOC 24
 PUSH.A 11
 FST64.A 24
 PUSH.B 22
 FST64.B 16
 PUSH.A 33
 FST64.A 8
 FLD64.B 24
 DROP.B
 FLD64.B 16
 DROP.B
 FLD64.B 8
 DROP.B
 FADDR.A 16
 FADDR.B 24
 MEMCPY.A 16
 FLD64.B 24
 FLD64.B 16
 FLD64.B 8
 CFREE 24
 RET.B 0 3
 ]]}
}
for _,case in ipairs(aliases) do for mirror=0,1 do
 local source=case[3]
 if mirror==1 then source=source:gsub('%.([AB])',function(bank)return bank=='A' and '.B' or '.A' end) end
 local lines={};for line in source:gmatch('[^\n]+') do lines[#lines+1]=line end
 compare(assemble(case[1]..'-'..mirror,lines),{},case[2],64)
end end
local trap_source=[[
.function main 1 3
 PUSH.A 111
 PUSH.B 222
 PUSH.B 10
 CGET.B 0
 CALL.B divide 2
 MOVE.A
 RET.B 1 3
.function divide 2 1
 CGET.A 0
 CGET.B 1
 DIVU.A
 RET.A 2 1
.export main
]]
for mirror=0,1 do
 local source=mirror==0 and trap_source or trap_source:gsub('%.([AB])',function(bank)return bank=='A' and '.B' or '.A' end)
 local lines={};for line in source:gmatch('[^\n]+') do lines[#lines+1]=line end
 local path=assemble('callee-trap-'..mirror,lines)
 compare(path,{2},'222 5 111\n',64)
 compare(path,{0},nil,64,'abort')
end
assert(os.execute('rm -rf '..string.format('%q',tmp))==0)
print(('validated %d continuation executions: A/B routing, live caller state, register/home arguments, result arities and stack exhaustion'):format(checks))
