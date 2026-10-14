#include "execution_emit.h"
#include "threaded.h"

typedef struct { size_t word; abc_exec_label target; uint32_t pc; } ThreadFixup;
typedef struct {
    abc_exec_emitter emitter;
    abc_thread_word *code;size_t count,capacity;
    size_t *labels,nlabels,label_cap;
    ThreadFixup *fixups;size_t nfix,fix_cap;
    unsigned published;
} ThreadImage;
static int grow(void **p,size_t *capacity,size_t need,size_t size) {
    if(need<=*capacity)return 1;if(need>SIZE_MAX/size)return 0;
    size_t n=*capacity?*capacity:32;
    while(n<need){if(n>SIZE_MAX/2){n=need;break;}n*=2;}
    if(n>SIZE_MAX/size)n=need;
    void *q=realloc(*p,n*size);if(!q)return 0;*p=q;*capacity=n;return 1;
}
static abc_status new_label(abc_exec_emitter *emitter,abc_exec_label *out,uint32_t pc,abc_error *error) {
    ThreadImage *t=(ThreadImage *)emitter;*out=ABC_EXEC_NO_LABEL;
    if(t->published)return abc_fail(error,ABC_INVALID,pc,"threaded image is published");
    if(t->nlabels>=ABC_EXEC_NO_LABEL||!grow((void **)&t->labels,&t->label_cap,t->nlabels+1,sizeof *t->labels))return abc_fail(error,ABC_NOMEM,pc,"execution label allocation failed");
    *out=(abc_exec_label)t->nlabels;t->labels[t->nlabels++]=SIZE_MAX;return ABC_OK;
}
static abc_status bind_label(abc_exec_emitter *emitter,abc_exec_label label,uint32_t pc,abc_error *error) {
    ThreadImage *t=(ThreadImage *)emitter;
    if(t->published||label>=t->nlabels||t->labels[label]!=SIZE_MAX)return abc_fail(error,ABC_INVALID,pc,"invalid or already bound execution label");
    t->labels[label]=t->count;return ABC_OK;
}
static abc_status emit(abc_exec_emitter *emitter,unsigned form,const abc_exec_operands *op,uint32_t pc,abc_error *error) {
    ThreadImage *t=(ThreadImage *)emitter;
    if(t->published)return abc_fail(error,ABC_INVALID,pc,"threaded image is published");
    if(form>=ABC_FORM_COUNT||!abc_thread_forms[form].handler)return abc_fail(error,ABC_INVALID,pc,"unavailable threaded execution form");
    const abc_thread_form *f=&abc_thread_forms[form];
    if((f->target_word!=0)!=(op->target!=ABC_EXEC_NO_LABEL)||(f->target_word&&op->target>=t->nlabels))return abc_fail(error,ABC_INVALID,pc,"invalid threaded target operand");
    if(t->count>SIZE_MAX-f->words||!grow((void **)&t->code,&t->capacity,t->count+f->words,sizeof *t->code))return abc_fail(error,ABC_NOMEM,pc,"threaded tape allocation failed");
    if(f->target_word&&!grow((void **)&t->fixups,&t->fix_cap,t->nfix+1,sizeof *t->fixups))return abc_fail(error,ABC_NOMEM,pc,"threaded fixup allocation failed");
    size_t start=t->count;t->code[start].handler=f->handler;
    unsigned operand=0;
    for(unsigned word=1;word<f->words;word++){
        if(word==f->target_word){
            t->code[start+word].target=NULL;t->fixups[t->nfix++]=(ThreadFixup){start+word,op->target,pc};
        }else t->code[start+word].bits=op->value[operand++];
    }
    t->count+=f->words;return ABC_OK;
}
static abc_status publish(abc_exec_emitter *emitter,uint32_t pc,abc_error *error) {
    ThreadImage *t=(ThreadImage *)emitter;(void)pc;
    if(t->published)return ABC_OK;
    for(size_t i=0;i<t->nfix;i++){
        ThreadFixup *f=&t->fixups[i];
        if(f->target>=t->nlabels||t->labels[f->target]>=t->count)return abc_fail(error,ABC_INVALID,f->pc,"unbound threaded target");
    }
    for(size_t i=0;i<t->nfix;i++)t->code[t->fixups[i].word].target=t->code+t->labels[t->fixups[i].target];
    t->published=1;return ABC_OK;
}
static uintptr_t address(const abc_exec_emitter *emitter,abc_exec_label label) {
    const ThreadImage *t=(const ThreadImage *)emitter;
    return t->published&&label<t->nlabels&&t->labels[label]<t->count?(uintptr_t)(t->code+t->labels[label]):0;
}
static abc_exec_storage storage(const abc_exec_emitter *emitter) {
    const ThreadImage *t=(const ThreadImage *)emitter;
    return (abc_exec_storage){t->count*sizeof *t->code,t->capacity*sizeof *t->code,1};
}
static abc_exec_region region(const abc_exec_emitter *emitter,size_t index) {
    const ThreadImage *t=(const ThreadImage *)emitter;
    return index?(abc_exec_region){0}:(abc_exec_region){(const uint8_t *)t->code,t->count*sizeof *t->code,t->capacity*sizeof *t->code};
}
static void discard_preparation(abc_exec_emitter *emitter) {
    ThreadImage *t=(ThreadImage *)emitter;
    free(t->labels);t->labels=NULL;t->nlabels=t->label_cap=0;
    free(t->fixups);t->fixups=NULL;t->nfix=t->fix_cap=0;
}
static void destroy(abc_exec_emitter *emitter) {
    if(!emitter)return;ThreadImage *t=(ThreadImage *)emitter;
    discard_preparation(emitter);free(t->code);free(t);
}
static abc_exec_exit enter(const abc_exec_emitter *emitter,abc_exec_context *context,const abc_resume_state *state) {
    (void)emitter;const abc_thread_word *ip=(const abc_thread_word *)state->entry;
    const uint64_t *r=state->value_register;
    context->disposition=ABC_EXEC_RETURNED;
    uint64_t result=ip[0].handler(ip,state->stack[0],state->stack[1],state->stack[2],r[0],r[1],r[2],r[3],r[4],r[5],r[6]);
    return (abc_exec_exit){context->disposition,result};
}
static const abc_exec_emitter_ops ops={new_label,bind_label,emit,NULL,publish,address,storage,discard_preparation,destroy,enter,NULL,region};
abc_status abc_threaded_emitter_create(abc_exec_emitter **out,abc_error *error) {
    *out=NULL;ThreadImage *t=calloc(1,sizeof *t);
    if(!t)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"threaded emitter allocation failed");
    t->emitter=(abc_exec_emitter){&ops,ABC_THREADED_VALUE_REGISTERS};*out=&t->emitter;return ABC_OK;
}
