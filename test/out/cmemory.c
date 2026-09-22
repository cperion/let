#include <stddef.h>
#include <stdbool.h>
#include <inttypes.h>

struct let_text {
    char* data;
    uint64_t size;
};

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

struct let_val_1 {
    void* f0;
    void* f1;
    int64_t f2;
    int64_t f3;
};

struct let_ret_1 {
    struct let_val_1 r0;
    struct let_val_1 r1;
};

extern void free(void* a0);

extern void * malloc(size_t a1);

extern int memcmp(const void * a1, const void * a2, size_t a3);

extern void * memcpy(void * a1, const void * a2, size_t a3);

extern int putchar(int a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(struct let_val_1 p1_1);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        void* v1_2_0 = malloc(((size_t)INT64_C(6)));
        const char* v1_4_0 = (((struct let_text){"\150\145\154\154\157", INT64_C(5)})).data;
        void* v1_6_0 = memcpy(v1_2_0, v1_4_0, ((size_t)INT64_C(6)));
        const char* v1_8_0 = (((struct let_text){"\150\145\154\154\157", INT64_C(5)})).data;
        int64_t v1_10_0 = ((int64_t)memcmp(v1_2_0, v1_8_0, ((size_t)INT64_C(6))));
        int64_t v1_12_0 = LET_ADD(INT64_C(48), v1_10_0);
        int64_t v1_13_0 = ((int64_t)putchar(((int)v1_12_0)));
        struct let_val_1 v1_14_0 = ((struct let_val_1){v1_2_0, v1_6_0, v1_10_0, v1_13_0});
        return ((struct let_ret_1){v1_14_0, v1_14_0});
    }
}

static uint8_t let_module_unload(struct let_val_1 p1_1) {
    {
        goto b1;
b1:;
        void* v1_1_0 = (p1_1).f0;
        free(v1_1_0);
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

struct let_text mark(struct let_text text){ fwrite(text.data,1,(size_t)text.size,stdout); fputc('\n',stdout); return text; }

void let_trap(char* reason){ fputs("trap: ",stderr); fputs(reason,stderr); fputc('\n',stderr); abort(); }

int main(void){ let_module_init(); return 0; }
