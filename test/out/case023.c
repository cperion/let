#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    int64_t a;
    int64_t b;
};

struct let_s2 {
    int64_t a;
};

struct let_s1 let_module_init(void);

static uint8_t let_word2_construct(void);

static struct let_s2 let_word2_advance_0(uint8_t p1, int64_t p2);

static struct let_s1 let_word2_advance_1(struct let_s2 p1, int64_t p2);

static struct let_s1 let_word2_run(struct let_s1 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_word2_construct();
        uint8_t v4 = let_word2_construct();
        struct let_s2 v5 = let_word2_advance_0(v4, INT64_C(1));
        struct let_s1 v6 = let_word2_advance_1(v5, INT64_C(2));
        struct let_s1 v7 = let_word2_run(v6);
        int64_t v8 = (v7).a;
        int64_t v9 = (v7).b;
        struct let_s1 v10 = ((struct let_s1){v8, v9});
        return v10;
    }
}

static uint8_t let_word2_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_word2_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s1 let_word2_advance_1(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).a;
        struct let_s1 v4 = ((struct let_s1){v3, p2});
        return v4;
    }
}

static struct let_s1 let_word2_run(struct let_s1 p1) {
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
