/* harness.c: reference interpreter, random differential tests, call tests and
   benchmarks for ABC VM 2.0 with the frame instructions (CALL.X f, n /
   TCALL f, k, n / RET k, r) and the operand forms (OPI, OPC, BxxI). */
#define _POSIX_C_SOURCE 199309L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "opcodes.h"

typedef uint64_t V;
typedef int64_t S;
struct vm_final { V *asp, *bsp, *csp; V reason; };
extern struct vm_final vm_final;
V vm_run(const uint8_t *code, V *as, V *bs, V *cs);
#define RET_B ((V)1 << 63)

/* ------------------------------------------------------------ reference */
static V pow_ref(V x, V e) { V r = 1; while (e) { if (e & 1) r *= x; x *= x; e >>= 1; } return r; }
static int ref_run(const uint8_t *code, V *A, V *B, V *C, V **ra, V **rb, V **rc) {
  const uint8_t *ip = code;
  V *a = A, *b = B, *c = C;
#define I16(o) ({ int16_t r_; memcpy(&r_, ip + (o), 2); r_; })
#define I32 ({ int32_t r_; memcpy(&r_, ip + 1, 4); r_; })
#define IMM ((V)(S)(int8_t)ip[1])
#define BIN(N, E) case OP_##N##_A: { V x = a[-1], y = b[-1]; E; a[-1] = r; b--; break; } \
                  case OP_##N##_B: { V x = a[-1], y = b[-1]; E; b[-1] = r; a--; break; }
#define OPI(N, E) case OP_##N##I_A: { V x = a[-1], y = IMM; E; a[-1] = r; break; } \
                  case OP_##N##I_B: { V x = b[-1], y = IMM; E; b[-1] = r; break; }
#define OPC(N, E) case OP_##N##C_A: { V x = a[-1], y = c[-1 - ip[1]]; E; a[-1] = r; break; } \
                  case OP_##N##C_B: { V x = b[-1], y = c[-1 - ip[1]]; E; b[-1] = r; break; }
#define CBI(N, E) case OP_##N: { V x = *--a, y = IMM; int16_t o = I16(2); ip += 4; if (E) ip += o; continue; }
  for (;;) {
    switch (*ip) {
    case OP_HALT: *ra = a; *rb = b; *rc = c; return 0;
    case OP_PUSH8_A: *a++ = IMM; break;
    case OP_PUSH8_B: *b++ = IMM; break;
    case OP_PUSH32_A: *a++ = (V)(S)I32; break;
    case OP_PUSH32_B: *b++ = (V)(S)I32; break;
    case OP_PUSH64_A: memcpy(a++, ip + 1, 8); break;
    case OP_PUSH64_B: memcpy(b++, ip + 1, 8); break;
    case OP_DUP_A: a[0] = a[-1]; a++; break;
    case OP_DUP_B: b[0] = b[-1]; b++; break;
    case OP_DROP_A: a--; break;
    case OP_DROP_B: b--; break;
    case OP_COPY_AB: *b++ = a[-1]; break;
    case OP_COPY_BA: *a++ = b[-1]; break;
    case OP_MOVE_AB: *b++ = *--a; break;
    case OP_MOVE_BA: *a++ = *--b; break;
    case OP_CPUSH_A: *c++ = *--a; break;
    case OP_CPUSH_B: *c++ = *--b; break;
    case OP_CPUSHN: for (int i = 0; i < ip[1]; i++) *c++ = *--a; break;
    case OP_CPOP: c--; break;
    case OP_CGET0_A: *a++ = c[-1]; break;
    case OP_CGET0_B: *b++ = c[-1]; break;
    case OP_CGET1_A: *a++ = c[-2]; break;
    case OP_CGET1_B: *b++ = c[-2]; break;
    case OP_CGETN_A: *a++ = c[-1 - ip[1]]; break;
    case OP_CGETN_B: *b++ = c[-1 - ip[1]]; break;
    case OP_CGETR_A: for (int i = 0; i < ip[2]; i++) *a++ = c[-1 - ip[1] - i]; break;
    case OP_CGETR_B: for (int i = 0; i < ip[2]; i++) *b++ = c[-1 - ip[1] - i]; break;
    case OP_CSET0_A: c[-1] = *--a; break;
    case OP_CSET0_B: c[-1] = *--b; break;
    case OP_CSETN_A: c[-1 - ip[1]] = *--a; break;
    case OP_CSETN_B: c[-1 - ip[1]] = *--b; break;
    BIN(ADD, V r = x + y) BIN(SUB, V r = x - y) BIN(MUL, V r = x * y)
    BIN(AND, V r = x & y) BIN(OR, V r = x | y) BIN(XOR, V r = x ^ y)
    BIN(DIVU, if (!y) return 1; V r = x / y)
    BIN(REMU, if (!y) return 1; V r = x % y)
    BIN(DIVS, if (!y) return 1; V r = (S)y == -1 ? (V)0 - x : (V)((S)x / (S)y))
    BIN(REMS, if (!y) return 1; V r = (S)y == -1 ? 0 : (V)((S)x % (S)y))
    BIN(SHL, V r = y >= 64 ? 0 : x << y) BIN(SHR, V r = y >= 64 ? 0 : x >> y)
    BIN(SAR, V r = (V)((S)x >> (y >= 64 ? 63 : y)))
    BIN(EQ, V r = x == y) BIN(NE, V r = x != y) BIN(LT, V r = (S)x < (S)y) BIN(LE, V r = (S)x <= (S)y)
    BIN(LTU, V r = x < y) BIN(LEU, V r = x <= y)
    OPI(ADD, V r = x + y) OPI(SUB, V r = x - y) OPI(MUL, V r = x * y) OPI(AND, V r = x & y) OPI(OR, V r = x | y)
    OPI(XOR, V r = x ^ y) OPI(SHL, V r = y >= 64 ? 0 : x << y) OPI(SHR, V r = y >= 64 ? 0 : x >> y)
    OPI(SAR, V r = (V)((S)x >> (y >= 64 ? 63 : y)))
    OPC(ADD, V r = x + y) OPC(SUB, V r = x - y) OPC(MUL, V r = x * y) OPC(XOR, V r = x ^ y)
    CBI(BEQI, x == y) CBI(BNEI, x != y) CBI(BLTI, (S)x < (S)y) CBI(BLEI, (S)x <= (S)y) CBI(BGTI, (S)x > (S)y)
    CBI(BGEI, (S)x >= (S)y) CBI(BLTUI, x < y) CBI(BLEUI, x <= y) CBI(BGTUI, x > y) CBI(BGEUI, x >= y)
    case OP_NEG_A: a[-1] = 0 - a[-1]; break;   case OP_NEG_B: b[-1] = 0 - b[-1]; break;
    case OP_NOT_A: a[-1] = ~a[-1]; break;      case OP_NOT_B: b[-1] = ~b[-1]; break;
    case OP_LNOT_A: a[-1] ^= 1; break;         case OP_LNOT_B: b[-1] ^= 1; break;
    case OP_ZX32_A: a[-1] &= 0xffffffffu; break; case OP_ZX32_B: b[-1] &= 0xffffffffu; break;
    case OP_SX32_A: a[-1] = (V)(S)(int32_t)a[-1]; break; case OP_SX32_B: b[-1] = (V)(S)(int32_t)b[-1]; break;
    case OP_ZX8: a[-1] &= 0xffu; break;
    case OP_ZX16: a[-1] &= 0xffffu; break;
    case OP_POW: a[-1] = pow_ref(a[-1], b[-1]); b--; break;
    case OP_POWS: if ((S)b[-1] < 0) return 4; a[-1] = pow_ref(a[-1], b[-1]); b--; break;
    case OP_CHKU8: if (a[-1] > 0xffu) return 3; break;
    case OP_CHKU16: if (a[-1] > 0xffffu) return 3; break;
    case OP_CHKU32: if (a[-1] > 0xffffffffu) return 3; break;
    case OP_CHKI32: if ((S)a[-1] < INT32_MIN || (S)a[-1] > INT32_MAX) return 3; break;
    case OP_CHKNN: if ((S)a[-1] < 0) return 3; break;
    case OP_JMP: ip += 3 + I16(1); continue;
#define JZ(N, P, T) case OP_##N: { V t = *--P; int16_t o = I16(1); ip += 3; if (t T 0) ip += o; continue; }
    JZ(JZ_A, a, ==) JZ(JNZ_A, a, !=) JZ(JZ_B, b, ==) JZ(JNZ_B, b, !=)
#define CB(N, E) case OP_##N: { V x = *--a, y = *--b; int16_t o = I16(1); ip += 3; if (E) ip += o; continue; }
    CB(BEQ, x == y) CB(BNE, x != y) CB(BLT, (S)x < (S)y) CB(BLE, (S)x <= (S)y) CB(BLTU, x < y) CB(BLEU, x <= y)
    case OP_CALL_A: case OP_CALL_B: case OP_CALL_A_0 ... OP_CALL_A_4: case OP_CALL_B_0 ... OP_CALL_B_4: {
      int toB = *ip == OP_CALL_B || (*ip >= OP_CALL_B_0 && *ip <= OP_CALL_B_4);
      *c++ = (V)(uintptr_t)(ip + 6) | (toB ? RET_B : 0);
      for (int i = 0; i < ip[5]; i++) *c++ = *--a;
      ip += 6 + I32; continue;
    }
    case OP_TCALL: case OP_TCALL_0_0 ... OP_TCALL_4_4:
      c -= ip[5];
      for (int i = 0; i < ip[6]; i++) *c++ = *--a;
      ip += 7 + I32; continue;
    case OP_RET: case OP_RET_0_0 ... OP_RET_4_2: {
      int r = ip[2];
      c -= ip[1];
      V t = *--c;
      if (t & RET_B) { memcpy(b, a - r, r * sizeof(V)); b += r; a -= r; }
      ip = (const uint8_t *)(uintptr_t)(t & ~RET_B); continue;
    }
    case OP_ABORT: return ip[1];
    default: fprintf(stderr, "ref: bad opcode %d\n", *ip); exit(2);
    }
    ip += op_len[*ip];
  }
}

