#define _GNU_SOURCE
#include "vm_internal.h"
#include "residualize.h"
#include "execution_emit.h"
#include "generated/banked.h"
#include <sys/mman.h>
#include <unistd.h>
/* Backing counts exclude cached cells. A/B share h0..h3, anchored from
 * opposite ends; C uses c0..c2. Pops never refill. */
size_t vm_depth(const abc_exec_context *v,char stack) {
    if(stack=='a') return v->na+v->ca;
    if(stack=='b') return v->nb+v->cb;
    return v->nc+v->cc;
}
uint64_t *vm_at(abc_exec_context *v,char stack,size_t depth) {
    if(stack=='a') return depth<v->ca ? &v->h[v->ca-1-depth] : &v->a[v->na-1-(depth-v->ca)];
    if(stack=='b') return depth<v->cb ? &v->h[4-v->cb+depth] : &v->b[v->nb-1-(depth-v->cb)];
    return depth<v->cc ? &v->cr[v->cc-1-depth] : &v->c[v->nc-1-(depth-v->cc)];
}
static void vm_spill(abc_exec_context *v,char stack) {
    if(stack=='a') {
        v->a[v->na++]=v->h[0];
        for(unsigned j=1;j<v->ca;j++) v->h[j-1]=v->h[j];
        v->ca--;
    } else if(stack=='b') {
        v->b[v->nb++]=v->h[3];
        for(unsigned j=3;j>4-v->cb;j--) v->h[j]=v->h[j-1];
        v->cb--;
    } else {
        v->c[v->nc++]=v->cr[0];
        for(unsigned j=1;j<v->cc;j++) v->cr[j-1]=v->cr[j];
        v->cc--;
    }
}
void vm_push(abc_exec_context *v,char stack,uint64_t value) {
    if(stack=='c') {
        if(v->cc==3) vm_spill(v,'c');
        v->cr[v->cc++]=value;
    } else {
        if(v->ca+v->cb==4) vm_spill(v,stack=='a' ? (v->ca ? 'a' : 'b') : (v->cb ? 'b' : 'a'));
        if(stack=='a') v->h[v->ca++]=value;
        else v->h[3-v->cb++]=value;
    }
}
uint64_t vm_pop(abc_exec_context *v,char stack) {
    if(stack=='a') return v->ca ? v->h[--v->ca] : v->a[--v->na];
    if(stack=='b') return v->cb ? v->h[4-v->cb--] : v->b[--v->nb];
    return v->cc ? v->cr[--v->cc] : v->c[--v->nc];
}
void vm_publish_all(abc_exec_context *v){while(v->ca)vm_spill(v,'a');while(v->cb)vm_spill(v,'b');while(v->cc)vm_spill(v,'c');}

