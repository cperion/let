#ifndef ABC_DYNAMIC_H
#define ABC_DYNAMIC_H
#include "vm_internal.h"
#include "scalar_rules.h"
#include "generated/scalar_ops.h"


static inline unsigned abc_primitive_tag(unsigned primitive) {
    static const uint8_t tags[]={ABC_ANY_UNIT,ABC_ANY_BOOL,ABC_ANY_U8,ABC_ANY_U16,ABC_ANY_U32,ABC_ANY_U64,ABC_ANY_I32,ABC_ANY_I64,ABC_ANY_F64,ABC_ANY_STRING,255,ABC_ANY_WORD};
    return primitive<sizeof tags?tags[primitive]:255;
}
/* Descriptor projection, independent of cache/register placement. */
enum { ABC_ANY_LAYOUT_INVALID, ABC_ANY_LAYOUT_SCALAR, ABC_ANY_LAYOUT_IDENTITY, ABC_ANY_LAYOUT_OBJECT };
typedef struct { unsigned form,tag,cells,object_kind,exact_descriptor,address; size_t offset[2]; unsigned width[2]; } abc_any_layout;
static inline abc_any_layout abc_any_descriptor_layout(const abc_descriptor *d) {
    abc_any_layout l={0};l.cells=1;
    if(d->tag==ABC_DESC_PRIMITIVE){
        unsigned p=d->payload[0];l.tag=abc_primitive_tag(p);
        if(p==ABC_PRIM_ANY||p==ABC_PRIM_WORD){l.form=ABC_ANY_LAYOUT_IDENTITY;return l;}
        if(p!=ABC_PRIM_STRING){l.form=ABC_ANY_LAYOUT_SCALAR;l.cells=p!=ABC_PRIM_UNIT;return l;}
        l.form=ABC_ANY_LAYOUT_OBJECT;l.object_kind=ABC_ANY_STRING;l.cells=2;l.address=1;
        l.offset[0]=sizeof(abc_object)+offsetof(string_box,bytes);l.offset[1]=sizeof(abc_object)+offsetof(string_box,length);l.width[1]=4;return l;
    }
    if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE){
        if(d->tag==ABC_DESC_POINTER&&d->payload[0]==0){l.form=ABC_ANY_LAYOUT_SCALAR;l.tag=ABC_ANY_PTR;return l;}
        if(d->payload[0]!=2)return l;
        l.form=ABC_ANY_LAYOUT_OBJECT;l.tag=ABC_ANY_AGGREGATE;l.object_kind=ABC_OBJECT_MANAGED;l.exact_descriptor=1;
        l.cells=d->tag==ABC_DESC_SLICE?2:1;l.offset[0]=sizeof(abc_object)+offsetof(managed_box,address);l.width[0]=8;
        l.offset[1]=sizeof(abc_object)+offsetof(managed_box,length);l.width[1]=8;return l;
    }
    if(d->tag==ABC_DESC_RECORD||d->tag==ABC_DESC_ARRAY||d->tag==ABC_DESC_SUM){
        l.form=ABC_ANY_LAYOUT_OBJECT;l.tag=ABC_ANY_AGGREGATE;l.object_kind=ABC_ANY_AGGREGATE;l.exact_descriptor=1;l.address=1;
        l.offset[0]=sizeof(abc_object)+offsetof(aggregate_box,storage);
    }
    return l;
}
/* Allocation only: tag checks and arithmetic never enter this boundary. */
uint64_t vm_scalar_allocate(uint64_t *asp,uint64_t *bsp,uint64_t *csp,unsigned tag,uint64_t bits);

uint64_t abc_any_unit(void);
unsigned abc_any_tag(const abc_vm *vm,uint64_t value);
abc_status vm_dynamic(abc_run *run,const uint8_t *p,uint32_t pc);
void abc_dynamic_collect(abc_vm *vm);
void vm_collect_native(uint64_t *asp,uint64_t *bsp,uint64_t *csp,uint64_t *registers);
void abc_dynamic_destroy(abc_vm *vm);

#endif

