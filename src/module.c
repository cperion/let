#include "internal.h"
#include <errno.h>

const char *abc_status_name(abc_status s) {
    static const char *names[] = {"ok", "invalid", "io", "out-of-memory", "export-not-found",
        "arguments", "abort", "stack-limit", "result-capacity"};
    return (unsigned)s < sizeof names / sizeof names[0] ? names[s] : "unknown";
}
void abc_module_free(abc_module *m) {
    if (!m || atomic_fetch_sub_explicit(&m->references, 1, memory_order_acq_rel) != 1) return;
    if (m->exports) for (uint32_t i = 0; i < m->export_count; i++) free(m->exports[i].name);
    if (m->externs) for (uint32_t i=0;i<m->extern_count;i++) free(m->externs[i].name);
    if(m->descriptors)for(uint32_t i=0;i<m->descriptor_count;i++)free(m->descriptors[i].payload);
    if(m->dynamic_constants)for(uint32_t i=0;i<m->dynamic_constant_count;i++)free(m->dynamic_constants[i].payload);
    free(m->exports); free(m->functions); free(m->code); free(m->image); free(m->load_kinds); free(m->sites); free(m->relocs); free(m->externs); free(m->descriptors); free(m->dynamic_constants); free(m->gc_roots); free(m);
}
int abc_find_export(const abc_module *m, const char *name) {
    if (!m || !name) return -1;
    for (uint32_t i = 0; i < m->export_count; i++) if (!strcmp(m->exports[i].name, name)) return (int)m->exports[i].function;
    return -1;
}
int abc_find_function(const abc_module *m, uint32_t entry) {
    uint32_t lo = 0, hi = m->function_count;
    while (lo < hi) { uint32_t mid = lo + (hi - lo) / 2;
        if (m->functions[mid].entry < entry) lo = mid + 1; else hi = mid; }
    return lo < m->function_count && m->functions[lo].entry == entry ? (int)lo : -1;
}
abc_status abc_module_export(const abc_module *m, const char *name, uint32_t *args, uint32_t *res, abc_error *e) {
    abc_clear(e); int f = abc_find_export(m, name);
    if (f < 0) return abc_fail(e, ABC_NOT_FOUND, UINT32_MAX, "unknown export '%s'", name ? name : "");
    if (args) *args = m->functions[f].arguments;
    if (res) *res = m->functions[f].results;
    return ABC_OK;
}

abc_status abc_module_export_signature(const abc_module *m,const char *name,abc_signature *out,abc_error *e) {
    abc_clear(e);
    if (!out) return abc_fail(e,ABC_INVALID,UINT32_MAX,"missing signature output");
    int fi=abc_find_export(m,name);
    if (fi<0) return abc_fail(e,ABC_NOT_FOUND,UINT32_MAX,"unknown export '%s'",name ? name : "");
    const abc_function *f=&m->functions[fi]; abc_signature s={0};
    s.arguments=f->arguments; s.results=f->results; s.hidden_result_bytes=f->hidden_bytes;
    memcpy(s.argument_kinds,f->argument_kinds,f->arguments); memcpy(s.result_kinds,f->result_kinds,f->results);
    *out=s; return ABC_OK;
}

const abc_function *abc_find_site(const abc_module *m,uint32_t pc) {
    uint32_t lo=0,hi=m->site_count;
    while (lo<hi) { uint32_t mid=lo+(hi-lo)/2; if (m->sites[mid].entry<pc) lo=mid+1; else hi=mid; }
    return lo<m->site_count && m->sites[lo].entry==pc ? &m->sites[lo] : NULL;
}
abc_status abc_module_export_address(const abc_module *m,const char *name,uint64_t *out,abc_error *e) {
    abc_clear(e); if (!out) return abc_fail(e,ABC_INVALID,UINT32_MAX,"missing code address output");
    int fi=abc_find_export(m,name); if (fi<0) return abc_fail(e,ABC_NOT_FOUND,UINT32_MAX,"unknown export '%s'",name ? name : "");
    if (m->functions[fi].has_halt) return abc_fail(e,ABC_INVALID,UINT32_MAX,"HALT export is not bytecode-callable");
    *out=(uint64_t)(uintptr_t)(m->code+m->functions[fi].entry); return ABC_OK;
}

