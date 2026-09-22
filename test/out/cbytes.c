#include <stddef.h>
#include <stdbool.h>
#include <inttypes.h>

struct let_text {
    char* data;
    uint64_t size;
};

extern void let_trap(char* reason);

struct let_val_1 {
    bool f0;
};

struct let_val_2 {
    struct let_text f0;
    int64_t f1;
    bool f2;
    struct let_val_1 f3;
    uint8_t f4;
};

struct let_ret_1 {
    struct let_val_2 r0;
    struct let_val_2 r1;
};

extern char * getenv(const char* a1);

extern int putchar(int a1);

extern long write(int a1, const void * a2, size_t a3);

extern struct let_ret_1 let_module_init(void);

static uint8_t let_module_unload(void);

static uint8_t let_show_3(bool p1_1);

extern struct let_ret_1 let_module_init(void) {
    {
        goto b1;
b1:;
        const char* v1_3_0 = (((struct let_text){"\150\151\012", INT64_C(3)})).data;
        int64_t v1_5_0 = ((int64_t)write(((int)INT64_C(1)), v1_3_0, ((size_t)INT64_C(3))));
        const char* v1_7_0 = (((struct let_text){"\114\105\124\137\116\117\137\123\125\103\110\137\126\101\122\111\101\102\114\105\137\130\131\132", INT64_C(24)})).data;
        const char* v1_8_0 = getenv(v1_7_0);
        bool v1_9_0 = (v1_8_0 == INT64_C(0));
        struct let_val_1 v1_10_0 = ((struct let_val_1){v1_9_0});
        let_show_3(v1_9_0);
        struct let_val_2 v1_12_0 = ((struct let_val_2){((struct let_text){"\150\151\012", INT64_C(3)}), v1_5_0, v1_9_0, v1_10_0, INT64_C(0)});
        return ((struct let_ret_1){v1_12_0, v1_12_0});
    }
}

static uint8_t let_module_unload(void) {
    {
        return INT64_C(0);
    }
}

static uint8_t let_show_3(bool p1_1) {
    {
        goto b1;
b1:;
        if (p1_1)
        {
            goto b2;
        }
        else
        {
            goto b3;
        }
b2:;
        int64_t v2_2_0 = ((int64_t)putchar(((int)INT64_C(49))));
        {
            goto b4;
        }
b3:;
        int64_t v3_2_0 = ((int64_t)putchar(((int)INT64_C(48))));
        {
            goto b4;
        }
b4:;
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
