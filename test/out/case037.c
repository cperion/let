#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    uint8_t square;
    uint8_t inc;
    int64_t a;
    uint8_t twice_10;
    int64_t b;
    uint8_t twice_14;
};

struct let_s2 {
    uint8_t f;
};

struct let_s3 {
    uint8_t f;
    int64_t x;
};

struct let_s4 {
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_square_construct(void);

static uint8_t let_inc_construct(void);

static uint8_t let_twice_10_construct(void);

static struct let_s2 let_twice_10_advance_0(uint8_t p1, uint8_t p2);

static struct let_s3 let_twice_10_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_twice_10_run(struct let_s3 p1);

static struct let_s4 let_square_advance_0(uint8_t p1, int64_t p2);

static int64_t let_square_run(struct let_s4 p1);

static uint8_t let_twice_14_construct(void);

static struct let_s2 let_twice_14_advance_0(uint8_t p1, uint8_t p2);

static struct let_s3 let_twice_14_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_twice_14_run(struct let_s3 p1);

static struct let_s4 let_inc_advance_0(uint8_t p1, int64_t p2);

static int64_t let_inc_run(struct let_s4 p1);

int64_t let_square_entry(struct let_s1 p1, int64_t p2);

int64_t let_inc_entry(struct let_s1 p1, int64_t p2);

int64_t let_twice_10_entry(struct let_s1 p1, uint8_t p2, int64_t p3);

int64_t let_twice_14_entry(struct let_s1 p1, uint8_t p2, int64_t p3);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_square_construct();
        uint8_t v2 = let_inc_construct();
        uint8_t v4 = let_twice_10_construct();
        struct let_s2 v5 = let_twice_10_advance_0(v4, v1);
        struct let_s3 v6 = let_twice_10_advance_1(v5, INT64_C(3));
        int64_t v7 = let_twice_10_run(v6);
        uint8_t v8 = let_twice_10_construct();
        uint8_t v10 = let_twice_14_construct();
        struct let_s2 v11 = let_twice_14_advance_0(v10, v2);
        struct let_s3 v12 = let_twice_14_advance_1(v11, INT64_C(3));
        int64_t v13 = let_twice_14_run(v12);
        uint8_t v14 = let_twice_14_construct();
        struct let_s1 v15 = ((struct let_s1){v1, v2, v7, v8, v13, v14});
        return v15;
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

static uint8_t let_twice_10_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_twice_10_advance_0(uint8_t p1, uint8_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s3 let_twice_10_advance_1(struct let_s2 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s3 v4 = ((struct let_s3){v3, p2});
        return v4;
    }
}

static int64_t let_twice_10_run(struct let_s3 p1) {
    {
        uint8_t v2 = (p1).f;
        int64_t v3 = (p1).x;
        struct let_s4 v4 = let_square_advance_0(v2, v3);
        int64_t v5 = let_square_run(v4);
        struct let_s4 v6 = let_square_advance_0(v2, v5);
        int64_t v7 = let_square_run(v6);
        return v7;
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

static uint8_t let_twice_14_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_twice_14_advance_0(uint8_t p1, uint8_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s3 let_twice_14_advance_1(struct let_s2 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s3 v4 = ((struct let_s3){v3, p2});
        return v4;
    }
}

static int64_t let_twice_14_run(struct let_s3 p1) {
    {
        uint8_t v2 = (p1).f;
        int64_t v3 = (p1).x;
        struct let_s4 v4 = let_inc_advance_0(v2, v3);
        int64_t v5 = let_inc_run(v4);
        struct let_s4 v6 = let_inc_advance_0(v2, v5);
        int64_t v7 = let_inc_run(v6);
        return v7;
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

int64_t let_square_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).square;
        struct let_s4 v4 = let_square_advance_0(v3, p2);
        int64_t v5 = let_square_run(v4);
        return v5;
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

int64_t let_twice_10_entry(struct let_s1 p1, uint8_t p2, int64_t p3) {
    {
        uint8_t v4 = (p1).twice_10;
        struct let_s2 v5 = let_twice_10_advance_0(v4, p2);
        struct let_s3 v6 = let_twice_10_advance_1(v5, p3);
        int64_t v7 = let_twice_10_run(v6);
        return v7;
    }
}

int64_t let_twice_14_entry(struct let_s1 p1, uint8_t p2, int64_t p3) {
    {
        uint8_t v4 = (p1).twice_14;
        struct let_s2 v5 = let_twice_14_advance_0(v4, p2);
        struct let_s3 v6 = let_twice_14_advance_1(v5, p3);
        int64_t v7 = let_twice_14_run(v6);
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld\n", (long long)m.a, (long long)m.b);
    return 0; }
