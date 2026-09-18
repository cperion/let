#include <stdint.h>
#include <stdio.h>

struct let_s1 {
    const char * greeting;
    int64_t hexed;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        return ((struct let_s1){.greeting = "\150\145\154\154\157\011\167\157\162\154\144", .hexed = INT64_C(256)});
    }
}

int main(void){ struct let_s1 m = let_module_init(); printf("%s %lld\n", (const char*)m.greeting, (long long)m.hexed); return 0; }
