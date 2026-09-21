#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

extern int64_t byte_at(const char * a1, int64_t a2);

struct let_s2 {
    uint8_t byte_at;
};

struct let_s3 {
    struct let_s2 skip;
    uint8_t byte_at;
    uint8_t is_digit;
    uint8_t prec;
    uint8_t apply_op;
};

struct let_s4 {
    struct let_s3 expr;
    uint8_t byte_at;
    struct let_s2 skip;
};

struct let_s1 {
    uint8_t byte_at;
    struct let_s2 skip;
    uint8_t is_digit;
    uint8_t prec;
    uint8_t apply_op;
    struct let_s3 expr;
    struct let_s4 eval;
};

struct let_s5 {
    const char * s;
};

struct let_s6 {
    const char * s;
    int64_t i;
};

struct let_s7 {
    uint8_t byte_at;
    const char * s;
};

struct let_s8 {
    uint8_t byte_at;
    const char * s;
    int64_t i;
};

struct let_s9 {
    int64_t c;
};

struct let_s10 {
    int64_t op;
};

struct let_s11 {
    int64_t op;
    int64_t a;
};

struct let_s12 {
    int64_t op;
    int64_t a;
    int64_t b;
};

struct let_s14 {
    int64_t value;
    int64_t pos;
};

struct let_s15 {
    int64_t at;
};

union let_u13 {
    struct let_s14 f0;
    struct let_s15 f1;
};

struct let_s13 {
    int64_t tag;
    union let_u13 payload;
};

struct let_s16 {
    struct let_s2 skip;
    uint8_t byte_at;
    uint8_t is_digit;
    uint8_t prec;
    uint8_t apply_op;
    const char * s;
};

struct let_s17 {
    struct let_s2 skip;
    uint8_t byte_at;
    uint8_t is_digit;
    uint8_t prec;
    uint8_t apply_op;
    const char * s;
    int64_t start;
};

struct let_s18 {
    struct let_s2 skip;
    uint8_t byte_at;
    uint8_t is_digit;
    uint8_t prec;
    uint8_t apply_op;
    const char * s;
    int64_t start;
    int64_t min;
};

struct let_s19 {
    struct let_s3 expr;
    uint8_t byte_at;
    struct let_s2 skip;
    const char * s;
};

struct let_s1 let_module_init(void);

static uint8_t let_byte_at_construct(void);

static struct let_s2 let_skip_construct(uint8_t p1);

static uint8_t let_is_digit_construct(void);

static uint8_t let_prec_construct(void);

static uint8_t let_apply_op_construct(void);

static struct let_s3 let_expr_construct(struct let_s2 p1, uint8_t p2, uint8_t p3, uint8_t p4, uint8_t p5);

static struct let_s4 let_eval_construct(struct let_s3 p1, uint8_t p2, struct let_s2 p3);

int64_t let_byte_at_entry(struct let_s1 p1, const char * p2, int64_t p3);

static struct let_s5 let_byte_at_advance_0(uint8_t p1, const char * p2);

static struct let_s6 let_byte_at_advance_1(struct let_s5 p1, int64_t p2);

static int64_t let_byte_at_run(struct let_s6 p1);

int64_t let_skip_entry(struct let_s1 p1, const char * p2, int64_t p3);

static struct let_s7 let_skip_advance_0(struct let_s2 p1, const char * p2);

static struct let_s8 let_skip_advance_1(struct let_s7 p1, int64_t p2);

static int64_t let_skip_run(struct let_s8 p1);

bool let_is_digit_entry(struct let_s1 p1, int64_t p2);

static struct let_s9 let_is_digit_advance_0(uint8_t p1, int64_t p2);

static bool let_is_digit_run(struct let_s9 p1);

int64_t let_prec_entry(struct let_s1 p1, int64_t p2);

static struct let_s9 let_prec_advance_0(uint8_t p1, int64_t p2);

static int64_t let_prec_run(struct let_s9 p1);

int64_t let_apply_op_entry(struct let_s1 p1, int64_t p2, int64_t p3, int64_t p4);

static struct let_s10 let_apply_op_advance_0(uint8_t p1, int64_t p2);

static struct let_s11 let_apply_op_advance_1(struct let_s10 p1, int64_t p2);

static struct let_s12 let_apply_op_advance_2(struct let_s11 p1, int64_t p2);

static int64_t let_apply_op_run(struct let_s12 p1);

struct let_s13 let_expr_entry(struct let_s1 p1, const char * p2, int64_t p3, int64_t p4);

static struct let_s16 let_expr_advance_0(struct let_s3 p1, const char * p2);

static struct let_s17 let_expr_advance_1(struct let_s16 p1, int64_t p2);

static struct let_s18 let_expr_advance_2(struct let_s17 p1, int64_t p2);

static struct let_s13 let_expr_run(struct let_s18 p1);

int64_t let_eval_entry(struct let_s1 p1, const char * p2);

static struct let_s19 let_eval_advance_0(struct let_s4 p1, const char * p2);

static int64_t let_eval_run(struct let_s19 p1);

struct let_s1 let_module_init(void) {
    {
        uint8_t v1 = let_byte_at_construct();
        struct let_s2 v2 = let_skip_construct(v1);
        uint8_t v3 = let_is_digit_construct();
        uint8_t v4 = let_prec_construct();
        uint8_t v5 = let_apply_op_construct();
        struct let_s3 v6 = let_expr_construct(v2, v1, v3, v4, v5);
        struct let_s4 v7 = let_eval_construct(v6, v1, v2);
        struct let_s1 v8 = ((struct let_s1){v1, v2, v3, v4, v5, v6, v7});
        return v8;
    }
}

static uint8_t let_byte_at_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s2 let_skip_construct(uint8_t p1) {
    {
        struct let_s2 v2 = ((struct let_s2){p1});
        return v2;
    }
}

static uint8_t let_is_digit_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_prec_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static uint8_t let_apply_op_construct(void) {
    {
        uint8_t v1 = INT64_C(0);
        return INT64_C(0);
    }
}

static struct let_s3 let_expr_construct(struct let_s2 p1, uint8_t p2, uint8_t p3, uint8_t p4, uint8_t p5) {
    {
        struct let_s3 v6 = ((struct let_s3){p1, p2, p3, p4, p5});
        return v6;
    }
}

static struct let_s4 let_eval_construct(struct let_s3 p1, uint8_t p2, struct let_s2 p3) {
    {
        struct let_s4 v4 = ((struct let_s4){p1, p2, p3});
        return v4;
    }
}

int64_t let_byte_at_entry(struct let_s1 p1, const char * p2, int64_t p3) {
    {
        uint8_t v4 = (p1).byte_at;
        struct let_s5 v5 = let_byte_at_advance_0(v4, p2);
        struct let_s6 v6 = let_byte_at_advance_1(v5, p3);
        int64_t v7 = let_byte_at_run(v6);
        return v7;
    }
}

static struct let_s5 let_byte_at_advance_0(uint8_t p1, const char * p2) {
    {
        struct let_s5 v3 = ((struct let_s5){p2});
        return v3;
    }
}

static struct let_s6 let_byte_at_advance_1(struct let_s5 p1, int64_t p2) {
    {
        const char * v3 = (p1).s;
        struct let_s6 v4 = ((struct let_s6){v3, p2});
        return v4;
    }
}

static int64_t let_byte_at_run(struct let_s6 p1) {
    {
        const char * v2 = (p1).s;
        int64_t v3 = (p1).i;
        int64_t v4 = byte_at(v2, v3);
        return v4;
    }
}

int64_t let_skip_entry(struct let_s1 p1, const char * p2, int64_t p3) {
    {
        struct let_s2 v4 = (p1).skip;
        struct let_s7 v5 = let_skip_advance_0(v4, p2);
        struct let_s8 v6 = let_skip_advance_1(v5, p3);
        int64_t v7 = let_skip_run(v6);
        return v7;
    }
}

static struct let_s7 let_skip_advance_0(struct let_s2 p1, const char * p2) {
    {
        uint8_t v3 = (p1).byte_at;
        struct let_s7 v4 = ((struct let_s7){v3, p2});
        return v4;
    }
}

static struct let_s8 let_skip_advance_1(struct let_s7 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).byte_at;
        const char * v4 = (p1).s;
        struct let_s8 v5 = ((struct let_s8){v3, v4, p2});
        return v5;
    }
}

static int64_t let_skip_run(struct let_s8 p1) {
    {
        const char * b2_p1;
        int64_t b2_p2;
        int64_t* b2_p3;
        uint8_t b2_p4;
        const char * b3_p1;
        int64_t b3_p2;
        int64_t* b3_p3;
        uint8_t b3_p4;
        const char * b4_p1;
        int64_t b4_p2;
        int64_t* b4_p3;
        uint8_t b4_p4;
        uint8_t v2 = (p1).byte_at;
        const char * v3 = (p1).s;
        int64_t v4 = (p1).i;
        int64_t v5 = v4;
        {
            b2_p1 = v3;
            b2_p2 = v4;
            b2_p3 = (&v5);
            b2_p4 = v2;
            goto b2;
        }
b2:;
        int64_t b2_v5 = (*b2_p3);
        struct let_s5 b2_v6 = let_byte_at_advance_0(b2_p4, b2_p1);
        struct let_s6 b2_v7 = let_byte_at_advance_1(b2_v6, b2_v5);
        int64_t b2_v8 = let_byte_at_run(b2_v7);
        bool b2_v10 = (b2_v8 == INT64_C(32));
        if (b2_v10)
        {
            b4_p1 = b2_p1;
            b4_p2 = b2_p2;
            b4_p3 = b2_p3;
            b4_p4 = b2_p4;
            goto b4;
        }
        else
        {
            b3_p1 = b2_p1;
            b3_p2 = b2_p2;
            b3_p3 = b2_p3;
            b3_p4 = b2_p4;
            goto b3;
        }
b3:;
        int64_t b3_v5 = (*b3_p3);
        return b3_v5;
b4:;
        int64_t b4_v5 = (*b4_p3);
        int64_t b4_v7 = ((int64_t)(((uint64_t)b4_v5) + ((uint64_t)INT64_C(1))));
        (*b4_p3) = b4_v7;
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_p2;
            b2_p3 = b4_p3;
            b2_p4 = b4_p4;
            goto b2;
        }
    }
}

