#ifndef LET_BENCH_SUPPORT_H
#define LET_BENCH_SUPPORT_H
#include <stdint.h>
typedef int64_t (*kernel_fn)(int64_t);
int64_t bench_acquire(int64_t);
int64_t bench_peek(int64_t);
void bench_release(int64_t);
void bench_reset(void);
uint64_t bench_allocations(void);
uint64_t bench_releases(void);
int bench_live(void);
#define KERNELS(X) \
    X(constant) X(affine) X(sum_loop) X(sum_tail) X(fib_loop) \
    X(fib_recursive) X(mix) X(gcd) X(prelude_tail) X(resource_loop) X(resource_tail)
#define DECLARE(name) int64_t let_##name(int64_t); int64_t ref_##name(int64_t);
KERNELS(DECLARE)
#undef DECLARE
#endif

