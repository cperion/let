#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <string.h>

struct let_s1 {
    uint8_t size;
    int64_t answer;
};

struct let_s2 {
    int64_t n;
};

struct let_s3 {
    const char * value;
};

struct let_s1 let_module_init(void);

static uint8_t let_size_construct(void);

static struct let_s2 let_size_advance_0(uint8_t p1, int64_t p2);

static int64_t let_size_run(struct let_s2 p1);

static uint8_t let_TextSize_construct(void);

static struct let_s3 let_TextSize_advance_0(uint8_t p1, const char * p2);

static int64_t let_TextSize_run(struct let_s3 p1);

int64_t let_size_entry(struct let_s1 p1, int64_t p2);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_size_construct();
        uint8_t v3 = let_size_construct();
        struct let_s2 v4 = let_size_advance_0(v3, INT64_C(1));
        int64_t v5 = let_size_run(v4);
        struct let_s1 v6 = ((struct let_s1){v1, v5});
        return v6;
    }
}

static uint8_t let_size_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_size_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static int64_t let_size_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).n;
        uint8_t v4 = let_TextSize_construct();
        struct let_s3 v5 = let_TextSize_advance_0(v4, "\150\145\154\154\157");
        int64_t v6 = let_TextSize_run(v5);
        int64_t v7 = ((int64_t)(((uint64_t)v6) + ((uint64_t)v2)));
        return v7;
    }
}

static uint8_t let_TextSize_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s3 let_TextSize_advance_0(uint8_t p1, const char * p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static int64_t let_TextSize_run(struct let_s3 p1) {
    {
        const char * v2 = (p1).value;
        int64_t v3 = ((int64_t)strlen(v2));
        return v3;
    }
}

int64_t let_size_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).size;
        struct let_s2 v4 = let_size_advance_0(v3, p2);
        int64_t v5 = let_size_run(v4);
        return v5;
    }
}

int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
