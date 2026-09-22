#include <stdbool.h>
#include <inttypes.h>

extern void let_trap(char* reason);

#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))

#define LET_MUL(a,b) ((int64_t)((uint64_t)(a)*(uint64_t)(b)))

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
    int64_t f2;
};

struct let_ret_1 {
    struct let_val_2 r0;
    struct let_val_2 r1;
};

extern void print_int(int64_t a1);

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
        struct let_val_3 p2_1;
        int64_t p2_2;
        int64_t p2_3;
        struct let_val_3 p3_1;
        int64_t p3_2;
        int64_t p3_3;
        int64_t p4_3;
        int64_t p5_2;
        int64_t p5_3;
        struct let_val_3 p5_6;
        int64_t p5_7;
        int64_t p6_2;
        int64_t p6_3;
        struct let_val_3 p6_6;
        int64_t p6_7;
        int64_t p7_2;
        int64_t p7_3;
        struct let_val_3 p7_6;
        int64_t p7_7;
        int64_t p8_2;
        int64_t p8_3;
        struct let_val_3 p8_6;
        int64_t p8_7;
        int64_t p9_2;
        int64_t p9_3;
        struct let_val_3 p9_6;
        int64_t p9_7;
        int64_t p11_2;
        int64_t p11_3;
        struct let_val_3 p11_6;
        int64_t p11_7;
        int64_t p11_8;
        int64_t p12_2;
        int64_t p12_3;
        struct let_val_3 p12_6;
        int64_t p12_7;
        int64_t p12_8;
        int64_t p13_2;
        int64_t p13_3;
        struct let_val_3 p13_6;
        int64_t p13_7;
        int64_t p13_8;
        int64_t p14_2;
        int64_t p14_3;
        struct let_val_3 p14_4;
        int64_t p14_6;
        int64_t p15_2;
        int64_t p15_3;
        struct let_val_3 p15_4;
        int64_t p15_5;
        int64_t p15_6;
        int64_t p16_2;
        int64_t p16_3;
        struct let_val_3 p16_4;
        int64_t p16_6;
        int64_t p17_2;
        int64_t p17_3;
        struct let_val_3 p17_4;
        int64_t p17_5;
        int64_t p17_6;
        int64_t p18_2;
        int64_t p18_3;
        struct let_val_3 p18_4;
        int64_t p18_6;
        int64_t p20_2;
        int64_t p20_3;
        struct let_val_3 p20_7;
        int64_t p21_2;
        int64_t p21_3;
        struct let_val_3 p21_7;
        int64_t p22_2;
        int64_t p22_3;
        struct let_val_3 p22_7;
        struct let_val_3 p23_1;
        int64_t p23_2;
        int64_t p23_4;
        struct let_val_3 p23_5;
        struct let_val_3 p24_1;
        int64_t p24_2;
        int64_t p24_4;
        struct let_val_3 p24_5;
        int64_t p24_6;
        struct let_val_3 p25_1;
        int64_t p25_2;
        int64_t p25_4;
        struct let_val_3 p25_5;
        struct let_val_3 p26_1;
        int64_t p26_2;
        int64_t p26_4;
        struct let_val_3 p26_5;
        int64_t p26_6;
        struct let_val_3 p27_1;
        int64_t p27_2;
        int64_t p27_4;
        struct let_val_3 p27_5;
        struct let_val_3 p29_1;
        int64_t p29_2;
        int64_t p29_4;
        int64_t p29_7;
        struct let_val_3 p30_1;
        int64_t p30_2;
        int64_t p30_4;
        int64_t p30_7;
        struct let_val_3 p31_1;
        int64_t p31_2;
        int64_t p31_4;
        int64_t p31_7;
        goto b1;
b1:;
        {
            struct let_val_3 v1_7_e2 = ((struct let_val_3){INT64_C(1), INT64_C(2), INT64_C(3)});
            int64_t v1_7_e3 = INT64_C(0);
            int64_t v1_7_e4 = INT64_C(0);
            p2_1 = v1_7_e2;
            p2_2 = v1_7_e3;
            p2_3 = v1_7_e4;
            goto b2;
        }
