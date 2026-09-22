#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

struct let_val_1 {
    int64_t f0;
};

struct let_val_2 {
    int64_t f0;
    int64_t f1;
};

struct let_ret_1 {
    struct let_val_1 r0;
    struct let_val_2 r1;
};

extern void close(int64_t a0);

extern int64_t open(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(struct let_val_2 p1_1);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        int64_t v1_2_0 = open(INT64_C(1));
        int64_t v1_4_0 = open(INT64_C(2));
        int64_t v1_5_0 = v1_2_0;
        struct let_val_1 v1_6_0 = ((struct let_val_1){v1_5_0});
        struct let_val_2 v1_7_0 = ((struct let_val_2){v1_2_0, v1_4_0});
        return ((struct let_ret_1){v1_6_0, v1_7_0});
    }
}

static uint8_t let_module_unload(struct let_val_2 p1_1) {
    {
        goto b1;
b1:;
        int64_t v1_1_0 = (p1_1).f1;
        close(v1_1_0);
        int64_t v1_3_0 = (p1_1).f0;
        close(v1_3_0);
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

int main(void){ struct let_ret_1 m = let_module_init(); let_module_unload(m.r1); return 0; }
