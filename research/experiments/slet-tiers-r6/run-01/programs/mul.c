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

static inline uint32_t abc_aot_function_0(uint32_t,uint32_t,uint32_t);
static inline uint32_t abc_aot_function_1(uint64_t);

static inline uint32_t abc_aot_function_0(uint32_t argument_0,uint32_t argument_1,uint32_t argument_2) {
  uint64_t v_3=0; (void)v_3;
  uint64_t v_4=0; (void)v_4;
  uint64_t v_5=0; (void)v_5;
  uint64_t v_8=0; (void)v_8;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_10=0; (void)v_10;
  uint64_t v_11=0; (void)v_11;
  uint64_t v_13=0; (void)v_13;
  uint32_t v_15=0; (void)v_15;
  uint64_t v_16=0; (void)v_16;
  uint64_t v_18=0; (void)v_18;
  uint32_t v_20=0; (void)v_20;
  uint64_t v_21=0; (void)v_21;
  uint64_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_26=0; (void)v_26;
  uint64_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_31=0; (void)v_31;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_34=0; (void)v_34;
  uint32_t v_36=0; (void)v_36;
  uint64_t v_38=0; (void)v_38;
  uint32_t v_40=0; (void)v_40;
  uint64_t v_41=0; (void)v_41;
  uint64_t v_43=0; (void)v_43;
  uint32_t v_45=0; (void)v_45;
  uint64_t v_46=0; (void)v_46;
  uint64_t v_49=0; (void)v_49;
  uint64_t v_51=0; (void)v_51;
  uint64_t v_52=0; (void)v_52;
  uint64_t v_54=0; (void)v_54;
  uint64_t v_56=0; (void)v_56;
  uint64_t v_57=0; (void)v_57;
  uint64_t v_59=0; (void)v_59;
  uint32_t v_61=0; (void)v_61;
  uint64_t v_63=0; (void)v_63;
  uint64_t v_64=0; (void)v_64;
  uint64_t v_65=0; (void)v_65;
  uint64_t v_66=0; (void)v_66;
  uint64_t v_67=0; (void)v_67;
  uint64_t v_68=0; (void)v_68;
  uint64_t v_69=0; (void)v_69;
  uint64_t v_71=0; (void)v_71;
  uint32_t v_73=0; (void)v_73;
  uint64_t v_74=0; (void)v_74;
  uint64_t v_76=0; (void)v_76;
  uint32_t v_78=0; (void)v_78;
  uint64_t v_79=0; (void)v_79;
  uint64_t v_81=0; (void)v_81;
  uint64_t v_82=0; (void)v_82;
  uint64_t v_83=0; (void)v_83;
  uint64_t v_84=0; (void)v_84;
  uint64_t v_86=0; (void)v_86;
  uint64_t v_87=0; (void)v_87;
  uint64_t v_88=0; (void)v_88;
  uint64_t v_89=0; (void)v_89;
  uint64_t v_90=0; (void)v_90;
  uint64_t v_92=0; (void)v_92;
  uint32_t v_94=0; (void)v_94;
  uint64_t v_96=0; (void)v_96;
  uint32_t v_98=0; (void)v_98;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_101=0; (void)v_101;
  uint32_t v_103=0; (void)v_103;
  v_11=UINT64_C(0x0000000000000021);
  v_16=UINT64_C(0x0000000000000011);
  v_21=UINT64_C(0x0000000000000000);
  v_32=UINT64_C(0x000000000000ffff);
  v_41=UINT64_C(0x0000000000000001);
  v_52=UINT64_C(0x0000000000000000);
  v_57=UINT64_C(0x0000000000000001);
  v_66=UINT64_C(0x0000000000002589);
  v_67=UINT64_C(0x0000000058bf2589);
  v_68=UINT64_C(0x0000000000000000);
  v_69=UINT64_C(0x0000000000000021);
  v_74=UINT64_C(0x0000000000000011);
  v_79=UINT64_C(0x0000000000000000);
  v_90=UINT64_C(0x000000000000ffff);
  v_99=UINT64_C(0x0000000000000001);
  v_3=argument_0;
  v_4=argument_1;
  v_5=argument_2;
  goto block_6;
block_6: ;
  {
    uint64_t edge_0=v_5;
    uint64_t edge_1=v_4;
    uint64_t edge_2=v_3;
    v_8=edge_0;
    v_9=edge_1;
    v_10=edge_2;
    goto block_7;
  }
block_7: ;
  v_13=v_9*v_11;
  v_15=(uint32_t)v_13;
  v_18=v_15+v_16;
  v_20=(uint32_t)v_18;
  if(v_10!=v_21){
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_20;
    v_23=edge_0;
    v_24=edge_1;
    v_25=edge_2;
    v_26=edge_3;
    goto block_22;
  }
  }
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_20;
    v_28=edge_0;
    v_29=edge_1;
    v_30=edge_2;
    v_31=edge_3;
    goto block_27;
  }
