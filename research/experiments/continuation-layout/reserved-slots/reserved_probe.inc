/* Isolated feasibility probe, NOT production version policy. */
#include <stdio.h>
#include <inttypes.h>
static uint64_t probe_roots[3];
static unsigned probe_activations,probe_general_entries,probe_resumes;
static void reserved_event(uint64_t *asp,uint64_t *bsp,uint64_t *csp,uint64_t event) {
    abc_run *run=abc_active_run;
    unsigned kind=(unsigned)(event&255u);
    int32_t bias=(int32_t)(uint32_t)(event>>8);
    if(kind==1) {
        for(unsigned i=0;i<3;i++)probe_roots[i]=abc_u64(run->image->bytes+8*i);
        probe_activations++;
        fprintf(stderr,"ACTIVATION %u roots=%td,%td,%td\n",probe_activations,
            (uint64_t *)(uintptr_t)probe_roots[0]-run->v->c,
            (uint64_t *)(uintptr_t)probe_roots[1]-run->v->c,
            (uint64_t *)(uintptr_t)probe_roots[2]-run->v->c);
    }else if(kind==2) {
        for(unsigned i=0;i<3;i++)if(probe_roots[i]!=abc_u64(run->image->bytes+8*i)||*(uint64_t *)(uintptr_t)probe_roots[i]!=101*(i+1))abort();
        if((uint64_t)(uintptr_t)(csp+bias)!=probe_roots[2]||asp[0]!=555||bsp[0]!=666)abort();
        probe_general_entries++;
        fprintf(stderr,"GENERAL_ENTRY %u roots_stable=3 A=%" PRIu64 " B=%" PRIu64 " cbase=%td bias=%d\n",probe_general_entries,asp[0],bsp[0],csp-run->v->c,bias);
    }else {
        probe_resumes++;
        fprintf(stderr,"MATERIALIZED_RETURN %u\n",probe_resumes);
    }
}
static int emit_reserved_event(Compiler *c,uint64_t event) {
    const Stencil *s=&stencils[ABC_STENCIL_RESERVED_EVENT];if(!reserve(c,s->len))return 0;
    uint8_t *at=c->pos;memcpy(at,s->code,s->len);c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++) {
        const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)c->pos;
        else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)reserved_event;
        else if(r->hole==HOLE_IMM)value=event;
        else return 0;
        patch(at+r->off,r->kind,r->addend,value);
    }
    return 1;
}
static Version *probe_general_version(Compiler *c,uint32_t pc,unsigned args,uint32_t na,uint32_t nb,uint32_t nc) {
    Context in={0};in.generic=1;in.c_origin=(int32_t)args;
    uint32_t count[3]={na,nb,nc};
    for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<count[s];i++)
        if(!push(&in,s,home_value(s,(int32_t)i-(s==JS_C?(int32_t)args:0)))){context_free(&in);return NULL;}
    Version *v=version_for(c,pc,&in);context_free(&in);return v;
}
static Version *reserved_probe_edge(Compiler *c,uint32_t target,Context *x) {
    if(getenv("ABC_RESERVED_TRACE")&&!x->ncont&&x->c_bias) {
        fprintf(stderr,"PRE_CONFORM pc=%u origin=%d bias=%d\n",target,x->c_origin,x->c_bias);
        for(unsigned s=0;s<3;s++)for(uint32_t i=0;i<x->n[s];i++) {
            JValue *v=&x->s[s][i];
            fprintf(stderr,"CELL stack=%u index=%u kind=%u reg=%u source_stack=%u source_home=%d current_dst=%u:%d desired_home=%d\n",s,i,v->kind,v->reg,v->stack,v->home,v->dst_stack,v->dst_home,s==JS_C?abc_symbolic_c_home(x,i):(int32_t)i);
        }
    }
    if(!conform_generic(c,x)||!emit_reserved_event(c,1))return NULL;
    if(!x->ncont){
        Version *v=version_for(c,target,x);unsigned count=0;
        for(Version *q=c->versions[target];q;q=q->next)count++;
        fprintf(stderr,"LEGACY_GENERAL pc=%u bias=%d versions_at_pc=%u\n",target,x->c_bias,count);
        return v;
    }
    if(x->ncont>32)return NULL; /* fixture bound, not a proposed execution limit */
    const VCont *leaf=&x->cont[x->ncont-1];
    int fi=containing_function(c->module,target);if(fi<0)return NULL;
    const abc_function *fn=&c->module->functions[fi];
    Version *general=probe_general_version(c,target,fn->arguments,
        x->n[JS_A]-leaf->abase,x->n[JS_B]-leaf->bbase,x->n[JS_C]-leaf->cbase);
    if(!general)return NULL;
    unsigned prior=0;for(Version *v=c->versions[target];v;v=v->next)prior++;
    fprintf(stderr,"MATERIALIZE pc=%u continuations=%u general_versions_at_pc=%u\n",target,x->ncont,prior);
    uint8_t *resume[32];
    Fixup skip;
    if(!local_branch(c,ABC_STENCIL_JUMP,&skip))return NULL;
    /* Each actual RET jumps to one of these native labels, not through C. */
    for(unsigned i=0;i<x->ncont;i++) {
        const VCont *f=&x->cont[i];
        int parent=containing_function(c->module,f->return_pc);
        int child=abc_find_function(c->module,f->target);
        if(parent<0||child<0)return NULL;
        unsigned results=c->module->functions[child].results;
        /* A tail call can change the active callee's argument count/origin.
           Restore from its actual origin, not the original CALL signature. */
        int32_t child_bias=i+1<x->ncont?x->cont[i+1].old_bias:x->c_bias;
        uint32_t pa=i?x->cont[i-1].abase:0,pb=i?x->cont[i-1].bbase:0,pcbase=i?x->cont[i-1].cbase:0;
        Version *to=probe_general_version(c,f->return_pc,c->module->functions[parent].arguments,
            f->abase-pa+(f->dst==JS_A?results:0),f->bbase-pb+(f->dst==JS_B?results:0),f->cbase-pcbase);
        if(!to)return NULL;
        resume[i]=c->pos;
        if(!rebase_frame(c,-(int64_t)f->abase*8,-(int64_t)f->bbase*8,-(int64_t)child_bias*8))return NULL;
        if(f->dst==JS_B)for(unsigned j=0;j<results;j++)
            if(!place(c,ABC_STENCIL_LOAD(JS_A,0),(uint64_t)(f->abase+j)*8,NULL)||
               !place(c,ABC_STENCIL_STORE(JS_B,0),(uint64_t)(f->bbase+j)*8,NULL))return NULL;
        if(!emit_reserved_event(c,3)||!rebase_frame(c,(int64_t)pa*8,(int64_t)pb*8,(int64_t)f->old_bias*8)||
           !place(c,ABC_STENCIL_JUMP,0,to))return NULL;
    }
    bind_local(c,&skip);
    for(unsigned i=0;i<x->ncont;i++) {
        const VCont *f=&x->cont[i];
        int32_t slot=f->old_bias+(int32_t)f->cbase-f->old_origin;
        Fixup fix;
        if(!local_reference(c,ABC_STENCIL_STORE_LABEL,(uint64_t)((int64_t)slot*8),&fix))return NULL;
        patch(fix.site,fix.kind,fix.addend,(int64_t)(intptr_t)resume[i]);
    }
    if(!rebase_frame(c,(int64_t)leaf->abase*8,(int64_t)leaf->bbase*8,(int64_t)x->c_bias*8))return NULL;
    return general;
}
