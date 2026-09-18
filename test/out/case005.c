#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    uint8_t make;
    uint8_t tuple;
    int64_t a;
    int64_t b;
};

struct let_s2 {
    int64_t n;
};

struct let_s3 {
    int64_t x;
    int64_t y;
};

struct let_s4 {
    int64_t f0;
    int64_t f1;
    int64_t f2;
};

struct let_s1 let_module_init(void);

static uint8_t let_make_construct(void);

static uint8_t let_tuple_construct(void);

static struct let_s2 let_make_advance_0(uint8_t p1, int64_t p2);

static int64_t let_make_run(struct let_s2 p1);

static struct let_s2 let_tuple_advance_0(uint8_t p1, int64_t p2);

static int64_t let_tuple_run(struct let_s2 p1);

int64_t let_make_entry(struct let_s1 p1, int64_t p2);

int64_t let_tuple_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_make_construct();
        uint8_t v2 = let_tuple_construct();
        uint8_t v4 = let_make_construct();
        struct let_s2 v5 = let_make_advance_0(v4, INT64_C(3));
        int64_t v6 = let_make_run(v5);
        uint8_t v8 = let_tuple_construct();
        struct let_s2 v9 = let_tuple_advance_0(v8, INT64_C(5));
        int64_t v10 = let_tuple_run(v9);
        struct let_s1 v11 = ((struct let_s1){v1, v2, v6, v10});
        return v11;
    }
}

static uint8_t let_make_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_tuple_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_make_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_make_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).n;
        int64_t v4 = ((int64_t)(((uint64_t)v2) * ((uint64_t)INT64_C(2))));
        struct let_s3 v5 = ((struct let_s3){v2, v4});
        int64_t v6 = (v5).x;
        int64_t v7 = (v5).y;
        int64_t v8 = ((int64_t)(((uint64_t)v6) + ((uint64_t)v7)));
        return v8;
    }
}

static struct let_s2 let_tuple_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_tuple_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).n;
        struct let_s4 v6 = ((struct let_s4){INT64_C(10), INT64_C(20), INT64_C(30)});
        int64_t v7 = (((struct let_s4){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)})).f1;
        int64_t v8 = ((int64_t)(((uint64_t)v7) + ((uint64_t)v2)));
        return v8;
    }
}

int64_t let_make_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).make;
        struct let_s2 v4 = let_make_advance_0(v3, p2);
        int64_t v5 = let_make_run(v4);
        return v5;
    }
}

int64_t let_tuple_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).tuple;
        struct let_s2 v4 = let_tuple_advance_0(v3, p2);
        int64_t v5 = let_tuple_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld\n", (long long)m.a, (long long)m.b);
    return 0; }