b2:;
        bool v2_2_0 = (p2_2 < INT64_C(3));
        if (v2_2_0)
        {
            struct let_val_3 v2_6_e2 = p2_1;
            int64_t v2_6_e3 = p2_2;
            int64_t v2_6_e4 = p2_3;
            p3_1 = v2_6_e2;
            p3_2 = v2_6_e3;
            p3_3 = v2_6_e4;
            goto b3;
        }
        else
        {
            int64_t v2_6_e4 = p2_3;
            p4_3 = v2_6_e4;
            goto b4;
        }
b3:;
        bool v3_2_0 = (p3_2 == INT64_C(0));
        if (v3_2_0)
        {
            int64_t v3_6_e3 = p3_2;
            int64_t v3_6_e4 = p3_3;
            struct let_val_3 v3_6_e7 = p3_1;
            int64_t v3_6_e8 = p3_2;
            p5_2 = v3_6_e3;
            p5_3 = v3_6_e4;
            p5_6 = v3_6_e7;
            p5_7 = v3_6_e8;
            goto b5;
        }
        else
        {
            int64_t v3_6_e3 = p3_2;
            int64_t v3_6_e4 = p3_3;
            struct let_val_3 v3_6_e7 = p3_1;
            int64_t v3_6_e8 = p3_2;
            p6_2 = v3_6_e3;
            p6_3 = v3_6_e4;
            p6_6 = v3_6_e7;
            p6_7 = v3_6_e8;
            goto b6;
        }
b4:;
        return p4_3;
b5:;
        int64_t v5_1_0 = (p5_6).f0;
        {
            int64_t v5_9_e3 = p5_2;
            int64_t v5_9_e4 = p5_3;
            struct let_val_3 v5_9_e7 = p5_6;
            int64_t v5_9_e8 = p5_7;
            int64_t v5_9_e9 = v5_1_0;
            p13_2 = v5_9_e3;
            p13_3 = v5_9_e4;
            p13_6 = v5_9_e7;
            p13_7 = v5_9_e8;
            p13_8 = v5_9_e9;
            goto b13;
        }
b6:;
        bool v6_2_0 = (p6_7 == INT64_C(1));
        if (v6_2_0)
        {
            int64_t v6_10_e3 = p6_2;
            int64_t v6_10_e4 = p6_3;
            struct let_val_3 v6_10_e7 = p6_6;
            int64_t v6_10_e8 = p6_7;
            p7_2 = v6_10_e3;
            p7_3 = v6_10_e4;
            p7_6 = v6_10_e7;
            p7_7 = v6_10_e8;
            goto b7;
        }
        else
        {
            int64_t v6_10_e3 = p6_2;
            int64_t v6_10_e4 = p6_3;
            struct let_val_3 v6_10_e7 = p6_6;
            int64_t v6_10_e8 = p6_7;
            p8_2 = v6_10_e3;
            p8_3 = v6_10_e4;
            p8_6 = v6_10_e7;
            p8_7 = v6_10_e8;
            goto b8;
        }
b7:;
        int64_t v7_1_0 = (p7_6).f1;
        {
            int64_t v7_9_e3 = p7_2;
            int64_t v7_9_e4 = p7_3;
            struct let_val_3 v7_9_e7 = p7_6;
            int64_t v7_9_e8 = p7_7;
            int64_t v7_9_e9 = v7_1_0;
            p12_2 = v7_9_e3;
            p12_3 = v7_9_e4;
            p12_6 = v7_9_e7;
            p12_7 = v7_9_e8;
            p12_8 = v7_9_e9;
            goto b12;
        }
b8:;
        bool v8_2_0 = (p8_7 == INT64_C(2));
        if (v8_2_0)
        {
            int64_t v8_10_e3 = p8_2;
            int64_t v8_10_e4 = p8_3;
            struct let_val_3 v8_10_e7 = p8_6;
            int64_t v8_10_e8 = p8_7;
            p9_2 = v8_10_e3;
            p9_3 = v8_10_e4;
            p9_6 = v8_10_e7;
            p9_7 = v8_10_e8;
            goto b9;
        }
        else
        {
            goto b10;
        }
