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

struct let_ret_1 {
    struct let_val_2 r0;
    struct let_val_2 r1;
};

extern void print_int(int64_t a1);

extern int64_t runtime_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static int64_t let_run_3(void);

static uint8_t let_show_4(int64_t p1_1);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        int64_t v1_2_0 = let_run_3();
        struct let_val_1 v1_3_0 = ((struct let_val_1){v1_2_0});
        let_show_4(v1_2_0);
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
        int64_t p2_1;
        int64_t p2_2;
        int64_t p3_1;
        int64_t p3_2;
        int64_t p4_2;
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
        int64_t v2_2_0 = runtime_int(INT64_C(5));
        bool v2_3_0 = (p2_1 < v2_2_0);
        if (v2_3_0)
        {
            int64_t v2_6_e2 = p2_1;
            int64_t v2_6_e3 = p2_2;
            p3_1 = v2_6_e2;
            p3_2 = v2_6_e3;
            goto b3;
        }
        else
        {
            int64_t v2_6_e3 = p2_2;
            p4_2 = v2_6_e3;
            goto b4;
        }
b3:;
        int64_t v3_2_0 = LET_ADD(p3_1, INT64_C(1));
        int64_t v3_3_0 = LET_ADD(p3_2, v3_2_0);
        {
            int64_t v3_6_e2 = v3_2_0;
            int64_t v3_6_e3 = v3_3_0;
            p2_1 = v3_6_e2;
            p2_2 = v3_6_e3;
            goto b2;
        }
b4:;
        return p4_2;
    }
}

static uint8_t let_show_4(int64_t p1_1) {
    {
        goto b1;
b1:;
        print_int(p1_1);
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
