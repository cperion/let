#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>

struct let_s2 {
    int64_t a;
};

struct let_s1 {
    uint8_t add;
    uint8_t mul;
    struct let_s2 add2;
    struct let_s2 mul3;
    uint8_t apply;
    int64_t answer;
};

union let_u4 {
    struct let_s2 f0;
    struct let_s2 f1;
};

struct let_s4 {
    int64_t tag;
    union let_u4 payload;
};

struct let_s3 {
    struct let_s4 f;
};

struct let_s5 {
    struct let_s4 f;
    int64_t x;
};

struct let_s6 {
    int64_t a;
    int64_t b;
};

struct let_s1 let_module_init(void);

static uint8_t let_add_construct(void);

static uint8_t let_mul_construct(void);

static struct let_s2 let_add_advance_0(uint8_t p1, int64_t p2);

static struct let_s2 let_mul_advance_0(uint8_t p1, int64_t p2);

static uint8_t let_apply_construct(void);

static struct let_s3 let_apply_advance_0(uint8_t p1, struct let_s4 p2);

static struct let_s5 let_apply_advance_1(struct let_s3 p1, int64_t p2);

static int64_t let_apply_run(struct let_s5 p1);

static struct let_s6 let_add_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_add_run(struct let_s6 p1);

static struct let_s6 let_mul_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_mul_run(struct let_s6 p1);

int64_t let_add_entry(struct let_s1 p1, int64_t p2, int64_t p3);

int64_t let_mul_entry(struct let_s1 p1, int64_t p2, int64_t p3);

int64_t let_apply_entry(struct let_s1 p1, struct let_s4 p2, int64_t p3);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_add_construct();
        uint8_t v2 = let_mul_construct();
        uint8_t v4 = let_add_construct();
        struct let_s2 v5 = let_add_advance_0(v4, INT64_C(2));
        uint8_t v7 = let_mul_construct();
        struct let_s2 v8 = let_mul_advance_0(v7, INT64_C(3));
        uint8_t v9 = let_apply_construct();
        struct let_s4 v11 = ((struct let_s4){.tag = INT64_C(0), .payload = ((union let_u4){.f0 = v5})});
        uint8_t v12 = let_apply_construct();
        struct let_s3 v13 = let_apply_advance_0(v12, v11);
        struct let_s5 v14 = let_apply_advance_1(v13, INT64_C(5));
        int64_t v15 = let_apply_run(v14);
        struct let_s4 v17 = ((struct let_s4){.tag = INT64_C(1), .payload = ((union let_u4){.f1 = v8})});
        uint8_t v18 = let_apply_construct();
        struct let_s3 v19 = let_apply_advance_0(v18, v17);
        struct let_s5 v20 = let_apply_advance_1(v19, INT64_C(5));
        int64_t v21 = let_apply_run(v20);
        int64_t v22 = ((int64_t)(((uint64_t)v15) + ((uint64_t)v21)));
        struct let_s1 v23 = ((struct let_s1){v1, v2, v5, v8, v9, v22});
        return v23;
    }
}

