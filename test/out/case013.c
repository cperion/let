#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s2 {
    int64_t a;
};

struct let_s1 {
    uint8_t sum;
    struct let_s2 add_one;
    int64_t answer;
};

struct let_s3 {
    int64_t a;
    int64_t b;
};

struct let_s1 let_module_init(void);

static uint8_t let_sum_construct(void);

static struct let_s2 let_sum_advance_0(uint8_t p1, int64_t p2);

static struct let_s3 let_sum_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_sum_run(struct let_s3 p1);

int64_t let_sum_entry(struct let_s1 p1, int64_t p2, int64_t p3);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_sum_construct();
        uint8_t v3 = let_sum_construct();
        struct let_s2 v4 = let_sum_advance_0(v3, INT64_C(1));
        struct let_s3 v6 = let_sum_advance_1(v4, INT64_C(2));
        int64_t v7 = let_sum_run(v6);
        struct let_s1 v8 = ((struct let_s1){v1, v4, v7});
        return v8;
    }
}

static uint8_t let_sum_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_sum_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s3 let_sum_advance_1(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).a;
        struct let_s3 v4 = ((struct let_s3){v3, p2});
        return v4;
    }
}

static int64_t let_sum_run(struct let_s3 p1) {
    {
        int64_t v2 = (p1).a;
        int64_t v3 = (p1).b;
        int64_t v4 = ((int64_t)(((uint64_t)v2) + ((uint64_t)v3)));
        return v4;
    }
}

int64_t let_sum_entry(struct let_s1 p1, int64_t p2, int64_t p3) {
    {
        uint8_t v4 = (p1).sum;
        struct let_s2 v5 = let_sum_advance_0(v4, p2);
        struct let_s3 v6 = let_sum_advance_1(v5, p3);
        int64_t v7 = let_sum_run(v6);
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
