#include "vm_internal.h"
#include "runtime_call.h"
#include "residualize.h"
#include "execution_emit.h"
#include <sys/mman.h>
#include <errno.h>
#include <assert.h>
#include <pthread.h>
#include <stdio.h>

void *__real_aligned_alloc(size_t,size_t);
void *__real_malloc(size_t);void *__real_calloc(size_t,size_t);void *__real_realloc(void *,size_t);
int __real_mprotect(void *,size_t,int);
static int fail_protect,fail_calloc;
int __wrap_mprotect(void *p,size_t bytes,int protection){if(fail_protect&&(protection&PROT_EXEC)){fail_protect=0;errno=EACCES;return -1;}return __real_mprotect(p,bytes,protection);}
static _Atomic long fail_after=-1,fail_hold=-1;
abc_status __real_abc_owner_retain(abc_owner_context *,abc_owner *,abc_error *);
abc_status __wrap_abc_owner_retain(abc_owner_context *c,abc_owner *o,abc_error *e){
 long n=atomic_load(&fail_hold);if(!n)return abc_fail(e,ABC_NOMEM,UINT32_MAX,"injected checked-retain failure");
 if(n>0)atomic_fetch_sub(&fail_hold,1);return __real_abc_owner_retain(c,o,e);
}
static _Atomic size_t allocation_attempts,drain_allocations;
static void allocation(void){atomic_fetch_add(&allocation_attempts,1);if(abc_active_context&&abc_active_context->reclaiming)atomic_fetch_add(&drain_allocations,1);}
void *__wrap_malloc(size_t bytes){allocation();return __real_malloc(bytes);}
void *__wrap_calloc(size_t n,size_t bytes){allocation();if(fail_calloc){fail_calloc=0;return NULL;}return __real_calloc(n,bytes);}
void *__wrap_realloc(void *p,size_t bytes){allocation();return __real_realloc(p,bytes);}
void *__wrap_aligned_alloc(size_t align,size_t bytes){
 allocation();long n=atomic_load(&fail_after);if(!n)return NULL;if(n>0)atomic_fetch_sub(&fail_after,1);return __real_aligned_alloc(align,bytes);
}
static unsigned checks;
#define CHECK(c) do {checks++;if(!(c)){fprintf(stderr,"owner validation line %d: %s\n",__LINE__,#c);exit(1);}}while(0)
static abc_type_ops local_leaf={.payload_size=8,.payload_align=8,.owner_kind=ABC_OWNER_LOCAL};
static abc_type_ops shared_leaf={.payload_size=8,.payload_align=8,.owner_kind=ABC_OWNER_SHARED};
static abc_owner *make(abc_owner_context *context,const abc_type_ops *ops,size_t bytes){
 abc_owner *owner=NULL;abc_error error;CHECK(abc_owner_new(context,ops,bytes,&owner,&error)==ABC_OK);return owner;
}
/* Core tests only inspect count transitions/queues. Actual release-code execution
 * below always uses generated module operations, including the deep graph. */
