#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

struct let_val_1 {
    uint8_t f0;
};

struct let_val_2 {
    int64_t f0;
};

struct let_val_3 {
    uint8_t f0;
    struct let_val_1 f1;
    int64_t f2;
    struct let_val_2 f3;
    uint8_t f4;
};

struct let_val_4 {
    int64_t f0;
    int64_t f1;
    int64_t f2;
};

struct let_ret_1 {
    struct let_val_3 r0;
    struct let_val_3 r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static int64_t let_run_3(uint8_t p1_1);

static int64_t let_run_3_2(void);

static uint8_t let_show_5(int64_t p1_1);

static int64_t let_bump_4(int64_t* p1_1, int64_t p1_2);

static int64_t let_bump_4_2(int64_t* p1_1);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        int64_t v1_3_0 = let_run_3_2();
        struct let_val_2 v1_4_0 = ((struct let_val_2){v1_3_0});
        let_show_5(v1_3_0);
        struct let_val_3 v1_6_0 = ((struct let_val_3){INT64_C(0), ((struct let_val_1){INT64_C(0)}), v1_3_0, v1_4_0, INT64_C(0)});
        return ((struct let_ret_1){v1_6_0, v1_6_0});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static int64_t let_run_3(uint8_t p1_1) {
    {
        struct let_val_4* p2_2;
        int64_t p2_3;
        struct let_val_4* p3_2;
        int64_t p3_3;
        struct let_val_4* p4_2;
        struct let_val_4* p5_2;
        int64_t p5_3;
        struct let_val_4* p5_4;
        struct let_val_4* p6_2;
        int64_t p6_3;
        struct let_val_4* p6_4;
        int64_t p6_5;
        struct let_val_4* p7_2;
        int64_t p7_3;
        struct let_val_4* p7_4;
        struct let_val_4* p8_2;
        int64_t p8_3;
        struct let_val_4* p8_4;
        int64_t p8_5;
        struct let_val_4* p9_2;
        int64_t p9_3;
        struct let_val_4* p9_4;
        struct let_val_4* p11_2;
        int64_t p11_3;
        int64_t* p11_6;
        struct let_val_4* p12_2;
        int64_t p12_3;
        int64_t* p12_6;
        struct let_val_4* p13_2;
        int64_t p13_3;
        int64_t* p13_6;
        goto b1;
b1:;
        struct let_val_4 v1_5_c = ((struct let_val_4){INT64_C(1), INT64_C(2), INT64_C(3)});
        struct let_val_4* v1_5_0 = (&v1_5_c);
        {
            struct let_val_4* v1_8_e3 = v1_5_0;
            int64_t v1_8_e4 = INT64_C(0);
            p2_2 = v1_8_e3;
            p2_3 = v1_8_e4;
            goto b2;
        }
b2:;
        bool v2_2_0 = (p2_3 < INT64_C(3));
        if (v2_2_0)
        {
            struct let_val_4* v2_6_e3 = p2_2;
            int64_t v2_6_e4 = p2_3;
            p3_2 = v2_6_e3;
            p3_3 = v2_6_e4;
            goto b3;
        }
        else
        {
            struct let_val_4* v2_6_e3 = p2_2;
            p4_2 = v2_6_e3;
            goto b4;
        }
b3:;
        bool v3_2_0 = (p3_3 == INT64_C(0));
        if (v3_2_0)
        {
            struct let_val_4* v3_6_e3 = p3_2;
            int64_t v3_6_e4 = p3_3;
            struct let_val_4* v3_6_e5 = p3_2;
            p5_2 = v3_6_e3;
            p5_3 = v3_6_e4;
            p5_4 = v3_6_e5;
            goto b5;
        }
        else
        {
            struct let_val_4* v3_6_e3 = p3_2;
            int64_t v3_6_e4 = p3_3;
            struct let_val_4* v3_6_e5 = p3_2;
            int64_t v3_6_e6 = p3_3;
            p6_2 = v3_6_e3;
            p6_3 = v3_6_e4;
            p6_4 = v3_6_e5;
            p6_5 = v3_6_e6;
            goto b6;
        }
b4:;
        struct let_val_4 v4_1_0 = (*p4_2);
        int64_t v4_2_0 = (v4_1_0).f0;
        struct let_val_4 v4_3_0 = (*p4_2);
        int64_t v4_4_0 = (v4_3_0).f1;
        int64_t v4_5_0 = LET_ADD(v4_2_0, v4_4_0);
        struct let_val_4 v4_6_0 = (*p4_2);
        int64_t v4_7_0 = (v4_6_0).f2;
        int64_t v4_8_0 = LET_ADD(v4_5_0, v4_7_0);
        return v4_8_0;
b5:;
        int64_t* v5_1_0 = (&((*p5_4)).f0);
        {
            struct let_val_4* v5_7_e3 = p5_2;
            int64_t v5_7_e4 = p5_3;
            int64_t* v5_7_e7 = v5_1_0;
            p13_2 = v5_7_e3;
            p13_3 = v5_7_e4;
            p13_6 = v5_7_e7;
            goto b13;
        }
b6:;
        bool v6_2_0 = (p6_5 == INT64_C(1));
        if (v6_2_0)
        {
            struct let_val_4* v6_8_e3 = p6_2;
            int64_t v6_8_e4 = p6_3;
            struct let_val_4* v6_8_e5 = p6_4;
            p7_2 = v6_8_e3;
            p7_3 = v6_8_e4;
            p7_4 = v6_8_e5;
            goto b7;
        }
        else
        {
            struct let_val_4* v6_8_e3 = p6_2;
            int64_t v6_8_e4 = p6_3;
            struct let_val_4* v6_8_e5 = p6_4;
            int64_t v6_8_e6 = p6_5;
            p8_2 = v6_8_e3;
            p8_3 = v6_8_e4;
            p8_4 = v6_8_e5;
            p8_5 = v6_8_e6;
            goto b8;
        }
b7:;
        int64_t* v7_1_0 = (&((*p7_4)).f1);
        {
            struct let_val_4* v7_7_e3 = p7_2;
            int64_t v7_7_e4 = p7_3;
            int64_t* v7_7_e7 = v7_1_0;
            p12_2 = v7_7_e3;
            p12_3 = v7_7_e4;
            p12_6 = v7_7_e7;
            goto b12;
        }
b8:;
        bool v8_2_0 = (p8_5 == INT64_C(2));
        if (v8_2_0)
        {
            struct let_val_4* v8_8_e3 = p8_2;
            int64_t v8_8_e4 = p8_3;
            struct let_val_4* v8_8_e5 = p8_4;
            p9_2 = v8_8_e3;
            p9_3 = v8_8_e4;
            p9_4 = v8_8_e5;
            goto b9;
        }
        else
        {
            goto b10;
        }
b9:;
        int64_t* v9_1_0 = (&((*p9_4)).f2);
        {
            struct let_val_4* v9_7_e3 = p9_2;
            int64_t v9_7_e4 = p9_3;
            int64_t* v9_7_e7 = v9_1_0;
            p11_2 = v9_7_e3;
            p11_3 = v9_7_e4;
            p11_6 = v9_7_e7;
            goto b11;
        }
b10:;
        {
            let_trap("\151\156\144\145\170\040\157\165\164\040\157\146\040\162\141\156\147\145");
            return INT64_C(0);
        }
b11:;
        {
            struct let_val_4* v11_7_e3 = p11_2;
            int64_t v11_7_e4 = p11_3;
            int64_t* v11_7_e7 = p11_6;
            p12_2 = v11_7_e3;
            p12_3 = v11_7_e4;
            p12_6 = v11_7_e7;
            goto b12;
        }
b12:;
        {
            struct let_val_4* v12_7_e3 = p12_2;
            int64_t v12_7_e4 = p12_3;
            int64_t* v12_7_e7 = p12_6;
            p13_2 = v12_7_e3;
            p13_3 = v12_7_e4;
            p13_6 = v12_7_e7;
            goto b13;
        }
b13:;
        int64_t v13_4_0 = let_bump_4_2(p13_6);
        int64_t v13_6_0 = LET_ADD(p13_3, INT64_C(1));
        {
            struct let_val_4* v13_13_e3 = p13_2;
            int64_t v13_13_e4 = v13_6_0;
            p2_2 = v13_13_e3;
            p2_3 = v13_13_e4;
            goto b2;
        }
    }
}

static int64_t let_run_3_2(void) {
    {
        struct let_val_4* p2_2;
        int64_t p2_3;
        struct let_val_4* p3_2;
        int64_t p3_3;
        struct let_val_4* p4_2;
        struct let_val_4* p5_2;
        int64_t p5_3;
        struct let_val_4* p5_4;
        struct let_val_4* p6_2;
        int64_t p6_3;
        struct let_val_4* p6_4;
        int64_t p6_5;
        struct let_val_4* p7_2;
        int64_t p7_3;
        struct let_val_4* p7_4;
        struct let_val_4* p8_2;
        int64_t p8_3;
        struct let_val_4* p8_4;
        int64_t p8_5;
        struct let_val_4* p9_2;
        int64_t p9_3;
        struct let_val_4* p9_4;
        struct let_val_4* p11_2;
        int64_t p11_3;
        int64_t* p11_6;
        struct let_val_4* p12_2;
        int64_t p12_3;
        int64_t* p12_6;
        struct let_val_4* p13_2;
        int64_t p13_3;
        int64_t* p13_6;
        goto b1;
b1:;
        struct let_val_4 v1_5_c = ((struct let_val_4){INT64_C(1), INT64_C(2), INT64_C(3)});
        struct let_val_4* v1_5_0 = (&v1_5_c);
        {
            struct let_val_4* v1_8_e3 = v1_5_0;
            int64_t v1_8_e4 = INT64_C(0);
            p2_2 = v1_8_e3;
            p2_3 = v1_8_e4;
            goto b2;
        }
b2:;
        bool v2_2_0 = (p2_3 < INT64_C(3));
        if (v2_2_0)
        {
            struct let_val_4* v2_6_e3 = p2_2;
            int64_t v2_6_e4 = p2_3;
            p3_2 = v2_6_e3;
            p3_3 = v2_6_e4;
            goto b3;
        }
        else
        {
            struct let_val_4* v2_6_e3 = p2_2;
            p4_2 = v2_6_e3;
            goto b4;
        }
b3:;
        bool v3_2_0 = (p3_3 == INT64_C(0));
        if (v3_2_0)
        {
            struct let_val_4* v3_6_e3 = p3_2;
            int64_t v3_6_e4 = p3_3;
            struct let_val_4* v3_6_e5 = p3_2;
            p5_2 = v3_6_e3;
            p5_3 = v3_6_e4;
            p5_4 = v3_6_e5;
            goto b5;
        }
        else
        {
            struct let_val_4* v3_6_e3 = p3_2;
            int64_t v3_6_e4 = p3_3;
            struct let_val_4* v3_6_e5 = p3_2;
            int64_t v3_6_e6 = p3_3;
            p6_2 = v3_6_e3;
            p6_3 = v3_6_e4;
            p6_4 = v3_6_e5;
            p6_5 = v3_6_e6;
            goto b6;
        }
b4:;
        struct let_val_4 v4_1_0 = (*p4_2);
        int64_t v4_2_0 = (v4_1_0).f0;
        struct let_val_4 v4_3_0 = (*p4_2);
        int64_t v4_4_0 = (v4_3_0).f1;
        int64_t v4_5_0 = LET_ADD(v4_2_0, v4_4_0);
        struct let_val_4 v4_6_0 = (*p4_2);
        int64_t v4_7_0 = (v4_6_0).f2;
        int64_t v4_8_0 = LET_ADD(v4_5_0, v4_7_0);
        return v4_8_0;
b5:;
        int64_t* v5_1_0 = (&((*p5_4)).f0);
        {
            struct let_val_4* v5_7_e3 = p5_2;
            int64_t v5_7_e4 = p5_3;
            int64_t* v5_7_e7 = v5_1_0;
            p13_2 = v5_7_e3;
            p13_3 = v5_7_e4;
            p13_6 = v5_7_e7;
            goto b13;
        }
b6:;
        bool v6_2_0 = (p6_5 == INT64_C(1));
        if (v6_2_0)
        {
            struct let_val_4* v6_8_e3 = p6_2;
            int64_t v6_8_e4 = p6_3;
            struct let_val_4* v6_8_e5 = p6_4;
            p7_2 = v6_8_e3;
            p7_3 = v6_8_e4;
            p7_4 = v6_8_e5;
            goto b7;
        }
        else
        {
            struct let_val_4* v6_8_e3 = p6_2;
            int64_t v6_8_e4 = p6_3;
            struct let_val_4* v6_8_e5 = p6_4;
            int64_t v6_8_e6 = p6_5;
            p8_2 = v6_8_e3;
            p8_3 = v6_8_e4;
            p8_4 = v6_8_e5;
            p8_5 = v6_8_e6;
            goto b8;
        }
b7:;
        int64_t* v7_1_0 = (&((*p7_4)).f1);
        {
            struct let_val_4* v7_7_e3 = p7_2;
            int64_t v7_7_e4 = p7_3;
            int64_t* v7_7_e7 = v7_1_0;
            p12_2 = v7_7_e3;
            p12_3 = v7_7_e4;
            p12_6 = v7_7_e7;
            goto b12;
        }
b8:;
        bool v8_2_0 = (p8_5 == INT64_C(2));
        if (v8_2_0)
        {
            struct let_val_4* v8_8_e3 = p8_2;
            int64_t v8_8_e4 = p8_3;
            struct let_val_4* v8_8_e5 = p8_4;
            p9_2 = v8_8_e3;
            p9_3 = v8_8_e4;
            p9_4 = v8_8_e5;
            goto b9;
        }
        else
        {
            goto b10;
        }
b9:;
        int64_t* v9_1_0 = (&((*p9_4)).f2);
        {
            struct let_val_4* v9_7_e3 = p9_2;
            int64_t v9_7_e4 = p9_3;
            int64_t* v9_7_e7 = v9_1_0;
            p11_2 = v9_7_e3;
            p11_3 = v9_7_e4;
            p11_6 = v9_7_e7;
            goto b11;
        }
b10:;
        {
            let_trap("\151\156\144\145\170\040\157\165\164\040\157\146\040\162\141\156\147\145");
            return INT64_C(0);
        }
b11:;
        {
            struct let_val_4* v11_7_e3 = p11_2;
            int64_t v11_7_e4 = p11_3;
            int64_t* v11_7_e7 = p11_6;
            p12_2 = v11_7_e3;
            p12_3 = v11_7_e4;
            p12_6 = v11_7_e7;
            goto b12;
        }
b12:;
        {
            struct let_val_4* v12_7_e3 = p12_2;
            int64_t v12_7_e4 = p12_3;
            int64_t* v12_7_e7 = p12_6;
            p13_2 = v12_7_e3;
            p13_3 = v12_7_e4;
            p13_6 = v12_7_e7;
            goto b13;
        }
b13:;
        int64_t v13_4_0 = let_bump_4_2(p13_6);
        int64_t v13_6_0 = LET_ADD(p13_3, INT64_C(1));
        {
            struct let_val_4* v13_13_e3 = p13_2;
            int64_t v13_13_e4 = v13_6_0;
            p2_2 = v13_13_e3;
            p2_3 = v13_13_e4;
            goto b2;
        }
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

static int64_t let_bump_4(int64_t* p1_1, int64_t p1_2) {
    {
        goto b1;
b1:;
        int64_t v1_1_0 = (*p1_1);
        int64_t v1_2_0 = LET_ADD(v1_1_0, p1_2);
        (*p1_1) = v1_2_0;
        int64_t v1_4_0 = (*p1_1);
        return v1_4_0;
    }
}

static int64_t let_bump_4_2(int64_t* p1_1) {
    {
        goto b1;
b1:;
        int64_t v1_1_0 = (*p1_1);
        int64_t v1_2_0 = LET_ADD(v1_1_0, INT64_C(1));
        (*p1_1) = v1_2_0;
        int64_t v1_4_0 = (*p1_1);
        return v1_4_0;
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
