#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

struct let_s1 {
    uint8_t f;
    int64_t a;
    int64_t b;
};

struct let_s4 {
    int64_t x;
};

union let_u3 {
    int64_t f0;
    struct let_s4 f1;
};

struct let_s3 {
    int64_t tag;
    union let_u3 payload;
};

struct let_s2 {
    struct let_s3 v;
};

struct let_s1 let_module_init(void);

static uint8_t let_f_construct(void);

static struct let_s2 let_f_advance_0(uint8_t p1, struct let_s3 p2);

static int64_t let_f_run(struct let_s2 p1);

int64_t let_f_entry(struct let_s1 p1, struct let_s3 p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_f_construct();
        struct let_s3 v3 = ((struct let_s3){.tag = INT64_C(0), .payload = ((union let_u3){.f0 = INT64_C(7)})});
        uint8_t v4 = let_f_construct();
        struct let_s2 v5 = let_f_advance_0(v4, v3);
        int64_t v6 = let_f_run(v5);
        struct let_s3 v9 = ((struct let_s3){.tag = INT64_C(1), .payload = ((union let_u3){.f1 = ((struct let_s4){.x = INT64_C(3)})})});
        uint8_t v10 = let_f_construct();
        struct let_s2 v11 = let_f_advance_0(v10, v9);
        int64_t v12 = let_f_run(v11);
        struct let_s1 v13 = ((struct let_s1){v1, v6, v12});
        return v13;
    }
}

static uint8_t let_f_construct(void) {
    {
        return INT64_C(0);
    }
}

static struct let_s2 let_f_advance_0(uint8_t p1, struct let_s3 p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_f_run(struct let_s2 p1) {
    {
        struct let_s3 b5_p1;
        struct let_s3 b5_p2;
        struct let_s3 b6_p1;
        struct let_s3 b6_p2;
        struct let_s3 b2_p1;
        struct let_s3 b2_p2;
        struct let_s3 b4_p1;
        struct let_s3 b4_p2;
        struct let_s3 b3_p1;
        struct let_s3 b3_p2;
        struct let_s3 v2 = (p1).v;
        {
            b5_p1 = v2;
            b5_p2 = v2;
            goto b5;
        }
b5:;
        int64_t b5_v3 = (b5_p1).tag;
        bool b5_v5 = (b5_v3 == INT64_C(1));
        if (b5_v5)
        {
            b3_p1 = b5_p1;
            b3_p2 = b5_p2;
            goto b3;
        }
        else
        {
            b6_p1 = b5_p1;
            b6_p2 = b5_p2;
            goto b6;
        }
b6:;
        int64_t b6_v3 = (b6_p1).tag;
        bool b6_v5 = (b6_v3 == INT64_C(0));
        if (b6_v5)
        {
            b4_p1 = b6_p1;
            b4_p2 = b6_p2;
            goto b4;
        }
        else
        {
            b2_p1 = b6_p1;
            b2_p2 = b6_p2;
            goto b2;
        }
b2:;
        return INT64_C(0);
b4:;
        int64_t b4_v3 = ((b4_p1).payload).f0;
        return b4_v3;
b3:;
        struct let_s4 b3_v3 = ((b3_p1).payload).f1;
        int64_t b3_v4 = (b3_v3).x;
        return b3_v4;
    }
}

int64_t let_f_entry(struct let_s1 p1, struct let_s3 p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s2 v4 = let_f_advance_0(v3, p2);
        int64_t v5 = let_f_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init(); printf("%lld %lld\n", (long long)m.a, (long long)m.b); return 0; }
