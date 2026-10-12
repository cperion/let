#define _GNU_SOURCE
#include "execution_emit.h"
#include "native_emit.h"
#include "vm_internal.h"
#include "generated/execution_forms.h"
#include <sys/mman.h>
#include <unistd.h>

typedef struct NativeImage NativeImage;
typedef struct NativeLazy NativeLazy;
typedef struct { abc_native_patch patch; abc_exec_label target; uint32_t pc; } NativeFixup;
struct NativeLazy {
    uint64_t saved[12]; /* private stencil ABI: three pointers, eight values, status */
    NativeImage *owner; void *state; abc_exec_prepare_fn prepare;
    abc_exec_label entry,body; uint32_t pc; NativeLazy *next;
};
struct NativeImage {
    abc_exec_emitter emitter;
    uint8_t *base,*pos,*end,*stub; size_t mapping_size,placements;
    uint8_t **labels; size_t nlabels,label_cap;
    NativeFixup *fixups; size_t nfix,fix_cap;
    NativeLazy *lazy; unsigned writable;
};
static int grow(void **p,size_t *capacity,size_t need,size_t size) {
    if(need<=*capacity)return 1;
    if(need>SIZE_MAX/size)return 0;
    size_t n=*capacity?*capacity:32;
    while(n<need){if(n>SIZE_MAX/2){n=need;break;}n*=2;}
    if(n>SIZE_MAX/size)n=need;
    void *q=realloc(*p,n*size);if(!q)return 0;*p=q;*capacity=n;return 1;
}
static abc_status new_label(abc_exec_emitter *emitter,abc_exec_label *out,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;*out=ABC_EXEC_NO_LABEL;
    if(!n->writable)return abc_fail(error,ABC_INVALID,pc,"native image is published");
    if(n->nlabels>=ABC_EXEC_NO_LABEL||!grow((void **)&n->labels,&n->label_cap,n->nlabels+1,sizeof *n->labels))
        return abc_fail(error,ABC_NOMEM,pc,"execution label allocation failed");
    *out=(abc_exec_label)n->nlabels;n->labels[n->nlabels++]=NULL;return ABC_OK;
}
static abc_status bind_label(abc_exec_emitter *emitter,abc_exec_label label,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;
    if(!n->writable||label>=n->nlabels||n->labels[label])return abc_fail(error,ABC_INVALID,pc,"invalid or already bound execution label");
    n->labels[label]=n->pos;return ABC_OK;
}
static uintptr_t address(const abc_exec_emitter *emitter,abc_exec_label label) {
    const NativeImage *n=(const NativeImage *)emitter;return label<n->nlabels?(uintptr_t)n->labels[label]:0;
}
static abc_exec_storage storage(const abc_exec_emitter *emitter) {
    const NativeImage *n=(const NativeImage *)emitter;
    return (abc_exec_storage){n->base,(size_t)(n->pos-n->base),n->mapping_size};
}
static abc_status emit(abc_exec_emitter *emitter,unsigned form,const abc_exec_operands *op,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;size_t bytes=abc_native_form_size(form);
    if(!n->writable)return abc_fail(error,ABC_INVALID,pc,"native image is published");
    if(!bytes)return abc_fail(error,ABC_INVALID,pc,"invalid native execution form");
    n->placements++;
    if((size_t)(n->end-n->pos)<bytes)return abc_fail(error,ABC_NOMEM,pc,"compiled code exhausted after %zu bytes, %zu forms",(size_t)(n->pos-n->base),n->placements);
    if(op->target!=ABC_EXEC_NO_LABEL&&op->target>=n->nlabels)return abc_fail(error,ABC_INVALID,pc,"invalid target label");
    uint8_t *at=n->pos;n->pos+=bytes;abc_native_patch patch={0};int ok;
    const uint64_t *v=op->value;
    if(form>=ABC_FORM_MEMCPY_BASE&&form<ABC_FORM_MEMCPY_BASE+64){
        unsigned r=form-ABC_FORM_MEMCPY_BASE;
        ok=v[0]<=UINT32_MAX&&abc_native_emit_copy(at,r/8,r%8,(uint32_t)v[0],(abc_native_copy_fn)(uintptr_t)v[1]);
    }else if(form>=ABC_FORM_FCALL_BASE&&form<ABC_FORM_FCALL_BASE+4){
        ok=v[0]%8==0&&v[0]/8<=INT32_MAX&&abc_native_emit_foreign(at,form,(uint32_t)(v[0]/8),
            (abc_foreign_bridge_fn)(uintptr_t)v[1],(const abc_extern *)(uintptr_t)v[2],(abc_foreign_address)(uintptr_t)v[3],v[4]);
    }else if(form>=ABC_FORM_GUARD_BASE&&form<ABC_FORM_GUARD_BASE+3){
        ok=abc_native_emit_guard(at,form-ABC_FORM_GUARD_BASE,v[0],(const uint64_t *)(uintptr_t)v[1],v[2]);
    }else if(form==ABC_FORM_RESOLVE_INDIRECT){
        ok=abc_native_emit_resolve(at,(abc_native_resolve_fn)(uintptr_t)v[0],(uint32_t)v[1],(int64_t)v[2],(int64_t)v[3],(int64_t)v[4]);
    }else if(form==ABC_FORM_CALLOC){
        int64_t cells=(int64_t)v[1]/8;
        ok=v[0]<=UINT32_MAX&&v[1]%8==0&&cells>=INT32_MIN&&cells<=INT32_MAX&&
            abc_native_emit_simple(at,form,((uint64_t)(uint32_t)cells<<32)|(uint32_t)v[0],NULL);
    }else if(form>=ABC_FORM_REBASE_BASE&&form<ABC_FORM_REBASE_BASE+3){
        if((int64_t)v[0]<INT32_MIN||(int64_t)v[0]>INT32_MAX)return abc_fail(error,ABC_INVALID,pc,"native frame displacement out of range");
        ok=abc_native_emit_simple(at,form,v[0],NULL);
    }else if(form==ABC_FORM_LAZY_ENTRY){ok=0;
    }else ok=abc_native_emit_simple(at,form,v[0],op->target==ABC_EXEC_NO_LABEL?NULL:&patch);
    if(!ok)return abc_fail(error,ABC_INVALID,pc,"invalid bound native operands");
    if(op->target!=ABC_EXEC_NO_LABEL){
        if(!abc_native_patch_present(&patch))return abc_fail(error,ABC_INVALID,pc,"form does not accept a target");
        if(!grow((void **)&n->fixups,&n->fix_cap,n->nfix+1,sizeof *n->fixups))return abc_fail(error,ABC_NOMEM,pc,"native fixup allocation failed");
        n->fixups[n->nfix++]=(NativeFixup){patch,op->target,pc};
    }
    return ABC_OK;
}
static abc_status resolve_fixups(NativeImage *n,abc_error *error) {
    for(size_t i=0;i<n->nfix;i++){
        NativeFixup *f=&n->fixups[i];
        if(f->target>=n->nlabels||!n->labels[f->target])return abc_fail(error,ABC_INVALID,f->pc,"unbound execution target");
        abc_native_bind(&f->patch,(uintptr_t)n->labels[f->target]);
    }
    return ABC_OK;
}
static abc_status executable(NativeImage *n,uint32_t pc,abc_error *error) {
    __builtin___clear_cache((char *)n->base,(char *)n->base+n->mapping_size);
    if(mprotect(n->base,n->mapping_size,PROT_READ|PROT_EXEC))return abc_fail(error,ABC_IO,pc,"cannot protect compiled code");
    n->writable=0;return ABC_OK;
}
static abc_status publish(abc_exec_emitter *emitter,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;if(!n->writable)return ABC_OK;
    abc_status status=resolve_fixups(n,error);
    return status==ABC_OK?executable(n,pc,error):status;
}
static uint64_t prepare_lazy(uint64_t raw) {
    NativeLazy *s=(NativeLazy *)(uintptr_t)raw;NativeImage *n=s->owner;
    abc_error local,*error=abc_active_run&&abc_active_run->e?abc_active_run->e:&local;
    abc_status status=ABC_OK;
    if(mprotect(n->base,n->mapping_size,PROT_READ|PROT_WRITE))status=abc_fail(error,ABC_IO,s->pc,"cannot make lazy code writable");
    else {n->writable=1;status=s->prepare(s->state,error);}
    if(status==ABC_OK)status=resolve_fixups(n,error);
    if(status==ABC_OK&&(!address(&n->emitter,s->body)||!abc_native_activate_lazy(n->labels[s->entry],n->labels[s->body])))
        status=abc_fail(error,ABC_INVALID,s->pc,"invalid lazy activation target");
    abc_status protection=executable(n,s->pc,status==ABC_OK?error:NULL);
    if(status==ABC_OK)status=protection;
    s->saved[11]=status==ABC_OK?0:(uint64_t)status|((uint64_t)s->pc<<16);
    return address(&n->emitter,s->body);
}
static abc_status lazy_entry(abc_exec_emitter *emitter,abc_exec_label entry,abc_exec_label body,
        void *state,abc_exec_prepare_fn prepare,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;size_t bytes=abc_native_form_size(ABC_FORM_LAZY_ENTRY);
    if(!n->writable||entry>=n->nlabels||body>=n->nlabels||n->labels[entry])return abc_fail(error,ABC_INVALID,pc,"invalid lazy labels");
    if((size_t)(n->stub-n->pos)<bytes)return abc_fail(error,ABC_NOMEM,pc,"lazy entry-stub region exhausted");
    NativeLazy *s=calloc(1,sizeof *s);if(!s)return abc_fail(error,ABC_NOMEM,pc,"lazy state allocation failed");
    s->owner=n;s->state=state;s->prepare=prepare;s->entry=entry;s->body=body;s->pc=pc;
    s->next=n->lazy;n->lazy=s;n->stub-=bytes;n->end=n->stub;n->placements++;n->labels[entry]=n->stub;
    if(!abc_native_emit_lazy(n->stub,s,prepare_lazy))return abc_fail(error,ABC_INVALID,pc,"invalid lazy entry form");
    return ABC_OK;
}
static void discard_preparation(abc_exec_emitter *emitter) {
    NativeImage *n=(NativeImage *)emitter;
    free(n->labels);n->labels=NULL;n->nlabels=n->label_cap=0;
    free(n->fixups);n->fixups=NULL;n->nfix=n->fix_cap=0;
}
static void destroy(abc_exec_emitter *emitter) {
    if(!emitter)return;NativeImage *n=(NativeImage *)emitter;
    while(n->lazy){NativeLazy *next=n->lazy->next;free(n->lazy);n->lazy=next;}
    discard_preparation(emitter);if(n->base)munmap(n->base,n->mapping_size);free(n);
}
typedef __attribute__((preserve_none)) uint64_t (*NativeEntry)(uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
static uint64_t enter(const abc_exec_emitter *emitter,uintptr_t entry,uint64_t *a,uint64_t *b,uint64_t *c) {
    (void)emitter;return ((NativeEntry)entry)(a,b,c,0,0,0,0,0,0,0,0);
}
static const abc_exec_emitter_ops ops={new_label,bind_label,emit,lazy_entry,publish,address,storage,discard_preparation,destroy,enter};
abc_status abc_native_emitter_create(size_t code_bytes,abc_exec_emitter **out,abc_error *error) {
    *out=NULL;NativeImage *n=calloc(1,sizeof *n);
    if(!n)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"native emitter allocation failed");
    size_t pages=(size_t)sysconf(_SC_PAGESIZE),wanted=code_bytes*4096+pages;
    wanted=(wanted+pages-1)&~(pages-1);if(wanted>UINT32_C(0x60000000))wanted=UINT32_C(0x60000000);
    n->base=mmap(NULL,wanted,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,-1,0);
    if(n->base==MAP_FAILED){free(n);return abc_fail(error,ABC_NOMEM,UINT32_MAX,"native mapping allocation failed");}
    n->mapping_size=wanted;n->pos=n->base;n->end=n->stub=n->base+wanted;n->writable=1;
    n->emitter=(abc_exec_emitter){&ops,ABC_NATIVE_VALUE_REGISTERS};*out=&n->emitter;return ABC_OK;
}
