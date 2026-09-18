#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    int64_t a;
    int64_t b;
};

struct let_s2 {
    int64_t T;
};

struct let_s3 {
    int64_t a;
};

struct let_s1 let_module_init(void);

static uint8_t let_Pair_construct(void);

static struct let_s2 let_Pair_advance_0(uint8_t p1, int64_t p2);

static uint8_t let_Pair_run(struct let_s2 p1);

static uint8_t let_word3_construct(void);

static struct let_s3 let_word3_advance_0(uint8_t p1, int64_t p2);

static struct let_s1 let_word3_advance_1(struct let_s3 p1, int64_t p2);

static struct let_s1 let_word3_run(struct let_s1 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_Pair_construct();
        uint8_t v3 = let_Pair_construct();
        struct let_s2 v4 = let_Pair_advance_0(v3, INT64_C(5));
        uint8_t v5 = let_Pair_run(v4);
        uint8_t v8 = let_word3_construct();
        struct let_s3 v9 = let_word3_advance_0(v8, INT64_C(1));
        struct let_s1 v10 = let_word3_advance_1(v9, INT64_C(2));
        struct let_s1 v11 = let_word3_run(v10);
        int64_t v12 = (v11).a;
        int64_t v13 = (v11).b;
        struct let_s1 v14 = ((struct let_s1){v12, v13});
        return v14;
    }
}

static uint8_t let_Pair_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_Pair_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static uint8_t let_Pair_run(struct let_s2 p1) {
    {
        uint8_t v3 = let_word3_construct();
        return v3;
    }
}

static uint8_t let_word3_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s3 let_word3_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static struct let_s1 let_word3_advance_1(struct let_s3 p1, int64_t p2) {
    {
        int64_t v3 = (p1).a;
        struct let_s1 v4 = ((struct let_s1){v3, p2});
        return v4;
    }
}

static struct let_s1 let_word3_run(struct let_s1 p1) {
    {
        int64_t v2 = (p1).a;
        int64_t v3 = (p1).b;
        struct let_s1 v4 = ((struct let_s1){v2, v3});
        return v4;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld\n", (long long)m.a, (long long)m.b);
    return 0; }
