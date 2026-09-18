#include <stdint.h>
#include <stdio.h>

struct let_s1 {
    int64_t n;
    int64_t* c;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        int64_t v3 = INT64_C(0);
        struct let_s1 v4 = ((struct let_s1){INT64_C(7), (&v3)});
        return v4;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.n);
    return 0; }

