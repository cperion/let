#include "native_emit.h"
#include "generated/stencils.h"
#include "generated/execution_forms.h"

_Static_assert(sizeof stencils/sizeof stencils[0]==ABC_FORM_COUNT,"native form coverage");
typedef struct { uint8_t *site; int32_t addend; uint8_t kind; } NativePatch;
_Static_assert(sizeof(NativePatch)<=sizeof(abc_native_patch),"native relocation token size");

static void patch(uint8_t *site,unsigned kind,int32_t addend,int64_t target) {
    if(kind==RPC32){int32_t value=(int32_t)(target+addend-(int64_t)(intptr_t)site);memcpy(site,&value,4);}
    else if(kind==R32){int32_t value=(int32_t)(target+addend);memcpy(site,&value,4);}
    else if(kind==R8){int8_t value=(int8_t)(target+addend);memcpy(site,&value,1);}
    else {int64_t value=target+addend;memcpy(site,&value,8);}
}
static void reference(abc_native_patch *out,uint8_t *site,const Reloc *r) {
    NativePatch p={0};p.site=site;p.addend=r->addend;p.kind=(uint8_t)r->kind;
    memset(out,0,sizeof *out);memcpy(out,&p,sizeof p);
}
int abc_native_patch_present(const abc_native_patch *reference) {
    NativePatch p;memcpy(&p,reference,sizeof p);return p.site!=NULL;
}
void abc_native_bind(const abc_native_patch *reference,uint64_t value) {
    NativePatch p;memcpy(&p,reference,sizeof p);patch(p.site,p.kind,p.addend,(int64_t)value);
}
size_t abc_native_form_size(unsigned form) { return form<ABC_FORM_COUNT?stencils[form].len:0; }
static const Stencil *copy(uint8_t *at,unsigned form) {
    if(form>=ABC_FORM_COUNT)return NULL;
    const Stencil *s=&stencils[form];memcpy(at,s->code,s->len);return s;
}
int abc_native_emit_simple(uint8_t *at,unsigned form,uint64_t immediate,abc_native_patch *taken) {
    const Stencil *s=copy(at,form);if(!s)return 0;
    if(taken)memset(taken,0,sizeof *taken);
    for(unsigned i=0;i<s->nrel;i++){
        const Reloc *r=&s->rel[i];uint8_t *site=at+r->off;int64_t value;
        if(r->hole==HOLE_TAKEN){
            if(!taken||abc_native_patch_present(taken))return 0;
            reference(taken,site,r);continue;
        }
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)(at+s->len);
        else if(r->hole==HOLE_IMM)value=(int64_t)immediate;
        else if(r->hole==HOLE_IMM2)value=(int64_t)(immediate>>32);
        else if(r->hole==HOLE_FINAL||r->hole==HOLE_ERROR)value=(int64_t)immediate;
        else value=0;
        patch(site,r->kind,r->addend,value);
    }
    return 1;
}
int abc_native_emit_copy(uint8_t *at,unsigned destination,unsigned source,uint32_t bytes,abc_native_copy_fn copy_fn) {
    if(destination>=ABC_NATIVE_VALUE_REGISTERS||source>=ABC_NATIVE_VALUE_REGISTERS)return 0;
    const Stencil *s=copy(at,ABC_FORM_MEMCPY(destination,source));
    for(unsigned i=0;i<s->nrel;i++){
        const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)(at+s->len);
        else if(r->hole==HOLE_IMM)value=bytes;
        else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)copy_fn;
        else return 0;
        patch(at+r->off,r->kind,r->addend,value);
    }
    return 1;
}
int abc_native_emit_foreign(uint8_t *at,unsigned form,uint32_t argument_cells,
        abc_foreign_bridge_fn bridge,const abc_extern *external,abc_foreign_address target,uint64_t error) {
    if(form<ABC_FORM_FCALL_BASE||form>=ABC_FORM_FCALL_BASE+4)return 0;
    const Stencil *s=copy(at,form);
    for(unsigned i=0;i<s->nrel;i++){
        const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)(at+s->len);
        else if(r->hole==HOLE_IMM)value=argument_cells;
        else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)bridge;
        else if(r->hole==HOLE_STATE)value=(int64_t)(intptr_t)external;
        else if(r->hole==HOLE_BIAS)value=(int64_t)(intptr_t)target;
        else if(r->hole==HOLE_ERROR)value=(int64_t)error;
        else return 0;
        patch(at+r->off,r->kind,r->addend,value);
    }
    return 1;
}
int abc_native_emit_release_field(uint8_t *at,unsigned reg,uintptr_t callee,uint64_t offset,uint64_t ordinal) {
    if(reg>=ABC_NATIVE_VALUE_REGISTERS)return 0;
    const Stencil *s=copy(at,ABC_FORM_RELEASE_FIELD(reg));
    for(unsigned i=0;i<s->nrel;i++) {
        const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)(at+s->len);
        else if(r->hole==HOLE_FINAL)value=(int64_t)callee;
        else if(r->hole==HOLE_IMM)value=(int64_t)offset;
        else if(r->hole==HOLE_STATE)value=(int64_t)ordinal;
        else return 0;
        patch(at+r->off,r->kind,r->addend,value);
    }
    return 1;
}
int abc_native_emit_release_entry(uint8_t *at,uint64_t bytes,uint64_t b,uint64_t c,abc_native_patch *body) {
    const Stencil *s=copy(at,ABC_FORM_RELEASE_ENTRY);memset(body,0,sizeof *body);
    for(unsigned i=0;i<s->nrel;i++) {
        const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_TAKEN){if(abc_native_patch_present(body))return 0;reference(body,at+r->off,r);continue;}
        if(r->hole==HOLE_IMM)value=(int64_t)bytes;
        else if(r->hole==HOLE_BIAS)value=(int64_t)b;
        else if(r->hole==HOLE_IMM2)value=(int64_t)c;
        else return 0;
        patch(at+r->off,r->kind,r->addend,value);
    }
    return abc_native_patch_present(body);
}
int abc_native_emit_guard(uint8_t *at,unsigned stack,uint64_t bytes,abc_native_bounds_fn bounds,uint64_t error) {
    if(stack>=3)return 0;
    const Stencil *s=copy(at,ABC_FORM_GUARD(stack));
    for(unsigned i=0;i<s->nrel;i++){
        const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)(at+s->len);
        else if(r->hole==HOLE_IMM)value=(int64_t)bytes;
        else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)bounds;
        else if(r->hole==HOLE_ERROR)value=(int64_t)error;
        else return 0;
        patch(at+r->off,r->kind,r->addend,value);
    }
    return 1;
}
int abc_native_emit_resolve(uint8_t *at,abc_native_resolve_fn resolver,uint32_t pc,
        int64_t a_bytes,int64_t b_bytes,int64_t c_bytes) {
    const Stencil *s=copy(at,ABC_FORM_RESOLVE_INDIRECT);
    for(unsigned i=0;i<s->nrel;i++){
        const Reloc *r=&s->rel[i];int64_t value;
        switch(r->hole){
        case HOLE_NEXT:value=(int64_t)(intptr_t)(at+s->len);break;
        case HOLE_IMM:value=a_bytes;break;
        case HOLE_BIAS:value=b_bytes;break;
        case HOLE_IMM2:value=c_bytes;break;
        case HOLE_STATE:value=pc;break;
        case HOLE_FINAL:value=(int64_t)(intptr_t)resolver;break;
        default:return 0;
        }
        patch(at+r->off,r->kind,r->addend,value);
    }
    return 1;
}
int abc_native_emit_lazy(uint8_t *at,void *state,abc_native_prepare_fn prepare) {
    const Stencil *s=copy(at,ABC_FORM_LAZY_ENTRY);unsigned has_prepare=0;
    for(unsigned i=0;i<s->nrel;i++){
        const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_STATE)value=(int64_t)(intptr_t)state;
        else if(r->hole==HOLE_FINAL){value=(int64_t)(intptr_t)prepare;has_prepare=1;}
        else return 0;
        patch(at+r->off,r->kind,r->addend,value);
    }
    return has_prepare!=0;
}