/* ------------------------------------------------------------ assembler */
typedef struct { uint8_t b[1 << 16]; int n; } Code;
static void e1(Code *c, int op) { c->b[c->n++] = (uint8_t)op; }
static void e2(Code *c, int op, int x) { e1(c, op); c->b[c->n++] = (uint8_t)x; }
static void e32(Code *c, int op, int32_t v) { e1(c, op); memcpy(c->b + c->n, &v, 4); c->n += 4; }
static void e64(Code *c, int op, int64_t v) { e1(c, op); memcpy(c->b + c->n, &v, 8); c->n += 8; }
static int ebr(Code *c, int op) { e1(c, op); c->n += 2; return c->n - 3; }
static void pbr(Code *c, int site, int target) { int16_t o = (int16_t)(target - (site + 3)); memcpy(c->b + site + 1, &o, 2); }
static void ebr_to(Code *c, int op, int target) { pbr(c, ebr(c, op), target); }
static int ebri(Code *c, int op, int imm) { e2(c, op, imm); c->n += 2; return c->n - 4; }
static void pbri(Code *c, int site, int target) { int16_t o = (int16_t)(target - (site + 4)); memcpy(c->b + site + 2, &o, 2); }
static int ecall(Code *c, int op, int n) { e1(c, op); c->n += 4; c->b[c->n++] = (uint8_t)n; return c->n - 6; }
static void pcall(Code *c, int site, int target) { int32_t o = target - (site + 6); memcpy(c->b + site + 1, &o, 4); }
static int etcall(Code *c, int k, int n) { e1(c, OP_TCALL); c->n += 4; c->b[c->n++] = (uint8_t)k; c->b[c->n++] = (uint8_t)n; return c->n - 7; }
static void ptcall(Code *c, int site, int target) { int32_t o = target - (site + 7); memcpy(c->b + site + 1, &o, 4); }
static void eret(Code *c, int k, int r) { e1(c, OP_RET); c->b[c->n++] = (uint8_t)k; c->b[c->n++] = (uint8_t)r; }
static void push_a(Code *c, int64_t v) {
  if (v >= -128 && v <= 127) e2(c, OP_PUSH8_A, (int)v);
  else if (v >= INT32_MIN && v <= INT32_MAX) e32(c, OP_PUSH32_A, (int32_t)v);
  else e64(c, OP_PUSH64_A, v);
}
#define DEPTH (1 << 20)
#define GUARD 64
static V *mkstack(void) { V *s = calloc(DEPTH + GUARD, sizeof(V)); return s + GUARD; }

