#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

struct let_s1 {
    uint8_t f;
    int64_t a;
};

struct let_s2 {
    int64_t n;
};

struct let_s1 let_module_init(void);

static uint8_t let_f_construct(void);

static struct let_s2 let_f_advance_0(uint8_t p1, int64_t p2);

static int64_t let_f_run(struct let_s2 p1);

int64_t let_f_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_f_construct();
        uint8_t v3 = let_f_construct();
        struct let_s2 v4 = let_f_advance_0(v3, INT64_C(3));
        int64_t v5 = let_f_run(v4);
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
    }
}

static uint8_t let_f_construct(void) {
    {
        return INT64_C(0);
    }
}

static struct let_s2 let_f_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_f_run(struct let_s2 p1) {
    {
        int64_t b4_p1;
        int64_t b4_p2;
        int64_t b2_p1;
        int64_t b2_p2;
        int64_t b3_p1;
        int64_t b3_p2;
        int64_t v2 = (p1).n;
        {
            b4_p1 = v2;
            b4_p2 = v2;
            goto b4;
        }
b4:;
        bool b4_v4 = (b4_p1 == INT64_C(0));
        if (b4_v4)
        {
            b3_p1 = b4_p1;
            b3_p2 = b4_p2;
            goto b3;
        }
        else
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            goto b2;
        }
b2:;
        int64_t b2_v5 = ((int64_t)(((uint64_t)b2_p2) - ((uint64_t)INT64_C(1))));
        uint8_t b2_v6 = let_f_construct();
        struct let_s2 b2_v7 = let_f_advance_0(b2_v6, b2_v5);
        int64_t b2_v8 = let_f_run(b2_v7);
        int64_t b2_v9 = ((int64_t)(((uint64_t)INT64_C(1)) + ((uint64_t)b2_v8)));
        return b2_v9;
b3:;
        return INT64_C(0);
    }
}

int64_t let_f_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s2 v4 = let_f_advance_0(v3, p2);
        int64_t v5 = let_f_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.a);
    return 0; }

