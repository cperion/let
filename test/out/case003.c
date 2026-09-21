#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

struct let_s2 {
    uint8_t ok;
    uint8_t bad;
};

struct let_s3 {
    struct let_s2 divide;
};

struct let_s1 {
    uint8_t success;
    uint8_t failure;
    uint8_t checked_divide;
    struct let_s2 divide;
    struct let_s3 answer;
};

struct let_s4 {
    uint8_t ok;
};

struct let_s5 {
    int64_t value;
};

struct let_s6 {
    int64_t code;
};

struct let_s7 {
    uint8_t ok;
    uint8_t bad;
    int64_t numerator;
};

struct let_s8 {
    uint8_t ok;
    uint8_t bad;
    int64_t numerator;
    int64_t denominator;
};

struct let_s1 let_module_init(void);

static uint8_t let_success_construct(void);

static uint8_t let_failure_construct(void);

static uint8_t let_checked_divide_construct(void);

static struct let_s4 let_checked_divide_advance_0(uint8_t p1, uint8_t p2);

static struct let_s2 let_checked_divide_advance_1(struct let_s4 p1, uint8_t p2);

static struct let_s3 let_answer_construct(struct let_s2 p1);

int64_t let_success_entry(struct let_s1 p1, int64_t p2);

static struct let_s5 let_success_advance_0(uint8_t p1, int64_t p2);

static int64_t let_success_run(struct let_s5 p1);

int64_t let_failure_entry(struct let_s1 p1, int64_t p2);

static struct let_s6 let_failure_advance_0(uint8_t p1, int64_t p2);

static int64_t let_failure_run(struct let_s6 p1);

int64_t let_checked_divide_entry(struct let_s1 p1, uint8_t p2, uint8_t p3, int64_t p4, int64_t p5);

static struct let_s7 let_checked_divide_advance_2(struct let_s2 p1, int64_t p2);

static struct let_s8 let_checked_divide_advance_3(struct let_s7 p1, int64_t p2);

static int64_t let_checked_divide_run(struct let_s8 p1);

int64_t let_answer_entry(struct let_s1 p1);

static int64_t let_answer_run(struct let_s3 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_success_construct();
        uint8_t v2 = let_failure_construct();
        uint8_t v3 = let_checked_divide_construct();
        uint8_t v4 = let_checked_divide_construct();
        struct let_s4 v5 = let_checked_divide_advance_0(v4, v1);
        struct let_s2 v6 = let_checked_divide_advance_1(v5, v2);
        struct let_s3 v7 = let_answer_construct(v6);
        struct let_s1 v8 = ((struct let_s1){v1, v2, v3, v6, v7});
        return v8;
    }
}

static uint8_t let_success_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_failure_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_checked_divide_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s4 let_checked_divide_advance_0(uint8_t p1, uint8_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static struct let_s2 let_checked_divide_advance_1(struct let_s4 p1, uint8_t p2) {
    {
        uint8_t v3 = (p1).ok;
        struct let_s2 v4 = ((struct let_s2){v3, p2});
        return v4;
    }
}

static struct let_s3 let_answer_construct(struct let_s2 p1) {
    {
        struct let_s3 v2 = ((struct let_s3){p1});
        return v2;
    }
}

int64_t let_success_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).success;
        struct let_s5 v4 = let_success_advance_0(v3, p2);
        int64_t v5 = let_success_run(v4);
        return v5;
    }
}

static struct let_s5 let_success_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s5 v3 = ((struct let_s5){p2});
        return v3;
    }
}

static int64_t let_success_run(struct let_s5 p1) {
    {
        int64_t v2 = (p1).value;
        return v2;
    }
}

int64_t let_failure_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).failure;
        struct let_s6 v4 = let_failure_advance_0(v3, p2);
        int64_t v5 = let_failure_run(v4);
        return v5;
    }
}

static struct let_s6 let_failure_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s6 v3 = ((struct let_s6){p2});
        return v3;
    }
}

