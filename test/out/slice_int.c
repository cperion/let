#include <stdint.h>
#include <stdio.h>

struct let_s1 {
    int64_t answer;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        return ((struct let_s1){.answer = INT64_C(42)});
    }
}

int main(void){ printf("%lld\n", (long long)let_module_init().answer); return 0; }
