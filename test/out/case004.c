#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>

struct let_s2 {
    int64_t n;
};

struct let_s3 {
    uint8_t factorial;
    struct let_s2 sum_from_zero;
};

struct let_s1 {
    uint8_t factorial;
    uint8_t sum_to;
    struct let_s2 sum_from_zero;
    struct let_s3 answer;
};

struct let_s4 {
    int64_t n;
    int64_t acc;
};

struct let_s1 let_module_init(void);

static uint8_t let_factorial_construct(void);

static uint8_t let_sum_to_construct(void);

static struct let_s2 let_sum_to_advance_0(uint8_t p1, int64_t p2);

static struct let_s3 let_answer_construct(uint8_t p1, struct let_s2 p2);

int64_t let_factorial_entry(struct let_s1 p1, int64_t p2);

static struct let_s2 let_factorial_advance_0(uint8_t p1, int64_t p2);

static int64_t let_factorial_run(struct let_s2 p1);

int64_t let_sum_to_entry(struct let_s1 p1, int64_t p2, int64_t p3);

static struct let_s4 let_sum_to_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_sum_to_run(struct let_s4 p1);

int64_t let_answer_entry(struct let_s1 p1);

static int64_t let_answer_run(struct let_s3 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_factorial_construct();
        uint8_t v2 = let_sum_to_construct();
        uint8_t v4 = let_sum_to_construct();
        struct let_s2 v5 = let_sum_to_advance_0(v4, INT64_C(1000000));
        struct let_s3 v6 = let_answer_construct(v1, v5);
        struct let_s1 v7 = ((struct let_s1){v1, v2, v5, v6});
        return v7;
    }
}

static uint8_t let_factorial_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_sum_to_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_sum_to_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s3 let_answer_construct(uint8_t p1, struct let_s2 p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p1, p2});
        return v3;
    }
}

int64_t let_factorial_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).factorial;
        struct let_s2 v4 = let_factorial_advance_0(v3, p2);
        int64_t v5 = let_factorial_run(v4);
        return v5;
    }
}

static struct let_s2 let_factorial_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_factorial_run(struct let_s2 p1) {
    {
        int64_t b4_p1;
        int64_t b2_p1;
        int64_t b3_p1;
        int64_t v2 = (p1).n;
        bool v4 = (v2 <= INT64_C(1));
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
        uint8_t b2_v4 = let_factorial_construct();
        struct let_s2 b2_v5 = let_factorial_advance_0(b2_v4, b2_v3);
        int64_t b2_v6 = let_factorial_run(b2_v5);
        int64_t b2_v7 = ((int64_t)(((uint64_t)b2_p1) * ((uint64_t)b2_v6)));
        return b2_v7;
b3:;
        return INT64_C(1);
    }
}

int64_t let_sum_to_entry(struct let_s1 p1, int64_t p2, int64_t p3) {
    {
        uint8_t v4 = (p1).sum_to;
        struct let_s2 v5 = let_sum_to_advance_0(v4, p2);
        struct let_s4 v6 = let_sum_to_advance_1(v5, p3);
        int64_t v7 = let_sum_to_run(v6);
        return v7;
    }
}

static struct let_s4 let_sum_to_advance_1(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).n;
        struct let_s4 v4 = ((struct let_s4){v3, p2});
        return v4;
    }
}

static int64_t let_sum_to_run(struct let_s4 p1) {
    {
        int64_t b4_p1;
        int64_t b4_p2;
        int64_t b2_p1;
        int64_t b2_p2;
        int64_t b3_p1;
        int64_t b3_p2;
        int64_t v2 = (p1).n;
        int64_t v3 = (p1).acc;
        bool v5 = (v2 == INT64_C(0));
        if (v5)
        {
            b3_p1 = v2;
            b3_p2 = v3;
            goto b3;
        }
        else
        {
            b4_p1 = v2;
            b4_p2 = v3;
            goto b4;
        }
b4:;
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            goto b2;
        }
b2:;
        int64_t b2_v3 = ((int64_t)(((uint64_t)b2_p2) + ((uint64_t)b2_p1)));
        int64_t b2_v5 = ((int64_t)(((uint64_t)b2_p1) - ((uint64_t)INT64_C(1))));
        uint8_t b2_v6 = let_sum_to_construct();
        struct let_s2 b2_v7 = let_sum_to_advance_0(b2_v6, b2_v5);
        struct let_s4 b2_v8 = let_sum_to_advance_1(b2_v7, b2_v3);
        int64_t b2_v9 = let_sum_to_run(b2_v8);
        return b2_v9;
b3:;
        return b3_p2;
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
        uint8_t v2 = (p1).factorial;
        struct let_s2 v3 = (p1).sum_from_zero;
        struct let_s2 v5 = let_factorial_advance_0(v2, INT64_C(5));
        int64_t v6 = let_factorial_run(v5);
        struct let_s4 v8 = let_sum_to_advance_1(v3, INT64_C(0));
        int64_t v9 = let_sum_to_run(v8);
        int64_t v10 = ((int64_t)(((uint64_t)v6) + ((uint64_t)v9)));
        return v10;
    }
}

int main(void) { struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_answer_entry(m)); return 0; }