static void destroy_leaf_queue(abc_owner_context *context){abc_owner *owner;while((owner=abc_owner_dequeue(context))){CHECK(*abc_owner_initialized(owner)==0);abc_owner_destroy(context,owner);}}
static void core(void){
 abc_owner_context c={0};abc_error e;abc_owner *owner=make(&c,&local_leaf,8);
 CHECK(owner->count.local==1&&*abc_owner_initialized(owner)==0);
 CHECK(abc_owner_retain(&c,owner,&e)==ABC_OK&&owner->count.local==2);
 abc_owner_release(&c,owner);CHECK(owner->count.local==1);
 owner->count.local=UINT64_MAX;CHECK(abc_owner_retain(&c,owner,&e)==ABC_NOMEM&&owner->count.local==UINT64_MAX);
 owner->count.local=1;abc_owner_release(&c,owner);CHECK(abc_owner_retain(&c,owner,&e)==ABC_INVALID);
 destroy_leaf_queue(&c);CHECK(c.allocations==c.frees);
 abc_type_ops aligned=local_leaf;aligned.payload_align=64;owner=make(&c,&aligned,72);
 CHECK((uintptr_t)abc_owner_payload(owner)%64==0);abc_owner_release(&c,owner);destroy_leaf_queue(&c);
 abc_owner *sentinel=(abc_owner *)(uintptr_t)1;owner=sentinel;
 CHECK(abc_owner_new(&c,&aligned,SIZE_MAX,&owner,&e)==ABC_ARGUMENTS&&owner==sentinel);
 aligned.payload_align=3;CHECK(abc_owner_new(&c,&aligned,8,&owner,&e)==ABC_ARGUMENTS&&owner==sentinel);
 atomic_store(&fail_after,0);CHECK(abc_owner_new(&c,&local_leaf,8,&owner,&e)==ABC_NOMEM&&owner==sentinel);atomic_store(&fail_after,-1);
 abc_type_ops immortal_ops=local_leaf;immortal_ops.owner_kind=ABC_OWNER_IMMORTAL;
 abc_owner immortal={.count.local=0,.ops=&immortal_ops};size_t retains=c.retains,frees=c.frees;
 CHECK(abc_owner_retain(&c,&immortal,&e)==ABC_OK);abc_owner_release(&c,&immortal);
 CHECK(c.retains==retains&&c.frees==frees&&!c.release_head);
}
typedef struct{abc_owner *owner;abc_owner_context context;int final;} shared_job;
static void *shared_worker(void *p){shared_job *j=p;abc_error e;
 if(!j->final)for(unsigned i=0;i<20000;i++){assert(abc_owner_retain(&j->context,j->owner,&e)==ABC_OK);abc_owner_release(&j->context,j->owner);}
 else abc_owner_release(&j->context,j->owner);
 return NULL;
}
static void shared(void){
 abc_owner_context c={0};abc_error e;abc_owner *owner=make(&c,&shared_leaf,8);
 atomic_store(&owner->count.shared,UINT64_MAX);CHECK(abc_owner_retain(&c,owner,&e)==ABC_NOMEM);atomic_store(&owner->count.shared,1);
 pthread_t threads[4];shared_job jobs[4]={0};
 for(unsigned i=0;i<4;i++){jobs[i].owner=owner;CHECK(!pthread_create(&threads[i],NULL,shared_worker,&jobs[i]));}
 for(unsigned i=0;i<4;i++){CHECK(!pthread_join(threads[i],NULL));CHECK(!jobs[i].context.release_head);}
 CHECK(atomic_load(&owner->count.shared)==1);
 shared_job last={.owner=owner,.final=1};pthread_t thread;CHECK(!pthread_create(&thread,NULL,shared_worker,&last));CHECK(!pthread_join(thread,NULL));
 CHECK(last.context.release_head==owner);destroy_leaf_queue(&last.context);CHECK(last.context.frees==1);
}
static void check_call(abc_vm *vm,const abc_module *m,const char *entry,abc_status wanted,uint64_t answer){
 abc_error e;uint64_t result=UINT64_C(0xdeadbeef01234567);size_t count=123;
 abc_status status=abc_vm_call(vm,m,entry,NULL,0,&result,1,&count,&e);
 if(status!=wanted)fprintf(stderr,"%s: %s instead of %s; %s pc=%u\n",entry,abc_status_name(status),abc_status_name(wanted),e.message,e.offset);
 CHECK(status==wanted);
 if(status==ABC_OK)CHECK(count==1&&result==answer);
 else {CHECK(!count&&result==UINT64_C(0xdeadbeef01234567));
  if(strcmp(entry,"forgot_leave"))CHECK(e.offset<m->code_size);
  if(status==ABC_ABORT)CHECK(e.reason==1&&abc_instruction_info(m->code+e.offset)->kind==K_ABORT);
  if(status==ABC_NOMEM||status==ABC_ARGUMENTS){CHECK(abc_instruction_info(m->code+e.offset)->kind==K_FCALL);CHECK(!strcmp(m->externs[abc_u16(m->code+e.offset+1)].name,!strcmp(entry,"copy_pair")?"__let_rt_v2_owner_hold":!strcmp(entry,"bad_type")||!strcmp(entry,"bad_policy")?"__let_rt_v2_type_bind":"__let_rt_v2_owner_new"));}
 }
 CHECK(!vm->root.scopes&&!vm->worker.owners.release_head&&!vm->worker.owners.release_tail);
 CHECK(vm->worker.owners.allocations==vm->worker.owners.frees&&!vm->executing);
 CHECK(atomic_load(&drain_allocations)==0);
}
static void not_callable(void){abort();}
static void execution(const char *path){
 abc_module *m=NULL;abc_error e;CHECK(abc_module_read(path,&m,&e)==ABC_OK);
 for(unsigned mode=0;mode<4;mode++){
  abc_vm *vm=NULL;abc_limits limits={.stack_cells=128,.mode=(abc_execution_mode)mode};CHECK(abc_vm_create(&limits,&vm,&e)==ABC_OK);
  CHECK(abc_vm_bind_foreign(vm,"__let_rt_v2_owner_new",not_callable,&e)==ABC_INVALID);CHECK(abc_vm_load(vm,m,&e)==ABC_OK);
  uint64_t live[3];size_t n=0;CHECK(abc_vm_call(vm,m,"live_banks",NULL,0,live,3,&n,&e)==ABC_OK);CHECK(n==3&&live[0]==111&&live[1]==333&&live[2]==222);
  abc_owner_context *o=&vm->worker.owners;size_t a=o->allocations,r=o->retains,d=o->releases;
  check_call(vm,m,"normal",ABC_OK,42);CHECK(o->allocations==a+1&&o->retains==r+1&&o->releases==d+2);
  a=o->allocations;r=o->retains;d=o->releases;check_call(vm,m,"nested",ABC_OK,42);CHECK(o->allocations==a+1&&o->retains==r&&o->releases==d+1);
  a=o->allocations;r=o->retains;d=o->releases;check_call(vm,m,"held_child",ABC_OK,42);CHECK(o->allocations==a+2&&o->retains==r+1&&o->releases==d+3);
  a=o->allocations;r=o->retains;d=o->releases;check_call(vm,m,"copy_pair",ABC_OK,42);
  CHECK(o->allocations==a+3&&o->retains==r+4&&o->releases==d+7);
  a=o->allocations;r=o->retains;d=o->releases;atomic_store(&fail_hold,3);check_call(vm,m,"copy_pair",ABC_NOMEM,0);atomic_store(&fail_hold,-1);
  CHECK(o->allocations==a+3&&o->retains==r+3&&o->releases==d+6);
  check_call(vm,m,"bad_type",ABC_ARGUMENTS,0);check_call(vm,m,"bad_policy",ABC_ARGUMENTS,0);
  check_call(vm,m,"abort_after_store",ABC_ABORT,0);check_call(vm,m,"read_persistent",ABC_OK,99);
  check_call(vm,m,"failed_init",ABC_ARGUMENTS,0);
  a=o->allocations;check_call(vm,m,"recursive_failure",ABC_STACK,0);CHECK(o->allocations>a+1);
  check_call(vm,m,"forgot_leave",ABC_INVALID,0);
  a=o->allocations;atomic_store(&fail_after,1);check_call(vm,m,"held_child",ABC_NOMEM,0);atomic_store(&fail_after,-1);CHECK(o->allocations==a+1);
  a=o->allocations;size_t entries=vm->worker.release_entries;
  check_call(vm,m,"chain",ABC_OK,42);CHECK(o->allocations==a+100001&&vm->worker.release_entries==entries+100001);
  CHECK(vm->worker.service_exits>0&&vm->worker.cleanup.capacity<vm->root.capacity);
  check_call(vm,m,"normal",ABC_OK,42);
  uint64_t unchanged=77;size_t count=55;CHECK(abc_vm_call(vm,m,"abort_after_store",NULL,0,&unchanged,1,&count,NULL)==ABC_ABORT);
  CHECK(unchanged==77&&!count&&o->allocations==o->frees);abc_vm_free(vm);
 }
 abc_module_free(m);
}
static void binding_failure(const char *path){
 abc_module *m=NULL;abc_error e;CHECK(abc_module_read(path,&m,&e)==ABC_OK);
 for(unsigned mode=0;mode<4;mode++){
 for(unsigned protection=0;protection<2;protection++){
  if(protection&&mode!=ABC_EXEC_LAZY)continue;
  abc_vm *vm=NULL;abc_limits limits={.stack_cells=128,.mode=(abc_execution_mode)mode};
  CHECK(abc_vm_create(&limits,&vm,&e)==ABC_OK&&abc_vm_load(vm,m,&e)==ABC_OK);
  check_call(vm,m,"normal",ABC_OK,42);
  /* Compile the source body without reaching its second layout binding. */
  atomic_store(&fail_after,0);check_call(vm,m,"binding_failure",ABC_NOMEM,0);atomic_store(&fail_after,-1);
  abc_exec_emitter *emitter=vm->images->execution?vm->images->execution->emitter:NULL;
  size_t regions=emitter?emitter->ops->storage(emitter).regions:0;
  abc_exec_region *before=calloc(regions,sizeof *before);uint8_t **bytes=calloc(regions,sizeof *bytes);
  for(size_t i=0;i<regions;i++){before[i]=emitter->ops->region(emitter,i);bytes[i]=malloc(before[i].body_bytes);CHECK(bytes[i]!=NULL);memcpy(bytes[i],before[i].base,before[i].body_bytes);}
  if(protection)fail_protect=1;else fail_calloc=1;
  uint64_t result=99;size_t count=123;abc_status wanted=protection?ABC_IO:ABC_NOMEM;
  CHECK(abc_vm_call(vm,m,"binding_failure",NULL,0,&result,1,&count,&e)==wanted);
  CHECK(!fail_protect&&!fail_calloc&&result==99&&!count);
  CHECK(e.offset<m->code_size&&abc_instruction_info(m->code+e.offset)->kind==K_FCALL);
  CHECK(!strcmp(m->externs[abc_u16(m->code+e.offset+1)].name,"__let_rt_v2_type_bind"));
  CHECK(vm->worker.owners.allocations==vm->worker.owners.frees&&!vm->root.scopes&&!vm->root.pending_type);
  CHECK(!atomic_load(&drain_allocations));
  for(size_t i=0;i<regions;i++){CHECK(!memcmp(bytes[i],before[i].base,before[i].body_bytes));free(bytes[i]);}free(before);free(bytes);
  if(protection){
   /* Compilation before a failed RX seal is not prepared publication. A
    * retry must not publish a descriptor with an unexecutable release entry. */
   CHECK(abc_vm_call(vm,m,"binding_failure",NULL,0,&result,1,&count,&e)==ABC_INVALID);
   CHECK(!count&&result==99&&vm->worker.owners.allocations==vm->worker.owners.frees);
   CHECK(!vm->root.pending_type&&!vm->root.scopes);
  }
  /* Previously published source/cleanup entries remain executable. */
  check_call(vm,m,"normal",ABC_OK,42);abc_vm_free(vm);
 }
 }
 abc_module_free(m);
}
static abc_vm *reentry_vm,*other_vm;static abc_module *reentry_module;
static uint64_t host_reenter(void){
 abc_owner_scope *scope=reentry_vm->root.scopes;CHECK(scope!=NULL);uint64_t result=77;size_t count=88;abc_error e;
 CHECK(abc_vm_call(reentry_vm,reentry_module,"normal",NULL,0,&result,1,&count,&e)==ABC_INVALID);
 CHECK(result==77&&!count&&reentry_vm->executing&&reentry_vm->root.scopes==scope);
 CHECK(abc_vm_call(other_vm,reentry_module,"normal",NULL,0,&result,1,&count,&e)==ABC_OK);CHECK(result==42&&count==1);return result;
}
static void reentrant(const char *path){abc_error e;CHECK(abc_module_read(path,&reentry_module,&e)==ABC_OK);
 for(unsigned mode=0;mode<4;mode++){
  abc_limits limits={.mode=(abc_execution_mode)mode};CHECK(abc_vm_create(&limits,&reentry_vm,&e)==ABC_OK);CHECK(abc_vm_create(&limits,&other_vm,&e)==ABC_OK);
  CHECK(abc_vm_bind_foreign(reentry_vm,"host_reenter",(abc_foreign_address)host_reenter,&e)==ABC_OK);CHECK(abc_vm_bind_foreign(other_vm,"host_reenter",(abc_foreign_address)host_reenter,&e)==ABC_OK);
  CHECK(abc_vm_load(reentry_vm,reentry_module,&e)==ABC_OK);CHECK(abc_vm_load(other_vm,reentry_module,&e)==ABC_OK);
  check_call(reentry_vm,reentry_module,"reentry",ABC_OK,42);abc_vm_free(reentry_vm);abc_vm_free(other_vm);
 }abc_module_free(reentry_module);
}
int main(int argc,char **argv){CHECK(argc==6);core();shared();for(int i=1;i<5;i++){execution(argv[i]);binding_failure(argv[i]);}reentrant(argv[5]);
 printf("generated holding runtime: %u checks; non-parking resumes, 100001-owner graphs, both banks/four modes/raw+optimized, no release allocations\n",checks);return 0;
}
