#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s2 {
    int64_t a;
};

struct let_s1 {
    struct let_s2 b;
    int64_t answer;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        struct let_s2 v2 = ((struct let_s2){INT64_C(1)});
        int64_t v3 = (((struct let_s2){.a = INT64_C(1)})).a;
        struct let_s1 v4 = ((struct let_s1){((struct let_s2){.a = INT64_C(1)}), v3});
        return v4;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