/* ------------------------------------------------------------ random tests */
static uint64_t rng = 88172645463325252ull;
static uint64_t rnd64(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }
static unsigned rnd(unsigned n) { return (unsigned)(rnd64() % n); }
static int64_t rval(void) {
  switch (rnd(6)) {
  case 0: return 0;
  case 1: return (int64_t)rnd(4) - 1;
  case 2: return (int64_t)rnd(130);
  case 3: return (int64_t)(int32_t)rnd64();
  case 4: return INT64_MIN + rnd(2);
  default: return (int64_t)rnd64();
  }
}
static void gen_random(Code *c) {
  c->n = 0;
  int da = 0, db = 0, dc = 0, len = 1 + rnd(200), target = 1 + rnd(10);
  for (int i = 0; i < len; i++) {
    int op = rnd(OP_COUNT);
    if ((da < target || db < target) && rnd(3) == 0) op = rnd(2) ? OP_PUSH8_A : OP_PUSH32_B;
    if (rnd(6) == 0 && dc < target) op = rnd(2) ? OP_CPUSH_A : OP_CPUSH_B;
    int k = op_kind[op];
    if (k == K_HALT || k == K_CALL || k == K_TCALL || k == K_RET || k == K_INTERNAL || op == OP_JMP) continue;
    if ((!strncmp(op_name[op], "DIV", 3) || !strncmp(op_name[op], "REM", 3) || op == OP_POWS ||
         !strncmp(op_name[op], "CHK", 3)) && rnd(10)) continue;
    const char *nm = op_name[op];
    size_t L = strlen(nm);
    char X = nm[L - 1];
    int needA = 0, needB = 0, needC = 0, pushA = 0, pushB = 0, popA = 0, popB = 0, pushC = 0, popC = 0;
    if (k == K_OPI) { if ((X == 'A' ? da : db) < 1) continue; e2(c, op, (int)rval()); continue; }
    if (k == K_OPC) { if ((X == 'A' ? da : db) < 1 || dc < 1) continue; e2(c, op, rnd(dc)); continue; }
    if (k == K_BRI) { if (da < 1) continue; pbri(c, ebri(c, op, (int)rval()), c->n); da--; continue; }
    switch (op) {
    case OP_PUSH8_A: e2(c, op, (int)rval()); da++; continue;
    case OP_PUSH8_B: e2(c, op, (int)rval()); db++; continue;
    case OP_PUSH32_A: e32(c, op, (int32_t)rval()); da++; continue;
    case OP_PUSH32_B: e32(c, op, (int32_t)rval()); db++; continue;
    case OP_PUSH64_A: e64(c, op, rval()); da++; continue;
    case OP_PUSH64_B: e64(c, op, rval()); db++; continue;
    case OP_ABORT: if (rnd(20)) continue; e2(c, op, 9); continue;
    case OP_DUP_A: needA = 1; pushA = 1; break;
    case OP_DUP_B: needB = 1; pushB = 1; break;
    case OP_DROP_A: needA = 1; popA = 1; break;
    case OP_DROP_B: needB = 1; popB = 1; break;
    case OP_COPY_AB: needA = 1; pushB = 1; break;
    case OP_COPY_BA: needB = 1; pushA = 1; break;
    case OP_MOVE_AB: needA = 1; popA = 1; pushB = 1; break;
    case OP_MOVE_BA: needB = 1; popB = 1; pushA = 1; break;
    case OP_CPUSH_A: needA = 1; popA = 1; pushC = 1; break;
    case OP_CPUSH_B: needB = 1; popB = 1; pushC = 1; break;
    case OP_CPUSHN: { if (da < 1) continue; int n = 1 + rnd(da < 4 ? da : 4); e2(c, op, n); da -= n; dc += n; continue; }
    case OP_CPOP: needC = 1; popC = 1; break;
    case OP_CGET0_A: needC = 1; pushA = 1; break;
    case OP_CGET0_B: needC = 1; pushB = 1; break;
    case OP_CGET1_A: needC = 2; pushA = 1; break;
    case OP_CGET1_B: needC = 2; pushB = 1; break;
    case OP_CSET0_A: needC = 1; needA = 1; popA = 1; break;
    case OP_CSET0_B: needC = 1; needB = 1; popB = 1; break;
    case OP_CGETR_A: case OP_CGETR_B: { if (dc < 1) continue; int n = 1 + rnd(dc < 4 ? dc : 4), d = rnd(dc - n + 1); e1(c, op); c->b[c->n++] = (uint8_t)d; c->b[c->n++] = (uint8_t)n; if (X == 'A') da += n; else db += n; continue; }
    case OP_CGETN_A: case OP_CGETN_B: case OP_CSETN_A: case OP_CSETN_B: {
      int get = op == OP_CGETN_A || op == OP_CGETN_B, isA = X == 'A';
      if (dc < 1 || (!get && (isA ? da : db) < 1)) continue;
      e2(c, op, rnd(dc));
      if (get) { if (isA) da++; else db++; } else { if (isA) da--; else db--; }
      continue;
    }
    case OP_ZX8: case OP_ZX16: case OP_CHKU8: case OP_CHKU16: case OP_CHKU32: case OP_CHKI32: case OP_CHKNN: needA = 1; break;
    case OP_POW: case OP_POWS: needA = 1; needB = 1; popB = 1; break;
    case OP_JZ_A: case OP_JNZ_A: if (da < 1) continue; ebr_to(c, op, c->n + 3); da--; continue;
    case OP_JZ_B: case OP_JNZ_B: if (db < 1) continue; ebr_to(c, op, c->n + 3); db--; continue;
    case OP_BEQ: case OP_BNE: case OP_BLT: case OP_BLE: case OP_BLTU: case OP_BLEU:
      if (da < 1 || db < 1) continue; ebr_to(c, op, c->n + 3); da--; db--; continue;
    default:
      if (!strncmp(nm, "NEG", 3) || !strncmp(nm, "NOT", 3) || !strncmp(nm, "LNOT", 4) ||
          !strncmp(nm, "ZX32", 4) || !strncmp(nm, "SX32", 4)) { if (X == 'A') needA = 1; else needB = 1; break; }
      needA = 1; needB = 1; if (X == 'A') popB = 1; else popA = 1; break;
    }
    if (da < needA || db < needB || dc < needC) continue;
    e1(c, op);
    da += pushA - popA; db += pushB - popB; dc += pushC - popC;
  }
  e1(c, OP_HALT);
}
static int run_tests(int count) {
  static Code c;
  V *A1 = mkstack(), *B1 = mkstack(), *C1 = mkstack(), *A2 = mkstack(), *B2 = mkstack(), *C2 = mkstack();
  int fails = 0, aborts = 0;
  for (int t = 0; t < count; t++) {
    gen_random(&c);
    V *ra = 0, *rb = 0, *rc = 0;
    int rr = ref_run(c.b, A1, B1, C1, &ra, &rb, &rc);
    vm_run(c.b, A2, B2, C2);
    int bad = (V)rr != vm_final.reason;
    if (!bad && rr == 0)
      bad = (ra - A1 != vm_final.asp - A2) || (rb - B1 != vm_final.bsp - B2) || (rc - C1 != vm_final.csp - C2)
         || memcmp(A1, A2, (ra - A1) * sizeof(V)) || memcmp(B1, B2, (rb - B1) * sizeof(V)) || memcmp(C1, C2, (rc - C1) * sizeof(V));
    aborts += rr != 0;
    if (bad && fails++ < 3) fprintf(stderr, "mismatch in test %d: ref reason %d, vm reason %d\n", t, rr, (int)vm_final.reason);
  }
  printf("differential tests: %d programs, %d ended in an abort, %s\n", count, aborts, fails ? "FAILED" : "all passed");
  return fails;
}
/* the result bit: a two-result word called with CALL.A and with CALL.B */
static int call_tests(void) {
  static Code c;
  int fails = 0;
  for (int toB = 0; toB < 2; toB++) {
    c.n = 0;
    push_a(&c, 17); push_a(&c, 5);
    int call = ecall(&c, toB ? OP_CALL_B : OP_CALL_A, 2);
    e1(&c, OP_HALT);
    pcall(&c, call, c.n);                                     /* frame: C0 = 17, C1 = 5 */
    e1(&c, OP_CGET0_A); e1(&c, OP_CGET1_B); e1(&c, OP_DIVU_A);
    e1(&c, OP_CGET0_A); e1(&c, OP_CGET1_B); e1(&c, OP_REMU_A);
    eret(&c, 2, 2);
    for (int vm = 0; vm < 2; vm++) {
      V *A = mkstack(), *B = mkstack(), *C = mkstack(), *fa, *fb, *fc;
      int reason;
      if (vm) { vm_run(c.b, A, B, C); fa = vm_final.asp; fb = vm_final.bsp; reason = (int)vm_final.reason; }
      else reason = ref_run(c.b, A, B, C, &fa, &fb, &fc);
      V *res = toB ? B : A, *end = toB ? fb : fa;
      int ok = reason == 0 && end - res == 2 && res[0] == 3 && res[1] == 2 && (toB ? fa == A : fb == B);
      if (!ok) { fails++; fprintf(stderr, "call test failed: CALL.%c on %s\n", toB ? 'B' : 'A', vm ? "vm" : "reference"); }
    }
  }
  printf("call tests: two results delivered to A and to B, %s\n", fails ? "FAILED" : "all passed");
  return fails;
}

