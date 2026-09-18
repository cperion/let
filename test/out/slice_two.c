#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

struct let_s1 {
    int64_t a;
    bool flag;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        return ((struct let_s1){.a = INT64_C(1), .flag = true});
    }
}

int main(void){ printf("%lld %d\n", (long long)let_module_init().a, (int)let_module_init().flag); return 0; }
