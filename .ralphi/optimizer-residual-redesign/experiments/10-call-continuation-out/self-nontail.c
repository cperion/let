/* generated from validated ABC residual IR */
#include <stddef.h>
#include <stdint.h>
#include <limits.h>
#include <string.h>

#ifndef ABC_AOT_ABI_DEFINED
#define ABC_AOT_ABI_DEFINED
typedef struct { uint32_t status; uint32_t offset; uint8_t reason; } abc_aot_error;
typedef int (*abc_aot_entry)(const uint64_t *, size_t, uint64_t *, size_t, abc_aot_error *);
typedef struct { const char *name; uint32_t arguments; uint32_t results; abc_aot_entry entry; } abc_aot_export;
#endif

enum { ABC_AOT_OK=0, ABC_AOT_INVALID=1, ABC_AOT_ARGUMENTS=5, ABC_AOT_ABORT=6, ABC_AOT_RESULTS=8 };
static inline int64_t abc_aot_signed(uint64_t x) {
  return x<=INT64_MAX ? (int64_t)x : -1-(int64_t)(UINT64_MAX-x);
}
static inline uint64_t abc_aot_sar(uint64_t x,uint64_t n) {
  if(n>=64)return x>>63?UINT64_MAX:0;
  if(!n)return x;
  return x>>n | (x>>63 ? UINT64_MAX<<(64-n) : 0);
}
static inline uint64_t abc_aot_pow(uint64_t x,uint64_t n) {
  uint64_t r=1; while(n){if(n&1)r*=x;x*=x;n>>=1;} return r;
}
static inline uint64_t abc_aot_signed_div(uint64_t x,uint64_t y) {
  return y==UINT64_MAX ? 0-x : (uint64_t)(abc_aot_signed(x)/abc_aot_signed(y));
}
static inline uint64_t abc_aot_signed_rem(uint64_t x,uint64_t y) {
  return y==UINT64_MAX ? 0 : (uint64_t)(abc_aot_signed(x)%abc_aot_signed(y));
}
static inline int abc_aot_fail(abc_aot_error *e,uint8_t reason,uint32_t offset) {
  if(e){e->status=ABC_AOT_ABORT;e->offset=offset;e->reason=reason;} return ABC_AOT_ABORT;
}
static inline void abc_aot_clear(abc_aot_error *e) {
  if(e){e->status=ABC_AOT_OK;e->offset=UINT32_MAX;e->reason=0;}
}

static inline uint32_t abc_aot_function_0(uint32_t);
static inline uint32_t abc_aot_function_1(void);

static inline uint32_t abc_aot_function_0(uint32_t argument_0) {
  uint64_t v_3=0; (void)v_3;
  uint64_t v_6=0; (void)v_6;
  uint64_t v_7=0; (void)v_7;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_11=0; (void)v_11;
  uint64_t v_12=0; (void)v_12;
  uint64_t v_14=0; (void)v_14;
  uint32_t v_16=0; (void)v_16;
  uint64_t v_18=0; (void)v_18;
  uint64_t v_19=0; (void)v_19;
  uint64_t v_21=0; (void)v_21;
  uint32_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_27=0; (void)v_27;
  v_7=UINT64_C(0x0000000000000000);
  v_12=UINT64_C(0x0000000000000001);
  v_19=UINT64_C(0x0000000000000003);
  v_24=UINT64_C(0x0000000000000000);
  v_27=UINT64_C(0x0000000000000005);
  v_3=argument_0;
  goto block_4;
block_4: ;
  {
    uint64_t edge_0=v_3;
    v_6=edge_0;
    goto block_5;
  }
block_5: ;
  if(v_6!=v_7){
  {
    uint64_t edge_0=v_6;
    v_9=edge_0;
    goto block_8;
  }
  }
  {
    uint64_t edge_0=v_6;
    v_11=edge_0;
    goto block_10;
  }
block_8: ;
  v_14=v_9-v_12;
  v_16=(uint32_t)v_14;
  v_18=abc_aot_function_0(v_16);
  v_21=v_18+v_19;
  v_23=(uint32_t)v_21;
  return v_23;
block_10: ;
  return v_24;
}

static inline uint32_t abc_aot_function_1(void) {
  uint64_t v_3=0; (void)v_3;
  uint64_t v_6=0; (void)v_6;
  uint64_t v_7=0; (void)v_7;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_11=0; (void)v_11;
  uint64_t v_12=0; (void)v_12;
  uint64_t v_14=0; (void)v_14;
  uint32_t v_16=0; (void)v_16;
  uint64_t v_18=0; (void)v_18;
  uint64_t v_19=0; (void)v_19;
  uint64_t v_21=0; (void)v_21;
  uint32_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_27=0; (void)v_27;
  v_7=UINT64_C(0x0000000000000000);
  v_12=UINT64_C(0x0000000000000001);
  v_19=UINT64_C(0x0000000000000003);
  v_24=UINT64_C(0x0000000000000000);
  v_27=UINT64_C(0x0000000000000005);
  goto block_25;
block_25: ;
  {
    goto block_26;
  }
block_26: ;
  return abc_aot_function_0(v_27);
}

int abc_export_main(const uint64_t *arguments,size_t argument_count,uint64_t *results,size_t result_capacity,abc_aot_error *error) {
  abc_aot_clear(error);
  if(argument_count!=0)return ABC_AOT_ARGUMENTS;
  if(result_capacity<1)return ABC_AOT_RESULTS;
  if(0&&!arguments)return ABC_AOT_ARGUMENTS;
  if(!results)return ABC_AOT_RESULTS;
  results[0]=abc_aot_function_1();
  return ABC_AOT_OK;
}

const abc_aot_export abc_aot_exports[] = {
  {"main",0,1,abc_export_main},
};
const size_t abc_aot_export_count=1;
const abc_aot_export *abc_aot_find(const char *name) {
  size_t i; if(!name)return NULL;
  for(i=0;i<abc_aot_export_count;i++)if(!strcmp(name,abc_aot_exports[i].name))return &abc_aot_exports[i];
  return NULL;
}
