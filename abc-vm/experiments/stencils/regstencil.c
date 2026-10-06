#include <stdint.h>
typedef uint64_t V;
#define PN __attribute__((preserve_none))
#define ARGS V *asp, V *bsp, V *csp, V r0, V r1, V r2, V r3, V r4, V r5, V r6, V r7
#define PASS asp, bsp, csp, r0, r1, r2, r3, r4, r5, r6, r7
extern PN V HOLE_NEXT(ARGS);
extern char HOLE_IMM[];
/* register-addressed residual stencils: each touches only the registers it names */
PN V add_r3_r5(ARGS) { r3 = r3 + r5; [[clang::musttail]] return HOLE_NEXT(PASS); }
PN V xor_r1_r6(ARGS) { r1 = r1 ^ r6; [[clang::musttail]] return HOLE_NEXT(PASS); }
PN V shl_r2_imm(ARGS) { r2 = r2 << ((uintptr_t)HOLE_IMM & 63); [[clang::musttail]] return HOLE_NEXT(PASS); }
PN V mov_r4_r0(ARGS) { r4 = r0; [[clang::musttail]] return HOLE_NEXT(PASS); }
/* a u32 operation: wrap at 32 bits, which should need no separate mask */
PN V shl32_r2_imm(ARGS) { r2 = (uint32_t)((uint32_t)r2 << ((uintptr_t)HOLE_IMM & 31)); [[clang::musttail]] return HOLE_NEXT(PASS); }
PN V xor32_r1_r6(ARGS) { r1 = (uint32_t)r1 ^ (uint32_t)r6; [[clang::musttail]] return HOLE_NEXT(PASS); }
