package.path='./?.lua;'..package.path
local catalog=require('gen.runtime_primitives')
local dir=assert(arg[1],'output directory required')
local h=assert(io.open(dir..'/runtime_primitives.h','wb'))
h:write('/* Generated from gen/runtime_primitives.lua. */\n#ifndef ABC_RUNTIME_PRIMITIVES_H\n#define ABC_RUNTIME_PRIMITIVES_H\n#include "internal.h"\n')
h:write('typedef struct { const char *name,*inputs,*results,*holding_inputs,*holding_results,*memory,*allocation,*failure,*suspension,*clobbers,*binding; } abc_primitive_info;\n')
h:write('enum {\n')
for _,p in ipairs(catalog.operations) do h:write((' ABC_PRIMITIVE_%s=%d,\n'):format(p.name:upper(),p.id)) end
h:write((' ABC_PRIMITIVE_COUNT=%d\n};\n'):format(#catalog.operations))
h:write('extern const abc_primitive_info abc_primitives[ABC_PRIMITIVE_COUNT];\nint abc_primitive_index(const char *name);\nint abc_primitive_reserved(const char *name);\nint abc_primitive_signature(const abc_extern *ext);\n#endif\n');assert(h:close())
local c=assert(io.open(dir..'/runtime_primitives.c','wb'))
c:write('#include "generated/runtime_primitives.h"\nconst abc_primitive_info abc_primitives[ABC_PRIMITIVE_COUNT]={\n')
for _,p in ipairs(catalog.operations) do
 local fields={};for _,f in ipairs{'symbol','inputs','results','holding_inputs','holding_results','memory','allocation','failure','suspension','clobbers','binding'} do fields[#fields+1]=string.format('%q',p[f]) end
 c:write(' {',table.concat(fields,','),'},\n')
end
c:write('};\nint abc_primitive_index(const char *name){for(unsigned i=0;i<ABC_PRIMITIVE_COUNT;i++)if(!strcmp(name,abc_primitives[i].name))return (int)i;return -1;}\n')
c:write('int abc_primitive_reserved(const char *name){return !strncmp(name,"__let_rt_",9);}\n')
c:write([[
static unsigned primitive_kind(char kind){return kind=='a'?ABC_KIND_ADDR:kind=='f'?ABC_KIND_FLOAT:ABC_KIND_INT;}
int abc_primitive_signature(const abc_extern *ext){
 int id=abc_primitive_index(ext->name);if(id<0)return 0;
 const abc_primitive_info *p=&abc_primitives[id];
 if(ext->arguments!=strlen(p->inputs)||ext->results!=strlen(p->results))return 0;
 for(unsigned i=0;i<ext->arguments;i++)if(ext->argument_kinds[i]!=primitive_kind(p->inputs[i]))return 0;
 return !ext->results||ext->result_kinds[0]==primitive_kind(p->results[0]);
}
]])
assert(c:close())
-- Literal data only, so compiler loading does not import build orchestration.
local lua=assert(io.open(dir..'/runtime_primitives.lua','wb'))
lua:write('-- Generated from gen/runtime_primitives.lua.\nreturn {\n')
for _,p in ipairs(catalog.operations) do
 lua:write((' [%q]={'):format(p.symbol))
 for _,f in ipairs{'name','inputs','results','holding_inputs','holding_results','memory','allocation','failure','suspension','clobbers','binding'} do lua:write(('%s=%q,'):format(f,p[f])) end
 lua:write('},\n')
end
lua:write('}\n');assert(lua:close())
