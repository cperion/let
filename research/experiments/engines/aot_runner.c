#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

typedef struct { uint32_t status; uint32_t offset; uint8_t reason; } abc_aot_error;
typedef int (*abc_aot_entry)(const uint64_t *, size_t, uint64_t *, size_t, abc_aot_error *);
typedef struct { const char *name; uint32_t arguments; uint32_t results; abc_aot_entry entry; } abc_aot_export;

extern const abc_aot_export *abc_aot_find(const char *name);

static volatile uint64_t sink;

static double now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC_RAW, &time);
    return (double)time.tv_sec + (double)time.tv_nsec * 1e-9;
}

static int compare_double(const void *left, const void *right) {
    double a = *(const double *)left;
    double b = *(const double *)right;
    return (a > b) - (a < b);
}

int main(int argc, char **argv) {
    int trials = argc == 2 ? atoi(argv[1]) : 9;
    const abc_aot_export *entry = abc_aot_find("main");
    double *times;
    uint64_t result = 0;
    abc_aot_error error;

    if (!entry || entry->arguments || entry->results != 1 ||
        trials < 3 || !(trials & 1))
        return 2;
    times = calloc((size_t)trials, sizeof(*times));
    if (!times) return 2;
    if (entry->entry(NULL, 0, &result, 1, &error)) return 3;
    sink = result;
    for (int i = 0; i < trials; i++) {
        double start = now();
        if (entry->entry(NULL, 0, &result, 1, &error)) return 3;
        times[i] = now() - start;
        sink = result;
    }
    qsort(times, (size_t)trials, sizeof(*times), compare_double);
    printf("%llu %.9f\n", (unsigned long long)sink, times[trials / 2]);
    free(times);
    return 0;
}

