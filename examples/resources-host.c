/* Minimal embedding for resources.let: integer handles, no hidden GC. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

static struct { bool live; int64_t size; } buffers[16];

int64_t app_open(int64_t size) {
    for (int i = 0; i < 16; ++i) {
        if (!buffers[i].live) {
            buffers[i].live = true; buffers[i].size = size;
            return i + 1;
        }
    }
    abort(); /* Explicit unrecoverable allocation trap in this tiny host. */
}

int64_t app_size(int64_t handle) {
    assert(handle > 0 && handle <= 16 && buffers[handle - 1].live);
    return buffers[handle - 1].size;
}

void app_close(int64_t handle) {
    assert(handle > 0 && handle <= 16 && buffers[handle - 1].live);
    buffers[handle - 1].live = false;
}

extern int64_t let_answer(void);
int main(void) {
    printf("%" PRId64 "\n", let_answer());
    for (int i = 0; i < 16; ++i) assert(!buffers[i].live);
    return 0;
}

