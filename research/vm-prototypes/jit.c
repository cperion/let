/* jit.c: copy-and-patch JIT for ABC VM 2.0, milestone 1.
 *
 * Compile with -DSTENCILS='"stencils_bank.h"' -DMETA='"stencils_bank_meta.h"'
 * (or the _mem pair). Same vm_run / vm_final interface as the interpreters.
 *
 * One linear pass over the reachable code. The cache state (operand bank
 * pair (a, b) and C's cached count k) is known at every instruction, so each
 * instruction becomes the stencil for its (state, opcode). A label takes the
 * state it is first reached in; mismatched edges get conform code, inline on
 * fallthrough and as out-of-line stubs on taken branches. Loop headers are
 * warmed (caches filled from proven stack depths) and aligned to 32 bytes.
 * CALL and RET flush every cache: that is the calling convention. */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include "opcodes.h"
#include STENCILS
#include META

typedef uint64_t V;
struct vm_final { V *asp, *bsp, *csp; V reason; } vm_final;

#define EEE 0
static int st_a(int s) { return ab_a[s / NCK]; }
static int st_b(int s) { return ab_b[s / NCK]; }
static int st_k(int s) { return s % NCK; }
static int st_make(int a, int b, int k) { return ab_index[a][b] * NCK + k; }
static const Stencil *op_stencil(int s, int op) { return &stencils[s * NOPS + op]; }
static const Stencil *conf_ab(int f, int t) { return &stencils[NSTATE * NOPS + f * NAB + t]; }
static const Stencil *conf_c(int f, int t) { return &stencils[NSTATE * NOPS + NAB * NAB + f * NCK + t]; }

typedef struct { int op, off; int64_t imm; int target, toff, a1, a2; } Ins;
typedef struct { uint8_t *site; uint8_t kind; int32_t addend; int is_stub, idx; } Fixup;
typedef struct { int from, label; uint8_t *addr; } Stub;
typedef struct {
  uint8_t *buf, *pos; size_t size;
  Ins *ins; int n;
  int *label_state; uint8_t **label_addr; char *is_label, *is_loop; int (*label_dep)[3];
  Fixup *fix; int nfix;
  Stub *stub; int nstub;
  V *final;
  int warm, align;
} Jit;

static void put32(uint8_t *p, int32_t v) { memcpy(p, &v, 4); }
static void put64(uint8_t *p, int64_t v) { memcpy(p, &v, 8); }
static void patch(uint8_t *site, int kind, int32_t addend, int64_t target) {
  if (kind == RPC32) put32(site, (int32_t)(target + addend - (int64_t)(intptr_t)site));
  else if (kind == R32) put32(site, (int32_t)(target + addend));
  else put64(site, target + addend);
}

static void edge(Jit *j, int label, int from, uint8_t *site, int kind, int32_t addend) {
  if (j->label_state[label] < 0) j->label_state[label] = from;
  Fixup *f = &j->fix[j->nfix++];
  f->site = site; f->kind = kind; f->addend = addend;
  if (j->label_state[label] == from) { f->is_stub = 0; f->idx = label; return; }
  for (int i = 0; i < j->nstub; i++)
    if (j->stub[i].from == from && j->stub[i].label == label) { f->is_stub = 1; f->idx = i; return; }
  j->stub[j->nstub] = (Stub){ from, label, 0 };
  f->is_stub = 1; f->idx = j->nstub++;
}

/* copy a stencil and patch its holes */
static void place(Jit *j, const Stencil *s, int64_t imm, int taken_label, int taken_from,
                  int next_label, int next_from) {
  uint8_t *at = j->pos;
  memcpy(at, s->code, s->len);
  j->pos += s->len;
  for (int i = 0; i < s->nrel; i++) {
    const Reloc *r = &s->rel[i];
    uint8_t *site = at + r->off;
    switch (r->hole) {
    case HOLE_IMM: patch(site, r->kind, r->addend, (int64_t)(uint32_t)imm); break;
    case HOLE_IMM2: patch(site, r->kind, r->addend, (int64_t)(uint32_t)((uint64_t)imm >> 32)); break;
    case HOLE_FINAL: patch(site, r->kind, r->addend, (int64_t)(intptr_t)j->final); break;
    case HOLE_NEXT:
      if (next_label >= 0) edge(j, next_label, next_from, site, r->kind, r->addend);
      else patch(site, r->kind, r->addend, (int64_t)(intptr_t)j->pos);
      break;
    case HOLE_TAKEN: edge(j, taken_label, taken_from, site, r->kind, r->addend); break;
    }
  }
}

