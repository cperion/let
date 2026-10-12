/* Link-time tripwires for both concrete and symbolic scalar execution. */
#include "dynamic.h"
#include <stdio.h>
#include <stdlib.h>
static void check_scalar(const abc_run *r,const uint8_t *p,uint32_t pc) {
    unsigned op=p[1];int scalar=op>=EXT_DNEG&&op<=EXT_DREQUIRE_BOOL;
    if(op==EXT_ANY_BOX||op==EXT_ANY_CAST||op==EXT_ANY_IS){
        const abc_descriptor *d=&r->m->descriptors[abc_u32(p+2)];
        scalar=op!=EXT_ANY_BOX||(d->tag==ABC_DESC_PRIMITIVE&&d->payload[0]!=ABC_PRIM_STRING);
    }
    if(scalar){fprintf(stderr,"unexpected scalar runtime handler: selector %u at %u\n",op,pc);exit(99);}
}
abc_status __real_vm_dynamic(abc_run *,const uint8_t *,uint32_t);
abc_status __wrap_vm_dynamic(abc_run *r,const uint8_t *p,uint32_t pc) {
    check_scalar(r,p,pc);return __real_vm_dynamic(r,p,pc);
}
uint64_t __real_vm_dynamic_native(uint64_t **,uint64_t **,uint64_t **,const uint8_t *,uint32_t);
uint64_t __wrap_vm_dynamic_native(uint64_t **a,uint64_t **b,uint64_t **c,const uint8_t *p,uint32_t pc) {
    check_scalar(abc_active_run,p,pc);return __real_vm_dynamic_native(a,b,c,p,pc);
}
uint64_t __real_vm_scalar_allocate(uint64_t *,uint64_t *,uint64_t *,unsigned,uint64_t);
uint64_t __wrap_vm_scalar_allocate(uint64_t *a,uint64_t *b,uint64_t *c,unsigned tag,uint64_t bits) {
    if(abc_active_run->v->mode!=ABC_EXEC_INTERPRETED&&getenv("ABC_TEST_NO_SCALAR_ALLOC")){
        fprintf(stderr,"unexpected compiled scalar allocation\n");exit(98);
    }
    if(getenv("ABC_TEST_COLLECT_SCALARS")&&abc_vm_request_collection(abc_active_run->v,NULL)!=ABC_OK){fprintf(stderr,"collection request failed\n");exit(97);}
    return __real_vm_scalar_allocate(a,b,c,tag,bits);
}