/* Abstract depths are relative to the callee's private A/B region and its C frame.
 * Every supported instruction operates on integers; address/float instructions are
 * absent from this profile, so kind checking is implicit rather than guessed. */
typedef struct { uint32_t a, b, c; unsigned seen; } Shape;
static abc_status verify(abc_module *m, abc_error *e) {
    uint8_t *starts = calloc(m->code_size, 1);
    Shape *shapes = calloc(m->code_size, sizeof *shapes);
    uint32_t *work = malloc(m->code_size * sizeof *work);
    if (!starts || !shapes || !work) { free(starts); free(shapes); free(work); return abc_fail(e, ABC_NOMEM, UINT32_MAX, "verifier allocation failed"); }
    abc_status status = ABC_OK; uint32_t pc = 0;
    #define BAD(...) do { status = abc_fail(e, ABC_INVALID, pc, __VA_ARGS__); goto done; } while (0)
    for (uint32_t fi = 0; fi < m->function_count; fi++) {
        const abc_function *f = &m->functions[fi];
        for (pc = f->entry; pc < f->end;) {
            unsigned op = m->code[pc];
            if (op >= OP_LEGACY_COUNT || op_kind[op] == K_INTERNAL) BAD("unknown or internal opcode %u", op);
            if (op == OP_EXT) BAD("dynamic EXT instruction requires profile 5");
            uint32_t length=op_len[op]; if(op==OP_SWITCH){if(f->end-pc<3)BAD("truncated SWITCH instruction");length=3u+4u*abc_u16(m->code+pc+1);}
            if (length > f->end - pc) BAD("truncated instruction");
            if (op == OP_HALT) m->functions[fi].has_halt = 1;
            starts[pc] = 1; pc += length;
        }
    }
    /* Validate encoded edges even when their source is unreachable. */
    for (uint32_t fi = 0; fi < m->function_count; fi++) {
        const abc_function *f = &m->functions[fi];
        for (pc = f->entry; pc < f->end; pc += abc_instruction_length(m->code+pc)) {
            unsigned op = m->code[pc], kind = op_kind[op];
            uint32_t next = pc + abc_instruction_length(m->code+pc);
            if (kind == K_BRANCH || kind == K_BRI || kind==K_JMP32) {
                int64_t target = (int64_t)next + (kind==K_JMP32?abc_i32(m->code+pc+1):abc_i16(m->code + pc + (kind == K_BRI ? 2 : 1)));
                if (target < f->entry || target >= f->end || !starts[target]) BAD("branch target is not an instruction in this function");
            } else if(kind==K_SWITCH) for(unsigned j=0;j<abc_u16(m->code+pc+1);j++){int64_t target=(int64_t)next+abc_i32(m->code+pc+3+4*j);if(target<f->entry||target>=f->end||!starts[target])BAD("SWITCH target is not an instruction in this function");}
            if (kind == K_CALL || kind == K_TCALL) {
                int64_t target = (int64_t)next + abc_i32(m->code + pc + 1);
                int callee = target < 0 || target > UINT32_MAX ? -1 : abc_find_function(m, (uint32_t)target);
                if (callee < 0) BAD("call target is not a function entry");
                if (m->functions[callee].has_halt) BAD("a function containing HALT is host-entry-only");
                unsigned n = m->code[pc + (kind == K_CALL ? 5 : 6)];
                if (n != m->functions[callee].arguments) BAD("call argument count disagrees with function table");
                if (kind == K_TCALL && f->results != m->functions[callee].results) BAD("tail call result contract disagrees");
            }
        }
    }
    for (uint32_t fi = 0; fi < m->function_count; fi++) {
        abc_function *f = &m->functions[fi]; size_t nw = 0;
        f->max_a=f->max_b=0; f->max_c=f->arguments;
        shapes[f->entry] = (Shape){0, 0, f->arguments, 1}; work[nw++] = f->entry;
        while (nw) {
            pc = work[--nw]; const uint8_t *p = m->code + pc; unsigned op = p[0], kind = op_kind[op];
            Shape s = shapes[pc]; uint32_t next = pc + abc_instruction_length(p); int terminal = 0, branch = 0;
            #define NEED(A,B,C) do { if ((int64_t)s.a < (int64_t)(A) || (int64_t)s.b < (int64_t)(B) || (int64_t)s.c < (int64_t)(C)) BAD("stack underflow or C access outside own frame"); } while (0)
            if (op >= OP_ADD_A && op <= OP_LEU_B) { NEED(1,1,0); if ((op - OP_ADD_A) & 1) s.a--; else s.b--; }
            else if (kind == K_OPI) { if ((op - OP_ADDI_A) & 1) NEED(0,1,0); else NEED(1,0,0); }
            else if (kind == K_OPC) { NEED(0,0,(uint32_t)p[1]+1); if ((op - OP_ADDC_A) & 1) NEED(0,1,0); else NEED(1,0,0); }
            else if (op >= OP_NEG_A && op <= OP_SX32_B) { if ((op - OP_NEG_A) & 1) NEED(0,1,0); else NEED(1,0,0); }
            else if (op >= OP_ZX8 && op <= OP_CHKNN) { NEED(1,0,0); if (op == OP_POW || op == OP_POWS) { NEED(1,1,0); s.b--; } }
            else switch (op) {
                case OP_PUSH8_A: case OP_PUSH32_A: case OP_PUSH64_A: s.a++; break;
                case OP_PUSH8_B: case OP_PUSH32_B: case OP_PUSH64_B: s.b++; break;
                case OP_DUP_A: NEED(1,0,0); s.a++; break; case OP_DUP_B: NEED(0,1,0); s.b++; break;
                case OP_DROP_A: NEED(1,0,0); s.a--; break; case OP_DROP_B: NEED(0,1,0); s.b--; break;
                case OP_COPY_AB: NEED(1,0,0); s.b++; break; case OP_COPY_BA: NEED(0,1,0); s.a++; break;
                case OP_MOVE_AB: NEED(1,0,0); s.a--; s.b++; break; case OP_MOVE_BA: NEED(0,1,0); s.b--; s.a++; break;
                case OP_CPUSH_A: NEED(1,0,0); s.a--; s.c++; break; case OP_CPUSH_B: NEED(0,1,0); s.b--; s.c++; break;
                case OP_CPUSHN: NEED((uint32_t)p[1],0,0); s.a-=p[1]; s.c+=p[1]; break;
                case OP_CPOP: NEED(0,0,1); s.c--; break;
                case OP_CGET0_A: case OP_CGET1_A: case OP_CGETN_A:
                    NEED(0,0,op == OP_CGET0_A ? 1u : op == OP_CGET1_A ? 2u : (uint32_t)p[1]+1); s.a++; break;
                case OP_CGET0_B: case OP_CGET1_B: case OP_CGETN_B:
                    NEED(0,0,op == OP_CGET0_B ? 1u : op == OP_CGET1_B ? 2u : (uint32_t)p[1]+1); s.b++; break;
                case OP_CGETR_A: NEED(0,0,(uint32_t)p[1]+p[2]); s.a+=p[2]; break;
                case OP_CGETR_B: NEED(0,0,(uint32_t)p[1]+p[2]); s.b+=p[2]; break;
                case OP_CSET0_A: case OP_CSETN_A: NEED(1,0,op == OP_CSET0_A ? 1u : (uint32_t)p[1]+1); s.a--; break;
                case OP_CSET0_B: case OP_CSETN_B: NEED(0,1,op == OP_CSET0_B ? 1u : (uint32_t)p[1]+1); s.b--; break;
                case OP_JMP: case OP_JMP32: branch = 1; terminal = 1; break;
                case OP_SWITCH: NEED(1,0,0);s.a--;branch=2;break;
                case OP_JZ_A: case OP_JNZ_A: NEED(1,0,0); s.a--; branch = 1; break;
                case OP_JZ_B: case OP_JNZ_B: NEED(0,1,0); s.b--; branch = 1; break;
                case OP_BEQ: case OP_BNE: case OP_BLT: case OP_BLE: case OP_BLTU: case OP_BLEU: NEED(1,1,0); s.a--; s.b--; branch = 1; break;
                case OP_CALL_A: case OP_CALL_B: {
                    uint32_t target = (uint32_t)((int64_t)next + abc_i32(p+1));
                    const abc_function *callee = &m->functions[abc_find_function(m,target)];
                    NEED((uint32_t)p[5],0,0); s.a -= p[5];
                    if (op == OP_CALL_A) s.a += callee->results; else s.b += callee->results; break;
                }
                case OP_TCALL: NEED((uint32_t)p[6],0,0);
                    if (s.a != p[6] || s.b || s.c != p[5]) BAD("tail call must replace the complete current frame and operand region");
                    terminal = 1; break;
                case OP_RET:
                    if (s.c != p[1] || s.a != p[2] || s.b || p[2] != f->results) BAD("RET disagrees with frame or result contract");
                    terminal = 1; break;
                case OP_HALT:
                    if (s.c || s.b || s.a != f->results) BAD("HALT must leave only the declared results and an empty frame");
                    terminal = 1; break;
                case OP_ABORT: if (!p[1]) BAD("ABORT reason must be nonzero"); terminal = 1; break;
                default: if (kind == K_BRI) { NEED(1,0,0); s.a--; branch = 1; } else BAD("unsupported instruction");
            }
            if (s.a > ABC_MAX_FILE || s.b > ABC_MAX_FILE || s.c > ABC_MAX_FILE) BAD("abstract stack depth exceeds profile limit");
            if(s.a>f->max_a)f->max_a=s.a; if(s.b>f->max_b)f->max_b=s.b; if(s.c>f->max_c)f->max_c=s.c;
            unsigned ne=branch==2?(unsigned)abc_u16(p+1)+1u:(branch?1u:0u)+(!terminal?1u:0u);
            for(unsigned j=0;j<ne;j++){uint32_t edge;
                if(branch==2)edge=j<abc_u16(p+1)?(uint32_t)((int64_t)next+abc_i32(p+3+4*j)):next;
                else if(branch&&j==0)edge=(uint32_t)((int64_t)next+(kind==K_JMP32?abc_i32(p+1):abc_i16(p+(kind==K_BRI?2:1))));else edge=next;
                if(edge>=f->end)BAD("execution falls out of function");Shape *old=&shapes[edge];
                if (old->seen) { if (old->a != s.a || old->b != s.b || old->c != s.c) BAD("incompatible stack shapes at join"); }
                else { *old = s; old->seen = 1; work[nw++] = edge; }
            }
            #undef NEED
        }
    }
done:
    free(starts); free(shapes); free(work); return status;
    #undef BAD
}

