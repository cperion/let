#include "internal.h"

/* Canonical persistent stacks: a join compares IDs, not just depths.
 * C nodes distinguish scalar cells from opaque padded byte blocks. */
typedef struct { uint32_t prev, span, bytes, depth; unsigned kind; } Node;
typedef struct { Node *nodes; uint32_t *hash; uint32_t count, capacity, hash_size; abc_status error; } Pool;
typedef struct { uint32_t a, b, c; unsigned seen; } Shape;
enum { MAX_NODES = 1048576 };
static uint32_t hash_node(Node n) {
    return n.prev*UINT32_C(2654435761) ^ n.span*UINT32_C(2246822519) ^ n.bytes*UINT32_C(3266489917) ^ n.kind;
}
static int same_node(Node a, Node b) { return a.prev==b.prev && a.span==b.span && a.bytes==b.bytes && a.kind==b.kind; }
static uint32_t intern(Pool *pool, uint32_t prev, unsigned kind, uint32_t span, uint32_t bytes) {
    if (pool->error) return 0;
    Node n={prev,span,bytes,pool->nodes[prev].depth+span,kind};
    if (n.depth>ABC_MAX_FILE) { pool->error=ABC_INVALID; return 0; }
    uint32_t slot=hash_node(n)&(pool->hash_size-1);
    while (pool->hash[slot]) {
        uint32_t id=pool->hash[slot]; if (same_node(n,pool->nodes[id])) return id;
        slot=(slot+1)&(pool->hash_size-1);
    }
    if (pool->count==MAX_NODES) { pool->error=ABC_INVALID; return 0; }
    if (pool->count==pool->capacity) {
        uint32_t cap=pool->capacity*2; Node *nodes=realloc(pool->nodes,(size_t)cap*sizeof *nodes);
        if (!nodes) { pool->error=ABC_NOMEM; return 0; } pool->nodes=nodes; pool->capacity=cap;
    }
    uint32_t id=pool->count++; pool->nodes[id]=n; pool->hash[slot]=id;
    if ((uint64_t)pool->count*4>pool->hash_size*3) {
        uint32_t size=pool->hash_size*2; uint32_t *table=calloc(size,sizeof *table);
        if (!table) { pool->error=ABC_NOMEM; return 0; }
        for (uint32_t i=1;i<pool->count;i++) {
            uint32_t at=hash_node(pool->nodes[i])&(size-1); while (table[at]) at=(at+1)&(size-1); table[at]=i;
        }
        free(pool->hash); pool->hash=table; pool->hash_size=size;
    }
    return id;
}
static uint32_t push(Pool *p,uint32_t stack,unsigned kind) { return intern(p,stack,kind,1,0); }
static uint32_t cslot(const Pool *p,uint32_t c,uint32_t depth) {
    while (c) { Node n=p->nodes[c]; if (depth<n.span) return n.kind==ABC_KIND_BLOCK ? 0 : c; depth-=n.span; c=n.prev; }
    return 0;
}
static uint32_t cset(Pool *p,uint32_t c,uint32_t depth,unsigned kind) {
    uint32_t prefix[256], count=0, cursor=c;
    while (depth>=p->nodes[cursor].span) { prefix[count++]=cursor; depth-=p->nodes[cursor].span; cursor=p->nodes[cursor].prev; }
    if (p->nodes[cursor].kind==kind) return c;
    uint32_t result=push(p,p->nodes[cursor].prev,kind);
    while (count) { Node n=p->nodes[prefix[--count]]; result=intern(p,result,n.kind,n.span,n.bytes); }
    return result;
}
static int frame_access(const Pool *p,uint32_t c,uint32_t offset,unsigned width) {
    uint32_t above=0;
    while (c) {
        Node n=p->nodes[c]; uint32_t extent=n.span*8;
        if (offset>above && offset<=above+extent) {
            uint32_t index=above+extent-offset;
            return n.kind==ABC_KIND_BLOCK && index<n.bytes && width<=n.bytes-index;
        }
        above+=extent; c=n.prev;
    }
    return 0;
}
static int result_shape(const Pool *p,uint32_t a,const abc_function *f) {
    for (uint32_t i=f->results;i;i--) { if (!a || p->nodes[a].kind!=f->result_kinds[i-1]) return 0; a=p->nodes[a].prev; }
    return !a;
}
static int load64(unsigned op) {
    abc_memory_op m=op_memory[op]; return m.width==8 && (m.action==M_FLOAD || m.action==M_GLOAD || m.action==M_PLOAD || m.action==M_XLOAD);
}
static int value_kind(unsigned kind) { return kind==ABC_KIND_INT || kind==ABC_KIND_ADDR || kind==ABC_KIND_FLOAT; }
static int module_kind(const abc_module *m,unsigned kind) { return value_kind(kind) || (m->dynamic_profile && kind==ABC_KIND_ANY); }
static int consume_kind(Pool *p,uint32_t *stack,unsigned kind){if(!*stack||p->nodes[*stack].kind!=kind)return 0;*stack=p->nodes[*stack].prev;return 1;}
static int descriptor_stack_kind(const abc_module *m,uint32_t index,unsigned *count,unsigned kinds[2]){
    if(index>=m->descriptor_count)return 0;const abc_descriptor *d=&m->descriptors[index];*count=0;
    if(d->tag==ABC_DESC_PRIMITIVE){unsigned p=d->payload[0];if(p==ABC_PRIM_UNIT)return 1;if(p==ABC_PRIM_STRING){*count=2;kinds[0]=ABC_KIND_ADDR;kinds[1]=ABC_KIND_INT;return 1;}*count=1;kinds[0]=p==ABC_PRIM_F64?ABC_KIND_FLOAT:p==ABC_PRIM_ANY||p==ABC_PRIM_WORD?ABC_KIND_ANY:ABC_KIND_INT;return 1;}
    if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_RECORD||d->tag==ABC_DESC_ARRAY||d->tag==ABC_DESC_SUM){*count=1;kinds[0]=ABC_KIND_ADDR;return 1;}if(d->tag==ABC_DESC_SLICE){*count=2;kinds[0]=ABC_KIND_ADDR;kinds[1]=ABC_KIND_INT;return 1;}return 0;
}
static int descriptor_signature_matches(const abc_module *m,uint32_t signature,const abc_function *f,unsigned environment){const abc_descriptor *d=&m->descriptors[signature];if(d->tag!=ABC_DESC_SIGNATURE)return 0;const uint8_t *p=d->payload;unsigned ai=environment,ri=0;if(environment&&(!f->arguments||f->argument_kinds[0]!=ABC_KIND_ADDR))return 0;for(unsigned i=0;i<p[0];i++){unsigned n=0,kinds[2];if(!descriptor_stack_kind(m,abc_u32(p+2+4*i),&n,kinds)||ai+n>f->arguments)return 0;for(unsigned j=0;j<n;j++)if(f->argument_kinds[ai++]!=kinds[j])return 0;}for(unsigned i=0;i<p[1];i++){unsigned n=0,kinds[2];if(!descriptor_stack_kind(m,abc_u32(p+2+4*(p[0]+i)),&n,kinds)||ri+n>f->results)return 0;for(unsigned j=0;j<n;j++)if(f->result_kinds[ri++]!=kinds[j])return 0;}return ai==f->arguments&&ri==f->results;}
static uint32_t descriptor_size(const abc_module *m,uint32_t index){if(index>=m->descriptor_count)return UINT32_MAX;const abc_descriptor *d=&m->descriptors[index];if(d->tag==ABC_DESC_PRIMITIVE){unsigned p=d->payload[0];return p==ABC_PRIM_UNIT?0:p==ABC_PRIM_STRING?16:8;}if(d->tag==ABC_DESC_POINTER)return 8;if(d->tag==ABC_DESC_SLICE)return 16;if(d->tag==ABC_DESC_RECORD||d->tag==ABC_DESC_ARRAY||d->tag==ABC_DESC_SUM)return abc_u32(d->payload);return UINT32_MAX;}
static unsigned descriptor_any_relation(const abc_module *m,uint32_t di,uint32_t base,uint32_t off,unsigned width){const abc_descriptor *d=&m->descriptors[di];const uint8_t *p=d->payload;if(d->tag==ABC_DESC_PRIMITIVE){if(p[0]!=ABC_PRIM_ANY&&p[0]!=ABC_PRIM_WORD)return 0;return (uint64_t)off+width>base&&(uint64_t)base+8>off?(off==base&&width==8?3u:1u):0;}unsigned relation=0;if(d->tag==ABC_DESC_RECORD){for(uint32_t i=0;i<abc_u32(p+4);i++){const uint8_t *f=p+8+16*i;relation|=descriptor_any_relation(m,abc_u32(f+12),base+abc_u32(f+8),off,width);}}else if(d->tag==ABC_DESC_ARRAY){uint32_t element=abc_u32(p+8),stride=descriptor_size(m,element);for(uint32_t i=0;i<abc_u32(p+4);i++)relation|=descriptor_any_relation(m,element,base+i*stride,off,width);}else if(d->tag==ABC_DESC_SUM){for(unsigned i=0;i<p[9];i++){const uint8_t *c=p+12+16*i;relation|=descriptor_any_relation(m,abc_u32(c+12),base+abc_u32(c+8),off,width);}}return relation;}
static int root_index(const abc_module *m,uint32_t off){for(uint32_t i=0;i<m->gc_root_count;i++)if(descriptor_any_relation(m,m->gc_roots[i].descriptor,m->gc_roots[i].offset,off,8)&2u)return (int)i;return -1;}
static int overlaps_root(const abc_module *m,uint32_t off,unsigned width){for(uint32_t i=0;i<m->gc_root_count;i++)if(descriptor_any_relation(m,m->gc_roots[i].descriptor,m->gc_roots[i].offset,off,width)&1u)return 1;return 0;}
static abc_status verify_memory(abc_module *m,abc_error *e) {
    uint8_t *starts=calloc(m->code_size,1); Shape *shapes=calloc(m->code_size,sizeof *shapes);
    uint32_t *work=malloc(m->code_size*sizeof *work); Pool pool={0};
    pool.capacity=1024; pool.hash_size=2048; pool.count=1;
    pool.nodes=calloc(pool.capacity,sizeof *pool.nodes); pool.hash=calloc(pool.hash_size,sizeof *pool.hash);
    abc_status status=ABC_OK; uint32_t pc=0;
    #define BAD(...) do { status=abc_fail(e,ABC_INVALID,pc,__VA_ARGS__); goto done; } while(0)
    #define POOL_CHECK() do { if (pool.error) { status=abc_fail(e,pool.error,pc,"verifier state allocation/complexity limit reached"); goto done; } } while(0)
    if (!starts || !shapes || !work || !pool.nodes || !pool.hash) { status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"verifier allocation failed"); goto done; }
    for (uint32_t fi=0;fi<m->function_count;fi++) {
        abc_function *f=&m->functions[fi];
        for (pc=f->entry;pc<f->end;pc+=abc_instruction_length(m->code+pc)) {
            unsigned op=m->code[pc];
            if (op>=OP_COUNT || op_kind[op]==K_INTERNAL) BAD("unknown or internal opcode %u",op);
            if (op==OP_EXT) { if(!m->dynamic_profile)BAD("dynamic EXT instruction requires profile 5");if(f->end-pc<2) BAD("truncated EXT instruction"); unsigned ext=m->code[pc+1]; if (!ext_len[ext]) BAD("unknown extended opcode %u",ext); }
            uint32_t length=op==OP_SWITCH?(f->end-pc<3?0:3u+4u*abc_u16(m->code+pc+1)):abc_instruction_length(m->code+pc);if(!length)BAD("truncated SWITCH instruction");
            if (length>f->end-pc) BAD("truncated instruction");
            if (!m->callable_profile && (op_kind[op]==K_ICALL || op_kind[op]==K_ITCALL)) BAD("indirect opcode requires callable profile");
            if (op==OP_ABORT && !m->code[pc+1]) BAD("ABORT reason must be nonzero");
            if (op==OP_HALT) f->has_halt=1;
            starts[pc]=1;
        }
    }
    for (pc=0;pc<m->code_size;pc++) if (m->load_kinds[pc] && (!starts[pc] || !load64(m->code[pc]))) BAD("load kind annotation requires a 64-bit memory load");
    for (uint32_t i=0;i<m->site_count;i++) {
        const abc_function *site=&m->sites[i]; pc=site->entry;
        if (!starts[pc] || (op_kind[m->code[pc]]!=K_ICALL && op_kind[m->code[pc]]!=K_ITCALL)) BAD("site signature requires an indirect instruction");
    }
    for (uint32_t i=0;i<m->reloc_count;i++) if (m->functions[m->relocs[i].function].has_halt) BAD("code relocation targets host-entry-only function");
    for (uint32_t fi=0;fi<m->function_count;fi++) {
        const abc_function *f=&m->functions[fi];
        for (pc=f->entry;pc<f->end;pc+=abc_instruction_length(m->code+pc)) {
            const uint8_t *p=m->code+pc; unsigned op=p[0],kind=op_kind[op]; uint32_t next=pc+abc_instruction_length(p);
            if (kind==K_BRANCH || kind==K_BRI || kind==K_JMP32) {
                int64_t target=(int64_t)next+(kind==K_JMP32?abc_i32(p+1):abc_i16(p+(kind==K_BRI ? 2:1)));
                if (target<f->entry || target>=f->end || !starts[target]) BAD("branch target is not an instruction in this function");
            } else if(kind==K_SWITCH) for(unsigned j=0;j<abc_u16(p+1);j++){int64_t target=(int64_t)next+abc_i32(p+3+4*j);if(target<f->entry||target>=f->end||!starts[target])BAD("SWITCH target is not an instruction in this function");}
            if (kind==K_CALL || kind==K_TCALL) {
                int64_t target=(int64_t)next+abc_i32(p+1); int callee=target<0 || target>UINT32_MAX ? -1 : abc_find_function(m,(uint32_t)target);
                if (callee<0) BAD("call target is not a function entry");
                const abc_function *g=&m->functions[callee];
                if (g->has_halt) BAD("a function containing HALT is host-entry-only");
                if (p[kind==K_CALL ? 5 : 6]!=g->arguments) BAD("call argument count disagrees with function table");
                if (kind==K_TCALL && (f->results!=g->results || memcmp(f->result_kinds,g->result_kinds,f->results))) BAD("tail call result contract disagrees");
            }
            if (kind==K_ICALL || kind==K_ITCALL) {
                const abc_function *site=abc_find_site(m,pc); unsigned tail=kind==K_ITCALL;
                if (!site || p[tail ? 2 : 1]!=site->arguments) BAD("missing or inconsistent indirect signature");
                if (abc_u32(p+(tail ? 3 : 2))) BAD("serialized indirect cache must be zero");
                if (tail && (f->results!=site->results || memcmp(f->result_kinds,site->result_kinds,f->results))) BAD("indirect tail result contract disagrees");
            }
            if (kind==K_FCALL && (!m->foreign_profile || abc_u16(p+1)>=m->extern_count)) BAD("invalid foreign-call index");
            abc_memory_op mem=op_memory[op]; uint32_t off=op_len[op]==5 ? abc_u32(p+1) : op_len[op]==3 ? abc_u16(p+1) : 0;
            if (mem.action==M_GLOAD && ((uint64_t)off+mem.width>m->image_size)) BAD("image load outside image");
            if (mem.action==M_GSTORE && ((uint64_t)off+mem.width>m->data_size)) BAD("image store outside writable prefix");
            if (mem.action==M_GADDR && off>=m->image_size) BAD("image address outside image");
            if(m->dynamic_profile&&(mem.action==M_GLOAD||mem.action==M_GSTORE)&&overlaps_root(m,off,mem.width)){if(mem.width!=8||root_index(m,off)<0)BAD("dynamic root access must be one aligned 64-bit cell");if(mem.action==M_GLOAD&&m->load_kinds[pc]!=(uint8_t)(ABC_KIND_ANY+1))BAD("dynamic root load requires any kind annotation");}
        }
    }
    for (uint32_t fi=0;fi<m->function_count;fi++) {
        abc_function *f=&m->functions[fi]; size_t nw=0; uint32_t c=0;
        for (uint32_t i=f->arguments;i;i--) c=push(&pool,c,f->argument_kinds[i-1]);
        f->max_a=f->max_b=0; f->max_c=f->arguments;
        pc=f->entry; POOL_CHECK(); shapes[pc]=(Shape){0,0,c,1}; work[nw++]=pc;
        while (nw) {
            pc=work[--nw]; const uint8_t *p=m->code+pc; unsigned op=p[0],kind=op_kind[op];
            uint32_t next=pc+abc_instruction_length(p); Shape s=shapes[pc]; int terminal=0,branch=0;
            #define DEPTH(S) (pool.nodes[s.S].depth)
            #define NEED(A,B,C) do { if ((int64_t)DEPTH(a)<(int64_t)(A) || (int64_t)DEPTH(b)<(int64_t)(B) || (int64_t)DEPTH(c)<(int64_t)(C)) BAD("stack underflow or C access outside own frame"); } while(0)
            #define INTEGER(S) do { if (pool.nodes[s.S].kind!=ABC_KIND_INT) BAD("integer instruction given non-integer kind"); } while(0)
            #define FLOAT(S) do { if (pool.nodes[s.S].kind!=ABC_KIND_FLOAT) BAD("float instruction given non-float kind"); } while(0)
            #define ADDRESS(S) do { if (pool.nodes[s.S].kind!=ABC_KIND_ADDR) BAD("memory instruction requires address kind"); } while(0)
            #define POP(S) (s.S=pool.nodes[s.S].prev)
            if(op==OP_EXT){
                unsigned ext=p[1];
                if(ext==EXT_ANY_BOX||ext==EXT_ANY_CAST||ext==EXT_ANY_IS){uint32_t di=abc_u32(p+2);unsigned n=0,ks[2]={0};if(!descriptor_stack_kind(m,di,&n,ks))BAD("dynamic instruction has invalid descriptor");const abc_descriptor *d=&m->descriptors[di];if((d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE)&&(d->payload[0]==1||(d->tag==ABC_DESC_SLICE&&!d->payload[0])))BAD("unmanaged borrowed descriptor cannot enter any");if(ext==EXT_ANY_BOX){if((d->tag==ABC_DESC_PRIMITIVE&&(d->payload[0]==ABC_PRIM_ANY||d->payload[0]==ABC_PRIM_WORD)))BAD("ANY_BOX requires a boxable typed descriptor");for(unsigned j=n;j;j--)if(!consume_kind(&pool,&s.a,ks[j-1]))BAD("ANY_BOX source layout mismatch");s.a=push(&pool,s.a,ABC_KIND_ANY);}else{NEED(1,0,0);if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic cast/test requires any");POP(a);if(ext==EXT_ANY_IS)s.a=push(&pool,s.a,ABC_KIND_INT);else for(unsigned j=0;j<n;j++)s.a=push(&pool,s.a,ks[j]);}}
                else if(ext>=EXT_DNEG&&ext<=EXT_DLNOT){NEED(1,0,0);if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic unary operation requires any");POP(a);s.a=push(&pool,s.a,ext==EXT_DLNOT?ABC_KIND_INT:ABC_KIND_ANY);}
                else if(ext>=EXT_DADD&&ext<=EXT_DXOR){NEED(2,0,0);if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic binary operation requires any");POP(a);if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic binary operation requires any");POP(a);s.a=push(&pool,s.a,ABC_KIND_ANY);}
                else if(ext>=EXT_DADDL&&ext<=EXT_DXORL){uint32_t ci=abc_u32(p+2);if(ci>=m->dynamic_constant_count||p[6]>1)BAD("invalid dynamic literal operation");NEED(1,0,0);if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic literal operation requires any");}
                else if(ext>=EXT_DEQ&&ext<=EXT_DLE){NEED(2,0,0);if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic comparison requires any");POP(a);if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic comparison requires any");POP(a);s.a=push(&pool,s.a,ABC_KIND_INT);}
                else if(ext==EXT_DREQUIRE_BOOL){NEED(1,0,0);if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic condition requires any");POP(a);s.a=push(&pool,s.a,ABC_KIND_INT);}
                else if(ext==EXT_DCALL||ext==EXT_DTCALL){unsigned na=p[2],nr=p[3];if(p[4]>1||abc_u32(p+5))BAD("invalid dynamic-call mode or cache");NEED((uint32_t)na+1,0,0);if(ext==EXT_DTCALL&&(DEPTH(a)!=(uint32_t)na+1||s.b||nr!=f->results))BAD("dynamic tail call must replace the complete operand region and produce the declared results");for(unsigned j=0;j<=na;j++){if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic call requires any cells");POP(a);}for(unsigned j=0;j<nr;j++)s.a=push(&pool,s.a,ABC_KIND_ANY);if(ext==EXT_DTCALL){for(unsigned j=0;j<f->results;j++)if(f->result_kinds[j]!=ABC_KIND_ANY)BAD("dynamic tail-call results must be any");uint32_t frame=DEPTH(c);memcpy((uint8_t *)p+5,&frame,4);terminal=1;}}
                else if(ext==EXT_WORD_NEW){uint32_t di=abc_u32(p+2);if(di>=m->descriptor_count||m->descriptors[di].tag!=ABC_DESC_SIGNATURE)BAD("WORD_NEW requires signature descriptor");s.a=push(&pool,s.a,ABC_KIND_ANY);}
                else if((ext>=EXT_WORD_GET&&ext<=EXT_WORD_FREEZE)||ext==EXT_WORD_BIND){unsigned need=ext==EXT_WORD_COUNT||ext==EXT_WORD_FREEZE?1:ext==EXT_WORD_SET||ext==EXT_WORD_METHOD||ext==EXT_WORD_BIND?3:2;NEED(need,0,0);for(unsigned j=0;j<need;j++){if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("open-word operation requires any cells");POP(a);}unsigned out_kind=ext==EXT_WORD_HAS||ext==EXT_WORD_COUNT?ABC_KIND_INT:ABC_KIND_ANY;s.a=push(&pool,s.a,out_kind);}
                else if(ext==EXT_STRING_CAT||ext==EXT_STRING_TEXT){unsigned need=ext==EXT_STRING_CAT?2:1;NEED(need,0,0);for(unsigned j=0;j<need;j++){if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic string operation requires any");POP(a);}s.a=push(&pool,s.a,ABC_KIND_ANY);}
                else if(ext==EXT_MANAGED_NEW||ext==EXT_MANAGED_COPY){uint32_t di=abc_u32(p+2);if(di>=m->descriptor_count||descriptor_size(m,di)==UINT32_MAX||!descriptor_size(m,di))BAD("managed storage requires a nonempty value descriptor");if(ext==EXT_MANAGED_COPY){NEED(1,0,0);ADDRESS(a);POP(a);}s.a=push(&pool,s.a,ABC_KIND_ADDR);}
                else if(ext==EXT_WORD_DIRECT||ext==EXT_CLOSURE_NEW){uint32_t fi2=abc_u32(p+2),di=abc_u32(p+6);if(fi2>=m->function_count||di>=m->descriptor_count)BAD("invalid dynamic callable constructor");if(ext==EXT_WORD_DIRECT){if(!descriptor_signature_matches(m,di,&m->functions[fi2],0))BAD("WORD_DIRECT function disagrees with signature descriptor");}else{if(m->descriptors[di].tag!=ABC_DESC_CLOSURE)BAD("CLOSURE_NEW requires closure descriptor");uint32_t sig=abc_u32(m->descriptors[di].payload),rd=abc_u32(m->descriptors[di].payload+4);if(!descriptor_signature_matches(m,sig,&m->functions[fi2],1))BAD("closure function disagrees with signature descriptor");unsigned n=0,ks[2]={0};if(!descriptor_stack_kind(m,rd,&n,ks)||n!=1||ks[0]!=ABC_KIND_ADDR)BAD("invalid closure capture layout");NEED(1,0,0);ADDRESS(a);POP(a);}s.a=push(&pool,s.a,ABC_KIND_ANY);}
                else BAD("unsupported dynamic instruction");
            } else if(kind==K_MEMORY) {
                abc_memory_op mem=op_memory[op]; uint32_t off=op_len[op]==5 ? abc_u32(p+1) : op_len[op]==3 ? abc_u16(p+1) : 0;
                uint32_t *dst=mem.to_b ? &s.b : &s.a; unsigned loaded=m->load_kinds[pc] ? m->load_kinds[pc]-1 : ABC_KIND_INT;
                switch (mem.action) {
                    case M_ALLOC: if (off) s.c=intern(&pool,s.c,ABC_KIND_BLOCK,(off+7)/8,off); break;
                    case M_FREE:
                        if (off) { if (!s.c || pool.nodes[s.c].kind!=ABC_KIND_BLOCK || pool.nodes[s.c].bytes!=off) BAD("CFREE must release the complete top frame block"); POP(c); } break;
                    case M_FLOAD: case M_FSTORE: case M_FADDR:
                        if (!frame_access(&pool,s.c,off,mem.width)) BAD("frame access outside a live byte block");
                        if (mem.action==M_FSTORE) {
                            if (!*dst) BAD("stack underflow");
                            if (mem.width<8 && pool.nodes[*dst].kind!=ABC_KIND_INT) BAD("narrow store requires integer kind");
                            *dst=pool.nodes[*dst].prev;
                        } else *dst=push(&pool,*dst,mem.action==M_FADDR ? ABC_KIND_ADDR : loaded);
                        break;
                    case M_GLOAD: *dst=push(&pool,*dst,loaded); break;
                    case M_GSTORE: NEED(1,0,0); if(m->dynamic_profile&&root_index(m,off)>=0){if(pool.nodes[s.a].kind!=ABC_KIND_ANY)BAD("dynamic root store requires any kind");}else if (mem.width<8) INTEGER(a); POP(a); break;
                    case M_GADDR: *dst=push(&pool,*dst,ABC_KIND_ADDR); break;
                    case M_PLOAD:
                        if (!*dst) BAD("stack underflow");
                        if (pool.nodes[*dst].kind!=ABC_KIND_ADDR) BAD("memory instruction requires address kind");
                        *dst=push(&pool,pool.nodes[*dst].prev,loaded); break;
                    case M_PSTORE: NEED(1,1,0); ADDRESS(a); if (mem.width<8) INTEGER(b); POP(a); POP(b); break;
                    case M_XLOAD: NEED(1,1,0); ADDRESS(a); INTEGER(b); POP(a); POP(b); s.a=push(&pool,s.a,loaded); break;
                    case M_INDEX: NEED(1,1,0); ADDRESS(a); INTEGER(b); POP(b); break;
                    case M_COPY: NEED(1,1,0); ADDRESS(a); ADDRESS(b); POP(a); POP(b); break;
                    default: BAD("unsupported memory instruction");
                }
            } else if(kind==K_FCALL) {
                const abc_extern *ext=&m->externs[abc_u16(p+1)]; NEED(ext->arguments,0,0);
                for(uint32_t i=ext->arguments;i;i--){if(pool.nodes[s.a].kind!=ext->argument_kinds[i-1])BAD("foreign argument kind disagrees with signature");POP(a);}
                if(ext->results)s.a=push(&pool,s.a,ext->result_kinds[0]);
            } else if (op>=OP_ADD_A && op<=OP_LEU_B) {
                NEED(1,1,0); unsigned base=OP_ADD_A+((op-OP_ADD_A)&~1u);
                if ((base==OP_EQ_A || base==OP_NE_A) && pool.nodes[s.a].kind==ABC_KIND_ADDR && pool.nodes[s.b].kind==ABC_KIND_ADDR) { /* address identity permitted */ }
                else { INTEGER(a); INTEGER(b); }
                POP(a); POP(b); if ((op-OP_ADD_A)&1) s.b=push(&pool,s.b,ABC_KIND_INT); else s.a=push(&pool,s.a,ABC_KIND_INT);
            } else if (op>=OP_FADD_A && op<=OP_FEQ_B) {
                NEED(1,1,0); FLOAT(a); FLOAT(b); unsigned compare=op>=OP_FLT_A; POP(a); POP(b);
                if ((op-OP_FADD_A)&1) s.b=push(&pool,s.b,compare?ABC_KIND_INT:ABC_KIND_FLOAT); else s.a=push(&pool,s.a,compare?ABC_KIND_INT:ABC_KIND_FLOAT);
            } else if (op>=OP_FNEG && op<=OP_F2IU) {
                NEED(1,0,0); unsigned from=pool.nodes[s.a].kind;
                if (op==OP_FNEG) { if(from!=ABC_KIND_FLOAT) BAD("FNEG requires float kind"); }
                else if (op==OP_I2FS || op==OP_I2FU) { if(from!=ABC_KIND_INT) BAD("integer-to-float conversion requires integer kind"); POP(a); s.a=push(&pool,s.a,ABC_KIND_FLOAT); }
                else { if(from!=ABC_KIND_FLOAT) BAD("float-to-integer conversion requires float kind"); POP(a); s.a=push(&pool,s.a,ABC_KIND_INT); }
            } else if (kind==K_OPI || kind==K_OPC) {
                unsigned index=op-(kind==K_OPI ? OP_ADDI_A : OP_ADDC_A);
                if (index&1) { NEED(0,1,0); INTEGER(b); } else { NEED(1,0,0); INTEGER(a); }
                if (kind==K_OPC) { uint32_t slot=cslot(&pool,s.c,p[1]); if (!slot) BAD("C arithmetic outside a scalar frame cell"); if (pool.nodes[slot].kind!=ABC_KIND_INT) BAD("C arithmetic requires integer kind"); }
            } else if (op>=OP_NEG_A && op<=OP_SX32_B) {
                if ((op-OP_NEG_A)&1) { NEED(0,1,0); INTEGER(b); } else { NEED(1,0,0); INTEGER(a); }
            } else if (op>=OP_ZX8 && op<=OP_CHKNN) {
                NEED(1,0,0); INTEGER(a); if (op==OP_POW || op==OP_POWS) { NEED(1,1,0); INTEGER(b); POP(b); }
            } else switch (op) {
                case OP_PUSH8_A: case OP_PUSH32_A: case OP_PUSH64_A: s.a=push(&pool,s.a,ABC_KIND_INT); break;
                case OP_PUSH8_B: case OP_PUSH32_B: case OP_PUSH64_B: s.b=push(&pool,s.b,ABC_KIND_INT); break;
                case OP_DUP_A: NEED(1,0,0); s.a=push(&pool,s.a,pool.nodes[s.a].kind); break;
                case OP_DUP_B: NEED(0,1,0); s.b=push(&pool,s.b,pool.nodes[s.b].kind); break;
                case OP_DROP_A: NEED(1,0,0); POP(a); break; case OP_DROP_B: NEED(0,1,0); POP(b); break;
                case OP_COPY_AB: case OP_MOVE_AB: NEED(1,0,0); s.b=push(&pool,s.b,pool.nodes[s.a].kind); if (op==OP_MOVE_AB) POP(a); break;
                case OP_COPY_BA: case OP_MOVE_BA: NEED(0,1,0); s.a=push(&pool,s.a,pool.nodes[s.b].kind); if (op==OP_MOVE_BA) POP(b); break;
                case OP_CPUSH_A: NEED(1,0,0); s.c=push(&pool,s.c,pool.nodes[s.a].kind); POP(a); break;
                case OP_CPUSH_B: NEED(0,1,0); s.c=push(&pool,s.c,pool.nodes[s.b].kind); POP(b); break;
                case OP_CPUSHN: NEED(p[1],0,0); for(unsigned j=0;j<p[1];j++){s.c=push(&pool,s.c,pool.nodes[s.a].kind);POP(a);} break;
                case OP_CPOP: NEED(0,0,1); if (pool.nodes[s.c].kind==ABC_KIND_BLOCK) BAD("CPOP cannot split a frame byte block"); POP(c); break;
                case OP_CGET0_A: case OP_CGET1_A: case OP_CGETN_A: case OP_CGET0_B: case OP_CGET1_B: case OP_CGETN_B: {
                    unsigned to_b=op>=OP_CGET0_B; uint32_t depth=(op==OP_CGET0_A || op==OP_CGET0_B) ? 0 : (op==OP_CGET1_A || op==OP_CGET1_B) ? 1 : p[1];
                    uint32_t slot=cslot(&pool,s.c,depth); if (!slot) BAD("CGET outside a scalar frame cell");
                    if (to_b) s.b=push(&pool,s.b,pool.nodes[slot].kind); else s.a=push(&pool,s.a,pool.nodes[slot].kind); break;
                }
                case OP_CGETR_A: case OP_CGETR_B: {
                    unsigned to_b=op==OP_CGETR_B; for(unsigned j=0;j<p[2];j++){uint32_t slot=cslot(&pool,s.c,p[1]+j);if(!slot)BAD("CGETR outside a scalar frame cell");if(to_b)s.b=push(&pool,s.b,pool.nodes[slot].kind);else s.a=push(&pool,s.a,pool.nodes[slot].kind);} break;
                }
                case OP_CSET0_A: case OP_CSETN_A: case OP_CSET0_B: case OP_CSETN_B: {
                    unsigned to_b=op==OP_CSET0_B || op==OP_CSETN_B; uint32_t depth=(op==OP_CSET0_A || op==OP_CSET0_B) ? 0 : p[1];
                    if (to_b) NEED(0,1,0); else NEED(1,0,0);
                    if (!cslot(&pool,s.c,depth)) BAD("CSET outside a scalar frame cell");
                    s.c=cset(&pool,s.c,depth,pool.nodes[to_b ? s.b : s.a].kind); if (to_b) POP(b); else POP(a); break;
                }
                case OP_JMP: case OP_JMP32: branch=terminal=1; break;
                case OP_SWITCH: NEED(1,0,0);INTEGER(a);POP(a);branch=2;break;
                case OP_JZ_A: case OP_JNZ_A: NEED(1,0,0); INTEGER(a); POP(a); branch=1; break;
                case OP_JZ_B: case OP_JNZ_B: NEED(0,1,0); INTEGER(b); POP(b); branch=1; break;
                case OP_BEQ: case OP_BNE: case OP_BLT: case OP_BLE: case OP_BLTU: case OP_BLEU:
                    NEED(1,1,0);
                    if ((op!=OP_BEQ && op!=OP_BNE) || pool.nodes[s.a].kind!=ABC_KIND_ADDR || pool.nodes[s.b].kind!=ABC_KIND_ADDR) { INTEGER(a); INTEGER(b); }
                    POP(a); POP(b); branch=1; break;
                case OP_FBLT: case OP_FBLE: case OP_FBEQ:
                    NEED(1,1,0); FLOAT(a); FLOAT(b); POP(a); POP(b); branch=1; break;
                case OP_CALL_A: case OP_CALL_B: case OP_TCALL:
                case OP_CALLI_A: case OP_CALLI_B: case OP_TCALLI: {
                    unsigned indirect=kind==K_ICALL || kind==K_ITCALL, tail=op==OP_TCALL || op==OP_TCALLI;
                    const abc_function *g=indirect ? abc_find_site(m,pc) : &m->functions[abc_find_function(m,(uint32_t)((int64_t)next+abc_i32(p+1)))];
                    if (indirect) { NEED(0,1,0); ADDRESS(b); POP(b); }
                    NEED(g->arguments,0,0);
                    if (tail && (DEPTH(a)!=g->arguments || s.b || DEPTH(c)!=p[indirect ? 1 : 5])) BAD("tail call must replace the complete frame and operand region");
                    for (uint32_t i=g->arguments;i;i--) { if (pool.nodes[s.a].kind!=g->argument_kinds[i-1]) BAD("call argument kind disagrees with function signature"); POP(a); }
                    if (tail) terminal=1;
                    else for (uint32_t i=0;i<g->results;i++) { if (op==OP_CALL_B || op==OP_CALLI_B) s.b=push(&pool,s.b,g->result_kinds[i]); else s.a=push(&pool,s.a,g->result_kinds[i]); }
                    break;
                }
                case OP_RET:
                    if (DEPTH(c)!=p[1] || s.b || p[2]!=f->results || !result_shape(&pool,s.a,f)) BAD("RET disagrees with frame or typed result contract (C %u/%u, B %u, A %u, results %u/%u)",DEPTH(c),(unsigned)p[1],DEPTH(b),DEPTH(a),(unsigned)p[2],f->results);
                    terminal=1; break;
                case OP_HALT:
                    if (s.c || s.b || !result_shape(&pool,s.a,f)) BAD("HALT must leave only declared results and an empty frame");
                    terminal=1; break;
                case OP_ABORT: terminal=1; break;
                default: if (kind==K_BRI) { NEED(1,0,0); INTEGER(a); POP(a); branch=1; } else BAD("unsupported instruction");
            }
            POOL_CHECK();
            uint32_t da=pool.nodes[s.a].depth,db=pool.nodes[s.b].depth,dc=pool.nodes[s.c].depth;
            if(da>f->max_a)f->max_a=da; if(db>f->max_b)f->max_b=db; if(dc>f->max_c)f->max_c=dc;
            unsigned ne=branch==2?(unsigned)abc_u16(p+1)+1u:(branch?1u:0u)+(!terminal?1u:0u);
            for(unsigned i=0;i<ne;i++){uint32_t edge;
                if(branch==2)edge=i<abc_u16(p+1)?(uint32_t)((int64_t)next+abc_i32(p+3+4*i)):next;
                else if(branch&&i==0)edge=(uint32_t)((int64_t)next+(kind==K_JMP32?abc_i32(p+1):abc_i16(p+(kind==K_BRI?2:1))));else edge=next;
                if(edge>=f->end)BAD("execution falls out of function");Shape *old=&shapes[edge];
                if (old->seen) { if (old->a!=s.a || old->b!=s.b || old->c!=s.c) BAD("incompatible kinds or live frame blocks at join"); }
                else { *old=s; old->seen=1; work[nw++]=edge; }
            }
            #undef DEPTH
            #undef NEED
            #undef INTEGER
            #undef FLOAT
            #undef ADDRESS
            #undef POP
        }
    }
done:
    free(starts); free(shapes); free(work); free(pool.nodes); free(pool.hash); return status;
    #undef BAD
    #undef NEED
#undef POOL_CHECK
}

static void compute_allocation_free(abc_module *m){for(uint32_t i=0;i<m->function_count;i++)m->functions[i].allocation_free=1;int changed;do{changed=0;for(uint32_t i=0;i<m->function_count;i++){abc_function *f=&m->functions[i];if(!f->allocation_free)continue;for(uint32_t pc=f->entry;pc<f->end;pc+=abc_instruction_length(m->code+pc)){const uint8_t *p=m->code+pc;unsigned kind=op_kind[p[0]];if(p[0]==OP_EXT||kind==K_ICALL||kind==K_ITCALL||kind==K_FCALL){f->allocation_free=0;changed=1;break;}if(kind==K_CALL||kind==K_TCALL){const abc_function *callee=abc_function_entry(m,abc_u32(p+1));if(!callee||!callee->allocation_free){f->allocation_free=0;changed=1;break;}}}}}while(changed);}
static int descriptor_ref_ok(const abc_module *m,uint32_t i){return i<m->descriptor_count;}
static int descriptor_ro_ok(const abc_module *m,uint32_t off,uint32_t n){uint32_t ro=m->image_size-m->data_size;return off<=ro&&n<=ro-off;}
static int descriptor_visit(const abc_module *m,uint32_t i,uint8_t *mark){
    if(mark[i]==2)return 1;if(mark[i]==1)return 0;mark[i]=1;const abc_descriptor *d=&m->descriptors[i];const uint8_t *p=d->payload;
    if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE){if(!descriptor_ref_ok(m,abc_u32(p+4)))return 0;}
    else if(d->tag==ABC_DESC_SIGNATURE){unsigned n=(unsigned)p[0]+p[1];for(unsigned j=0;j<n;j++){uint32_t x=abc_u32(p+2+4*j);if(!descriptor_ref_ok(m,x)||!descriptor_visit(m,x,mark))return 0;}}
    else if(d->tag==ABC_DESC_RECORD){uint32_t n=abc_u32(p+4);for(uint32_t j=0;j<n;j++){uint32_t x=abc_u32(p+8+16*j+12);if(!descriptor_ref_ok(m,x)||!descriptor_visit(m,x,mark))return 0;}}
    else if(d->tag==ABC_DESC_ARRAY){uint32_t x=abc_u32(p+8);if(!descriptor_ref_ok(m,x)||!descriptor_visit(m,x,mark))return 0;}
    else if(d->tag==ABC_DESC_SUM){unsigned n=p[9];for(unsigned j=0;j<n;j++){uint32_t x=abc_u32(p+12+16*j+12);if(!descriptor_ref_ok(m,x)||!descriptor_visit(m,x,mark))return 0;}}
    else if(d->tag==ABC_DESC_CLOSURE){for(unsigned j=0;j<2;j++){uint32_t x=abc_u32(p+4*j);if(!descriptor_ref_ok(m,x)||!descriptor_visit(m,x,mark))return 0;}}
    mark[i]=2;return 1;
}
static uint32_t descriptor_align(const abc_module *m,uint32_t di){const abc_descriptor *d=&m->descriptors[di];if(d->tag==ABC_DESC_PRIMITIVE){uint32_t size=descriptor_size(m,di);return size>=8?8:size?size:1;}if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE)return 8;if(d->tag==ABC_DESC_ARRAY)return descriptor_align(m,abc_u32(d->payload+8));if(d->tag==ABC_DESC_RECORD){uint32_t align=1;for(uint32_t i=0;i<abc_u32(d->payload+4);i++){uint32_t a=descriptor_align(m,abc_u32(d->payload+8+16*i+12));if(a>align)align=a;}return align;}if(d->tag==ABC_DESC_SUM)return 8;return 1;}
static int descriptor_layout_ok(const abc_module *m,uint32_t di){const abc_descriptor *d=&m->descriptors[di];const uint8_t *p=d->payload;if(d->tag==ABC_DESC_PRIMITIVE||d->tag==ABC_DESC_SIGNATURE)return 1;if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE)return p[0]<=2&&!p[1]&&!p[2]&&!p[3];if(d->tag==ABC_DESC_RECORD){uint32_t size=abc_u32(p),n=abc_u32(p+4);for(uint32_t i=0;i<n;i++){const uint8_t *f=p+8+16*i;uint32_t off=abc_u32(f+8),child=abc_u32(f+12),child_size=descriptor_size(m,child),align=descriptor_align(m,child);if(child_size==UINT32_MAX||(uint64_t)off+child_size>size||off%align)return 0;for(uint32_t j=0;j<i;j++){const uint8_t *g=p+8+16*j;uint32_t goff=abc_u32(g+8),gsize=descriptor_size(m,abc_u32(g+12));if(child_size&&gsize&&(uint64_t)off+child_size>goff&&(uint64_t)goff+gsize>off)return 0;}}return size%descriptor_align(m,di)==0;}if(d->tag==ABC_DESC_ARRAY){uint32_t size=abc_u32(p),count=abc_u32(p+4),element=abc_u32(p+8),stride=descriptor_size(m,element);return stride!=UINT32_MAX&&(uint64_t)count*stride==size;}if(d->tag==ABC_DESC_SUM){uint32_t size=abc_u32(p),disc_off=abc_u32(p+4);unsigned width=p[8],n=p[9];for(unsigned i=0;i<n;i++){const uint8_t *c=p+12+16*i;uint64_t bits=abc_u64(c);uint32_t off=abc_u32(c+8),child=abc_u32(c+12),child_size=descriptor_size(m,child),align=descriptor_align(m,child);if((width<8&&(bits>>(width*8)))||child_size==UINT32_MAX||(uint64_t)off+child_size>size||off%align)return 0;for(unsigned j=0;j<i;j++)if(abc_u64(p+12+16*j)==bits)return 0;}return (uint64_t)disc_off+width<=size;}if(d->tag==ABC_DESC_CLOSURE){uint32_t sig=abc_u32(p),record=abc_u32(p+4);return m->descriptors[sig].tag==ABC_DESC_SIGNATURE&&m->descriptors[record].tag==ABC_DESC_RECORD;}return 0;}
static int root_initial_ok(const abc_module *m,const uint8_t *base,uint32_t di){const abc_descriptor *d=&m->descriptors[di];const uint8_t *p=d->payload;if(d->tag==ABC_DESC_PRIMITIVE)return (p[0]!=ABC_PRIM_ANY&&p[0]!=ABC_PRIM_WORD)||!abc_u64(base);if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE)return p[0]!=2||!abc_u64(base);if(d->tag==ABC_DESC_RECORD){for(uint32_t i=0;i<abc_u32(p+4);i++){const uint8_t *f=p+8+16*i;if(!root_initial_ok(m,base+abc_u32(f+8),abc_u32(f+12)))return 0;}return 1;}if(d->tag==ABC_DESC_ARRAY){uint32_t count=abc_u32(p+4),element=abc_u32(p+8),stride=descriptor_size(m,element);for(uint32_t i=0;i<count;i++)if(!root_initial_ok(m,base+(size_t)i*stride,element))return 0;return 1;}if(d->tag==ABC_DESC_SUM){uint64_t disc=0;memcpy(&disc,base+abc_u32(p+4),p[8]);for(unsigned i=0;i<p[9];i++){const uint8_t *c=p+12+16*i;if(abc_u64(c)==disc)return root_initial_ok(m,base+abc_u32(c+8),abc_u32(c+12));}return 0;}return 0;}
static abc_status load_dynamic_sections(abc_module *m,const uint8_t **sec,const uint32_t *len,abc_error *e){
    size_t at=4;
    m->descriptors=calloc(m->descriptor_count?m->descriptor_count:1,sizeof *m->descriptors);
    m->dynamic_constants=calloc(m->dynamic_constant_count?m->dynamic_constant_count:1,sizeof *m->dynamic_constants);
    m->gc_roots=calloc(m->gc_root_count?m->gc_root_count:1,sizeof *m->gc_roots);
    if(!m->descriptors||!m->dynamic_constants||!m->gc_roots)return abc_fail(e,ABC_NOMEM,UINT32_MAX,"dynamic metadata allocation failed");
    for(uint32_t i=0;i<m->descriptor_count;i++){if(len[10]-at<4)return abc_fail(e,ABC_INVALID,UINT32_MAX,"truncated dynamic descriptor");abc_descriptor *d=&m->descriptors[i];d->tag=sec[10][at];d->flags=sec[10][at+1];d->length=abc_u16(sec[10]+at+2);at+=4;if(d->flags||d->tag>ABC_DESC_CLOSURE||d->length>len[10]-at)return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid dynamic descriptor header");d->payload=malloc(d->length?d->length:1);if(!d->payload)return abc_fail(e,ABC_NOMEM,UINT32_MAX,"descriptor allocation failed");memcpy(d->payload,sec[10]+at,d->length);at+=d->length;const uint8_t *q=d->payload;
        if(d->tag==ABC_DESC_PRIMITIVE){if(d->length!=1||q[0]>ABC_PRIM_WORD)return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid primitive descriptor");}
        else if(d->tag==ABC_DESC_POINTER||d->tag==ABC_DESC_SLICE){if(d->length!=8||q[0]>2||q[1]||q[2]||q[3])return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid pointer or slice descriptor");}
        else if(d->tag==ABC_DESC_SIGNATURE){if(d->length<2||d->length!=2u+4u*((unsigned)q[0]+q[1]))return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid signature descriptor");}
        else if(d->tag==ABC_DESC_RECORD){if(d->length<8||d->length!=8u+16u*abc_u32(q+4))return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid record descriptor");uint32_t n=abc_u32(q+4);for(uint32_t j=0;j<n;j++){const uint8_t *f=q+8+16*j;uint32_t no=abc_u32(f),nn=abc_u32(f+4);if(!descriptor_ro_ok(m,no,nn))return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid record field");}}
        else if(d->tag==ABC_DESC_ARRAY){if(d->length!=12)return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid array descriptor");}
        else if(d->tag==ABC_DESC_SUM){if(d->length<12||(q[8]!=1&&q[8]!=2&&q[8]!=4&&q[8]!=8)||abc_u16(q+10)||d->length!=12u+16u*q[9])return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid sum descriptor");uint32_t size=abc_u32(q),off=abc_u32(q+4);if(off>size||q[8]>size-off)return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid sum discriminant");}
        else if(d->length!=8)return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid closure descriptor");
    }
    if(at!=len[10])return abc_fail(e,ABC_INVALID,UINT32_MAX,"trailing descriptor bytes");
    uint8_t *mark=calloc(m->descriptor_count?m->descriptor_count:1,1);if(!mark)return abc_fail(e,ABC_NOMEM,UINT32_MAX,"descriptor validation allocation failed");for(uint32_t i=0;i<m->descriptor_count;i++)if(!descriptor_visit(m,i,mark)){free(mark);return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid or cyclic dynamic descriptor graph");}free(mark);for(uint32_t i=0;i<m->descriptor_count;i++)if(!descriptor_layout_ok(m,i))return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid dynamic descriptor layout");
    at=4;for(uint32_t i=0;i<m->dynamic_constant_count;i++){if(len[11]-at<4)return abc_fail(e,ABC_INVALID,UINT32_MAX,"truncated dynamic constant");abc_dynamic_constant *c=&m->dynamic_constants[i];c->kind=sec[11][at];c->flags=sec[11][at+1];c->length=abc_u16(sec[11]+at+2);at+=4;if(c->kind>ABC_PRIM_STRING||c->length>len[11]-at||(c->flags&~1u))return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid dynamic constant header");unsigned expect=c->kind==ABC_PRIM_UNIT?0:c->kind==ABC_PRIM_BOOL||c->kind==ABC_PRIM_U8?1:c->kind==ABC_PRIM_U16?2:c->kind==ABC_PRIM_U32||c->kind==ABC_PRIM_I32?4:8;if(c->length!=expect||(c->flags&&c->kind!=ABC_PRIM_U8&&c->kind!=ABC_PRIM_U16&&c->kind!=ABC_PRIM_U32&&c->kind!=ABC_PRIM_U64&&c->kind!=ABC_PRIM_I32&&c->kind!=ABC_PRIM_I64))return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid dynamic constant payload");c->payload=malloc(c->length?c->length:1);if(!c->payload)return abc_fail(e,ABC_NOMEM,UINT32_MAX,"dynamic constant allocation failed");memcpy(c->payload,sec[11]+at,c->length);at+=c->length;if(c->kind==ABC_PRIM_BOOL&&c->payload[0]>1)return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid boolean dynamic constant");if(c->kind==ABC_PRIM_F64){uint64_t bits=abc_u64(c->payload);if((bits&UINT64_C(0x7ff0000000000000))==UINT64_C(0x7ff0000000000000)&&(bits&UINT64_C(0x000fffffffffffff))&&bits!=UINT64_C(0x7ff8000000000000))return abc_fail(e,ABC_INVALID,UINT32_MAX,"noncanonical NaN dynamic constant");}if(c->kind==ABC_PRIM_STRING&&!descriptor_ro_ok(m,abc_u32(c->payload),abc_u32(c->payload+4)))return abc_fail(e,ABC_INVALID,UINT32_MAX,"dynamic string constant outside rodata");}
    if(at!=len[11]||len[12]!=4u+8u*m->gc_root_count)return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid dynamic constants or GC roots");for(uint32_t i=0;i<m->gc_root_count;i++){abc_gc_root *root=&m->gc_roots[i];root->offset=abc_u32(sec[12]+4+8*i);root->descriptor=abc_u32(sec[12]+8+8*i);uint32_t size=descriptor_size(m,root->descriptor);uint64_t end=(uint64_t)root->offset+size,previous_end=i?(uint64_t)m->gc_roots[i-1].offset+descriptor_size(m,m->gc_roots[i-1].descriptor):0;if(size==UINT32_MAX||end>m->data_size||(i&&(root->offset<=m->gc_roots[i-1].offset||root->offset<previous_end))||!root_initial_ok(m,m->image+root->offset,root->descriptor))return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid dynamic GC root");}
    return ABC_OK;
}
abc_status abc_load_memory(const void *bytes,size_t size,abc_module **out,abc_error *e) {
    const uint8_t *p=bytes; const uint16_t endian=1;
    if (*(const uint8_t *)&endian!=1) return abc_fail(e,ABC_INVALID,UINT32_MAX,"memory profile requires little-endian host memory");
    unsigned profile=abc_u16(p+4),dynamic=profile==5,foreign=profile>=4,callable=profile>=3,sections=dynamic?12:foreign?9:callable?8:6;
    if ((profile<2||profile>5) || p[6]!=8 || p[7]!=profile || abc_u32(p+8)!=sections || abc_u32(p+12)) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid memory/callable/foreign/dynamic profile header");
    const uint8_t *sec[13]={0}; uint32_t len[13]={0}; size_t at=16;
    for (unsigned i=0;i<sections;i++) {
        if (size-at<8) return abc_fail(e,ABC_INVALID,UINT32_MAX,"truncated section header");
        uint32_t tag=abc_u32(p+at),n=abc_u32(p+at+4); at+=8;
        if (tag<1 || tag>sections || sec[tag] || n>size-at) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid, duplicate or unsupported section");
        sec[tag]=p+at; len[tag]=n; at+=n;
    }
    if (at!=size || len[1]<4 || !len[2] || len[3]<4 || len[6]<4 || (callable && (len[7]<4 || len[8]<4)) || (foreign && len[9]<4) || (dynamic && (len[10]<4||len[11]<4||len[12]<4))) return abc_fail(e,ABC_INVALID,UINT32_MAX,"missing sections or trailing bytes");
    uint32_t nf=abc_u32(sec[1]),nx=abc_u32(sec[3]),nk=abc_u32(sec[6]);
    uint32_t ns=callable ? abc_u32(sec[7]) : 0,nr=callable ? abc_u32(sec[8]) : 0,ne=foreign?abc_u32(sec[9]):0;
    uint32_t nd=dynamic?abc_u32(sec[10]):0,nc=dynamic?abc_u32(sec[11]):0,ng=dynamic?abc_u32(sec[12]):0;
    if (!nf || nf>ABC_MAX_FUNCTIONS || nx>ABC_MAX_FUNCTIONS || ns>ABC_MAX_FUNCTIONS || nr>ABC_MAX_FUNCTIONS || ne>65535 || len[6]!=4+(uint64_t)nk*5 || (callable && len[8]!=4+(uint64_t)nr*8) || (uint64_t)len[4]+len[5]>ABC_MAX_FILE) return abc_fail(e,ABC_INVALID,UINT32_MAX,"invalid table or image size");
    abc_module *m=calloc(1,sizeof *m); if (!m) return abc_fail(e,ABC_NOMEM,UINT32_MAX,"module allocation failed");
    atomic_init(&m->references,1); m->memory_profile=1; m->callable_profile=callable; m->foreign_profile=foreign; m->dynamic_profile=dynamic; m->function_count=nf; m->export_count=nx;
    m->site_count=ns; m->reloc_count=nr; m->extern_count=ne;m->descriptor_count=nd;m->dynamic_constant_count=nc;m->gc_root_count=ng;
    m->code_size=len[2]; m->data_size=len[4]; m->image_size=len[4]+len[5];
    m->functions=calloc(nf,sizeof *m->functions); m->exports=calloc(nx ? nx : 1,sizeof *m->exports);
    m->code=malloc(len[2]); m->load_kinds=calloc(len[2],1); m->image=malloc(m->image_size ? m->image_size : 1);
    abc_status status=ABC_INVALID;
    #define FAIL(...) do { status=abc_fail(e,ABC_INVALID,UINT32_MAX,__VA_ARGS__); goto failed; } while(0)
    if (!m->functions || !m->exports || !m->code || !m->load_kinds || !m->image) { status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"module allocation failed"); goto failed; }
    memcpy(m->code,sec[2],len[2]); memcpy(m->image,sec[4],len[4]); memcpy(m->image+len[4],sec[5],len[5]);
    at=4;
    for (uint32_t i=0;i<nf;i++) {
        if (len[1]-at<16) FAIL("truncated function signature");
        const uint8_t *q=sec[1]+at; abc_function *f=&m->functions[i];
        f->entry=abc_u32(q); f->arguments=abc_u32(q+4); f->results=abc_u32(q+8); f->hidden_bytes=abc_u32(q+12); at+=16;
        if ((i==0 && f->entry) || f->entry>=len[2] || (i && f->entry<=m->functions[i-1].entry) || f->arguments>255 || f->results>255 || f->hidden_bytes>ABC_MAX_FILE || f->arguments+f->results>len[1]-at) FAIL("invalid function entry/count or hidden result size");
        memcpy(f->argument_kinds,sec[1]+at,f->arguments); at+=f->arguments; memcpy(f->result_kinds,sec[1]+at,f->results); at+=f->results;
        for (uint32_t j=0;j<f->arguments;j++) if (!module_kind(m,f->argument_kinds[j])) FAIL("unsupported argument kind");
        for (uint32_t j=0;j<f->results;j++) if (!module_kind(m,f->result_kinds[j])) FAIL("unsupported result kind");
        if (f->hidden_bytes && (!f->arguments || f->argument_kinds[0]!=ABC_KIND_ADDR)) FAIL("hidden aggregate result requires first argument address");
        if (i) m->functions[i-1].end=f->entry;
    }
    if (at!=len[1]) FAIL("trailing function signature bytes");
    m->functions[nf-1].end=len[2]; at=4;
    for (uint32_t i=0;i<nx;i++) {
        if (len[3]-at<6) FAIL("truncated export");
        uint32_t index=abc_u32(sec[3]+at); unsigned n=abc_u16(sec[3]+at+4); at+=6;
        if (index>=nf || !n || n>255 || n>len[3]-at) FAIL("invalid export name or index");
        for (unsigned j=0;j<n;j++) { unsigned ch=sec[3][at+j];
            if (!(ch=='_' || (ch>='a' && ch<='z') || (ch>='A' && ch<='Z') || (j && ch>='0' && ch<='9'))) FAIL("export names must be ASCII identifiers");
        }
        m->exports[i].name=malloc(n+1); if (!m->exports[i].name) { status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"export allocation failed"); goto failed; }
        memcpy(m->exports[i].name,sec[3]+at,n); m->exports[i].name[n]=0; m->exports[i].function=index; at+=n;
        if(dynamic){abc_function *ef=&m->functions[index];for(uint32_t j=0;j<ef->arguments;j++)if(ef->argument_kinds[j]==ABC_KIND_ANY)FAIL("abi-any in export arguments");for(uint32_t j=0;j<ef->results;j++)if(ef->result_kinds[j]==ABC_KIND_ANY)FAIL("abi-any in export results");}
        for (uint32_t j=0;j<i;j++) if (!strcmp(m->exports[j].name,m->exports[i].name)) FAIL("duplicate export name");
    }
    if (at!=len[3]) FAIL("trailing export bytes");
    for (uint32_t i=0;i<nk;i++) {
        const uint8_t *q=sec[6]+4+i*5; uint32_t offset=abc_u32(q); unsigned kind=q[4];
        if (offset>=len[2] || !module_kind(m,kind) || m->load_kinds[offset]) FAIL("invalid or duplicate load kind annotation");
        m->load_kinds[offset]=(uint8_t)(kind+1);
    }
    if (callable) {
        m->sites=calloc(ns ? ns : 1,sizeof *m->sites); m->relocs=calloc(nr ? nr : 1,sizeof *m->relocs);
        if (!m->sites || !m->relocs) { status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"callable table allocation failed"); goto failed; }
        at=4;
        for (uint32_t i=0;i<ns;i++) {
            if (len[7]-at<16) FAIL("truncated indirect signature");
            const uint8_t *q=sec[7]+at; abc_function *s=&m->sites[i];
            s->entry=abc_u32(q); s->arguments=abc_u32(q+4); s->results=abc_u32(q+8); s->hidden_bytes=abc_u32(q+12); at+=16;
            if (s->entry>=m->code_size || (i && s->entry<=m->sites[i-1].entry) || !s->arguments || s->arguments>255 || s->results>255 || s->hidden_bytes>ABC_MAX_FILE || s->arguments+s->results>len[7]-at) FAIL("invalid indirect signature offset/count");
            memcpy(s->argument_kinds,sec[7]+at,s->arguments); at+=s->arguments; memcpy(s->result_kinds,sec[7]+at,s->results); at+=s->results;
            for (uint32_t j=0;j<s->arguments;j++) if (!module_kind(m,s->argument_kinds[j])) FAIL("unsupported indirect argument kind");
            for (uint32_t j=0;j<s->results;j++) if (!module_kind(m,s->result_kinds[j])) FAIL("unsupported indirect result kind");
            if (s->argument_kinds[0]!=ABC_KIND_ADDR) FAIL("indirect signature needs environment address as first argument");
        }
        if (at!=len[7]) FAIL("trailing indirect signature bytes");
        for (uint32_t i=0;i<nr;i++) {
            const uint8_t *q=sec[8]+4+i*8; abc_code_reloc *r=&m->relocs[i]; r->offset=abc_u32(q); r->function=abc_u32(q+4);
            if ((uint64_t)r->offset+8>m->data_size || r->function>=nf || (i && r->offset<(uint64_t)m->relocs[i-1].offset+8)) FAIL("invalid or overlapping code image relocation");
        }
    }
    if (foreign) {
        m->externs=calloc(ne?ne:1,sizeof *m->externs); if(!m->externs){status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"extern allocation failed");goto failed;}
        at=4; for(uint32_t i=0;i<ne;i++) {
            if(len[9]-at<4) FAIL("truncated extern signature"); abc_extern *ext=&m->externs[i]; ext->arguments=sec[9][at]; ext->results=sec[9][at+1]; unsigned nn=abc_u16(sec[9]+at+2); at+=4;
            if(ext->arguments>10||ext->results>1||!nn||nn>255||(uint64_t)ext->arguments+ext->results+nn>len[9]-at) FAIL("invalid extern signature");
            unsigned ni=0,nf64=0; for(unsigned j=0;j<ext->arguments;j++){unsigned k=sec[9][at+j];if(!value_kind(k))FAIL("invalid extern argument kind");if(k==ABC_KIND_FLOAT)nf64++;else ni++;ext->argument_kinds[j]=(uint8_t)k;} at+=ext->arguments;
            if(ni>6||nf64>4) FAIL("extern exceeds C ABI argument limits");
            if(ext->results){unsigned k=sec[9][at++];if(!value_kind(k))FAIL("invalid extern result kind");ext->result_kinds[0]=(uint8_t)k;}
            ext->name=malloc(nn+1);if(!ext->name){status=abc_fail(e,ABC_NOMEM,UINT32_MAX,"extern name allocation failed");goto failed;} memcpy(ext->name,sec[9]+at,nn);ext->name[nn]=0;
            for(unsigned j=0;j<nn;j++){unsigned ch=(unsigned char)ext->name[j];if(!(ch=='_'||(ch>='a'&&ch<='z')||(ch>='A'&&ch<='Z')||(j&&ch>='0'&&ch<='9')))FAIL("extern names must be ASCII identifiers");} at+=nn;
            for(uint32_t j=0;j<i;j++)if(!strcmp(m->externs[j].name,ext->name))FAIL("duplicate extern name");
        } if(at!=len[9])FAIL("trailing extern bytes");
    }
    if(dynamic){status=load_dynamic_sections(m,sec,len,e);if(status!=ABC_OK)goto failed;}
    status=verify_memory(m,e); if (status!=ABC_OK) goto failed; compute_allocation_free(m); *out=m; return ABC_OK;
failed: abc_module_free(m); return status;
    #undef FAIL
}

