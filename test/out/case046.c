#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

struct let_s1 {
    uint8_t pick;
    uint8_t choose;
    uint8_t use;
    int64_t answer;
};

struct let_s2 {
    int64_t n;
};

union let_u3 {
    int64_t f0;
    bool f1;
};

struct let_s3 {
    int64_t tag;
    union let_u3 payload;
};

struct let_s4 {
    struct let_s3 r;
};

struct let_s1 let_module_init(void);

static uint8_t let_pick_construct(void);

static uint8_t let_choose_construct(void);

static uint8_t let_use_construct(void);

static struct let_s2 let_choose_advance_0(uint8_t p1, int64_t p2);

static struct let_s3 let_choose_run(struct let_s2 p1);

static struct let_s4 let_use_advance_0(uint8_t p1, struct let_s3 p2);

static int64_t let_use_run(struct let_s4 p1);

struct let_s3 let_pick_entry(struct let_s1 p1, struct let_s3 p2);

static struct let_s4 let_pick_advance_0(uint8_t p1, struct let_s3 p2);

static struct let_s3 let_pick_run(struct let_s4 p1);

struct let_s3 let_choose_entry(struct let_s1 p1, int64_t p2);

int64_t let_use_entry(struct let_s1 p1, struct let_s3 p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_pick_construct();
        uint8_t v2 = let_choose_construct();
        uint8_t v3 = let_use_construct();
        uint8_t v5 = let_choose_construct();
        struct let_s2 v6 = let_choose_advance_0(v5, INT64_C(7));
        struct let_s3 v7 = let_choose_run(v6);
        uint8_t v8 = let_use_construct();
        struct let_s4 v9 = let_use_advance_0(v8, v7);
        int64_t v10 = let_use_run(v9);
        struct let_s1 v11 = ((struct let_s1){v1, v2, v3, v10});
        return v11;
    }
}

static uint8_t let_pick_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_choose_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_use_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_choose_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static struct let_s3 let_choose_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).n;
        struct let_s3 v3 = ((struct let_s3){.tag = INT64_C(0), .payload = ((union let_u3){.f0 = v2})});
        return v3;
    }
}

static struct let_s4 let_use_advance_0(uint8_t p1, struct let_s3 p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static int64_t let_use_run(struct let_s4 p1) {
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
        struct let_s3 v2 = (p1).r;
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
        abort();
b4:;
        return INT64_C(100);
b3:;
        int64_t b3_v3 = ((b3_p1).payload).f0;
        return b3_v3;
    }
}

struct let_s3 let_pick_entry(struct let_s1 p1, struct let_s3 p2) {
    {
        uint8_t v3 = (p1).pick;
        struct let_s4 v4 = let_pick_advance_0(v3, p2);
        struct let_s3 v5 = let_pick_run(v4);
        return v5;
    }
}

static struct let_s4 let_pick_advance_0(uint8_t p1, struct let_s3 p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static struct let_s3 let_pick_run(struct let_s4 p1) {
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
        struct let_s3 v2 = (p1).r;
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
        abort();
b4:;
        struct let_s3 b4_v4 = ((struct let_s3){.tag = INT64_C(1), .payload = ((union let_u3){.f1 = true})});
        return b4_v4;
b3:;
        int64_t b3_v3 = ((b3_p1).payload).f0;
        struct let_s3 b3_v4 = ((struct let_s3){.tag = INT64_C(0), .payload = ((union let_u3){.f0 = b3_v3})});
        return b3_v4;
    }
}

struct let_s3 let_choose_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).choose;
        struct let_s2 v4 = let_choose_advance_0(v3, p2);
        struct let_s3 v5 = let_choose_run(v4);
        return v5;
    }
}

int64_t let_use_entry(struct let_s1 p1, struct let_s3 p2) {
    {
        uint8_t v3 = (p1).use;
        struct let_s4 v4 = let_use_advance_0(v3, p2);
        int64_t v5 = let_use_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
