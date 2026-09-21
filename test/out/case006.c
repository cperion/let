#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>

extern int64_t say(const char * a1);

struct let_s2 {
    uint8_t say;
};

struct let_s1 {
    uint8_t say;
    struct let_s2 main;
};

struct let_s3 {
    const char * s;
};

struct let_s4 {
    const char * value;
};

struct let_s1 let_module_init(void);

static uint8_t let_say_construct(void);

static struct let_s2 let_main_construct(uint8_t p1);

int64_t let_say_entry(struct let_s1 p1, const char * p2);

static struct let_s3 let_say_advance_0(uint8_t p1, const char * p2);

static int64_t let_say_run(struct let_s3 p1);

uint8_t let_main_entry(struct let_s1 p1);

static uint8_t let_main_run(struct let_s2 p1);

static uint8_t let_ToCString_construct(void);

static struct let_s4 let_ToCString_advance_0(uint8_t p1, const char * p2);

static const char * let_ToCString_run(struct let_s4 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_say_construct();
        struct let_s2 v2 = let_main_construct(v1);
        struct let_s1 v3 = ((struct let_s1){v1, v2});
        return v3;
    }
}

static uint8_t let_say_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_main_construct(uint8_t p1) {
    {
        struct let_s2 v2 = ((struct let_s2){p1});
        return v2;
    }
}

int64_t let_say_entry(struct let_s1 p1, const char * p2) {
    {
        uint8_t v3 = (p1).say;
        struct let_s3 v4 = let_say_advance_0(v3, p2);
        int64_t v5 = let_say_run(v4);
        return v5;
    }
}

static struct let_s3 let_say_advance_0(uint8_t p1, const char * p2) {
    {
        struct let_s3 v3 = ((struct let_s3){p2});
        return v3;
    }
}

static int64_t let_say_run(struct let_s3 p1) {
    {
        const char * v2 = (p1).s;
        int64_t v3 = say(v2);
        return v3;
    }
}

uint8_t let_main_entry(struct let_s1 p1) {
    {
        struct let_s2 v2 = (p1).main;
        uint8_t v3 = let_main_run(v2);
        return v3;
    }
}

static uint8_t let_main_run(struct let_s2 p1) {
    {
        uint8_t v2 = (p1).say;
        uint8_t v4 = let_ToCString_construct();
        struct let_s4 v5 = let_ToCString_advance_0(v4, "\150\145\154\154\157\054\040\167\157\162\154\144");
        const char * v6 = let_ToCString_run(v5);
        struct let_s3 v7 = let_say_advance_0(v2, v6);
        int64_t v8 = let_say_run(v7);
        return INT64_C(0);
    }
}

static uint8_t let_ToCString_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s4 let_ToCString_advance_0(uint8_t p1, const char * p2) {
    {
        struct let_s4 v3 = ((struct let_s4){p2});
        return v3;
    }
}

static const char * let_ToCString_run(struct let_s4 p1) {
    {
        const char * v2 = (p1).value;
        const char * v3 = ((const char *)v2);
        return v3;
    }
}

#include <stdio.h>
int64_t say(const char *s) { puts(s); return 0; }
int main(void) { struct let_s1 m = let_module_init(); let_main_entry(m); return 0; }
