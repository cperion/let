#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_NEG(a) ((int64_t)(0-(uint64_t)(a)))

static int64_t let_div(int64_t a,int64_t b){if(b==0)let_trap("division by zero");if(b==-1)return (int64_t)(0-(uint64_t)a);return a/b;}

struct let_val_1 {
    uint8_t f0;
    uint8_t f1;
};

struct let_val_2 {
    struct let_val_1 f0;
};

struct let_val_3 {
    uint8_t f0;
    uint8_t f1;
    uint8_t f2;
    struct let_val_1 f3;
    struct let_val_2 f4;
    int64_t f5;
};

struct let_ret_1 {
    struct let_val_3 r0;
    struct let_val_3 r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static int64_t let_run_3(struct let_val_1 p1_1);

static int64_t let_run_3_2(void);

static int64_t let_checked_divide_4(uint8_t p1_1, uint8_t p1_2, int64_t p1_3, int64_t p1_4);

static int64_t let_checked_divide_4_2(uint8_t p1_1, uint8_t p1_2);

static int64_t let_checked_divide_4_3(uint8_t p1_1, uint8_t p1_2);

static int64_t let_checked_divide_4_4(void);

static int64_t let_checked_divide_4_5(void);

static int64_t let_failure_5(int64_t p1_1);

static int64_t let_failure_5_2(void);

static int64_t let_success_6(int64_t p1_1);

static int64_t let_success_6_2(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        let_run_3_2();
        return ((struct let_ret_1){((struct let_val_3){INT64_C(0), INT64_C(0), INT64_C(0), ((struct let_val_1){INT64_C(0), INT64_C(0)}), ((struct let_val_2){((struct let_val_1){INT64_C(0), INT64_C(0)})}), INT64_C(0)}), ((struct let_val_3){INT64_C(0), INT64_C(0), INT64_C(0), ((struct let_val_1){INT64_C(0), INT64_C(0)}), ((struct let_val_2){((struct let_val_1){INT64_C(0), INT64_C(0)})}), INT64_C(0)})});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static int64_t let_run_3(struct let_val_1 p1_1) {
    {
        goto b1;
b1:;
        uint8_t v1_1_0 = (p1_1).f0;
        uint8_t v1_2_0 = (p1_1).f1;
        int64_t v1_7_0 = let_checked_divide_4_2(v1_1_0, v1_2_0);
        print_int(v1_7_0);
        uint8_t v1_9_0 = (p1_1).f0;
        uint8_t v1_10_0 = (p1_1).f1;
        int64_t v1_15_0 = let_checked_divide_4_3(v1_9_0, v1_10_0);
        print_int(v1_15_0);
        return INT64_C(0);
    }
}

static int64_t let_run_3_2(void) {
    {
        goto b1;
b1:;
        int64_t v1_7_0 = let_checked_divide_4_4();
        print_int(v1_7_0);
        int64_t v1_15_0 = let_checked_divide_4_5();
        print_int(v1_15_0);
        return INT64_C(0);
    }
}

static int64_t let_checked_divide_4(uint8_t p1_1, uint8_t p1_2, int64_t p1_3, int64_t p1_4) {
    {
        int64_t p3_3;
        int64_t p3_4;
        goto b1;
b1:;
        bool v1_2_0 = (p1_4 == INT64_C(0));
        if (v1_2_0)
        {
            goto b2;
        }
        else
        {
            int64_t v1_7_e4 = p1_3;
            int64_t v1_7_e5 = p1_4;
            p3_3 = v1_7_e4;
            p3_4 = v1_7_e5;
            goto b3;
        }
b2:;
        return let_failure_5_2();
b3:;
        int64_t v3_1_0 = let_div(p3_3, p3_4);
        return let_success_6(v3_1_0);
    }
}

static int64_t let_checked_divide_4_2(uint8_t p1_1, uint8_t p1_2) {
    {
        goto b1;
b1:;
        {
            goto b3;
        }
b3:;
        return let_success_6_2();
    }
}

static int64_t let_checked_divide_4_3(uint8_t p1_1, uint8_t p1_2) {
    {
        int64_t p3_3;
        int64_t p3_4;
        goto b1;
b1:;
        {
            goto b2;
        }
b2:;
        return let_failure_5_2();
    }
}

static int64_t let_checked_divide_4_4(void) {
    {
        goto b1;
b1:;
        {
            goto b3;
        }
b3:;
        return let_success_6_2();
    }
}

static int64_t let_checked_divide_4_5(void) {
    {
        int64_t p3_3;
        int64_t p3_4;
        goto b1;
b1:;
        {
            goto b2;
        }
b2:;
        return let_failure_5_2();
    }
}

static int64_t let_failure_5(int64_t p1_1) {
    {
        goto b1;
b1:;
        int64_t v1_1_0 = LET_NEG(p1_1);
        return v1_1_0;
    }
}

static int64_t let_failure_5_2(void) {
    {
        return (-INT64_C(1));
    }
}

static int64_t let_success_6(int64_t p1_1) {
    {
        goto b1;
b1:;
        return p1_1;
    }
}

static int64_t let_success_6_2(void) {
    {
        return INT64_C(42);
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
