#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

struct let_val_1 {
    uint8_t f0;
    uint8_t f1;
};

struct let_ret_1 {
    struct let_val_1 r0;
    struct let_val_1 r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static uint8_t let_compute_3(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        let_compute_3();
        return ((struct let_ret_1){((struct let_val_1){INT64_C(0), INT64_C(0)}), ((struct let_val_1){INT64_C(0), INT64_C(0)})});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static uint8_t let_compute_3(void) {
    {
        int64_t p2_1;
        int64_t p2_2;
        int64_t p3_1;
        int64_t p3_2;
        int64_t p4_2;
        int64_t p5_1;
        int64_t p5_2;
        int64_t p6_1;
        int64_t p6_2;
        int64_t p7_1;
        int64_t p7_2;
        int64_t p8_2;
        int64_t p9_1;
        int64_t p9_2;
        int64_t p10_1;
        int64_t p10_2;
        goto b1;
b1:;
        {
            int64_t v1_3_e2 = INT64_C(0);
            int64_t v1_3_e3 = INT64_C(0);
            p2_1 = v1_3_e2;
            p2_2 = v1_3_e3;
            goto b2;
        }
b2:;
        bool v2_2_0 = (p2_1 < INT64_C(10));
        if (v2_2_0)
        {
            int64_t v2_5_e2 = p2_1;
            int64_t v2_5_e3 = p2_2;
            p3_1 = v2_5_e2;
            p3_2 = v2_5_e3;
            goto b3;
        }
        else
        {
            int64_t v2_5_e3 = p2_2;
            p4_2 = v2_5_e3;
            goto b4;
        }
b3:;
        int64_t v3_2_0 = LET_ADD(p3_1, INT64_C(1));
        bool v3_4_0 = (v3_2_0 == INT64_C(3));
        if (v3_4_0)
        {
            int64_t v3_7_e2 = v3_2_0;
            int64_t v3_7_e3 = p3_2;
            p5_1 = v3_7_e2;
            p5_2 = v3_7_e3;
            goto b5;
        }
        else
        {
            int64_t v3_7_e2 = v3_2_0;
            int64_t v3_7_e3 = p3_2;
            p6_1 = v3_7_e2;
            p6_2 = v3_7_e3;
            goto b6;
        }
b4:;
        print_int(p4_2);
        return INT64_C(0);
b5:;
        {
            int64_t v5_3_e2 = p5_1;
            int64_t v5_3_e3 = p5_2;
            p2_1 = v5_3_e2;
            p2_2 = v5_3_e3;
            goto b2;
        }
b6:;
        {
            int64_t v6_3_e2 = p6_1;
            int64_t v6_3_e3 = p6_2;
            p7_1 = v6_3_e2;
            p7_2 = v6_3_e3;
            goto b7;
        }
b7:;
        bool v7_2_0 = (p7_1 == INT64_C(6));
        if (v7_2_0)
        {
            int64_t v7_5_e3 = p7_2;
            p8_2 = v7_5_e3;
            goto b8;
        }
        else
        {
            int64_t v7_5_e2 = p7_1;
            int64_t v7_5_e3 = p7_2;
            p9_1 = v7_5_e2;
            p9_2 = v7_5_e3;
            goto b9;
        }
b8:;
        {
            int64_t v8_3_e3 = p8_2;
            p4_2 = v8_3_e3;
            goto b4;
        }
b9:;
        {
            int64_t v9_3_e2 = p9_1;
            int64_t v9_3_e3 = p9_2;
            p10_1 = v9_3_e2;
            p10_2 = v9_3_e3;
            goto b10;
        }
b10:;
        int64_t v10_1_0 = LET_ADD(p10_2, p10_1);
        {
            int64_t v10_4_e2 = p10_1;
            int64_t v10_4_e3 = v10_1_0;
            p2_1 = v10_4_e2;
            p2_2 = v10_4_e3;
            goto b2;
        }
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
