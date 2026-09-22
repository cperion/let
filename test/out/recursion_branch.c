#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

static int64_t let_div(int64_t a,int64_t b){if(b==0)let_trap("division by zero");if(b==-1)return (int64_t)(0-(uint64_t)a);return a/b;}

static int64_t let_rem(int64_t a,int64_t b){if(b==0)let_trap("remainder by zero");if(b==-1)return 0;return a%b;}

struct let_val_1 {
    uint8_t f0;
};

struct let_val_2 {
    uint8_t f0;
    struct let_val_1 f1;
    uint8_t f2;
};

struct let_ret_1 {
    struct let_val_2 r0;
    struct let_val_2 r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static uint8_t let_show_3(void);

static uint8_t let_show_3_2(void);

static uint8_t let_digits_4(int64_t p1_1);

static uint8_t let_digits_4_2(void);

static uint8_t let_digits_4_3(void);

static uint8_t let_digits_4_4(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        let_show_3_2();
        return ((struct let_ret_1){((struct let_val_2){INT64_C(0), ((struct let_val_1){INT64_C(0)}), INT64_C(0)}), ((struct let_val_2){INT64_C(0), ((struct let_val_1){INT64_C(0)}), INT64_C(0)})});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static uint8_t let_show_3(void) {
    {
        goto b1;
b1:;
        let_digits_4_2();
        return INT64_C(0);
    }
}

static uint8_t let_show_3_2(void) {
    {
        goto b1;
b1:;
        let_digits_4_2();
        return INT64_C(0);
    }
}

static uint8_t let_digits_4(int64_t p1_1) {
    {
        int64_t p2_1;
        int64_t p3_1;
        int64_t p4_1;
        goto b1;
b1:;
        bool v1_2_0 = (p1_1 >= INT64_C(10));
        if (v1_2_0)
        {
            int64_t v1_4_e2 = p1_1;
            p2_1 = v1_4_e2;
            goto b2;
        }
        else
        {
            int64_t v1_4_e2 = p1_1;
            p3_1 = v1_4_e2;
            goto b3;
        }
b2:;
        int64_t v2_3_0 = let_div(p2_1, INT64_C(10));
        let_digits_4(v2_3_0);
        {
            int64_t v2_7_e2 = p2_1;
            p4_1 = v2_7_e2;
            goto b4;
        }
b3:;
        {
            int64_t v3_2_e2 = p3_1;
            p4_1 = v3_2_e2;
            goto b4;
        }
b4:;
        int64_t v4_2_0 = let_rem(p4_1, INT64_C(10));
        print_int(v4_2_0);
        return INT64_C(0);
    }
}

static uint8_t let_digits_4_2(void) {
    {
        int64_t p3_1;
        goto b1;
b1:;
        {
            goto b2;
        }
b2:;
        let_digits_4_3();
        {
            goto b4;
        }
b4:;
        print_int(INT64_C(3));
        return INT64_C(0);
    }
}

static uint8_t let_digits_4_3(void) {
    {
        int64_t p3_1;
        goto b1;
b1:;
        {
            goto b2;
        }
b2:;
        let_digits_4_4();
        {
            goto b4;
        }
b4:;
        print_int(INT64_C(2));
        return INT64_C(0);
    }
}

static uint8_t let_digits_4_4(void) {
    {
        int64_t p2_1;
        goto b1;
b1:;
        {
            goto b3;
        }
b3:;
        {
            goto b4;
        }
b4:;
        print_int(INT64_C(1));
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
