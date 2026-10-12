-- Real recursive calls force the native return protocol, rather than inlining.
local directory=arg[0]:match('^(.*)/[^/]*$') or '.'
package.path=directory..'/?.lua;'..package.path
local assembler,util=require('assembler'),require('tool_util')
local runtime=arg[1] or 'build/abc-runtime'
local cases=0
local function check(name,source,expected,capacity)
 local path=os.tmpname()
 local success,message=pcall(function()
  util.write(path,assembler.assemble(source))
  for _,mode in ipairs{'interpreted','compiled','lazy','jit=threaded'} do
   local command={runtime,'run',path,'--'..mode}
   if capacity then command[#command+1]='--stack='..capacity end
   local valid,result,error=util.capture(command)
   if expected==false then
    assert(not valid and error:find('stack',1,true),name..'/'..mode..': expected stack trap, got '..result..error)
   else
    assert(valid,name..'/'..mode..': '..error)
    assert(result:match('^%s*(.-)%s*$')==expected,name..'/'..mode..': '..result)
   end
   cases=cases+1
   if capacity and expected~=false then
    command[#command]='--stack='..(capacity-1)
    local too_small,_,diagnostic=util.capture(command)
    assert(not too_small and diagnostic:find('stack',1,true),name..'/'..mode..': missing capacity trap')
    cases=cases+1
   end
  end
 end)
 os.remove(path);assert(success,message)
end
for _,caller in ipairs{'A','B'} do for _,source in ipairs{'A','B'} do
 local main_collect=caller=='A' and 'MOVE.B' or 'CPUSHN.B 3\nCGETR.A 0 3\nCPOP\nCPOP\nCPOP'
 local return_collect=caller==source and '' or ('CPUSHN.%s 2\nCGETR.%s 0 2\nCPOP\nCPOP'):format(caller,source)
 check('CALL.'..caller..'/RET.'..source,([[.function main 0 4
 PUSH.A 111
 PUSH.B 112
 PUSH.%s 2
 CALL.%s recur 1
 %s
 RET.A 0 4
 .function recur 1 2
 CGET.A 0
 JZ.A base
 CGET.%s 0
 ADDI.%s -1
 CALL.%s recur 1
 %s
 RET.%s 1 2
 base:
 PUSH.%s 7
 PUSH.%s 3
 RET.%s 1 2
 ]]):format(caller,caller,main_collect,caller,caller,caller,return_collect,source,source,source,source),
 caller=='A' and '111 7 3 112' or '111 112 7 3')
end end
-- Cross both the seven- and eight-register argument boundary. Recursive calls
-- must agree on which arguments are carried and which have C homes.
for _,bank in ipairs{'A','B'} do
 local source={('.function main 0 1\nPUSH.%s 4'):format(bank)}
 for i=1,8 do source[#source+1]=('PUSH.%s %d'):format(bank,i) end
 source[#source+1]=('CALL.%s recur 9\nRET.%s 0 1\n.function recur 9 1\nCGET.A 0\nJZ.A base\nCGET.%s 0\nADDI.%s -1'):format(bank,bank,bank,bank)
 for i=1,8 do source[#source+1]=('CGET.%s %d'):format(bank,i) end
 source[#source+1]=('CALL.%s recur 9\nRET.%s 9 1\nbase:\nPUSH.A 0'):format(bank,bank)
 for i=1,8 do source[#source+1]=('CGET.B %d\nADD.A'):format(i) end
 source[#source+1]='RET.A 9 1'
 check('nine-argument recursion '..bank,table.concat(source,'\n')..'\n','36')
end
-- One compiled callee has A and B return paths; its continuation is unchanged.
check('mixed return sources',[[.function main 0 2
 PUSH.B 1
 CALL.B mixed 1
 RET.B 0 2
 .function mixed 1 2
 CGET.B 0
 JZ.B base
 PUSH.A 0
 CALL.A mixed 1
 RET.A 1 2
 base:
 PUSH.B 7
 PUSH.B 3
 RET.B 1 2
]],'7 3')
-- A is full throughout the B-only call. No A scratch result region is legal.
local prefix={};for index=1,8 do prefix[#prefix+1]='PUSH.A '..index end
local drop={};for index=1,8 do drop[#drop+1]='DROP.A' end
check('full opposite prefix',('.function main 0 1\n%s\nPUSH.B 2\nCALL.B recur 1\n%s\nMOVE.B\nSUB.B\nRET.B 0 1\n'):format(table.concat(prefix,'\n'),table.concat(drop,'\n'))..[[
 .function recur 1 2
 CGET.B 0
 JZ.B base
 CGET.B 0
 ADDI.B -1
 CALL.B recur 1
 RET.B 1 2
 base:
 PUSH.B 7
 PUSH.B 3
 RET.B 1 2
]],'4',8)
check('single register result',[[.function main 0 1
 PUSH.B 3
 CALL.B recur 1
 RET.B 0 1
 .function recur 1 1
 CGET.B 0
 JZ.B base
 CGET.B 0
 ADDI.B -1
 CALL.B recur 1
 ADDI.B 1
 RET.B 1 1
 base:
 PUSH.B 7
 RET.B 1 1
]],'10')
check('tail preserves destination with changed C argument count',[[.function main 0 2
 PUSH.B 1
 CALL.B recur 1
 RET.B 0 2
 .function recur 1 2
 CGET.B 0
 JZ.B base
 CGET.B 0
 ADDI.B -1
 CALL.B recur 1
 RET.B 1 2
 base:
 PUSH.A 17
 PUSH.A 19
 TCALL.A leaf 1 2
 .function leaf 2 2
 PUSH.A 7
 PUSH.A 3
 RET.A 2 2
]],'7 3')
check('restore live caller C prefix',[[.function main 0 4
 PUSH.A 31
 CPUSH.A
 PUSH.B 41
 CPUSH.B
 PUSH.B 1
 CALL.B recur 1
 CGET.A 0
 CGET.A 1
 CPUSHN.B 2
 CGETR.A 0 2
 CPOP
 CPOP
 RET.A 2 4
 .function recur 1 2
 CGET.B 0
 JZ.B base
 CGET.B 0
 ADDI.B -1
 CALL.B recur 1
 RET.B 1 2
 base:
 PUSH.B 7
 PUSH.B 3
 RET.B 1 2
]],'41 31 7 3')
check('host HALT.B',[[.function main 0 2
 PUSH.B 7
 PUSH.B 3
 HALT.B
]],'7 3')
check('host RET.B',[[.function main 0 2
 PUSH.B 7
 PUSH.B 3
 RET.B 0 2
]],'7 3')
local function collect(bank,results)
 if bank=='A' then return 'MOVE.B' end
 local count=results+1
 return ('CPUSHN.B %d\nCGETR.A 0 %d\n'):format(count,count)..string.rep('CPOP\n',count)
end
for _,caller in ipairs{'A','B'} do for _,source in ipairs{'A','B'} do
 local opposite=caller=='A' and 'B' or 'A'
 check('indirect '..caller..' return '..source,([[.profile callables
 .datazero 16
 .codeaddr 0 target
 .signature sig 2 2 ai ii
 .function main 0 4 - iiii
 PUSH.A 111
 PUSH.B 112
 GADDR.%s 8
 PUSH.%s 9
 .loadkind addr
 GLD64.%s 0
 CALLI.%s 2 sig
 %s
 RET.A 0 4
 .function target 2 2 ai ii
 CGET.%s 1
 PUSH.%s 3
 RET.%s 2 2
 ]]):format(caller,caller,opposite,caller,collect(caller,2),source,source,source),
 caller=='A' and '111 9 3 112' or '111 112 9 3')
end end
for results=1,2 do
 for _,caller in ipairs{'A','B'} do for _,tail in ipairs{'A','B'} do for _,source in ipairs{'A','B'} do
  local opposite=tail=='A' and 'B' or 'A'
  local kinds=string.rep('i',results)
  local expected=caller=='A' and ('111 9'..(results==2 and ' 3' or '')..' 112 31')
      or ('111 112 9'..(results==2 and ' 3' or '')..' 31')
  check(('indirect tail %s/%s/%s/%d'):format(caller,tail,source,results),([[.profile callables
 .datazero 16
 .codeaddr 0 target
 .signature sig 2 %d ai %s
 .function main 0 %d - %s
 PUSH.A 31
 CPUSH.A
 PUSH.A 111
 PUSH.B 112
 GADDR.%s 8
 CALL.%s first 1
 %s
 CGET.A 0
 RET.A 1 %d
 .function first 1 %d a %s
 CGET.%s 0
 PUSH.%s 9
 .loadkind addr
 GLD64.%s 0
 TCALLI.%s 1 2 sig
 .function target 2 %d ai %s
 CGET.%s 1
 %s
 RET.%s 2 %d
 ]]):format(results,kinds,results+3,string.rep('i',results+3),caller,caller,
    collect(caller,results),results+3,results,kinds,tail,tail,opposite,tail,
    results,kinds,source,results==2 and 'PUSH.'..source..' 3' or '',source,results),expected)
 end end end
end
for _,caller in ipairs{'A','B'} do
 local opposite=caller=='A' and 'B' or 'A'
 check('indirect zero results '..caller,([[.profile callables
 .datazero 16
 .codeaddr 0 target
 .signature sig 1 0 a -
 .function main 0 2 - ii
 PUSH.A 111
 PUSH.B 112
 GADDR.%s 8
 .loadkind addr
 GLD64.%s 0
 CALLI.%s 1 sig
 MOVE.B
 RET.A 0 2
 .function target 1 0 a -
 RET.B 1 0
 ]]):format(caller,opposite,caller),'111 112')
end
check('deep indirect recursion',[[.profile callables
 .datazero 16
 .codeaddr 0 recur
 .signature sig 2 1 ai i
 .function main 0 1 - i
 GADDR.B 8
 PUSH.B 2000
 CALL.B recur 2
 RET.B 0 1
 .function recur 2 1 ai i
 CGET.B 1
 JZ.B base
 CGET.B 0
 CGET.B 1
 ADDI.B -1
 .loadkind addr
 GLD64.A 0
 CALLI.B 2 sig
 ADDI.B 1
 RET.B 2 1
 base:
 PUSH.B 0
 RET.B 2 1
]],'2000')
check('changed-arity indirect tail cycle at fixed capacity',[[.profile callables
 .datazero 24
 .codeaddr 0 first
 .codeaddr 8 second
 .signature two 2 1 ai i
 .signature one 1 1 a i
 .function main 0 1 - i
 GADDR.B 16
 PUSH.B 2000
 CALL.B first 2
 RET.B 0 1
 .function first 2 1 ai i
 CGET.B 1
 JZ.B first_done
 CGET.B 1
 ADDI.B -1
 CGET.A 0
 ST64.A 0
 CGET.B 0
 .loadkind addr
 GLD64.A 8
 TCALLI.B 2 1 one
 first_done:
 PUSH.B 7
 RET.B 2 1
 .function second 1 1 a i
 CGET.A 0
 LD64.A 0
 JZ.A second_done
 CGET.B 0
 CGET.B 0
 LD64.B 0
 .loadkind addr
 GLD64.A 0
 TCALLI.B 1 2 two
 second_done:
 PUSH.B 7
 RET.B 1 1
]],'7',4)
local capacity_source=[[.profile callables
 .datazero 16
 .codeaddr 0 small
 .signature sig 1 2 a ii
 .function main 0 2 - ii
 ]]..string.rep('PUSH.A 11\n',7)..[[
 GADDR.B 8
 .loadkind addr
 GLD64.A 0
 CALLI.B 1 sig
 ]]..string.rep('DROP.A\n',7)..[[
 RET.B 0 2
 .function small 1 2 a ii
 PUSH.B 7
 PUSH.B 3
 RET.B 1 2
 .function large 1 2 a ii
 ]]..string.rep('PUSH.A 1\n',9)..string.rep('DROP.A\n',9)..[[
 PUSH.B 7
 PUSH.B 3
 RET.B 1 2
 ]]
check('indirect capacity uses actual target',capacity_source,'7 3',8)
check('indirect target exceeds available capacity',capacity_source:gsub('0 small','0 large'),false,8)
print(('residual return transport: %d interpreter/eager/lazy/threaded checks passed'):format(cases))
