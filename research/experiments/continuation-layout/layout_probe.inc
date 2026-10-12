/* Experiment only: observe real emitted native state, then test continuation
 * insertion on a COPY. Never mutate the running VM or claim a general transfer
 * has been implemented. Fixed storage is sufficient for this bounded fixture. */
#include <stdio.h>
#include <inttypes.h>
typedef struct {
    uint32_t pc, na, nb, count;
    int32_t end, holes[32];
} LayoutProbe;
static LayoutProbe layout_probes[256];
static unsigned layout_probe_count;

static void inspect_layout(uint64_t *asp,uint64_t *bsp,uint64_t *csp,uint64_t id) {
    LayoutProbe *p=&layout_probes[id];
    abc_run *run=abc_active_run;
    uint64_t before[256],after[288];
    ptrdiff_t base=csp-run->v->c;
    size_t count=(size_t)(base+p->end),out=0;
    if(count>256||p->count>32)abort();
    memcpy(before,run->v->c,count*sizeof *before);
    for(size_t i=0;i<=count;i++) {
        for(unsigned h=0;h<p->count;h++)
            if((ptrdiff_t)i==base+p->holes[h])after[out++]=UINT64_C(0xc0110000)+h;
        if(i<count)after[out++]=before[i];
    }
    fprintf(stderr,"RUNTIME pc=%u virtual=%u cbase=%td cells=%zu holes=",p->pc,p->count,base,count);
    for(unsigned h=0;h<p->count;h++)fprintf(stderr,"%s%td",h?",":"",base+p->holes[h]);
    fprintf(stderr," A=");for(unsigned i=0;i<p->na;i++)fprintf(stderr,"%s%" PRIu64,i?",":"",asp[i]);
    fprintf(stderr," B=");for(unsigned i=0;i<p->nb;i++)fprintf(stderr,"%s%" PRIu64,i?",":"",bsp[i]);
    fprintf(stderr,"\n");
    unsigned broken=0;
    for(unsigned r=0;r<3;r++) {
        uint64_t address=abc_u64(run->image->bytes+8*r);
        uintptr_t start=(uintptr_t)run->v->c;
        if(address<start||(address-start)%8||(address-start)/8>=count)abort();
        size_t old=(size_t)((address-start)/8),shift=0;
        for(unsigned h=0;h<p->count;h++)shift+=(ptrdiff_t)old>=base+p->holes[h];
        uint64_t expected=101*(r+1);
        if(before[old]!=expected||after[old+shift]!=expected)abort();
        broken+=shift!=0;
        fprintf(stderr,"ROOT %u old_cell=%zu canonical_cell=%zu old_pointer_reads=%" PRIu64 " expected=%" PRIu64 " identity=%s\n",
            r,old,old+shift,after[old],expected,shift?"MOVED":"stable");
        /* Updating through an unrevised alias must reach the canonical object. */
        uint64_t copy[288];memcpy(copy,after,out*sizeof *copy);copy[old]=UINT64_C(0xabcdef);
        if(shift&&copy[old+shift]==UINT64_C(0xabcdef))abort();
    }
    if(p->count&&!broken)abort();
    fprintf(stderr,"INSERTION_COUNTEREXAMPLE moved_roots=%u live_state_unmodified=1\n",broken);
}

static int emit_layout_probe(Compiler *c,Context *x,uint32_t pc) {
    if(layout_probe_count>=256||x->ncont>32)return 0;
    unsigned id=layout_probe_count++;
    LayoutProbe *p=&layout_probes[id];
    p->pc=pc;p->na=x->n[JS_A];p->nb=x->n[JS_B];p->count=x->ncont;
    p->end=x->c_bias+(int32_t)x->n[JS_C]-x->c_origin;
    for(unsigned i=0;i<x->ncont;i++) {
        const VCont *v=&x->cont[i];
        p->holes[i]=v->old_bias+(int32_t)v->cbase-v->old_origin;
    }
    unsigned existing=0;for(Version *v=c->versions[pc];v;v=v->next)existing++;
    fprintf(stderr,"COMPILE pc=%u virtual=%u existing_at_location=%u origin=%d bias=%d end=%d\n",pc,x->ncont,existing,x->c_origin,x->c_bias,p->end);
    /* Publish constants too; flush_context alone preserves them symbolically. */
    if(!conform_generic(c,x))return 0;
    const Stencil *s=&stencils[ABC_STENCIL_LAYOUT_PROBE];
    if(!reserve(c,s->len))return 0;
    uint8_t *at=c->pos;memcpy(at,s->code,s->len);c->pos+=s->len;
    for(unsigned i=0;i<s->nrel;i++) {
        const Reloc *r=&s->rel[i];int64_t value;
        if(r->hole==HOLE_NEXT)value=(int64_t)(intptr_t)c->pos;
        else if(r->hole==HOLE_FINAL)value=(int64_t)(intptr_t)inspect_layout;
        else if(r->hole==HOLE_IMM)value=id;
        else return 0;
        patch(at+r->off,r->kind,r->addend,value);
    }
    return 1;
}