/* ------------------------------------------------------------ benchmarks */
/* each benchmark in its milestone-1 form ("before") and with the frame
   instructions and operand forms ("after") */
static void loop_init(Code *c, int64_t acc, int64_t n) { push_a(c, acc); push_a(c, n); e1(c, OP_CPUSH_A); push_a(c, 0); e1(c, OP_CPUSH_A); }
static int loop_head(Code *c) { e1(c, OP_CGET1_A); e1(c, OP_CGET0_B); return ebr(c, OP_BLE); }   /* n <= i: done */
static void incr_old(Code *c) { e1(c, OP_CGET0_A); e2(c, OP_PUSH8_B, 1); e1(c, OP_ADD_A); e1(c, OP_CSET0_A); }
static void incr_new(Code *c) { e1(c, OP_CGET0_A); e2(c, OP_ADDI_A, 1); e1(c, OP_CSET0_A); }
static void loop_end(Code *c, int top, int ex) { ebr_to(c, OP_JMP, top); pbr(c, ex, c->n); e1(c, OP_HALT); }
static int sum_old(Code *c, int64_t n) { c->n = 0; loop_init(c, 0, n); int top = c->n, ex = loop_head(c);
  e1(c, OP_CGET0_B); e1(c, OP_ADD_A); incr_old(c); loop_end(c, top, ex); return 10; }
