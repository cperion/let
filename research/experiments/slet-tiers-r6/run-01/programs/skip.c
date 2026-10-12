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
static inline uint32_t abc_aot_function_1(uint64_t);

static inline uint32_t abc_aot_function_0(uint32_t argument_0,uint32_t argument_1) {
  uint64_t v_3=0; (void)v_3;
  uint64_t v_4=0; (void)v_4;
  uint64_t v_7=0; (void)v_7;
  uint64_t v_8=0; (void)v_8;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_11=0; (void)v_11;
  uint32_t v_13=0; (void)v_13;
  uint64_t v_15=0; (void)v_15;
  uint32_t v_17=0; (void)v_17;
  uint64_t v_18=0; (void)v_18;
  uint64_t v_20=0; (void)v_20;
  uint32_t v_22=0; (void)v_22;
  uint32_t v_24=0; (void)v_24;
  uint32_t v_26=0; (void)v_26;
  uint64_t v_27=0; (void)v_27;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_31=0; (void)v_31;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_34=0; (void)v_34;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_36=0; (void)v_36;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_38=0; (void)v_38;
  uint64_t v_40=0; (void)v_40;
  uint32_t v_42=0; (void)v_42;
  uint64_t v_44=0; (void)v_44;
  uint32_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  uint64_t v_49=0; (void)v_49;
  uint32_t v_51=0; (void)v_51;
  uint64_t v_52=0; (void)v_52;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_57=0; (void)v_57;
  uint64_t v_58=0; (void)v_58;
  uint64_t v_60=0; (void)v_60;
  uint64_t v_62=0; (void)v_62;
  uint64_t v_63=0; (void)v_63;
  uint64_t v_65=0; (void)v_65;
  uint32_t v_67=0; (void)v_67;
  uint64_t v_69=0; (void)v_69;
  uint64_t v_70=0; (void)v_70;
  uint64_t v_71=0; (void)v_71;
  uint64_t v_72=0; (void)v_72;
  uint64_t v_73=0; (void)v_73;
  uint64_t v_75=0; (void)v_75;
  uint32_t v_77=0; (void)v_77;
  uint64_t v_79=0; (void)v_79;
  uint32_t v_81=0; (void)v_81;
  uint64_t v_82=0; (void)v_82;
  uint64_t v_84=0; (void)v_84;
  uint32_t v_86=0; (void)v_86;
  uint32_t v_88=0; (void)v_88;
  uint32_t v_90=0; (void)v_90;
  uint64_t v_91=0; (void)v_91;
  uint64_t v_93=0; (void)v_93;
  uint64_t v_94=0; (void)v_94;
  uint64_t v_95=0; (void)v_95;
  uint64_t v_96=0; (void)v_96;
  uint64_t v_98=0; (void)v_98;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_100=0; (void)v_100;
  uint64_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_104=0; (void)v_104;
  uint32_t v_106=0; (void)v_106;
  uint64_t v_108=0; (void)v_108;
  uint32_t v_110=0; (void)v_110;
  uint64_t v_111=0; (void)v_111;
  uint64_t v_113=0; (void)v_113;
  uint32_t v_115=0; (void)v_115;
  v_9=UINT64_C(0x000000000000000d);
  v_18=UINT64_C(0x0000000000000011);
  v_27=UINT64_C(0x0000000000000000);
  v_38=UINT64_C(0x0000000000000005);
  v_47=UINT64_C(0x0000000000000001);
  v_58=UINT64_C(0x0000000000000000);
  v_63=UINT64_C(0x0000000000000001);
  v_71=UINT64_C(0x000000002b1f4d63);
  v_72=UINT64_C(0x0000000092d68ca2);
  v_73=UINT64_C(0x000000000000000d);
  v_82=UINT64_C(0x0000000000000011);
  v_91=UINT64_C(0x0000000000000000);
  v_102=UINT64_C(0x0000000000000005);
  v_111=UINT64_C(0x0000000000000001);
  v_3=argument_0;
  v_4=argument_1;
  goto block_5;
block_5: ;
  {
    uint64_t edge_0=v_4;
    uint64_t edge_1=v_3;
    v_7=edge_0;
    v_8=edge_1;
    goto block_6;
  }
block_6: ;
  v_11=(v_9>=64?0:v_7<<v_9);
  v_13=(uint32_t)v_11;
  v_15=v_7^v_13;
  v_17=(uint32_t)v_15;
  v_20=(v_18>=64?0:v_17>>v_18);
  v_22=(uint32_t)v_20;
  v_24=v_17^v_22;
  v_26=(uint32_t)v_24;
  if(v_8!=v_27){
  {
    uint64_t edge_0=v_7;
    uint64_t edge_1=v_8;
    uint64_t edge_2=v_17;
    uint64_t edge_3=v_26;
    v_29=edge_0;
    v_30=edge_1;
    v_31=edge_2;
    v_32=edge_3;
    goto block_28;
  }
  }
  {
    uint64_t edge_0=v_7;
    uint64_t edge_1=v_8;
    uint64_t edge_2=v_17;
    uint64_t edge_3=v_26;
    v_34=edge_0;
    v_35=edge_1;
    v_36=edge_2;
    v_37=edge_3;
    goto block_33;
  }
block_28: ;
  v_40=(v_38>=64?0:v_32<<v_38);
  v_42=(uint32_t)v_40;
  v_44=v_32^v_42;
  v_46=(uint32_t)v_44;
  v_49=v_30-v_47;
  v_51=(uint32_t)v_49;
  {
    uint64_t edge_0=v_46;
    uint64_t edge_1=v_51;
    v_7=edge_0;
    v_8=edge_1;
    goto block_6;
  }
block_33: ;
  return v_34;
}

