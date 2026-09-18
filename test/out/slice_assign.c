#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

struct let_s1 {
    uint8_t f;
    int64_t x;
};

struct let_s2 {
    bool b;
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
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
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
        bool b2_p1;
        bool* b2_p2;
        int64_t* b2_p3;
        bool b3_p1;
        bool* b3_p2;
        int64_t* b3_p3;
        bool b4_p1;
        bool* b4_p2;
        int64_t* b4_p3;
        bool v2 = (p1).b;
        bool v3 = v2;
        int64_t v5 = INT64_C(0);
        {
            b2_p1 = v2;
            b2_p2 = (&v3);
            b2_p3 = (&v5);
            goto b2;
        }
b2:;
        bool b2_v4 = (*b2_p2);
        if (b2_v4)
        {
            b4_p1 = b2_p1;
            b4_p2 = b2_p2;
            b4_p3 = b2_p3;
            goto b4;
        }
        else
        {
            b3_p1 = b2_p1;
            b3_p2 = b2_p2;
            b3_p3 = b2_p3;
            goto b3;
        }
b3:;
        int64_t b3_v4 = (*b3_p3);
        return b3_v4;
b4:;
        (*b4_p2) = false;
        (*b4_p3) = INT64_C(1);
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            b2_p3 = b4_p3;
            goto b2;
        }
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

int main(void){ printf("%lld\n", (long long)let_module_init().x); return 0; }
