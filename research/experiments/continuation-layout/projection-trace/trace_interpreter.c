/* Diagnostic only: execute the real generated interpreter from leaf entry,
 * replacing a private-copy stop instruction with HALT to publish a snapshot. */
#include "generated/banked.h"
#include <inttypes.h>
#include <stdio.h>
static void cell(uint64_t x,uint64_t *main_object,uint64_t *middle_object){
    if(x==(uint64_t)(uintptr_t)main_object)fputs("MAIN_REF",stdout);
    else if(x==(uint64_t)(uintptr_t)middle_object)fputs("MIDDLE_REF",stdout);
    else if(x==UINT32_MAX)fputs("RETURN",stdout);
    else printf("%" PRIu64,x);
}
int main(int argc,char **argv){
    if(argc!=2)return 2;
    const uint32_t stops[]={0x2f3,0x2f4,0x2f5,0x2f7,0x2f9,0x300,0x303,0x308,0x30b,0x30e,0x313,0x318,0x319,0x31e,0x323,0x326};
    abc_module *m=NULL;abc_error e={0};
    if(abc_module_read(argv[1],&m,&e)!=ABC_OK){fprintf(stderr,"%s\n",e.message);return 1;}
    for(size_t k=0;k<sizeof stops/sizeof *stops;k++){
        abc_vm *v=NULL;abc_limits limits={.stack_cells=128,.mode=ABC_EXEC_INTERPRETED};
        if(abc_vm_create(&limits,&v,&e)!=ABC_OK||abc_vm_load(v,m,&e)!=ABC_OK)return 1;
        abc_image *im=v->images;uint64_t main_object=101,middle_object=202;
        v->c[0]=UINT32_MAX;v->c[1]=7;v->c[2]=(uint64_t)(uintptr_t)&middle_object;v->c[3]=(uint64_t)(uintptr_t)&main_object;
        v->nc=4;v->nf=1;v->frames[0]=(abc_frame){UINT32_MAX,0};
        memcpy(im->bytes,&v->c[3],8);memcpy(im->bytes+8,&v->c[2],8);
        uint32_t entry=m->functions[2].entry,stop=stops[k];
        if(entry!=0x2f3||stop>=m->code_size)return 2;
        im->code[stop]=OP_HALT;
        abc_run r={v,m,im,im->code,&e,entry,0};abc_active_run=&r;
        abc_status status=(abc_status)abc_tables[0][im->code[entry]](im->code+entry,v->a,v->b,v->c+4,0,0,0,0,0,0,0);
        abc_active_run=NULL;
        if(status!=ABC_OK||!r.done||r.pc!=stop+1){fprintf(stderr,"stop %x status %u pc %x %s\n",stop,status,r.pc,e.message);return 1;}
        printf("BEFORE %03x %-12s A=[",stop,op_name[m->code[stop]]);
        for(size_t i=0;i<v->na;i++){if(i)putchar(',');cell(v->a[i],&main_object,&middle_object);}fputs("] B=[",stdout);
        for(size_t i=0;i<v->nb;i++){if(i)putchar(',');cell(v->b[i],&main_object,&middle_object);}fputs("] C=[",stdout);
        for(size_t i=0;i<v->nc;i++){if(i)putchar(',');cell(v->c[i],&main_object,&middle_object);}puts("]");
        abc_vm_free(v);
    }
    abc_module_free(m);return 0;
}
