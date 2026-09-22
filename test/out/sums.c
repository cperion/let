#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

struct let_val_1 {
    uint8_t f0;
    uint8_t f1;
};

struct let_val_2 {
    int64_t f0;
    int64_t f1;
    int64_t f2;
};

struct let_ret_1 {
    struct let_val_1 r0;
    struct let_val_1 r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static uint8_t let_run_3(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        let_run_3();
        return ((struct let_ret_1){((struct let_val_1){INT64_C(0), INT64_C(0)}), ((struct let_val_1){INT64_C(0), INT64_C(0)})});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static uint8_t let_run_3(void) {
    {
        struct let_val_2 p3_3;
        int64_t p3_4;
        struct let_val_2 p4_3;
        struct let_val_2 p5_3;
        struct let_val_2 p6_3;
        goto b1;
b1:;
        {
            goto b2;
        }
b2:;
        print_int(INT64_C(65));
        {
            goto b7;
        }
b7:;
        {
            goto b9;
        }
b9:;
        {
            goto b10;
        }
b10:;
        print_int(INT64_C(66));
        {
            goto b12;
        }
b12:;
        {
            goto b13;
        }
b13:;
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

int main(void){ let_module_init(); return 0; }
