#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    uint8_t on_ok;
    uint8_t on_err;
    int64_t a;
    uint8_t divide_15;
    int64_t b;
    uint8_t divide_23;
};

struct let_s3 {
    uint8_t ok;
    uint8_t err;
};

struct let_s2 {
    struct let_s3 provide;
    uint8_t ok;
    uint8_t err;
};

struct let_s4 {
    struct let_s3 provide;
    uint8_t ok;
    uint8_t err;
    int64_t n;
};

struct let_s5 {
    int64_t n;
};

struct let_s1 let_module_init(void);

static uint8_t let_on_ok_construct(void);

static uint8_t let_on_err_construct(void);

static uint8_t let_divide_15_construct(void);

static struct let_s2 let_divide_15_advance_0(uint8_t p1, struct let_s3 p2);

static struct let_s4 let_divide_15_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_divide_15_run(struct let_s4 p1);

static struct let_s5 let_on_ok_advance_0(uint8_t p1, int64_t p2);

static int64_t let_on_ok_run(struct let_s5 p1);

static uint8_t let_divide_23_construct(void);

static struct let_s2 let_divide_23_advance_0(uint8_t p1, struct let_s3 p2);

static struct let_s4 let_divide_23_advance_1(struct let_s2 p1, int64_t p2);

static int64_t let_divide_23_run(struct let_s4 p1);

static struct let_s5 let_on_err_advance_0(uint8_t p1, int64_t p2);

static int64_t let_on_err_run(struct let_s5 p1);

int64_t let_on_ok_entry(struct let_s1 p1, int64_t p2);

int64_t let_on_err_entry(struct let_s1 p1, int64_t p2);

int64_t let_divide_15_entry(struct let_s1 p1, struct let_s3 p2, int64_t p3);

int64_t let_divide_23_entry(struct let_s1 p1, struct let_s3 p2, int64_t p3);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_on_ok_construct();
        uint8_t v2 = let_on_err_construct();
        uint8_t v4 = let_on_ok_construct();
        uint8_t v5 = let_on_err_construct();
        struct let_s3 v6 = ((struct let_s3){v4, v5});
        uint8_t v7 = let_divide_15_construct();
        struct let_s2 v8 = let_divide_15_advance_0(v7, v6);
        struct let_s4 v9 = let_divide_15_advance_1(v8, INT64_C(41));
        int64_t v10 = let_divide_15_run(v9);
        uint8_t v11 = let_divide_15_construct();
        uint8_t v13 = let_on_err_construct();
        uint8_t v14 = let_on_ok_construct();
        struct let_s3 v15 = ((struct let_s3){v13, v14});
        uint8_t v16 = let_divide_23_construct();
        struct let_s2 v17 = let_divide_23_advance_0(v16, v15);
        struct let_s4 v18 = let_divide_23_advance_1(v17, INT64_C(41));
        int64_t v19 = let_divide_23_run(v18);
        uint8_t v20 = let_divide_23_construct();
        struct let_s1 v21 = ((struct let_s1){v1, v2, v10, v11, v19, v20});
        return v21;
    }
}

static uint8_t let_on_ok_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_on_err_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_divide_15_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_divide_15_advance_0(uint8_t p1, struct let_s3 p2) {
    {
        uint8_t v3 = (p2).ok;
        uint8_t v4 = (p2).err;
        struct let_s2 v5 = ((struct let_s2){p2, v3, v4});
        return v5;
    }
}

static struct let_s4 let_divide_15_advance_1(struct let_s2 p1, int64_t p2) {
    {
        struct let_s3 v3 = (p1).provide;
        uint8_t v4 = (p1).ok;
        uint8_t v5 = (p1).err;
        struct let_s4 v6 = ((struct let_s4){v3, v4, v5, p2});
        return v6;
    }
}

static int64_t let_divide_15_run(struct let_s4 p1) {
    {
        int64_t v5 = (p1).n;
        uint8_t v6 = let_on_ok_construct();
        struct let_s5 v7 = let_on_ok_advance_0(v6, v5);
        int64_t v8 = let_on_ok_run(v7);
        return v8;
    }
}

static struct let_s5 let_on_ok_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s5 v3 = ((struct let_s5){p2});
        return v3;
    }
}

static int64_t let_on_ok_run(struct let_s5 p1) {
    {
        int64_t v2 = (p1).n;
        int64_t v4 = ((int64_t)(((uint64_t)v2) + ((uint64_t)INT64_C(1))));
        return v4;
    }
}

static uint8_t let_divide_23_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_divide_23_advance_0(uint8_t p1, struct let_s3 p2) {
    {
        uint8_t v3 = (p2).ok;
        uint8_t v4 = (p2).err;
        struct let_s2 v5 = ((struct let_s2){p2, v3, v4});
        return v5;
    }
}

static struct let_s4 let_divide_23_advance_1(struct let_s2 p1, int64_t p2) {
    {
        struct let_s3 v3 = (p1).provide;
        uint8_t v4 = (p1).ok;
        uint8_t v5 = (p1).err;
        struct let_s4 v6 = ((struct let_s4){v3, v4, v5, p2});
        return v6;
    }
}

static int64_t let_divide_23_run(struct let_s4 p1) {
    {
        int64_t v5 = (p1).n;
        uint8_t v6 = let_on_err_construct();
        struct let_s5 v7 = let_on_err_advance_0(v6, v5);
        int64_t v8 = let_on_err_run(v7);
        return v8;
    }
}

static struct let_s5 let_on_err_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s5 v3 = ((struct let_s5){p2});
        return v3;
    }
}

static int64_t let_on_err_run(struct let_s5 p1) {
    {
        int64_t v2 = (p1).n;
        int64_t v4 = ((int64_t)(((uint64_t)INT64_C(0)) - ((uint64_t)v2)));
        return v4;
    }
}

int64_t let_on_ok_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).on_ok;
        struct let_s5 v4 = let_on_ok_advance_0(v3, p2);
        int64_t v5 = let_on_ok_run(v4);
        return v5;
    }
}

int64_t let_on_err_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).on_err;
        struct let_s5 v4 = let_on_err_advance_0(v3, p2);
        int64_t v5 = let_on_err_run(v4);
        return v5;
    }
}

int64_t let_divide_15_entry(struct let_s1 p1, struct let_s3 p2, int64_t p3) {
    {
        uint8_t v4 = (p1).divide_15;
        struct let_s2 v5 = let_divide_15_advance_0(v4, p2);
        struct let_s4 v6 = let_divide_15_advance_1(v5, p3);
        int64_t v7 = let_divide_15_run(v6);
        return v7;
    }
}

int64_t let_divide_23_entry(struct let_s1 p1, struct let_s3 p2, int64_t p3) {
    {
        uint8_t v4 = (p1).divide_23;
        struct let_s2 v5 = let_divide_23_advance_0(v4, p2);
        struct let_s4 v6 = let_divide_23_advance_1(v5, p3);
        int64_t v7 = let_divide_23_run(v6);
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld\n", (long long)m.a, (long long)m.b);
    return 0; }
