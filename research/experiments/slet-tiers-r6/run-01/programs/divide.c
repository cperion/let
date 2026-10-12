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

static inline int abc_aot_function_0(const uint64_t *,uint64_t *,abc_aot_error *);
static inline int abc_aot_function_1(const uint64_t *,uint64_t *,abc_aot_error *);

static inline int abc_aot_function_0(const uint64_t *arguments,uint64_t *results,abc_aot_error *error) {
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
  uint64_t v_19=0; (void)v_19;
  uint64_t v_20=0; (void)v_20;
  uint64_t v_21=0; (void)v_21;
  uint64_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_26=0; (void)v_26;
  uint64_t v_27=0; (void)v_27;
  uint64_t v_29=0; (void)v_29;
  uint32_t v_31=0; (void)v_31;
  uint64_t v_33=0; (void)v_33;
  uint32_t v_35=0; (void)v_35;
  uint64_t v_37=0; (void)v_37;
  uint32_t v_39=0; (void)v_39;
  uint64_t v_40=0; (void)v_40;
  uint64_t v_42=0; (void)v_42;
  uint32_t v_44=0; (void)v_44;
  uint64_t v_45=0; (void)v_45;
  uint64_t v_47=0; (void)v_47;
  uint32_t v_49=0; (void)v_49;
  uint64_t v_50=0; (void)v_50;
  uint64_t v_53=0; (void)v_53;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_56=0; (void)v_56;
  uint64_t v_58=0; (void)v_58;
  uint64_t v_60=0; (void)v_60;
  uint64_t v_61=0; (void)v_61;
  uint64_t v_63=0; (void)v_63;
  uint32_t v_65=0; (void)v_65;
  uint64_t v_67=0; (void)v_67;
  uint64_t v_68=0; (void)v_68;
  uint64_t v_69=0; (void)v_69;
  uint64_t v_70=0; (void)v_70;
  uint64_t v_71=0; (void)v_71;
  uint64_t v_72=0; (void)v_72;
  uint64_t v_73=0; (void)v_73;
  uint64_t v_75=0; (void)v_75;
  uint32_t v_77=0; (void)v_77;
  uint64_t v_78=0; (void)v_78;
  uint64_t v_80=0; (void)v_80;
  uint64_t v_81=0; (void)v_81;
  uint64_t v_82=0; (void)v_82;
  uint64_t v_83=0; (void)v_83;
  uint64_t v_85=0; (void)v_85;
  uint64_t v_86=0; (void)v_86;
  uint64_t v_87=0; (void)v_87;
  uint64_t v_88=0; (void)v_88;
  uint64_t v_89=0; (void)v_89;
  uint64_t v_91=0; (void)v_91;
  uint32_t v_93=0; (void)v_93;
  uint64_t v_95=0; (void)v_95;
  uint32_t v_97=0; (void)v_97;
  uint64_t v_99=0; (void)v_99;
  uint32_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_104=0; (void)v_104;
  uint32_t v_106=0; (void)v_106;
  uint64_t v_107=0; (void)v_107;
  uint64_t v_109=0; (void)v_109;
  uint32_t v_111=0; (void)v_111;
  (void)arguments; (void)results; (void)error;
  v_11=UINT64_C(0x0000000000000003);
  v_16=UINT64_C(0x0000000000000000);
  v_27=UINT64_C(0x0000000000000003);
  v_40=UINT64_C(0x000000009e3779b9);
  v_45=UINT64_C(0x0000000000000001);
  v_56=UINT64_C(0x0000000000000000);
  v_61=UINT64_C(0x0000000000000001);
  v_70=UINT64_C(0x0000000000000001);
  v_71=UINT64_C(0x00000000c5a8dfbe);
  v_72=UINT64_C(0x0000000000000000);
  v_73=UINT64_C(0x0000000000000003);
  v_78=UINT64_C(0x0000000000000000);
  v_89=UINT64_C(0x0000000000000003);
  v_102=UINT64_C(0x000000009e3779b9);
  v_107=UINT64_C(0x0000000000000001);
  v_3=arguments[0];
  v_4=arguments[1];
  v_5=arguments[2];
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
  v_13=0;
  if(!v_11)return abc_aot_fail(error,1,3);
  v_13=v_9/v_11;
  v_15=(uint32_t)v_13;
  if(v_10!=v_16){
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_15;
    v_18=edge_0;
    v_19=edge_1;
    v_20=edge_2;
    v_21=edge_3;
    goto block_17;
  }
  }
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_15;
    v_23=edge_0;
    v_24=edge_1;
    v_25=edge_2;
    v_26=edge_3;
    goto block_22;
  }
