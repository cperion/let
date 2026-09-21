#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

struct let_s3 {
    int64_t value;
};

struct let_s2 {
    struct let_s3 value;
};

struct let_s1 {
    struct let_s2 c;
    int64_t answer;
};

struct let_s1 let_module_init(void);

struct let_s1 let_module_init(void) {
    {
        struct let_s3 v2 = ((struct let_s3){INT64_C(1)});
        struct let_s2 v3 = ((struct let_s2){((struct let_s3){.value = INT64_C(1)})});
        struct let_s3 v4 = (((struct let_s2){.value = ((struct let_s3){.value = INT64_C(1)})})).value;
        int64_t v5 = (v4).value;
        struct let_s1 v6 = ((struct let_s1){((struct let_s2){.value = ((struct let_s3){.value = INT64_C(1)})}), v5});
        return v6;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
