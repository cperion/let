#define _POSIX_C_SOURCE 200809L
#include "support.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

struct probe { const char *name; kernel_fn let, reference; int64_t input; int resources; };
#define PROBE(name, input, resources) {#name, let_##name, ref_##name, input, resources}
static const struct probe probes[] = {
    PROBE(constant, 41, 0), PROBE(affine, 41, 0),
    PROBE(sum_loop, 10000, 0), PROBE(sum_tail, 10000, 0),
    PROBE(fib_loop, 1000, 0), PROBE(fib_recursive, 22, 0),
    PROBE(mix, 10000, 0), PROBE(gcd, 123456789, 0),
    PROBE(prelude_tail, 10000, 0),
    PROBE(resource_loop, 1000, 1), PROBE(resource_tail, 1000, 2),
};
static volatile uint64_t sink;
static double now(void) {
    struct timespec t; assert(clock_gettime(CLOCK_MONOTONIC, &t) == 0);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}
static int64_t checked(const struct probe *probe, kernel_fn fn, int64_t n) {
    bench_reset();
    int64_t value = fn(n);
    uint64_t expected = 0;
    if (probe->resources == 1 && n > 0) expected = (uint64_t)n;
    if (probe->resources == 2) expected = n > 0 ? (uint64_t)n + 1 : 1;
    assert(bench_live() == 0 && bench_allocations() == expected && bench_releases() == expected);
    return value;
}
static void validate(const struct probe *probe) {
    int64_t inputs[] = {-3, 0, 1, 2, 7, 17, probe->input, probe->input + 1};
    for (unsigned i = 0; i < sizeof inputs / sizeof *inputs; ++i) {
        int64_t a = checked(probe, probe->let, inputs[i]);
        int64_t b = checked(probe, probe->reference, inputs[i]);
        if (a != b) {
            fprintf(stderr, "%s(%" PRId64 "): Let=%" PRId64 ", C=%" PRId64 "\n", probe->name, inputs[i], a, b);
            exit(1);
        }
    }
}
static double batch(kernel_fn fn, int64_t n, uint64_t repeats, uint64_t *checksum) {
    uint64_t sum = 0;
    double start = now();
    for (uint64_t i = 0; i < repeats; ++i) sum += (uint64_t)fn(n + (int64_t)(i & 1));
    double elapsed = now() - start;
    sink = sum; *checksum = sum;
    assert(bench_live() == 0);
    return elapsed;
}
static uint64_t calibrate(kernel_fn fn, int64_t n, double seconds) {
    uint64_t repeats = 1, checksum;
    while (batch(fn, n, repeats, &checksum) < seconds && repeats < (UINT64_C(1) << 29)) repeats *= 2;
    return repeats;
}
int main(int argc, char **argv) {
    int samples = argc > 1 ? atoi(argv[1]) : 7;
    double seconds = argc > 2 ? atof(argv[2]) : 0.02;
    assert(samples >= 3 && samples <= 31 && seconds >= 0.001 && seconds <= 1);
    for (unsigned i = 0; i < sizeof probes / sizeof *probes; ++i) validate(&probes[i]);
    puts("case,implementation,sample,repetitions,ns_per_call,checksum");
    for (unsigned i = 0; i < sizeof probes / sizeof *probes; ++i) {
        const struct probe *p = &probes[i];
        uint64_t repeats[2] = {calibrate(p->let, p->input, seconds), calibrate(p->reference, p->input, seconds)};
        for (int sample = 0; sample < samples; ++sample) {
            for (int k = 0; k < 2; ++k) {
                int implementation = (sample + k) & 1;
                uint64_t checksum;
                double elapsed = batch(implementation ? p->reference : p->let, p->input, repeats[implementation], &checksum);
                printf("%s,%s,%d,%" PRIu64 ",%.6f,%" PRIu64 "\n", p->name, implementation ? "C" : "Let", sample, repeats[implementation], elapsed * 1e9 / (double)repeats[implementation], checksum);
            }
        }
    }
    return 0;
}

