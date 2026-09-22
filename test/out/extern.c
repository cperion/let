#include <stddef.h>
#include <stdbool.h>
#include <inttypes.h>

struct let_text {
    char* data;
    uint64_t size;
};

extern void let_trap(char* reason);

struct let_val_1 {
    int64_t f0;
    uint8_t f1;
};

struct let_ret_1 {
    struct let_val_1 r0;
    struct let_val_1 r1;
};

extern int64_t ffi_len(const char* a1);

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        const char* v1_2_0 = (((struct let_text){"\150\145\154\154\157", INT64_C(5)})).data;
        int64_t v1_3_0 = ((int64_t)ffi_len(v1_2_0));
        print_int(v1_3_0);
        struct let_val_1 v1_5_0 = ((struct let_val_1){v1_3_0, INT64_C(0)});
        return ((struct let_ret_1){v1_5_0, v1_5_0});
    }
}

static uint8_t let_module_unload(void) {
    {
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

#include <string.h>
int64_t ffi_len(const char* text){ return (int64_t)strlen(text); }
int main(void){ let_module_init(); return 0; }

