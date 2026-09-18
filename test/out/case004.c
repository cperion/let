#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

struct let_s1 {
    int64_t a;
    int64_t b;
    int64_t c;
    bool d;
    bool e;
    bool f;
    int64_t g;
    int64_t h;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        int64_t b3_p1;
        int64_t b3_p2;
        int64_t b3_p3;
        bool b3_p4;
        bool b3_p5;
        int64_t b4_p1;
        int64_t b4_p2;
        int64_t b4_p3;
        bool b4_p4;
        int64_t b2_p1;
        int64_t b2_p2;
        int64_t b2_p3;
        bool b2_p4;
        bool b2_p5;
        int64_t v13 = ((INT64_C(3) == INT64_C(0)) ? (abort(), INT64_C(0)) : ((INT64_C(3) == (-INT64_C(1))) ? INT64_C(0) : (INT64_C(10) % INT64_C(3))));
        if (true)
        {
            b4_p1 = INT64_C(14);
            b4_p2 = INT64_C(20);
            b4_p3 = v13;
            b4_p4 = true;
            goto b4;
        }
        else
        {
            b3_p1 = INT64_C(14);
            b3_p2 = INT64_C(20);
            b3_p3 = v13;
            b3_p4 = true;
            goto b3;
        }
b3:;
        {
            b2_p1 = INT64_C(14);
            b2_p2 = INT64_C(20);
            b2_p3 = b3_p3;
            b2_p4 = true;
            b2_p5 = b3_p5;
            goto b2;
        }
b4:;
        {
            b2_p1 = INT64_C(14);
            b2_p2 = INT64_C(20);
            b2_p3 = b4_p3;
            b2_p4 = true;
            b2_p5 = false;
            goto b2;
        }
b2:;
        int64_t b2_v13 = ((int64_t)(((uint64_t)INT64_C(1)) << (((uint64_t)INT64_C(4)) & INT64_C(63))));
        struct let_s1 b2_v14 = ((struct let_s1){INT64_C(14), INT64_C(20), b2_p3, true, b2_p5, true, (-INT64_C(5)), b2_v13});
        return b2_v14;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld %lld %lld %lld %lld %lld %lld\n", (long long)m.a, (long long)m.b, (long long)m.c, (long long)m.d, (long long)m.e, (long long)m.f, (long long)m.g, (long long)m.h);
    return 0; }
