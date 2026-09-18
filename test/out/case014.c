#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s2 {
    uint8_t twice;
};

struct let_s1 {
    struct let_s2 other;
    int64_t answer;
};

struct let_s3 {
    int64_t n;
};

struct let_s1 let_module_init(void);

static uint8_t let_twice_construct(void);

static struct let_s3 let_twice_advance_0(uint8_t p1, int64_t p2);

static int64_t let_twice_run(struct let_s3 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_twice_construct();
        struct let_s2 v2 = ((struct let_s2){v1});
        uint8_t v4 = let_twice_construct();
        struct let_s3 v5 = let_twice_advance_0(v4, INT64_C(21));
        int64_t v6 = let_twice_run(v5);
        struct let_s1 v7 = ((struct let_s1){v2, v6});
        return v7;
    }
}

static uint8_t let_twice_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s3 let_twice_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static int64_t let_twice_run(struct let_s3 p1) {
    {
        int64_t v2 = (p1).n;
        int64_t v4 = ((int64_t)(((uint64_t)v2) * ((uint64_t)INT64_C(2))));
        return v4;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
