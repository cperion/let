/* Minimal embedding for resources.let: integer handles, no hidden GC. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

/* The unit NAMES this type -- `host Buffer app_close` -- so the host declares it (§S44). */
typedef int64_t Buffer;

static struct { bool live; int64_t size; } buffers[16];

Buffer app_open(int64_t size) {
    for (int i = 0; i < 16; ++i) {
        if (!buffers[i].live) {
            buffers[i].live = true; buffers[i].size = size;
            return i + 1;
        }
    }
    abort(); /* Explicit unrecoverable allocation trap in this tiny host. */
}

int64_t app_size(Buffer handle) {
    assert(handle > 0 && handle <= 16 && buffers[handle - 1].live);
    return buffers[handle - 1].size;
}

void app_close(Buffer handle) {
    assert(handle > 0 && handle <= 16 && buffers[handle - 1].live);
    buffers[handle - 1].live = false;
}

int main(void) {
    struct let_s1 m = let_module_init();
    printf("%" PRId64 "\n", let_answer_entry(m));
    let_module_unload(m);
    /* §3.6: the module owns what it opened, so `unload` must have closed BOTH buffers. */
    for (int i = 0; i < 16; ++i) assert(!buffers[i].live);
    return 0;
}
