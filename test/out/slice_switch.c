#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

struct let_s1 {
    uint8_t f;
    int64_t x;
    int64_t y;
    int64_t z;
};

struct let_s2 {
    int64_t a;
};

struct let_s1 let_module_init(void);

static uint8_t let_f_construct(void);

static struct let_s2 let_f_advance_0(uint8_t p1, int64_t p2);

static int64_t let_f_run(struct let_s2 p1);

int64_t let_f_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_f_construct();
        uint8_t v3 = let_f_construct();
        struct let_s2 v4 = let_f_advance_0(v3, INT64_C(0));
        int64_t v5 = let_f_run(v4);
        uint8_t v7 = let_f_construct();
        struct let_s2 v8 = let_f_advance_0(v7, INT64_C(2));
        int64_t v9 = let_f_run(v8);
        uint8_t v11 = let_f_construct();
        struct let_s2 v12 = let_f_advance_0(v11, INT64_C(9));
        int64_t v13 = let_f_run(v12);
        struct let_s1 v14 = ((struct let_s1){v1, v5, v9, v13});
        return v14;
    }
}

static uint8_t let_f_construct(void) {
    {
        return INT64_C(0);
    }
}

static struct let_s2 let_f_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_f_run(struct let_s2 p1) {
    {
        int64_t b6_p1;
        int64_t b6_p2;
        int64_t b7_p1;
        int64_t b7_p2;
        int64_t b8_p1;
        int64_t b8_p2;
        int64_t b5_p1;
        int64_t b5_p2;
        int64_t b4_p1;
        int64_t b4_p2;
        int64_t b3_p1;
        int64_t b3_p2;
        int64_t v2 = (p1).a;
        {
            b6_p1 = v2;
            b6_p2 = v2;
            goto b6;
        }
b6:;
        bool b6_v4 = (b6_p1 == INT64_C(0));
        if (b6_v4)
        {
            b3_p1 = b6_p1;
            b3_p2 = b6_p2;
            goto b3;
        }
        else
        {
            b7_p1 = b6_p1;
            b7_p2 = b6_p2;
            goto b7;
        }
b7:;
        bool b7_v4 = (b7_p1 == INT64_C(1));
        if (b7_v4)
        {
            b4_p1 = b7_p1;
            b4_p2 = b7_p2;
            goto b4;
        }
        else
        {
            b8_p1 = b7_p1;
            b8_p2 = b7_p2;
            goto b8;
        }
b8:;
        bool b8_v4 = (b8_p1 == INT64_C(2));
        if (b8_v4)
        {
            b4_p1 = b8_p1;
            b4_p2 = b8_p2;
            goto b4;
        }
        else
        {
            b5_p1 = b8_p1;
            b5_p2 = b8_p2;
            goto b5;
        }
b5:;
        return INT64_C(30);
b4:;
        return INT64_C(20);
b3:;
        return INT64_C(10);
    }
}

int64_t let_f_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s2 v4 = let_f_advance_0(v3, p2);
        int64_t v5 = let_f_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init(); printf("%lld %lld %lld\n", (long long)m.x, (long long)m.y, (long long)m.z); return 0; }