static int sum_new(Code *c, int64_t n) { c->n = 0; loop_init(c, 0, n); int top = c->n, ex = loop_head(c);
  e2(c, OP_ADDC_A, 0); incr_new(c); loop_end(c, top, ex); return 8; }
static int poly_old(Code *c, int64_t n) { c->n = 0; loop_init(c, 0, n); int top = c->n, ex = loop_head(c);
  e1(c, OP_CGET0_A); e2(c, OP_PUSH8_B, 3); e1(c, OP_MUL_A); e2(c, OP_PUSH8_B, 5); e1(c, OP_ADD_A);
  e1(c, OP_CGET0_B); e1(c, OP_MUL_A); e2(c, OP_PUSH8_B, 7); e1(c, OP_SUB_A); e1(c, OP_MOVE_AB); e1(c, OP_ADD_A);
  incr_old(c); loop_end(c, top, ex); return 19; }
static int poly_new(Code *c, int64_t n) { c->n = 0; loop_init(c, 0, n); int top = c->n, ex = loop_head(c);
  e1(c, OP_CGET0_A); e2(c, OP_MULI_A, 3); e2(c, OP_ADDI_A, 5); e2(c, OP_MULC_A, 0); e2(c, OP_SUBI_A, 7);
  e1(c, OP_MOVE_AB); e1(c, OP_ADD_A); incr_new(c); loop_end(c, top, ex); return 14; }
