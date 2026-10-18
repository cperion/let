package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler');local S=require('let.schema');local Walk=require('let.walk')
local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*)/[^/]+$')
local file=assert(io.open(directory..'/fixture.lua'));local text=file:read('*a');file:close()
local unit=C.source{profile='slet',source=assert(text:match('local source=%[%[(.-)%]%]'))}
local needed={}
local function need(name)
 local node=unit.bindings[name];if not node or needed[node] then return end;needed[node]=true
 Walk.walk(node,{enter=function(n)if n.kind=='Reference' then need(n.name.text)end end})
end
need(assert(arg[1]))
local decls={};for _,d in ipairs(unit.ast.declarations) do if needed[d] then decls[#decls+1]=d end end
local old=unit.ast.export
local exported=getmetatable(old.functions[1])(unit.bindings[arg[1]].def.name)
unit.ast=getmetatable(unit.ast)(S.List(decls),getmetatable(old)(old.types,S.List{exported},old.results))
local start=os.clock();local typed=C.typed(unit,{staticMode='interpreted',staticOptimize=false})
local elapsed=os.clock()-start
local stats=typed.program.accessStats
print('entry',arg[1],'source declarations',#decls,'functions',#typed.functions,'cpu',elapsed,'heap MiB',collectgarbage('count')/1024)
for k,v in pairs(stats) do print('access',k,v) end
local fn={};local sumRoots,states,keyBytes=0,0,0
local function count(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end
for id,f in pairs(typed.program.flow.contexts) do
 local row=fn[f.fn_id] or {n=0,contexts={},inputs=0};fn[f.fn_id]=row;row.n=row.n+1
 row.contexts[S.encode(f.context)]=true;row.inputs=row.inputs+count(f.input)
 keyBytes=keyBytes+#id
 for _,st in pairs(f.before or {}) do states=states+1;sumRoots=sumRoots+count(st) end
 for _,st in pairs(f.after or {}) do states=states+1;sumRoots=sumRoots+count(st) end
end
local rows={};for name,row in pairs(fn) do row.name=name;rows[#rows+1]=row end;table.sort(rows,function(a,b)return a.n>b.n end)
print('state snapshots',states,'total snapshot root entries',sumRoots,'query key bytes',keyBytes)
collectgarbage('collect');print('retained Lua heap MiB',collectgarbage('count')/1024)
for _,r in ipairs(rows) do print('function',r.name,'queries',r.n,'call paths',count(r.contexts),'mean input roots',r.inputs/r.n) end
