#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>

struct let_s2 {
    int64_t x;
};

struct let_s3 {
    struct let_s2 twice;
    uint8_t fibonacci;
};

struct let_s1 {
    uint8_t fibonacci;
    uint8_t multiply;
    struct let_s2 twice;
    struct let_s3 answer;
};

struct let_s4 {
    int64_t n;
};

struct let_s5 {
    int64_t x;
    int64_t y;
};

struct let_s1 let_module_init(void);

static uint8_t let_fibonacci_construct(void);

static uint8_t let_multiply_construct(void);

static struct let_s2 let_multiply_advance_0(uint8_t p1, int64_t p2);

static struct let_s3 let_answer_construct(struct let_s2 p1, uint8_t p2);

int64_t let_fibonacci_entry(struct let_s1 p1, int64_t p2);

static struct let_s4 let_fibonacci_advance_0(uint8_t p1, int64_t p2);

static int64_t let_fibonacci_run(struct let_s4 p1);

int64_t let_multiply_entry(struct let_s1 p1, int64_t p2, int64_t p3);

static struct let_s5 let_multiply_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_multiply_run(struct let_s5 p1);

int64_t let_answer_entry(struct let_s1 p1);

static int64_t let_answer_run(struct let_s3 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_fibonacci_construct();
        uint8_t v2 = let_multiply_construct();
        uint8_t v4 = let_multiply_construct();
        struct let_s2 v5 = let_multiply_advance_0(v4, INT64_C(2));
        struct let_s3 v6 = let_answer_construct(v5, v1);
        struct let_s1 v7 = ((struct let_s1){v1, v2, v5, v6});
        return v7;
    }
}

static uint8_t let_fibonacci_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_multiply_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_multiply_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s3 let_answer_construct(struct let_s2 p1, uint8_t p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p1, p2});
        return v3;
    }
}

int64_t let_fibonacci_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).fibonacci;
        struct let_s4 v4 = let_fibonacci_advance_0(v3, p2);
        int64_t v5 = let_fibonacci_run(v4);
        return v5;
    }
}

static struct let_s4 let_fibonacci_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static int64_t let_fibonacci_run(struct let_s4 p1) {
    {
        int64_t b2_p1;
        int64_t* b2_p2;
        int64_t* b2_p3;
        int64_t* b2_p4;
        int64_t b3_p1;
        int64_t* b3_p2;
        int64_t* b3_p3;
        int64_t* b3_p4;
        int64_t b4_p1;
        int64_t* b4_p2;
        int64_t* b4_p3;
        int64_t* b4_p4;
        int64_t v2 = (p1).n;
        int64_t v4 = INT64_C(0);
        int64_t v6 = INT64_C(0);
        int64_t v8 = INT64_C(1);
        {
            b2_p1 = v2;
            b2_p2 = (&v4);
            b2_p3 = (&v6);
            b2_p4 = (&v8);
            goto b2;
        }
b2:;
        int64_t b2_v5 = (*b2_p2);
        bool b2_v6 = (b2_v5 < b2_p1);
        if (b2_v6)
        {
            b4_p1 = b2_p1;
            b4_p2 = b2_p2;
            b4_p3 = b2_p3;
            b4_p4 = b2_p4;
            goto b4;
        }
        else
        {
            b3_p1 = b2_p1;
            b3_p2 = b2_p2;
            b3_p3 = b2_p3;
            b3_p4 = b2_p4;
            goto b3;
        }
b3:;
        int64_t b3_v5 = (*b3_p3);
        return b3_v5;
b4:;
        int64_t b4_v5 = (*b4_p3);
        int64_t b4_v6 = (*b4_p4);
        int64_t b4_v7 = ((int64_t)(((uint64_t)b4_v5) + ((uint64_t)b4_v6)));
        int64_t b4_v8 = (*b4_p4);
        (*b4_p3) = b4_v8;
        (*b4_p4) = b4_v7;
        int64_t b4_v11 = (*b4_p2);
        int64_t b4_v13 = ((int64_t)(((uint64_t)b4_v11) + ((uint64_t)INT64_C(1))));
        (*b4_p2) = b4_v13;
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            b2_p3 = b4_p3;
            b2_p4 = b4_p4;
            goto b2;
        }
    }
}

int64_t let_multiply_entry(struct let_s1 p1, int64_t p2, int64_t p3) {
    {
        uint8_t v4 = (p1).multiply;
        struct let_s2 v5 = let_multiply_advance_0(v4, p2);
        struct let_s5 v6 = let_multiply_advance_1(v5, p3);
        int64_t v7 = let_multiply_run(v6);
        return v7;
    }
}

static struct let_s5 let_multiply_advance_1(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).x;
        struct let_s5 v4 = ((struct let_s5){v3, p2});
        return v4;
    }
}

static int64_t let_multiply_run(struct let_s5 p1) {
    {
        int64_t v2 = (p1).x;
        int64_t v3 = (p1).y;
        int64_t v4 = ((int64_t)(((uint64_t)v2) * ((uint64_t)v3)));
        return v4;
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
        struct let_s2 v2 = (p1).twice;
        uint8_t v3 = (p1).fibonacci;
        struct let_s5 v5 = let_multiply_advance_1(v2, INT64_C(21));
        int64_t v6 = let_multiply_run(v5);
        struct let_s4 v8 = let_fibonacci_advance_0(v3, INT64_C(10));
        int64_t v9 = let_fibonacci_run(v8);
        int64_t v10 = ((int64_t)(((uint64_t)v6) + ((uint64_t)v9)));
        return v10;
    }
}

int main(void) { struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)let_answer_entry(m)); return 0; }
