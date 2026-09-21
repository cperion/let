#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>

struct let_s2 {
    uint8_t g;
};

struct let_s1 {
    uint8_t g;
    struct let_s2 check;
    int64_t a;
    int64_t b;
    int64_t c;
};

struct let_s3 {
    uint8_t g;
    int64_t a;
};

struct let_s4 {
    int64_t a;
};

struct let_s1 let_module_init(void);

static uint8_t let_g_construct(void);

static struct let_s2 let_check_construct(uint8_t p1);

static struct let_s3 let_check_advance_0(struct let_s2 p1, int64_t p2);

static int64_t let_check_run(struct let_s3 p1);

static struct let_s4 let_g_advance_0(uint8_t p1, int64_t p2);

static bool let_g_run(struct let_s4 p1);

bool let_g_entry(struct let_s1 p1, int64_t p2);

int64_t let_check_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_g_construct();
        struct let_s2 v2 = let_check_construct(v1);
        struct let_s2 v4 = let_check_construct(v1);
        struct let_s3 v5 = let_check_advance_0(v4, INT64_C(0));
        int64_t v6 = let_check_run(v5);
        struct let_s2 v8 = let_check_construct(v1);
        struct let_s3 v9 = let_check_advance_0(v8, INT64_C(101));
        int64_t v10 = let_check_run(v9);
        struct let_s2 v12 = let_check_construct(v1);
        struct let_s3 v13 = let_check_advance_0(v12, INT64_C(5));
        int64_t v14 = let_check_run(v13);
        struct let_s1 v15 = ((struct let_s1){v1, v2, v6, v10, v14});
        return v15;
    }
}

static uint8_t let_g_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_check_construct(uint8_t p1) {
    {
        struct let_s2 v2 = ((struct let_s2){p1});
        return v2;
    }
}

static struct let_s3 let_check_advance_0(struct let_s2 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).g;
        struct let_s3 v4 = ((struct let_s3){v3, p2});
        return v4;
    }
}

static int64_t let_check_run(struct let_s3 p1) {
    {
        int64_t b4_p1;
        uint8_t b4_p2;
        int64_t b2_p1;
        uint8_t b2_p2;
        int64_t b3_p1;
        uint8_t b3_p2;
        uint8_t v2 = (p1).g;
        int64_t v3 = (p1).a;
        struct let_s4 v4 = let_g_advance_0(v2, v3);
        bool v5 = let_g_run(v4);
        if (v5)
        {
            b3_p1 = v3;
            b3_p2 = v2;
            goto b3;
        }
        else
        {
            b4_p1 = v3;
            b4_p2 = v2;
            goto b4;
        }
b4:;
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            goto b2;
        }
b2:;
        return INT64_C(0);
b3:;
        return INT64_C(1);
    }
}

static struct let_s4 let_g_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static bool let_g_run(struct let_s4 p1) {
    {
        int64_t b4_p1;
        int64_t b3_p1;
        bool b3_p2;
        int64_t b2_p1;
        bool b2_p2;
        int64_t v2 = (p1).a;
        bool v4 = (v2 == INT64_C(0));
        if (v4)
        {
            b3_p1 = v2;
            b3_p2 = v4;
            goto b3;
        }
        else
        {
            b4_p1 = v2;
            goto b4;
        }
b4:;
        bool b4_v3 = (b4_p1 > INT64_C(100));
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_v3;
            goto b2;
        }
b3:;
        {
            b2_p1 = b3_p1;
            b2_p2 = b3_p2;
            goto b2;
        }
b2:;
        return b2_p2;
    }
}

bool let_g_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).g;
        struct let_s4 v4 = let_g_advance_0(v3, p2);
        bool v5 = let_g_run(v4);
        return v5;
    }
}

int64_t let_check_entry(struct let_s1 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).check;
        struct let_s3 v4 = let_check_advance_0(v3, p2);
        int64_t v5 = let_check_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld %lld\n", (long long)m.a, (long long)m.b, (long long)m.c);
    return 0; }
