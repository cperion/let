-- Generate cache-transition validation cases and their independent logical-stack oracle.
local root=(arg[0]:match('^(.*)/tools/[^/]+$') or '.')
package.path=root..'/gen/?.lua;'..package.path
local cache=require('cache')
local asm_path,oracle_path=assert(arg[1]),assert(arg[2])
local asm,oracle={},{}
local function push(t,v) t[#t+1]=v end
local function pop(t) local v=t[#t]; t[#t]=nil; return v end
local operations={
  {'push_a','PUSH.A 99',function(a) push(a,99) end},
  {'push_b','PUSH.B 98',function(_,b) push(b,98) end},
  {'dup_a','DUP.A',function(a) push(a,a[#a]) end,function(a) return #a>0 end},
  {'dup_b','DUP.B',function(_,b) push(b,b[#b]) end,function(_,b) return #b>0 end},
  {'drop_a','DROP.A',function(a) pop(a) end,function(a) return #a>0 end},
  {'drop_b','DROP.B',function(_,b) pop(b) end,function(_,b) return #b>0 end},
  {'copy_ab','COPY.AB',function(a,b) push(b,a[#a]) end,function(a) return #a>0 end},
  {'copy_ba','COPY.BA',function(a,b) push(a,b[#b]) end,function(_,b) return #b>0 end},
  {'move_ab','MOVE.AB',function(a,b) push(b,pop(a)) end,function(a) return #a>0 end},
  {'move_ba','MOVE.BA',function(a,b) push(a,pop(b)) end,function(_,b) return #b>0 end},
  {'cpush_a','CPUSH.A',function(a,_,c) push(c,pop(a)) end,function(a) return #a>0 end},
  {'cpush_b','CPUSH.B',function(_,b,c) push(c,pop(b)) end,function(_,b) return #b>0 end},
  {'cget_a','CGET.A 0',function(a,_,c) push(a,c[#c]) end,function(_,_,c) return #c>0 end},
  {'cget_b','CGET.B 0',function(_,b,c) push(b,c[#c]) end,function(_,_,c) return #c>0 end},
  {'cpop','CPOP',function(_,_,c) pop(c) end,function(_,_,c) return #c>0 end},
}
local cases=0
for si,s in ipairs(cache.states()) do
  for _,op in ipairs(operations) do
    local a,b,c={},{},{}
    for i=1,s.c do push(c,10+i) end
    for i=1,s.a do push(a,30+i) end
    for i=1,s.b do push(b,50+i) end
    if not op[4] or op[4](a,b,c) then
      local name=('s%02d_%s'):format(si-1,op[1]); cases=cases+1
      local header=#asm+1; push(asm,'')
      for i=1,s.c do push(asm,(' PUSH.A %d'):format(10+i)); push(asm,' CPUSH.A') end
      for i=1,s.a do push(asm,(' PUSH.A %d'):format(30+i)) end
      for i=1,s.b do push(asm,(' PUSH.B %d'):format(50+i)) end
      push(asm,' '..op[2]); op[3](a,b,c)
      while #b>0 do push(asm,' MOVE.BA'); push(a,pop(b)) end
      while #c>0 do push(asm,' CGET.A 0'); push(a,c[#c]); push(asm,' CPOP'); pop(c) end
      push(asm,(' RET 0 %d'):format(#a)); push(asm,'.export '..name)
      asm[header]=('.function %s 0 %d'):format(name,#a)
      local row={name,tostring(#a)}; for _,v in ipairs(a) do row[#row+1]=tostring(v) end; push(oracle,table.concat(row,' '))
    end
  end
end
local f=assert(io.open(asm_path,'wb')); assert(f:write(table.concat(asm,'\n'),'\n')); assert(f:close())
f=assert(io.open(oracle_path,'wb')); assert(f:write(table.concat(oracle,'\n'),'\n')); assert(f:close())
io.stdout:write(('generated %d cache-transition cases\n'):format(cases))

