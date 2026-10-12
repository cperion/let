#include <stdio.h>
#include <inttypes.h>
static void projection_trace(const abc_symbolic_machine *m,const char *phase){
    const abc_symbolic_context *x=m->context;
    if(!getenv("ABC_PROJECTION_TRACE")||m->pc<0x2f3||m->pc>0x326||x->ncont)return;
    fprintf(stderr,"%s %03x %s origin=%d bias=%d generic=%u\n",phase,m->pc,op_name[m->code[m->pc]],x->c_origin,x->c_bias,x->generic);
    for(unsigned s=0;s<3;s++){
        fprintf(stderr," %c=[","ABC"[s]);
        for(uint32_t i=0;i<x->n[s];i++){
            const abc_symbolic_value *v=&x->s[s][i];if(i)fputc(',',stderr);
            if(v->kind==ABC_SYM_CONST)fprintf(stderr,"constant:%" PRIu64,v->constant);
            else if(v->kind==ABC_SYM_HOME)fprintf(stderr,"home:%c%d","ABC"[v->stack],v->home);
            else fprintf(stderr,"register:r%u",v->reg);
            fprintf(stderr,"->%c%d","ABC"[v->dst_stack],v->dst_home);
        }
        fputs("]\n",stderr);
    }
}
