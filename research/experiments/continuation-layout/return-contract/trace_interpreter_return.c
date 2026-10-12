/* Diagnostic: real generated handlers, stopping at the caller's resume PC.
   The private HALT only publishes state after RET; it does not change RET. */
#include "generated/banked.h"
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
static int check(int ok,const char *why){if(!ok)fprintf(stderr,"return trace: %s\n",why);return ok;}
int main(int argc,char **argv){
    if(argc!=3)return 2;unsigned to_b=!strcmp(argv[2],"B");
    abc_module *m=NULL;abc_vm *v=NULL;abc_error e={0};abc_limits limits={.stack_cells=128,.mode=ABC_EXEC_INTERPRETED};
    if(abc_module_read(argv[1],&m,&e)!=ABC_OK||abc_vm_create(&limits,&v,&e)!=ABC_OK||abc_vm_load(v,m,&e)!=ABC_OK){fprintf(stderr,"%s\n",e.message);return 1;}
    abc_image *im=v->images;const uint32_t entry=0x2f3,resume=0x2c6;
    if(!check(m->functions[2].entry==entry&&m->code[entry]==OP_CGET0_A,"fixture entry changed"))return 1;
    v->a[0]=111;v->a[1]=333;v->na=2;v->b[0]=222;v->b[1]=444;v->nb=2;
    uint64_t main_ref=(uint64_t)(uintptr_t)(v->c+1),middle_ref=(uint64_t)(uintptr_t)(v->c+6);
    uint64_t cells[]={UINT32_MAX,101,777,0x28,7,main_ref,202,888,resume,7,middle_ref,main_ref};
    memcpy(v->c,cells,sizeof cells);v->nc=12;
    v->frames[0]=(abc_frame){0,to_b};v->frames[1]=(abc_frame){resume,to_b};v->nf=2;
    memcpy(im->bytes,&main_ref,8);memcpy(im->bytes+8,&middle_ref,8);im->code[resume]=OP_HALT;
    abc_run run={v,m,im,im->code,&e,entry,0};abc_active_run=&run;
    abc_status status=(abc_status)abc_tables[0][im->code[entry]](im->code+entry,v->a+2,v->b+2,v->c+12,0,0,0,0,0,0,0);
    abc_active_run=NULL;
    if(!check(status==ABC_OK&&run.done&&run.pc==resume+1,e.message)||!check(v->nc==8&&v->nf==1,"RET must pop the frame and its continuation")||!check(v->na==(to_b?2u:4u)&&v->nb==(to_b?4u:2u),"result depths"))return 1;
    if(!check(v->a[0]==111&&v->a[1]==333&&v->b[0]==222&&v->b[1]==444,"caller operands"))return 1;
    uint64_t *results=to_b?v->b+2:v->a+2;if(!check(results[0]==607&&results[1]==17,"ordered results"))return 1;
    printf("INTERPRETER_RETURN destination=%s original_argument_end=12 tail_argument_end=13 continuation_slot=8 caller_C_top=%zu results=%" PRIu64 ",%" PRIu64 "\n",argv[2],v->nc,results[0],results[1]);
    abc_vm_free(v);abc_module_free(m);return 0;
}
