#include "vm_internal.h"
#include "runtime_call.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>

/* Link-time allocation failure injection, absent from the runtime ABI. */
void *__real_aligned_alloc(size_t,size_t);
static _Atomic long fail_after=-1;
static _Atomic size_t allocation_attempts;
void *__real_malloc(size_t);
void *__real_calloc(size_t,size_t);
void *__real_realloc(void *,size_t);
void *__wrap_malloc(size_t bytes){atomic_fetch_add_explicit(&allocation_attempts,1,memory_order_relaxed);return __real_malloc(bytes);}
void *__wrap_calloc(size_t count,size_t bytes){atomic_fetch_add_explicit(&allocation_attempts,1,memory_order_relaxed);return __real_calloc(count,bytes);}
void *__wrap_realloc(void *p,size_t bytes){atomic_fetch_add_explicit(&allocation_attempts,1,memory_order_relaxed);return __real_realloc(p,bytes);}
void *__wrap_aligned_alloc(size_t align,size_t bytes) {
    atomic_fetch_add_explicit(&allocation_attempts,1,memory_order_relaxed);
    long left=atomic_load_explicit(&fail_after,memory_order_relaxed);
    if(left==0)return NULL;
    if(left>0)atomic_fetch_sub_explicit(&fail_after,1,memory_order_relaxed);
    return __real_aligned_alloc(align,bytes);
}
static unsigned checks;
#define CHECK(c) do {checks++;if(!(c)){fprintf(stderr,"owner validation line %d: %s\n",__LINE__,#c);exit(1);}}while(0)
static abc_owner *make(abc_owner_context *context,unsigned type,size_t bytes) {
    abc_owner *owner=NULL;abc_error error;
    CHECK(abc_owner_new(context,&abc_runtime_types[type],bytes,&owner,&error)==ABC_OK);
    return owner;
}
static void core(void) {
    abc_owner_context context={0};abc_error error;
    abc_owner *owner=make(&context,ABC_TYPE_LOCAL_BYTES,8);
    CHECK(owner->count.local==1);
    CHECK(abc_owner_retain(&context,owner,&error)==ABC_OK&&owner->count.local==2);
    abc_owner_release(&context,owner);CHECK(owner->count.local==1);
    owner->count.local=UINT64_MAX;
    CHECK(abc_owner_retain(&context,owner,&error)==ABC_NOMEM&&owner->count.local==UINT64_MAX);
    owner->count.local=1;abc_owner_release(&context,owner);
    CHECK(abc_owner_retain(&context,owner,&error)==ABC_INVALID);
    abc_owner_drain(&context);CHECK(context.frees==context.allocations);
    abc_type_ops aligned={8,64,ABC_OWNER_LOCAL,ABC_TYPE_COPY_NONE,ABC_TYPE_RELEASE_NONE};
    CHECK(abc_owner_new(&context,&aligned,72,&owner,&error)==ABC_OK);
    CHECK((uintptr_t)abc_owner_payload(owner)%64==0);
    abc_owner_release(&context,owner);abc_owner_drain(&context);
    abc_owner *sentinel=(abc_owner *)(uintptr_t)1;owner=sentinel;
    CHECK(abc_owner_new(&context,&aligned,SIZE_MAX,&owner,&error)==ABC_ARGUMENTS&&owner==sentinel);
    aligned.payload_align=3;
    CHECK(abc_owner_new(&context,&aligned,8,&owner,&error)==ABC_ARGUMENTS&&owner==sentinel);
    atomic_store(&fail_after,0);
    CHECK(abc_owner_new(&context,&abc_runtime_types[ABC_TYPE_LOCAL_BYTES],8,&owner,&error)==ABC_NOMEM&&owner==sentinel);
    atomic_store(&fail_after,-1);
    const abc_type_ops immortal_ops={0,8,ABC_OWNER_IMMORTAL,ABC_TYPE_COPY_NONE,ABC_TYPE_RELEASE_NONE};
    abc_owner immortal={.count.local=0,.ops=&immortal_ops,.release_next=NULL};
    size_t retains=context.retains,frees=context.frees;
    CHECK(abc_owner_retain(&context,&immortal,&error)==ABC_OK);
    abc_owner_release(&context,&immortal);abc_owner_drain(&context);
    CHECK(immortal.count.local==0&&context.retains==retains&&context.frees==frees);
    abc_owner *first=make(&context,ABC_TYPE_LOCAL_BYTES,8),*second=make(&context,ABC_TYPE_LOCAL_BYTES,8);
    abc_owner *holder=make(&context,ABC_TYPE_LOCAL_OWNER,sizeof(abc_owner *));
    abc_owner *field=NULL;memcpy(&field,abc_owner_payload(holder),sizeof field);CHECK(field==NULL);
    CHECK(abc_owner_set(&context,holder,first,&error)==ABC_OK&&first->count.local==2);
    CHECK(abc_owner_set(&context,holder,first,&error)==ABC_OK&&first->count.local==2);
    second->count.local=UINT64_MAX;
    CHECK(abc_owner_set(&context,holder,second,&error)==ABC_NOMEM);
    memcpy(&field,abc_owner_payload(holder),sizeof field);CHECK(field==first&&first->count.local==2);
    second->count.local=1;
    CHECK(abc_owner_set(&context,holder,second,&error)==ABC_OK&&first->count.local==1&&second->count.local==2);
    abc_owner_release(&context,holder);abc_owner_drain(&context);CHECK(second->count.local==1);
    abc_owner_release(&context,first);abc_owner_release(&context,second);abc_owner_drain(&context);
    CHECK(context.frees==context.allocations);
    /* No recursively nested destructor calls, even with 100001 owners. */
    owner=make(&context,ABC_TYPE_LOCAL_BYTES,0);
    for(unsigned i=0;i<100000;i++) {
        abc_owner *next=make(&context,ABC_TYPE_LOCAL_OWNER,sizeof(abc_owner *));
        CHECK(abc_owner_set(&context,next,owner,&error)==ABC_OK);
        abc_owner_release(&context,owner);abc_owner_drain(&context);owner=next;
    }
    size_t before=atomic_load(&allocation_attempts);
    abc_owner_release(&context,owner);abc_owner_drain(&context);
    CHECK(atomic_load(&allocation_attempts)==before&&context.frees==context.allocations);
    CHECK(!context.release_head&&!context.release_tail&&!context.draining);
}
typedef struct {abc_owner *owner;abc_owner_context context;int final;} shared_job;
static void *shared_worker(void *data) {
    shared_job *job=data;abc_error error;
    if(!job->final)for(unsigned i=0;i<20000;i++) {
        assert(abc_owner_retain(&job->context,job->owner,&error)==ABC_OK);
        abc_owner_release(&job->context,job->owner);
    }
    else abc_owner_release(&job->context,job->owner);
    abc_owner_drain(&job->context);return NULL;
}
static void shared(void) {
    abc_owner_context context={0};abc_error error;
    abc_owner *owner=make(&context,ABC_TYPE_SHARED_BYTES,8);
    atomic_store(&owner->count.shared,UINT64_MAX);
    CHECK(abc_owner_retain(&context,owner,&error)==ABC_NOMEM&&atomic_load(&owner->count.shared)==UINT64_MAX);
    atomic_store(&owner->count.shared,1);
    pthread_t threads[4];shared_job jobs[4]={0};
    for(unsigned i=0;i<4;i++){jobs[i].owner=owner;CHECK(!pthread_create(&threads[i],NULL,shared_worker,&jobs[i]));}
    for(unsigned i=0;i<4;i++){CHECK(!pthread_join(threads[i],NULL));CHECK(jobs[i].context.frees==0);}
    CHECK(atomic_load(&owner->count.shared)==1);
    shared_job final={.owner=owner,.final=1};pthread_t last;
    CHECK(!pthread_create(&last,NULL,shared_worker,&final));CHECK(!pthread_join(last,NULL));
    CHECK(final.context.frees==1); /* free on the worker observing zero */
}
static void check_call(abc_vm *vm,const abc_module *module,const char *entry,abc_status wanted,uint64_t answer) {
    abc_error error;uint64_t result=UINT64_C(0xdeadbeef01234567);size_t count=123;
    abc_status status=abc_vm_call(vm,module,entry,NULL,0,&result,1,&count,&error);
    if(status!=wanted)fprintf(stderr,"%s: got %s, wanted %s, %s pc=%u\n",entry,abc_status_name(status),abc_status_name(wanted),error.message,error.offset);
    CHECK(status==wanted);
    if(status==ABC_OK)CHECK(count==1&&result==answer);
    else {
        CHECK(!count&&result==UINT64_C(0xdeadbeef01234567));
        if(strcmp(entry,"forgot_leave"))CHECK(error.offset<module->code_size);
        if(status==ABC_ABORT)CHECK(error.reason==1&&abc_instruction_info(module->code+error.offset)->kind==K_ABORT);
        if(status==ABC_NOMEM||status==ABC_ARGUMENTS) {
            CHECK(abc_instruction_info(module->code+error.offset)->kind==K_FCALL);
            unsigned index=abc_u16(module->code+error.offset+1);
            CHECK(!strcmp(module->externs[index].name,"__let_rt_v1_owner_new"));
        }
    }
    CHECK(!vm->owners.scopes&&!vm->owners.release_head&&!vm->owners.release_tail);
    CHECK(vm->owners.allocations==vm->owners.frees);
    CHECK(!vm->executing);
}
static void not_callable(void) {abort();}
static void execution(const char *path) {
    abc_module *module=NULL;abc_error error;
    CHECK(abc_module_read(path,&module,&error)==ABC_OK);
    for(unsigned mode=0;mode<4;mode++) {
        abc_vm *vm=NULL;abc_limits limits={.stack_cells=128,.mode=(abc_execution_mode)mode};
        CHECK(abc_vm_create(&limits,&vm,&error)==ABC_OK);
        CHECK(abc_vm_bind_foreign(vm,"__let_rt_v1_owner_new",not_callable,&error)==ABC_INVALID);
        CHECK(abc_vm_load(vm,module,&error)==ABC_OK);
        uint64_t live[3]={0};size_t live_count=0;
        CHECK(abc_vm_call(vm,module,"live_banks",NULL,0,live,3,&live_count,&error)==ABC_OK);
        CHECK(live_count==3&&live[0]==111&&live[1]==333&&live[2]==222);
        CHECK(vm->owners.allocations==vm->owners.frees&&!vm->owners.scopes);
        size_t alloc=vm->owners.allocations,retains=vm->owners.retains,releases=vm->owners.releases;
        check_call(vm,module,"normal",ABC_OK,42);
        CHECK(vm->owners.allocations==alloc+1&&vm->owners.retains==retains+1&&vm->owners.releases==releases+2);
        alloc=vm->owners.allocations;retains=vm->owners.retains;releases=vm->owners.releases;
        check_call(vm,module,"nested",ABC_OK,42);
        CHECK(vm->owners.allocations==alloc+1&&vm->owners.retains==retains&&vm->owners.releases==releases+1);
        alloc=vm->owners.allocations;retains=vm->owners.retains;releases=vm->owners.releases;
        check_call(vm,module,"held_child",ABC_OK,42);
        CHECK(vm->owners.allocations==alloc+2&&vm->owners.retains==retains+1&&vm->owners.releases==releases+3);
        check_call(vm,module,"abort_after_store",ABC_ABORT,0);
        check_call(vm,module,"read_persistent",ABC_OK,99);
        check_call(vm,module,"failed_init",ABC_ARGUMENTS,0);
        alloc=vm->owners.allocations;
        check_call(vm,module,"recursive_failure",ABC_STACK,0);
        CHECK(vm->owners.allocations>alloc+1); /* actual nested abandoned frames */
        check_call(vm,module,"forgot_leave",ABC_INVALID,0);
        alloc=vm->owners.allocations;
        atomic_store(&fail_after,1); /* parent constructed, child allocation fails */
        check_call(vm,module,"held_child",ABC_NOMEM,0);atomic_store(&fail_after,-1);
        CHECK(vm->owners.allocations==alloc+1);
        check_call(vm,module,"normal",ABC_OK,42);
        uint64_t unchanged=77;size_t count=55;
        CHECK(abc_vm_call(vm,module,"abort_after_store",NULL,0,&unchanged,1,&count,NULL)==ABC_ABORT);
        CHECK(unchanged==77&&count==0&&vm->owners.allocations==vm->owners.frees&&!vm->owners.scopes);
        abc_vm_free(vm);
    }
    abc_module_free(module);
}
static abc_vm *reentry_vm,*other_vm;
static abc_module *reentry_module;
static uint64_t host_reenter(void) {
    abc_owner_scope *scope=reentry_vm->owners.scopes;CHECK(scope!=NULL);
    uint64_t result=77;size_t count=88;abc_error error;
    CHECK(abc_vm_call(reentry_vm,reentry_module,"normal",NULL,0,&result,1,&count,&error)==ABC_INVALID);
    CHECK(result==77&&count==0&&reentry_vm->executing&&reentry_vm->owners.scopes==scope);
    CHECK(abc_vm_call(other_vm,reentry_module,"normal",NULL,0,&result,1,&count,&error)==ABC_OK);
    CHECK(result==42&&count==1&&other_vm->owners.allocations==other_vm->owners.frees);
    return result;
}
static void reentrant(const char *path) {
    abc_error error;CHECK(abc_module_read(path,&reentry_module,&error)==ABC_OK);
    for(unsigned mode=0;mode<4;mode++) {
        abc_limits limits={.mode=(abc_execution_mode)mode};
        CHECK(abc_vm_create(&limits,&reentry_vm,&error)==ABC_OK);
        CHECK(abc_vm_create(&limits,&other_vm,&error)==ABC_OK);
        CHECK(abc_vm_bind_foreign(reentry_vm,"host_reenter",(abc_foreign_address)host_reenter,&error)==ABC_OK);
        CHECK(abc_vm_bind_foreign(other_vm,"host_reenter",(abc_foreign_address)host_reenter,&error)==ABC_OK);
        CHECK(abc_vm_load(reentry_vm,reentry_module,&error)==ABC_OK);
        CHECK(abc_vm_load(other_vm,reentry_module,&error)==ABC_OK);
        check_call(reentry_vm,reentry_module,"reentry",ABC_OK,42);
        abc_vm_free(reentry_vm);abc_vm_free(other_vm);
    }
    abc_module_free(reentry_module);
}
int main(int argc,char **argv) {
    CHECK(argc==6);core();shared();
    for(int i=1;i<5;i++)execution(argv[i]);
    reentrant(argv[5]);
    printf("runtime owners: %u checks; local/shared/immortal, 100001-owner release, both banks raw/optimized in four modes, failure cleanup and VM reuse\n",checks);
    return 0;
}
