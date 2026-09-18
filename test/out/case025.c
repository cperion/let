#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    int64_t r;
};

struct let_s2 {
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_square_construct(void);

static struct let_s2 let_square_advance_0(uint8_t p1, int64_t p2);

static int64_t let_square_run(struct let_s2 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_square_construct();
        uint8_t v2 = let_square_construct();
        uint8_t v4 = let_square_construct();
        struct let_s2 v5 = let_square_advance_0(v4, INT64_C(3));
        int64_t v6 = let_square_run(v5);
        struct let_s1 v7 = ((struct let_s1){v6});
        return v7;
    }
}

static uint8_t let_square_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_square_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_square_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).x;
        int64_t v3 = ((int64_t)(((uint64_t)v2) * ((uint64_t)v2)));
        return v3;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.r);
    return 0; }
