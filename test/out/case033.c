#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    uint8_t twice;
    int64_t answer;
};

struct let_s2 {
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_twice_construct(void);

static struct let_s2 let_twice_advance_0(uint8_t p1, int64_t p2);

static int64_t let_twice_run(struct let_s2 p1);

int64_t let_twice_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_twice_construct();
        uint8_t v3 = let_twice_construct();
        struct let_s2 v4 = let_twice_advance_0(v3, INT64_C(21));
        int64_t v5 = let_twice_run(v4);
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
    }
}

static uint8_t let_twice_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_twice_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_twice_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).x;
        int64_t v4 = ((int64_t)(((uint64_t)v2) * ((uint64_t)INT64_C(2))));
        return v4;
    }
}

int64_t let_twice_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).twice;
        struct let_s2 v4 = let_twice_advance_0(v3, p2);
        int64_t v5 = let_twice_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