static int conform(Jit *j, int from, int to) {
  int fab = from / NCK, tab = to / NCK;
  if (fab != tab) place(j, conf_ab(fab, tab), 0, -1, 0, -1, 0);
  if (st_k(from) != st_k(to)) place(j, conf_c(st_k(from), st_k(to)), 0, -1, 0, -1, 0);
  return to;
}

static void align32(Jit *j) {
  static const uint8_t nops[9][9] = {
    {0x90}, {0x66,0x90}, {0x0f,0x1f,0x00}, {0x0f,0x1f,0x40,0x00}, {0x0f,0x1f,0x44,0x00,0x00},
    {0x66,0x0f,0x1f,0x44,0x00,0x00}, {0x0f,0x1f,0x80,0x00,0x00,0x00,0x00},
    {0x0f,0x1f,0x84,0x00,0x00,0x00,0x00,0x00}, {0x66,0x0f,0x1f,0x84,0x00,0x00,0x00,0x00,0x00} };
  int pad = (int)((32 - ((uintptr_t)j->pos & 31)) & 31);
  while (pad > 0) { int n = pad > 9 ? 9 : pad; memcpy(j->pos, nops[n - 1], n); j->pos += n; pad -= n; }
}

/* decode only what is reachable from the entry */
static int decode(const uint8_t *code, Ins **out) {
  enum { MAXB = 1 << 16 };
  char *seen = calloc(MAXB, 1);
  int *work = malloc(MAXB * sizeof(int)), nw = 0;
  work[nw++] = 0;
  while (nw) {
    int off = work[--nw];
    while (off < MAXB && !seen[off]) {
      int op = code[off];
      if (op >= OP_COUNT) { fprintf(stderr, "jit: bad opcode %d at %d\n", op, off); exit(2); }
      seen[off] = 1;
      int next = off + op_len[op], k = op_kind[op];
      if (k == K_BRANCH) { int16_t r; memcpy(&r, code + off + 1, 2); work[nw++] = next + r; }
      if (k == K_BRI) { int16_t r; memcpy(&r, code + off + 2, 2); work[nw++] = next + r; }
      if (k == K_CALL || k == K_TCALL) { int32_t r; memcpy(&r, code + off + 1, 4); work[nw++] = next + r; }
      if (k == K_CALL) work[nw++] = next;
      if (k == K_HALT || k == K_RET || k == K_ABORT || op == OP_JMP || k == K_CALL || k == K_TCALL) break;
      off = next;
    }
  }
  int n = 0;
  for (int o = 0; o < MAXB; o++) n += seen[o];
  Ins *v = malloc(n * sizeof *v);
  int *at = calloc(MAXB, sizeof(int)), m = 0;
  for (int off = 0; off < MAXB; off++) {
    if (!seen[off]) continue;
    int op = code[off];
    Ins *in = &v[m]; in->op = op; in->off = off; in->imm = 0; in->target = -1; in->toff = -1; in->a1 = in->a2 = 0;
    int k = op_kind[op];
    if (k == K_OPI || k == K_BRI || op == OP_PUSH8_A || op == OP_PUSH8_B) in->imm = (int8_t)code[off + 1];
    else if (op == OP_CPUSHN) { in->imm = code[off + 1]; in->a1 = code[off + 1]; }
    else if (op == OP_CGETR_A || op == OP_CGETR_B) { in->imm = code[off + 1] | ((int64_t)code[off + 2] << 8); in->a1 = code[off + 1]; in->a2 = code[off + 2]; }
    else if (op_len[op] == 2) in->imm = code[off + 1];              /* depths, OPC depth, ABORT reason */
    else if (op_len[op] == 5) { int32_t x; memcpy(&x, code + off + 1, 4); in->imm = x; }
    else if (op_len[op] == 9) { int64_t x; memcpy(&x, code + off + 1, 8); in->imm = x; }
    if (k == K_BRANCH) { int16_t r; memcpy(&r, code + off + 1, 2); in->toff = off + 3 + r; }
    if (k == K_BRI) { int16_t r; memcpy(&r, code + off + 2, 2); in->toff = off + 4 + r; }
    if (k == K_CALL) { int32_t r; memcpy(&r, code + off + 1, 4); in->toff = off + 6 + r; in->a1 = code[off + 5]; }
    if (k == K_TCALL) { int32_t r; memcpy(&r, code + off + 1, 4); in->toff = off + 7 + r; in->a1 = code[off + 5]; in->a2 = code[off + 6]; }
    if (k == K_RET) { in->a1 = code[off + 1]; in->a2 = code[off + 2]; }
    at[off] = ++m;
  }
  for (int i = 0; i < n; i++) {
    if (v[i].toff >= 0) {
      int t = v[i].toff < MAXB ? at[v[i].toff] : 0;
      if (!t) { fprintf(stderr, "jit: jump into the middle of an instruction\n"); exit(2); }
      v[i].target = t - 1;
    }
  }
  free(seen); free(work); free(at);
  *out = v;
  return n;
}

