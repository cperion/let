-- Generate the admitted private runtime holding operations. These are concrete
-- routines, not a holding-plan interpreter or a second executable IR. User type
-- specializations must supply their own generated routines before admission.
local dir=assert(arg[1],'output directory required')
local types={
 {name='local_bytes',kind='LOCAL',size='0',align='_Alignof(uint64_t)',holding='NONE'},
 {name='shared_bytes',kind='SHARED',size='0',align='_Alignof(uint64_t)',holding='NONE'},
 {name='local_owner',kind='LOCAL',size='sizeof(abc_owner *)',align='_Alignof(abc_owner *)',holding='OWNER'},
}
local h=assert(io.open(dir..'/type_ops.h','wb'))
h:write('#ifndef ABC_GENERATED_TYPE_OPS_H\n#define ABC_GENERATED_TYPE_OPS_H\n')
h:write('enum { ABC_TYPE_COPY_NONE, ABC_TYPE_COPY_OWNER };\nenum { ABC_TYPE_RELEASE_NONE, ABC_TYPE_RELEASE_OWNER };\nenum {\n')
for i,ty in ipairs(types) do h:write((' ABC_TYPE_%s=%d,\n'):format(ty.name:upper(),i-1)) end
h:write((' ABC_TYPE_COUNT=%d\n};\n'):format(#types))
h:write('extern const abc_type_ops abc_runtime_types[ABC_TYPE_COUNT];\n#endif\n')
assert(h:close())
local c=assert(io.open(dir..'/type_ops.c','wb'))
c:write('#include "owner.h"\n#include <stdlib.h>\n#include <string.h>\nconst abc_type_ops abc_runtime_types[ABC_TYPE_COUNT]={\n')
for _,ty in ipairs(types) do
 c:write((' {%s,%s,ABC_OWNER_%s,ABC_TYPE_COPY_%s,ABC_TYPE_RELEASE_%s},\n'):format(ty.size,ty.align,ty.kind,ty.holding,ty.holding))
end
c:write([[
};
void abc_type_initialize(const abc_type_ops *ops,void *payload){
 switch(ops->release_holdings){
 case ABC_TYPE_RELEASE_NONE: break;
 case ABC_TYPE_RELEASE_OWNER: {abc_owner *empty=NULL;memcpy(payload,&empty,sizeof empty);break;}
 default: abort(); /* private descriptor invariant; never a source abort */
 }
}
void abc_type_release(abc_owner_context *context,abc_owner *owner){
 switch(owner->ops->release_holdings){
 case ABC_TYPE_RELEASE_NONE: break;
 case ABC_TYPE_RELEASE_OWNER: {
  abc_owner *held;memcpy(&held,abc_owner_payload(owner),sizeof held);
  if(held)abc_owner_release(context,held);
  break;
 }
 default: abort();
 }
}
]])
assert(c:close())
local lua=assert(io.open(dir..'/type_ops.lua','wb'))
lua:write('-- Generated private layouts; not source Ty identities or serialized ISA kinds.\nreturn {')
for i,ty in ipairs(types) do lua:write(('%s=%d,'):format(ty.name,i-1)) end
lua:write('scope_header_cells=2,scope_slot_cells=1}\n');assert(lua:close())
