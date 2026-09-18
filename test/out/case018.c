#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s2 {
    int64_t f0;
    int64_t f1;
};

struct let_s1 {
    struct let_s2 t;
    int64_t answer;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        struct let_s2 v3 = ((struct let_s2){INT64_C(2), INT64_C(3)});
        int64_t v4 = (((struct let_s2){.f0 = INT64_C(2), .f1 = INT64_C(3)})).f0;
        int64_t v5 = (((struct let_s2){.f0 = INT64_C(2), .f1 = INT64_C(3)})).f1;
        int64_t v6 = ((int64_t)(((uint64_t)v4) + ((uint64_t)v5)));
        struct let_s1 v7 = ((struct let_s1){((struct let_s2){.f0 = INT64_C(2), .f1 = INT64_C(3)}), v6});
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
