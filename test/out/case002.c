#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>

struct let_s1 {
    uint8_t sign;
    uint8_t classify;
};

struct let_s2 {
    int64_t n;
};

struct let_s3 {
    int64_t code;
};

struct let_s1 let_module_init(void);

static uint8_t let_sign_construct(void);

static uint8_t let_classify_construct(void);

int64_t let_sign_entry(struct let_s1 p1, int64_t p2);

static struct let_s2 let_sign_advance_0(uint8_t p1, int64_t p2);

static int64_t let_sign_run(struct let_s2 p1);

int64_t let_classify_entry(struct let_s1 p1, int64_t p2);

static struct let_s3 let_classify_advance_0(uint8_t p1, int64_t p2);

static int64_t let_classify_run(struct let_s3 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_sign_construct();
        uint8_t v2 = let_classify_construct();
        struct let_s1 v3 = ((struct let_s1){v1, v2});
        return v3;
    }
}

static uint8_t let_sign_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_classify_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

int64_t let_sign_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).sign;
        struct let_s2 v4 = let_sign_advance_0(v3, p2);
        int64_t v5 = let_sign_run(v4);
        return v5;
    }
}

static struct let_s2 let_sign_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_sign_run(struct let_s2 p1) {
    {
        int64_t b4_p1;
        int64_t b7_p1;
        int64_t b6_p1;
        int64_t b3_p1;
        int64_t v2 = (p1).n;
        bool v4 = (v2 < INT64_C(0));
        if (v4)
        {
            b3_p1 = v2;
            goto b3;
        }
        else
        {
            b4_p1 = v2;
            goto b4;
        }
b4:;
        bool b4_v3 = (b4_p1 == INT64_C(0));
        if (b4_v3)
        {
            b6_p1 = b4_p1;
            goto b6;
        }
        else
        {
            b7_p1 = b4_p1;
            goto b7;
        }
b7:;
        return INT64_C(1);
b6:;
        return INT64_C(0);
b3:;
        return (-INT64_C(1));
    }
}

int64_t let_classify_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).classify;
        struct let_s3 v4 = let_classify_advance_0(v3, p2);
        int64_t v5 = let_classify_run(v4);
        return v5;
    }
}

static struct let_s3 let_classify_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static int64_t let_classify_run(struct let_s3 p1) {
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
        int64_t v2 = (p1).code;
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

int main(void) {
    struct let_s1 m = let_module_init();
    printf("%lld %lld %lld\n", (long long)let_sign_entry(m, 0 - 5), (long long)let_sign_entry(m, 0),
        (long long)let_sign_entry(m, 7));
    printf("%lld %lld %lld %lld\n", (long long)let_classify_entry(m, 0),
        (long long)let_classify_entry(m, 1), (long long)let_classify_entry(m, 2),
        (long long)let_classify_entry(m, 3));
    return 0;
}
