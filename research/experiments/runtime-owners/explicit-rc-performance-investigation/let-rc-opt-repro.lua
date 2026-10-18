package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local n=assert(tonumber(arg[1]));local direct=arg[2]=='direct'
local lines={'.profile foreign','.extern observe i -','.function body 1 1 i i',' CALLOC 8',' CFREE 8'}
for i=1,n do
 lines[#lines+1]=' CGET.A 0';lines[#lines+1]=' JZ.A skip_'..i
 lines[#lines+1]=' PUSH.A '..i;lines[#lines+1]=' FCALL.A observe';lines[#lines+1]='skip_'..i..':'
end
local effects=tonumber(arg[3]) or 0
for i=1,effects do lines[#lines+1]=' CGET.A 0';lines[#lines+1]=' FCALL.A observe' end
lines[#lines+1]=' PUSH.A 42';lines[#lines+1]=' RET.A 1 1'
if direct then lines[#lines+1]='.export body' else
 lines[#lines+1]='.function main 1 1 i i';lines[#lines+1]=' CGET.A 0';lines[#lines+1]=' CALL.A body 1';lines[#lines+1]=' RET.A 1 1';lines[#lines+1]='.export main'
end
local source=table.concat(lines,'\n')..'\n'
local path=('/tmp/let-rc-branch-%d-%s-%d'):format(n,direct and 'direct' or 'wrapper',effects)
local f=assert(io.open(path..'.abcasm','w'));f:write(source);f:close()
local bytes=require('assembler').assemble(source);f=assert(io.open(path..'.abc','wb'));f:write(bytes);f:close()
local t=os.clock();local out=require('let.optimize').optimize(bytes)
print('branches',n,'tail effects',effects,'direct',direct,'bytes',#bytes,'optimized bytes',#out,'CPU seconds',os.clock()-t)
