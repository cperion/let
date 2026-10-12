local directory=arg[1]
for _,op in ipairs{'FBLT','FBLE','FBEQ'} do for _,bank in ipairs{'A','B'} do
 local opposite=bank=='A' and 'B' or 'A'
 local path=directory..'/'..op..'-'..bank
 local f=assert(io.open(path..'.abcasm','wb'))
 f:write(('.profile memory\n.function main 2 1 ff i\n CGET.%s 0\n CGET.%s 1\n %s.%s yes\n PUSH.%s 0\n RET.%s 2 1\nyes: PUSH.%s 1\n RET.%s 2 1\n.export main\n'):format(bank,opposite,op,bank,bank,bank,bank,bank));f:close()
 assert(os.execute(('build/abc asm %q -o %q'):format(path..'.abcasm',path..'.abc'))==0)
 local left=op=='FBEQ' and '4611686018427387904' or '4609434218613702656'
 for _,mode in ipairs{'interpreted','compiled','lazy'} do
  io.write(op..'.'..bank..' '..mode..' expected=1: ');io.stdout:flush()
  os.execute(('build/abc run %q main %s 4611686018427387904 --%s 2>&1; printf "status=%%d\\n" "$?"'):format(path..'.abc',left,mode))
 end
end end
