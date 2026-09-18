#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    int64_t r;
};

struct let_s2 {
    uint8_t g;
};

struct let_s3 {
    uint8_t g;
    int64_t x;
};

struct let_s4 {
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_square_construct(void);

static uint8_t let_apply_construct(void);

static struct let_s2 let_apply_advance_0(uint8_t p1, uint8_t p2);

static struct let_s3 let_apply_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_apply_run(struct let_s3 p1);

static struct let_s4 let_square_advance_0(uint8_t p1, int64_t p2);

static int64_t let_square_run(struct let_s4 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_square_construct();
        uint8_t v2 = let_apply_construct();
        uint8_t v4 = let_apply_construct();
        struct let_s2 v5 = let_apply_advance_0(v4, v1);
        struct let_s3 v6 = let_apply_advance_1(v5, INT64_C(3));
        int64_t v7 = let_apply_run(v6);
        struct let_s1 v8 = ((struct let_s1){v7});
        return v8;
    }
}

static uint8_t let_square_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_apply_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_apply_advance_0(uint8_t p1, uint8_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s3 let_apply_advance_1(struct let_s2 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).g;
        struct let_s3 v4 = ((struct let_s3){v3, p2});
        return v4;
    }
}

static int64_t let_apply_run(struct let_s3 p1) {
    {
        uint8_t v2 = (p1).g;
        int64_t v3 = (p1).x;
        struct let_s4 v4 = let_square_advance_0(v2, v3);
        int64_t v5 = let_square_run(v4);
        return v5;
    }
}

static struct let_s4 let_square_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static int64_t let_square_run(struct let_s4 p1) {
    {
        int64_t v2 = (p1).x;
        int64_t v3 = ((int64_t)(((uint64_t)v2) * ((uint64_t)v2)));
        return v3;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.r);
    return 0; }
