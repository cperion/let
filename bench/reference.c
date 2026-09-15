#include "support.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>

/* Same 64-bit wrapping semantics on the measured two's-complement target.
   Unsigned arithmetic is intentional: plain signed C overflow is not a baseline. */
static int64_t signed_bits(uint64_t value) {
    int64_t result; memcpy(&result, &value, sizeof result); return result;
}
int64_t ref_multiply(int64_t a, int64_t b) { return signed_bits((uint64_t)a * (uint64_t)b); }
int64_t ref_pending(void) { return ref_multiply(6, 7); }
int64_t ref_constant(int64_t ignored) { (void)ignored; return ref_pending(); }
int64_t ref_affine_template(int64_t scale, int64_t bias, int64_t value) {
    return signed_bits((uint64_t)scale * (uint64_t)value + (uint64_t)bias);
}
int64_t ref_affine(int64_t value) { return ref_affine_template(3, 7, value); }
int64_t ref_sum_loop(int64_t n) {
    uint64_t total = 0;
    for (int64_t i = 0; i < n; ++i) total += (uint64_t)i;
    return signed_bits(total);
}
int64_t ref_sum_tail_impl(int64_t n, int64_t initial) {
    uint64_t total = (uint64_t)initial;
    while (n > 0) { total += (uint64_t)(n - 1); --n; }
    return signed_bits(total);
}
int64_t ref_sum_tail(int64_t n) { return ref_sum_tail_impl(n, 0); }
int64_t ref_fib_loop(int64_t n) {
    uint64_t a = 0, b = 1;
    for (int64_t i = 0; i < n; ++i) { uint64_t next = a + b; a = b; b = next; }
    return signed_bits(a);
}
int64_t ref_fib_recursive(int64_t n) {
    if (n <= 1) return n;
    return signed_bits((uint64_t)ref_fib_recursive(n - 1) + (uint64_t)ref_fib_recursive(n - 2));
}
int64_t ref_mix(int64_t n) {
    uint64_t state = 1;
    for (int64_t i = 0; i < n; ++i) state = state * UINT64_C(6364136223846793005) + UINT64_C(1442695040888963407);
    return signed_bits(state);
}
int64_t ref_gcd_impl(int64_t a, int64_t b) {
    while (b != 0) {
        int64_t remainder = (a == INT64_MIN && b == -1) ? 0 : a % b;
        a = b; b = remainder;
    }
    return a;
}
int64_t ref_gcd(int64_t value) { return ref_gcd_impl(value, 65537); }
int64_t ref_prelude_tail_impl(int64_t n, int64_t initial) {
    uint64_t total = (uint64_t)initial;
    while (n > 0) { int64_t step = n - 1; total += (uint64_t)step; n = step; }
    return signed_bits(total);
}
int64_t ref_prelude_tail(int64_t n) { return ref_prelude_tail_impl(n, 0); }
int64_t ref_resource_loop(int64_t n) {
    uint64_t total = 0;
    for (int64_t i = 0; i < n; ++i) {
        int64_t cell = bench_acquire(i);
        total += (uint64_t)bench_peek(cell);
        bench_release(cell);
    }
    return signed_bits(total);
}
int64_t ref_resource_tail_impl(int64_t n, int64_t initial) {
    uint64_t total = (uint64_t)initial;
    int64_t cell = bench_acquire(n), value = bench_peek(cell);
    while (n > 0) {
        int64_t next_n = n - 1;
        uint64_t next_total = total + (uint64_t)value;
        int64_t next_cell = bench_acquire(next_n), next_value = bench_peek(next_cell);
        bench_release(cell); /* Preparation before old-activation cleanup. */
        n = next_n; total = next_total; cell = next_cell; value = next_value;
    }
    bench_release(cell);
    return signed_bits(total);
}
int64_t ref_resource_tail(int64_t n) { return ref_resource_tail_impl(n, 0); }

