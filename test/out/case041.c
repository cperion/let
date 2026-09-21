#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    int64_t answer;
    uint8_t id_5;
};

struct let_s2 {
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_id_5_construct(void);

static struct let_s2 let_id_5_advance_0(uint8_t p1, int64_t p2);

static int64_t let_id_5_run(struct let_s2 p1);

int64_t let_id_5_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v2 = let_id_5_construct();
        struct let_s2 v3 = let_id_5_advance_0(v2, INT64_C(42));
        int64_t v4 = let_id_5_run(v3);
        uint8_t v5 = let_id_5_construct();
        struct let_s1 v6 = ((struct let_s1){v4, v5});
        return v6;
    }
}

static uint8_t let_id_5_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_id_5_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_id_5_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).x;
        return v2;
    }
}

int64_t let_id_5_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).id_5;
        struct let_s2 v4 = let_id_5_advance_0(v3, p2);
        int64_t v5 = let_id_5_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
