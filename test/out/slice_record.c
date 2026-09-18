#include <stdint.h>
#include <stdio.h>

struct let_s2 {
    int64_t x;
    int64_t y;
};

struct let_s1 {
    struct let_s2 r;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        return ((struct let_s1){.r = ((struct let_s2){.x = INT64_C(1), .y = INT64_C(2)})});
    }
}

int main(void){ printf("%lld %lld\n", (long long)let_module_init().r.x, (long long)let_module_init().r.y); return 0; }
