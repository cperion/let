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
};

struct let_ret_1 {
    struct let_val_3 r0;
    struct let_val_3 r1;
};

extern void print_int(int64_t a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static int64_t let_run_3(void);

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

static int64_t let_run_3(void) {
    {
        goto b1;
b1:;
        struct let_val_4 v1_4_c = ((struct let_val_4){INT64_C(1), INT64_C(2)});
        struct let_val_4* v1_4_0 = (&v1_4_c);
        int64_t* v1_5_0 = (&((*v1_4_0)).f0);
        int64_t v1_9_0 = let_bump_4_2(v1_5_0);
        struct let_val_4 v1_10_0 = (*v1_4_0);
        int64_t v1_11_0 = (v1_10_0).f0;
        int64_t v1_12_0 = LET_ADD(v1_11_0, v1_9_0);
        return v1_12_0;
    }
}

static int64_t let_run_3_2(void) {
    {
        goto b1;
b1:;
        struct let_val_4 v1_4_c = ((struct let_val_4){INT64_C(1), INT64_C(2)});
        struct let_val_4* v1_4_0 = (&v1_4_c);
        int64_t* v1_5_0 = (&((*v1_4_0)).f0);
        int64_t v1_9_0 = let_bump_4_2(v1_5_0);
        struct let_val_4 v1_10_0 = (*v1_4_0);
        int64_t v1_11_0 = (v1_10_0).f0;
        int64_t v1_12_0 = LET_ADD(v1_11_0, v1_9_0);
        return v1_12_0;
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
        int64_t v1_2_0 = LET_ADD(v1_1_0, INT64_C(40));
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
