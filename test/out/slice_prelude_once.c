#include <stdint.h>
#include <stdio.h>

extern int64_t tick(int64_t a1);

struct let_s2 {
    int64_t k;
};

struct let_s1 {
    uint8_t tick;
    int64_t k;
    struct let_s2 f;
    int64_t a;
};

struct let_s3 {
    int64_t n;
};

struct let_s4 {
    int64_t k;
    int64_t n;
};

struct let_s1 let_module_init(void);

static uint8_t let_tick_construct(void);

static struct let_s3 let_tick_advance_0(uint8_t p1, int64_t p2);

static int64_t let_tick_run(struct let_s3 p1);

static struct let_s2 let_f_construct(int64_t p1);

static struct let_s4 let_f_advance_0(struct let_s2 p1, int64_t p2);

static int64_t let_f_run(struct let_s4 p1);

int64_t let_tick_entry(struct let_s1 p1, int64_t p2);

int64_t let_f_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_tick_construct();
        uint8_t v3 = let_tick_construct();
        struct let_s3 v4 = let_tick_advance_0(v3, INT64_C(1));
        int64_t v5 = let_tick_run(v4);
        struct let_s2 v6 = let_f_construct(v5);
        struct let_s2 v8 = let_f_construct(v5);
        struct let_s4 v9 = let_f_advance_0(v8, INT64_C(1));
        int64_t v10 = let_f_run(v9);
        struct let_s1 v11 = ((struct let_s1){v1, v5, v6, v10});
        return v11;
    }
}

static uint8_t let_tick_construct(void) {
    {
        return INT64_C(0);
    }
}

static struct let_s3 let_tick_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static int64_t let_tick_run(struct let_s3 p1) {
    {
        int64_t v2 = (p1).n;
        int64_t v3 = tick(v2);
        return v3;
    }
}

static struct let_s2 let_f_construct(int64_t p1) {
    {
        struct let_s2 v2 = ((struct let_s2){p1});
        return v2;
    }
}

static struct let_s4 let_f_advance_0(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).k;
        struct let_s4 v4 = ((struct let_s4){v3, p2});
        return v4;
    }
}

static int64_t let_f_run(struct let_s4 p1) {
    {
        int64_t v2 = (p1).k;
        int64_t v3 = (p1).n;
        int64_t v4 = ((int64_t)(((uint64_t)v3) + ((uint64_t)v2)));
        return v4;
    }
}

int64_t let_tick_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).tick;
        struct let_s3 v4 = let_tick_advance_0(v3, p2);
        int64_t v5 = let_tick_run(v4);
        return v5;
    }
}

int64_t let_f_entry(struct let_s1 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).f;
        struct let_s4 v4 = let_f_advance_0(v3, p2);
        int64_t v5 = let_f_run(v4);
        return v5;
    }
}

int64_t tick_calls = 0;
int64_t tick(int64_t n) { tick_calls = tick_calls + 1; return n + 39; }
int main(void){ struct let_s1 m = let_module_init();
    printf("%lld tick_calls=%lld\n", (long long)m.a, (long long)tick_calls);
    return 0; }

