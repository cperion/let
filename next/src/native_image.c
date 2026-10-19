#define _GNU_SOURCE
#include "execution_emit.h"
#include "native_emit.h"
#include "vm_internal.h"
#include "generated/execution_forms.h"
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>

typedef struct NativeImage NativeImage;
typedef struct NativeChunk {
    uint8_t *base;size_t used,capacity;unsigned sealed;
    struct NativeChunk *next;
} NativeChunk;
typedef struct NativeLazy {
    _Atomic uint64_t published; /* stencil acquire-load ABI; never saved registers */
    NativeImage *owner;void *state;abc_exec_prepare_fn prepare;
    abc_exec_label entry,body;uint32_t pc;struct NativeLazy *next;
} NativeLazy;
_Static_assert(offsetof(NativeLazy,published)==0,"lazy entry slot ABI");
typedef struct {abc_native_patch patch;abc_exec_label target;uint32_t pc;} NativeFixup;
struct NativeImage {
    abc_exec_emitter emitter;
    NativeChunk *chunks,*tail,*current,*stubs;
    uint8_t **labels;size_t nlabels,label_cap;
    NativeFixup *fixups;size_t nfix,fix_cap;
    NativeLazy *lazy;pthread_mutex_t preparation;
    size_t pages,placements;unsigned writable,failed;
};
static int grow(void **p,size_t *capacity,size_t need,size_t size) {
    if(need<=*capacity)return 1;if(need>SIZE_MAX/size)return 0;
    size_t n=*capacity?*capacity:32;
    while(n<need){if(n>SIZE_MAX/2){n=need;break;}n*=2;}
    if(n>SIZE_MAX/size)n=need;
    void *q=realloc(*p,n*size);if(!q)return 0;*p=q;*capacity=n;return 1;
}
static abc_status chunk(NativeImage *n,uint32_t pc,abc_error *error) {
    NativeChunk *c=calloc(1,sizeof *c);if(!c)return abc_fail(error,ABC_NOMEM,pc,"native allocation record failed");
    c->capacity=n->pages;c->base=mmap(NULL,c->capacity,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,-1,0);
    if(c->base==MAP_FAILED){free(c);return abc_fail(error,ABC_NOMEM,pc,"native code allocation failed");}
    if(n->tail)n->tail->next=c;else n->chunks=c;n->tail=n->current=c;return ABC_OK;
}
static abc_status space(NativeImage *n,size_t bytes,uint32_t pc,abc_error *error) {
    size_t jump=abc_native_form_size(ABC_FORM_JUMP);
    if(bytes>n->pages-jump)return abc_fail(error,ABC_INVALID,pc,"native form exceeds allocation page");
    if(!n->current)return chunk(n,pc,error);
    if(n->current->capacity-n->current->used>=bytes+jump)return ABC_OK;
    NativeChunk *previous=n->current;abc_status status=chunk(n,pc,error);if(status!=ABC_OK)return status;
    abc_native_patch target={0};
    if(!abc_native_emit_simple(previous->base+previous->used,ABC_FORM_JUMP,0,&target))return abc_fail(error,ABC_INVALID,pc,"native allocation transfer failed");
    abc_native_bind(&target,(uintptr_t)n->current->base);previous->used+=jump;return ABC_OK;
}
static abc_status new_label(abc_exec_emitter *emitter,abc_exec_label *out,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;*out=ABC_EXEC_NO_LABEL;
    if(!n->writable||n->failed)return abc_fail(error,ABC_INVALID,pc,"native preparation is closed");
    if(n->nlabels>=ABC_EXEC_NO_LABEL||!grow((void **)&n->labels,&n->label_cap,n->nlabels+1,sizeof *n->labels))return abc_fail(error,ABC_NOMEM,pc,"execution label allocation failed");
    *out=(abc_exec_label)n->nlabels;n->labels[n->nlabels++]=NULL;return ABC_OK;
}
static abc_status bind_label(abc_exec_emitter *emitter,abc_exec_label label,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;
    if(!n->writable||label>=n->nlabels||n->labels[label])return abc_fail(error,ABC_INVALID,pc,"invalid or already bound execution label");
    abc_status status=space(n,0,pc,error);if(status!=ABC_OK)return status;
    n->labels[label]=n->current->base+n->current->used;return ABC_OK;
}
static uintptr_t address(const abc_exec_emitter *emitter,abc_exec_label label) {
    const NativeImage *n=(const NativeImage *)emitter;return label<n->nlabels?(uintptr_t)n->labels[label]:0;
}
static abc_exec_storage storage(const abc_exec_emitter *emitter) {
    const NativeImage *n=(const NativeImage *)emitter;abc_exec_storage s={0};
    for(const NativeChunk *c=n->chunks;c;c=c->next){s.body_bytes+=c->used;s.allocation_bytes+=c->capacity;s.regions++;}return s;
}
static abc_exec_region region(const abc_exec_emitter *emitter,size_t index) {
    const NativeChunk *c=((const NativeImage *)emitter)->chunks;while(c&&index){c=c->next;index--;}
    return c?(abc_exec_region){c->base,c->used,c->capacity}:(abc_exec_region){0};
}
static abc_status emit(abc_exec_emitter *emitter,unsigned form,const abc_exec_operands *op,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;size_t bytes=abc_native_form_size(form);
    if(!n->writable||n->failed)return abc_fail(error,ABC_INVALID,pc,"native preparation is closed");
    if(!bytes)return abc_fail(error,ABC_INVALID,pc,"invalid native execution form");
    if(op->target!=ABC_EXEC_NO_LABEL&&op->target>=n->nlabels)return abc_fail(error,ABC_INVALID,pc,"invalid target label");
    abc_status status=space(n,bytes,pc,error);if(status!=ABC_OK)return status;
    uint8_t *at=n->current->base+n->current->used;n->current->used+=bytes;n->placements++;
    abc_native_patch patch={0};int ok;const uint64_t *v=op->value;
    if(form>=ABC_FORM_MEMCPY_BASE&&form<ABC_FORM_MEMCPY_BASE+64){
        unsigned r=form-ABC_FORM_MEMCPY_BASE;ok=v[0]<=UINT32_MAX&&abc_native_emit_copy(at,r/8,r%8,(uint32_t)v[0],(abc_native_copy_fn)(uintptr_t)v[1]);
    }else if(form>=ABC_FORM_FCALL_BASE&&form<ABC_FORM_FCALL_BASE+4){
        ok=v[0]%8==0&&v[0]/8<=INT32_MAX&&abc_native_emit_foreign(at,form,(uint32_t)(v[0]/8),(abc_foreign_bridge_fn)(uintptr_t)v[1],(const abc_extern *)(uintptr_t)v[2],(abc_foreign_address)(uintptr_t)v[3],v[4]);
    }else if(form>=ABC_FORM_GUARD_BASE&&form<ABC_FORM_GUARD_BASE+3){
        ok=abc_native_emit_guard(at,form-ABC_FORM_GUARD_BASE,v[0],(abc_native_bounds_fn)(uintptr_t)v[1],v[2]);
    }else if(form==ABC_FORM_RESOLVE_INDIRECT){
        ok=abc_native_emit_resolve(at,(abc_native_resolve_fn)(uintptr_t)v[0],(uint32_t)v[1],(int64_t)v[2],(int64_t)v[3],(int64_t)v[4]);
    }else if(form==ABC_FORM_CALLOC){int64_t cells=(int64_t)v[1]/8;
        ok=v[0]<=UINT32_MAX&&v[1]%8==0&&cells>=INT32_MIN&&cells<=INT32_MAX&&abc_native_emit_simple(at,form,((uint64_t)(uint32_t)cells<<32)|(uint32_t)v[0],NULL);
    }else if(form>=ABC_FORM_REBASE_BASE&&form<ABC_FORM_REBASE_BASE+3){
        if((int64_t)v[0]<INT32_MIN||(int64_t)v[0]>INT32_MAX)return abc_fail(error,ABC_INVALID,pc,"native frame displacement out of range");
        ok=abc_native_emit_simple(at,form,v[0],NULL);
    }else if(form==ABC_FORM_C_ENTRY){
        ok=v[0]<=ABC_MAX_FILE&&v[1]<=ABC_MAX_FILE&&v[2]>=2&&v[2]<=ABC_MAX_FILE&&abc_native_emit_c_entry(at,v[0],v[1],v[2],&patch);
    }else if(form==ABC_FORM_LAZY_ENTRY)ok=0;
    else ok=abc_native_emit_simple(at,form,v[0],op->target==ABC_EXEC_NO_LABEL?NULL:&patch);
    if(!ok)return abc_fail(error,ABC_INVALID,pc,"invalid bound native operands");
    if(op->target!=ABC_EXEC_NO_LABEL){
        if(!abc_native_patch_present(&patch))return abc_fail(error,ABC_INVALID,pc,"form does not accept a target");
        if(!grow((void **)&n->fixups,&n->fix_cap,n->nfix+1,sizeof *n->fixups))return abc_fail(error,ABC_NOMEM,pc,"native fixup allocation failed");
        n->fixups[n->nfix++]=(NativeFixup){patch,op->target,pc};
    }
    return ABC_OK;
}
static abc_status publish(abc_exec_emitter *emitter,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;if(!n->writable)return n->failed?abc_fail(error,ABC_INVALID,pc,"failed native preparation"):ABC_OK;
    /* Check all labels before patching anything. Previously published code has
     * no pending fixups and is never reopened writable. */
    for(size_t i=0;i<n->nfix;i++){NativeFixup *f=&n->fixups[i];if(f->target>=n->nlabels||!n->labels[f->target])return abc_fail(error,ABC_INVALID,f->pc,"unbound execution target");}
    for(size_t i=0;i<n->nfix;i++)abc_native_bind(&n->fixups[i].patch,(uintptr_t)n->labels[n->fixups[i].target]);
    n->nfix=0;
    for(NativeChunk *c=n->chunks;c;c=c->next)if(!c->sealed){
        __builtin___clear_cache((char *)c->base,(char *)c->base+c->used);
        if(mprotect(c->base,c->capacity,PROT_READ|PROT_EXEC)){n->failed=1;n->writable=0;return abc_fail(error,ABC_IO,pc,"cannot protect new native allocation");}
        c->sealed=1;
    }
    n->writable=0;n->current=n->stubs=NULL;return ABC_OK;
}
static abc_status prepare_locked(NativeLazy *s,abc_error *error) {
    NativeImage *n=s->owner;
    if(atomic_load_explicit(&s->published,memory_order_acquire))return ABC_OK;
    if(n->failed)return abc_fail(error,ABC_INVALID,s->pc,"native preparation previously failed");
    n->writable=1;n->current=NULL;
    abc_status status=s->prepare(s->state,error);
    if(status==ABC_OK)status=publish(&n->emitter,s->pc,error);
    if(status==ABC_OK){uintptr_t body=address(&n->emitter,s->body);if(!body)status=abc_fail(error,ABC_INVALID,s->pc,"unbound lazy body");else atomic_store_explicit(&s->published,body,memory_order_release);}
    if(status!=ABC_OK){n->failed=1;n->writable=0;n->current=NULL;}
    return status;
}
static uint64_t prepare_lazy(uint64_t raw,uint64_t *failure) {
    NativeLazy *s=(NativeLazy *)(uintptr_t)raw;NativeImage *n=s->owner;
    uint64_t target=atomic_load_explicit(&s->published,memory_order_acquire);if(target){*failure=0;return target;}
    abc_error local,*error=abc_active_context?&abc_active_context->error:&local;
    pthread_mutex_lock(&n->preparation);abc_status status=prepare_locked(s,error);pthread_mutex_unlock(&n->preparation);
    *failure=status==ABC_OK?0:(uint64_t)status|((uint64_t)s->pc<<16);
    return atomic_load_explicit(&s->published,memory_order_acquire);
}
static abc_status lazy_entry(abc_exec_emitter *emitter,abc_exec_label entry,abc_exec_label body,void *state,abc_exec_prepare_fn prepare,uint32_t pc,abc_error *error) {
    NativeImage *n=(NativeImage *)emitter;
    if(!n->writable||entry>=n->nlabels||body>=n->nlabels||n->labels[entry])return abc_fail(error,ABC_INVALID,pc,"invalid lazy labels");
    NativeLazy *s=calloc(1,sizeof *s);if(!s)return abc_fail(error,ABC_NOMEM,pc,"lazy state allocation failed");
    atomic_init(&s->published,0);s->owner=n;s->state=state;s->prepare=prepare;s->entry=entry;s->body=body;s->pc=pc;
    NativeChunk *body_chunk=n->current;n->current=n->stubs;
    size_t bytes=abc_native_form_size(ABC_FORM_LAZY_ENTRY);abc_status status=space(n,bytes,pc,error);
    if(status!=ABC_OK){n->current=body_chunk;free(s);return status;}
    uint8_t *at=n->current->base+n->current->used;n->current->used+=bytes;n->labels[entry]=at;
    n->stubs=n->current;n->current=body_chunk;
    s->next=n->lazy;n->lazy=s;
    if(!abc_native_emit_lazy(at,s,prepare_lazy))return abc_fail(error,ABC_INVALID,pc,"invalid lazy entry form");return ABC_OK;
}
static void discard_preparation(abc_exec_emitter *emitter) {
    NativeImage *n=(NativeImage *)emitter;free(n->labels);n->labels=NULL;n->nlabels=n->label_cap=0;
    free(n->fixups);n->fixups=NULL;n->nfix=n->fix_cap=0;
}
static void destroy(abc_exec_emitter *emitter) {
    if(!emitter)return;NativeImage *n=(NativeImage *)emitter;
    while(n->lazy){NativeLazy *next=n->lazy->next;free(n->lazy);n->lazy=next;}
    while(n->chunks){NativeChunk *next=n->chunks->next;munmap(n->chunks->base,n->chunks->capacity);free(n->chunks);n->chunks=next;}
    discard_preparation(emitter);pthread_mutex_destroy(&n->preparation);free(n);
}
typedef __attribute__((preserve_none)) uint64_t (*NativeEntry)(uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
static uint64_t enter(const abc_exec_emitter *emitter,uintptr_t entry,uint64_t *a,uint64_t *b,uint64_t *c) {
    (void)emitter;return ((NativeEntry)entry)(a,b,c,0,0,0,0,0,0,0,0);
}
static const abc_exec_emitter_ops ops={new_label,bind_label,emit,lazy_entry,publish,address,storage,discard_preparation,destroy,enter,region};
abc_status abc_native_emitter_create(size_t code_bytes,abc_exec_emitter **out,abc_error *error) {
    (void)code_bytes;*out=NULL;NativeImage *n=calloc(1,sizeof *n);
    if(!n)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"native emitter allocation failed");
    if(pthread_mutex_init(&n->preparation,NULL)){free(n);return abc_fail(error,ABC_IO,UINT32_MAX,"native preparation lock failed");}
    n->pages=(size_t)sysconf(_SC_PAGESIZE);n->writable=1;
    n->emitter=(abc_exec_emitter){&ops,ABC_NATIVE_VALUE_REGISTERS};*out=&n->emitter;return ABC_OK;
}
