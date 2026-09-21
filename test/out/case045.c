#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

struct let_s2 {
    uint8_t g;
};

struct let_s1 {
    uint8_t g;
    struct let_s2 use;
    int64_t answer;
};

struct let_s3 {
    uint8_t g;
    int64_t n;
};

struct let_s4 {
    int64_t n;
};

struct let_s6 {
    int64_t a;
    bool b;
};

union let_u5 {
    struct let_s6 f0;
    int64_t f1;
};

struct let_s5 {
    int64_t tag;
    union let_u5 payload;
};

struct let_s1 let_module_init(void);

static uint8_t let_g_construct(void);

static struct let_s2 let_use_construct(uint8_t p1);

static struct let_s3 let_use_advance_0(struct let_s2 p1, int64_t p2);

static int64_t let_use_run(struct let_s3 p1);

static struct let_s4 let_g_advance_0(uint8_t p1, int64_t p2);

static struct let_s5 let_g_run(struct let_s4 p1);

struct let_s5 let_g_entry(struct let_s1 p1, int64_t p2);

int64_t let_use_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_g_construct();
        struct let_s2 v2 = let_use_construct(v1);
        struct let_s2 v4 = let_use_construct(v1);
        struct let_s3 v5 = let_use_advance_0(v4, INT64_C(42));
        int64_t v6 = let_use_run(v5);
        struct let_s1 v7 = ((struct let_s1){v1, v2, v6});
        return v7;
    }
}

static uint8_t let_g_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_use_construct(uint8_t p1) {
    {
        struct let_s2 v2 = ((struct let_s2){p1});
        return v2;
    }
}

static struct let_s3 let_use_advance_0(struct let_s2 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).g;
        struct let_s3 v4 = ((struct let_s3){v3, p2});
        return v4;
    }
}

static int64_t let_use_run(struct let_s3 p1) {
    {
        struct let_s5 b5_p1;
        int64_t b5_p2;
        uint8_t b5_p3;
        struct let_s5 b6_p1;
        int64_t b6_p2;
        uint8_t b6_p3;
        struct let_s5 b2_p1;
        int64_t b2_p2;
        uint8_t b2_p3;
        struct let_s5 b4_p1;
        int64_t b4_p2;
        uint8_t b4_p3;
        struct let_s5 b3_p1;
        int64_t b3_p2;
        uint8_t b3_p3;
        uint8_t v2 = (p1).g;
        int64_t v3 = (p1).n;
        struct let_s4 v4 = let_g_advance_0(v2, v3);
        struct let_s5 v5 = let_g_run(v4);
        {
            b5_p1 = v5;
            b5_p2 = v3;
            b5_p3 = v2;
            goto b5;
        }
b5:;
        int64_t b5_v4 = (b5_p1).tag;
        bool b5_v6 = (b5_v4 == INT64_C(1));
        if (b5_v6)
        {
            b3_p1 = b5_p1;
            b3_p2 = b5_p2;
            b3_p3 = b5_p3;
            goto b3;
        }
        else
        {
            b6_p1 = b5_p1;
            b6_p2 = b5_p2;
            b6_p3 = b5_p3;
            goto b6;
        }
b6:;
        int64_t b6_v4 = (b6_p1).tag;
        bool b6_v6 = (b6_v4 == INT64_C(0));
        if (b6_v6)
        {
            b4_p1 = b6_p1;
            b4_p2 = b6_p2;
            b4_p3 = b6_p3;
            goto b4;
        }
        else
        {
            b2_p1 = b6_p1;
            b2_p2 = b6_p2;
            b2_p3 = b6_p3;
            goto b2;
        }
b2:;
        abort();
b4:;
        struct let_s6 b4_v4 = ((b4_p1).payload).f0;
        int64_t b4_v5 = (b4_v4).a;
        return b4_v5;
b3:;
        int64_t b3_v4 = ((b3_p1).payload).f1;
        return b3_v4;
    }
}

static struct let_s4 let_g_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static struct let_s5 let_g_run(struct let_s4 p1) {
    {
        int64_t v2 = (p1).n;
        struct let_s6 v4 = ((struct let_s6){v2, true});
        struct let_s5 v5 = ((struct let_s5){.tag = INT64_C(0), .payload = ((union let_u5){.f0 = v4})});
        return v5;
    }
}

struct let_s5 let_g_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).g;
        struct let_s4 v4 = let_g_advance_0(v3, p2);
        struct let_s5 v5 = let_g_run(v4);
        return v5;
    }
}

int64_t let_use_entry(struct let_s1 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).use;
        struct let_s3 v4 = let_use_advance_0(v3, p2);
        int64_t v5 = let_use_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