static int64_t let_failure_run(struct let_s6 p1) {
    {
        int64_t v2 = (p1).code;
        int64_t v4 = ((int64_t)(((uint64_t)INT64_C(0)) - ((uint64_t)v2)));
        return v4;
    }
}

int64_t let_checked_divide_entry(struct let_s1 p1, uint8_t p2, uint8_t p3, int64_t p4, int64_t p5) {
    {
        uint8_t v6 = (p1).checked_divide;
        struct let_s4 v7 = let_checked_divide_advance_0(v6, p2);
        struct let_s2 v8 = let_checked_divide_advance_1(v7, p3);
        struct let_s7 v9 = let_checked_divide_advance_2(v8, p4);
        struct let_s8 v10 = let_checked_divide_advance_3(v9, p5);
        int64_t v11 = let_checked_divide_run(v10);
        return v11;
    }
}

static struct let_s7 let_checked_divide_advance_2(struct let_s2 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).ok;
        uint8_t v4 = (p1).bad;
        struct let_s7 v5 = ((struct let_s7){v3, v4, p2});
        return v5;
    }
}

static struct let_s8 let_checked_divide_advance_3(struct let_s7 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).ok;
        uint8_t v4 = (p1).bad;
        int64_t v5 = (p1).numerator;
        struct let_s8 v6 = ((struct let_s8){v3, v4, v5, p2});
        return v6;
    }
}

static int64_t let_checked_divide_run(struct let_s8 p1) {
    {
        uint8_t b4_p1;
        uint8_t b4_p2;
        int64_t b4_p3;
        int64_t b4_p4;
        uint8_t b2_p1;
        uint8_t b2_p2;
        int64_t b2_p3;
        int64_t b2_p4;
        uint8_t b3_p1;
        uint8_t b3_p2;
        int64_t b3_p3;
        int64_t b3_p4;
        uint8_t v2 = (p1).ok;
        uint8_t v3 = (p1).bad;
        int64_t v4 = (p1).numerator;
        int64_t v5 = (p1).denominator;
        bool v7 = (v5 == INT64_C(0));
        if (v7)
        {
            b3_p1 = v2;
            b3_p2 = v3;
            b3_p3 = v4;
            b3_p4 = v5;
            goto b3;
        }
        else
        {
            b4_p1 = v2;
            b4_p2 = v3;
            b4_p3 = v4;
            b4_p4 = v5;
            goto b4;
        }
b4:;
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            b2_p3 = b4_p3;
            b2_p4 = b4_p4;
            goto b2;
        }
b2:;
        int64_t b2_v5 = ((b2_p4 == INT64_C(0)) ? (abort(), INT64_C(0)) : ((b2_p4 == (-INT64_C(1))) ? ((int64_t)(((uint64_t)INT64_C(0)) - ((uint64_t)b2_p3))) : (b2_p3 / b2_p4)));
        struct let_s5 b2_v6 = let_success_advance_0(b2_p1, b2_v5);
        int64_t b2_v7 = let_success_run(b2_v6);
        return b2_v7;
b3:;
        struct let_s6 b3_v6 = let_failure_advance_0(b3_p2, INT64_C(1));
        int64_t b3_v7 = let_failure_run(b3_v6);
        return b3_v7;
    }
}

int64_t let_answer_entry(struct let_s1 p1) {
    {
        struct let_s3 v2 = (p1).answer;
        int64_t v3 = let_answer_run(v2);
        return v3;
    }
}

static int64_t let_answer_run(struct let_s3 p1) {
    {
        struct let_s2 v2 = (p1).divide;
        struct let_s7 v5 = let_checked_divide_advance_2(v2, INT64_C(84));
        struct let_s8 v6 = let_checked_divide_advance_3(v5, INT64_C(2));
        int64_t v7 = let_checked_divide_run(v6);
        return v7;
    }
}

int main(void) { struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_answer_entry(m)); return 0; }
