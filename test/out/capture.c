#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

static struct let_val_1 v1_4_c;

struct let_val_1 {
    int64_t f0;
    int64_t f1;
};

struct let_val_2 {
    struct let_val_1* f0;
};

struct let_val_3 {
    int64_t f0;
    int64_t f1;
    int64_t f2;
};

struct let_val_4 {
    uint8_t f0;
    struct let_val_1* f1;
    struct let_val_2 f2;
    int64_t f3;
    int64_t f4;
    int64_t f5;
    struct let_val_3 f6;
    uint8_t f7;
};

struct let_ret_1 {
    struct let_val_4 r0;
    struct let_val_4 r1;
};

struct let_ret_2 {
    int64_t r0;
    int64_t r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static int64_t let_f_3(struct let_val_1* p1_1);

static struct let_ret_2 let_counter_4(int64_t p1_2);

static uint8_t let_show_5(int64_t p1_1, int64_t p1_2, int64_t p1_3);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        v1_4_c = ((struct let_val_1){INT64_C(0), INT64_C(0)});
        struct let_val_1* v1_4_0 = (&v1_4_c);
        struct let_val_1* v1_5_0 = v1_4_0;
        struct let_val_2 v1_6_0 = ((struct let_val_2){v1_5_0});
        int64_t v1_7_0 = let_f_3(v1_5_0);
        int64_t v1_8_0 = let_f_3(v1_5_0);
        struct let_val_1 v1_9_0 = (*v1_4_0);
        int64_t v1_10_0 = (v1_9_0).f0;
        int64_t v1_11_0 = (v1_9_0).f1;
        struct let_ret_2 v1_12_t = let_counter_4(v1_11_0);
        int64_t v1_12_0 = (v1_12_t).r0;
        int64_t v1_12_1 = (v1_12_t).r1;
        struct let_val_1 v1_13_0 = ((struct let_val_1){v1_10_0, v1_12_1});
        (*v1_4_0) = v1_13_0;
        struct let_val_3 v1_15_0 = ((struct let_val_3){v1_7_0, v1_8_0, v1_12_0});
        let_show_5(v1_7_0, v1_8_0, v1_12_0);
        struct let_val_4 v1_17_0 = ((struct let_val_4){INT64_C(0), v1_4_0, v1_6_0, v1_7_0, v1_8_0, v1_12_0, v1_15_0, INT64_C(0)});
        return ((struct let_ret_1){v1_17_0, v1_17_0});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static int64_t let_f_3(struct let_val_1* p1_1) {
    {
        goto b1;
b1:;
        struct let_val_1 v1_1_0 = (*p1_1);
        int64_t v1_2_0 = (v1_1_0).f0;
        int64_t v1_3_0 = (v1_1_0).f1;
        struct let_ret_2 v1_4_t = let_counter_4(v1_3_0);
        int64_t v1_4_0 = (v1_4_t).r0;
        int64_t v1_4_1 = (v1_4_t).r1;
        struct let_val_1 v1_5_0 = ((struct let_val_1){v1_2_0, v1_4_1});
        (*p1_1) = v1_5_0;
        return v1_4_0;
    }
}

static struct let_ret_2 let_counter_4(int64_t p1_2) {
    {
        goto b1;
b1:;
        int64_t v1_2_0 = LET_ADD(p1_2, INT64_C(1));
        return ((struct let_ret_2){v1_2_0, v1_2_0});
    }
}

static uint8_t let_show_5(int64_t p1_1, int64_t p1_2, int64_t p1_3) {
    {
        goto b1;
b1:;
        print_int(p1_1);
        print_int(p1_2);
        print_int(p1_3);
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
