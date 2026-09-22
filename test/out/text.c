#include <stdbool.h>
#include <inttypes.h>

struct let_text {
    char* data;
    uint64_t size;
};

extern void let_trap(char* reason);

struct let_val_1 {
    bool f0;
    bool f1;
};

struct let_val_2 {
    bool f0;
    bool f1;
    struct let_val_1 f2;
    uint8_t f3;
};

struct let_ret_1 {
    struct let_val_2 r0;
    struct let_val_2 r1;
};

extern void print_bool(bool a1);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static uint8_t let_show_3(bool p1_1, bool p1_2);

static uint8_t let_show_3_2(void);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        let_show_3_2();
        return ((struct let_ret_1){((struct let_val_2){true, true, ((struct let_val_1){true, true}), INT64_C(0)}), ((struct let_val_2){true, true, ((struct let_val_1){true, true}), INT64_C(0)})});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static uint8_t let_show_3(bool p1_1, bool p1_2) {
    {
        goto b1;
b1:;
        print_bool(p1_1);
        print_bool(p1_2);
        return INT64_C(0);
    }
}

static uint8_t let_show_3_2(void) {
    {
        goto b1;
b1:;
        print_bool(true);
        print_bool(true);
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

struct let_text mark(struct let_text text){ fwrite(text.data,1,(size_t)text.size,stdout); fputc('\n',stdout); return text; }

void let_trap(char* reason){ fputs("trap: ",stderr); fputs(reason,stderr); fputc('\n',stderr); abort(); }

int main(void){ let_module_init(); return 0; }