block_22: ;
  v_34=v_26&v_32;
  v_36=(uint32_t)v_34;
  v_38=v_23+v_36;
  v_40=(uint32_t)v_38;
  v_43=v_25-v_41;
  v_45=(uint32_t)v_43;
  {
    uint64_t edge_0=v_40;
    uint64_t edge_1=v_26;
    uint64_t edge_2=v_45;
    v_8=edge_0;
    v_9=edge_1;
    v_10=edge_2;
    goto block_7;
  }
block_27: ;
  return v_28;
}

static inline uint32_t abc_aot_function_1(uint64_t argument_0) {
  uint64_t v_3=0; (void)v_3;
  uint64_t v_4=0; (void)v_4;
  uint64_t v_5=0; (void)v_5;
  uint64_t v_8=0; (void)v_8;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_10=0; (void)v_10;
  uint64_t v_11=0; (void)v_11;
  uint64_t v_13=0; (void)v_13;
  uint32_t v_15=0; (void)v_15;
  uint64_t v_16=0; (void)v_16;
  uint64_t v_18=0; (void)v_18;
  uint32_t v_20=0; (void)v_20;
  uint64_t v_21=0; (void)v_21;
  uint64_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_26=0; (void)v_26;
  uint64_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_31=0; (void)v_31;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_34=0; (void)v_34;
  uint32_t v_36=0; (void)v_36;
  uint64_t v_38=0; (void)v_38;
  uint32_t v_40=0; (void)v_40;
  uint64_t v_41=0; (void)v_41;
  uint64_t v_43=0; (void)v_43;
  uint32_t v_45=0; (void)v_45;
  uint64_t v_46=0; (void)v_46;
  uint64_t v_49=0; (void)v_49;
  uint64_t v_51=0; (void)v_51;
  uint64_t v_52=0; (void)v_52;
  uint64_t v_54=0; (void)v_54;
  uint64_t v_56=0; (void)v_56;
  uint64_t v_57=0; (void)v_57;
  uint64_t v_59=0; (void)v_59;
  uint32_t v_61=0; (void)v_61;
  uint64_t v_63=0; (void)v_63;
  uint64_t v_64=0; (void)v_64;
  uint64_t v_65=0; (void)v_65;
  uint64_t v_66=0; (void)v_66;
  uint64_t v_67=0; (void)v_67;
  uint64_t v_68=0; (void)v_68;
  uint64_t v_69=0; (void)v_69;
  uint64_t v_71=0; (void)v_71;
  uint32_t v_73=0; (void)v_73;
  uint64_t v_74=0; (void)v_74;
  uint64_t v_76=0; (void)v_76;
  uint32_t v_78=0; (void)v_78;
  uint64_t v_79=0; (void)v_79;
  uint64_t v_81=0; (void)v_81;
  uint64_t v_82=0; (void)v_82;
  uint64_t v_83=0; (void)v_83;
  uint64_t v_84=0; (void)v_84;
  uint64_t v_86=0; (void)v_86;
  uint64_t v_87=0; (void)v_87;
  uint64_t v_88=0; (void)v_88;
  uint64_t v_89=0; (void)v_89;
  uint64_t v_90=0; (void)v_90;
  uint64_t v_92=0; (void)v_92;
  uint32_t v_94=0; (void)v_94;
  uint64_t v_96=0; (void)v_96;
  uint32_t v_98=0; (void)v_98;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_101=0; (void)v_101;
  uint32_t v_103=0; (void)v_103;
  v_11=UINT64_C(0x0000000000000021);
  v_16=UINT64_C(0x0000000000000011);
  v_21=UINT64_C(0x0000000000000000);
  v_32=UINT64_C(0x000000000000ffff);
  v_41=UINT64_C(0x0000000000000001);
  v_52=UINT64_C(0x0000000000000000);
  v_57=UINT64_C(0x0000000000000001);
  v_66=UINT64_C(0x0000000000002589);
  v_67=UINT64_C(0x0000000058bf2589);
  v_68=UINT64_C(0x0000000000000000);
  v_69=UINT64_C(0x0000000000000021);
  v_74=UINT64_C(0x0000000000000011);
  v_79=UINT64_C(0x0000000000000000);
  v_90=UINT64_C(0x000000000000ffff);
  v_99=UINT64_C(0x0000000000000001);
  v_46=argument_0;
  goto block_47;
block_47: ;
  {
    uint64_t edge_0=v_46;
    v_49=edge_0;
    goto block_48;
  }
block_48: ;
  {
    uint64_t edge_0=v_49;
    v_51=edge_0;
    goto block_50;
  }
block_50: ;
  if(v_51!=v_52){
  {
    uint64_t edge_0=v_51;
    v_54=edge_0;
    goto block_53;
  }
  }
  {
    uint64_t edge_0=v_51;
    v_56=edge_0;
    goto block_55;
  }
block_53: ;
  v_59=v_54-v_57;
  v_61=(uint32_t)v_59;
  {
    uint64_t edge_0=v_66;
    uint64_t edge_1=v_67;
    uint64_t edge_2=v_61;
    v_63=edge_0;
    v_64=edge_1;
    v_65=edge_2;
    goto block_62;
  }
block_55: ;
  return v_68;
block_62: ;
  v_71=v_64*v_69;
  v_73=(uint32_t)v_71;
  v_76=v_73+v_74;
  v_78=(uint32_t)v_76;
  if(v_65!=v_79){
  {
    uint64_t edge_0=v_63;
    uint64_t edge_1=v_64;
    uint64_t edge_2=v_65;
    uint64_t edge_3=v_78;
    v_81=edge_0;
    v_82=edge_1;
    v_83=edge_2;
    v_84=edge_3;
    goto block_80;
  }
  }
  {
    uint64_t edge_0=v_63;
    uint64_t edge_1=v_64;
    uint64_t edge_2=v_65;
    uint64_t edge_3=v_78;
    v_86=edge_0;
    v_87=edge_1;
    v_88=edge_2;
    v_89=edge_3;
    goto block_85;
  }
block_80: ;
  v_92=v_84&v_90;
  v_94=(uint32_t)v_92;
  v_96=v_81+v_94;
  v_98=(uint32_t)v_96;
  v_101=v_83-v_99;
  v_103=(uint32_t)v_101;
  {
    uint64_t edge_0=v_98;
    uint64_t edge_1=v_84;
    uint64_t edge_2=v_103;
    v_63=edge_0;
    v_64=edge_1;
    v_65=edge_2;
    goto block_62;
  }
block_85: ;
  return v_86;
}

int abc_export_main(const uint64_t *arguments,size_t argument_count,uint64_t *results,size_t result_capacity,abc_aot_error *error) {
  abc_aot_clear(error);
  if(argument_count!=1)return ABC_AOT_ARGUMENTS;
  if(result_capacity<1)return ABC_AOT_RESULTS;
  if(1&&!arguments)return ABC_AOT_ARGUMENTS;
  if(!results)return ABC_AOT_RESULTS;
  results[0]=abc_aot_function_1(arguments[0]);
  return ABC_AOT_OK;
}

const abc_aot_export abc_aot_exports[] = {
  {"main",1,1,abc_export_main},
};
const size_t abc_aot_export_count=1;
const abc_aot_export *abc_aot_find(const char *name) {
  size_t i; if(!name)return NULL;
  for(i=0;i<abc_aot_export_count;i++)if(!strcmp(name,abc_aot_exports[i].name))return &abc_aot_exports[i];
  return NULL;
}
