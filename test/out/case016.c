#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

extern double half(double a1);

struct let_s1 {
    uint8_t half;
    double answer;
};

struct let_s2 {
    double x;
};

struct let_s1 let_module_init(void);

static uint8_t let_half_construct(void);

static struct let_s2 let_half_advance_0(uint8_t p1, double p2);

static double let_half_run(struct let_s2 p1);

double let_half_entry(struct let_s1 p1, double p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_half_construct();
        double v2 = 0x1.4p+2;
        uint8_t v3 = let_half_construct();
        struct let_s2 v4 = let_half_advance_0(v3, v2);
        double v5 = let_half_run(v4);
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
    }
}

static uint8_t let_half_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_half_advance_0(uint8_t p1, double p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static double let_half_run(struct let_s2 p1) {
    {
        double v2 = (p1).x;
        double v3 = half(v2);
        return v3;
    }
}

double let_half_entry(struct let_s1 p1, double p2) {
    {
        uint8_t v3 = (p1).half;
        struct let_s2 v4 = let_half_advance_0(v3, p2);
        double v5 = let_half_run(v4);
        return v5;
    }
}

double half(double x) { return x / 2.0; }
int main(void){ struct let_s1 m = let_module_init(); printf("%g\n", m.answer); return 0; }
