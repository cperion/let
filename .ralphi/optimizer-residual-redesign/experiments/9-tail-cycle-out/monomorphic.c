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

static inline uint32_t abc_aot_function_0(uint32_t,uint32_t);
static inline uint32_t abc_aot_function_1(uint32_t,uint32_t);
static inline uint32_t abc_aot_function_2(void);

static inline uint32_t abc_aot_function_0(uint32_t argument_0,uint32_t argument_1) {
  uint64_t v_4=0; (void)v_4;
  uint64_t v_5=0; (void)v_5;
  uint64_t v_8=0; (void)v_8;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_10=0; (void)v_10;
  uint64_t v_12=0; (void)v_12;
  uint64_t v_13=0; (void)v_13;
  uint64_t v_15=0; (void)v_15;
  uint64_t v_16=0; (void)v_16;
  uint64_t v_17=0; (void)v_17;
  uint64_t v_19=0; (void)v_19;
  uint32_t v_21=0; (void)v_21;
  uint64_t v_22=0; (void)v_22;
  uint64_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_33=0; (void)v_33;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_36=0; (void)v_36;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_39=0; (void)v_39;
  uint32_t v_41=0; (void)v_41;
  uint64_t v_42=0; (void)v_42;
  uint64_t v_43=0; (void)v_43;
  uint64_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  v_10=UINT64_C(0x0000000000000000);
  v_17=UINT64_C(0x0000000000000001);
  v_22=UINT64_C(0x0000000000000009);
  v_23=UINT64_C(0x0000000000000009);
  v_30=UINT64_C(0x0000000000000000);
  v_37=UINT64_C(0x0000000000000001);
  v_42=UINT64_C(0x0000000000000009);
  v_43=UINT64_C(0x000000000000000a);
  v_46=UINT64_C(0x0000000000000004);
  v_47=UINT64_C(0x0000000000000009);
  v_4=argument_0;
  v_5=argument_1;
  goto block_6;
block_6: ;
  {
    uint64_t edge_0=v_5;
    uint64_t edge_1=v_4;
    v_8=edge_0;
    v_9=edge_1;
    goto block_7;
  }
block_7: ;
  if(v_9!=v_10){
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    v_12=edge_0;
    v_13=edge_1;
    goto block_11;
  }
  }
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    v_15=edge_0;
    v_16=edge_1;
    goto block_14;
  }
block_11: ;
  v_19=v_13-v_17;
  v_21=(uint32_t)v_19;
  return abc_aot_function_1(v_21,v_22);
block_14: ;
  return v_23;
}

static inline uint32_t abc_aot_function_1(uint32_t argument_0,uint32_t argument_1) {
  uint64_t v_4=0; (void)v_4;
  uint64_t v_5=0; (void)v_5;
  uint64_t v_8=0; (void)v_8;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_10=0; (void)v_10;
  uint64_t v_12=0; (void)v_12;
  uint64_t v_13=0; (void)v_13;
  uint64_t v_15=0; (void)v_15;
  uint64_t v_16=0; (void)v_16;
  uint64_t v_17=0; (void)v_17;
  uint64_t v_19=0; (void)v_19;
  uint32_t v_21=0; (void)v_21;
  uint64_t v_22=0; (void)v_22;
  uint64_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_33=0; (void)v_33;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_36=0; (void)v_36;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_39=0; (void)v_39;
  uint32_t v_41=0; (void)v_41;
  uint64_t v_42=0; (void)v_42;
  uint64_t v_43=0; (void)v_43;
  uint64_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  v_10=UINT64_C(0x0000000000000000);
  v_17=UINT64_C(0x0000000000000001);
  v_22=UINT64_C(0x0000000000000009);
  v_23=UINT64_C(0x0000000000000009);
  v_30=UINT64_C(0x0000000000000000);
  v_37=UINT64_C(0x0000000000000001);
  v_42=UINT64_C(0x0000000000000009);
  v_43=UINT64_C(0x000000000000000a);
  v_46=UINT64_C(0x0000000000000004);
  v_47=UINT64_C(0x0000000000000009);
  v_24=argument_0;
  v_25=argument_1;
  goto block_26;
block_26: ;
  {
    uint64_t edge_0=v_25;
    uint64_t edge_1=v_24;
    v_28=edge_0;
    v_29=edge_1;
    goto block_27;
  }
block_27: ;
  if(v_29!=v_30){
  {
    uint64_t edge_0=v_28;
    uint64_t edge_1=v_29;
    v_32=edge_0;
    v_33=edge_1;
    goto block_31;
  }
  }
  {
    uint64_t edge_0=v_28;
    uint64_t edge_1=v_29;
    v_35=edge_0;
    v_36=edge_1;
    goto block_34;
  }
block_31: ;
  v_39=v_33-v_37;
  v_41=(uint32_t)v_39;
  return abc_aot_function_0(v_41,v_42);
block_34: ;
  return v_43;
}

static inline uint32_t abc_aot_function_2(void) {
  uint64_t v_4=0; (void)v_4;
  uint64_t v_5=0; (void)v_5;
  uint64_t v_8=0; (void)v_8;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_10=0; (void)v_10;
  uint64_t v_12=0; (void)v_12;
  uint64_t v_13=0; (void)v_13;
  uint64_t v_15=0; (void)v_15;
  uint64_t v_16=0; (void)v_16;
  uint64_t v_17=0; (void)v_17;
  uint64_t v_19=0; (void)v_19;
  uint32_t v_21=0; (void)v_21;
  uint64_t v_22=0; (void)v_22;
  uint64_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_33=0; (void)v_33;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_36=0; (void)v_36;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_39=0; (void)v_39;
  uint32_t v_41=0; (void)v_41;
  uint64_t v_42=0; (void)v_42;
  uint64_t v_43=0; (void)v_43;
  uint64_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  v_10=UINT64_C(0x0000000000000000);
  v_17=UINT64_C(0x0000000000000001);
  v_22=UINT64_C(0x0000000000000009);
  v_23=UINT64_C(0x0000000000000009);
  v_30=UINT64_C(0x0000000000000000);
  v_37=UINT64_C(0x0000000000000001);
  v_42=UINT64_C(0x0000000000000009);
  v_43=UINT64_C(0x000000000000000a);
  v_46=UINT64_C(0x0000000000000004);
  v_47=UINT64_C(0x0000000000000009);
  goto block_44;
block_44: ;
  {
    goto block_45;
  }
block_45: ;
  return abc_aot_function_0(v_46,v_47);
}

int abc_export_main(const uint64_t *arguments,size_t argument_count,uint64_t *results,size_t result_capacity,abc_aot_error *error) {
  abc_aot_clear(error);
  if(argument_count!=0)return ABC_AOT_ARGUMENTS;
  if(result_capacity<1)return ABC_AOT_RESULTS;
  if(0&&!arguments)return ABC_AOT_ARGUMENTS;
  if(!results)return ABC_AOT_RESULTS;
  results[0]=abc_aot_function_2();
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
