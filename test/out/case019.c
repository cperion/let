#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

struct let_s1 {
    uint8_t pick;
    int64_t first;
    int64_t last;
};

struct let_s2 {
    int64_t i;
};

struct let_s3 {
    int64_t f0;
    int64_t f1;
    int64_t f2;
};

struct let_s1 let_module_init(void);

static uint8_t let_pick_construct(void);

static struct let_s2 let_pick_advance_0(uint8_t p1, int64_t p2);

static int64_t let_pick_run(struct let_s2 p1);

int64_t let_pick_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_pick_construct();
        uint8_t v3 = let_pick_construct();
        struct let_s2 v4 = let_pick_advance_0(v3, INT64_C(0));
        int64_t v5 = let_pick_run(v4);
        uint8_t v7 = let_pick_construct();
        struct let_s2 v8 = let_pick_advance_0(v7, INT64_C(2));
        int64_t v9 = let_pick_run(v8);
        struct let_s1 v10 = ((struct let_s1){v1, v5, v9});
        return v10;
    }
}

static uint8_t let_pick_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_pick_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_pick_run(struct let_s2 p1) {
    {
        int64_t* b4_p1;
        int64_t b4_p2;
        struct let_s3 b4_p3;
        int64_t b4_p4;
        struct let_s3 b4_p5;
        int64_t* b6_p1;
        int64_t b6_p2;
        struct let_s3 b6_p3;
        int64_t b6_p4;
        struct let_s3 b6_p5;
        int64_t* b8_p1;
        int64_t b8_p2;
        struct let_s3 b8_p3;
        int64_t b8_p4;
        struct let_s3 b8_p5;
        int64_t* b3_p1;
        int64_t b3_p2;
        struct let_s3 b3_p3;
        int64_t b3_p4;
        struct let_s3 b3_p5;
        int64_t* b9_p1;
        int64_t b9_p2;
        struct let_s3 b9_p3;
        int64_t b9_p4;
        struct let_s3 b9_p5;
        int64_t* b7_p1;
        int64_t b7_p2;
        struct let_s3 b7_p3;
        int64_t b7_p4;
        struct let_s3 b7_p5;
        int64_t* b5_p1;
        int64_t b5_p2;
        struct let_s3 b5_p3;
        int64_t b5_p4;
        struct let_s3 b5_p5;
        int64_t* b2_p1;
        int64_t b2_p2;
        struct let_s3 b2_p3;
        int64_t b2_p4;
        struct let_s3 b2_p5;
        int64_t v2 = (p1).i;
        struct let_s3 v6 = ((struct let_s3){INT64_C(10), INT64_C(20), INT64_C(30)});
        int64_t v7 = (((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)})).f0;
        int64_t v8 = v7;
        {
            b4_p1 = (&v8);
            b4_p2 = v2;
            b4_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b4_p4 = v2;
            b4_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b4;
        }
b4:;
        bool b4_v7 = (b4_p2 == INT64_C(0));
        if (b4_v7)
        {
            b5_p1 = b4_p1;
            b5_p2 = b4_p2;
            b5_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b5_p4 = b4_p4;
            b5_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b5;
        }
        else
        {
            b6_p1 = b4_p1;
            b6_p2 = b4_p2;
            b6_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b6_p4 = b4_p4;
            b6_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b6;
        }
b6:;
        bool b6_v7 = (b6_p2 == INT64_C(1));
        if (b6_v7)
        {
            b7_p1 = b6_p1;
            b7_p2 = b6_p2;
            b7_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b7_p4 = b6_p4;
            b7_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b7;
        }
        else
        {
            b8_p1 = b6_p1;
            b8_p2 = b6_p2;
            b8_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b8_p4 = b6_p4;
            b8_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b8;
        }
b8:;
        bool b8_v7 = (b8_p2 == INT64_C(2));
        if (b8_v7)
        {
            b9_p1 = b8_p1;
            b9_p2 = b8_p2;
            b9_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b9_p4 = b8_p4;
            b9_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b9;
        }
        else
        {
            b3_p1 = b8_p1;
            b3_p2 = b8_p2;
            b3_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b3_p4 = b8_p4;
            b3_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b3;
        }
b3:;
        abort();
b9:;
        int64_t b9_v6 = (((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)})).f2;
        (*b9_p1) = b9_v6;
        {
            b2_p1 = b9_p1;
            b2_p2 = b9_p2;
            b2_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b2_p4 = b9_p4;
            b2_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b2;
        }
b7:;
        int64_t b7_v6 = (((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)})).f1;
        (*b7_p1) = b7_v6;
        {
            b2_p1 = b7_p1;
            b2_p2 = b7_p2;
            b2_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b2_p4 = b7_p4;
            b2_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b2;
        }
b5:;
        {
            b2_p1 = b5_p1;
            b2_p2 = b5_p2;
            b2_p3 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            b2_p4 = b5_p4;
            b2_p5 = ((struct let_s3){.f0 = INT64_C(10), .f1 = INT64_C(20), .f2 = INT64_C(30)});
            goto b2;
        }
b2:;
        int64_t b2_v6 = (*b2_p1);
        return b2_v6;
    }
}

int64_t let_pick_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).pick;
        struct let_s2 v4 = let_pick_advance_0(v3, p2);
        int64_t v5 = let_pick_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld\n", (long long)m.first, (long long)m.last);
    return 0; }
