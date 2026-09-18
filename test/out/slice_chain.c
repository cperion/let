#include <stdint.h>
#include <stdio.h>

struct let_s2 {
    int64_t base;
};

struct let_s1 {
    struct let_s2 id;
    int64_t result;
};

struct let_s3 {
    int64_t base;
    int64_t x;
    int64_t y;
};

struct let_s1 let_module_init(void);

static struct let_s2 let_id_construct(void);

static struct let_s3 let_id_advance_0(struct let_s2 p1, int64_t p2);

static int64_t let_id_run(struct let_s3 p1);

int64_t let_id_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        struct let_s2 v1 = let_id_construct();
        struct let_s2 v3 = let_id_construct();
        struct let_s3 v4 = let_id_advance_0(v3, INT64_C(5));
        int64_t v5 = let_id_run(v4);
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
    }
}

static struct let_s2 let_id_construct(void) {
    {
        return ((struct let_s2){.base = INT64_C(0)});
    }
}

static struct let_s3 let_id_advance_0(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).base;
        struct let_s3 v4 = ((struct let_s3){v3, p2, p2});
        return v4;
    }
}

static int64_t let_id_run(struct let_s3 p1) {
    {
        int64_t v4 = (p1).y;
        return v4;
    }
}

int64_t let_id_entry(struct let_s1 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).id;
        struct let_s3 v4 = let_id_advance_0(v3, p2);
        int64_t v5 = let_id_run(v4);
        return v5;
    }
}

int main(void){ printf("%lld\n", (long long)let_module_init().result); return 0; }
