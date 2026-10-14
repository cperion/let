#ifndef ABC_VM_INTERNAL_H
#define ABC_VM_INTERNAL_H
#include "internal.h"
#include "execution_context.h"
#include <math.h>

typedef struct { uint32_t entry,max_a,max_b,max_c; } abc_call_info;
typedef struct abc_foreign_binding { char *name; abc_foreign_address address; struct abc_foreign_binding *next; } abc_foreign_binding;
typedef struct abc_image {
    const abc_module *module; uint8_t *bytes;
    uint32_t *direct_callees, *indirect_site_states;
    abc_call_info *call_info; size_t bytes_mapping_size; uint64_t transitions;
    abc_foreign_address *foreign; abc_foreign_bridge_fn *foreign_bridges;
    struct abc_execution_image *execution;
    abc_type_ops *type_ops;
    struct abc_image *next;
} abc_image;
struct abc_vm {
    abc_exec_context root;
    abc_worker worker;
    abc_execution_mode mode; abc_image *images;
    abc_foreign_binding *foreign_bindings;
    unsigned executing;
};
abc_status vm_resolve_indirect(abc_exec_context *run, uint32_t pc, uint64_t target, uint32_t *callee_index);
abc_status vm_foreign(abc_exec_context *run, unsigned extern_index, unsigned selected_stack, uint32_t pc);
abc_foreign_address abc_foreign_lookup(const abc_vm *vm,const char *name);
abc_status abc_context_reserve(abc_exec_context *,size_t,abc_error *);
abc_status abc_type_bind(abc_exec_context *,size_t,size_t,unsigned,uint64_t,uint64_t,const abc_type_ops **);
abc_status abc_type_publish(abc_exec_context *);
size_t vm_depth(const abc_exec_context *v,char stack);
uint64_t *vm_at(abc_exec_context *v,char stack,size_t depth);
void vm_push(abc_exec_context *v,char stack,uint64_t value);
uint64_t vm_pop(abc_exec_context *v,char stack);
void vm_publish_all(abc_exec_context *v);
uint64_t vm_sar(uint64_t x,uint64_t n);
uint64_t vm_pow(uint64_t x,uint64_t n);
int32_t abc_i32_from_u64(uint64_t x);
static inline double vm_float(uint64_t x) { double d; memcpy(&d,&x,8); return d; }
static inline uint64_t vm_float_bits(double d) { uint64_t x; memcpy(&x,&d,8); return x; }
static inline uint64_t vm_fadd(uint64_t x,uint64_t y) { return vm_float_bits(vm_float(x)+vm_float(y)); }
static inline uint64_t vm_fsub(uint64_t x,uint64_t y) { return vm_float_bits(vm_float(x)-vm_float(y)); }
static inline uint64_t vm_fmul(uint64_t x,uint64_t y) { return vm_float_bits(vm_float(x)*vm_float(y)); }
static inline uint64_t vm_fdiv(uint64_t x,uint64_t y) { return vm_float_bits(vm_float(x)/vm_float(y)); }
static inline int vm_flt(uint64_t x,uint64_t y) { return vm_float(x)<vm_float(y); }
static inline int vm_fle(uint64_t x,uint64_t y) { return vm_float(x)<=vm_float(y); }
static inline int vm_feq(uint64_t x,uint64_t y) { return vm_float(x)==vm_float(y); }
static inline uint64_t vm_u2f_bits(uint64_t v,uint64_t sign) {
    if(!v)return sign; unsigned p=63u-(unsigned)__builtin_clzll(v); uint64_t q;
    if(p<=52) q=v<<(52-p); else { unsigned shift=p-52; q=v>>shift; uint64_t rem=v&((UINT64_C(1)<<shift)-1),half=UINT64_C(1)<<(shift-1); if(rem>half||(rem==half&&(q&1))) { q++; if(q==UINT64_C(1)<<53){q>>=1;p++;} } }
    return sign|((uint64_t)(p+1023)<<52)|(q&UINT64_C(0x000fffffffffffff));
}
static inline uint64_t vm_i2fs(uint64_t x) { uint64_t sign=x>>63?UINT64_C(0x8000000000000000):0; return vm_u2f_bits(sign?0-x:x,sign); }
static inline uint64_t vm_i2fu(uint64_t x) { return vm_u2f_bits(x,0); }
static inline int vm_f2is(uint64_t x,uint64_t *out) { double d=vm_float(x); if(!isfinite(d)||d<-0x1p63||d>=0x1p63)return 0; *out=(uint64_t)(int64_t)d; return 1; }
static inline int vm_f2iu(uint64_t x,uint64_t *out) { double d=vm_float(x); if(!isfinite(d)||d<0||d>=0x1p64)return 0; *out=(uint64_t)d; return 1; }

#endif

