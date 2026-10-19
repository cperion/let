/* Standalone C ownership tests, not source lifetime/VM binding evidence. */
#include "owner.h"
#include <pthread.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
#define CHECK(c) do { checks++; if(!(c)){fprintf(stderr,"owner core line %d: %s\n",__LINE__,#c);exit(1);} } while(0)
static _Atomic size_t allocations, frees, allocation_during_drain, drops;
static _Thread_local abc_owner_context *watched;
static _Thread_local size_t thread_drops, callback_depth;
static _Thread_local bool record_order;
static _Thread_local unsigned order[8], order_count;
static bool fail_allocation;
static size_t last_bytes, last_alignment;
void *__real_aligned_alloc(size_t,size_t);
void *__real_malloc(size_t);
void *__real_calloc(size_t,size_t);
void *__real_realloc(void *,size_t);
void __real_free(void *);
static void allocation_attempt(void){
    if(watched&&watched->draining)atomic_fetch_add(&allocation_during_drain,1);
}
void *__wrap_malloc(size_t n){allocation_attempt();return __real_malloc(n);}
void *__wrap_calloc(size_t n,size_t size){allocation_attempt();return __real_calloc(n,size);}
void *__wrap_realloc(void *p,size_t n){allocation_attempt();return __real_realloc(p,n);}
void *__wrap_aligned_alloc(size_t alignment,size_t n){
    allocation_attempt();last_bytes=n;last_alignment=alignment;
    if(fail_allocation){fail_allocation=false;return NULL;}
    void *p=__real_aligned_alloc(alignment,n);
    if(p)atomic_fetch_add(&allocations,1);
    return p;
}
void __wrap_free(void *p){if(p)atomic_fetch_add(&frees,1);__real_free(p);}