bool let_is_digit_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).is_digit;
        struct let_s9 v4 = let_is_digit_advance_0(v3, p2);
        bool v5 = let_is_digit_run(v4);
        return v5;
    }
}

static struct let_s9 let_is_digit_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s9 v3 = ((struct let_s9){p2});
        return v3;
    }
}

static bool let_is_digit_run(struct let_s9 p1) {
    {
        int64_t b3_p1;
        bool b3_p2;
        int64_t b4_p1;
        int64_t b2_p1;
        bool b2_p2;
        int64_t v2 = (p1).c;
        bool v4 = (v2 >= INT64_C(48));
        if (v4)
        {
            b4_p1 = v2;
            goto b4;
        }
        else
        {
            b3_p1 = v2;
            b3_p2 = v4;
            goto b3;
        }
b3:;
        {
            b2_p1 = b3_p1;
            b2_p2 = b3_p2;
            goto b2;
        }
b4:;
        bool b4_v3 = (b4_p1 <= INT64_C(57));
        {
            b2_p1 = b4_p1;
            b2_p2 = b4_v3;
            goto b2;
        }
b2:;
        return b2_p2;
    }
}

int64_t let_prec_entry(struct let_s1 p1, int64_t p2) {
    {
        uint8_t v3 = (p1).prec;
        struct let_s9 v4 = let_prec_advance_0(v3, p2);
        int64_t v5 = let_prec_run(v4);
        return v5;
    }
}

static struct let_s9 let_prec_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s9 v3 = ((struct let_s9){p2});
        return v3;
    }
}

static int64_t let_prec_run(struct let_s9 p1) {
    {
        int64_t b6_p1;
        int64_t b6_p2;
        int64_t b7_p1;
        int64_t b7_p2;
        int64_t b8_p1;
        int64_t b8_p2;
        int64_t b9_p1;
        int64_t b9_p2;
        int64_t b10_p1;
        int64_t b10_p2;
        int64_t b5_p1;
        int64_t b5_p2;
        int64_t b4_p1;
        int64_t b4_p2;
        int64_t b3_p1;
        int64_t b3_p2;
        int64_t v2 = (p1).c;
        {
            b6_p1 = v2;
            b6_p2 = v2;
            goto b6;
        }
b6:;
        bool b6_v4 = (b6_p1 == INT64_C(43));
        if (b6_v4)
        {
            b3_p1 = b6_p1;
            b3_p2 = b6_p2;
            goto b3;
        }
        else
        {
            b7_p1 = b6_p1;
            b7_p2 = b6_p2;
            goto b7;
        }
b7:;
        bool b7_v4 = (b7_p1 == INT64_C(45));
        if (b7_v4)
        {
            b3_p1 = b7_p1;
            b3_p2 = b7_p2;
            goto b3;
        }
        else
        {
            b8_p1 = b7_p1;
            b8_p2 = b7_p2;
            goto b8;
        }
b8:;
        bool b8_v4 = (b8_p1 == INT64_C(42));
        if (b8_v4)
        {
            b4_p1 = b8_p1;
            b4_p2 = b8_p2;
            goto b4;
        }
        else
        {
            b9_p1 = b8_p1;
            b9_p2 = b8_p2;
            goto b9;
        }
b9:;
        bool b9_v4 = (b9_p1 == INT64_C(47));
        if (b9_v4)
        {
            b4_p1 = b9_p1;
            b4_p2 = b9_p2;
            goto b4;
        }
        else
        {
            b10_p1 = b9_p1;
            b10_p2 = b9_p2;
            goto b10;
        }
b10:;
        bool b10_v4 = (b10_p1 == INT64_C(37));
        if (b10_v4)
        {
            b4_p1 = b10_p1;
            b4_p2 = b10_p2;
            goto b4;
        }
        else
        {
            b5_p1 = b10_p1;
            b5_p2 = b10_p2;
            goto b5;
        }
b5:;
        return INT64_C(0);
b4:;
        return INT64_C(2);
b3:;
        return INT64_C(1);
    }
}

int64_t let_apply_op_entry(struct let_s1 p1, int64_t p2, int64_t p3, int64_t p4) {
    {
        uint8_t v5 = (p1).apply_op;
        struct let_s10 v6 = let_apply_op_advance_0(v5, p2);
        struct let_s11 v7 = let_apply_op_advance_1(v6, p3);
        struct let_s12 v8 = let_apply_op_advance_2(v7, p4);
        int64_t v9 = let_apply_op_run(v8);
        return v9;
    }
}

static struct let_s10 let_apply_op_advance_0(uint8_t p1, int64_t p2) {
    {
        struct let_s10 v3 = ((struct let_s10){p2});
        return v3;
    }
}

static struct let_s11 let_apply_op_advance_1(struct let_s10 p1, int64_t p2) {
    {
        int64_t v3 = (p1).op;
        struct let_s11 v4 = ((struct let_s11){v3, p2});
        return v4;
    }
}

static struct let_s12 let_apply_op_advance_2(struct let_s11 p1, int64_t p2) {
    {
        int64_t v3 = (p1).op;
        int64_t v4 = (p1).a;
        struct let_s12 v5 = ((struct let_s12){v3, v4, p2});
        return v5;
    }
}

static int64_t let_apply_op_run(struct let_s12 p1) {
    {
        int64_t b8_p1;
        int64_t b8_p2;
        int64_t b8_p3;
        int64_t b8_p4;
        int64_t b9_p1;
        int64_t b9_p2;
        int64_t b9_p3;
        int64_t b9_p4;
        int64_t b10_p1;
        int64_t b10_p2;
        int64_t b10_p3;
        int64_t b10_p4;
        int64_t b11_p1;
        int64_t b11_p2;
        int64_t b11_p3;
        int64_t b11_p4;
        int64_t b7_p1;
        int64_t b7_p2;
        int64_t b7_p3;
        int64_t b7_p4;
        int64_t b6_p1;
        int64_t b6_p2;
        int64_t b6_p3;
        int64_t b6_p4;
        int64_t b5_p1;
        int64_t b5_p2;
        int64_t b5_p3;
        int64_t b5_p4;
        int64_t b4_p1;
        int64_t b4_p2;
        int64_t b4_p3;
        int64_t b4_p4;
        int64_t b3_p1;
        int64_t b3_p2;
        int64_t b3_p3;
        int64_t b3_p4;
        int64_t v2 = (p1).op;
        int64_t v3 = (p1).a;
        int64_t v4 = (p1).b;
        {
            b8_p1 = v2;
            b8_p2 = v2;
            b8_p3 = v3;
            b8_p4 = v4;
            goto b8;
        }
b8:;
        bool b8_v6 = (b8_p1 == INT64_C(43));
        if (b8_v6)
        {
            b3_p1 = b8_p1;
            b3_p2 = b8_p2;
            b3_p3 = b8_p3;
            b3_p4 = b8_p4;
            goto b3;
        }
        else
        {
            b9_p1 = b8_p1;
            b9_p2 = b8_p2;
            b9_p3 = b8_p3;
            b9_p4 = b8_p4;
            goto b9;
        }
b9:;
        bool b9_v6 = (b9_p1 == INT64_C(45));
        if (b9_v6)
        {
            b4_p1 = b9_p1;
            b4_p2 = b9_p2;
            b4_p3 = b9_p3;
            b4_p4 = b9_p4;
            goto b4;
        }
        else
        {
            b10_p1 = b9_p1;
            b10_p2 = b9_p2;
            b10_p3 = b9_p3;
            b10_p4 = b9_p4;
            goto b10;
        }
b10:;
        bool b10_v6 = (b10_p1 == INT64_C(42));
        if (b10_v6)
        {
            b5_p1 = b10_p1;
            b5_p2 = b10_p2;
            b5_p3 = b10_p3;
            b5_p4 = b10_p4;
            goto b5;
        }
        else
        {
            b11_p1 = b10_p1;
            b11_p2 = b10_p2;
            b11_p3 = b10_p3;
            b11_p4 = b10_p4;
            goto b11;
        }
b11:;
        bool b11_v6 = (b11_p1 == INT64_C(47));
        if (b11_v6)
        {
            b6_p1 = b11_p1;
            b6_p2 = b11_p2;
            b6_p3 = b11_p3;
            b6_p4 = b11_p4;
            goto b6;
        }
        else
        {
            b7_p1 = b11_p1;
            b7_p2 = b11_p2;
            b7_p3 = b11_p3;
            b7_p4 = b11_p4;
            goto b7;
        }
b7:;
        int64_t b7_v5 = ((b7_p4 == INT64_C(0)) ? (abort(), INT64_C(0)) : ((b7_p4 == (-INT64_C(1))) ? INT64_C(0) : (b7_p3 % b7_p4)));
        return b7_v5;
b6:;
        int64_t b6_v5 = ((b6_p4 == INT64_C(0)) ? (abort(), INT64_C(0)) : ((b6_p4 == (-INT64_C(1))) ? ((int64_t)(((uint64_t)INT64_C(0)) - ((uint64_t)b6_p3))) : (b6_p3 / b6_p4)));
        return b6_v5;
b5:;
        int64_t b5_v5 = ((int64_t)(((uint64_t)b5_p3) * ((uint64_t)b5_p4)));
        return b5_v5;
b4:;
        int64_t b4_v5 = ((int64_t)(((uint64_t)b4_p3) - ((uint64_t)b4_p4)));
        return b4_v5;
b3:;
        int64_t b3_v5 = ((int64_t)(((uint64_t)b3_p3) + ((uint64_t)b3_p4)));
        return b3_v5;
    }
}

