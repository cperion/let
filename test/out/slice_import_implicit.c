#include <stdint.h>
#include <stdio.h>

struct let_s2 {
    int64_t width;
    int64_t height;
};

struct let_s1 {
    struct let_s2 codec;
    int64_t area;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        int64_t v4 = (((struct let_s2){.width = INT64_C(8), .height = INT64_C(4)})).width;
        int64_t v5 = (((struct let_s2){.width = INT64_C(8), .height = INT64_C(4)})).height;
        int64_t v6 = ((int64_t)(((uint64_t)v4) * ((uint64_t)v5)));
        struct let_s1 v7 = ((struct let_s1){((struct let_s2){.width = INT64_C(8), .height = INT64_C(4)}), v6});
        return v7;
    }
}

int main(void){ printf("%lld\n", (long long)let_module_init().area); return 0; }
