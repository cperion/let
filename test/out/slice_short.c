#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>

struct let_s1 {
    uint8_t f;
    bool x;
};

struct let_s2 {
    bool a;
};

struct let_s1 let_module_init(void);

static uint8_t let_f_construct(void);

static struct let_s2 let_f_advance_0(uint8_t p1, bool p2);

static bool let_f_run(struct let_s2 p1);

bool let_f_entry(struct let_s1 p1, bool p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_f_construct();
        uint8_t v3 = let_f_construct();
        struct let_s2 v4 = let_f_advance_0(v3, false);
        bool v5 = let_f_run(v4);
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

static bool let_f_run(struct let_s2 p1) {
    {
        bool b3_p1;
        bool b3_p2;
        bool b4_p1;
        bool b2_p1;
        bool b2_p2;
        bool v2 = (p1).a;
        if (v2)
        {
            b4_p1 = v2;
            goto b4;
        }
        else
        {
            b3_p1 = v2;
            goto b3;
        }
b3:;
        {
            b2_p1 = b3_p1;
            b2_p2 = b3_p2;
            goto b2;
        }
b4:;
        int64_t b4_v4 = ((INT64_C(0) == INT64_C(0)) ? (abort(), INT64_C(0)) : ((INT64_C(0) == (-INT64_C(1))) ? ((int64_t)(((uint64_t)INT64_C(0)) - ((uint64_t)INT64_C(1)))) : (INT64_C(1) / INT64_C(0))));
        bool b4_v6 = (b4_v4 == INT64_C(0));
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_v6;
            goto b2;
        }
b2:;
        return b2_p2;
    }
}

bool let_f_entry(struct let_s1 p1, bool p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s2 v4 = let_f_advance_0(v3, p2);
        bool v5 = let_f_run(v4);
        return v5;
    }
}

int main(void){ printf("%d\n", (int)let_module_init().x); return 0; }
