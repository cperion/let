#include <stdint.h>
#include <stdio.h>

struct let_s2 {
    int64_t c;
};

struct let_s1 {
    int64_t c;
    struct let_s2 inc;
    int64_t a;
    int64_t b;
};

struct let_s3 {
    int64_t c;
    int64_t n;
};

struct let_s1 let_module_init(void);

static struct let_s2 let_inc_construct(int64_t* p1);

static struct let_s3 let_inc_advance_0(struct let_s2 p1, int64_t p2);

static int64_t let_inc_run(struct let_s3 p1);

int64_t let_inc_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        struct let_s2 v2 = let_inc_construct(INT64_C(0));
        struct let_s2 v4 = let_inc_construct(INT64_C(0));
        struct let_s3 v5 = let_inc_advance_0(v4, INT64_C(1));
        int64_t v6 = let_inc_run(v5);
        struct let_s2 v8 = let_inc_construct(INT64_C(0));
        struct let_s3 v9 = let_inc_advance_0(v8, INT64_C(1));
        int64_t v10 = let_inc_run(v9);
        int64_t v11 = (*INT64_C(0));
        struct let_s1 v12 = ((struct let_s1){v11, v2, v6, v10});
        return v12;
    }
}

static struct let_s2 let_inc_construct(int64_t* p1) {
    {
        struct let_s2 v2 = ((struct let_s2){p1});
        return v2;
    }
}

static struct let_s3 let_inc_advance_0(struct let_s2 p1, int64_t p2) {
    {
        int64_t v3 = (p1).c;
        struct let_s3 v4 = ((struct let_s3){v3, p2});
        return v4;
    }
}

static int64_t let_inc_run(struct let_s3 p1) {
    {
        int64_t v2 = (p1).c;
        int64_t v4 = (*v2);
        int64_t v6 = ((int64_t)(((uint64_t)v4) + ((uint64_t)INT64_C(1))));
        (*v2) = v6;
        int64_t v8 = (*v2);
        return v8;
    }
}

int64_t let_inc_entry(struct let_s1 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).inc;
        struct let_s3 v4 = let_inc_advance_0(v3, p2);
        int64_t v5 = let_inc_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("a=%lld b=%lld\n", (long long)m.a, (long long)m.b);
    return 0; }
