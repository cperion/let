#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    uint8_t g;
    int64_t staged;
    int64_t invoked;
};

struct let_s2 {
    int64_t a;
    int64_t p;
};

struct let_s3 {
    int64_t a;
    int64_t p;
    int64_t b;
};

struct let_s1 let_module_init(void);

static uint8_t let_g_construct(void);

static struct let_s2 let_g_advance_0(uint8_t p1, int64_t p2);

static struct let_s3 let_g_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_g_run(struct let_s3 p1);

int64_t let_g_entry(struct let_s1 p1, int64_t p2, int64_t p3);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_g_construct();
        uint8_t v4 = let_g_construct();
        struct let_s2 v5 = let_g_advance_0(v4, INT64_C(1));
        struct let_s3 v6 = let_g_advance_1(v5, INT64_C(2));
        int64_t v7 = let_g_run(v6);
        uint8_t v10 = let_g_construct();
        struct let_s2 v11 = let_g_advance_0(v10, INT64_C(1));
        struct let_s3 v12 = let_g_advance_1(v11, INT64_C(2));
        int64_t v13 = let_g_run(v12);
        struct let_s1 v14 = ((struct let_s1){v1, v7, v13});
        return v14;
    }
}

static uint8_t let_g_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_g_advance_0(uint8_t p1, int64_t p2) {
    {
        int64_t v4 = ((int64_t)(((uint64_t)p2) * ((uint64_t)INT64_C(10))));
        struct let_s2 v5 = ((struct let_s2){p2, v4});
        return v5;
    }
}

static struct let_s3 let_g_advance_1(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).a;
        int64_t v4 = (p1).p;
        struct let_s3 v5 = ((struct let_s3){v3, v4, p2});
        return v5;
    }
}

static int64_t let_g_run(struct let_s3 p1) {
    {
        int64_t v3 = (p1).p;
        int64_t v4 = (p1).b;
        int64_t v5 = ((int64_t)(((uint64_t)v3) + ((uint64_t)v4)));
        return v5;
    }
}

int64_t let_g_entry(struct let_s1 p1, int64_t p2, int64_t p3) {
    {
        uint8_t v4 = (p1).g;
        struct let_s2 v5 = let_g_advance_0(v4, p2);
        struct let_s3 v6 = let_g_advance_1(v5, p3);
        int64_t v7 = let_g_run(v6);
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld\n", (long long)m.staged, (long long)m.invoked);
    return 0; }
