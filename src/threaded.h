#ifndef ABC_THREADED_H
#define ABC_THREADED_H
#include "internal.h"
#include "generated/execution_forms.h"
typedef uint64_t abc_value;
typedef union abc_thread_word abc_thread_word;
#define ABC_THREAD_CC __attribute__((preserve_none))
#define ABC_THREAD_ARGS const abc_thread_word *ip,abc_value *asp,abc_value *bsp,abc_value *csp, \
    abc_value r0,abc_value r1,abc_value r2,abc_value r3,abc_value r4,abc_value r5,abc_value r6
#define ABC_THREAD_PASS ip,asp,bsp,csp,r0,r1,r2,r3,r4,r5,r6
typedef ABC_THREAD_CC uint64_t (*abc_thread_handler)(ABC_THREAD_ARGS);
union abc_thread_word { abc_thread_handler handler; uint64_t bits; const abc_thread_word *target; };
_Static_assert(sizeof(abc_thread_word)==8 && _Alignof(abc_thread_word)==8,"threaded word layout");
typedef struct { abc_thread_handler handler; uint8_t words,target_word; } abc_thread_form;
extern const abc_thread_form abc_thread_forms[ABC_FORM_COUNT];
#endif
