-- D07: active dependencies must not bring the retired collector back.
-- Historical prose/experiments are evidence, never build inputs. Run from repo root.
-- next/ is an independent experiment tree with its own copy of this audit.
package.path='tools/?.lua;'..package.path
local util=require('tool_util')
local function buildInput(path)
 return path=='Makefile' or path=='.gitmodules' or path:match('%.mk$')
  or path:match('^%.github/') or path:match('^tools/') or path=='lab/build.lua'
  or path:match('package[^/]*%.json$') or path:match('CMakeLists%.txt$')
end
local function violation(path,text)
 local name=path:lower()
 if name:find('whippet',1,true) then return 'retired collector path' end
 -- Documentation may describe the removed implementation or the no-GC contract.
 if name:match('%.md$') then return end
 local body=text:lower()
 if body:find('whippet',1,true) or body:find('bdw%-gc') or body:find('bdwgc',1,true)
  or body:find('%-lgc%f[^%w_]') or body:find('libgc[%.%-]')
  or body:find('%f[%w_]gc_[%w_]+') or body:find('[<"]gc[/.%-]') then
  return 'collector dependency/API reference'
 end
 for line in body:gmatch('[^\n]+') do
  if line:find('research/archive',1,true) then
   local comment=line:match('^%s*%-%-') or line:match('^%s*//') or line:match('^%s*/%*') or line:match('^%s*%*')
   if buildInput(path) or not comment then return 'archived implementation referenced by active code/tooling' end
  end
 end
end
local probes={
 {'vendor/whippet/README.md','',true},
 {'src/whippet_types.h','',true},
 {'Makefile','include vendor/whippet/embed.mk',true},
 {'.github/workflows/test.yml','run: apt install libgc-dev',true},
 {'src/old.c','#include <gc/gc.h>',true},
 {'src/old.c','gc_allocate(thread, size); gc_collect(thread);',true},
 {'src/old.c','GC_malloc(size);',true},
 {'src/old.c','gc_register_roots(roots);',true},
 {'Makefile','LDLIBS += -lgc -lm',true},
 {'Makefile','LDLIBS += -l:libgc.so',true},
 {'tools/build.lua','input = "research/archive/old/runtime.c"',true},
 {'src/old.c','#include "../research/archive/old/runtime.c"',true},
 {'Makefile','LDLIBS += -lgcc -lm -pthread',false},
 {'src/residual_builder.c','effect.calls = true; effect.safepoint = true;',false},
 {'frontend/tests/cost.lua','collectgarbage("collect")',false},
 {'frontend/tests/compiler.lua','-- historical evidence: research/archive/old/compiler.lua',false},
 {'docs/architecture.md','Whippet is removed; historical GC evidence is preserved.',false},
}
for _,p in ipairs(probes) do assert((violation(p[1],p[2])~=nil)==p[3],'dependency guard probe: '..p[1]..' '..p[2]) end
assert(os.execute('test ! -e vendor/whippet && test ! -L vendor/whippet')==0,'retired vendor/whippet path exists')
local ok,listing,err=util.capture({'find','.',
 '(','-path','./.git','-o','-path','./.jj','-o','-path','./.pi','-o','-path','./build','-o','-path','./research','-o','-path','./next',')','-prune','-o',
 '(','-type','f','-o','-type','l',')','-printf','%p\\0%l\\0'})
assert(ok,err)
local count,failures=0,{}
for entry,target in listing:gmatch('([^%z]+)%z([^%z]*)%z') do
 local path=entry:sub(3)
 -- This one test necessarily contains forbidden strings as negative controls.
 if path~='tools/validate_no_collector.lua' then
  local text=util.read(path);count=count+1
  local why=violation(path,text)
  if target~='' then why=why or violation(path,target) end
  if why then failures[#failures+1]=path..': '..why end
 end
end
table.sort(failures)
assert(#failures==0,table.concat(failures,'\n'))
print(('collector-free dependency audit: %d active files, %d negative/positive guard probes; archives/build artifacts excluded'):format(count,#probes))
