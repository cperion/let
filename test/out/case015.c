#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
typedef struct { int64_t tag; } Handle;

#include <stdint.h>
#include <stdbool.h>

extern void release(Handle a1);

extern Handle made(int64_t a1);

struct let_s2 {
    uint8_t made;
};

struct let_s1 {
    uint8_t made;
    struct let_s2 f;
    int64_t answer;
};

struct let_s3 {
    uint8_t made;
    int64_t n;
};

struct let_s4 {
    int64_t n;
};

union let_u5 {
    int64_t f0;
    Handle f1;
};

struct let_s5 {
    int64_t tag;
    union let_u5 payload;
};

struct let_s1 let_module_init(void);

static uint8_t let_made_construct(void);

static struct let_s2 let_f_construct(uint8_t p1);

static struct let_s3 let_f_advance_0(struct let_s2 p1, int64_t p2);

static int64_t let_f_run(struct let_s3 p1);

static struct let_s4 let_made_advance_0(uint8_t p1, int64_t p2);

static Handle let_made_run(struct let_s4 p1);

Handle let_made_entry(struct let_s1 p1, int64_t p2);

int64_t let_f_entry(struct let_s1 p1, int64_t p2);

void let_module_unload(struct let_s1 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_made_construct();
        struct let_s2 v2 = let_f_construct(v1);
        struct let_s2 v4 = let_f_construct(v1);
        struct let_s3 v5 = let_f_advance_0(v4, INT64_C(1));
        int64_t v6 = let_f_run(v5);
        struct let_s1 v8 = ((struct let_s1){v1, v2, v6});
        return v8;
    }
}

static uint8_t let_made_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_f_construct(uint8_t p1) {
    {
        struct let_s2 v2 = ((struct let_s2){p1});
        return v2;
    }
}

static struct let_s3 let_f_advance_0(struct let_s2 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).made;
        struct let_s3 v4 = ((struct let_s3){v3, p2});
        return v4;
    }
}

static int64_t let_f_run(struct let_s3 p1) {
    {
        struct let_s5 b3_p1;
        int64_t b3_p2;
        int64_t b3_p3;
        struct let_s5 b3_p4;
        uint8_t b3_p5;
        struct let_s5 b4_p1;
        int64_t b4_p2;
        int64_t b4_p3;
        struct let_s5 b4_p4;
        uint8_t b4_p5;
        struct let_s5 b2_p1;
        int64_t b2_p2;
        int64_t b2_p3;
        struct let_s5 b2_p4;
        uint8_t b2_p5;
        uint8_t v2 = (p1).made;
        int64_t v3 = (p1).n;
        struct let_s4 v4 = let_made_advance_0(v2, v3);
        Handle v5 = let_made_run(v4);
        struct let_s5 v6 = ((struct let_s5){.tag = INT64_C(1), .payload = ((union let_u5){.f1 = v5})});
        {
            b3_p1 = v6;
            b3_p2 = v3;
            b3_p3 = v3;
            b3_p4 = v6;
            b3_p5 = v2;
            goto b3;
        }
b3:;
        int64_t b3_v6 = (b3_p1).tag;
        bool b3_v8 = (b3_v6 == INT64_C(1));
        if (b3_v8)
        {
            b4_p1 = b3_p1;
            b4_p2 = b3_p2;
            b4_p3 = b3_p3;
            b4_p4 = b3_p4;
            b4_p5 = b3_p5;
            goto b4;
        }
        else
        {
            b2_p1 = b3_p1;
            b2_p2 = b3_p2;
            b2_p3 = b3_p3;
            b2_p4 = b3_p4;
            b2_p5 = b3_p5;
            goto b2;
        }
b4:;
        Handle b4_v6 = ((b4_p1).payload).f1;
        release(b4_v6);
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            b2_p3 = b4_p3;
            b2_p4 = b4_p4;
            b2_p5 = b4_p5;
            goto b2;
        }
b2:;
        return b2_p2;
    }
}

static struct let_s4 let_made_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static Handle let_made_run(struct let_s4 p1) {
    {
        int64_t v2 = (p1).n;
        Handle v3 = made(v2);
        return v3;
    }
}

Handle let_made_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).made;
        struct let_s4 v4 = let_made_advance_0(v3, p2);
        Handle v5 = let_made_run(v4);
        return v5;
    }
}

int64_t let_f_entry(struct let_s1 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).f;
        struct let_s3 v4 = let_f_advance_0(v3, p2);
        int64_t v5 = let_f_run(v4);
        return v5;
    }
}

void let_module_unload(struct let_s1 p1) {
    {
        return;
    }
}

int64_t made_calls = 0, release_calls = 0;
Handle made(int64_t n) { made_calls = made_calls + 1; return (Handle){n}; }
void release(Handle h) { (void)h; release_calls = release_calls + 1; }
int main(void){ struct let_s1 m = let_module_init();
    printf("%lld made=%lld released=%lld\n", (long long)m.answer, (long long)made_calls, (long long)release_calls);
    return 0; }