static uint8_t let_add_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_mul_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_add_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s2 let_mul_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static uint8_t let_apply_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s3 let_apply_advance_0(uint8_t p1, struct let_s4 p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static struct let_s5 let_apply_advance_1(struct let_s3 p1, int64_t p2) {
    {
        struct let_s4 v3 = (p1).f;
        struct let_s5 v4 = ((struct let_s5){v3, p2});
        return v4;
    }
}

static int64_t let_apply_run(struct let_s5 p1) {
    {
        struct let_s4 b5_p1;
        struct let_s4 b5_p2;
        int64_t b5_p3;
        struct let_s4 b6_p1;
        struct let_s4 b6_p2;
        int64_t b6_p3;
        struct let_s4 b2_p1;
        struct let_s4 b2_p2;
        int64_t b2_p3;
        struct let_s4 b4_p1;
        struct let_s4 b4_p2;
        int64_t b4_p3;
        struct let_s4 b3_p1;
        struct let_s4 b3_p2;
        int64_t b3_p3;
        struct let_s4 v2 = (p1).f;
        int64_t v3 = (p1).x;
        {
            b5_p1 = v2;
            b5_p2 = v2;
            b5_p3 = v3;
            goto b5;
        }
b5:;
        int64_t b5_v4 = (b5_p1).tag;
        bool b5_v6 = (b5_v4 == INT64_C(0));
        if (b5_v6)
        {
            b3_p1 = b5_p1;
            b3_p2 = b5_p2;
            b3_p3 = b5_p3;
            goto b3;
        }
        else
        {
            b6_p1 = b5_p1;
            b6_p2 = b5_p2;
            b6_p3 = b5_p3;
            goto b6;
        }
b6:;
        int64_t b6_v4 = (b6_p1).tag;
        bool b6_v6 = (b6_v4 == INT64_C(1));
        if (b6_v6)
        {
            b4_p1 = b6_p1;
            b4_p2 = b6_p2;
            b4_p3 = b6_p3;
            goto b4;
        }
        else
        {
            b2_p1 = b6_p1;
            b2_p2 = b6_p2;
            b2_p3 = b6_p3;
            goto b2;
        }
b2:;
        return INT64_C(0);
b4:;
        struct let_s2 b4_v4 = ((b4_p1).payload).f1;
        struct let_s6 b4_v5 = let_mul_advance_1(b4_v4, b4_p3);
        int64_t b4_v6 = let_mul_run(b4_v5);
        return b4_v6;
b3:;
        struct let_s2 b3_v4 = ((b3_p1).payload).f0;
        struct let_s6 b3_v5 = let_add_advance_1(b3_v4, b3_p3);
        int64_t b3_v6 = let_add_run(b3_v5);
        return b3_v6;
    }
}

static struct let_s6 let_add_advance_1(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).a;
        struct let_s6 v4 = ((struct let_s6){v3, p2});
        return v4;
    }
}

static int64_t let_add_run(struct let_s6 p1) {
    {
        int64_t v2 = (p1).a;
        int64_t v3 = (p1).b;
        int64_t v4 = ((int64_t)(((uint64_t)v2) + ((uint64_t)v3)));
        return v4;
    }
}

static struct let_s6 let_mul_advance_1(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).a;
        struct let_s6 v4 = ((struct let_s6){v3, p2});
        return v4;
    }
}

static int64_t let_mul_run(struct let_s6 p1) {
    {
        int64_t v2 = (p1).a;
        int64_t v3 = (p1).b;
        int64_t v4 = ((int64_t)(((uint64_t)v2) * ((uint64_t)v3)));
        return v4;
    }
}

int64_t let_add_entry(struct let_s1 p1, int64_t p2, int64_t p3) {
    {
        uint8_t v4 = (p1).add;
        struct let_s2 v5 = let_add_advance_0(v4, p2);
        struct let_s6 v6 = let_add_advance_1(v5, p3);
        int64_t v7 = let_add_run(v6);
        return v7;
    }
}

int64_t let_mul_entry(struct let_s1 p1, int64_t p2, int64_t p3) {
    {
        uint8_t v4 = (p1).mul;
        struct let_s2 v5 = let_mul_advance_0(v4, p2);
        struct let_s6 v6 = let_mul_advance_1(v5, p3);
        int64_t v7 = let_mul_run(v6);
        return v7;
    }
}

int64_t let_apply_entry(struct let_s1 p1, struct let_s4 p2, int64_t p3) {
    {
        uint8_t v4 = (p1).apply;
        struct let_s3 v5 = let_apply_advance_0(v4, p2);
        struct let_s5 v6 = let_apply_advance_1(v5, p3);
        int64_t v7 = let_apply_run(v6);
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
