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
local function compare(path,args,expected,stack)
  local reference,reference_status
  for _,mode in ipairs{'interpreted','compiled','lazy'} do
    local cmd={abc,'run',path,'main','--'..mode,'--stack='..(stack or 1024)}
    for _,v in ipairs(args) do cmd[#cmd+1]=v end
    local out,status=run(cmd)
    if mode=='interpreted' then reference,reference_status=out,status
    else assert(out==reference and status==reference_status,mode..' '..path..': '..out..' != '..reference) end
    if expected then assert(status==0 and out==expected,mode..' '..path..': '..out)
    else assert(status~=0 and out:match('stack'),out) end
    checks=checks+1
  end
end
-- Both result destinations, register/home arguments, zero/single/multi results,
-- and live caller values on both operand stacks. Nonzero A/B/C rebases are all
-- required; the one-cell return must preserve r0 while loading its continuation.
for _,n in ipairs{1,2,9} do for results=0,2 do for _,dst in ipairs{'A','B'} do
  local lines={('.function recurse %d %d'):format(n,results),' CGET.A 0',' JZ.A base',
    ' PUSH.A 101',' PUSH.B 202',' CGET.A 0',' SUBI.A 1'}
  for j=1,n-1 do lines[#lines+1]=' CGET.A '..j end
  lines[#lines+1]=(' CALL.%s recurse %d'):format(dst,n)
  local other=dst=='A' and 'B' or 'A'
  if results==2 then
    lines[#lines+1]=' PUSH.'..other..' 42';lines[#lines+1]=' BEQ pair_ok';lines[#lines+1]=' ABORT 1';lines[#lines+1]='pair_ok:'
  end
  if results>=1 then
    lines[#lines+1]=' CGET.'..other..' 0';lines[#lines+1]=' SUBI.'..other..' 1'
    lines[#lines+1]=' BEQ result_ok';lines[#lines+1]=' ABORT 2';lines[#lines+1]='result_ok:'
  end
  for _,line in ipairs{' PUSH.A 202',' BEQ b_ok',' ABORT 3','b_ok:',
    ' PUSH.B 101',' BEQ a_ok',' ABORT 4','a_ok:','base:'} do lines[#lines+1]=line end
  for j=1,n-1 do
    lines[#lines+1]=' CGET.A '..j;lines[#lines+1]=' PUSH.B '..(10+j)
    lines[#lines+1]=' BEQ arg'..j;lines[#lines+1]=' ABORT 5';lines[#lines+1]='arg'..j..':'
  end
  if results>=1 then lines[#lines+1]=' CGET.A 0' end
  if results==2 then lines[#lines+1]=' PUSH.A 42' end
  lines[#lines+1]=(' RET %d %d'):format(n,results);lines[#lines+1]='.export main recurse'
  local path=assemble(('recursive-%d-%d-%s'):format(n,results,dst),lines)
  for _,depth in ipairs{0,1,6} do
    local args={depth};for j=1,n-1 do args[#args+1]=10+j end
    local expected=results==0 and '\n' or tostring(depth)..(results==2 and ' 42\n' or '\n')
    compare(path,args,expected)
  end
  local args={64};for j=1,n-1 do args[#args+1]=10+j end
  compare(path,args,nil,32)
end end end
-- A tail transfer keeps the original continuation and CALL.B destination
-- while crossing a mutually recursive SCC.
local mutual=assemble('mutual-tail',{
  '.function f 1 1',' CGET.A 0',' JZ.A base',' CGET.A 0',' SUBI.A 1',
  ' CALL.B g 1',' MOVE.BA',' ADDI.A 1',' RET 1 1','base:',' PUSH.A 0',' RET 1 1',
  '.function g 1 1',' CGET.A 0',' TCALL f 1 1','.export main f',
})
for _,depth in ipairs{0,1,6,20} do compare(mutual,{depth},depth..'\n') end
compare(mutual,{64},nil,32)

-- Zero-argument recursive activation still needs its own continuation cell.
local zero=assemble('zero-arguments',{
  '.profile memory','.datazero 8','.function recurse 0 1 - i',
  ' .loadkind int',' GLD64 0',' DUP.A',' JZ.A base',' SUBI.A 1',' GST64 0',
  ' CALL.A recurse 0',' ADDI.A 1',' RET 0 1','base:',' RET 0 1',
  '.function main 0 1 - i',' PUSH.A 6',' GST64 0',' CALL.B recurse 0',
  ' MOVE.BA',' RET 0 1','.export main',
})
compare(zero,{},'6\n')
assert(os.execute('rm -rf '..string.format('%q',tmp))==0)
print(('validated %d continuation executions: A/B routing, live caller state, register/home arguments, result arities and stack exhaustion'):format(checks))
