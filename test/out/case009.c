#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s1 {
    uint8_t f;
    int64_t answer;
};

struct let_s2 {
    int64_t n;
};

struct let_s3 {
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_f_construct(void);

static struct let_s2 let_f_advance_0(uint8_t p1, int64_t p2);

static int64_t let_f_run(struct let_s2 p1);

int64_t let_f_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_f_construct();
        uint8_t v3 = let_f_construct();
        struct let_s2 v4 = let_f_advance_0(v3, INT64_C(0));
        int64_t v5 = let_f_run(v4);
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
    }
}

static uint8_t let_f_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_f_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_f_run(struct let_s2 p1) {
    {
        struct let_s3 v4 = ((struct let_s3){INT64_C(1)});
        struct let_s3 v5 = ((struct let_s3){.x = INT64_C(1)});
        ((*(&v5))).x = INT64_C(9);
        int64_t* v8 = (&((*(&v5))).x);
        int64_t v9 = (*v8);
        return v9;
    }
}

int64_t let_f_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).f;
        struct let_s2 v4 = let_f_advance_0(v3, p2);
        int64_t v5 = let_f_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
