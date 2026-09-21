#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
typedef int64_t Buffer;

#include <stdint.h>

extern Buffer app_open(int64_t a1);

extern int64_t app_size(Buffer a1);

extern void app_close(Buffer a1);

struct let_s2 {
    uint8_t buffer_size;
};

struct let_s3 {
    uint8_t open_buffer;
    struct let_s2 consume_buffer;
};

struct let_s1 {
    uint8_t open_buffer;
    uint8_t buffer_size;
    struct let_s2 consume_buffer;
    struct let_s3 answer;
};

struct let_s4 {
    int64_t size;
};

struct let_s5 {
    Buffer b;
};

struct let_s6 {
    uint8_t buffer_size;
    Buffer buffer;
};

struct let_s1 let_module_init(void);

static uint8_t let_open_buffer_construct(void);

static uint8_t let_buffer_size_construct(void);

static struct let_s2 let_consume_buffer_construct(uint8_t p1);

static struct let_s3 let_answer_construct(uint8_t p1, struct let_s2 p2);

Buffer let_open_buffer_entry(struct let_s1 p1, int64_t p2);

static struct let_s4 let_open_buffer_advance_0(uint8_t p1, int64_t p2);

static Buffer let_open_buffer_run(struct let_s4 p1);

int64_t let_buffer_size_entry(struct let_s1 p1, Buffer p2);

static struct let_s5 let_buffer_size_advance_0(uint8_t p1, Buffer p2);

static int64_t let_buffer_size_run(struct let_s5 p1);

int64_t let_consume_buffer_entry(struct let_s1 p1, Buffer p2);

static struct let_s6 let_consume_buffer_advance_0(struct let_s2 p1, Buffer p2);

static int64_t let_consume_buffer_run(struct let_s6 p1);

int64_t let_answer_entry(struct let_s1 p1);

static int64_t let_answer_run(struct let_s3 p1);

void let_module_unload(struct let_s1 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_open_buffer_construct();
        uint8_t v2 = let_buffer_size_construct();
        struct let_s2 v3 = let_consume_buffer_construct(v2);
        struct let_s3 v4 = let_answer_construct(v1, v3);
        struct let_s1 v6 = ((struct let_s1){v1, v2, v3, v4});
        return v6;
    }
}

static uint8_t let_open_buffer_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_buffer_size_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_consume_buffer_construct(uint8_t p1) {
    {
        struct let_s2 v2 = ((struct let_s2){p1});
        return v2;
    }
}

static struct let_s3 let_answer_construct(uint8_t p1, struct let_s2 p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p1, p2});
        return v3;
    }
}

Buffer let_open_buffer_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).open_buffer;
        struct let_s4 v4 = let_open_buffer_advance_0(v3, p2);
        Buffer v5 = let_open_buffer_run(v4);
        return v5;
    }
}

static struct let_s4 let_open_buffer_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static Buffer let_open_buffer_run(struct let_s4 p1) {
    {
        int64_t v2 = (p1).size;
        Buffer v3 = app_open(v2);
        return v3;
    }
}

int64_t let_buffer_size_entry(struct let_s1 p1, Buffer p2) {
    {
        uint8_t v3 = (p1).buffer_size;
        struct let_s5 v4 = let_buffer_size_advance_0(v3, p2);
        int64_t v5 = let_buffer_size_run(v4);
        return v5;
    }
}

static struct let_s5 let_buffer_size_advance_0(uint8_t p1, Buffer p2) {
    {
        struct let_s5 v3 = ((struct let_s5){p2});
        return v3;
    }
}

static int64_t let_buffer_size_run(struct let_s5 p1) {
    {
        Buffer v2 = (p1).b;
        int64_t v3 = app_size(v2);
        return v3;
    }
}

int64_t let_consume_buffer_entry(struct let_s1 p1, Buffer p2) {
    {
        struct let_s2 v3 = (p1).consume_buffer;
        struct let_s6 v4 = let_consume_buffer_advance_0(v3, p2);
        int64_t v5 = let_consume_buffer_run(v4);
        return v5;
    }
}

static struct let_s6 let_consume_buffer_advance_0(struct let_s2 p1, Buffer p2) {
    {
        uint8_t v3 = (p1).buffer_size;
        struct let_s6 v4 = ((struct let_s6){v3, p2});
        return v4;
    }
}

static int64_t let_consume_buffer_run(struct let_s6 p1) {
    {
        uint8_t v2 = (p1).buffer_size;
        Buffer v3 = (p1).buffer;
        struct let_s5 v4 = let_buffer_size_advance_0(v2, v3);
        int64_t v5 = let_buffer_size_run(v4);
        app_close(v3);
        return v5;
    }
}

int64_t let_answer_entry(struct let_s1 p1) {
    {
        struct let_s3 v2 = (p1).answer;
        int64_t v3 = let_answer_run(v2);
        return v3;
    }
}

static int64_t let_answer_run(struct let_s3 p1) {
    {
        uint8_t v2 = (p1).open_buffer;
        struct let_s2 v3 = (p1).consume_buffer;
        struct let_s4 v5 = let_open_buffer_advance_0(v2, INT64_C(16));
        Buffer v6 = let_open_buffer_run(v5);
        struct let_s4 v8 = let_open_buffer_advance_0(v2, INT64_C(32));
        Buffer v9 = let_open_buffer_run(v8);
        struct let_s6 v11 = let_consume_buffer_advance_0(v3, v6);
        int64_t v12 = let_consume_buffer_run(v11);
        struct let_s6 v14 = let_consume_buffer_advance_0(v3, v9);
        int64_t v15 = let_consume_buffer_run(v14);
        int64_t v16 = ((int64_t)(((uint64_t)v12) + ((uint64_t)v15)));
        return v16;
    }
}

void let_module_unload(struct let_s1 p1) {
    {
        return;
    }
}

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
