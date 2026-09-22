#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

struct let_val_1 {
    int64_t f0;
    int64_t f1;
};

struct let_val_2 {
    uint8_t f0;
    struct let_val_1 f1;
    int64_t f2;
    int64_t f3;
    struct let_val_1 f4;
    int64_t f5;
};

struct let_ret_1 {
    struct let_val_2 r0;
    struct let_val_2 r1;
};

struct let_ret_2 {
    int64_t r0;
    int64_t r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static struct let_ret_2 let_counter_3(int64_t p1_2);

static struct let_ret_2 let_counter_3_2(void);

static struct let_ret_2 let_counter_3_3(void);

static struct let_ret_2 let_counter_3_4(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        struct let_ret_2 v1_4_t = let_counter_3_2();
        struct let_ret_2 v1_6_t = let_counter_3_3();
        struct let_ret_2 v1_10_t = let_counter_3_4();
        return ((struct let_ret_1){((struct let_val_2){INT64_C(0), ((struct let_val_1){INT64_C(0), INT64_C(2)}), INT64_C(1), INT64_C(2), ((struct let_val_1){INT64_C(100), INT64_C(101)}), INT64_C(101)}), ((struct let_val_2){INT64_C(0), ((struct let_val_1){INT64_C(0), INT64_C(2)}), INT64_C(1), INT64_C(2), ((struct let_val_1){INT64_C(100), INT64_C(101)}), INT64_C(101)})});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static struct let_ret_2 let_counter_3(int64_t p1_2) {
    {
        goto b1;
b1:;
        int64_t v1_2_0 = LET_ADD(p1_2, INT64_C(1));
        print_int(v1_2_0);
        return ((struct let_ret_2){v1_2_0, v1_2_0});
    }
}

static struct let_ret_2 let_counter_3_2(void) {
    {
        goto b1;
b1:;
        print_int(INT64_C(1));
        return ((struct let_ret_2){INT64_C(1), INT64_C(1)});
    }
}

static struct let_ret_2 let_counter_3_3(void) {
    {
        goto b1;
b1:;
        print_int(INT64_C(2));
        return ((struct let_ret_2){INT64_C(2), INT64_C(2)});
    }
}

static struct let_ret_2 let_counter_3_4(void) {
    {
        goto b1;
b1:;
        print_int(INT64_C(101));
        return ((struct let_ret_2){INT64_C(101), INT64_C(101)});
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