block_17: ;
  v_29=v_21*v_27;
  v_31=(uint32_t)v_29;
  v_33=v_19-v_31;
  v_35=(uint32_t)v_33;
  v_37=v_18+v_35;
  v_39=(uint32_t)v_37;
  v_42=v_21+v_40;
  v_44=(uint32_t)v_42;
  v_47=v_20-v_45;
  v_49=(uint32_t)v_47;
  {
    uint64_t edge_0=v_39;
    uint64_t edge_1=v_44;
    uint64_t edge_2=v_49;
    v_8=edge_0;
    v_9=edge_1;
    v_10=edge_2;
    goto block_7;
  }
block_22: ;
  results[0]=v_23;
  return ABC_AOT_OK;
}

static inline int abc_aot_function_1(const uint64_t *arguments,uint64_t *results,abc_aot_error *error) {
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
  uint64_t v_19=0; (void)v_19;
  uint64_t v_20=0; (void)v_20;
  uint64_t v_21=0; (void)v_21;
  uint64_t v_23=0; (void)v_23;
  uint64_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_26=0; (void)v_26;
  uint64_t v_27=0; (void)v_27;
  uint64_t v_29=0; (void)v_29;
  uint32_t v_31=0; (void)v_31;
  uint64_t v_33=0; (void)v_33;
  uint32_t v_35=0; (void)v_35;
  uint64_t v_37=0; (void)v_37;
  uint32_t v_39=0; (void)v_39;
  uint64_t v_40=0; (void)v_40;
  uint64_t v_42=0; (void)v_42;
  uint32_t v_44=0; (void)v_44;
  uint64_t v_45=0; (void)v_45;
  uint64_t v_47=0; (void)v_47;
  uint32_t v_49=0; (void)v_49;
  uint64_t v_50=0; (void)v_50;
  uint64_t v_53=0; (void)v_53;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_56=0; (void)v_56;
  uint64_t v_58=0; (void)v_58;
  uint64_t v_60=0; (void)v_60;
  uint64_t v_61=0; (void)v_61;
  uint64_t v_63=0; (void)v_63;
  uint32_t v_65=0; (void)v_65;
  uint64_t v_67=0; (void)v_67;
  uint64_t v_68=0; (void)v_68;
  uint64_t v_69=0; (void)v_69;
  uint64_t v_70=0; (void)v_70;
  uint64_t v_71=0; (void)v_71;
  uint64_t v_72=0; (void)v_72;
  uint64_t v_73=0; (void)v_73;
  uint64_t v_75=0; (void)v_75;
  uint32_t v_77=0; (void)v_77;
  uint64_t v_78=0; (void)v_78;
  uint64_t v_80=0; (void)v_80;
  uint64_t v_81=0; (void)v_81;
  uint64_t v_82=0; (void)v_82;
  uint64_t v_83=0; (void)v_83;
  uint64_t v_85=0; (void)v_85;
  uint64_t v_86=0; (void)v_86;
  uint64_t v_87=0; (void)v_87;
  uint64_t v_88=0; (void)v_88;
  uint64_t v_89=0; (void)v_89;
  uint64_t v_91=0; (void)v_91;
  uint32_t v_93=0; (void)v_93;
  uint64_t v_95=0; (void)v_95;
  uint32_t v_97=0; (void)v_97;
  uint64_t v_99=0; (void)v_99;
  uint32_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_104=0; (void)v_104;
  uint32_t v_106=0; (void)v_106;
  uint64_t v_107=0; (void)v_107;
  uint64_t v_109=0; (void)v_109;
  uint32_t v_111=0; (void)v_111;
  (void)arguments; (void)results; (void)error;
  v_11=UINT64_C(0x0000000000000003);
  v_16=UINT64_C(0x0000000000000000);
  v_27=UINT64_C(0x0000000000000003);
  v_40=UINT64_C(0x000000009e3779b9);
  v_45=UINT64_C(0x0000000000000001);
  v_56=UINT64_C(0x0000000000000000);
  v_61=UINT64_C(0x0000000000000001);
  v_70=UINT64_C(0x0000000000000001);
  v_71=UINT64_C(0x00000000c5a8dfbe);
  v_72=UINT64_C(0x0000000000000000);
  v_73=UINT64_C(0x0000000000000003);
  v_78=UINT64_C(0x0000000000000000);
  v_89=UINT64_C(0x0000000000000003);
  v_102=UINT64_C(0x000000009e3779b9);
  v_107=UINT64_C(0x0000000000000001);
  v_50=arguments[0];
  goto block_51;
block_51: ;
  {
    uint64_t edge_0=v_50;
    v_53=edge_0;
    goto block_52;
  }
block_52: ;
  {
    uint64_t edge_0=v_53;
    v_55=edge_0;
    goto block_54;
  }
block_54: ;
  if(v_55!=v_56){
  {
    uint64_t edge_0=v_55;
    v_58=edge_0;
    goto block_57;
  }
  }
  {
    uint64_t edge_0=v_55;
    v_60=edge_0;
    goto block_59;
  }
block_57: ;
  v_63=v_58-v_61;
  v_65=(uint32_t)v_63;
  {
    uint64_t edge_0=v_70;
    uint64_t edge_1=v_71;
    uint64_t edge_2=v_65;
    v_67=edge_0;
    v_68=edge_1;
    v_69=edge_2;
    goto block_66;
  }
block_59: ;
  results[0]=v_72;
  return ABC_AOT_OK;
block_66: ;
  v_75=0;
  if(!v_73)return abc_aot_fail(error,1,3);
  v_75=v_68/v_73;
  v_77=(uint32_t)v_75;
  if(v_69!=v_78){
  {
    uint64_t edge_0=v_67;
    uint64_t edge_1=v_68;
    uint64_t edge_2=v_69;
    uint64_t edge_3=v_77;
    v_80=edge_0;
    v_81=edge_1;
    v_82=edge_2;
    v_83=edge_3;
    goto block_79;
  }
  }
  {
    uint64_t edge_0=v_67;
    uint64_t edge_1=v_68;
    uint64_t edge_2=v_69;
    uint64_t edge_3=v_77;
    v_85=edge_0;
    v_86=edge_1;
    v_87=edge_2;
    v_88=edge_3;
    goto block_84;
  }
block_79: ;
  v_91=v_83*v_89;
  v_93=(uint32_t)v_91;
  v_95=v_81-v_93;
  v_97=(uint32_t)v_95;
  v_99=v_80+v_97;
  v_101=(uint32_t)v_99;
  v_104=v_83+v_102;
  v_106=(uint32_t)v_104;
  v_109=v_82-v_107;
  v_111=(uint32_t)v_109;
  {
    uint64_t edge_0=v_101;
    uint64_t edge_1=v_106;
    uint64_t edge_2=v_111;
    v_67=edge_0;
    v_68=edge_1;
    v_69=edge_2;
    goto block_66;
  }
block_84: ;
  results[0]=v_85;
  return ABC_AOT_OK;
}

int abc_export_main(const uint64_t *arguments,size_t argument_count,uint64_t *results,size_t result_capacity,abc_aot_error *error) {
  abc_aot_clear(error);
  if(argument_count!=1)return ABC_AOT_ARGUMENTS;
  if(result_capacity<1)return ABC_AOT_RESULTS;
  if(1&&!arguments)return ABC_AOT_ARGUMENTS;
  if(1&&!results)return ABC_AOT_RESULTS;
  return abc_aot_function_1(arguments,results,error);
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
