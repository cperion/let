#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

struct let_val_1 {
    uint8_t f0;
    uint8_t f1;
};

struct let_val_2 {
    int64_t f0;
    int64_t f1;
};

struct let_val_3 {
    int64_t f0;
    int64_t f1;
    int64_t f2;
};

struct let_val_4 {
    struct let_val_1 f0;
    struct let_val_2 f1;
    struct let_val_3 f2;
};

struct let_val_5 {
    struct let_val_1 f0;
    struct let_val_2 f1;
    struct let_val_3 f2;
    struct let_val_4 f3;
    uint8_t f4;
};

struct let_ret_1 {
    struct let_val_5 r0;
    struct let_val_5 r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static uint8_t let_show_3(struct let_val_1 p1_1, struct let_val_2 p1_2, struct let_val_3 p1_3);

static uint8_t let_show_3_2(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        let_show_3_2();
        return ((struct let_ret_1){((struct let_val_5){((struct let_val_1){INT64_C(0), INT64_C(0)}), ((struct let_val_2){INT64_C(10), INT64_C(20)}), ((struct let_val_3){INT64_C(255), INT64_C(128), INT64_C(32)}), ((struct let_val_4){((struct let_val_1){INT64_C(0), INT64_C(0)}), ((struct let_val_2){INT64_C(10), INT64_C(20)}), ((struct let_val_3){INT64_C(255), INT64_C(128), INT64_C(32)})}), INT64_C(0)}), ((struct let_val_5){((struct let_val_1){INT64_C(0), INT64_C(0)}), ((struct let_val_2){INT64_C(10), INT64_C(20)}), ((struct let_val_3){INT64_C(255), INT64_C(128), INT64_C(32)}), ((struct let_val_4){((struct let_val_1){INT64_C(0), INT64_C(0)}), ((struct let_val_2){INT64_C(10), INT64_C(20)}), ((struct let_val_3){INT64_C(255), INT64_C(128), INT64_C(32)})}), INT64_C(0)})});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static uint8_t let_show_3(struct let_val_1 p1_1, struct let_val_2 p1_2, struct let_val_3 p1_3) {
    {
        goto b1;
b1:;
        print_int(INT64_C(42));
        int64_t v1_8_0 = (p1_2).f0;
        int64_t v1_9_0 = (p1_2).f1;
        int64_t v1_10_0 = LET_ADD(v1_8_0, v1_9_0);
        print_int(v1_10_0);
        int64_t v1_12_0 = (p1_3).f1;
        print_int(v1_12_0);
        return INT64_C(0);
    }
}

static uint8_t let_show_3_2(void) {
    {
        goto b1;
b1:;
        print_int(INT64_C(42));
        print_int(INT64_C(30));
        print_int(INT64_C(128));
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
