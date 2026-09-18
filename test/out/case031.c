#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>

union let_u2 {
    uint8_t f0;
    uint8_t f1;
};

struct let_s2 {
    int64_t tag;
    union let_u2 payload;
};

struct let_s3 {
    uint8_t twice;
    struct let_s2 chosen;
};

struct let_s1 {
    uint8_t square;
    uint8_t inc;
    struct let_s2 chosen;
    uint8_t twice;
    struct let_s3 main;
};

struct let_s4 {
    int64_t x;
};

struct let_s5 {
    struct let_s2 f;
};

struct let_s6 {
    struct let_s2 f;
    int64_t x;
};

struct let_s7 {
    uint8_t twice;
    struct let_s2 chosen;
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_square_construct(void);

static uint8_t let_inc_construct(void);

static uint8_t let_twice_construct(void);

static struct let_s3 let_main_construct(uint8_t p1, struct let_s2 p2);

int64_t let_square_entry(struct let_s1 p1, int64_t p2);

static struct let_s4 let_square_advance_0(uint8_t p1, int64_t p2);

static int64_t let_square_run(struct let_s4 p1);

int64_t let_inc_entry(struct let_s1 p1, int64_t p2);

static struct let_s4 let_inc_advance_0(uint8_t p1, int64_t p2);

static int64_t let_inc_run(struct let_s4 p1);

int64_t let_twice_entry(struct let_s1 p1, struct let_s2 p2, int64_t p3);

static struct let_s5 let_twice_advance_0(uint8_t p1, struct let_s2 p2);

static struct let_s6 let_twice_advance_1(struct let_s5 p1, int64_t p2);

static int64_t let_twice_run(struct let_s6 p1);

int64_t let_main_entry(struct let_s1 p1, int64_t p2);

static struct let_s7 let_main_advance_0(struct let_s3 p1, int64_t p2);

static int64_t let_main_run(struct let_s7 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_square_construct();
        uint8_t v2 = let_inc_construct();
        uint8_t v3 = let_inc_construct();
        struct let_s2 v4 = ((struct let_s2){.tag = INT64_C(1), .payload = ((union let_u2){.f1 = v3})});
        uint8_t v5 = let_twice_construct();
        struct let_s3 v6 = let_main_construct(v5, v4);
        struct let_s1 v7 = ((struct let_s1){v1, v2, v4, v5, v6});
        return v7;
    }
}

static uint8_t let_square_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_inc_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_twice_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s3 let_main_construct(uint8_t p1, struct let_s2 p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p1, p2});
        return v3;
    }
}

int64_t let_square_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).square;
        struct let_s4 v4 = let_square_advance_0(v3, p2);
        int64_t v5 = let_square_run(v4);
        return v5;
    }
}

static struct let_s4 let_square_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static int64_t let_square_run(struct let_s4 p1) {
    {
        int64_t v2 = (p1).x;
        int64_t v3 = ((int64_t)(((uint64_t)v2) * ((uint64_t)v2)));
        return v3;
    }
}

int64_t let_inc_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).inc;
        struct let_s4 v4 = let_inc_advance_0(v3, p2);
        int64_t v5 = let_inc_run(v4);
        return v5;
    }
}

static struct let_s4 let_inc_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static int64_t let_inc_run(struct let_s4 p1) {
    {
        int64_t v2 = (p1).x;
        int64_t v4 = ((int64_t)(((uint64_t)v2) + ((uint64_t)INT64_C(1))));
        return v4;
    }
}

int64_t let_twice_entry(struct let_s1 p1, struct let_s2 p2, int64_t p3) {
    {
        uint8_t v4 = (p1).twice;
        struct let_s5 v5 = let_twice_advance_0(v4, p2);
        struct let_s6 v6 = let_twice_advance_1(v5, p3);
        int64_t v7 = let_twice_run(v6);
        return v7;
    }
}

static struct let_s5 let_twice_advance_0(uint8_t p1, struct let_s2 p2) {
    {
        struct let_s5 v3 = ((struct let_s5){p2});
        return v3;
    }
}

static struct let_s6 let_twice_advance_1(struct let_s5 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).f;
        struct let_s6 v4 = ((struct let_s6){v3, p2});
        return v4;
    }
}

static int64_t let_twice_run(struct let_s6 p1) {
    {
        struct let_s2 b5_p1;
        struct let_s2 b5_p2;
        int64_t b5_p3;
        struct let_s2 b6_p1;
        struct let_s2 b6_p2;
        int64_t b6_p3;
        struct let_s2 b2_p1;
        struct let_s2 b2_p2;
        int64_t b2_p3;
        struct let_s2 b4_p1;
        struct let_s2 b4_p2;
        int64_t b4_p3;
        struct let_s2 b3_p1;
        struct let_s2 b3_p2;
        int64_t b3_p3;
        struct let_s2 v2 = (p1).f;
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
        uint8_t b4_v4 = ((b4_p1).payload).f1;
        struct let_s4 b4_v5 = let_inc_advance_0(b4_v4, b4_p3);
        int64_t b4_v6 = let_inc_run(b4_v5);
        struct let_s4 b4_v7 = let_inc_advance_0(b4_v4, b4_v6);
        int64_t b4_v8 = let_inc_run(b4_v7);
        return b4_v8;
b3:;
        uint8_t b3_v4 = ((b3_p1).payload).f0;
        struct let_s4 b3_v5 = let_square_advance_0(b3_v4, b3_p3);
        int64_t b3_v6 = let_square_run(b3_v5);
        struct let_s4 b3_v7 = let_square_advance_0(b3_v4, b3_v6);
        int64_t b3_v8 = let_square_run(b3_v7);
        return b3_v8;
    }
}

int64_t let_main_entry(struct let_s1 p1, int64_t p2) {
    {
        struct let_s3 v3 = (p1).main;
        struct let_s7 v4 = let_main_advance_0(v3, p2);
        int64_t v5 = let_main_run(v4);
        return v5;
    }
}

static struct let_s7 let_main_advance_0(struct let_s3 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).twice;
        struct let_s2 v4 = (p1).chosen;
        struct let_s7 v5 = ((struct let_s7){v3, v4, p2});
        return v5;
    }
}

static int64_t let_main_run(struct let_s7 p1) {
    {
        uint8_t v2 = (p1).twice;
        struct let_s2 v3 = (p1).chosen;
        int64_t v4 = (p1).x;
        struct let_s5 v5 = let_twice_advance_0(v2, v3);
        struct let_s6 v6 = let_twice_advance_1(v5, v4);
        int64_t v7 = let_twice_run(v6);
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_main_entry(m, 3)); return 0; }