static int chain_old(Code *c, int64_t n) { c->n = 0; loop_init(c, 1, n); int top = c->n, ex = loop_head(c);
  for (int k = 0; k < 8; k++) { e2(c, OP_PUSH8_B, 3 + k); e1(c, k & 1 ? OP_ADD_A : OP_MUL_A); }
  incr_old(c); loop_end(c, top, ex); return 24; }
static int chain_new(Code *c, int64_t n) { c->n = 0; loop_init(c, 1, n); int top = c->n, ex = loop_head(c);
  for (int k = 0; k < 8; k++) e2(c, k & 1 ? OP_ADDI_A : OP_MULI_A, 3 + k);
  incr_new(c); loop_end(c, top, ex); return 15; }
/* fib: before, n travels on A; after, n lives in the frame and the second call delivers to B */
static int fib_old(Code *c, int64_t n) {
  c->n = 0; push_a(c, n);
  int call = ecall(c, OP_CALL_A, 0); e1(c, OP_HALT);
  int fib = c->n; pcall(c, call, fib);
  e1(c, OP_DUP_A); e2(c, OP_PUSH8_B, 2); int base = ebr(c, OP_BLT);
  e1(c, OP_DUP_A); e2(c, OP_PUSH8_B, 1); e1(c, OP_SUB_A); pcall(c, ecall(c, OP_CALL_A, 0), fib);
  e1(c, OP_MOVE_AB); e2(c, OP_PUSH8_B, 2); e1(c, OP_SUB_A); pcall(c, ecall(c, OP_CALL_A, 0), fib);
  e1(c, OP_ADD_A); eret(c, 0, 0);
  pbr(c, base, c->n); eret(c, 0, 0);
  return 0;
}
static int fib_new(Code *c, int64_t n) {
  c->n = 0; push_a(c, n);
  int call = ecall(c, OP_CALL_A, 1); e1(c, OP_HALT);
  int fib = c->n; pcall(c, call, fib);                       /* frame: C0 = n */
  e1(c, OP_CGET0_A); int rec = ebri(c, OP_BGEI, 2);          /* n >= 2: recurse */
  e1(c, OP_CGET0_A); eret(c, 1, 1);
  pbri(c, rec, c->n);
  e1(c, OP_CGET0_A); e2(c, OP_SUBI_A, 1); pcall(c, ecall(c, OP_CALL_A, 1), fib);
  e1(c, OP_CGET0_A); e2(c, OP_SUBI_A, 2); pcall(c, ecall(c, OP_CALL_B, 1), fib);
  e1(c, OP_ADD_A); eret(c, 1, 1);
  return 0;
}
/* Let section 13: next32 and skip */
static int skip_old(Code *c, int64_t n) {
  c->n = 0; push_a(c, 2463534242); push_a(c, n);
  int call = ecall(c, OP_CALL_A, 0); e1(c, OP_HALT);
  int next32 = c->n;
  static const int sh[3] = { 13, 17, 5 }, left[3] = { 1, 0, 1 };
  for (int k = 0; k < 3; k++) {
    e1(c, OP_DUP_A); e2(c, OP_PUSH8_B, sh[k]); e1(c, left[k] ? OP_SHL_A : OP_SHR_A);
    if (left[k]) e1(c, OP_ZX32_A);
    e1(c, OP_MOVE_AB); e1(c, OP_XOR_A);
  }
  eret(c, 0, 0);
  int skip = c->n; pcall(c, call, skip);
  e1(c, OP_CPUSH_A); e1(c, OP_CPUSH_A);
  int loop = c->n;
  e1(c, OP_CGET1_A); e2(c, OP_PUSH8_B, 0); int done = ebr(c, OP_BEQ);
  e1(c, OP_CGET0_A); pcall(c, ecall(c, OP_CALL_A, 0), next32);
  e1(c, OP_CGET1_A); e2(c, OP_PUSH8_B, 1); e1(c, OP_SUB_A); e1(c, OP_ZX32_A);
  e2(c, OP_CSETN_A, 1); e1(c, OP_CSET0_A); ebr_to(c, OP_JMP, loop);
  pbr(c, done, c->n);
  e1(c, OP_CGET0_A); e1(c, OP_CPOP); e1(c, OP_CPOP); eret(c, 0, 0);
  return 30;
}
static int skip_new(Code *c, int64_t n) {
  c->n = 0; push_a(c, 2463534242); push_a(c, n);
  int call = ecall(c, OP_CALL_A, 2); e1(c, OP_HALT);
  int next32 = c->n;                                          /* frame: C0 = s */
  e1(c, OP_CGET0_A); e2(c, OP_SHLI_A, 13); e1(c, OP_ZX32_A); e2(c, OP_XORC_A, 0);
  e1(c, OP_DUP_A); e2(c, OP_SHRI_A, 17); e1(c, OP_MOVE_AB); e1(c, OP_XOR_A);
  e1(c, OP_DUP_A); e2(c, OP_SHLI_A, 5); e1(c, OP_ZX32_A); e1(c, OP_MOVE_AB); e1(c, OP_XOR_A);
  eret(c, 1, 1);
  int skip = c->n; pcall(c, call, skip);                      /* frame: C0 = s, C1 = n */
  e1(c, OP_CGET1_A); int done = ebri(c, OP_BEQI, 0);
  e1(c, OP_CGET0_A); pcall(c, ecall(c, OP_CALL_A, 1), next32);
  e1(c, OP_CGET1_A); e2(c, OP_SUBI_A, 1); e1(c, OP_ZX32_A);
  ptcall(c, etcall(c, 2, 2), skip);
  pbri(c, done, c->n);
  e1(c, OP_CGET0_A); eret(c, 2, 1);
  return 22;
}

