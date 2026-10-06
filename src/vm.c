#define _GNU_SOURCE
#include "vm_internal.h"
#include "residualize.h"
#include "dynamic.h"
#include "generated/banked.h"
#include <sys/mman.h>
#include <unistd.h>
/* Backing counts exclude cached cells. A/B share h0..h3, anchored from
 * opposite ends; C uses c0..c2. Pops never refill. */
size_t vm_depth(const abc_vm *v,char stack) {
    if(stack=='a') return v->na+v->ca;
    if(stack=='b') return v->nb+v->cb;
    return v->nc+v->cc;
}
uint64_t *vm_at(abc_vm *v,char stack,size_t depth) {
    if(stack=='a') return depth<v->ca ? &v->h[v->ca-1-depth] : &v->a[v->na-1-(depth-v->ca)];
    if(stack=='b') return depth<v->cb ? &v->h[4-v->cb+depth] : &v->b[v->nb-1-(depth-v->cb)];
    return depth<v->cc ? &v->cr[v->cc-1-depth] : &v->c[v->nc-1-(depth-v->cc)];
}
static void vm_spill(abc_vm *v,char stack) {
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
void vm_push(abc_vm *v,char stack,uint64_t value) {
    if(stack=='c') {
        if(v->cc==3) vm_spill(v,'c');
        v->cr[v->cc++]=value;
    } else {
        if(v->ca+v->cb==4) vm_spill(v,stack=='a' ? (v->ca ? 'a' : 'b') : (v->cb ? 'b' : 'a'));
        if(stack=='a') v->h[v->ca++]=value;
        else v->h[3-v->cb++]=value;
    }
}
uint64_t vm_pop(abc_vm *v,char stack) {
    if(stack=='a') return v->ca ? v->h[--v->ca] : v->a[--v->na];
    if(stack=='b') return v->cb ? v->h[4-v->cb--] : v->b[--v->nb];
    return v->cc ? v->cr[--v->cc] : v->c[--v->nc];
}
void vm_publish_all(abc_vm *v){while(v->ca)vm_spill(v,'a');while(v->cb)vm_spill(v,'b');while(v->cc)vm_spill(v,'c');}

abc_status abc_vm_create(const abc_limits *limits,abc_vm **out,abc_error *e) {
    abc_clear(e); if(out) *out=NULL;
    if(!out) return abc_fail(e,ABC_INVALID,UINT32_MAX,"missing VM output");
    size_t cap=limits && limits->stack_cells ? limits->stack_cells : 65536;
    if(cap>ABC_MAX_FILE) return abc_fail(e,ABC_INVALID,UINT32_MAX,"stack limit exceeds maximum");
    abc_vm *v=calloc(1,sizeof *v);
    if(!v) return abc_fail(e,ABC_NOMEM,UINT32_MAX,"VM allocation failed");
    v->capacity=cap;
    v->mode=limits ? limits->mode : ABC_EXEC_INTERPRETED;
    if(v->mode!=ABC_EXEC_INTERPRETED && v->mode!=ABC_EXEC_COMPILED && v->mode!=ABC_EXEC_LAZY) { free(v); return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid execution mode"); }
    v->a=calloc(cap,sizeof *v->a); v->b=calloc(cap,sizeof *v->b);
    v->c=calloc(cap,sizeof *v->c); v->frames=calloc(cap,sizeof *v->frames);
    if(!v->a || !v->b || !v->c || !v->frames) { abc_vm_free(v); return abc_fail(e,ABC_NOMEM,UINT32_MAX,"stack allocation failed"); }
    *out=v; return ABC_OK;
}
abc_foreign_address abc_foreign_lookup(const abc_vm *v,const char *name) {
    for(const abc_foreign_binding *b=v->foreign_bindings;b;b=b->next) if(!strcmp(b->name,name)) return b->address; return NULL;
}
abc_status abc_vm_bind_foreign(abc_vm *v,const char *name,abc_foreign_address address,abc_error *e) {
    abc_clear(e); if(!v||!name||!address) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid foreign binding");
    if(v->images) return abc_fail(e,ABC_INVALID,UINT32_MAX,"foreign bindings must be installed before loading modules");
    if(!(name[0]=='_'||(name[0]>='a'&&name[0]<='z')||(name[0]>='A'&&name[0]<='Z'))) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid foreign name");
    for(size_t i=1;name[i];i++) if(!(name[i]=='_'||(name[i]>='a'&&name[i]<='z')||(name[i]>='A'&&name[i]<='Z')||(name[i]>='0'&&name[i]<='9'))) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid foreign name");
    for(abc_foreign_binding *b=v->foreign_bindings;b;b=b->next) if(!strcmp(b->name,name)){b->address=address;return ABC_OK;}
    abc_foreign_binding *b=calloc(1,sizeof *b); if(!b)return abc_fail(e,ABC_NOMEM,UINT32_MAX,"foreign binding allocation failed");
    b->name=malloc(strlen(name)+1);if(!b->name){free(b);return abc_fail(e,ABC_NOMEM,UINT32_MAX,"foreign binding allocation failed");}strcpy(b->name,name);b->address=address;b->next=v->foreign_bindings;v->foreign_bindings=b;return ABC_OK;
}
static void image_bytes_free(abc_image *i) { if(i->bytes_mapping_size) munmap(i->bytes,i->bytes_mapping_size); else free(i->bytes); }
void abc_vm_free(abc_vm *v) {
    if(!v) return;
    while(v->images) {
        abc_image *i=v->images; v->images=i->next;
        abc_module_free((abc_module *)i->module); abc_native_image_free(i->native); image_bytes_free(i); free(i->code); free(i->direct_callees); free(i->call_info); free(i->foreign); free(i->foreign_bridges); free(i);
    }
    abc_dynamic_destroy(v);
    while(v->foreign_bindings){abc_foreign_binding *b=v->foreign_bindings;v->foreign_bindings=b->next;free(b->name);free(b);}
    free(v->a); free(v->b); free(v->c); free(v->frames); free(v);
}
static uint32_t dynamic_layout_size(const abc_module *m,uint32_t di){const abc_descriptor *d=&m->descriptors[di];if(d->tag==ABC_DESC_PRIMITIVE){unsigned p=d->payload[0];return p==ABC_PRIM_UNIT?0:p==ABC_PRIM_STRING?16:8;}if(d->tag==ABC_DESC_POINTER)return 8;if(d->tag==ABC_DESC_SLICE)return 16;if(d->tag==ABC_DESC_RECORD||d->tag==ABC_DESC_ARRAY||d->tag==ABC_DESC_SUM)return abc_u32(d->payload);return 0;}
static void initialize_dynamic_layout(const abc_module *m,uint8_t *base,uint32_t di){const abc_descriptor *d=&m->descriptors[di];const uint8_t *p=d->payload;if(d->tag==ABC_DESC_PRIMITIVE){if(p[0]==ABC_PRIM_ANY){uint64_t unit=abc_any_unit();memcpy(base,&unit,8);}return;}if(d->tag==ABC_DESC_RECORD){uint32_t n=abc_u32(p+4);for(uint32_t i=0;i<n;i++){const uint8_t *field=p+8+16*i;initialize_dynamic_layout(m,base+abc_u32(field+8),abc_u32(field+12));}}else if(d->tag==ABC_DESC_ARRAY){uint32_t n=abc_u32(p+4),element=abc_u32(p+8),stride=dynamic_layout_size(m,element);for(uint32_t i=0;i<n;i++)initialize_dynamic_layout(m,base+(size_t)i*stride,element);}else if(d->tag==ABC_DESC_SUM){uint64_t disc=0;memcpy(&disc,base+abc_u32(p+4),p[8]);for(unsigned i=0;i<p[9];i++){const uint8_t *c=p+12+16*i;if(abc_u64(c)==disc){initialize_dynamic_layout(m,base+abc_u32(c+8),abc_u32(c+12));break;}}}}
static abc_status vm_image(abc_vm *v,const abc_module *m,abc_image **out,abc_error *e) {
    *out=NULL;
    for(abc_image *i=v->images;i;i=i->next) if(i->module==m) { *out=i; return ABC_OK; }
    abc_image *i=calloc(1,sizeof *i);
    if(!i) return abc_fail(e,ABC_NOMEM,UINT32_MAX,"image allocation failed");
    if(v->mode!=ABC_EXEC_INTERPRETED && m->image_size) {
        size_t pages=(size_t)sysconf(_SC_PAGESIZE); i->bytes_mapping_size=(m->image_size+pages-1)&~(pages-1);
        i->bytes=mmap(NULL,i->bytes_mapping_size,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,-1,0);
        if(i->bytes==MAP_FAILED) i->bytes=NULL;
    } else i->bytes=malloc(m->image_size ? m->image_size : 1);
    i->code=malloc(m->code_size ? m->code_size : 1);
    if(v->mode==ABC_EXEC_INTERPRETED){i->direct_callees=calloc(m->code_size?m->code_size:1,sizeof *i->direct_callees);i->call_info=malloc((size_t)m->function_count*sizeof *i->call_info);if(i->call_info)for(uint32_t j=0;j<m->function_count;j++)i->call_info[j]=(abc_call_info){m->functions[j].entry,m->functions[j].max_a,m->functions[j].max_b,m->functions[j].max_c};}
    if(!i->bytes || !i->code || (v->mode==ABC_EXEC_INTERPRETED&&(!i->direct_callees||!i->call_info))) { image_bytes_free(i); free(i->code); free(i->direct_callees); free(i->call_info); free(i); return abc_fail(e,ABC_NOMEM,UINT32_MAX,"image allocation failed"); }
    if(m->extern_count){i->foreign=calloc(m->extern_count,sizeof *i->foreign);i->foreign_bridges=calloc(m->extern_count,sizeof *i->foreign_bridges);if(!i->foreign||!i->foreign_bridges){image_bytes_free(i);free(i->code);free(i->direct_callees);free(i->call_info);free(i->foreign);free(i->foreign_bridges);free(i);return abc_fail(e,ABC_NOMEM,UINT32_MAX,"foreign table allocation failed");}
        for(uint32_t j=0;j<m->extern_count;j++){i->foreign[j]=abc_foreign_lookup(v,m->externs[j].name);i->foreign_bridges[j]=abc_foreign_select(&m->externs[j]);if(!i->foreign[j]||!i->foreign_bridges[j]){image_bytes_free(i);free(i->code);free(i->direct_callees);free(i->call_info);free(i->foreign);free(i->foreign_bridges);free(i);return abc_fail(e,ABC_NOT_FOUND,UINT32_MAX,"unbound or unsupported foreign symbol '%s'",m->externs[j].name);}}}
    abc_module *owned=(abc_module *)m; unsigned refs=atomic_load_explicit(&owned->references,memory_order_relaxed);
    do { if(refs==UINT_MAX) { image_bytes_free(i); free(i->code); free(i->direct_callees); free(i->call_info); free(i->foreign); free(i->foreign_bridges); free(i); return abc_fail(e,ABC_NOMEM,UINT32_MAX,"module reference limit reached"); } }
    while(!atomic_compare_exchange_weak_explicit(&owned->references,&refs,refs+1,memory_order_relaxed,memory_order_relaxed));
    if(m->image_size) memcpy(i->bytes,m->image,m->image_size);
    if(m->dynamic_profile)for(uint32_t j=0;j<m->gc_root_count;j++)initialize_dynamic_layout(m,i->bytes+m->gc_roots[j].offset,m->gc_roots[j].descriptor);
    memcpy(i->code,m->code,m->code_size);
    if(v->mode!=ABC_EXEC_INTERPRETED) {
        abc_status status=abc_residualize_module(m,i->bytes,v,v->mode==ABC_EXEC_LAZY,&i->native,e);
        if(status!=ABC_OK) { abc_module_free(owned); image_bytes_free(i); free(i->code); free(i->direct_callees); free(i->call_info); free(i->foreign); free(i->foreign_bridges); free(i); return status; }
    }
    for(uint32_t j=0;j<m->reloc_count;j++) {
        uint32_t f=m->relocs[j].function;
        uint64_t address=(uint64_t)(uintptr_t)(v->mode!=ABC_EXEC_INTERPRETED ? i->native->entries[f] : m->code+m->functions[f].entry);
        for(unsigned k=0;k<8;k++) i->bytes[m->relocs[j].offset+k]=(uint8_t)(address>>(8*k));
    }
    i->module=m; i->next=v->images; v->images=i; *out=i; return ABC_OK;
}
abc_status abc_vm_load(abc_vm *v,const abc_module *m,abc_error *e) {
    abc_clear(e); if(!v||!m) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid VM load input");
    abc_image *image=NULL; return vm_image(v,m,&image,e);
}
abc_status abc_vm_site_stats(const abc_vm *v,const abc_module *m,abc_site_stats *out,abc_error *e) {
    abc_clear(e); if(!v || !m || !out) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid site statistics inputs");
    abc_site_stats stats={m->site_count,0,0,0};
    for(const abc_image *i=v->images;i;i=i->next) if(i->module==m) {
        if(i->native) abc_native_site_stats(i->native,&stats);
        else {
            stats.transitions=i->transitions;
            for(uint32_t j=0;j<m->site_count;j++) {
                unsigned op=i->code[m->sites[j].entry];
                if(op>=OP_CALLI_MONO_A && op<=OP_TCALLI_MONO) { stats.generic--; stats.specific++; }
                else if(op>=OP_CALLI_FINAL_A && op<=OP_TCALLI_FINAL) { stats.generic--; stats.final_generic++; }
            }
        }
        break;
    }
    *out=stats; return ABC_OK;
}
abc_status vm_enter(abc_vm *v,const abc_function *callee,uint32_t ret,unsigned to_b,unsigned n,uint32_t pc,abc_error *e) {
    size_t da=vm_depth(v,'a'),db=vm_depth(v,'b'),dc=vm_depth(v,'c');
    if(v->nf==v->capacity || da<n || da-n+callee->max_a>v->capacity || db+callee->max_b>v->capacity || dc+1+callee->max_c>v->capacity)
        return abc_fail(e,ABC_STACK,pc,"stack limit reached");
    v->frames[v->nf++]=(abc_frame){ret,to_b};
    vm_push(v,'c',ret);
    for(unsigned j=0;j<n;j++) vm_push(v,'c',vm_pop(v,'a'));
    return ABC_OK;
}
abc_status vm_tail_require(abc_vm *v,const abc_function *callee,uint32_t pc,abc_error *e) {
    if(vm_depth(v,'a')+callee->max_a>v->capacity || vm_depth(v,'b')+callee->max_b>v->capacity || vm_depth(v,'c')+callee->max_c>v->capacity)
        return abc_fail(e,ABC_STACK,pc,"stack limit reached");
    return ABC_OK;
}
static void vm_store(uint8_t *p,unsigned width,uint64_t value) {
    for(unsigned j=0;j<width;j++) p[j]=(uint8_t)(value>>(8*j));
}
_Thread_local abc_run *abc_active_run;
#include "generated/cold.inc"

static abc_status vm_execute(abc_vm *v,const abc_module *m,abc_image *image,uint32_t entry,abc_error *e) {
    abc_run run={v,m,image,image->code,e,entry,0};
    abc_run *previous=abc_active_run; abc_active_run=&run;
    unsigned state=(v->ca*5+v->cb)*4+v->cc;
    abc_value result=abc_tables[state][run.code[entry]](
        run.code+entry,v->a+v->na,v->b+v->nb,v->c+v->nc,
        v->h[0],v->h[1],v->h[2],v->h[3],v->cr[0],v->cr[1],v->cr[2]);
    abc_active_run=previous;
    return (abc_status)result;
}
typedef __attribute__((preserve_none)) uint64_t (*abc_native_entry)(
    uint64_t *,uint64_t *,uint64_t *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);
abc_status vm_dynamic_invoke(abc_run *parent,uint32_t function,unsigned arguments,uint32_t pc){
    abc_vm *v=parent->v;abc_image *image=parent->image;
    if(function>=parent->m->function_count||v->na<arguments)return abc_fail(parent->e,ABC_INVALID,pc,"dynamic callable function is invalid");
    const abc_function *f=&parent->m->functions[function];
    size_t saved_na=v->na-arguments,saved_nb=v->nb,saved_nc=v->nc,saved_nf=v->nf;
    size_t old_count=v->dynamic->suspended_count,total=old_count+v->na+saved_nb+saved_nc;
    if(total<old_count||total<v->na||total>SIZE_MAX/sizeof(uint64_t))return abc_fail(parent->e,ABC_NOMEM,pc,"dynamic stack save failed");
    uint64_t *old_suspended=v->dynamic->suspended,*suspended=total?malloc(total*sizeof *suspended):NULL;
    abc_frame *saved_frames=saved_nf?malloc(saved_nf*sizeof *saved_frames):NULL;
    uint64_t *results=f->results?malloc((size_t)f->results*sizeof *results):NULL;
    if((total&&!suspended)||(saved_nf&&!saved_frames)||(f->results&&!results)){free(suspended);free(saved_frames);free(results);return abc_fail(parent->e,ABC_NOMEM,pc,"dynamic stack save failed");}
    size_t at=0;if(old_count){memcpy(suspended,old_suspended,old_count*sizeof *suspended);at+=old_count;}
    memcpy(suspended+at,v->a,v->na*sizeof *suspended);size_t arguments_at=at+saved_na;at+=v->na;
    if(saved_nb){memcpy(suspended+at,v->b,saved_nb*sizeof *suspended);at+=saved_nb;}if(saved_nc)memcpy(suspended+at,v->c,saved_nc*sizeof *suspended);
    if(saved_nf)memcpy(saved_frames,v->frames,saved_nf*sizeof *saved_frames);
    v->dynamic->suspended=suspended;v->dynamic->suspended_count=total;v->na=v->nb=v->nc=v->nf=v->ca=v->cb=v->cc=0;
    abc_run run={v,parent->m,image,image->code,parent->e,f->entry,0};abc_run *previous=abc_active_run;abc_active_run=&run;abc_status status=ABC_OK;
    if(v->mode==ABC_EXEC_INTERPRETED){
        if(arguments)memcpy(v->a,suspended+arguments_at,arguments*sizeof *v->a);v->na=arguments;status=vm_enter(v,f,UINT32_MAX,0,arguments,pc,parent->e);
        if(status==ABC_OK){unsigned state=(v->ca*5+v->cb)*4+v->cc;status=(abc_status)abc_tables[state][run.code[f->entry]](run.code+f->entry,v->a+v->na,v->b+v->nb,v->c+v->nc,v->h[0],v->h[1],v->h[2],v->h[3],v->cr[0],v->cr[1],v->cr[2]);}vm_publish_all(v);
    }else{
        v->c[0]=UINT32_MAX;for(size_t i=0;i<arguments;i++)v->c[arguments-i]=suspended[arguments_at+i];v->nc=arguments+1;
        uint64_t result=((abc_native_entry)image->native->entries[function])(v->a,v->b,v->c+v->nc,0,0,0,0,0,0,0,0);status=(abc_status)(result&255);uint32_t offset=(uint32_t)(result>>16);
        if(status==ABC_ABORT){unsigned reason=(unsigned)((result>>8)&255);status=abc_fail(parent->e,ABC_ABORT,offset,"language abort %u",reason);if(parent->e)parent->e->reason=(uint8_t)reason;}else if(status==ABC_STACK)status=abc_fail(parent->e,status,offset,"stack limit reached");else if(status!=ABC_OK)status=abc_fail(parent->e,status,offset,"dynamic callable execution failed");if(status==ABC_OK)v->na=f->results;
    }
    abc_active_run=previous;if(status==ABC_OK&&f->results)memcpy(results,v->a,(size_t)f->results*sizeof *results);
    at=old_count;if(saved_na)memcpy(v->a,suspended+at,saved_na*sizeof *v->a);at+=saved_na+arguments;if(saved_nb)memcpy(v->b,suspended+at,saved_nb*sizeof *v->b);at+=saved_nb;if(saved_nc)memcpy(v->c,suspended+at,saved_nc*sizeof *v->c);
    v->na=saved_na;v->nb=saved_nb;v->nc=saved_nc;v->nf=saved_nf;v->ca=v->cb=v->cc=0;if(saved_nf)memcpy(v->frames,saved_frames,saved_nf*sizeof *saved_frames);if(status==ABC_OK&&f->results){memcpy(v->a+v->na,results,(size_t)f->results*sizeof *results);v->na+=f->results;}
    v->dynamic->suspended=old_suspended;v->dynamic->suspended_count=old_count;free(suspended);free(saved_frames);free(results);return status;
}
static abc_status vm_execute_native(abc_vm *v,abc_image *image,unsigned function,const abc_function *f,
                                    const uint64_t *args,size_t nargs,abc_error *e) {
    v->c[0]=UINT32_MAX;
    for(size_t i=0;i<nargs;i++) v->c[nargs-i]=args[i];
    v->nc=nargs+1;
    abc_run run={v,image->module,image,image->code,e,f->entry,0};abc_run *previous=abc_active_run;abc_active_run=&run;
    uint64_t result=((abc_native_entry)image->native->entries[function])(
        v->a,v->b,v->c+nargs+1,0,0,0,0,0,0,0,0);
    abc_active_run=previous;
    abc_status status=(abc_status)(result&255); uint32_t offset=(uint32_t)(result>>16);
    if(status==ABC_ABORT) { unsigned reason=(unsigned)((result>>8)&255); status=abc_fail(e,ABC_ABORT,offset,"language abort %u",reason); if(e)e->reason=(uint8_t)reason; }
    else if(status==ABC_STACK) status=abc_fail(e,status,offset,"stack limit reached");
    else if(status==ABC_ARGUMENTS) status=abc_fail(e,status,offset,"indirect target signature disagrees with call site");
    else if(status==ABC_INVALID) status=abc_fail(e,status,offset,"indirect target is not a callable function entry in this module");
    else if(status!=ABC_OK) status=abc_fail(e,status,offset,"compiled execution failed");
    if(status==ABC_OK) v->na=f->results; return status;
}
abc_status abc_vm_call(abc_vm *v,const abc_module *m,const char *name,const uint64_t *args,size_t nargs,
                       uint64_t *results,size_t cap,size_t *nresults,abc_error *e) {
    abc_clear(e); if(nresults) *nresults=0;
    if(!v || !m || !name || (nargs && !args)) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid call inputs");
    v->na=v->nb=v->nc=v->nf=v->ca=v->cb=v->cc=0;
    int fi=abc_find_export(m,name);
    if(fi<0) return abc_fail(e,ABC_NOT_FOUND,UINT32_MAX,"unknown export '%s'",name);
    const abc_function *f=&m->functions[fi];
    if(nargs!=f->arguments) return abc_fail(e,ABC_ARGUMENTS,UINT32_MAX,"expected %u argument cells, got %zu",f->arguments,nargs);
    if(cap<f->results || (f->results && !results)) return abc_fail(e,ABC_RESULTS,UINT32_MAX,"need capacity for %u result cells",f->results);
    size_t cneed=(size_t)f->max_c+1;
    if(nargs>v->capacity || f->max_a>v->capacity || f->max_b>v->capacity || cneed>v->capacity) return abc_fail(e,ABC_STACK,f->entry,"stack limit reached");
    abc_image *image=NULL; abc_status status=ABC_OK;
    if(v->mode!=ABC_EXEC_INTERPRETED) {
        for(image=v->images;image&&image->module!=m;image=image->next) {}
        if(!image||!image->native) status=abc_fail(e,ABC_INVALID,UINT32_MAX,"compiled module was not loaded with abc_vm_load");
        else status=vm_execute_native(v,image,(unsigned)fi,f,args,nargs,e);
    } else {
        if(nargs) memcpy(v->a,args,nargs*sizeof *args);
        v->na=nargs;
        status=vm_image(v,m,&image,e);
        if(status==ABC_OK) status=vm_enter(v,f,UINT32_MAX,0,(unsigned)nargs,f->entry,e);
        if(status==ABC_OK) status=vm_execute(v,m,image,f->entry,e);
    }
    if(status==ABC_OK) {
        if(vm_depth(v,'a')!=f->results || vm_depth(v,'b')) status=abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid final result shape");
        else { for(unsigned j=0;j<f->results;j++) results[j]=v->mode!=ABC_EXEC_INTERPRETED ? v->a[j] : *vm_at(v,'a',f->results-j-1); if(nresults) *nresults=f->results; }
    }
    v->na=v->nb=v->nc=v->nf=v->ca=v->cb=v->cc=0; return status;
}

