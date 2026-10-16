#include "vm_internal.h"
#include "owner.h"
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <sys/mman.h>
#include <errno.h>

static unsigned checks,active,in_drain,allocations,frees,acquires,fail_alloc,fail_acquire,drain_allocations;
static void *live[131072];static size_t extents[131072];static unsigned used,searchable;
static abc_drop_fields_fn concrete_drop,tagged_drop;
static unsigned hold_calls;
static size_t live_bytes,peak_bytes;
static unsigned reject_publication,publication_failures;
int __real_mprotect(void *,size_t,int);
int __wrap_mprotect(void *p,size_t n,int protection) {
    if(reject_publication&&(protection&PROT_EXEC)){publication_failures++;errno=ENOMEM;return -1;}
    return __real_mprotect(p,n,protection);
}
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"source owners: %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
void *__real_aligned_alloc(size_t,size_t);
void *__real_malloc(size_t);
void *__real_calloc(size_t,size_t);
void *__real_realloc(void *,size_t);
void __real_free(void *);
abc_status __real_abc_owner_replace(abc_owner_context *,abc_owner **,abc_owner *,abc_error *);
void __real_abc_owner_drain(abc_owner_context *);
void *__wrap_malloc(size_t n){if(in_drain)drain_allocations++;return __real_malloc(n);}
void *__wrap_calloc(size_t n,size_t s){if(in_drain)drain_allocations++;return __real_calloc(n,s);}
void *__wrap_realloc(void *p,size_t n){if(in_drain)drain_allocations++;return __real_realloc(p,n);}
void *__wrap_aligned_alloc(size_t alignment,size_t bytes) {
    if(in_drain)drain_allocations++;
    if(active&&++allocations==fail_alloc)return NULL;
    void *p=__real_aligned_alloc(alignment,bytes);
    if(active&&p){CHECK(used<sizeof live/sizeof *live);live[used]=p;extents[used++]=bytes;searchable=used;
        live_bytes+=bytes;if(live_bytes>peak_bytes)peak_bytes=live_bytes;}
    return p;
}
void __wrap_free(void *p) {
    if(active&&p)for(unsigned i=searchable;i;i--)if(live[i-1]==p) {
        abc_owner *owner=p;CHECK(owner->kind==ABC_OWNER_LOCAL);CHECK(owner->count.local==0);
        if(extents[i-1]==48&&owner->drop_fields)concrete_drop=owner->drop_fields;
        if(extents[i-1]==80&&owner->drop_fields)tagged_drop=owner->drop_fields;
        CHECK(live_bytes>=extents[i-1]);live_bytes-=extents[i-1];
        live[i-1]=NULL;frees++;while(searchable&&!live[searchable-1])searchable--;break;
    }
    __real_free(p);
}
abc_status __wrap_abc_owner_replace(abc_owner_context *context,abc_owner **slot,abc_owner *incoming,abc_error *error) {
    if(active)hold_calls++;
    if(active&&incoming&&++acquires==fail_acquire) {
        CHECK(incoming->kind==ABC_OWNER_LOCAL);uint64_t count=incoming->count.local;abc_owner *old=*slot;
        incoming->count.local=UINT64_MAX;
        abc_status status=__real_abc_owner_replace(context,slot,incoming,error);
        CHECK(status==ABC_NOMEM&&*slot==old&&incoming->count.local==UINT64_MAX);
        incoming->count.local=count;return status;
    }
    return __real_abc_owner_replace(context,slot,incoming,error);
}
void __wrap_abc_owner_drain(abc_owner_context *context) {
    CHECK(!in_drain);in_drain=1;__real_abc_owner_drain(context);in_drain=0;
}
static abc_module *load(const char *path) {
    FILE *f=fopen(path,"rb");CHECK(f);CHECK(!fseek(f,0,SEEK_END));long n=ftell(f);CHECK(n>0);rewind(f);
    void *bytes=malloc((size_t)n);CHECK(bytes);CHECK(fread(bytes,1,(size_t)n,f)==(size_t)n);CHECK(!fclose(f));
    abc_module *m=NULL;abc_error error;abc_status status=abc_module_load(bytes,(size_t)n,&m,&error);
    if(status!=ABC_OK)fprintf(stderr,"load: %s\n",error.message);
    CHECK(status==ABC_OK);free(bytes);return m;
}
static void begin(unsigned allocation_failure,unsigned acquire_failure) {
    CHECK(!active);active=1;used=searchable=allocations=frees=acquires=drain_allocations=hold_calls=0;
    live_bytes=peak_bytes=0;fail_alloc=allocation_failure;fail_acquire=acquire_failure;
}
static void finish(abc_vm *vm) {
    for(unsigned i=0;i<used;i++)CHECK(!live[i]);
    CHECK(frees==used);CHECK(!live_bytes);CHECK(!drain_allocations);CHECK(!vm->root.cleanup);
    CHECK(!vm->root.owners.head&&!vm->root.owners.tail&&!vm->root.owners.draining);
    CHECK(!abc_active_context);active=0;
}
static abc_status run(abc_vm *vm,abc_module *m,const char *entry,uint64_t input,uint64_t wanted,abc_error *error) {
    uint64_t output=UINT64_C(0x12345678);size_t n=99;
    abc_status status=abc_vm_call(vm,m,entry,&input,1,&output,1,&n,error);
    if(status==ABC_OK){CHECK(output==wanted);CHECK(n==1);}else {
        CHECK(output==UINT64_C(0x12345678));CHECK(n==0);CHECK(error->offset<m->code_size);
        if(status==ABC_NOMEM)CHECK(abc_instruction_info(m->code+error->offset)->kind==K_FCALL);
    }
    finish(vm);return status;
}
typedef struct { abc_owner_context *context;abc_owner *head; } drain_input;
static void *drain_thread(void *data) {
    drain_input *input=data;CHECK(!abc_active_context);
    abc_owner_release(input->context,input->head);abc_owner_drain(input->context);
    CHECK(!abc_active_context);return NULL;
}
int main(int argc,char **argv) {
    if(argc!=5){fprintf(stderr,"usage: validate-source-owners raw.abc optimized.abc mirrored.abc mirrored-optimized.abc\n");return 2;}
    const abc_execution_mode modes[]={ABC_EXEC_INTERPRETED,ABC_EXEC_THREADED,ABC_EXEC_COMPILED,ABC_EXEC_LAZY};
    for(unsigned file=1;file<(unsigned)argc;file++) {
        abc_module *m=load(argv[file]);CHECK(m->c_entry_count);
        for(unsigned mode=0;mode<4;mode++) {
            abc_vm *vm=NULL;abc_error error;abc_limits limits={.stack_cells=65536,.mode=modes[mode]};
            CHECK(abc_vm_create(&limits,&vm,&error)==ABC_OK);
            unsigned references=atomic_load(&m->references);reject_publication=1;publication_failures=0;
            CHECK(abc_vm_load(vm,m,&error)==ABC_IO);CHECK(publication_failures==1);
            CHECK(!vm->images&&atomic_load(&m->references)==references&&!vm->root.cleanup);
            reject_publication=0;CHECK(abc_vm_load(vm,m,&error)==ABC_OK);
            CHECK(vm->images->lifecycle);CHECK(!vm->root.cleanup);
            begin(0,0);CHECK(run(vm,m,"main",2,203,&error)==ABC_OK);CHECK(allocations==3&&frees==3);
            unsigned total_acquires=acquires;CHECK(total_acquires>3);CHECK(concrete_drop);
            for(unsigned i=1;i<=3;i++){begin(i,0);CHECK(run(vm,m,"main",2,0,&error)==ABC_NOMEM);CHECK(allocations==i&&frees==i-1);}
            /* Every acquire boundary, including partially initialized payloads,
               callback environments and caller result buffers, is protected. */
            for(unsigned i=1;i<=total_acquires;i++){begin(0,i);CHECK(run(vm,m,"main",2,0,&error)==ABC_NOMEM);CHECK(acquires==i);}
            begin(0,0);CHECK(run(vm,m,"closure",2,304,&error)==ABC_OK);CHECK(allocations==2);
            unsigned closure_acquires=acquires;
            for(unsigned i=1;i<=2;i++){begin(i,0);CHECK(run(vm,m,"closure",2,0,&error)==ABC_NOMEM);CHECK(allocations==i&&frees==i-1);}
            for(unsigned i=1;i<=closure_acquires;i++){begin(0,i);CHECK(run(vm,m,"closure",2,0,&error)==ABC_NOMEM);CHECK(acquires==i);}
            uint32_t borrowed=91;abc_signature signature;
            CHECK(abc_module_export_signature(m,"read_only",&signature,&error)==ABC_OK);
            CHECK(signature.arguments==1&&signature.argument_kinds[0]==ABC_KIND_ADDR);
            begin(0,0);CHECK(run(vm,m,"read_only",(uintptr_t)&borrowed,91,&error)==ABC_OK);CHECK(!allocations&&!acquires);
            begin(0,0);CHECK(run(vm,m,"borrow_local",91,91,&error)==ABC_OK);CHECK(!allocations&&!acquires);
            begin(0,0);CHECK(run(vm,m,"variant",0,0,&error)==ABC_OK);CHECK(!allocations&&!acquires);
            const char *extra[]={"pair_result","array","slice","borrow","projection","indirect_result","partial","keyed","self_replace","zero_width","opened",
                "variant","variant_replace","variant_nested","variant_indirect","variant_callable","variant_slice","variant_loop","variant_scalar","variant_multi","variant_raw"};
            const uint64_t wanted[]={203,20403,203,2,2,2,7,5,2,2,2,2,521,9,2,3,203,1,2,203,4};
            const unsigned owners[]={2,4,1,2,1,2,0,1,2,2,2,1,4,3,2,2,1,2,1,2,1};
            for(unsigned test=0;test<sizeof extra/sizeof *extra;test++) {
                begin(0,0);CHECK(run(vm,m,extra[test],2,wanted[test],&error)==ABC_OK);
                if(owners[test]&&allocations!=owners[test])fprintf(stderr,"%s: %u owner allocations, expected %u\n",extra[test],allocations,owners[test]);
                CHECK(owners[test]?allocations==owners[test]:allocations>0);
                unsigned count=acquires,allocated=allocations;
                if(file==1&&mode==0)printf("traffic %s: owners=%u holds=%u nonnull-acquires=%u peak-owner-bytes=%zu\n",extra[test],allocated,hold_calls,count,peak_bytes);
                for(unsigned i=1;i<=allocated;i++){begin(i,0);CHECK(run(vm,m,extra[test],2,0,&error)==ABC_NOMEM);CHECK(allocations==i&&frees==i-1);}
                for(unsigned i=1;i<=count;i++){begin(0,i);CHECK(run(vm,m,extra[test],2,0,&error)==ABC_NOMEM);CHECK(acquires==i);}
            }
            begin(0,0);CHECK(run(vm,m,"variant_fail",2,0,&error)==ABC_ABORT);CHECK(error.reason==1&&allocations==3);
            begin(0,0);CHECK(run(vm,m,"deep_graph",42,42,&error)==ABC_OK);CHECK(allocations==25);unsigned graph_acquires=acquires;
            begin(25,0);CHECK(run(vm,m,"deep_graph",42,0,&error)==ABC_NOMEM);CHECK(frees==24);
            begin(0,graph_acquires);CHECK(run(vm,m,"deep_graph",42,0,&error)==ABC_NOMEM);CHECK(acquires==graph_acquires);
            begin(0,0);CHECK(run(vm,m,"loop",50,1225,&error)==ABC_OK);CHECK(allocations==100);
            begin(0,0);CHECK(run(vm,m,"recursive",32,42,&error)==ABC_OK);CHECK(allocations==2);
            begin(0,0);CHECK(run(vm,m,"fail",2,0,&error)==ABC_ABORT);CHECK(error.reason==1);CHECK(error.offset<m->code_size);CHECK(allocations==3);
            begin(0,0);CHECK(run(vm,m,"persisted",0,2,&error)==ABC_OK);CHECK(!allocations&&!acquires);
            begin(0,0);CHECK(run(vm,m,"main",3,304,&error)==ABC_OK);
            if((file==1||file==3)&&mode==0) {
                /* Exercise the actual source-generated C callback outside VM TLS.
                   The graph is constructed by C, not claimed as source execution. */
                abc_owner_context context={0};abc_owner *head=NULL;begin(0,0);
                for(unsigned i=0;i<100001;i++){
                    abc_owner *owner=NULL;CHECK(abc_owner_alloc(48,8,ABC_OWNER_LOCAL,concrete_drop,&owner,&error)==ABC_OK);
                    uint64_t *fields=(uint64_t *)(owner+1);fields[0]=0;fields[1]=(uintptr_t)head;head=owner;
                }
                CHECK(!abc_active_context);pthread_t thread;pthread_attr_t attr;drain_input input={&context,head};
                CHECK(!pthread_attr_init(&attr));CHECK(!pthread_attr_setstacksize(&attr,128*1024));
                CHECK(!pthread_create(&thread,&attr,drain_thread,&input));CHECK(!pthread_join(thread,NULL));CHECK(!pthread_attr_destroy(&attr));
                CHECK(allocations==100001&&frees==100001&&!context.head&&!context.tail);finish(vm);
                /* TaggedBox is header32 + {sentinel/pad, tag/pad, union32}.
                   Exercise one/pair/noise branches without source TLS, including
                   two holdings to one child and scalar bits in inactive owner slots. */
                CHECK(tagged_drop);head=NULL;begin(0,0);
                for(unsigned i=0;i<100001;i++) {
                    abc_owner *owner=NULL;CHECK(abc_owner_alloc(80,8,ABC_OWNER_LOCAL,tagged_drop,&owner,&error)==ABC_OK);
                    uint64_t *fields=(uint64_t *)(owner+1);fields[0]=17;fields[1]=i?2:1;
                    fields[2]=123;fields[3]=i?(uintptr_t)head:456;fields[4]=789;fields[5]=321;
                    if(i==100000){fields[1]=3;fields[5]=(uintptr_t)head;CHECK(abc_owner_retain(head,&error)==ABC_OK);}
                    head=owner;
                }
                input=(drain_input){&context,head};CHECK(!pthread_attr_init(&attr));CHECK(!pthread_attr_setstacksize(&attr,128*1024));
                CHECK(!pthread_create(&thread,&attr,drain_thread,&input));CHECK(!pthread_join(thread,NULL));CHECK(!pthread_attr_destroy(&attr));
                CHECK(allocations==100001&&frees==100001&&!context.head&&!context.tail);finish(vm);
            }
            abc_vm_free(vm);
            /* Fail after owning callers exist, before the recursive child can
               establish its next activation. The ordinary stack limit survives. */
            limits.stack_cells=1024;CHECK(abc_vm_create(&limits,&vm,&error)==ABC_OK);CHECK(abc_vm_load(vm,m,&error)==ABC_OK);
            begin(0,0);CHECK(run(vm,m,"deep",10000,0,&error)==ABC_STACK);CHECK(allocations>0);
            begin(0,0);CHECK(run(vm,m,"variant_deep",10000,0,&error)==ABC_STACK);CHECK(allocations>0);
            begin(0,0);CHECK(run(vm,m,"main",2,203,&error)==ABC_OK);
            abc_vm_free(vm);
        }
        abc_module_free(m);
    }
    printf("source ownership cleanup: %u checks; four modes, raw/optimized, both lifecycle banks, allocation/acquire failures, trap, stack limit, generated C drain\n",checks);
    return 0;
}
