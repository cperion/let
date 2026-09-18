#include <stdint.h>
#include <stdbool.h>

struct let_s1 {
    uint8_t fact;
    int64_t answer;
};

struct let_s2 {
    int64_t n;
};

struct let_s1 let_module_init(void);

static uint8_t let_fact_construct(void);

static struct let_s2 let_fact_advance_0(uint8_t p1, int64_t p2);

static int64_t let_fact_run(struct let_s2 p1);

int64_t let_fact_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_fact_construct();
        uint8_t v3 = let_fact_construct();
        struct let_s2 v4 = let_fact_advance_0(v3, INT64_C(5));
        int64_t v5 = let_fact_run(v4);
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
    }
}

static uint8_t let_fact_construct(void) {
    {
        return INT64_C(0);
    }
}

static struct let_s2 let_fact_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_fact_run(struct let_s2 p1) {
    {
        int64_t b4_p1;
        int64_t b2_p1;
        int64_t b3_p1;
        int64_t v2 = (p1).n;
        bool v4 = (v2 == INT64_C(0));
        if (v4)
        {
            b3_p1 = v2;
            goto b3;
        }
        else
        {
            b4_p1 = v2;
            goto b4;
        }
b4:;
        {
            b2_p1 = b4_p1;
            goto b2;
        }
b2:;
        int64_t b2_v3 = ((int64_t)(((uint64_t)b2_p1) - ((uint64_t)INT64_C(1))));
        uint8_t b2_v4 = let_fact_construct();
        struct let_s2 b2_v5 = let_fact_advance_0(b2_v4, b2_v3);
        int64_t b2_v6 = let_fact_run(b2_v5);
        int64_t b2_v7 = ((int64_t)(((uint64_t)b2_p1) * ((uint64_t)b2_v6)));
        return b2_v7;
b3:;
        return INT64_C(1);
    }
}

int64_t let_fact_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).fact;
        struct let_s2 v4 = let_fact_advance_0(v3, p2);
        int64_t v5 = let_fact_run(v4);
        return v5;
    }
}

int main(void){ printf("%lld\n", (long long)let_module_init().answer); return 0; }