abc_status abc_context_reserve(abc_exec_context *c,size_t capacity,abc_error *error) {
    if(capacity<=c->capacity)return ABC_OK;
    if(capacity>ABC_MAX_FILE)return abc_fail(error,ABC_ARGUMENTS,UINT32_MAX,"execution storage exceeds maximum");
    uint64_t *a=calloc(capacity,8),*b=calloc(capacity,8),*stack=calloc(capacity,8);
    abc_frame *frames=calloc(capacity,sizeof *frames);
    if(!a||!b||!stack||!frames){free(a);free(b);free(stack);free(frames);return abc_fail(error,ABC_NOMEM,UINT32_MAX,"execution storage allocation failed");}
    free(c->a);free(c->b);free(c->c);free(c->frames);
    c->a=a;c->b=b;c->c=stack;c->frames=frames;c->capacity=capacity;return ABC_OK;
}
static void context_free(abc_exec_context *c){free(c->a);free(c->b);free(c->c);free(c->frames);}
abc_status abc_vm_create(const abc_limits *limits,abc_vm **out,abc_error *e) {
    abc_clear(e); if(out) *out=NULL;
    if(!out) return abc_fail(e,ABC_INVALID,UINT32_MAX,"missing VM output");
    size_t cap=limits && limits->stack_cells ? limits->stack_cells : 65536;
    if(cap>ABC_MAX_FILE) return abc_fail(e,ABC_INVALID,UINT32_MAX,"stack limit exceeds maximum");
    abc_vm *v=calloc(1,sizeof *v);
    if(!v) return abc_fail(e,ABC_NOMEM,UINT32_MAX,"VM allocation failed");
    v->root.session=v;
    v->mode=limits ? limits->mode : ABC_EXEC_INTERPRETED;
    if(v->mode!=ABC_EXEC_INTERPRETED && v->mode!=ABC_EXEC_COMPILED && v->mode!=ABC_EXEC_LAZY && v->mode!=ABC_EXEC_THREADED) { free(v); return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid execution mode"); }
    abc_status status=abc_context_reserve(&v->root,cap,e);
    if(status!=ABC_OK){abc_vm_free(v);return status;}
    *out=v; return ABC_OK;
}
abc_foreign_address abc_foreign_lookup(const abc_vm *v,const char *name) {
    for(const abc_foreign_binding *b=v->foreign_bindings;b;b=b->next) if(!strcmp(b->name,name)) return b->address; return NULL;
}
abc_status abc_vm_bind_foreign(abc_vm *v,const char *name,abc_foreign_address address,abc_error *e) {
    abc_clear(e); if(!v||!name||!address) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid foreign binding");
    if(!strncmp(name,"__let_rt_",9))return abc_fail(e,ABC_INVALID,UINT32_MAX,"runtime primitive names cannot be rebound as foreign symbols");
    if(v->images) return abc_fail(e,ABC_INVALID,UINT32_MAX,"foreign bindings must be installed before loading modules");
    if(!(name[0]=='_'||(name[0]>='a'&&name[0]<='z')||(name[0]>='A'&&name[0]<='Z'))) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid foreign name");
    for(size_t i=1;name[i];i++) if(!(name[i]=='_'||(name[i]>='a'&&name[i]<='z')||(name[i]>='A'&&name[i]<='Z')||(name[i]>='0'&&name[i]<='9'))) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid foreign name");
    for(abc_foreign_binding *b=v->foreign_bindings;b;b=b->next) if(!strcmp(b->name,name)){b->address=address;return ABC_OK;}
    abc_foreign_binding *b=calloc(1,sizeof *b); if(!b)return abc_fail(e,ABC_NOMEM,UINT32_MAX,"foreign binding allocation failed");
    b->name=malloc(strlen(name)+1);if(!b->name){free(b);return abc_fail(e,ABC_NOMEM,UINT32_MAX,"foreign binding allocation failed");}strcpy(b->name,name);b->address=address;b->next=v->foreign_bindings;v->foreign_bindings=b;return ABC_OK;
}
static void image_free(abc_image *image) {
    abc_execution_image_free(image->execution);
    abc_execution_image_free(image->lifecycle);
    if(image->bytes_mapping_size) munmap(image->bytes,image->bytes_mapping_size);
    else free(image->bytes);
    free(image->direct_callees); free(image->call_info); free(image->indirect_site_states);
    free(image->foreign); free(image->foreign_bridges); free(image);
}
void abc_vm_free(abc_vm *v) {
    if(!v) return;
    while(v->images) {
        abc_image *i=v->images; v->images=i->next;
        /* Lazy native state still reads module metadata during destruction. */
        abc_module *module=(abc_module *)i->module;
        image_free(i); abc_module_free(module);
    }
    while(v->foreign_bindings){abc_foreign_binding *b=v->foreign_bindings;v->foreign_bindings=b->next;free(b->name);free(b);}
    context_free(&v->root);free(v);
}
static abc_status vm_image(abc_vm *v,const abc_module *m,abc_image **out,abc_error *e) {
    *out=NULL;
    for(abc_image *i=v->images;i;i=i->next) if(i->module==m) { *out=i; return ABC_OK; }
    abc_status checked=abc_source_lifecycle_check(m,e);if(checked!=ABC_OK)return checked;
    abc_image *i=calloc(1,sizeof *i);
    if(!i) return abc_fail(e,ABC_NOMEM,UINT32_MAX,"image allocation failed");
    if((v->mode==ABC_EXEC_COMPILED || v->mode==ABC_EXEC_LAZY) && m->image_size) {
        size_t pages=(size_t)sysconf(_SC_PAGESIZE); i->bytes_mapping_size=(m->image_size+pages-1)&~(pages-1);
        i->bytes=mmap(NULL,i->bytes_mapping_size,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,-1,0);
        if(i->bytes==MAP_FAILED) i->bytes=NULL;
    } else i->bytes=malloc(m->image_size ? m->image_size : 1);
    i->module=m;
    if(m->site_count)i->indirect_site_states=calloc(m->site_count,sizeof *i->indirect_site_states);
    if(v->mode==ABC_EXEC_INTERPRETED) {
        i->direct_callees=calloc(m->code_size?m->code_size:1,sizeof *i->direct_callees);
        i->call_info=malloc((size_t)m->function_count*sizeof *i->call_info);
        if(i->call_info)for(uint32_t index=0;index<m->function_count;index++)
            i->call_info[index]=(abc_call_info){m->functions[index].entry,m->functions[index].max_a,m->functions[index].max_b,m->functions[index].max_c};
    }
    if(!i->bytes || (m->site_count&&!i->indirect_site_states) ||
       (v->mode==ABC_EXEC_INTERPRETED&&(!i->direct_callees||!i->call_info))) {
        image_free(i);return abc_fail(e,ABC_NOMEM,UINT32_MAX,"image allocation failed");
    }
    if(v->mode==ABC_EXEC_INTERPRETED)for(uint32_t pc=0;pc<m->code_size;pc+=abc_instruction_length(m->code+pc)) {
        const abc_instruction_metadata *instruction=abc_instruction_info(m->code+pc);
        if(instruction->kind==K_CALL || instruction->kind==K_TCALL) {
            uint32_t target=(uint32_t)((int64_t)pc+instruction->encoded_length+abc_i32(m->code+pc+1));
            i->direct_callees[pc]=(uint32_t)(abc_function_entry(m,target)-m->functions);
        }
    }
    if(m->extern_count) {
        i->foreign=calloc(m->extern_count,sizeof *i->foreign);
        i->foreign_bridges=calloc(m->extern_count,sizeof *i->foreign_bridges);
        if(!i->foreign||!i->foreign_bridges){image_free(i);return abc_fail(e,ABC_NOMEM,UINT32_MAX,"foreign table allocation failed");}
        for(uint32_t index=0;index<m->extern_count;index++) {
            abc_foreign_bridge_fn source=abc_source_binding(&m->externs[index]);
            i->foreign_bridges[index]=source;
            if(!source){i->foreign[index]=abc_foreign_lookup(v,m->externs[index].name);i->foreign_bridges[index]=abc_foreign_select(&m->externs[index]);}
            if((!source&&!i->foreign[index])||!i->foreign_bridges[index]) {
                image_free(i);return abc_fail(e,ABC_NOT_FOUND,UINT32_MAX,"unbound or unsupported foreign symbol '%s'",m->externs[index].name);
            }
        }
    }
    abc_module *owned=(abc_module *)m;unsigned references=atomic_load_explicit(&owned->references,memory_order_relaxed);
    do {if(references==UINT_MAX){image_free(i);return abc_fail(e,ABC_NOMEM,UINT32_MAX,"module reference limit reached");}}
    while(!atomic_compare_exchange_weak_explicit(&owned->references,&references,references+1,memory_order_relaxed,memory_order_relaxed));
    if(m->image_size)memcpy(i->bytes,m->image,m->image_size);
    for(uint32_t index=0;index<m->reloc_count;index++) {
        uint32_t function=m->relocs[index].function;
        uint64_t identity=(uint64_t)(uintptr_t)(m->code+m->functions[function].entry);
        for(unsigned byte=0;byte<8;byte++)i->bytes[m->relocs[index].offset+byte]=(uint8_t)(identity>>(8*byte));
    }
    if(m->c_entry_count) {
        abc_status status=abc_prepare_lifecycle(m,i->bytes,v,&i->lifecycle,e);
        if(status!=ABC_OK){image_free(i);abc_module_free(owned);return status;}
        for(uint32_t entry=0;entry<m->c_entry_count;entry++) {
            uint64_t address=(uint64_t)(uintptr_t)i->lifecycle->entries[m->c_entries[entry].function];
            memcpy(i->bytes+m->c_entries[entry].offset,&address,8);
        }
    }
    if(v->mode!=ABC_EXEC_INTERPRETED) {
        abc_status status=abc_residualize_module(m,i->bytes,v,v->mode,&i->execution,e);
        if(status!=ABC_OK){image_free(i);abc_module_free(owned);return status;}
    }
    i->next=v->images;v->images=i;*out=i;return ABC_OK;
}
abc_status abc_vm_load(abc_vm *v,const abc_module *m,abc_error *e) {
    abc_clear(e); if(!v||!m) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid VM load input");
    abc_image *image=NULL; return vm_image(v,m,&image,e);
}
abc_status abc_vm_site_stats(const abc_vm *v,const abc_module *m,abc_site_stats *out,abc_error *e) {
    abc_clear(e); if(!v || !m || !out) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid site statistics inputs");
    abc_site_stats stats={m->site_count,0,0,0};
    for(const abc_image *i=v->images;i;i=i->next) if(i->module==m) {
        stats.transitions=i->transitions;
        for(uint32_t index=0;index<m->site_count;index++) {
            uint32_t observation=i->indirect_site_states[index];
            if(observation==UINT32_MAX){stats.generic--;stats.final_generic++;}
            else if(observation){stats.generic--;stats.specific++;}
        }
        break;
    }
    *out=stats; return ABC_OK;
}
/* Host arguments are a vector, not an A-shaped bytecode calling convention. */
static void prepare_entry(abc_exec_context *context,abc_image *image,unsigned function,const uint64_t *args,size_t count) {
    context->na=context->nb=context->nc=context->nf=context->ca=context->cb=context->cc=0;
    context->m=image->module;context->image=image;context->code=image->module->code;
    context->pc=image->module->functions[function].entry;context->done=0;
    abc_clear(&context->error);
    context->frames[context->nf++]=(abc_frame){UINT32_MAX,ABC_STACK_A};
    context->c[context->nc++]=UINT32_MAX;
    for(size_t i=count;i;i--)context->c[context->nc++]=args[i-1];
}
_Thread_local abc_exec_context *abc_active_context;
#include "generated/cold.inc"
uint64_t *abc_execution_limit(unsigned stack) {
    abc_exec_context *c=abc_active_context;
    return (stack==0?c->a:stack==1?c->b:c->c)+c->capacity;
}
/* Every invocation returns before another context is entered. TLS never points
 * to a temporary C run record and no suspended execution retains host frames. */
static uint64_t execute(abc_exec_context *v,unsigned function) {
    abc_exec_context *previous=abc_active_context;abc_active_context=v;uint64_t result;
    if(v->session->mode!=ABC_EXEC_INTERPRETED) {
        abc_exec_emitter *emitter=v->image->execution->emitter;
        result=emitter->ops->enter(emitter,(uintptr_t)v->image->execution->entries[function],v->a,v->b,v->c+v->nc);
    } else {
        unsigned state=(v->ca*5+v->cb)*4+v->cc;
        result=abc_tables[state][v->code[v->pc]](v->code+v->pc,v->a+v->na,v->b+v->nb,v->c+v->nc,
            v->h[0],v->h[1],v->h[2],v->h[3],v->cr[0],v->cr[1],v->cr[2]);
    }
    abc_active_context=previous;return result;
}
static abc_status execution_status(abc_exec_context *context,uint64_t result) {
    abc_status status=(abc_status)(result&255);abc_error *e=&context->error;
    if(status==ABC_OK||context->session->mode==ABC_EXEC_INTERPRETED)return status;
    uint32_t pc=(uint32_t)(result>>16);
    if(e->status==status){if(e->offset==UINT32_MAX)e->offset=pc;}
    else if(status==ABC_ABORT){unsigned reason=(unsigned)((result>>8)&255);abc_fail(e,status,pc,"language abort %u",reason);e->reason=(uint8_t)reason;}
    else abc_fail(e,status,pc,status==ABC_STACK?"stack limit reached":"compiled execution failed");
    return status;
}
abc_status abc_vm_read_image(const abc_vm *v,const abc_module *m,size_t offset,void *output,size_t size,abc_error *e) {
    abc_clear(e);
    if(!v || !m || (size && !output)) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid image copy inputs");
    if(offset>m->image_size || size>m->image_size-offset) return abc_fail(e,ABC_ARGUMENTS,UINT32_MAX,"image copy outside module extent");
    const abc_image *image=v->images;
    while(image && image->module!=m) image=image->next;
    if(!image) return abc_fail(e,ABC_NOT_FOUND,UINT32_MAX,"module has no loaded VM image");
    if(size) memcpy(output,image->bytes+offset,size);
    return ABC_OK;
}

abc_status abc_vm_call(abc_vm *v,const abc_module *m,const char *name,const uint64_t *args,size_t nargs,
                       uint64_t *results,size_t cap,size_t *nresults,abc_error *e) {
    abc_clear(e); if(nresults) *nresults=0;
    if(!v || !m || !name || (nargs && !args)) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid call inputs");
    if(v->executing)return abc_fail(e,ABC_INVALID,UINT32_MAX,"VM is already executing a call");
    abc_exec_context *context=&v->root;
    int fi=abc_find_export(m,name);
    if(fi<0) return abc_fail(e,ABC_NOT_FOUND,UINT32_MAX,"unknown export '%s'",name);
    const abc_function *f=&m->functions[fi];
    if(nargs!=f->arguments) return abc_fail(e,ABC_ARGUMENTS,UINT32_MAX,"expected %u argument cells, got %zu",f->arguments,nargs);
    if(cap<f->results || (f->results && !results)) return abc_fail(e,ABC_RESULTS,UINT32_MAX,"need capacity for %u result cells",f->results);
    size_t cneed=(size_t)f->max_c+1;
    if(nargs>context->capacity || f->max_a>context->capacity || f->max_b>context->capacity || cneed>context->capacity) return abc_fail(e,ABC_STACK,f->entry,"stack limit reached");
    abc_image *image=NULL; abc_status status=ABC_OK;
    v->executing=1;
    if(v->mode!=ABC_EXEC_INTERPRETED) {
        for(image=v->images;image&&image->module!=m;image=image->next) {}
        if(!image||!image->execution)status=abc_fail(e,ABC_INVALID,UINT32_MAX,"residual module was not loaded with abc_vm_load");
    }else status=vm_image(v,m,&image,e);
    if(status==ABC_OK) {
        prepare_entry(context,image,(unsigned)fi,args,nargs);
        status=execution_status(context,execute(context,(unsigned)fi));
        if(status==ABC_OK&&context->cleanup)status=abc_fail(&context->error,ABC_INVALID,UINT32_MAX,"source activation returned without cleanup");
        /* Frames still exist here. Drop actual holdings before resetting any ABC
           storage, retaining the original failure and persistent image writes. */
        if(context->cleanup||context->owners.head)abc_source_unwind(context);
        if(status==ABC_OK) {
            if(v->mode!=ABC_EXEC_INTERPRETED){context->na=f->results;context->nb=context->ca=context->cb=0;}
            if(vm_depth(context,'a')!=f->results||vm_depth(context,'b'))status=abc_fail(&context->error,ABC_INVALID,UINT32_MAX,"invalid final result shape");
            else {for(unsigned j=0;j<f->results;j++)results[j]=v->mode!=ABC_EXEC_INTERPRETED?context->a[j]:*vm_at(context,'a',f->results-j-1);if(nresults)*nresults=f->results;}
        }
        if(e)*e=context->error;
    }
    v->executing=0;context->na=context->nb=context->nc=context->nf=context->ca=context->cb=context->cc=0;return status;
}