struct let_s13 let_expr_entry(struct let_s1 p1, const char * p2, int64_t p3, int64_t p4) {
    {
        struct let_s3 v5 = (p1).expr;
        struct let_s16 v6 = let_expr_advance_0(v5, p2);
        struct let_s17 v7 = let_expr_advance_1(v6, p3);
        struct let_s18 v8 = let_expr_advance_2(v7, p4);
        struct let_s13 v9 = let_expr_run(v8);
        return v9;
    }
}

static struct let_s16 let_expr_advance_0(struct let_s3 p1, const char * p2) {
    {
        struct let_s2 v3 = (p1).skip;
        uint8_t v4 = (p1).byte_at;
        uint8_t v5 = (p1).is_digit;
        uint8_t v6 = (p1).prec;
        uint8_t v7 = (p1).apply_op;
        struct let_s16 v8 = ((struct let_s16){v3, v4, v5, v6, v7, p2});
        return v8;
    }
}

static struct let_s17 let_expr_advance_1(struct let_s16 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).skip;
        uint8_t v4 = (p1).byte_at;
        uint8_t v5 = (p1).is_digit;
        uint8_t v6 = (p1).prec;
        uint8_t v7 = (p1).apply_op;
        const char * v8 = (p1).s;
        struct let_s17 v9 = ((struct let_s17){v3, v4, v5, v6, v7, v8, p2});
        return v9;
    }
}

static struct let_s18 let_expr_advance_2(struct let_s17 p1, int64_t p2) {
    {
        struct let_s2 v3 = (p1).skip;
        uint8_t v4 = (p1).byte_at;
        uint8_t v5 = (p1).is_digit;
        uint8_t v6 = (p1).prec;
        uint8_t v7 = (p1).apply_op;
        const char * v8 = (p1).s;
        int64_t v9 = (p1).start;
        struct let_s18 v10 = ((struct let_s18){v3, v4, v5, v6, v7, v8, v9, p2});
        return v10;
    }
}

