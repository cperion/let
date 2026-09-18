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

struct let_s3 {
    uint8_t f;
};

struct let_s4 {
    uint8_t f;
    int64_t k;
};

struct let_s1 let_module_init(void);

static uint8_t let_f_construct(void);

static struct let_s2 let_f_advance_0(uint8_t p1, int64_t p2);

static int64_t let_f_run(struct let_s2 p1);

static struct let_s3 let_g_construct(uint8_t p1);

static struct let_s4 let_g_advance_0(struct let_s3 p1, int64_t p2);

static int64_t let_g_run(struct let_s4 p1);

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
        uint8_t b4_p1;
        int64_t b4_p2;
        struct let_s3 b4_p3;
        uint8_t b2_p1;
        int64_t b2_p2;
        struct let_s3 b2_p3;
        uint8_t b3_p1;
        int64_t b3_p2;
        struct let_s3 b3_p3;
        int64_t v2 = (p1).n;
        uint8_t v3 = let_f_construct();
        struct let_s3 v4 = let_g_construct(v3);
        bool v6 = (v2 == INT64_C(0));
        if (v6)
        {
            b3_p1 = v3;
            b3_p2 = v2;
            b3_p3 = v4;
            goto b3;
        }
        else
        {
            b4_p1 = v3;
            b4_p2 = v2;
            b4_p3 = v4;
            goto b4;
        }
b4:;
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            b2_p3 = b4_p3;
            goto b2;
        }
b2:;
        int64_t b2_v6 = ((int64_t)(((uint64_t)b2_p2) - ((uint64_t)INT64_C(1))));
        struct let_s3 b2_v7 = let_g_construct(b2_p1);
        struct let_s4 b2_v8 = let_g_advance_0(b2_v7, b2_v6);
        int64_t b2_v9 = let_g_run(b2_v8);
        int64_t b2_v10 = ((int64_t)(((uint64_t)INT64_C(1)) + ((uint64_t)b2_v9)));
        return b2_v10;
b3:;
        return INT64_C(0);
    }
}

static struct let_s3 let_g_construct(uint8_t p1) {
    {
        struct let_s3 v2 = ((struct let_s3){p1});
        return v2;
    }
}

static struct let_s4 let_g_advance_0(struct let_s3 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s4 v4 = ((struct let_s4){v3, p2});
        return v4;
    }
}

static int64_t let_g_run(struct let_s4 p1) {
    {
        uint8_t v2 = (p1).f;
        int64_t v3 = (p1).k;
        struct let_s2 v4 = let_f_advance_0(v2, v3);
        int64_t v5 = let_f_run(v4);
        return v5;
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