static inline uint32_t abc_aot_function_1(uint64_t argument_0) {
  uint64_t v_3=0; (void)v_3;
  uint64_t v_4=0; (void)v_4;
  uint64_t v_7=0; (void)v_7;
  uint64_t v_8=0; (void)v_8;
  uint64_t v_9=0; (void)v_9;
  uint64_t v_11=0; (void)v_11;
  uint32_t v_13=0; (void)v_13;
  uint64_t v_15=0; (void)v_15;
  uint32_t v_17=0; (void)v_17;
  uint64_t v_18=0; (void)v_18;
  uint64_t v_20=0; (void)v_20;
  uint32_t v_22=0; (void)v_22;
  uint32_t v_24=0; (void)v_24;
  uint32_t v_26=0; (void)v_26;
  uint64_t v_27=0; (void)v_27;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_31=0; (void)v_31;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_34=0; (void)v_34;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_36=0; (void)v_36;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_38=0; (void)v_38;
  uint64_t v_40=0; (void)v_40;
  uint32_t v_42=0; (void)v_42;
  uint64_t v_44=0; (void)v_44;
  uint32_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  uint64_t v_49=0; (void)v_49;
  uint32_t v_51=0; (void)v_51;
  uint64_t v_52=0; (void)v_52;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_57=0; (void)v_57;
  uint64_t v_58=0; (void)v_58;
  uint64_t v_60=0; (void)v_60;
  uint64_t v_62=0; (void)v_62;
  uint64_t v_63=0; (void)v_63;
  uint64_t v_65=0; (void)v_65;
  uint32_t v_67=0; (void)v_67;
  uint64_t v_69=0; (void)v_69;
  uint64_t v_70=0; (void)v_70;
  uint64_t v_71=0; (void)v_71;
  uint64_t v_72=0; (void)v_72;
  uint64_t v_73=0; (void)v_73;
  uint64_t v_75=0; (void)v_75;
  uint32_t v_77=0; (void)v_77;
  uint64_t v_79=0; (void)v_79;
  uint32_t v_81=0; (void)v_81;
  uint64_t v_82=0; (void)v_82;
  uint64_t v_84=0; (void)v_84;
  uint32_t v_86=0; (void)v_86;
  uint32_t v_88=0; (void)v_88;
  uint32_t v_90=0; (void)v_90;
  uint64_t v_91=0; (void)v_91;
  uint64_t v_93=0; (void)v_93;
  uint64_t v_94=0; (void)v_94;
  uint64_t v_95=0; (void)v_95;
  uint64_t v_96=0; (void)v_96;
  uint64_t v_98=0; (void)v_98;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_100=0; (void)v_100;
  uint64_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_104=0; (void)v_104;
  uint32_t v_106=0; (void)v_106;
  uint64_t v_108=0; (void)v_108;
  uint32_t v_110=0; (void)v_110;
  uint64_t v_111=0; (void)v_111;
  uint64_t v_113=0; (void)v_113;
  uint32_t v_115=0; (void)v_115;
  v_9=UINT64_C(0x000000000000000d);
  v_18=UINT64_C(0x0000000000000011);
  v_27=UINT64_C(0x0000000000000000);
  v_38=UINT64_C(0x0000000000000005);
  v_47=UINT64_C(0x0000000000000001);
  v_58=UINT64_C(0x0000000000000000);
  v_63=UINT64_C(0x0000000000000001);
  v_71=UINT64_C(0x000000002b1f4d63);
  v_72=UINT64_C(0x0000000092d68ca2);
  v_73=UINT64_C(0x000000000000000d);
  v_82=UINT64_C(0x0000000000000011);
  v_91=UINT64_C(0x0000000000000000);
  v_102=UINT64_C(0x0000000000000005);
  v_111=UINT64_C(0x0000000000000001);
  v_52=argument_0;
  goto block_53;
block_53: ;
  {
    uint64_t edge_0=v_52;
    v_55=edge_0;
    goto block_54;
  }
block_54: ;
  {
    uint64_t edge_0=v_55;
    v_57=edge_0;
    goto block_56;
  }
block_56: ;
  if(v_57!=v_58){
  {
    uint64_t edge_0=v_57;
    v_60=edge_0;
    goto block_59;
  }
  }
  {
    uint64_t edge_0=v_57;
    v_62=edge_0;
    goto block_61;
  }
block_59: ;
  v_65=v_60-v_63;
  v_67=(uint32_t)v_65;
  {
    uint64_t edge_0=v_71;
    uint64_t edge_1=v_67;
    v_69=edge_0;
    v_70=edge_1;
    goto block_68;
  }
block_61: ;
  return v_72;
block_68: ;
  v_75=(v_73>=64?0:v_69<<v_73);
  v_77=(uint32_t)v_75;
  v_79=v_69^v_77;
  v_81=(uint32_t)v_79;
  v_84=(v_82>=64?0:v_81>>v_82);
  v_86=(uint32_t)v_84;
  v_88=v_81^v_86;
  v_90=(uint32_t)v_88;
  if(v_70!=v_91){
  {
    uint64_t edge_0=v_69;
    uint64_t edge_1=v_70;
    uint64_t edge_2=v_81;
    uint64_t edge_3=v_90;
    v_93=edge_0;
    v_94=edge_1;
    v_95=edge_2;
    v_96=edge_3;
    goto block_92;
  }
  }
  {
    uint64_t edge_0=v_69;
    uint64_t edge_1=v_70;
    uint64_t edge_2=v_81;
    uint64_t edge_3=v_90;
    v_98=edge_0;
    v_99=edge_1;
    v_100=edge_2;
    v_101=edge_3;
    goto block_97;
  }
block_92: ;
  v_104=(v_102>=64?0:v_96<<v_102);
  v_106=(uint32_t)v_104;
  v_108=v_96^v_106;
  v_110=(uint32_t)v_108;
  v_113=v_94-v_111;
  v_115=(uint32_t)v_113;
  {
    uint64_t edge_0=v_110;
    uint64_t edge_1=v_115;
    v_69=edge_0;
    v_70=edge_1;
    goto block_68;
  }
block_97: ;
  return v_98;
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