abc_status abc_module_load(const void *bytes, size_t size, abc_module **out, abc_error *e) {
    abc_clear(e); if (out) *out = NULL;
    if (!out || !bytes || size < 16 || size > ABC_MAX_FILE) return abc_fail(e, ABC_INVALID, UINT32_MAX, "invalid module size or input");
    const uint8_t *p = bytes;
    if (!memcmp(p,"ABC2",4) && ((abc_u16(p+4)==2 && p[7]==2) || (abc_u16(p+4)==3 && p[7]==3) || (abc_u16(p+4)==4 && p[7]==4) || (abc_u16(p+4)==5 && p[7]==5))) return abc_load_memory(bytes,size,out,e);
    if (memcmp(p,"ABC2",4) || abc_u16(p+4) != 1 || p[6] != 8 || p[7] != 1 || abc_u32(p+12))
        return abc_fail(e, ABC_INVALID, UINT32_MAX, "expected ABC2 version 1, 64-bit integer profile");
    uint32_t sections = abc_u32(p+8); if (sections != 3) return abc_fail(e, ABC_INVALID, UINT32_MAX, "integer profile requires functions, code and exports");
    const uint8_t *sec[4] = {0}; uint32_t len[4] = {0}; size_t at = 16;
    for (uint32_t i=0; i<sections; i++) {
        if (size-at < 8) return abc_fail(e, ABC_INVALID, UINT32_MAX, "truncated section header");
        uint32_t tag=abc_u32(p+at), n=abc_u32(p+at+4); at+=8;
        if (tag<1 || tag>3 || sec[tag] || n>size-at) return abc_fail(e, ABC_INVALID, UINT32_MAX, "invalid, duplicate or unsupported section");
        sec[tag]=p+at; len[tag]=n; at+=n;
    }
    if (at!=size || !sec[1] || !sec[2] || !sec[3] || len[1]<4 || !len[2] || len[3]<4)
        return abc_fail(e, ABC_INVALID, UINT32_MAX, "missing sections or trailing bytes");
    uint32_t nf=abc_u32(sec[1]), nx=abc_u32(sec[3]);
    if (!nf || nf>ABC_MAX_FUNCTIONS || len[1] != 4+(uint64_t)nf*16 || nx>ABC_MAX_FUNCTIONS)
        return abc_fail(e, ABC_INVALID, UINT32_MAX, "invalid function or export table");
    abc_module *m=calloc(1,sizeof *m); if (!m) return abc_fail(e, ABC_NOMEM, UINT32_MAX, "module allocation failed");
    atomic_init(&m->references,1);
    m->function_count=nf; m->export_count=nx; m->code_size=len[2];
    m->functions=calloc(nf,sizeof *m->functions); m->exports=calloc(nx ? nx : 1,sizeof *m->exports); m->code=malloc(len[2]);
    abc_status status=ABC_INVALID;
    #define FAIL(...) do { status=abc_fail(e,ABC_INVALID,UINT32_MAX,__VA_ARGS__); goto failed; } while(0)
    if (!m->functions || !m->exports || !m->code) { status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"module allocation failed"); goto failed; }
    memcpy(m->code,sec[2],len[2]);
    for (uint32_t i=0;i<nf;i++) { const uint8_t *q=sec[1]+4+i*16; abc_function *f=&m->functions[i];
        f->entry=abc_u32(q); f->arguments=abc_u32(q+4); f->results=abc_u32(q+8);
        if ((i==0 && f->entry) || f->entry>=len[2] || (i && f->entry<=m->functions[i-1].entry) || f->arguments>255 || f->results>255 || abc_u32(q+12)) FAIL("invalid function entry/count or unsupported aggregate result");
        if (i) m->functions[i-1].end=f->entry;
    }
    m->functions[nf-1].end=len[2]; at=4;
    for (uint32_t i=0;i<nx;i++) {
        if (len[3]-at<6) FAIL("truncated export");
        uint32_t index=abc_u32(sec[3]+at); uint16_t n=abc_u16(sec[3]+at+4); at+=6;
        if (index>=nf || !n || n>255 || n>len[3]-at) FAIL("invalid export name or index");
        m->exports[i].name=malloc((size_t)n+1); if (!m->exports[i].name) { status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"export allocation failed"); goto failed; }
        for (unsigned j=0;j<n;j++) { unsigned c=sec[3][at+j];
            if (!(c=='_' || (c>='a'&&c<='z') || (c>='A'&&c<='Z') || (j && c>='0'&&c<='9'))) FAIL("export names must be ASCII identifiers");
        }
        memcpy(m->exports[i].name,sec[3]+at,n); m->exports[i].name[n]=0; m->exports[i].function=index; at+=n;
        for(uint32_t j=0;j<i;j++) if(!strcmp(m->exports[j].name,m->exports[i].name)) FAIL("duplicate export name");
    }
    if(at!=len[3]) FAIL("trailing export bytes");
    status=verify(m,e); if(status!=ABC_OK) goto failed; *out=m; return ABC_OK;