b9:;
        int64_t v9_1_0 = (p9_6).f2;
        {
            int64_t v9_9_e3 = p9_2;
            int64_t v9_9_e4 = p9_3;
            struct let_val_3 v9_9_e7 = p9_6;
            int64_t v9_9_e8 = p9_7;
            int64_t v9_9_e9 = v9_1_0;
            p11_2 = v9_9_e3;
            p11_3 = v9_9_e4;
            p11_6 = v9_9_e7;
            p11_7 = v9_9_e8;
            p11_8 = v9_9_e9;
            goto b11;
        }
b10:;
        {
            let_trap("\151\156\144\145\170\040\157\165\164\040\157\146\040\162\141\156\147\145");
            return INT64_C(0);
        }
b11:;
        {
            int64_t v11_9_e3 = p11_2;
            int64_t v11_9_e4 = p11_3;
            struct let_val_3 v11_9_e7 = p11_6;
            int64_t v11_9_e8 = p11_7;
            int64_t v11_9_e9 = p11_8;
            p12_2 = v11_9_e3;
            p12_3 = v11_9_e4;
            p12_6 = v11_9_e7;
            p12_7 = v11_9_e8;
            p12_8 = v11_9_e9;
            goto b12;
        }
b12:;
        {
            int64_t v12_9_e3 = p12_2;
            int64_t v12_9_e4 = p12_3;
            struct let_val_3 v12_9_e7 = p12_6;
            int64_t v12_9_e8 = p12_7;
            int64_t v12_9_e9 = p12_8;
            p13_2 = v12_9_e3;
            p13_3 = v12_9_e4;
            p13_6 = v12_9_e7;
            p13_7 = v12_9_e8;
            p13_8 = v12_9_e9;
            goto b13;
        }
b13:;
        int64_t v13_2_0 = LET_MUL(p13_8, INT64_C(10));
        bool v13_4_0 = (p13_7 == INT64_C(0));
        if (v13_4_0)
        {
            int64_t v13_13_e3 = p13_2;
            int64_t v13_13_e4 = p13_3;
            struct let_val_3 v13_13_e5 = p13_6;
            int64_t v13_13_e7 = v13_2_0;
            p14_2 = v13_13_e3;
            p14_3 = v13_13_e4;
            p14_4 = v13_13_e5;
            p14_6 = v13_13_e7;
            goto b14;
        }
        else
        {
            int64_t v13_13_e3 = p13_2;
            int64_t v13_13_e4 = p13_3;
            struct let_val_3 v13_13_e5 = p13_6;
            int64_t v13_13_e6 = p13_7;
            int64_t v13_13_e7 = v13_2_0;
            p15_2 = v13_13_e3;
            p15_3 = v13_13_e4;
            p15_4 = v13_13_e5;
            p15_5 = v13_13_e6;
            p15_6 = v13_13_e7;
            goto b15;
        }
b14:;
        struct let_val_3 v14_3_0 = ((struct let_val_3){p14_6, (p14_4).f1, (p14_4).f2});
        {
            int64_t v14_10_e3 = p14_2;
            int64_t v14_10_e4 = p14_3;
            struct let_val_3 v14_10_e8 = v14_3_0;
            p22_2 = v14_10_e3;
            p22_3 = v14_10_e4;
            p22_7 = v14_10_e8;
            goto b22;
        }
b15:;
        bool v15_2_0 = (p15_5 == INT64_C(1));
        if (v15_2_0)
        {
            int64_t v15_9_e3 = p15_2;
            int64_t v15_9_e4 = p15_3;
            struct let_val_3 v15_9_e5 = p15_4;
            int64_t v15_9_e7 = p15_6;
            p16_2 = v15_9_e3;
            p16_3 = v15_9_e4;
            p16_4 = v15_9_e5;
            p16_6 = v15_9_e7;
            goto b16;
        }
        else
        {
            int64_t v15_9_e3 = p15_2;
            int64_t v15_9_e4 = p15_3;
            struct let_val_3 v15_9_e5 = p15_4;
            int64_t v15_9_e6 = p15_5;
            int64_t v15_9_e7 = p15_6;
            p17_2 = v15_9_e3;
            p17_3 = v15_9_e4;
            p17_4 = v15_9_e5;
            p17_5 = v15_9_e6;
            p17_6 = v15_9_e7;
            goto b17;
        }
