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
  uint64_t v_48=0; (void)v_48;
  uint32_t v_50=0; (void)v_50;
  uint64_t v_51=0; (void)v_51;
  uint64_t v_53=0; (void)v_53;
  uint32_t v_55=0; (void)v_55;
  uint64_t v_56=0; (void)v_56;
  uint64_t v_59=0; (void)v_59;
  uint64_t v_61=0; (void)v_61;
  uint64_t v_62=0; (void)v_62;
  uint64_t v_64=0; (void)v_64;
  uint64_t v_66=0; (void)v_66;
  uint64_t v_67=0; (void)v_67;
  uint64_t v_69=0; (void)v_69;
  uint32_t v_71=0; (void)v_71;
  uint64_t v_72=0; (void)v_72;
  uint64_t v_74=0; (void)v_74;
  uint32_t v_76=0; (void)v_76;
  uint64_t v_78=0; (void)v_78;
  uint64_t v_79=0; (void)v_79;
  uint64_t v_80=0; (void)v_80;
  uint64_t v_81=0; (void)v_81;
  uint64_t v_83=0; (void)v_83;
  uint32_t v_85=0; (void)v_85;
  uint64_t v_87=0; (void)v_87;
  uint32_t v_89=0; (void)v_89;
  uint64_t v_90=0; (void)v_90;
  uint64_t v_92=0; (void)v_92;
  uint32_t v_94=0; (void)v_94;
  uint32_t v_96=0; (void)v_96;
  uint32_t v_98=0; (void)v_98;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_103=0; (void)v_103;
  uint64_t v_104=0; (void)v_104;
  uint64_t v_106=0; (void)v_106;
  uint64_t v_107=0; (void)v_107;
  uint64_t v_108=0; (void)v_108;
  uint64_t v_109=0; (void)v_109;
  uint64_t v_110=0; (void)v_110;
  uint64_t v_112=0; (void)v_112;
  uint32_t v_114=0; (void)v_114;
  uint64_t v_116=0; (void)v_116;
  uint32_t v_118=0; (void)v_118;
  uint64_t v_120=0; (void)v_120;
  uint32_t v_122=0; (void)v_122;
  uint64_t v_123=0; (void)v_123;
  uint64_t v_125=0; (void)v_125;
  uint32_t v_127=0; (void)v_127;
  v_9=UINT64_C(0x000000000000000d);
  v_18=UINT64_C(0x0000000000000011);
  v_27=UINT64_C(0x0000000000000000);
  v_38=UINT64_C(0x0000000000000005);
  v_51=UINT64_C(0x0000000000000001);
  v_62=UINT64_C(0x0000000000000000);
  v_67=UINT64_C(0x0000000000000000);
  v_72=UINT64_C(0x0000000000000001);
  v_80=UINT64_C(0x0000000000000000);
  v_81=UINT64_C(0x000000000000000d);
  v_90=UINT64_C(0x0000000000000011);
  v_99=UINT64_C(0x0000000000000000);
  v_110=UINT64_C(0x0000000000000005);
  v_123=UINT64_C(0x0000000000000001);
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
  v_48=v_46^v_30;
  v_50=(uint32_t)v_48;
  v_53=v_30-v_51;
  v_55=(uint32_t)v_53;
  {
    uint64_t edge_0=v_50;
    uint64_t edge_1=v_55;
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
  uint64_t v_48=0; (void)v_48;
  uint32_t v_50=0; (void)v_50;
  uint64_t v_51=0; (void)v_51;
  uint64_t v_53=0; (void)v_53;
  uint32_t v_55=0; (void)v_55;
  uint64_t v_56=0; (void)v_56;
  uint64_t v_59=0; (void)v_59;
  uint64_t v_61=0; (void)v_61;
  uint64_t v_62=0; (void)v_62;
  uint64_t v_64=0; (void)v_64;
  uint64_t v_66=0; (void)v_66;
  uint64_t v_67=0; (void)v_67;
  uint64_t v_69=0; (void)v_69;
  uint32_t v_71=0; (void)v_71;
  uint64_t v_72=0; (void)v_72;
  uint64_t v_74=0; (void)v_74;
  uint32_t v_76=0; (void)v_76;
  uint64_t v_78=0; (void)v_78;
  uint64_t v_79=0; (void)v_79;
  uint64_t v_80=0; (void)v_80;
  uint64_t v_81=0; (void)v_81;
  uint64_t v_83=0; (void)v_83;
  uint32_t v_85=0; (void)v_85;
  uint64_t v_87=0; (void)v_87;
  uint32_t v_89=0; (void)v_89;
  uint64_t v_90=0; (void)v_90;
  uint64_t v_92=0; (void)v_92;
  uint32_t v_94=0; (void)v_94;
  uint32_t v_96=0; (void)v_96;
  uint32_t v_98=0; (void)v_98;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_103=0; (void)v_103;
  uint64_t v_104=0; (void)v_104;
  uint64_t v_106=0; (void)v_106;
  uint64_t v_107=0; (void)v_107;
  uint64_t v_108=0; (void)v_108;
  uint64_t v_109=0; (void)v_109;
  uint64_t v_110=0; (void)v_110;
  uint64_t v_112=0; (void)v_112;
  uint32_t v_114=0; (void)v_114;
  uint64_t v_116=0; (void)v_116;
  uint32_t v_118=0; (void)v_118;
  uint64_t v_120=0; (void)v_120;
  uint32_t v_122=0; (void)v_122;
  uint64_t v_123=0; (void)v_123;
  uint64_t v_125=0; (void)v_125;
  uint32_t v_127=0; (void)v_127;
  v_9=UINT64_C(0x000000000000000d);
  v_18=UINT64_C(0x0000000000000011);
  v_27=UINT64_C(0x0000000000000000);
  v_38=UINT64_C(0x0000000000000005);
  v_51=UINT64_C(0x0000000000000001);
  v_62=UINT64_C(0x0000000000000000);
  v_67=UINT64_C(0x0000000000000000);
  v_72=UINT64_C(0x0000000000000001);
  v_80=UINT64_C(0x0000000000000000);
  v_81=UINT64_C(0x000000000000000d);
  v_90=UINT64_C(0x0000000000000011);
  v_99=UINT64_C(0x0000000000000000);
  v_110=UINT64_C(0x0000000000000005);
  v_123=UINT64_C(0x0000000000000001);
  v_56=argument_0;
  goto block_57;
block_57: ;
  {
    uint64_t edge_0=v_56;
    v_59=edge_0;
    goto block_58;
  }
block_58: ;
  {
    uint64_t edge_0=v_59;
    v_61=edge_0;
    goto block_60;
  }
block_60: ;
  if(v_61!=v_62){
  {
    uint64_t edge_0=v_61;
    v_64=edge_0;
    goto block_63;
  }
  }
  {
    uint64_t edge_0=v_61;
    v_66=edge_0;
    goto block_65;
  }
block_63: ;
  v_69=v_67^v_64;
  v_71=(uint32_t)v_69;
  v_74=v_64-v_72;
  v_76=(uint32_t)v_74;
  {
    uint64_t edge_0=v_71;
    uint64_t edge_1=v_76;
    v_78=edge_0;
    v_79=edge_1;
    goto block_77;
  }
block_65: ;
  return v_80;
block_77: ;
  v_83=(v_81>=64?0:v_78<<v_81);
  v_85=(uint32_t)v_83;
  v_87=v_78^v_85;
  v_89=(uint32_t)v_87;
  v_92=(v_90>=64?0:v_89>>v_90);
  v_94=(uint32_t)v_92;
  v_96=v_89^v_94;
  v_98=(uint32_t)v_96;
  if(v_79!=v_99){
  {
    uint64_t edge_0=v_78;
    uint64_t edge_1=v_79;
    uint64_t edge_2=v_89;
    uint64_t edge_3=v_98;
    v_101=edge_0;
    v_102=edge_1;
    v_103=edge_2;
    v_104=edge_3;
    goto block_100;
  }
  }
  {
    uint64_t edge_0=v_78;
    uint64_t edge_1=v_79;
    uint64_t edge_2=v_89;
    uint64_t edge_3=v_98;
    v_106=edge_0;
    v_107=edge_1;
    v_108=edge_2;
    v_109=edge_3;
    goto block_105;
  }
block_100: ;
  v_112=(v_110>=64?0:v_104<<v_110);
  v_114=(uint32_t)v_112;
  v_116=v_104^v_114;
  v_118=(uint32_t)v_116;
  v_120=v_118^v_102;
  v_122=(uint32_t)v_120;
  v_125=v_102-v_123;
  v_127=(uint32_t)v_125;
  {
    uint64_t edge_0=v_122;
    uint64_t edge_1=v_127;
    v_78=edge_0;
    v_79=edge_1;
    goto block_77;
  }
block_105: ;
  return v_106;
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
