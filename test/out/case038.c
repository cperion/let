#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s2 {
    uint8_t bump;
    uint8_t fold;
};

struct let_s1 {
    uint8_t inc1;
    uint8_t dbl;
    struct let_s2 dict;
    int64_t answer;
    uint8_t use_15;
};

struct let_s3 {
    struct let_s2 d;
};

struct let_s4 {
    struct let_s2 d;
    int64_t x;
};

struct let_s5 {
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_inc1_construct(void);

static uint8_t let_dbl_construct(void);

static uint8_t let_use_15_construct(void);

static struct let_s3 let_use_15_advance_0(uint8_t p1, struct let_s2 p2);

static struct let_s4 let_use_15_advance_1(struct let_s3 p1, int64_t p2);

static int64_t let_use_15_run(struct let_s4 p1);

static struct let_s5 let_inc1_advance_0(uint8_t p1, int64_t p2);

static int64_t let_inc1_run(struct let_s5 p1);

static struct let_s5 let_dbl_advance_0(uint8_t p1, int64_t p2);

static int64_t let_dbl_run(struct let_s5 p1);

int64_t let_inc1_entry(struct let_s1 p1, int64_t p2);

int64_t let_dbl_entry(struct let_s1 p1, int64_t p2);

int64_t let_use_15_entry(struct let_s1 p1, struct let_s2 p2, int64_t p3);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_inc1_construct();
        uint8_t v2 = let_dbl_construct();
        uint8_t v3 = let_inc1_construct();
        uint8_t v4 = let_dbl_construct();
        struct let_s2 v5 = ((struct let_s2){v3, v4});
        uint8_t v7 = let_use_15_construct();
        struct let_s3 v8 = let_use_15_advance_0(v7, v5);
        struct let_s4 v9 = let_use_15_advance_1(v8, INT64_C(21));
        int64_t v10 = let_use_15_run(v9);
        uint8_t v11 = let_use_15_construct();
        struct let_s1 v12 = ((struct let_s1){v1, v2, v5, v10, v11});
        return v12;
    }
}

static uint8_t let_inc1_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_dbl_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_use_15_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s3 let_use_15_advance_0(uint8_t p1, struct let_s2 p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static struct let_s4 let_use_15_advance_1(struct let_s3 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).d;
        struct let_s4 v4 = ((struct let_s4){v3, p2});
        return v4;
    }
}

static int64_t let_use_15_run(struct let_s4 p1) {
    {
        int64_t v3 = (p1).x;
        uint8_t v4 = let_inc1_construct();
        struct let_s5 v5 = let_inc1_advance_0(v4, v3);
        int64_t v6 = let_inc1_run(v5);
        uint8_t v7 = let_dbl_construct();
        struct let_s5 v8 = let_dbl_advance_0(v7, v6);
        int64_t v9 = let_dbl_run(v8);
        return v9;
    }
}

static struct let_s5 let_inc1_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s5 v3 = ((struct let_s5){p2});
        return v3;
    }
}

static int64_t let_inc1_run(struct let_s5 p1) {
    {
        int64_t v2 = (p1).x;
        int64_t v4 = ((int64_t)(((uint64_t)v2) + ((uint64_t)INT64_C(1))));
        return v4;
    }
}

static struct let_s5 let_dbl_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s5 v3 = ((struct let_s5){p2});
        return v3;
    }
}

static int64_t let_dbl_run(struct let_s5 p1) {
    {
        int64_t v2 = (p1).x;
        int64_t v4 = ((int64_t)(((uint64_t)v2) * ((uint64_t)INT64_C(2))));
        return v4;
    }
}

int64_t let_inc1_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).inc1;
        struct let_s5 v4 = let_inc1_advance_0(v3, p2);
        int64_t v5 = let_inc1_run(v4);
        return v5;
    }
}

int64_t let_dbl_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).dbl;
        struct let_s5 v4 = let_dbl_advance_0(v3, p2);
        int64_t v5 = let_dbl_run(v4);
        return v5;
    }
}

int64_t let_use_15_entry(struct let_s1 p1, struct let_s2 p2, int64_t p3) {
    {
        uint8_t v4 = (p1).use_15;
        struct let_s3 v5 = let_use_15_advance_0(v4, p2);
        struct let_s4 v6 = let_use_15_advance_1(v5, p3);
        int64_t v7 = let_use_15_run(v6);
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
