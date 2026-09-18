#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>

struct let_s1 {
    uint8_t describe;
    int64_t a;
    int64_t b;
};

union let_u3 {
    int64_t f0;
    bool f1;
};

struct let_s3 {
    int64_t tag;
    union let_u3 payload;
};

struct let_s2 {
    struct let_s3 v;
};

struct let_s1 let_module_init(void);

static uint8_t let_describe_construct(void);

static struct let_s2 let_describe_advance_0(uint8_t p1, struct let_s3 p2);

static int64_t let_describe_run(struct let_s2 p1);

int64_t let_describe_entry(struct let_s1 p1, struct let_s3 p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_describe_construct();
        struct let_s3 v3 = ((struct let_s3){.tag = INT64_C(0), .payload = ((union let_u3){.f0 = INT64_C(7)})});
        uint8_t v4 = let_describe_construct();
        struct let_s2 v5 = let_describe_advance_0(v4, v3);
        int64_t v6 = let_describe_run(v5);
        struct let_s3 v8 = ((struct let_s3){.tag = INT64_C(1), .payload = ((union let_u3){.f1 = true})});
        uint8_t v9 = let_describe_construct();
        struct let_s2 v10 = let_describe_advance_0(v9, v8);
        int64_t v11 = let_describe_run(v10);
        struct let_s1 v12 = ((struct let_s1){v1, v6, v11});
        return v12;
    }
}

static uint8_t let_describe_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_describe_advance_0(uint8_t p1, struct let_s3 p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_describe_run(struct let_s2 p1) {
    {
        struct let_s3 b5_p1;
        struct let_s3 b5_p2;
        struct let_s3 b6_p1;
        struct let_s3 b6_p2;
        struct let_s3 b2_p1;
        struct let_s3 b2_p2;
        struct let_s3 b4_p1;
        struct let_s3 b4_p2;
        struct let_s3 b3_p1;
        struct let_s3 b3_p2;
        struct let_s3 v2 = (p1).v;
        {
            b5_p1 = v2;
            b5_p2 = v2;
            goto b5;
        }
b5:;
        int64_t b5_v3 = (b5_p1).tag;
        bool b5_v5 = (b5_v3 == INT64_C(0));
        if (b5_v5)
        {
            b3_p1 = b5_p1;
            b3_p2 = b5_p2;
            goto b3;
        }
        else
        {
            b6_p1 = b5_p1;
            b6_p2 = b5_p2;
            goto b6;
        }
b6:;
        int64_t b6_v3 = (b6_p1).tag;
        bool b6_v5 = (b6_v3 == INT64_C(1));
        if (b6_v5)
        {
            b4_p1 = b6_p1;
            b4_p2 = b6_p2;
            goto b4;
        }
        else
        {
            b2_p1 = b6_p1;
            b2_p2 = b6_p2;
            goto b2;
        }
b2:;
        return INT64_C(0);
b4:;
        return INT64_C(1);
b3:;
        int64_t b3_v3 = ((b3_p1).payload).f0;
        return b3_v3;
    }
}

int64_t let_describe_entry(struct let_s1 p1, struct let_s3 p2) {
    {
        uint8_t v3 = (p1).describe;
        struct let_s2 v4 = let_describe_advance_0(v3, p2);
        int64_t v5 = let_describe_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld\n", (long long)m.a, (long long)m.b);
    return 0; }
