#include "support.h"
#include <assert.h>
#include <stdlib.h>

/* External calls deliberately remain outside the kernels' translation units.
   This measures handle/ABI/cleanup overhead, not malloc performance. */
static struct { int live; int64_t payload; } slots[4];
static uint64_t allocations, releases;
static int live;
int64_t bench_acquire(int64_t value) {
    for (int i = 0; i < 4; ++i) if (!slots[i].live) {
        slots[i].live = 1; slots[i].payload = value;
        ++live; ++allocations; return i + 1;
    }
    abort();
}
int64_t bench_peek(int64_t handle) {
    assert(handle > 0 && handle <= 4 && slots[handle - 1].live);
    return slots[handle - 1].payload;
}
void bench_release(int64_t handle) {
    assert(handle > 0 && handle <= 4 && slots[handle - 1].live);
    slots[handle - 1].live = 0; --live; ++releases;
}
void bench_reset(void) { assert(live == 0); allocations = releases = 0; }
uint64_t bench_allocations(void) { return allocations; }
uint64_t bench_releases(void) { return releases; }
int bench_live(void) { return live; }

