#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s2 {
    int64_t a;
    int64_t c;
};

struct let_s1 {
    struct let_s2 x;
    int64_t answer;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        struct let_s2 v3 = ((struct let_s2){INT64_C(1), INT64_C(2)});
        int64_t v4 = (((struct let_s2){.a = INT64_C(1), .c = INT64_C(2)})).a;
        int64_t v5 = (((struct let_s2){.a = INT64_C(1), .c = INT64_C(2)})).c;
        int64_t v6 = ((int64_t)(((uint64_t)v4) + ((uint64_t)v5)));
        struct let_s1 v7 = ((struct let_s1){((struct let_s2){.a = INT64_C(1), .c = INT64_C(2)}), v6});
        return v7;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
