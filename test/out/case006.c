#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>

struct let_s1 {
    uint8_t total;
    int64_t answer;
};

struct let_s2 {
    int64_t n;
};

struct let_s1 let_module_init(void);

static uint8_t let_total_construct(void);

static struct let_s2 let_total_advance_0(uint8_t p1, int64_t p2);

static int64_t let_total_run(struct let_s2 p1);

int64_t let_total_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_total_construct();
        uint8_t v3 = let_total_construct();
        struct let_s2 v4 = let_total_advance_0(v3, INT64_C(5));
        int64_t v5 = let_total_run(v4);
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
    }
}

static uint8_t let_total_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_total_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_total_run(struct let_s2 p1) {
    {
        int64_t b2_p1;
        int64_t* b2_p2;
        int64_t* b2_p3;
        int64_t b3_p1;
        int64_t* b3_p2;
        int64_t* b3_p3;
        int64_t b4_p1;
        int64_t* b4_p2;
        int64_t* b4_p3;
        int64_t b7_p1;
        int64_t* b7_p2;
        int64_t* b7_p3;
        int64_t b5_p1;
        int64_t* b5_p2;
        int64_t* b5_p3;
        int64_t b6_p1;
        int64_t* b6_p2;
        int64_t* b6_p3;
        int64_t v2 = (p1).n;
        int64_t v4 = INT64_C(0);
        int64_t v6 = INT64_C(0);
        {
            b2_p1 = v2;
            b2_p2 = (&v4);
            b2_p3 = (&v6);
            goto b2;
        }
b2:;
        int64_t b2_v4 = (*b2_p2);
        bool b2_v5 = (b2_v4 < b2_p1);
        if (b2_v5)
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
        int64_t b4_v4 = (*b4_p2);
        int64_t b4_v6 = ((int64_t)(((uint64_t)b4_v4) + ((uint64_t)INT64_C(1))));
        (*b4_p2) = b4_v6;
        int64_t b4_v8 = (*b4_p2);
        bool b4_v10 = (b4_v8 == INT64_C(3));
        if (b4_v10)
        {
            b6_p1 = b4_p1;
            b6_p2 = b4_p2;
            b6_p3 = b4_p3;
            goto b6;
        }
        else
        {
            b7_p1 = b4_p1;
            b7_p2 = b4_p2;
            b7_p3 = b4_p3;
            goto b7;
        }
b7:;
        {
            b5_p1 = b7_p1;
            b5_p2 = b7_p2;
            b5_p3 = b7_p3;
            goto b5;
        }
b5:;
        int64_t b5_v4 = (*b5_p3);
        int64_t b5_v5 = (*b5_p2);
        int64_t b5_v6 = ((int64_t)(((uint64_t)b5_v4) + ((uint64_t)b5_v5)));
        (*b5_p3) = b5_v6;
        {
            b2_p1 = b5_p1;
            b2_p2 = b5_p2;
            b2_p3 = b5_p3;
            goto b2;
        }
b6:;
        {
            b2_p1 = b6_p1;
            b2_p2 = b6_p2;
            b2_p3 = b6_p3;
            goto b2;
        }
    }
}

int64_t let_total_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).total;
        struct let_s2 v4 = let_total_advance_0(v3, p2);
        int64_t v5 = let_total_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
