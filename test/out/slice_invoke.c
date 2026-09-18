#include <stdint.h>
#include <stdio.h>

struct let_s1 {
    uint8_t f;
    int64_t x;
};

struct let_s1 let_module_init(void);

static uint8_t let_f_construct(void);

static int64_t let_f_run(uint8_t p1);

int64_t let_f_entry(struct let_s1 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_f_construct();
        uint8_t v2 = let_f_construct();
        int64_t v3 = let_f_run(v2);
        struct let_s1 v4 = ((struct let_s1){v1, v3});
        return v4;
    }
}

static uint8_t let_f_construct(void) {
    {
        return INT64_C(0);
    }
}

static int64_t let_f_run(uint8_t p1) {
    {
        int64_t v3 = INT64_C(0);
        (*(&v3)) = INT64_C(1);
        int64_t v6 = (*(&v3));
        return v6;
    }
}

int64_t let_f_entry(struct let_s1 p1) {
    {
        uint8_t v2 = (p1).f;
        int64_t v3 = let_f_run(v2);
        return v3;
    }
}

int main(void){ printf("%lld\n", (long long)let_module_init().x); return 0; }