b16:;
        struct let_val_3 v16_3_0 = ((struct let_val_3){(p16_4).f0, p16_6, (p16_4).f2});
        {
            int64_t v16_10_e3 = p16_2;
            int64_t v16_10_e4 = p16_3;
            struct let_val_3 v16_10_e8 = v16_3_0;
            p21_2 = v16_10_e3;
            p21_3 = v16_10_e4;
            p21_7 = v16_10_e8;
            goto b21;
        }
b17:;
        bool v17_2_0 = (p17_5 == INT64_C(2));
        if (v17_2_0)
        {
            int64_t v17_9_e3 = p17_2;
            int64_t v17_9_e4 = p17_3;
            struct let_val_3 v17_9_e5 = p17_4;
            int64_t v17_9_e7 = p17_6;
            p18_2 = v17_9_e3;
            p18_3 = v17_9_e4;
            p18_4 = v17_9_e5;
            p18_6 = v17_9_e7;
            goto b18;
        }
        else
        {
            goto b19;
        }
b18:;
        struct let_val_3 v18_3_0 = ((struct let_val_3){(p18_4).f0, (p18_4).f1, p18_6});
        {
            int64_t v18_10_e3 = p18_2;
            int64_t v18_10_e4 = p18_3;
            struct let_val_3 v18_10_e8 = v18_3_0;
            p20_2 = v18_10_e3;
            p20_3 = v18_10_e4;
            p20_7 = v18_10_e8;
            goto b20;
        }
b19:;
        {
            let_trap("\151\156\144\145\170\040\157\165\164\040\157\146\040\162\141\156\147\145");
            return INT64_C(0);
        }
b20:;
        {
            int64_t v20_8_e3 = p20_2;
            int64_t v20_8_e4 = p20_3;
            struct let_val_3 v20_8_e8 = p20_7;
            p21_2 = v20_8_e3;
            p21_3 = v20_8_e4;
            p21_7 = v20_8_e8;
            goto b21;
        }
b21:;
        {
            int64_t v21_8_e3 = p21_2;
            int64_t v21_8_e4 = p21_3;
            struct let_val_3 v21_8_e8 = p21_7;
            p22_2 = v21_8_e3;
            p22_3 = v21_8_e4;
            p22_7 = v21_8_e8;
            goto b22;
        }
b22:;
        bool v22_2_0 = (p22_2 == INT64_C(0));
        if (v22_2_0)
        {
            struct let_val_3 v22_10_e2 = p22_7;
            int64_t v22_10_e3 = p22_2;
            int64_t v22_10_e5 = p22_3;
            struct let_val_3 v22_10_e6 = p22_7;
            p23_1 = v22_10_e2;
            p23_2 = v22_10_e3;
            p23_4 = v22_10_e5;
            p23_5 = v22_10_e6;
            goto b23;
        }
        else
        {
            struct let_val_3 v22_10_e2 = p22_7;
            int64_t v22_10_e3 = p22_2;
            int64_t v22_10_e5 = p22_3;
            struct let_val_3 v22_10_e6 = p22_7;
            int64_t v22_10_e7 = p22_2;
            p24_1 = v22_10_e2;
            p24_2 = v22_10_e3;
            p24_4 = v22_10_e5;
            p24_5 = v22_10_e6;
            p24_6 = v22_10_e7;
            goto b24;
        }
b23:;
        int64_t v23_1_0 = (p23_5).f0;
        {
            struct let_val_3 v23_8_e2 = p23_1;
            int64_t v23_8_e3 = p23_2;
            int64_t v23_8_e5 = p23_4;
            int64_t v23_8_e8 = v23_1_0;
            p31_1 = v23_8_e2;
            p31_2 = v23_8_e3;
            p31_4 = v23_8_e5;
            p31_7 = v23_8_e8;
            goto b31;
        }