typedef struct {abc_owner owner;abc_owner *left,*right;unsigned marker;} Node;
_Static_assert(offsetof(Node,owner)==0,"owner must be allocation base");
static void drop_node(abc_owner_context *context,abc_owner *owner){
    Node *node=(Node *)owner;
    if(!context->draining||++callback_depth!=1||node->marker!=0x1234)abort();
    atomic_fetch_add(&drops,1);thread_drops++;
    abc_owner_release(context,node->left);
    abc_owner_release(context,node->right);
    callback_depth--;
}
static void drop_ordered(abc_owner_context *context,abc_owner *owner){
    Node *node=(Node *)owner;
    if(!record_order||order_count>=sizeof order/sizeof order[0])abort();
    order[order_count++]=node->marker;node->marker=0x1234;
    drop_node(context,owner);
}
static Node *node_new_with(abc_owner_kind kind,abc_drop_fields_fn drop,unsigned marker){
    abc_owner *owner=NULL;abc_error error;
    if(abc_owner_alloc(sizeof(Node),_Alignof(Node),kind,drop,&owner,&error)!=ABC_OK){
        fprintf(stderr,"node allocation: %s\n",error.message);exit(1);
    }
    Node *node=(Node *)owner;
    node->left=node->right=NULL;node->marker=marker;return node;
}
static Node *node_new(abc_owner_kind kind){return node_new_with(kind,drop_node,0x1234);}
static void drain(abc_owner_context *context){
    watched=context;abc_owner_drain(context);watched=NULL;
    CHECK(!context->head&&!context->tail&&!context->draining);
    CHECK(!atomic_load(&allocation_during_drain));
}
static uint64_t count(const abc_owner *owner){
    return owner->kind==ABC_OWNER_SHARED?atomic_load(&owner->count.shared):owner->count.local;
}
static void set_count(abc_owner *owner,uint64_t n){
    if(owner->kind==ABC_OWNER_SHARED)atomic_store(&owner->count.shared,n);
    else owner->count.local=n;
}
static void allocation_contract(void){
    abc_owner sentinel={0},*owner=&sentinel;abc_error error;
    size_t before=atomic_load(&allocations);
    CHECK(abc_owner_alloc(sizeof(abc_owner)-1,8,ABC_OWNER_LOCAL,NULL,&owner,&error)==ABC_ARGUMENTS);
    CHECK(owner==&sentinel);
    CHECK(abc_owner_alloc(sizeof(Node),0,ABC_OWNER_LOCAL,NULL,&owner,NULL)==ABC_ARGUMENTS);
    CHECK(abc_owner_alloc(sizeof(Node),3,ABC_OWNER_LOCAL,NULL,&owner,NULL)==ABC_ARGUMENTS);
    CHECK(abc_owner_alloc(SIZE_MAX,64,ABC_OWNER_LOCAL,NULL,&owner,NULL)==ABC_ARGUMENTS);
    CHECK(abc_owner_alloc(sizeof(Node),8,ABC_OWNER_IMMORTAL,NULL,&owner,NULL)==ABC_ARGUMENTS);
    CHECK(abc_owner_alloc(sizeof(Node),8,(abc_owner_kind)-1,NULL,&owner,NULL)==ABC_ARGUMENTS);
    CHECK(abc_owner_alloc(sizeof(Node),8,ABC_OWNER_LOCAL,NULL,NULL,NULL)==ABC_ARGUMENTS);
    CHECK(owner==&sentinel&&atomic_load(&allocations)==before);
    fail_allocation=true;
    CHECK(abc_owner_alloc(sizeof(Node),64,ABC_OWNER_LOCAL,NULL,&owner,&error)==ABC_NOMEM);
    CHECK(error.status==ABC_NOMEM&&!fail_allocation&&owner==&sentinel&&atomic_load(&allocations)==before);
    CHECK(abc_owner_alloc(sizeof(Node),64,ABC_OWNER_LOCAL,NULL,&owner,&error)==ABC_OK);
    CHECK((uintptr_t)owner%64==0&&last_alignment==64&&last_bytes==(sizeof(Node)+63)/64*64);
    CHECK(count(owner)==1&&owner->drop_fields==NULL&&owner->next_dead==NULL);
    abc_owner_context context={0};size_t dropped=atomic_load(&drops);
    abc_owner_release(&context,owner);drain(&context);CHECK(atomic_load(&drops)==dropped);
    CHECK(abc_owner_alloc(sizeof(abc_owner),1,ABC_OWNER_LOCAL,NULL,&owner,NULL)==ABC_OK);
    CHECK(last_alignment==_Alignof(abc_owner)&&last_bytes==sizeof(abc_owner));
    abc_owner_release(&context,owner);drain(&context);
    CHECK(abc_owner_retain(NULL,NULL)==ABC_ARGUMENTS);
    abc_owner_release(&context,NULL);drain(&context);
    abc_owner immortal={.kind=ABC_OWNER_IMMORTAL};size_t freed=atomic_load(&frees);
    CHECK(abc_owner_retain(&immortal,&error)==ABC_OK);
    abc_owner_release(&context,&immortal);drain(&context);
    CHECK(atomic_load(&frees)==freed);
}
static void counts(abc_owner_kind kind){
    abc_owner_context context={0};abc_error error;Node *node=node_new(kind);
    CHECK(count(&node->owner)==1);
    CHECK(abc_owner_retain(&node->owner,&error)==ABC_OK&&count(&node->owner)==2);
    abc_owner_release(&context,&node->owner);CHECK(count(&node->owner)==1&&!context.head);
    set_count(&node->owner,UINT64_MAX);
    CHECK(abc_owner_retain(&node->owner,&error)==ABC_NOMEM&&count(&node->owner)==UINT64_MAX);
    set_count(&node->owner,1);size_t freed=atomic_load(&frees);
    abc_owner_release(&context,&node->owner);
    CHECK(count(&node->owner)==0&&context.head==&node->owner&&context.tail==&node->owner);
    CHECK(abc_owner_retain(&node->owner,&error)==ABC_INVALID&&count(&node->owner)==0);
    CHECK(atomic_load(&frees)==freed);drain(&context);CHECK(atomic_load(&frees)==freed+1);
    drain(&context);
}
static void replacement(abc_owner_kind kind){
    abc_owner_context context={0};abc_error error;
    Node *old=node_new(kind),*incoming=node_new(kind);abc_owner *slot=&old->owner;
    size_t freed=atomic_load(&frees);
    CHECK(abc_owner_replace(&context,NULL,&incoming->owner,&error)==ABC_ARGUMENTS);
    CHECK(count(&incoming->owner)==1);
    set_count(&incoming->owner,UINT64_MAX);
    CHECK(abc_owner_replace(&context,&slot,&incoming->owner,&error)==ABC_NOMEM);
    CHECK(slot==&old->owner&&count(&old->owner)==1&&count(&incoming->owner)==UINT64_MAX&&!context.head);
    set_count(&incoming->owner,1);
    CHECK(abc_owner_replace(&context,&slot,&incoming->owner,&error)==ABC_OK);
    CHECK(slot==&incoming->owner&&count(slot)==2&&context.head==&old->owner&&atomic_load(&frees)==freed);
    drain(&context);CHECK(atomic_load(&frees)==freed+1);
    CHECK(abc_owner_replace(&context,&slot,slot,&error)==ABC_OK&&count(slot)==2&&!context.head);
    CHECK(abc_owner_replace(&context,&slot,NULL,&error)==ABC_OK&&!slot&&count(&incoming->owner)==1);
    abc_owner_release(&context,&incoming->owner);drain(&context);
    CHECK(atomic_load(&frees)==freed+2);
    CHECK(abc_owner_replace(&context,&slot,NULL,NULL)==ABC_OK&&!slot);drain(&context);
}
static void diamond(void){
    Node *root=node_new_with(ABC_OWNER_LOCAL,drop_ordered,0),*left=node_new_with(ABC_OWNER_LOCAL,drop_ordered,1);
    Node *right=node_new_with(ABC_OWNER_LOCAL,drop_ordered,2),*leaf=node_new_with(ABC_OWNER_LOCAL,drop_ordered,3);
    root->left=&left->owner;root->right=&right->owner;
    left->left=&leaf->owner;CHECK(abc_owner_retain(&leaf->owner,NULL)==ABC_OK);right->left=&leaf->owner;
    abc_owner_context context={0};size_t freed=atomic_load(&frees);record_order=true;order_count=0;
    abc_owner_release(&context,&root->owner);drain(&context);record_order=false;
    CHECK(order_count==4&&order[0]==0&&order[1]==1&&order[2]==2&&order[3]==3);
    CHECK(atomic_load(&frees)==freed+4);
}
static void long_chain(void){
    const size_t length=100001;Node *head=NULL;
    size_t made=atomic_load(&allocations),freed=atomic_load(&frees),dropped=atomic_load(&drops);
    for(size_t i=0;i<length;i++){
        Node *node=node_new(ABC_OWNER_LOCAL);node->left=head?&head->owner:NULL;head=node;
    }
    CHECK(atomic_load(&allocations)==made+length);
    abc_owner_context context={0};abc_owner_release(&context,&head->owner);drain(&context);
    CHECK(atomic_load(&frees)==freed+length&&atomic_load(&drops)==dropped+length);
}
typedef struct {abc_owner *owner;bool final,failed;size_t dropped;} Job;
static void *thread_run(void *raw){
    Job *job=raw;abc_owner_context context={0};abc_error error;
    if(job->final){
        watched=&context;abc_owner_release(&context,job->owner);abc_owner_drain(&context);watched=NULL;
    }else for(unsigned i=0;i<20000;i++){
        if(abc_owner_retain(job->owner,&error)!=ABC_OK){job->failed=true;break;}
        abc_owner_release(&context,job->owner);
    }
    job->failed|=context.head!=NULL||context.tail!=NULL||context.draining;
    job->dropped=thread_drops;return NULL;
}
static void shared_threads(void){
    Node *parent=node_new(ABC_OWNER_SHARED),*child=node_new(ABC_OWNER_SHARED);
    parent->left=&child->owner;Job jobs[4]={0};pthread_t threads[4];
    for(unsigned i=0;i<4;i++){jobs[i].owner=&parent->owner;CHECK(!pthread_create(&threads[i],NULL,thread_run,&jobs[i]));}
    for(unsigned i=0;i<4;i++){CHECK(!pthread_join(threads[i],NULL));CHECK(!jobs[i].failed&&!jobs[i].dropped);}
    CHECK(count(&parent->owner)==1&&count(&child->owner)==1);
    size_t freed=atomic_load(&frees),dropped=atomic_load(&drops);
    Job last={.owner=&parent->owner,.final=true};pthread_t thread;
    CHECK(!pthread_create(&thread,NULL,thread_run,&last));CHECK(!pthread_join(thread,NULL));
    CHECK(!last.failed&&last.dropped==2&&atomic_load(&frees)==freed+2&&atomic_load(&drops)==dropped+2);
}
int main(void){
    allocation_contract();counts(ABC_OWNER_LOCAL);counts(ABC_OWNER_SHARED);
    replacement(ABC_OWNER_LOCAL);replacement(ABC_OWNER_SHARED);diamond();long_chain();shared_threads();
    CHECK(atomic_load(&allocations)==atomic_load(&frees));CHECK(!atomic_load(&allocation_during_drain));
    printf("owner core: %u checks; 100001-object chain, branching queue, shared-thread release; header %zu bytes; no source/VM binding claim\n",checks,sizeof(abc_owner));
    return 0;
}