static struct let_s13 let_expr_run(struct let_s18 p1) {
    {
        const char * b4_p1;
        int64_t b4_p2;
        int64_t b4_p3;
        int64_t* b4_p4;
        struct let_s2 b4_p5;
        int64_t* b4_p6;
        int64_t b4_p7;
        uint8_t b4_p8;
        uint8_t b4_p9;
        uint8_t b4_p10;
        uint8_t b4_p11;
        const char * b15_p1;
        int64_t b15_p2;
        int64_t b15_p3;
        int64_t* b15_p4;
        struct let_s2 b15_p5;
        int64_t* b15_p6;
        int64_t b15_p7;
        uint8_t b15_p8;
        uint8_t b15_p9;
        uint8_t b15_p10;
        uint8_t b15_p11;
        const char * b23_p1;
        int64_t b23_p2;
        int64_t b23_p3;
        int64_t* b23_p4;
        struct let_s2 b23_p5;
        int64_t* b23_p6;
        int64_t b23_p7;
        uint8_t b23_p8;
        uint8_t b23_p9;
        uint8_t b23_p10;
        uint8_t b23_p11;
        const char * b22_p1;
        int64_t b22_p2;
        int64_t b22_p3;
        int64_t* b22_p4;
        struct let_s2 b22_p5;
        int64_t* b22_p6;
        int64_t b22_p7;
        uint8_t b22_p8;
        uint8_t b22_p9;
        uint8_t b22_p10;
        uint8_t b22_p11;
        const char * b24_p1;
        int64_t b24_p2;
        int64_t b24_p3;
        int64_t* b24_p4;
        struct let_s2 b24_p5;
        int64_t* b24_p6;
        int64_t b24_p7;
        uint8_t b24_p8;
        uint8_t b24_p9;
        uint8_t b24_p10;
        uint8_t b24_p11;
        const char * b25_p1;
        int64_t b25_p2;
        int64_t b25_p3;
        int64_t* b25_p4;
        struct let_s2 b25_p5;
        int64_t* b25_p6;
        int64_t b25_p7;
        uint8_t b25_p8;
        uint8_t b25_p9;
        uint8_t b25_p10;
        uint8_t b25_p11;
        const char * b21_p1;
        int64_t b21_p2;
        int64_t b21_p3;
        int64_t* b21_p4;
        struct let_s2 b21_p5;
        int64_t* b21_p6;
        int64_t b21_p7;
        uint8_t b21_p8;
        uint8_t b21_p9;
        uint8_t b21_p10;
        uint8_t b21_p11;
        const char * b26_p1;
        int64_t b26_p2;
        int64_t b26_p3;
        int64_t* b26_p4;
        struct let_s2 b26_p5;
        int64_t* b26_p6;
        int64_t b26_p7;
        uint8_t b26_p8;
        uint8_t b26_p9;
        uint8_t b26_p10;
        uint8_t b26_p11;
        const char * b14_p1;
        int64_t b14_p2;
        int64_t b14_p3;
        int64_t* b14_p4;
        struct let_s2 b14_p5;
        int64_t* b14_p6;
        int64_t b14_p7;
        uint8_t b14_p8;
        uint8_t b14_p9;
        uint8_t b14_p10;
        uint8_t b14_p11;
        struct let_s13 b19_p1;
        const char * b19_p2;
        int64_t b19_p3;
        int64_t b19_p4;
        int64_t* b19_p5;
        struct let_s2 b19_p6;
        int64_t* b19_p7;
        int64_t b19_p8;
        uint8_t b19_p9;
        struct let_s13 b19_p10;
        uint8_t b19_p11;
        uint8_t b19_p12;
        uint8_t b19_p13;
        struct let_s13 b20_p1;
        const char * b20_p2;
        int64_t b20_p3;
        int64_t b20_p4;
        int64_t* b20_p5;
        struct let_s2 b20_p6;
        int64_t* b20_p7;
        int64_t b20_p8;
        uint8_t b20_p9;
        struct let_s13 b20_p10;
        uint8_t b20_p11;
        uint8_t b20_p12;
        uint8_t b20_p13;
        struct let_s13 b18_p1;
        const char * b18_p2;
        int64_t b18_p3;
        int64_t b18_p4;
        int64_t* b18_p5;
        struct let_s2 b18_p6;
        int64_t* b18_p7;
        int64_t b18_p8;
        uint8_t b18_p9;
        struct let_s13 b18_p10;
        uint8_t b18_p11;
        uint8_t b18_p12;
        uint8_t b18_p13;
        struct let_s13 b16_p1;
        const char * b16_p2;
        int64_t b16_p3;
        int64_t b16_p4;
        int64_t* b16_p5;
        struct let_s2 b16_p6;
        int64_t* b16_p7;
        int64_t b16_p8;
        uint8_t b16_p9;
        struct let_s13 b16_p10;
        uint8_t b16_p11;
        uint8_t b16_p12;
        uint8_t b16_p13;
        const char * b13_p1;
        int64_t b13_p2;
        int64_t b13_p3;
        int64_t* b13_p4;
        struct let_s2 b13_p5;
        int64_t* b13_p6;
        int64_t b13_p7;
        uint8_t b13_p8;
        uint8_t b13_p9;
        uint8_t b13_p10;
        uint8_t b13_p11;
        struct let_s13 b17_p1;
        const char * b17_p2;
        int64_t b17_p3;
        int64_t b17_p4;
        int64_t* b17_p5;
        struct let_s2 b17_p6;
        int64_t* b17_p7;
        int64_t b17_p8;
        uint8_t b17_p9;
        struct let_s13 b17_p10;
        uint8_t b17_p11;
        uint8_t b17_p12;
        uint8_t b17_p13;
        const char * b3_p1;
        int64_t b3_p2;
        int64_t b3_p3;
        int64_t* b3_p4;
        struct let_s2 b3_p5;
        int64_t* b3_p6;
        int64_t b3_p7;
        uint8_t b3_p8;
        uint8_t b3_p9;
        uint8_t b3_p10;
        uint8_t b3_p11;
        struct let_s13 b8_p1;
        const char * b8_p2;
        int64_t b8_p3;
        int64_t b8_p4;
        int64_t* b8_p5;
        struct let_s2 b8_p6;
        int64_t* b8_p7;
        int64_t b8_p8;
        uint8_t b8_p9;
        struct let_s13 b8_p10;
        uint8_t b8_p11;
        uint8_t b8_p12;
        uint8_t b8_p13;
        struct let_s13 b9_p1;
        const char * b9_p2;
        int64_t b9_p3;
        int64_t b9_p4;
        int64_t* b9_p5;
        struct let_s2 b9_p6;
        int64_t* b9_p7;
        int64_t b9_p8;
        uint8_t b9_p9;
        struct let_s13 b9_p10;
        uint8_t b9_p11;
        uint8_t b9_p12;
        uint8_t b9_p13;
        struct let_s13 b7_p1;
        const char * b7_p2;
        int64_t b7_p3;
        int64_t b7_p4;
        int64_t* b7_p5;
        struct let_s2 b7_p6;
        int64_t* b7_p7;
        int64_t b7_p8;
        uint8_t b7_p9;
        struct let_s13 b7_p10;
        uint8_t b7_p11;
        uint8_t b7_p12;
        uint8_t b7_p13;
        struct let_s13 b12_p1;
        const char * b12_p2;
        int64_t b12_p3;
        int64_t b12_p4;
        int64_t* b12_p5;
        struct let_s2 b12_p6;
        int64_t* b12_p7;
        int64_t b12_p8;
        uint8_t b12_p9;
        struct let_s13 b12_p10;
        struct let_s14 b12_p11;
        uint8_t b12_p12;
        uint8_t b12_p13;
        uint8_t b12_p14;
        struct let_s13 b10_p1;
        const char * b10_p2;
        int64_t b10_p3;
        int64_t b10_p4;
        int64_t* b10_p5;
        struct let_s2 b10_p6;
        int64_t* b10_p7;
        int64_t b10_p8;
        uint8_t b10_p9;
        struct let_s13 b10_p10;
        struct let_s14 b10_p11;
        uint8_t b10_p12;
        uint8_t b10_p13;
        uint8_t b10_p14;
        struct let_s13 b5_p1;
        const char * b5_p2;
        int64_t b5_p3;
        int64_t b5_p4;
        int64_t* b5_p5;
        struct let_s2 b5_p6;
        int64_t* b5_p7;
        int64_t b5_p8;
        uint8_t b5_p9;
        struct let_s13 b5_p10;
        uint8_t b5_p11;
        uint8_t b5_p12;
        uint8_t b5_p13;
        const char * b2_p1;
        int64_t b2_p2;
        int64_t b2_p3;
        int64_t* b2_p4;
        struct let_s2 b2_p5;
        int64_t* b2_p6;
        int64_t b2_p7;
        uint8_t b2_p8;
        uint8_t b2_p9;
        uint8_t b2_p10;
        uint8_t b2_p11;
        const char * b27_p1;
        int64_t b27_p2;
        int64_t b27_p3;
        int64_t* b27_p4;
        struct let_s2 b27_p5;
        int64_t* b27_p6;
        int64_t b27_p7;
        uint8_t b27_p8;
        uint8_t b27_p9;
        uint8_t b27_p10;
        uint8_t b27_p11;
        const char * b29_p1;
        int64_t b29_p2;
        int64_t b29_p3;
        int64_t* b29_p4;
        struct let_s2 b29_p5;
        int64_t* b29_p6;
        int64_t b29_p7;
        uint8_t b29_p8;
        uint8_t b29_p9;
        uint8_t b29_p10;
        uint8_t b29_p11;
        const char * b32_p1;
        int64_t b32_p2;
        int64_t b32_p3;
        int64_t* b32_p4;
        struct let_s2 b32_p5;
        int64_t* b32_p6;
        int64_t b32_p7;
        uint8_t b32_p8;
        uint8_t b32_p9;
        int64_t b32_p10;
        int64_t b32_p11;
        uint8_t b32_p12;
        uint8_t b32_p13;
        const char * b31_p1;
        int64_t b31_p2;
        int64_t b31_p3;
        int64_t* b31_p4;
        struct let_s2 b31_p5;
        int64_t* b31_p6;
        int64_t b31_p7;
        uint8_t b31_p8;
        uint8_t b31_p9;
        int64_t b31_p10;
        int64_t b31_p11;
        uint8_t b31_p12;
        uint8_t b31_p13;
        bool b31_p14;
        const char * b30_p1;
        int64_t b30_p2;
        int64_t b30_p3;
        int64_t* b30_p4;
        struct let_s2 b30_p5;
        int64_t* b30_p6;
        int64_t b30_p7;
        uint8_t b30_p8;
        uint8_t b30_p9;
        int64_t b30_p10;
        int64_t b30_p11;
        uint8_t b30_p12;
        uint8_t b30_p13;
        bool b30_p14;
        const char * b35_p1;
        int64_t b35_p2;
        int64_t b35_p3;
        int64_t* b35_p4;
        struct let_s2 b35_p5;
        int64_t* b35_p6;
        int64_t b35_p7;
        uint8_t b35_p8;
        uint8_t b35_p9;
        int64_t b35_p10;
        int64_t b35_p11;
        uint8_t b35_p12;
        uint8_t b35_p13;
        const char * b33_p1;
        int64_t b33_p2;
        int64_t b33_p3;
        int64_t* b33_p4;
        struct let_s2 b33_p5;
        int64_t* b33_p6;
        int64_t b33_p7;
        uint8_t b33_p8;
        uint8_t b33_p9;
        int64_t b33_p10;
        int64_t b33_p11;
        uint8_t b33_p12;
        uint8_t b33_p13;
        struct let_s13 b39_p1;
        const char * b39_p2;
        int64_t b39_p3;
        int64_t b39_p4;
        int64_t* b39_p5;
        struct let_s2 b39_p6;
        int64_t* b39_p7;
        int64_t b39_p8;
        uint8_t b39_p9;
        uint8_t b39_p10;
        int64_t b39_p11;
        int64_t b39_p12;
        uint8_t b39_p13;
        struct let_s13 b39_p14;
        uint8_t b39_p15;
        struct let_s13 b40_p1;
        const char * b40_p2;
        int64_t b40_p3;
        int64_t b40_p4;
        int64_t* b40_p5;
        struct let_s2 b40_p6;
        int64_t* b40_p7;
        int64_t b40_p8;
        uint8_t b40_p9;
        uint8_t b40_p10;
        int64_t b40_p11;
        int64_t b40_p12;
        uint8_t b40_p13;
        struct let_s13 b40_p14;
        uint8_t b40_p15;
        struct let_s13 b38_p1;
        const char * b38_p2;
        int64_t b38_p3;
        int64_t b38_p4;
        int64_t* b38_p5;
        struct let_s2 b38_p6;
        int64_t* b38_p7;
        int64_t b38_p8;
        uint8_t b38_p9;
        uint8_t b38_p10;
        int64_t b38_p11;
        int64_t b38_p12;
        uint8_t b38_p13;
        struct let_s13 b38_p14;
        uint8_t b38_p15;
        struct let_s13 b36_p1;
        const char * b36_p2;
        int64_t b36_p3;
        int64_t b36_p4;
        int64_t* b36_p5;
        struct let_s2 b36_p6;
        int64_t* b36_p7;
        int64_t b36_p8;
        uint8_t b36_p9;
        uint8_t b36_p10;
        int64_t b36_p11;
        int64_t b36_p12;
        uint8_t b36_p13;
        struct let_s13 b36_p14;
        uint8_t b36_p15;
        struct let_s13 b37_p1;
        const char * b37_p2;
        int64_t b37_p3;
        int64_t b37_p4;
        int64_t* b37_p5;
        struct let_s2 b37_p6;
        int64_t* b37_p7;
        int64_t b37_p8;
        uint8_t b37_p9;
        uint8_t b37_p10;
        int64_t b37_p11;
        int64_t b37_p12;
        uint8_t b37_p13;
        struct let_s13 b37_p14;
        uint8_t b37_p15;
        const char * b34_p1;
        int64_t b34_p2;
        int64_t b34_p3;
        int64_t* b34_p4;
        struct let_s2 b34_p5;
        int64_t* b34_p6;
        int64_t b34_p7;
        uint8_t b34_p8;
        uint8_t b34_p9;
        int64_t b34_p10;
        int64_t b34_p11;
        uint8_t b34_p12;
        uint8_t b34_p13;
        const char * b28_p1;
        int64_t b28_p2;
        int64_t b28_p3;
        int64_t* b28_p4;
        struct let_s2 b28_p5;
        int64_t* b28_p6;
        int64_t b28_p7;
        uint8_t b28_p8;
        uint8_t b28_p9;
        uint8_t b28_p10;
        uint8_t b28_p11;
        struct let_s13 b11_p1;
        const char * b11_p2;
        int64_t b11_p3;
        int64_t b11_p4;
        int64_t* b11_p5;
        struct let_s2 b11_p6;
        int64_t* b11_p7;
        int64_t b11_p8;
        uint8_t b11_p9;
        struct let_s13 b11_p10;
        struct let_s14 b11_p11;
        uint8_t b11_p12;
        uint8_t b11_p13;
        uint8_t b11_p14;
        struct let_s13 b6_p1;
        const char * b6_p2;
        int64_t b6_p3;
        int64_t b6_p4;
        int64_t* b6_p5;
        struct let_s2 b6_p6;
        int64_t* b6_p7;
        int64_t b6_p8;
        uint8_t b6_p9;
        struct let_s13 b6_p10;
        uint8_t b6_p11;
        uint8_t b6_p12;
        uint8_t b6_p13;
        struct let_s2 v2 = (p1).skip;
        uint8_t v3 = (p1).byte_at;
        uint8_t v4 = (p1).is_digit;
        uint8_t v5 = (p1).prec;
        uint8_t v6 = (p1).apply_op;
        const char * v7 = (p1).s;
        int64_t v8 = (p1).start;
        int64_t v9 = (p1).min;
        struct let_s7 v10 = let_skip_advance_0(v2, v7);
        struct let_s8 v11 = let_skip_advance_1(v10, v8);
        int64_t v12 = let_skip_run(v11);
        int64_t v13 = v12;
        int64_t v15 = INT64_C(0);
        int64_t v16 = (*(&v13));
        struct let_s5 v17 = let_byte_at_advance_0(v3, v7);
        struct let_s6 v18 = let_byte_at_advance_1(v17, v16);
        int64_t v19 = let_byte_at_run(v18);
        bool v21 = (v19 == INT64_C(40));
        if (v21)
        {
            b3_p1 = v7;
            b3_p2 = v8;
            b3_p3 = v9;
            b3_p4 = (&v13);
            b3_p5 = v2;
            b3_p6 = (&v15);
            b3_p7 = v19;
            b3_p8 = v3;
            b3_p9 = v4;
            b3_p10 = v5;
            b3_p11 = v6;
            goto b3;
        }
        else
        {
            b4_p1 = v7;
            b4_p2 = v8;
            b4_p3 = v9;
            b4_p4 = (&v13);
            b4_p5 = v2;
            b4_p6 = (&v15);
            b4_p7 = v19;
            b4_p8 = v3;
            b4_p9 = v4;
            b4_p10 = v5;
            b4_p11 = v6;
            goto b4;
        }
b4:;
        bool b4_v13 = (b4_p7 == INT64_C(45));
        if (b4_v13)
        {
            b14_p1 = b4_p1;
            b14_p2 = b4_p2;
            b14_p3 = b4_p3;
            b14_p4 = b4_p4;
            b14_p5 = b4_p5;
            b14_p6 = b4_p6;
            b14_p7 = b4_p7;
            b14_p8 = b4_p8;
            b14_p9 = b4_p9;
            b14_p10 = b4_p10;
            b14_p11 = b4_p11;
            goto b14;
        }
        else
        {
            b15_p1 = b4_p1;
            b15_p2 = b4_p2;
            b15_p3 = b4_p3;
            b15_p4 = b4_p4;
            b15_p5 = b4_p5;
            b15_p6 = b4_p6;
            b15_p7 = b4_p7;
            b15_p8 = b4_p8;
            b15_p9 = b4_p9;
            b15_p10 = b4_p10;
            b15_p11 = b4_p11;
            goto b15;
        }
b15:;
        struct let_s9 b15_v12 = let_is_digit_advance_0(b15_p9, b15_p7);
        bool b15_v13 = let_is_digit_run(b15_v12);
        if (b15_v13)
        {
            b22_p1 = b15_p1;
            b22_p2 = b15_p2;
            b22_p3 = b15_p3;
            b22_p4 = b15_p4;
            b22_p5 = b15_p5;
            b22_p6 = b15_p6;
            b22_p7 = b15_p7;
            b22_p8 = b15_p8;
            b22_p9 = b15_p9;
            b22_p10 = b15_p10;
            b22_p11 = b15_p11;
            goto b22;
        }
        else
        {
            b23_p1 = b15_p1;
            b23_p2 = b15_p2;
            b23_p3 = b15_p3;
            b23_p4 = b15_p4;
            b23_p5 = b15_p5;
            b23_p6 = b15_p6;
            b23_p7 = b15_p7;
            b23_p8 = b15_p8;
            b23_p9 = b15_p9;
            b23_p10 = b15_p10;
            b23_p11 = b15_p11;
            goto b23;
        }
b23:;
        int64_t b23_v12 = (*b23_p4);
        struct let_s15 b23_v13 = ((struct let_s15){b23_v12});
        struct let_s13 b23_v14 = ((struct let_s13){.tag = INT64_C(1), .payload = ((union let_u13){.f1 = b23_v13})});
        return b23_v14;
b22:;
        {
            b24_p1 = b22_p1;
            b24_p2 = b22_p2;
            b24_p3 = b22_p3;
            b24_p4 = b22_p4;
            b24_p5 = b22_p5;
            b24_p6 = b22_p6;
            b24_p7 = b22_p7;
            b24_p8 = b22_p8;
            b24_p9 = b22_p9;
            b24_p10 = b22_p10;
            b24_p11 = b22_p11;
            goto b24;
        }
b24:;
        int64_t b24_v12 = (*b24_p4);
        struct let_s5 b24_v13 = let_byte_at_advance_0(b24_p8, b24_p1);
        struct let_s6 b24_v14 = let_byte_at_advance_1(b24_v13, b24_v12);
        int64_t b24_v15 = let_byte_at_run(b24_v14);
        struct let_s9 b24_v16 = let_is_digit_advance_0(b24_p9, b24_v15);
        bool b24_v17 = let_is_digit_run(b24_v16);
        if (b24_v17)
        {
            b26_p1 = b24_p1;
            b26_p2 = b24_p2;
            b26_p3 = b24_p3;
            b26_p4 = b24_p4;
            b26_p5 = b24_p5;
            b26_p6 = b24_p6;
            b26_p7 = b24_p7;
            b26_p8 = b24_p8;
            b26_p9 = b24_p9;
            b26_p10 = b24_p10;
            b26_p11 = b24_p11;
            goto b26;
        }
        else
        {
            b25_p1 = b24_p1;
            b25_p2 = b24_p2;
            b25_p3 = b24_p3;
            b25_p4 = b24_p4;
            b25_p5 = b24_p5;
            b25_p6 = b24_p6;
            b25_p7 = b24_p7;
            b25_p8 = b24_p8;
            b25_p9 = b24_p9;
            b25_p10 = b24_p10;
            b25_p11 = b24_p11;
            goto b25;
        }
b25:;
        {
            b21_p1 = b25_p1;
            b21_p2 = b25_p2;
            b21_p3 = b25_p3;
            b21_p4 = b25_p4;
            b21_p5 = b25_p5;
            b21_p6 = b25_p6;
            b21_p7 = b25_p7;
            b21_p8 = b25_p8;
            b21_p9 = b25_p9;
            b21_p10 = b25_p10;
            b21_p11 = b25_p11;
            goto b21;
        }
b21:;
        {
            b13_p1 = b21_p1;
            b13_p2 = b21_p2;
            b13_p3 = b21_p3;
            b13_p4 = b21_p4;
            b13_p5 = b21_p5;
            b13_p6 = b21_p6;
            b13_p7 = b21_p7;
            b13_p8 = b21_p8;
            b13_p9 = b21_p9;
            b13_p10 = b21_p10;
            b13_p11 = b21_p11;
            goto b13;
        }
b26:;
        int64_t b26_v12 = (*b26_p6);
        int64_t b26_v14 = ((int64_t)(((uint64_t)b26_v12) * ((uint64_t)INT64_C(10))));
        int64_t b26_v15 = (*b26_p4);
        struct let_s5 b26_v16 = let_byte_at_advance_0(b26_p8, b26_p1);
        struct let_s6 b26_v17 = let_byte_at_advance_1(b26_v16, b26_v15);
        int64_t b26_v18 = let_byte_at_run(b26_v17);
        int64_t b26_v19 = ((int64_t)(((uint64_t)b26_v14) + ((uint64_t)b26_v18)));
        int64_t b26_v21 = ((int64_t)(((uint64_t)b26_v19) - ((uint64_t)INT64_C(48))));
        (*b26_p6) = b26_v21;
        int64_t b26_v23 = (*b26_p4);
        int64_t b26_v25 = ((int64_t)(((uint64_t)b26_v23) + ((uint64_t)INT64_C(1))));
        (*b26_p4) = b26_v25;
        {
            b24_p1 = b26_p1;
            b24_p2 = b26_p2;
            b24_p3 = b26_p3;
            b24_p4 = b26_p4;
            b24_p5 = b26_p5;
            b24_p6 = b26_p6;
            b24_p7 = b26_p7;
            b24_p8 = b26_p8;
            b24_p9 = b26_p9;
            b24_p10 = b26_p10;
            b24_p11 = b26_p11;
            goto b24;
        }
b14:;
        int64_t b14_v13 = (*b14_p4);
        int64_t b14_v15 = ((int64_t)(((uint64_t)b14_v13) + ((uint64_t)INT64_C(1))));
        struct let_s3 b14_v16 = let_expr_construct(b14_p5, b14_p8, b14_p9, b14_p10, b14_p11);
        struct let_s16 b14_v17 = let_expr_advance_0(b14_v16, b14_p1);
        struct let_s17 b14_v18 = let_expr_advance_1(b14_v17, b14_v15);
        struct let_s18 b14_v19 = let_expr_advance_2(b14_v18, INT64_C(3));
        struct let_s13 b14_v20 = let_expr_run(b14_v19);
        {
            b19_p1 = b14_v20;
            b19_p2 = b14_p1;
            b19_p3 = b14_p2;
            b19_p4 = b14_p3;
            b19_p5 = b14_p4;
            b19_p6 = b14_p5;
            b19_p7 = b14_p6;
            b19_p8 = b14_p7;
            b19_p9 = b14_p8;
            b19_p10 = b14_v20;
            b19_p11 = b14_p9;
            b19_p12 = b14_p10;
            b19_p13 = b14_p11;
            goto b19;
        }
b19:;
        int64_t b19_v14 = (b19_p1).tag;
        bool b19_v16 = (b19_v14 == INT64_C(1));
        if (b19_v16)
        {
            b17_p1 = b19_p1;
            b17_p2 = b19_p2;
            b17_p3 = b19_p3;
            b17_p4 = b19_p4;
            b17_p5 = b19_p5;
            b17_p6 = b19_p6;
            b17_p7 = b19_p7;
            b17_p8 = b19_p8;
            b17_p9 = b19_p9;
            b17_p10 = b19_p10;
            b17_p11 = b19_p11;
            b17_p12 = b19_p12;
            b17_p13 = b19_p13;
            goto b17;
        }
        else
        {
            b20_p1 = b19_p1;
            b20_p2 = b19_p2;
            b20_p3 = b19_p3;
            b20_p4 = b19_p4;
            b20_p5 = b19_p5;
            b20_p6 = b19_p6;
            b20_p7 = b19_p7;
            b20_p8 = b19_p8;
            b20_p9 = b19_p9;
            b20_p10 = b19_p10;
            b20_p11 = b19_p11;
            b20_p12 = b19_p12;
            b20_p13 = b19_p13;
            goto b20;
        }
b20:;
        int64_t b20_v14 = (b20_p1).tag;
        bool b20_v16 = (b20_v14 == INT64_C(0));
        if (b20_v16)
        {
            b18_p1 = b20_p1;
            b18_p2 = b20_p2;
            b18_p3 = b20_p3;
            b18_p4 = b20_p4;
            b18_p5 = b20_p5;
            b18_p6 = b20_p6;
            b18_p7 = b20_p7;
            b18_p8 = b20_p8;
            b18_p9 = b20_p9;
            b18_p10 = b20_p10;
            b18_p11 = b20_p11;
            b18_p12 = b20_p12;
            b18_p13 = b20_p13;
            goto b18;
        }
        else
        {
            b16_p1 = b20_p1;
            b16_p2 = b20_p2;
            b16_p3 = b20_p3;
            b16_p4 = b20_p4;
            b16_p5 = b20_p5;
            b16_p6 = b20_p6;
            b16_p7 = b20_p7;
            b16_p8 = b20_p8;
            b16_p9 = b20_p9;
            b16_p10 = b20_p10;
            b16_p11 = b20_p11;
            b16_p12 = b20_p12;
            b16_p13 = b20_p13;
            goto b16;
        }
b18:;
        struct let_s14 b18_v14 = ((b18_p1).payload).f0;
        int64_t b18_v16 = (b18_v14).value;
        int64_t b18_v17 = ((int64_t)(((uint64_t)INT64_C(0)) - ((uint64_t)b18_v16)));
        (*b18_p7) = b18_v17;
        int64_t b18_v19 = (b18_v14).pos;
        (*b18_p5) = b18_v19;
        {
            b16_p1 = b18_p1;
            b16_p2 = b18_p2;
            b16_p3 = b18_p3;
            b16_p4 = b18_p4;
            b16_p5 = b18_p5;
            b16_p6 = b18_p6;
            b16_p7 = b18_p7;
            b16_p8 = b18_p8;
            b16_p9 = b18_p9;
            b16_p10 = b18_p10;
            b16_p11 = b18_p11;
            b16_p12 = b18_p12;
            b16_p13 = b18_p13;
            goto b16;
        }
b16:;
        {
            b13_p1 = b16_p2;
            b13_p2 = b16_p3;
            b13_p3 = b16_p4;
            b13_p4 = b16_p5;
            b13_p5 = b16_p6;
            b13_p6 = b16_p7;
            b13_p7 = b16_p8;
            b13_p8 = b16_p9;
            b13_p9 = b16_p11;
            b13_p10 = b16_p12;
            b13_p11 = b16_p13;
            goto b13;
        }
b13:;
        {
            b2_p1 = b13_p1;
            b2_p2 = b13_p2;
            b2_p3 = b13_p3;
            b2_p4 = b13_p4;
            b2_p5 = b13_p5;
            b2_p6 = b13_p6;
            b2_p7 = b13_p7;
            b2_p8 = b13_p8;
            b2_p9 = b13_p9;
            b2_p10 = b13_p10;
            b2_p11 = b13_p11;
            goto b2;
        }
b17:;
        struct let_s15 b17_v14 = ((b17_p1).payload).f1;
        int64_t b17_v15 = (b17_v14).at;
        struct let_s15 b17_v16 = ((struct let_s15){b17_v15});
        struct let_s13 b17_v17 = ((struct let_s13){.tag = INT64_C(1), .payload = ((union let_u13){.f1 = b17_v16})});
        return b17_v17;
b3:;
        int64_t b3_v13 = (*b3_p4);
        int64_t b3_v15 = ((int64_t)(((uint64_t)b3_v13) + ((uint64_t)INT64_C(1))));
        struct let_s3 b3_v16 = let_expr_construct(b3_p5, b3_p8, b3_p9, b3_p10, b3_p11);
        struct let_s16 b3_v17 = let_expr_advance_0(b3_v16, b3_p1);
        struct let_s17 b3_v18 = let_expr_advance_1(b3_v17, b3_v15);
        struct let_s18 b3_v19 = let_expr_advance_2(b3_v18, INT64_C(1));
        struct let_s13 b3_v20 = let_expr_run(b3_v19);
        {
            b8_p1 = b3_v20;
            b8_p2 = b3_p1;
            b8_p3 = b3_p2;
            b8_p4 = b3_p3;
            b8_p5 = b3_p4;
            b8_p6 = b3_p5;
            b8_p7 = b3_p6;
            b8_p8 = b3_p7;
            b8_p9 = b3_p8;
            b8_p10 = b3_v20;
            b8_p11 = b3_p9;
            b8_p12 = b3_p10;
            b8_p13 = b3_p11;
            goto b8;
        }
b8:;
        int64_t b8_v14 = (b8_p1).tag;
        bool b8_v16 = (b8_v14 == INT64_C(1));
        if (b8_v16)
        {
            b6_p1 = b8_p1;
            b6_p2 = b8_p2;
            b6_p3 = b8_p3;
            b6_p4 = b8_p4;
            b6_p5 = b8_p5;
            b6_p6 = b8_p6;
            b6_p7 = b8_p7;
            b6_p8 = b8_p8;
            b6_p9 = b8_p9;
            b6_p10 = b8_p10;
            b6_p11 = b8_p11;
            b6_p12 = b8_p12;
            b6_p13 = b8_p13;
            goto b6;
        }
        else
        {
            b9_p1 = b8_p1;
            b9_p2 = b8_p2;
            b9_p3 = b8_p3;
            b9_p4 = b8_p4;
            b9_p5 = b8_p5;
            b9_p6 = b8_p6;
            b9_p7 = b8_p7;
            b9_p8 = b8_p8;
            b9_p9 = b8_p9;
            b9_p10 = b8_p10;
            b9_p11 = b8_p11;
            b9_p12 = b8_p12;
            b9_p13 = b8_p13;
            goto b9;
        }
b9:;
        int64_t b9_v14 = (b9_p1).tag;
        bool b9_v16 = (b9_v14 == INT64_C(0));
        if (b9_v16)
        {
            b7_p1 = b9_p1;
            b7_p2 = b9_p2;
            b7_p3 = b9_p3;
            b7_p4 = b9_p4;
            b7_p5 = b9_p5;
            b7_p6 = b9_p6;
            b7_p7 = b9_p7;
            b7_p8 = b9_p8;
            b7_p9 = b9_p9;
            b7_p10 = b9_p10;
            b7_p11 = b9_p11;
            b7_p12 = b9_p12;
            b7_p13 = b9_p13;
            goto b7;
        }
        else
        {
            b5_p1 = b9_p1;
            b5_p2 = b9_p2;
            b5_p3 = b9_p3;
            b5_p4 = b9_p4;
            b5_p5 = b9_p5;
            b5_p6 = b9_p6;
            b5_p7 = b9_p7;
            b5_p8 = b9_p8;
            b5_p9 = b9_p9;
            b5_p10 = b9_p10;
            b5_p11 = b9_p11;
            b5_p12 = b9_p12;
            b5_p13 = b9_p13;
            goto b5;
        }
b7:;
        struct let_s14 b7_v14 = ((b7_p1).payload).f0;
        int64_t b7_v15 = (b7_v14).value;
        (*b7_p7) = b7_v15;
        int64_t b7_v17 = (b7_v14).pos;
        struct let_s7 b7_v18 = let_skip_advance_0(b7_p6, b7_p2);
        struct let_s8 b7_v19 = let_skip_advance_1(b7_v18, b7_v17);
        int64_t b7_v20 = let_skip_run(b7_v19);
        (*b7_p5) = b7_v20;
        int64_t b7_v22 = (*b7_p5);
        struct let_s5 b7_v23 = let_byte_at_advance_0(b7_p9, b7_p2);
        struct let_s6 b7_v24 = let_byte_at_advance_1(b7_v23, b7_v22);
        int64_t b7_v25 = let_byte_at_run(b7_v24);
        bool b7_v27 = (b7_v25 != INT64_C(41));
        if (b7_v27)
        {
            b11_p1 = b7_p1;
            b11_p2 = b7_p2;
            b11_p3 = b7_p3;
            b11_p4 = b7_p4;
            b11_p5 = b7_p5;
            b11_p6 = b7_p6;
            b11_p7 = b7_p7;
            b11_p8 = b7_p8;
            b11_p9 = b7_p9;
            b11_p10 = b7_p10;
            b11_p11 = b7_v14;
            b11_p12 = b7_p11;
            b11_p13 = b7_p12;
            b11_p14 = b7_p13;
            goto b11;
        }
        else
        {
            b12_p1 = b7_p1;
            b12_p2 = b7_p2;
            b12_p3 = b7_p3;
            b12_p4 = b7_p4;
            b12_p5 = b7_p5;
            b12_p6 = b7_p6;
            b12_p7 = b7_p7;
            b12_p8 = b7_p8;
            b12_p9 = b7_p9;
            b12_p10 = b7_p10;
            b12_p11 = b7_v14;
            b12_p12 = b7_p11;
            b12_p13 = b7_p12;
            b12_p14 = b7_p13;
            goto b12;
        }
b12:;
        {
            b10_p1 = b12_p1;
            b10_p2 = b12_p2;
            b10_p3 = b12_p3;
            b10_p4 = b12_p4;
            b10_p5 = b12_p5;
            b10_p6 = b12_p6;
            b10_p7 = b12_p7;
            b10_p8 = b12_p8;
            b10_p9 = b12_p9;
            b10_p10 = b12_p10;
            b10_p11 = b12_p11;
            b10_p12 = b12_p12;
            b10_p13 = b12_p13;
            b10_p14 = b12_p14;
            goto b10;
        }
b10:;
        int64_t b10_v15 = (*b10_p5);
        int64_t b10_v17 = ((int64_t)(((uint64_t)b10_v15) + ((uint64_t)INT64_C(1))));
        (*b10_p5) = b10_v17;
        {
            b5_p1 = b10_p1;
            b5_p2 = b10_p2;
            b5_p3 = b10_p3;
            b5_p4 = b10_p4;
            b5_p5 = b10_p5;
            b5_p6 = b10_p6;
            b5_p7 = b10_p7;
            b5_p8 = b10_p8;
            b5_p9 = b10_p9;
            b5_p10 = b10_p10;
            b5_p11 = b10_p12;
            b5_p12 = b10_p13;
            b5_p13 = b10_p14;
            goto b5;
        }
b5:;
        {
            b2_p1 = b5_p2;
            b2_p2 = b5_p3;
            b2_p3 = b5_p4;
            b2_p4 = b5_p5;
            b2_p5 = b5_p6;
            b2_p6 = b5_p7;
            b2_p7 = b5_p8;
            b2_p8 = b5_p9;
            b2_p9 = b5_p11;
            b2_p10 = b5_p12;
            b2_p11 = b5_p13;
            goto b2;
        }
b2:;
        {
            b27_p1 = b2_p1;
            b27_p2 = b2_p2;
            b27_p3 = b2_p3;
            b27_p4 = b2_p4;
            b27_p5 = b2_p5;
            b27_p6 = b2_p6;
            b27_p7 = b2_p7;
            b27_p8 = b2_p8;
            b27_p9 = b2_p9;
            b27_p10 = b2_p10;
            b27_p11 = b2_p11;
            goto b27;
        }
b27:;
        if (true)
        {
            b29_p1 = b27_p1;
            b29_p2 = b27_p2;
            b29_p3 = b27_p3;
            b29_p4 = b27_p4;
            b29_p5 = b27_p5;
            b29_p6 = b27_p6;
            b29_p7 = b27_p7;
            b29_p8 = b27_p8;
            b29_p9 = b27_p9;
            b29_p10 = b27_p10;
            b29_p11 = b27_p11;
            goto b29;
        }
        else
        {
            b28_p1 = b27_p1;
            b28_p2 = b27_p2;
            b28_p3 = b27_p3;
            b28_p4 = b27_p4;
            b28_p5 = b27_p5;
            b28_p6 = b27_p6;
            b28_p7 = b27_p7;
            b28_p8 = b27_p8;
            b28_p9 = b27_p9;
            b28_p10 = b27_p10;
            b28_p11 = b27_p11;
            goto b28;
        }
b29:;
        int64_t b29_v12 = (*b29_p4);
        struct let_s7 b29_v13 = let_skip_advance_0(b29_p5, b29_p1);
        struct let_s8 b29_v14 = let_skip_advance_1(b29_v13, b29_v12);
        int64_t b29_v15 = let_skip_run(b29_v14);
        (*b29_p4) = b29_v15;
        int64_t b29_v17 = (*b29_p4);
        struct let_s5 b29_v18 = let_byte_at_advance_0(b29_p8, b29_p1);
        struct let_s6 b29_v19 = let_byte_at_advance_1(b29_v18, b29_v17);
        int64_t b29_v20 = let_byte_at_run(b29_v19);
        struct let_s9 b29_v21 = let_prec_advance_0(b29_p10, b29_v20);
        int64_t b29_v22 = let_prec_run(b29_v21);
        bool b29_v24 = (b29_v22 == INT64_C(0));
        if (b29_v24)
        {
            b31_p1 = b29_p1;
            b31_p2 = b29_p2;
            b31_p3 = b29_p3;
            b31_p4 = b29_p4;
            b31_p5 = b29_p5;
            b31_p6 = b29_p6;
            b31_p7 = b29_p7;
            b31_p8 = b29_p8;
            b31_p9 = b29_p9;
            b31_p10 = b29_v20;
            b31_p11 = b29_v22;
            b31_p12 = b29_p10;
            b31_p13 = b29_p11;
            b31_p14 = b29_v24;
            goto b31;
        }
        else
        {
            b32_p1 = b29_p1;
            b32_p2 = b29_p2;
            b32_p3 = b29_p3;
            b32_p4 = b29_p4;
            b32_p5 = b29_p5;
            b32_p6 = b29_p6;
            b32_p7 = b29_p7;
            b32_p8 = b29_p8;
            b32_p9 = b29_p9;
            b32_p10 = b29_v20;
            b32_p11 = b29_v22;
            b32_p12 = b29_p10;
            b32_p13 = b29_p11;
            goto b32;
        }
b32:;
        bool b32_v14 = (b32_p11 < b32_p3);
        {
            b30_p1 = b32_p1;
            b30_p2 = b32_p2;
            b30_p3 = b32_p3;
            b30_p4 = b32_p4;
            b30_p5 = b32_p5;
            b30_p6 = b32_p6;
            b30_p7 = b32_p7;
            b30_p8 = b32_p8;
            b30_p9 = b32_p9;
            b30_p10 = b32_p10;
            b30_p11 = b32_p11;
            b30_p12 = b32_p12;
            b30_p13 = b32_p13;
            b30_p14 = b32_v14;
            goto b30;
        }
b31:;
        {
            b30_p1 = b31_p1;
            b30_p2 = b31_p2;
            b30_p3 = b31_p3;
            b30_p4 = b31_p4;
            b30_p5 = b31_p5;
            b30_p6 = b31_p6;
            b30_p7 = b31_p7;
            b30_p8 = b31_p8;
            b30_p9 = b31_p9;
            b30_p10 = b31_p10;
            b30_p11 = b31_p11;
            b30_p12 = b31_p12;
            b30_p13 = b31_p13;
            b30_p14 = b31_p14;
            goto b30;
        }
b30:;
        if (b30_p14)
        {
            b34_p1 = b30_p1;
            b34_p2 = b30_p2;
            b34_p3 = b30_p3;
            b34_p4 = b30_p4;
            b34_p5 = b30_p5;
            b34_p6 = b30_p6;
            b34_p7 = b30_p7;
            b34_p8 = b30_p8;
            b34_p9 = b30_p9;
            b34_p10 = b30_p10;
            b34_p11 = b30_p11;
            b34_p12 = b30_p12;
            b34_p13 = b30_p13;
            goto b34;
        }
        else
        {
            b35_p1 = b30_p1;
            b35_p2 = b30_p2;
            b35_p3 = b30_p3;
            b35_p4 = b30_p4;
            b35_p5 = b30_p5;
            b35_p6 = b30_p6;
            b35_p7 = b30_p7;
            b35_p8 = b30_p8;
            b35_p9 = b30_p9;
            b35_p10 = b30_p10;
            b35_p11 = b30_p11;
            b35_p12 = b30_p12;
            b35_p13 = b30_p13;
            goto b35;
        }
b35:;
        {
            b33_p1 = b35_p1;
            b33_p2 = b35_p2;
            b33_p3 = b35_p3;
            b33_p4 = b35_p4;
            b33_p5 = b35_p5;
            b33_p6 = b35_p6;
            b33_p7 = b35_p7;
            b33_p8 = b35_p8;
            b33_p9 = b35_p9;
            b33_p10 = b35_p10;
            b33_p11 = b35_p11;
            b33_p12 = b35_p12;
            b33_p13 = b35_p13;
            goto b33;
        }
b33:;
        int64_t b33_v15 = ((int64_t)(((uint64_t)b33_p11) + ((uint64_t)INT64_C(1))));
        int64_t b33_v16 = (*b33_p4);
        int64_t b33_v18 = ((int64_t)(((uint64_t)b33_v16) + ((uint64_t)INT64_C(1))));
        struct let_s3 b33_v19 = let_expr_construct(b33_p5, b33_p8, b33_p9, b33_p12, b33_p13);
        struct let_s16 b33_v20 = let_expr_advance_0(b33_v19, b33_p1);
        struct let_s17 b33_v21 = let_expr_advance_1(b33_v20, b33_v18);
        struct let_s18 b33_v22 = let_expr_advance_2(b33_v21, b33_v15);
        struct let_s13 b33_v23 = let_expr_run(b33_v22);
        {
            b39_p1 = b33_v23;
            b39_p2 = b33_p1;
            b39_p3 = b33_p2;
            b39_p4 = b33_p3;
            b39_p5 = b33_p4;
            b39_p6 = b33_p5;
            b39_p7 = b33_p6;
            b39_p8 = b33_p7;
            b39_p9 = b33_p8;
            b39_p10 = b33_p9;
            b39_p11 = b33_p10;
            b39_p12 = b33_p11;
            b39_p13 = b33_p12;
            b39_p14 = b33_v23;
            b39_p15 = b33_p13;
            goto b39;
        }
b39:;
        int64_t b39_v16 = (b39_p1).tag;
        bool b39_v18 = (b39_v16 == INT64_C(1));
        if (b39_v18)
        {
            b37_p1 = b39_p1;
            b37_p2 = b39_p2;
            b37_p3 = b39_p3;
            b37_p4 = b39_p4;
            b37_p5 = b39_p5;
            b37_p6 = b39_p6;
            b37_p7 = b39_p7;
            b37_p8 = b39_p8;
            b37_p9 = b39_p9;
            b37_p10 = b39_p10;
            b37_p11 = b39_p11;
            b37_p12 = b39_p12;
            b37_p13 = b39_p13;
            b37_p14 = b39_p14;
            b37_p15 = b39_p15;
            goto b37;
        }
        else
        {
            b40_p1 = b39_p1;
            b40_p2 = b39_p2;
            b40_p3 = b39_p3;
            b40_p4 = b39_p4;
            b40_p5 = b39_p5;
            b40_p6 = b39_p6;
            b40_p7 = b39_p7;
            b40_p8 = b39_p8;
            b40_p9 = b39_p9;
            b40_p10 = b39_p10;
            b40_p11 = b39_p11;
            b40_p12 = b39_p12;
            b40_p13 = b39_p13;
            b40_p14 = b39_p14;
            b40_p15 = b39_p15;
            goto b40;
        }
b40:;
        int64_t b40_v16 = (b40_p1).tag;
        bool b40_v18 = (b40_v16 == INT64_C(0));
        if (b40_v18)
        {
            b38_p1 = b40_p1;
            b38_p2 = b40_p2;
            b38_p3 = b40_p3;
            b38_p4 = b40_p4;
            b38_p5 = b40_p5;
            b38_p6 = b40_p6;
            b38_p7 = b40_p7;
            b38_p8 = b40_p8;
            b38_p9 = b40_p9;
            b38_p10 = b40_p10;
            b38_p11 = b40_p11;
            b38_p12 = b40_p12;
            b38_p13 = b40_p13;
            b38_p14 = b40_p14;
            b38_p15 = b40_p15;
            goto b38;
        }
        else
        {
            b36_p1 = b40_p1;
            b36_p2 = b40_p2;
            b36_p3 = b40_p3;
            b36_p4 = b40_p4;
            b36_p5 = b40_p5;
            b36_p6 = b40_p6;
            b36_p7 = b40_p7;
            b36_p8 = b40_p8;
            b36_p9 = b40_p9;
            b36_p10 = b40_p10;
            b36_p11 = b40_p11;
            b36_p12 = b40_p12;
            b36_p13 = b40_p13;
            b36_p14 = b40_p14;
            b36_p15 = b40_p15;
            goto b36;
        }
b38:;
        struct let_s14 b38_v16 = ((b38_p1).payload).f0;
        int64_t b38_v17 = (b38_v16).value;
        int64_t b38_v18 = (*b38_p7);
        struct let_s10 b38_v19 = let_apply_op_advance_0(b38_p15, b38_p11);
        struct let_s11 b38_v20 = let_apply_op_advance_1(b38_v19, b38_v18);
        struct let_s12 b38_v21 = let_apply_op_advance_2(b38_v20, b38_v17);
        int64_t b38_v22 = let_apply_op_run(b38_v21);
        (*b38_p7) = b38_v22;
        int64_t b38_v24 = (b38_v16).pos;
        (*b38_p5) = b38_v24;
        {
            b36_p1 = b38_p1;
            b36_p2 = b38_p2;
            b36_p3 = b38_p3;
            b36_p4 = b38_p4;
            b36_p5 = b38_p5;
            b36_p6 = b38_p6;
            b36_p7 = b38_p7;
            b36_p8 = b38_p8;
            b36_p9 = b38_p9;
            b36_p10 = b38_p10;
            b36_p11 = b38_p11;
            b36_p12 = b38_p12;
            b36_p13 = b38_p13;
            b36_p14 = b38_p14;
            b36_p15 = b38_p15;
            goto b36;
        }
b36:;
        {
            b27_p1 = b36_p2;
            b27_p2 = b36_p3;
            b27_p3 = b36_p4;
            b27_p4 = b36_p5;
            b27_p5 = b36_p6;
            b27_p6 = b36_p7;
            b27_p7 = b36_p8;
            b27_p8 = b36_p9;
            b27_p9 = b36_p10;
            b27_p10 = b36_p13;
            b27_p11 = b36_p15;
            goto b27;
        }
b37:;
        struct let_s15 b37_v16 = ((b37_p1).payload).f1;
        int64_t b37_v17 = (b37_v16).at;
        struct let_s15 b37_v18 = ((struct let_s15){b37_v17});
        struct let_s13 b37_v19 = ((struct let_s13){.tag = INT64_C(1), .payload = ((union let_u13){.f1 = b37_v18})});
        return b37_v19;
b34:;
        {
            b28_p1 = b34_p1;
            b28_p2 = b34_p2;
            b28_p3 = b34_p3;
            b28_p4 = b34_p4;
            b28_p5 = b34_p5;
            b28_p6 = b34_p6;
            b28_p7 = b34_p7;
            b28_p8 = b34_p8;
            b28_p9 = b34_p9;
            b28_p10 = b34_p12;
            b28_p11 = b34_p13;
            goto b28;
        }
b28:;
        int64_t b28_v12 = (*b28_p6);
        int64_t b28_v13 = (*b28_p4);
        struct let_s14 b28_v14 = ((struct let_s14){b28_v12, b28_v13});
        struct let_s13 b28_v15 = ((struct let_s13){.tag = INT64_C(0), .payload = ((union let_u13){.f0 = b28_v14})});
        return b28_v15;
b11:;
        int64_t b11_v15 = (*b11_p5);
        struct let_s15 b11_v16 = ((struct let_s15){b11_v15});
        struct let_s13 b11_v17 = ((struct let_s13){.tag = INT64_C(1), .payload = ((union let_u13){.f1 = b11_v16})});
        return b11_v17;
b6:;
        struct let_s15 b6_v14 = ((b6_p1).payload).f1;
        int64_t b6_v15 = (b6_v14).at;
        struct let_s15 b6_v16 = ((struct let_s15){b6_v15});
        struct let_s13 b6_v17 = ((struct let_s13){.tag = INT64_C(1), .payload = ((union let_u13){.f1 = b6_v16})});
        return b6_v17;
    }
}