/* what a completed compiled tier would run: next32 inlined into the loop.
   _tc keeps the loop as a TCALL; _jmp rebinds the parameters and jumps. */
static int skip_inl_body(Code *c) {
  e1(c, OP_CGET0_A); e2(c, OP_SHLI_A, 13); e1(c, OP_ZX32_A); e2(c, OP_XORC_A, 0);
  e1(c, OP_DUP_A); e2(c, OP_SHRI_A, 17); e1(c, OP_MOVE_AB); e1(c, OP_XOR_A);
  e1(c, OP_DUP_A); e2(c, OP_SHLI_A, 5); e1(c, OP_ZX32_A); e1(c, OP_MOVE_AB); e1(c, OP_XOR_A);
  e1(c, OP_CGET1_A); e2(c, OP_SUBI_A, 1); e1(c, OP_ZX32_A);
  return 0;
}
static int skip_inl_tc(Code *c, int64_t n) {
  c->n = 0; push_a(c, 2463534242); push_a(c, n);
  int call = ecall(c, OP_CALL_A, 2); e1(c, OP_HALT);
  int skip = c->n; pcall(c, call, skip);
  e1(c, OP_CGET1_A); int done = ebri(c, OP_BEQI, 0);
  skip_inl_body(c); ptcall(c, etcall(c, 2, 2), skip);
  pbri(c, done, c->n); e1(c, OP_CGET0_A); eret(c, 2, 1);
  return 19;
}
static int skip_inl_jmp(Code *c, int64_t n) {
  c->n = 0; push_a(c, 2463534242); push_a(c, n);
  int call = ecall(c, OP_CALL_A, 2); e1(c, OP_HALT);
  int skip = c->n; pcall(c, call, skip);
  int loop = c->n;
  e1(c, OP_CGET1_A); int done = ebri(c, OP_BEQI, 0);
  skip_inl_body(c); e2(c, OP_CSETN_A, 1); e1(c, OP_CSET0_A); ebr_to(c, OP_JMP, loop);
  pbri(c, done, c->n); e1(c, OP_CGET0_A); eret(c, 2, 1);
  return 21;
}
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static V fib_native(V n) { return n < 2 ? n : fib_native(n - 1) + fib_native(n - 2); }
static double timed(int (*prog)(Code *, int64_t), int64_t n, V expect, int *ok, int *per) {
  static Code c;
  *per = prog(&c, n);
  V *A = mkstack(), *B = mkstack(), *C = mkstack();
  double best = 1e9;
  for (int r = 0; r < 5; r++) {
    double t0 = now(); vm_run(c.b, A, B, C); double t = now() - t0;
    if (t < best) best = t;
    if (vm_final.reason || vm_final.asp[-1] != expect) *ok = 0;
  }
  free(A - GUARD); free(B - GUARD); free(C - GUARD);
  return best;
}
static void bench(const char *name, int (*before)(Code *, int64_t), int (*after)(Code *, int64_t), int64_t n,
                  V expect, double units, const char *unit) {
  int ok = 1, pb, pa;
  double tb = timed(before, n, expect, &ok, &pb), ta = timed(after, n, expect, &ok, &pa);
  printf("  %-6s %6.2f -> %6.2f ns per %-9s %4.2fx faster", name, tb * 1e9 / units, ta * 1e9 / units, unit, tb / ta);
  if (pb && pa) printf("   %2d -> %2d instructions", pb, pa);
  printf("  %s\n", ok ? "ok" : "WRONG");
}
int main(int argc, char **argv) {
  int f = run_tests(argc > 1 ? atoi(argv[1]) : 20000);
  f += call_tests();
  if (f) return 1;
  if (argc > 2 && !strcmp(argv[2], "notime")) return 0;
  if (argc > 2 && !strcmp(argv[2], "compile")) {
    /* compile cost: one long straight-line program, compiled and run once */
    static Code c; const int K = 15000;
    c.n = 0; push_a(&c, 1);
    for (int i = 0; i < K; i++) e2(&c, i & 1 ? OP_ADDI_A : OP_XORI_A, 3 + (i & 7));
    e1(&c, OP_HALT);
    V *A = mkstack(), *B = mkstack(), *C = mkstack();
    double best = 1e9;
    for (int r = 0; r < 20; r++) { double t0 = now(); vm_run(c.b, A, B, C); double t = now() - t0; if (t < best) best = t; }
    printf("compile and run once: %d instructions in %.1f us, %.1f ns per instruction\n", K + 2, best * 1e6, best * 1e9 / (K + 2));
    return 0;
  }
  const int64_t N = 50000000;
  bench("sum", sum_old, sum_new, N, (V)N * (N - 1) / 2, (double)N, "iteration");
  { V acc = 0; for (V i = 0; i < (V)N / 2; i++) acc += (3 * i + 5) * i - 7; bench("poly", poly_old, poly_new, N / 2, acc, N / 2.0, "iteration"); }
  { V x = 1; for (int64_t i = 0; i < N / 4; i++) for (int k = 0; k < 8; k++) x = k & 1 ? x + 3 + k : x * (3 + k);
    bench("chain", chain_old, chain_new, N / 4, x, N / 4.0, "iteration"); }
  { const int64_t F = 30; V calls = 2 * fib_native(F + 1) - 1; bench("fib", fib_old, fib_new, F, fib_native(F), (double)calls, "call"); }
  { uint32_t s = 2463534242u; for (int64_t i = 0; i < N / 4; i++) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; }
    bench("skip", skip_old, skip_new, N / 4, s, N / 4.0, "iteration");
    if (argc > 2 && !strcmp(argv[2], "inline")) {
      bench("inl-tc", skip_new, skip_inl_tc, N / 4, s, N / 4.0, "iteration");
      bench("inl-jmp", skip_new, skip_inl_jmp, N / 4, s, N / 4.0, "iteration");
    } }
  return 0;
}
