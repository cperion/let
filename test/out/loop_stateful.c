#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

struct let_val_1 {
    int64_t f0;
};

struct let_val_2 {
    uint8_t f0;
    int64_t f1;
    struct let_val_1 f2;
    uint8_t f3;
};

struct let_val_3 {
    int64_t f0;
    int64_t f1;
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

extern int64_t runtime_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static int64_t let_run_3(void);

static uint8_t let_show_5(int64_t p1_1);

static struct let_ret_2 let_counter_4(int64_t p1_2);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        int64_t v1_2_0 = let_run_3();
        struct let_val_1 v1_3_0 = ((struct let_val_1){v1_2_0});
        let_show_5(v1_2_0);
        struct let_val_2 v1_5_0 = ((struct let_val_2){INT64_C(0), v1_2_0, v1_3_0, INT64_C(0)});
        return ((struct let_ret_1){v1_5_0, v1_5_0});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static int64_t let_run_3(void) {
    {
        struct let_val_3 p2_2;
        int64_t p2_4;
        int64_t p2_5;
        struct let_val_3 p3_2;
        int64_t p3_4;
        int64_t p3_5;
        int64_t p4_4;
        int64_t p5_5;
        int64_t p6_5;
        int64_t p7_5;
        goto b1;
b1:;
        int64_t v1_3_0 = runtime_int(INT64_C(0));
        struct let_val_3 v1_4_0 = ((struct let_val_3){v1_3_0, v1_3_0});
        {
            struct let_val_3 v1_8_e3 = v1_4_0;
            int64_t v1_8_e5 = INT64_C(0);
            int64_t v1_8_e6 = INT64_C(0);
            p2_2 = v1_8_e3;
            p2_4 = v1_8_e5;
            p2_5 = v1_8_e6;
            goto b2;
        }
b2:;
        int64_t v2_2_0 = runtime_int(INT64_C(4));
        bool v2_3_0 = (p2_5 < v2_2_0);
        if (v2_3_0)
        {
            struct let_val_3 v2_9_e3 = p2_2;
            int64_t v2_9_e5 = p2_4;
            int64_t v2_9_e6 = p2_5;
            p3_2 = v2_9_e3;
            p3_4 = v2_9_e5;
            p3_5 = v2_9_e6;
            goto b3;
        }
        else
        {
            int64_t v2_9_e5 = p2_4;
            p4_4 = v2_9_e5;
            goto b4;
        }
b3:;
        int64_t v3_1_0 = (p3_2).f0;
        int64_t v3_2_0 = (p3_2).f1;
        struct let_ret_2 v3_3_t = let_counter_4(v3_2_0);
        int64_t v3_3_0 = (v3_3_t).r0;
        int64_t v3_3_1 = (v3_3_t).r1;
        struct let_val_3 v3_4_0 = ((struct let_val_3){v3_1_0, v3_3_1});
        int64_t v3_5_0 = LET_ADD(p3_4, v3_3_0);
        int64_t v3_7_0 = LET_ADD(p3_5, INT64_C(1));
        {
            struct let_val_3 v3_14_e3 = v3_4_0;
            int64_t v3_14_e5 = v3_5_0;
            int64_t v3_14_e6 = v3_7_0;
            p2_2 = v3_14_e3;
            p2_4 = v3_14_e5;
            p2_5 = v3_14_e6;
            goto b2;
        }
b4:;
        {
            int64_t v4_6_e6 = p4_4;
            p5_5 = v4_6_e6;
            goto b5;
        }
b5:;
        {
            int64_t v5_7_e6 = p5_5;
            p7_5 = v5_7_e6;
            goto b7;
        }
b7:;
        return p7_5;
    }
}

static uint8_t let_show_5(int64_t p1_1) {
    {
        goto b1;
b1:;
        print_int(p1_1);
        return INT64_C(0);
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
