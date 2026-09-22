#include <stddef.h>
#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

struct let_val_1 {
    uint8_t f0;
    int64_t f1;
    int64_t f2;
    int64_t f3;
};

struct let_ret_1 {
    struct let_val_1 r0;
    struct let_val_1 r1;
};

extern void ffi_release(void* a0);

extern void * ffi_alloc(size_t a1);

extern int ffi_released(void);

extern int putchar(int a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static int64_t let_allocate_3(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        let_allocate_3();
        int64_t v1_3_0 = ((int64_t)ffi_released());
        int64_t v1_5_0 = LET_ADD(INT64_C(48), v1_3_0);
        int64_t v1_6_0 = ((int64_t)putchar(((int)v1_5_0)));
        struct let_val_1 v1_7_0 = ((struct let_val_1){INT64_C(0), INT64_C(0), v1_3_0, v1_6_0});
        return ((struct let_ret_1){v1_7_0, v1_7_0});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static int64_t let_allocate_3(void) {
    {
        goto b1;
b1:;
        void* v1_2_0 = ffi_alloc(((size_t)INT64_C(8)));
        void* v1_4_0 = ffi_alloc(((size_t)INT64_C(16)));
        ffi_release(v1_4_0);
        ffi_release(v1_2_0);
        return INT64_C(0);
    }
}

#include <stdio.h>
#include <stdlib.h>
int64_t runtime_int(int64_t value){ return value; }
int64_t open(int64_t value){ printf("open:%lld\n",(long long)value); return value; }
void close(int64_t value){ printf("close:%lld\n",(long long)value); }
int64_t open_buffer(int64_t n){ printf("open:%lld\n",(long long)n); return 7; }
void write_byte(int64_t* buffer,int64_t index,int64_t value){ printf("write:%lld:%lld\n",(long long)index,(long long)value); }
void consume_buffer(int64_t buffer){ printf("consume:%lld\n",(long long)buffer); }
void close_buffer(int64_t buffer){ printf("close_buffer:%lld\n",(long long)buffer); }
void print_bool(bool value){ printf("%d\n",value?1:0); }
void print_int(int64_t value){ printf("%lld\n",(long long)value); }


void let_trap(char* reason){ fputs("trap: ",stderr); fputs(reason,stderr); fputc('\n',stderr); abort(); }

static int tracked_released=0;
void* ffi_alloc(size_t n){ return malloc(n); }
void ffi_release(void* p){ ++tracked_released; free(p); }
int ffi_released(void){ return tracked_released; }
int main(void){ let_module_init(); return 0; }

