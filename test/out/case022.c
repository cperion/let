#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
typedef struct { int64_t tag; } Handle;

#include <stdint.h>

extern void release(Handle a1);

extern Handle made(int64_t a1);

struct let_s1 {
    Handle x;
};

struct let_s2 {
    int64_t n;
};

struct let_s1 let_module_init(void);

static uint8_t let_made_construct(void);

static struct let_s2 let_made_advance_0(uint8_t p1, int64_t p2);

static Handle let_made_run(struct let_s2 p1);

void let_module_unload(struct let_s1 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_made_construct();
        uint8_t v3 = let_made_construct();
        struct let_s2 v4 = let_made_advance_0(v3, INT64_C(1));
        Handle v5 = let_made_run(v4);
        struct let_s1 v8 = ((struct let_s1){v5});
        return v8;
    }
}

static uint8_t let_made_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_made_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s2 v3 = ((struct let_s2){p2});
        return v3;
    }
}

static Handle let_made_run(struct let_s2 p1) {
    {
        int64_t v2 = (p1).n;
        Handle v3 = made(v2);
        return v3;
    }
}

void let_module_unload(struct let_s1 p1) {
    {
        Handle v2 = (p1).x;
        release(v2);
        return;
    }
}

int64_t made_calls = 0, release_calls = 0;
Handle made(int64_t n) { made_calls = made_calls + 1; return (Handle){n}; }
void release(Handle h) { (void)h; release_calls = release_calls + 1; }
int main(void){ struct let_s1 m = let_module_init(); let_module_unload(m);
    printf("made=%lld released=%lld\n", (long long)made_calls, (long long)release_calls);
    return 0; }
