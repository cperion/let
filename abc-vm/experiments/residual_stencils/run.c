/* copy-and-patch the residual program for skip's inlined loop, then time it */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 199309L
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/mman.h>
#include "rs.h"
#include "rs_names.h"
typedef uint64_t V;
typedef __attribute__((preserve_none)) V (*H)(V *, V *, V *, V, V, V, V, V, V, V, V);
static uint8_t *buf, *pos; static V *fin;
static void put32(uint8_t *p, int32_t v) { memcpy(p, &v, 4); }
typedef struct { uint8_t *site; int kind; int32_t addend; int label; } Fix;
static Fix fix[64]; static int nfix; static uint8_t *labels[8];
static void place(int s, int64_t imm, int taken_label) {
  const Stencil *t = &stencils[s];
  uint8_t *at = pos; memcpy(at, t->code, t->len); pos += t->len;
  for (int i = 0; i < t->nrel; i++) {
    const Reloc *r = &t->rel[i]; uint8_t *site = at + r->off; int64_t target;
    switch (r->hole) {
    case HOLE_IMM: target = (uint32_t)imm; break;
    case HOLE_FINAL: target = (int64_t)(intptr_t)fin; break;
    case HOLE_NEXT: target = (int64_t)(intptr_t)pos; break;
    case HOLE_TAKEN: fix[nfix++] = (Fix){ site, r->kind, r->addend, taken_label }; continue;
    default: target = 0;
    }
    if (r->kind == RPC32) put32(site, (int32_t)(target + r->addend - (int64_t)(intptr_t)site)); else put32(site, (int32_t)(target + r->addend));
  }
}
static void align32(void) { while ((uintptr_t)pos & 31) *pos++ = 0x90; }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
int main(int argc, char **argv) {
  int stackcache = argc > 1;
  buf = pos = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0);
  fin = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0);
  enum { LOOP, EXIT };
  align32(); labels[LOOP] = pos;
  if (!stackcache) {
    /* hand-written: s in r0, n in r1, r2 scratch, as a register allocator would assign it */
    place(S_bz_1, 0, EXIT);                                      /* n == 0: done */
    place(S_mov_2_0, 0, 0); place(S_shl32_2_13, 0, 0); place(S_xor32_0_2, 0, 0);   /* s ^= s << 13 (u32) */
    place(S_mov_2_0, 0, 0); place(S_shr32_2_17, 0, 0); place(S_xor32_0_2, 0, 0);   /* s ^= s >> 17 */
    place(S_mov_2_0, 0, 0); place(S_shl32_2_5, 0, 0);  place(S_xor32_0_2, 0, 0);   /* s ^= s << 5 */
    place(S_sub32_1_imm, 1, 0);                                  /* n = n - 1 (u32) */
  } else {
    /* the stack cache as allocator, applied mechanically to the bytecode of the inlined loop:
       renaming costs nothing, a write to a register another live cell names copies first,
       and the back edge restores the loop entry's layout (C0 in r0, C1 in r1) */
    place(S_bz_1, 0, EXIT);                                      /* CGET.A 1; BEQI.A 0: test C1 */
    place(S_mov_2_0, 0, 0); place(S_shl32_2_13, 0, 0);           /* CGET.A 0; SHLI.A 13; ZX32: copy-on-write of C0 */
    place(S_xor32_2_0, 0, 0);                                    /* XORC.A 0 */
    place(S_mov_3_2, 0, 0); place(S_shr32_3_17, 0, 0);           /* DUP.A; SHRI.A 17: copy-on-write */
    place(S_xor32_2_3, 0, 0);                                    /* MOVE.AB; XOR.A */
    place(S_mov_3_2, 0, 0); place(S_shl32_3_5, 0, 0);            /* DUP.A; SHLI.A 5; ZX32 */
    place(S_xor32_2_3, 0, 0);                                    /* MOVE.AB; XOR.A */
    place(S_mov_3_1, 0, 0); place(S_sub32_3_imm, 1, 0);          /* CGET.A 1; SUBI.A 1; ZX32: copy-on-write of C1 */
    place(S_mov_0_2, 0, 0); place(S_mov_1_3, 0, 0);              /* CSETN.A 1; CSET0.A rename; back edge restores the layout */
  }
  place(S_jmp, 0, LOOP);
  labels[EXIT] = pos; place(S_exit_0, 0, 0);
  for (int i = 0; i < nfix; i++) { int64_t t = (int64_t)(intptr_t)labels[fix[i].label];
    if (fix[i].kind == RPC32) put32(fix[i].site, (int32_t)(t + fix[i].addend - (int64_t)(intptr_t)fix[i].site)); else put32(fix[i].site, (int32_t)(t + fix[i].addend)); }
  mprotect(buf, 4096, PROT_READ | PROT_EXEC);
  printf("residual loop: %ld bytes of machine code\n", (long)(labels[EXIT] - labels[LOOP]));
  FILE *f = fopen("/tmp/rs_loop.bin", "wb"); fwrite(labels[LOOP], 1, pos - labels[LOOP], f); fclose(f);
  const uint32_t N = 12500000; double best = 1e9;
  for (int r = 0; r < 7; r++) { double t0 = now(); ((H)labels[LOOP])(0, 0, 0, 2463534242u, N, 0, 0, 0, 0, 0, 0); double t = now() - t0; if (t < best) best = t; }
  uint32_t s = 2463534242u; for (uint32_t i = 0; i < N; i++) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; }
  printf("residual stencils: %.2f ns per iteration, result %s\n", best * 1e9 / N, *fin == s ? "correct" : "WRONG");
  return 0;
}