static H compile(Jit *j, const uint8_t *code) {
  int n = j->n = decode(code, &j->ins);
  j->label_state = malloc(n * sizeof(int));
  j->label_addr = calloc(n, sizeof(uint8_t *));
  j->is_label = calloc(n, 1);
  j->is_loop = calloc(n, 1);
  j->label_dep = malloc(n * sizeof *j->label_dep);
  j->fix = malloc((size_t)n * 8 * sizeof(Fixup)); j->nfix = 0;
  j->stub = malloc((size_t)n * 4 * sizeof(Stub)); j->nstub = 0;
  for (int i = 0; i < n; i++) { j->label_state[i] = -1; j->label_dep[i][0] = -1; }
  for (int i = 0; i < n; i++) {
    int t = j->ins[i].target;
    if (t >= 0) { j->is_label[t] = 1; if (t <= i) j->is_loop[t] = 1; }
    if (op_kind[j->ins[i].op] == K_CALL && i + 1 < n) j->is_label[i + 1] = 1;
  }
  size_t maxlen = 0;
  for (size_t k = 0; k < sizeof stencils / sizeof stencils[0]; k++) if (stencils[k].len > maxlen) maxlen = stencils[k].len;
  j->size = ((size_t)n * 8 + 16) * (maxlen + 8) + 4096;
  j->buf = mmap(NULL, j->size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0);
  j->final = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0);
  if (j->buf == MAP_FAILED || j->final == MAP_FAILED) { perror("jit: mmap"); exit(2); }
  j->pos = j->buf;

  int cur = EEE, live = 1, d[3] = { 0, 0, 0 };