b24:;
        bool v24_2_0 = (p24_6 == INT64_C(1));
        if (v24_2_0)
        {
            struct let_val_3 v24_9_e2 = p24_1;
            int64_t v24_9_e3 = p24_2;
            int64_t v24_9_e5 = p24_4;
            struct let_val_3 v24_9_e6 = p24_5;
            p25_1 = v24_9_e2;
            p25_2 = v24_9_e3;
            p25_4 = v24_9_e5;
            p25_5 = v24_9_e6;
            goto b25;
        }
        else
        {
            struct let_val_3 v24_9_e2 = p24_1;
            int64_t v24_9_e3 = p24_2;
            int64_t v24_9_e5 = p24_4;
            struct let_val_3 v24_9_e6 = p24_5;
            int64_t v24_9_e7 = p24_6;
            p26_1 = v24_9_e2;
            p26_2 = v24_9_e3;
            p26_4 = v24_9_e5;
            p26_5 = v24_9_e6;
            p26_6 = v24_9_e7;
            goto b26;
        }
b25:;
        int64_t v25_1_0 = (p25_5).f1;
        {
            struct let_val_3 v25_8_e2 = p25_1;
            int64_t v25_8_e3 = p25_2;
            int64_t v25_8_e5 = p25_4;
            int64_t v25_8_e8 = v25_1_0;
            p30_1 = v25_8_e2;
            p30_2 = v25_8_e3;
            p30_4 = v25_8_e5;
            p30_7 = v25_8_e8;
            goto b30;
        }
b26:;
        bool v26_2_0 = (p26_6 == INT64_C(2));
        if (v26_2_0)
        {
            struct let_val_3 v26_9_e2 = p26_1;
            int64_t v26_9_e3 = p26_2;
            int64_t v26_9_e5 = p26_4;
            struct let_val_3 v26_9_e6 = p26_5;
            p27_1 = v26_9_e2;
            p27_2 = v26_9_e3;
            p27_4 = v26_9_e5;
            p27_5 = v26_9_e6;
            goto b27;
        }
        else
        {
            goto b28;
        }
b27:;
        int64_t v27_1_0 = (p27_5).f2;
        {
            struct let_val_3 v27_8_e2 = p27_1;
            int64_t v27_8_e3 = p27_2;
            int64_t v27_8_e5 = p27_4;
            int64_t v27_8_e8 = v27_1_0;
            p29_1 = v27_8_e2;
            p29_2 = v27_8_e3;
            p29_4 = v27_8_e5;
            p29_7 = v27_8_e8;
            goto b29;
        }
b28:;
        {
            let_trap("\151\156\144\145\170\040\157\165\164\040\157\146\040\162\141\156\147\145");
            return INT64_C(0);
        }
b29:;
        {
            struct let_val_3 v29_8_e2 = p29_1;
            int64_t v29_8_e3 = p29_2;
            int64_t v29_8_e5 = p29_4;
            int64_t v29_8_e8 = p29_7;
            p30_1 = v29_8_e2;
            p30_2 = v29_8_e3;
            p30_4 = v29_8_e5;
            p30_7 = v29_8_e8;
            goto b30;
        }
b30:;
        {
            struct let_val_3 v30_8_e2 = p30_1;
            int64_t v30_8_e3 = p30_2;
            int64_t v30_8_e5 = p30_4;
            int64_t v30_8_e8 = p30_7;
            p31_1 = v30_8_e2;
            p31_2 = v30_8_e3;
            p31_4 = v30_8_e5;
            p31_7 = v30_8_e8;
            goto b31;
        }
b31:;
        int64_t v31_1_0 = LET_ADD(p31_4, p31_7);
        int64_t v31_3_0 = LET_ADD(p31_2, INT64_C(1));
        {
            struct let_val_3 v31_11_e2 = p31_1;
            int64_t v31_11_e3 = v31_3_0;
            int64_t v31_11_e4 = v31_1_0;
            p2_1 = v31_11_e2;
            p2_2 = v31_11_e3;
            p2_3 = v31_11_e4;
            goto b2;
        }
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