failed: abc_module_free(m); return status;
    #undef FAIL
}

abc_status abc_module_read(const char *path, abc_module **out, abc_error *e) {
    abc_clear(e); if(out) *out=NULL;
    if(!path || !out) return abc_fail(e,ABC_INVALID,UINT32_MAX,"missing path or output");
    FILE *f=fopen(path,"rb"); if(!f) return abc_fail(e,ABC_IO,UINT32_MAX,"cannot open '%s': %s",path,strerror(errno));
    if(fseek(f,0,SEEK_END) || ftell(f)<0) { fclose(f); return abc_fail(e,ABC_IO,UINT32_MAX,"cannot size module"); }
    long n=ftell(f); if(n>ABC_MAX_FILE || n<16) { fclose(f); return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid module size"); }
    rewind(f); uint8_t *buf=malloc((size_t)n); if(!buf) { fclose(f); return abc_fail(e,ABC_NOMEM,UINT32_MAX,"file allocation failed"); }
    size_t got=fread(buf,1,(size_t)n,f); int bad=ferror(f); fclose(f);
    abc_status s=got!=(size_t)n || bad ? abc_fail(e,ABC_IO,UINT32_MAX,"cannot read module") : abc_module_load(buf,(size_t)n,out,e);
    free(buf); return s;
}

