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
    if(m->revision==ABC_LIFECYCLE_REVISION)printf("ABC2 revision 7; lifecycle entry metadata\n");
    for(uint32_t i=0;i<m->c_entry_count;i++)printf("C-entry image[%u] = function %u\n",m->c_entries[i].offset,m->c_entries[i].function);
    for(uint32_t i=0;i<m->function_count;i++) {
        const abc_function *f=&m->functions[i]; printf("function %u: %u arguments, %u results",i,f->arguments,f->results);
        if (m->memory_profile) {
            printf("; kinds "); for (uint32_t j=0;j<f->arguments;j++) putchar(f->argument_kinds[j]==ABC_KIND_FLOAT ? 'f' : f->argument_kinds[j]==ABC_KIND_ADDR ? 'a' : 'i');
            printf(" -> "); for (uint32_t j=0;j<f->results;j++) putchar(f->result_kinds[j]==ABC_KIND_FLOAT ? 'f' : f->result_kinds[j]==ABC_KIND_ADDR ? 'a' : 'i');
            if (f->hidden_bytes) printf("; hidden=%u bytes",f->hidden_bytes);
        }
        if(f->c_entry)printf("; lifecycle C entry (not ABC-callable)");
        putchar('\n');
        for(uint32_t pc=f->entry;pc<f->end;) {
            abc_decoded_instruction instruction;
            abc_decode_instruction(m->code+pc,f->end-pc,&instruction);
            const abc_instruction_metadata *metadata=instruction.metadata;
            const uint8_t *operand=instruction.operands;
            unsigned len=instruction.length,kind=metadata->kind;uint32_t next=pc+len;
            char name[64];
            if(abc_core_instructions[m->code[pc]].kind==K_EXT)
                snprintf(name,sizeof name,"%s_%c",metadata->name,instruction.selected_stack==ABC_STACK_A?'A':'B');
            else snprintf(name,sizeof name,"%s",metadata->name);
            printf("  %08x  %-14s",pc,name);
            if(kind==K_BRANCH)printf(" 0x%08x",(uint32_t)((int64_t)next+abc_i16(operand)));
            else if(kind==K_JMP32)printf(" 0x%08x",(uint32_t)((int64_t)next+abc_i32(operand)));
            else if(kind==K_BRI)printf(" %" PRId64 " 0x%08x",abc_signed(abc_imm8(operand[0])),(uint32_t)((int64_t)next+abc_i16(operand+1)));
            else if(kind==K_SWITCH){unsigned count=abc_u16(operand);printf(" %u",count);for(unsigned entry=0;entry<count;entry++)printf(" 0x%08x",(uint32_t)((int64_t)next+abc_i32(operand+2+4*entry)));}
            else if(kind==K_CALL||kind==K_TCALL){printf(" 0x%08x %u",(uint32_t)((int64_t)next+abc_i32(operand)),operand[4]);if(kind==K_TCALL)printf(" %u",operand[5]);}
            else if(kind==K_ICALL||kind==K_ITCALL){unsigned tail=kind==K_ITCALL;if(tail)printf(" frame=%u",operand[0]);printf(" args=%u results=%u",operand[tail?1:0],abc_find_site(m,pc)->results);}
            else if(kind==K_FCALL){unsigned external=abc_u16(operand);printf(" %u ; %s",external,m->externs[external].name);}
            else switch(metadata->operand_layout) {
                case ABC_LAYOUT_U8_U8:printf(" %u %u",operand[0],operand[1]);break;
                case ABC_LAYOUT_U8:printf(" %u",operand[0]);break;
                case ABC_LAYOUT_I8:printf(" %" PRId64,abc_signed(abc_imm8(operand[0])));break;
                case ABC_LAYOUT_U16:printf(" %u",abc_u16(operand));break;
                case ABC_LAYOUT_U32:printf(" %" PRIu32,abc_u32(operand));break;
                case ABC_LAYOUT_I32:printf(" %" PRId32,abc_i32(operand));break;
                case ABC_LAYOUT_U64:printf(" %" PRId64,abc_signed(abc_u64(operand)));break;
                default:break;
            }
            if (m->load_kinds && m->load_kinds[pc]) printf(" ; loadkind=%s",m->load_kinds[pc]==3 ? "float" : m->load_kinds[pc]==2 ? "addr" : "int");
            putchar('\n'); pc+=len;
        }
    }
    for(uint32_t i=0;i<m->export_count;i++) printf("export %s = function %u\n",m->exports[i].name,m->exports[i].function);
}
int main(int argc,char **argv) {
    if(argc==2 && !strcmp(argv[1],"opcodes")) {
        printf("["); int first=1;
        for(unsigned opcode=0;opcode<OP_COUNT;opcode++) {
            const abc_instruction_metadata *metadata=&abc_core_instructions[opcode];
            printf("%s{\"name\":\"%s\",\"opcode\":%u,\"length\":%u,\"kind\":%u,\"profile\":%u}",first?"":",",metadata->name,opcode,metadata->encoded_length,metadata->kind,metadata->minimum_profile);first=0;
        }
        for(unsigned selector=0;selector<EXT_COUNT;selector++)for(unsigned stack=0;stack<2;stack++) {
            const abc_instruction_metadata *metadata=&abc_extended_instructions[selector];
            printf(",{\"name\":\"%s_%c\",\"opcode\":%u,\"selector\":%u,\"length\":%u,\"kind\":%u,\"profile\":%u}",metadata->name,stack?'B':'A',OP_EXT_A+stack,selector,metadata->encoded_length,metadata->kind,metadata->minimum_profile);
        }
        puts("]"); return 0;
    }
    if(argc<3 || (strcmp(argv[1],"check") && strcmp(argv[1],"dis") && strcmp(argv[1],"run"))) {
        fprintf(stderr,"usage: abc-runtime check|dis module.abc\n       abc-runtime run module.abc [export [integer ...]] [--jit=off|threaded|lazy|eager] [--stack=N]\n"); return 2;
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
        } else if(!strncmp(argv[i],"--jit=",6)) {
            const char *mode=argv[i]+6;
            if(!strcmp(mode,"off"))limits.mode=ABC_EXEC_INTERPRETED;
            else if(!strcmp(mode,"threaded"))limits.mode=ABC_EXEC_THREADED;
            else if(!strcmp(mode,"lazy"))limits.mode=ABC_EXEC_LAZY;
            else if(!strcmp(mode,"eager"))limits.mode=ABC_EXEC_COMPILED;
            else {fprintf(stderr,"abc: invalid execution policy: %s\n",mode);rc=2;goto done;}
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

