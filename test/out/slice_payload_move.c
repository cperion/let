#include <stdint.h>
#include <stdbool.h>
#include "sum_payload.h"
#include <stdio.h>

extern Slot slot(int64_t a1);

extern void release(Handle a1);

extern Handle made(int64_t a1);

extern void drop(Slot a1);

struct let_s1 {
    uint8_t made;
    uint8_t slot;
    uint8_t f;
    int64_t a;
    int64_t b;
};

struct let_s2 {
    int64_t n;
};

union let_u4 {
    Handle f0;
    Slot f1;
};

struct let_s4 {
    int64_t tag;
    union let_u4 payload;
};

struct let_s3 {
    struct let_s4 v;
};

struct let_s1 let_module_init(void);

static uint8_t let_made_construct(void);

static uint8_t let_slot_construct(void);

static uint8_t let_f_construct(void);

static struct let_s2 let_made_advance_0(uint8_t p1, int64_t p2);

static Handle let_made_run(struct let_s2 p1);

static struct let_s3 let_f_advance_0(uint8_t p1, struct let_s4 p2);

static int64_t let_f_run(struct let_s3 p1);

static struct let_s2 let_slot_advance_0(uint8_t p1, int64_t p2);

static Slot let_slot_run(struct let_s2 p1);

Handle let_made_entry(struct let_s1 p1, int64_t p2);

Slot let_slot_entry(struct let_s1 p1, int64_t p2);

int64_t let_f_entry(struct let_s1 p1, struct let_s4 p2);

void let_module_unload(struct let_s1 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_made_construct();
        uint8_t v2 = let_slot_construct();
        uint8_t v3 = let_f_construct();
        uint8_t v5 = let_made_construct();
        struct let_s2 v6 = let_made_advance_0(v5, INT64_C(1));
        Handle v7 = let_made_run(v6);
        struct let_s4 v8 = ((struct let_s4){.tag = INT64_C(0), .payload = ((union let_u4){.f0 = v7})});
        uint8_t v9 = let_f_construct();
        struct let_s3 v10 = let_f_advance_0(v9, v8);
        int64_t v11 = let_f_run(v10);
        uint8_t v13 = let_slot_construct();
        struct let_s2 v14 = let_slot_advance_0(v13, INT64_C(2));
        Slot v15 = let_slot_run(v14);
        struct let_s4 v16 = ((struct let_s4){.tag = INT64_C(1), .payload = ((union let_u4){.f1 = v15})});
        uint8_t v17 = let_f_construct();
        struct let_s3 v18 = let_f_advance_0(v17, v16);
        int64_t v19 = let_f_run(v18);
        struct let_s1 v22 = ((struct let_s1){v1, v2, v3, v11, v19});
        return v22;
    }
}

static uint8_t let_made_construct(void) {
    {
        return INT64_C(0);
    }
}

static uint8_t let_slot_construct(void) {
    {
        return INT64_C(0);
    }
}

static uint8_t let_f_construct(void) {
    {
        return INT64_C(0);
    }
}

static struct let_s2 let_made_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static Handle let_made_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).n;
        Handle v3 = made(v2);
        return v3;
    }
}

static struct let_s3 let_f_advance_0(uint8_t p1, struct let_s4 p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static int64_t let_f_run(struct let_s3 p1) {
    {
        struct let_s4 b5_p1;
        struct let_s4 b5_p2;
        struct let_s4 b6_p1;
        struct let_s4 b6_p2;
        struct let_s4 b2_p1;
        struct let_s4 b2_p2;
        struct let_s4 b4_p1;
        struct let_s4 b4_p2;
        struct let_s4 b3_p1;
        struct let_s4 b3_p2;
        struct let_s4 v2 = (p1).v;
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
        Slot b4_v3 = ((b4_p1).payload).f1;
        drop(b4_v3);
        return INT64_C(2);
b3:;
        Handle b3_v3 = ((b3_p1).payload).f0;
        release(b3_v3);
        return INT64_C(1);
    }
}

static struct let_s2 let_slot_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static Slot let_slot_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).n;
        Slot v3 = slot(v2);
        return v3;
    }
}

Handle let_made_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).made;
        struct let_s2 v4 = let_made_advance_0(v3, p2);
        Handle v5 = let_made_run(v4);
        return v5;
    }
}

Slot let_slot_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).slot;
        struct let_s2 v4 = let_slot_advance_0(v3, p2);
        Slot v5 = let_slot_run(v4);
        return v5;
    }
}

int64_t let_f_entry(struct let_s1 p1, struct let_s4 p2) {
    {
        uint8_t v3 = (p1).f;
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

int64_t made_calls = 0, release_calls = 0, slot_calls = 0, drop_calls = 0;
Handle made(int64_t n) { made_calls = made_calls + 1; return (Handle){n}; }
void release(Handle h) { (void)h; release_calls = release_calls + 1; }
Slot slot(int64_t n) { slot_calls = slot_calls + 1; return (Slot){n}; }
void drop(Slot s) { (void)s; drop_calls = drop_calls + 1; }
int main(void){ struct let_s1 m = let_module_init();
    printf("%lld %lld made=%lld released=%lld slot=%lld dropped=%lld\n", (long long)m.a, (long long)m.b,
        (long long)made_calls, (long long)release_calls, (long long)slot_calls, (long long)drop_calls);
    return 0; }

