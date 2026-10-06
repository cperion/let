#include "internal.h"
#include <inttypes.h>
#include <errno.h>

static int report(abc_error *e) {
    fprintf(stderr,"abc: %s",abc_status_name(e->status));
    if(e->offset!=UINT32_MAX) fprintf(stderr," at byte 0x%x",e->offset);
    fprintf(stderr,": %s\n",e->message); return 1;
}
static int number(const char *s,uint64_t *out) {
    if(!s || !*s || *s==' ' || *s=='+') return 0;
    int negative=*s=='-'; if(negative) s++; if(!*s) return 0;
    errno=0; char *end; uint64_t v=strtoull(s,&end,0);
    if(errno || *end || (negative && v>UINT64_C(0x8000000000000000))) return 0;
    *out=negative ? 0-v : v; return 1;
}
static void disassemble(const abc_module *m) {
    for(uint32_t i=0;i<m->function_count;i++) {
        const abc_function *f=&m->functions[i]; printf("function %u: %u arguments, %u results",i,f->arguments,f->results);
        if (m->memory_profile) {
            printf("; kinds "); for (uint32_t j=0;j<f->arguments;j++) putchar(f->argument_kinds[j]==ABC_KIND_FLOAT ? 'f' : f->argument_kinds[j]==ABC_KIND_ADDR ? 'a' : 'i');
            printf(" -> "); for (uint32_t j=0;j<f->results;j++) putchar(f->result_kinds[j]==ABC_KIND_FLOAT ? 'f' : f->result_kinds[j]==ABC_KIND_ADDR ? 'a' : 'i');
            if (f->hidden_bytes) printf("; hidden=%u bytes",f->hidden_bytes);
        }
        putchar('\n');
        for(uint32_t pc=f->entry;pc<f->end;) {
            const uint8_t *p=m->code+pc; unsigned op=*p, len=abc_instruction_length(p), k=op_kind[op];
            printf("  %08x  %-14s",pc,op_name[op]);
            if(k==K_BRANCH) printf(" 0x%08x",(uint32_t)((int64_t)pc+len+abc_i16(p+1)));
            else if(k==K_JMP32) printf(" 0x%08x",(uint32_t)((int64_t)pc+len+abc_i32(p+1)));
            else if(k==K_SWITCH){unsigned count=abc_u16(p+1);printf(" %u",count);for(unsigned j=0;j<count;j++)printf(" 0x%08x",(uint32_t)((int64_t)pc+len+abc_i32(p+3+4*j)));}
            else if(k==K_BRI) printf(" %" PRId64 " 0x%08x",abc_signed(abc_imm8(p[1])),(uint32_t)((int64_t)pc+len+abc_i16(p+2)));
            else if(k==K_CALL || k==K_TCALL) { printf(" 0x%08x %u",(uint32_t)((int64_t)pc+len+abc_i32(p+1)),p[5]); if(k==K_TCALL) printf(" %u",p[6]); }
            else if(k==K_RET) printf(" %u %u",p[1],p[2]);
            else if(k==K_ICALL || k==K_ITCALL) {
                unsigned tail=k==K_ITCALL; if (tail) printf(" frame=%u",p[1]);
                const abc_function *s=abc_find_site(m,pc);
                printf(" args=%u results=%u cache=%u",p[tail ? 2 : 1],s->results,abc_u32(p+(tail ? 3 : 2)));
            }
            else if(op==OP_CGETR_A || op==OP_CGETR_B) printf(" %u %u",p[1],p[2]);
            else if(len==2) printf(" %" PRId64,k==K_OPI || op==OP_PUSH8_A || op==OP_PUSH8_B ? abc_signed(abc_imm8(p[1])) : (int64_t)p[1]);
            else if(k==K_MEMORY && len==3) printf(" %u",abc_u16(p+1));
            else if(k==K_MEMORY && len==5) printf(" %" PRIu32,abc_u32(p+1));
            else if(k==K_FCALL) { unsigned index=abc_u16(p+1); printf(" %u",index); if(index<m->extern_count)printf(" ; %s",m->externs[index].name); }
            else if(len==5) printf(" %" PRId32,abc_i32(p+1)); else if(len==9) printf(" %" PRId64,abc_signed(abc_u64(p+1)));
            if (m->load_kinds && m->load_kinds[pc]) printf(" ; loadkind=%s",m->load_kinds[pc]==3 ? "float" : m->load_kinds[pc]==2 ? "addr" : "int");
            putchar('\n'); pc+=len;
        }
    }
    for(uint32_t i=0;i<m->export_count;i++) printf("export %s = function %u\n",m->exports[i].name,m->exports[i].function);
}
int main(int argc,char **argv) {
    if(argc==2 && !strcmp(argv[1],"opcodes")) {
        printf("["); int first=1;
        for(unsigned i=0;i<OP_COUNT;i++) if(op_kind[i]!=K_INTERNAL) {
            printf("%s{\"name\":\"%s\",\"opcode\":%u,\"length\":%u,\"kind\":%u}",first ? "" : ",",op_name[i],i,op_len[i],op_kind[i]); first=0;
        }
        puts("]"); return 0;
    }
    if(argc<3 || (strcmp(argv[1],"check") && strcmp(argv[1],"dis") && strcmp(argv[1],"run"))) {
        fprintf(stderr,"usage: abc-runtime check|dis module.abc\n       abc-runtime run module.abc [export [integer ...]] [--compiled|--lazy|--interpreted] [--stack=N]\n"); return 2;
    }
    abc_module *m=NULL; abc_vm *v=NULL; abc_error e; int rc=0;
    if(abc_module_read(argv[2],&m,&e)!=ABC_OK) return report(&e);
    if(!strcmp(argv[1],"check")) { printf("verified: ABC2 %s profile\n",m->callable_profile ? "callable" : m->memory_profile ? "memory" : "integer"); goto done; }
    if(!strcmp(argv[1],"dis")) { disassemble(m); goto done; }
    abc_limits limits={0}; const char *name="main"; uint64_t args[255], results[255]; size_t nargs=0,nres=0; int named=0;
    for(int i=3;i<argc;i++) {
        if(!strncmp(argv[i],"--stack=",8)) {
            uint64_t n;
            if(!number(argv[i]+8,&n) || !n || argv[i][8]=='-' || n>ABC_MAX_FILE) { fprintf(stderr,"abc: invalid stack limit\n"); rc=2; goto done; }
            limits.stack_cells=(size_t)n;
        } else if(!strcmp(argv[i],"--compiled")) limits.mode=ABC_EXEC_COMPILED;
        else if(!strcmp(argv[i],"--lazy")) limits.mode=ABC_EXEC_LAZY;
        else if(!strcmp(argv[i],"--interpreted")) limits.mode=ABC_EXEC_INTERPRETED;
        else if(!strncmp(argv[i],"--",2)) { fprintf(stderr,"abc: unknown option: %s\n",argv[i]); rc=2; goto done; }
        else if(!named) { name=argv[i]; named=1; }
        else if(nargs==255 || !number(argv[i],&args[nargs++])) { fprintf(stderr,"abc: invalid integer argument\n"); rc=2; goto done; }
    }
    if(abc_vm_create(&limits,&v,&e)!=ABC_OK || abc_vm_load(v,m,&e)!=ABC_OK || abc_vm_call(v,m,name,args,nargs,results,255,&nres,&e)!=ABC_OK) { rc=report(&e); goto done; }
    for(size_t i=0;i<nres;i++) printf("%s%" PRId64,i ? " " : "",abc_signed(results[i]));
    putchar('\n');
done: abc_vm_free(v); abc_module_free(m); return rc;
}

