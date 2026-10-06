#define _POSIX_C_SOURCE 199309L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
typedef uint64_t V;
V run_R(const uint8_t *ip, V *a0, V *a1, V *a2, V *a3);
V run_D(const uint8_t *ip, V **sp);
extern V *fin_d[4];
enum { PUSH, ADD, SUB, MUL, XOR, BR_GE, JMP, HALT };
#define RT(L, R, D, kl, kr) ((L) | (R) << 2 | (D) << 4 | (kl) << 6 | (kr) << 7)
static uint8_t code[4096]; static int n;
static void e2(int op, int r) { code[n++] = op; code[n++] = r; }
static void epush(int lane, int imm) { code[n++] = PUSH; code[n++] = lane << 4; code[n++] = (uint8_t)imm; }
static int ebr(int r) { code[n++] = BR_GE; code[n++] = r; n += 2; return n - 4; }
static void pat(int site, int target) { int16_t o = (int16_t)(target - (site + 4)); memcpy(code + site + 2, &o, 2); }
static void ejmp(int target) { int s = n; code[n++] = JMP; code[n++] = 0; n += 2; pat(s, target); }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
/* sum: while (i < n) { sum += i; i++ }   S0 = sum, S1 = scratch, S2 = i, S3 = n */
static int prog_sum(void) {
  n = 0; int top = n;
  int ex = ebr(RT(2, 3, 0, 1, 1));                 /* i >= n: exit, keep both */
  e2(ADD, RT(0, 2, 0, 0, 1));                      /* sum = sum + i, keep i */
  epush(1, 1); e2(ADD, RT(2, 1, 2, 0, 0));          /* i = i + 1 */
  ejmp(top); pat(ex, n); code[n++] = HALT; code[n++] = 0; return 5;
}
static int prog_chain(void) {
  n = 0; int top = n;
  int ex = ebr(RT(2, 3, 0, 1, 1));
  for (int k = 0; k < 8; k++) { epush(1, 3 + k); e2(k & 1 ? ADD : MUL, RT(0, 1, 0, 0, 0)); }
  epush(1, 1); e2(ADD, RT(2, 1, 2, 0, 0));
  ejmp(top); pat(ex, n); code[n++] = HALT; code[n++] = 0; return 20;
}
static V L[4][64];
static void bench(const char *name, int (*prog)(void), V acc0, V iters, V expect) {
  int per = prog();
  for (int variant = 0; variant < 2; variant++) {
    double best = 1e9; int ok = 1;
    for (int rep = 0; rep < 5; rep++) {
      memset(L, 0, sizeof L);
      L[0][0] = acc0; L[2][0] = 0; L[3][0] = iters;
      double t0 = now(); V top;
      if (variant == 0) { run_R(code, L[0] + 1, L[1], L[2] + 1, L[3] + 1); top = L[0][0]; }
      else { V *sp[4] = { L[0] + 1, L[1], L[2] + 1, L[3] + 1 }; run_D(code, sp); top = fin_d[0][-1]; }
      double t = now() - t0; if (t < best) best = t;
      if (top != expect) ok = 0;
    }
    printf("  %-6s %-34s %6.2f ns/iteration  %5.3f ns/instruction  %s\n", name,
           variant == 0 ? "routing static, pointers in registers" : "routing decoded at run time, in memory",
           best * 1e9 / iters, best * 1e9 / (iters * per), ok ? "ok" : "WRONG");
  }
}
int main(void) {
  const V N = 50000000;
  bench("sum", prog_sum, 0, N, N * (N - 1) / 2);
  V x = 1; const V C = N / 4; for (V i = 0; i < C; i++) for (int k = 0; k < 8; k++) x = (k & 1) ? x + 3 + k : x * (3 + k);
  bench("chain", prog_chain, 1, C, x);
  return 0;
}