int64_t let_eval_entry(struct let_s1 p1, const char * p2) {
    {
        struct let_s4 v3 = (p1).eval;
        struct let_s19 v4 = let_eval_advance_0(v3, p2);
        int64_t v5 = let_eval_run(v4);
        return v5;
    }
}

static struct let_s19 let_eval_advance_0(struct let_s4 p1, const char * p2) {
    {
        struct let_s3 v3 = (p1).expr;
        uint8_t v4 = (p1).byte_at;
        struct let_s2 v5 = (p1).skip;
        struct let_s19 v6 = ((struct let_s19){v3, v4, v5, p2});
        return v6;
    }
}

static int64_t let_eval_run(struct let_s19 p1) {
    {
        struct let_s13 b5_p1;
        const char * b5_p2;
        struct let_s13 b5_p3;
        struct let_s3 b5_p4;
        uint8_t b5_p5;
        struct let_s2 b5_p6;
        struct let_s13 b6_p1;
        const char * b6_p2;
        struct let_s13 b6_p3;
        struct let_s3 b6_p4;
        uint8_t b6_p5;
        struct let_s2 b6_p6;
        struct let_s13 b2_p1;
        const char * b2_p2;
        struct let_s13 b2_p3;
        struct let_s3 b2_p4;
        uint8_t b2_p5;
        struct let_s2 b2_p6;
        struct let_s13 b4_p1;
        const char * b4_p2;
        struct let_s13 b4_p3;
        struct let_s3 b4_p4;
        uint8_t b4_p5;
        struct let_s2 b4_p6;
        struct let_s13 b3_p1;
        const char * b3_p2;
        struct let_s13 b3_p3;
        struct let_s3 b3_p4;
        uint8_t b3_p5;
        struct let_s2 b3_p6;
        struct let_s13 b9_p1;
        const char * b9_p2;
        struct let_s13 b9_p3;
        struct let_s3 b9_p4;
        struct let_s14 b9_p5;
        uint8_t b9_p6;
        struct let_s2 b9_p7;
        struct let_s13 b7_p1;
        const char * b7_p2;
        struct let_s13 b7_p3;
        struct let_s3 b7_p4;
        struct let_s14 b7_p5;
        uint8_t b7_p6;
        struct let_s2 b7_p7;
        struct let_s13 b8_p1;
        const char * b8_p2;
        struct let_s13 b8_p3;
        struct let_s3 b8_p4;
        struct let_s14 b8_p5;
        uint8_t b8_p6;
        struct let_s2 b8_p7;
        struct let_s3 v2 = (p1).expr;
        uint8_t v3 = (p1).byte_at;
        struct let_s2 v4 = (p1).skip;
        const char * v5 = (p1).s;
        struct let_s16 v8 = let_expr_advance_0(v2, v5);
        struct let_s17 v9 = let_expr_advance_1(v8, INT64_C(0));
        struct let_s18 v10 = let_expr_advance_2(v9, INT64_C(1));
        struct let_s13 v11 = let_expr_run(v10);
        {
            b5_p1 = v11;
            b5_p2 = v5;
            b5_p3 = v11;
            b5_p4 = v2;
            b5_p5 = v3;
            b5_p6 = v4;
            goto b5;
        }
b5:;
        int64_t b5_v7 = (b5_p1).tag;
        bool b5_v9 = (b5_v7 == INT64_C(0));
        if (b5_v9)
        {
            b3_p1 = b5_p1;
            b3_p2 = b5_p2;
            b3_p3 = b5_p3;
            b3_p4 = b5_p4;
            b3_p5 = b5_p5;
            b3_p6 = b5_p6;
            goto b3;
        }
        else
        {
            b6_p1 = b5_p1;
            b6_p2 = b5_p2;
            b6_p3 = b5_p3;
            b6_p4 = b5_p4;
            b6_p5 = b5_p5;
            b6_p6 = b5_p6;
            goto b6;
        }
b6:;
        int64_t b6_v7 = (b6_p1).tag;
        bool b6_v9 = (b6_v7 == INT64_C(1));
        if (b6_v9)
        {
            b4_p1 = b6_p1;
            b4_p2 = b6_p2;
            b4_p3 = b6_p3;
            b4_p4 = b6_p4;
            b4_p5 = b6_p5;
            b4_p6 = b6_p6;
            goto b4;
        }
        else
        {
            b2_p1 = b6_p1;
            b2_p2 = b6_p2;
            b2_p3 = b6_p3;
            b2_p4 = b6_p4;
            b2_p5 = b6_p5;
            b2_p6 = b6_p6;
            goto b2;
        }
b2:;
        abort();
b4:;
        struct let_s15 b4_v7 = ((b4_p1).payload).f1;
        int64_t b4_v11 = (b4_v7).at;
        int64_t b4_v12 = ((int64_t)(((uint64_t)(-INT64_C(1000000))) - ((uint64_t)b4_v11)));
        return b4_v12;
b3:;
        struct let_s14 b3_v7 = ((b3_p1).payload).f0;
        int64_t b3_v8 = (b3_v7).pos;
        struct let_s7 b3_v9 = let_skip_advance_0(b3_p6, b3_p2);
        struct let_s8 b3_v10 = let_skip_advance_1(b3_v9, b3_v8);
        int64_t b3_v11 = let_skip_run(b3_v10);
        struct let_s5 b3_v12 = let_byte_at_advance_0(b3_p5, b3_p2);
        struct let_s6 b3_v13 = let_byte_at_advance_1(b3_v12, b3_v11);
        int64_t b3_v14 = let_byte_at_run(b3_v13);
        bool b3_v16 = (b3_v14 != INT64_C(0));
        if (b3_v16)
        {
            b8_p1 = b3_p1;
            b8_p2 = b3_p2;
            b8_p3 = b3_p3;
            b8_p4 = b3_p4;
            b8_p5 = b3_v7;
            b8_p6 = b3_p5;
            b8_p7 = b3_p6;
            goto b8;
        }
        else
        {
            b9_p1 = b3_p1;
            b9_p2 = b3_p2;
            b9_p3 = b3_p3;
            b9_p4 = b3_p4;
            b9_p5 = b3_v7;
            b9_p6 = b3_p5;
            b9_p7 = b3_p6;
            goto b9;
        }
b9:;
        {
            b7_p1 = b9_p1;
            b7_p2 = b9_p2;
            b7_p3 = b9_p3;
            b7_p4 = b9_p4;
            b7_p5 = b9_p5;
            b7_p6 = b9_p6;
            b7_p7 = b9_p7;
            goto b7;
        }
b7:;
        int64_t b7_v8 = (b7_p5).value;
        return b7_v8;
b8:;
        return (-INT64_C(999999));
    }
}

int64_t byte_at(const char *s, int64_t i) { return (int64_t)(unsigned char)s[i]; }
int main(void) {
    struct let_s1 m = let_module_init();
    const char *cases[] = {"1+2*3", "(1+2)*3", " 2 * (3 + 4) - 10 / 5", "-3*-(2+1)",
                           "1-2-3", "1+", "(1+2", "42 x"};
    for (int i = 0; i < 8; i++)
        printf("%s => %lld\n", cases[i], (long long)let_eval_entry(m, cases[i]));
    return 0;
}
