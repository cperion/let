#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

struct let_s1 {
    uint8_t f;
    int64_t a;
    int64_t b;
};

struct let_s2 {
    bool c;
};

struct let_s3 {
    int64_t x;
    int64_t y;
};

struct let_s1 let_module_init(void);

static uint8_t let_f_construct(void);

static struct let_s2 let_f_advance_0(uint8_t p1, bool p2);

static int64_t let_f_run(struct let_s2 p1);

int64_t let_f_entry(struct let_s1 p1, bool p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_f_construct();
        uint8_t v3 = let_f_construct();
        struct let_s2 v4 = let_f_advance_0(v3, true);
        int64_t v5 = let_f_run(v4);
        uint8_t v7 = let_f_construct();
        struct let_s2 v8 = let_f_advance_0(v7, false);
        int64_t v9 = let_f_run(v8);
        struct let_s1 v10 = ((struct let_s1){v1, v5, v9});
        return v10;
    }
}

static uint8_t let_f_construct(void) {
    {
        return INT64_C(0);
    }
}

static struct let_s2 let_f_advance_0(uint8_t p1, bool p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_f_run(struct let_s2 p1) {
    {
        bool b4_p1;
        struct let_s3 b4_p2;
        int64_t b4_p3;
        int64_t b4_p4;
        bool b3_p1;
        struct let_s3 b3_p2;
        int64_t b3_p3;
        int64_t b3_p4;
        bool v2 = (p1).c;
        if (v2)
        {
            b3_p1 = v2;
            b3_p2 = ((struct let_s3){.x = INT64_C(1), .y = INT64_C(2)});
            b3_p3 = INT64_C(1);
            b3_p4 = INT64_C(2);
            goto b3;
        }
        else
        {
            b4_p1 = v2;
            b4_p2 = ((struct let_s3){.x = INT64_C(1), .y = INT64_C(2)});
            b4_p3 = INT64_C(1);
            b4_p4 = INT64_C(2);
            goto b4;
        }
b4:;
        int64_t b4_v5 = (((struct let_s3){.x = INT64_C(1), .y = INT64_C(2)})).y;
        return b4_v5;
b3:;
        int64_t b3_v5 = (((struct let_s3){.x = INT64_C(1), .y = INT64_C(2)})).x;
        return b3_v5;
    }
}

int64_t let_f_entry(struct let_s1 p1, bool p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s2 v4 = let_f_advance_0(v3, p2);
        int64_t v5 = let_f_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init(); printf("%lld %lld\n", (long long)m.a, (long long)m.b); return 0; }