#define SETDEP(L, x, y, z) do { if (j->label_dep[L][0] < 0) { j->label_dep[L][0] = (x); j->label_dep[L][1] = (y); j->label_dep[L][2] = (z); } } while (0)
  for (int i = 0; i < n; i++) {
    Ins *in = &j->ins[i];
    if (i > 0 && live && j->ins[i - 1].off + op_len[j->ins[i - 1].op] != in->off) live = 0;
    if (j->is_label[i]) {
      if (live) SETDEP(i, d[0], d[1], d[2]);
      if (j->label_dep[i][0] < 0) SETDEP(i, 0, 0, 0);
      /* warm a loop header reached by fallthrough: fill caches from proven depths */
      if (j->label_state[i] < 0 && live && j->is_loop[i] && j->warm && NSTATE > 1) {
        int *ld = j->label_dep[i];
        int b2 = st_b(cur), a2 = st_a(cur), k2 = st_k(cur);
        int wb = ld[1] < 2 ? ld[1] : 2; if (b2 < wb) b2 = wb;
        int wa = ld[0] < NBANK - b2 ? ld[0] : NBANK - b2; if (a2 < wa) a2 = wa;
        int wk = ld[2] < NCK - 1 ? ld[2] : NCK - 1; if (k2 < wk) k2 = wk;
        if (a2 + b2 > NBANK) a2 = NBANK - b2;
        cur = conform(j, cur, st_make(a2, b2, k2));
      }
      if (j->label_state[i] < 0) j->label_state[i] = live ? cur : EEE;
      else if (live && cur != j->label_state[i]) conform(j, cur, j->label_state[i]);
      cur = j->label_state[i];
      for (int x = 0; x < 3; x++) d[x] = j->label_dep[i][x];
      if (j->is_loop[i] && j->align) align32(j);
      j->label_addr[i] = j->pos;
      live = 1;
    }
    if (!live) continue;
    int op = in->op, target = in->target;
    int64_t imm = in->imm;
    if (op == OP_CGETN_A || op == OP_CGETN_B || op == OP_CSETN_A || op == OP_CSETN_B) {
      int k = st_k(cur), xs = (op == OP_CGETN_B || op == OP_CSETN_B), get = (op == OP_CGETN_A || op == OP_CGETN_B);
      if (in->imm < k) {
        if (in->imm == 0) op = get ? (xs ? OP_CGET0_B : OP_CGET0_A) : (xs ? OP_CSET0_B : OP_CSET0_A);
        else op = get ? cgetd_op[xs][in->imm] : csetd_op[xs][in->imm];
      } else imm = (int64_t)(k - 1 - in->imm) * 8;
    }
    /* an operand form reading a cached C cell uses its register variant */
    if (op_kind[op] == K_OPC) {
      int kc = st_k(cur);
      if (imm < kc) { op = opcd_op[op][imm]; imm = 0; } else imm = (int64_t)(kc - 1 - in->imm) * 8;
    }
    /* calls and returns flush every cache, then use the variant with the counts built in */
    if (op_kind[op] == K_CALL || op_kind[op] == K_TCALL || op_kind[op] == K_RET) {
      int a1 = in->a1, a2 = in->a2, q;
      if (a1 > 4 || (op_kind[op] == K_TCALL && a2 > 4) || (op_kind[op] == K_RET && a2 > 2)) { fprintf(stderr, "jit: call counts beyond this build\n"); exit(2); }
      if (op_kind[op] == K_CALL) q = (op == OP_CALL_A ? OP_CALL_A_0 : OP_CALL_B_0) + a1;
      else if (op_kind[op] == K_TCALL) q = OP_TCALL_0_0 + a1 * 5 + a2;
      else q = OP_RET_0_0 + a1 * 3 + a2;
      cur = conform(j, cur, EEE);
      if (op_kind[op] == K_CALL) {
        SETDEP(target, 0, 0, a1 + 1);
        if (i + 1 < n) SETDEP(i + 1, 0, 0, 0);
        place(j, op_stencil(EEE, q), 0, target, st_taken[EEE][q], i + 1, EEE);
      } else if (op_kind[op] == K_TCALL) {
        SETDEP(target, 0, 0, a2 + 1);
        place(j, op_stencil(EEE, q), 0, target, st_taken[EEE][q], -1, 0);
      } else place(j, op_stencil(EEE, q), 0, -1, 0, -1, 0);
      live = 0; continue;
    }
    if (op == OP_CPUSHN || op == OP_CGETR_A || op == OP_CGETR_B) {
      place(j, op_stencil(cur, op), imm, target, target >= 0 ? st_taken[cur][op] : 0, -1, 0);
      cur = st_fall[cur][op];
      if (op == OP_CPUSHN) { d[0] -= in->a1; if (d[0] < 0) d[0] = 0; d[2] += in->a1; }
      else { d[op == OP_CGETR_A ? 0 : 1] += in->a2; }
      continue;
    }
    switch (op) {
    case OP_HALT: case OP_ABORT:
      place(j, op_stencil(cur, op), imm, -1, 0, -1, 0);
      live = 0; break;
    case OP_JMP:
      SETDEP(target, d[0], d[1], d[2]);
      place(j, op_stencil(cur, op), 0, target, cur, -1, 0);
      live = 0; break;
    default:
      if (target >= 0) SETDEP(target, d[0] + eff_taken[op][0], d[1] + eff_taken[op][1], d[2] + eff_taken[op][2]);
      place(j, op_stencil(cur, op), imm, target, target >= 0 ? st_taken[cur][op] : 0, -1, 0);
      cur = st_fall[cur][op];
      for (int x = 0; x < 3; x++) { d[x] += eff_fall[op][x]; if (d[x] < 0) d[x] = 0; }
    }
  }
  for (int s = 0; s < j->nstub; s++) {
    Stub *st = &j->stub[s];
    st->addr = j->pos;
    int to = j->label_state[st->label];
    conform(j, st->from, to);
    place(j, op_stencil(to, OP_JMP), 0, st->label, to, -1, 0);
  }
  for (int k = 0; k < j->nfix; k++) {
    Fixup *f = &j->fix[k];
    uint8_t *t = f->is_stub ? j->stub[f->idx].addr : j->label_addr[f->idx];
    if (!t) { fprintf(stderr, "jit: unresolved jump\n"); exit(2); }
    patch(f->site, f->kind, f->addend, (int64_t)(intptr_t)t);
  }
  if (mprotect(j->buf, j->size, PROT_READ | PROT_EXEC)) { perror("jit: mprotect"); exit(2); }
  return (H)j->buf;
}

V vm_run(const uint8_t *code, V *as, V *bs, V *cs) {
  Jit j = {0};
  const char *w = getenv("JIT_WARM"), *al = getenv("JIT_ALIGN");
  j.warm = !w || *w != '0';
  j.align = !al || *al != '0';
  H entry = compile(&j, code);
  const char *dump = getenv("JIT_DUMP");
  if (dump) { FILE *f = fopen(dump, "wb"); fwrite(j.buf, 1, (size_t)(j.pos - j.buf), f); fclose(f); }
  V r = JIT_ENTER(entry, as, bs, cs);
  vm_final.asp = (V *)(uintptr_t)j.final[0]; vm_final.bsp = (V *)(uintptr_t)j.final[1];
  vm_final.csp = (V *)(uintptr_t)j.final[2]; vm_final.reason = j.final[3];
  munmap(j.buf, j.size); munmap(j.final, 4096);
  free(j.ins); free(j.label_state); free(j.label_addr); free(j.is_label); free(j.is_loop);
  free(j.label_dep); free(j.fix); free(j.stub);
  return r;
}
