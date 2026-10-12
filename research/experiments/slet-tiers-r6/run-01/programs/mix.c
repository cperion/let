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
  uint64_t v_17=0; (void)v_17;
  uint32_t v_19=0; (void)v_19;
  uint64_t v_20=0; (void)v_20;
  uint64_t v_22=0; (void)v_22;
  uint32_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_27=0; (void)v_27;
  uint32_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_33=0; (void)v_33;
  uint64_t v_34=0; (void)v_34;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_38=0; (void)v_38;
  uint64_t v_39=0; (void)v_39;
  uint64_t v_40=0; (void)v_40;
  uint64_t v_41=0; (void)v_41;
  uint64_t v_43=0; (void)v_43;
  uint32_t v_45=0; (void)v_45;
  uint64_t v_47=0; (void)v_47;
  uint32_t v_49=0; (void)v_49;
  uint64_t v_50=0; (void)v_50;
  uint64_t v_52=0; (void)v_52;
  uint32_t v_54=0; (void)v_54;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_58=0; (void)v_58;
  uint64_t v_60=0; (void)v_60;
  uint64_t v_61=0; (void)v_61;
  uint64_t v_63=0; (void)v_63;
  uint64_t v_65=0; (void)v_65;
  uint64_t v_66=0; (void)v_66;
  uint64_t v_68=0; (void)v_68;
  uint32_t v_70=0; (void)v_70;
  uint64_t v_72=0; (void)v_72;
  uint64_t v_73=0; (void)v_73;
  uint64_t v_74=0; (void)v_74;
  uint64_t v_75=0; (void)v_75;
  uint64_t v_76=0; (void)v_76;
  uint64_t v_77=0; (void)v_77;
  uint64_t v_78=0; (void)v_78;
  uint64_t v_80=0; (void)v_80;
  uint32_t v_82=0; (void)v_82;
  uint64_t v_84=0; (void)v_84;
  uint32_t v_86=0; (void)v_86;
  uint64_t v_87=0; (void)v_87;
  uint64_t v_89=0; (void)v_89;
  uint32_t v_91=0; (void)v_91;
  uint64_t v_92=0; (void)v_92;
  uint64_t v_94=0; (void)v_94;
  uint32_t v_96=0; (void)v_96;
  uint64_t v_97=0; (void)v_97;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_100=0; (void)v_100;
  uint64_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_104=0; (void)v_104;
  uint64_t v_105=0; (void)v_105;
  uint64_t v_106=0; (void)v_106;
  uint64_t v_107=0; (void)v_107;
  uint64_t v_108=0; (void)v_108;
  uint64_t v_110=0; (void)v_110;
  uint32_t v_112=0; (void)v_112;
  uint64_t v_114=0; (void)v_114;
  uint32_t v_116=0; (void)v_116;
  uint64_t v_117=0; (void)v_117;
  uint64_t v_119=0; (void)v_119;
  uint32_t v_121=0; (void)v_121;
  v_11=UINT64_C(0x0000000000000007);
  v_20=UINT64_C(0x0000000000000005);
  v_25=UINT64_C(0x0000000000000001);
  v_30=UINT64_C(0x0000000000000000);
  v_41=UINT64_C(0x00000000000003ff);
  v_50=UINT64_C(0x0000000000000001);
  v_61=UINT64_C(0x0000000000000000);
  v_66=UINT64_C(0x0000000000000001);
  v_75=UINT64_C(0x0000000000000225);
  v_76=UINT64_C(0x000000005a513a25);
  v_77=UINT64_C(0x0000000000000000);
  v_78=UINT64_C(0x0000000000000007);
  v_87=UINT64_C(0x0000000000000005);
  v_92=UINT64_C(0x0000000000000001);
  v_97=UINT64_C(0x0000000000000000);
  v_108=UINT64_C(0x00000000000003ff);
  v_117=UINT64_C(0x0000000000000001);
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
  v_13=(v_11>=64?0:v_9>>v_11);
  v_15=(uint32_t)v_13;
  v_17=v_9^v_15;
  v_19=(uint32_t)v_17;
  v_22=v_19*v_20;
  v_24=(uint32_t)v_22;
  v_27=v_24+v_25;
  v_29=(uint32_t)v_27;
  if(v_10!=v_30){
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_29;
    v_32=edge_0;
    v_33=edge_1;
    v_34=edge_2;
    v_35=edge_3;
    goto block_31;
  }
  }
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_29;
    v_37=edge_0;
    v_38=edge_1;
    v_39=edge_2;
    v_40=edge_3;
    goto block_36;
  }
block_31: ;
  v_43=v_35&v_41;
  v_45=(uint32_t)v_43;
  v_47=v_32+v_45;
  v_49=(uint32_t)v_47;
  v_52=v_34-v_50;
  v_54=(uint32_t)v_52;
  {
    uint64_t edge_0=v_49;
    uint64_t edge_1=v_35;
    uint64_t edge_2=v_54;
    v_8=edge_0;
    v_9=edge_1;
    v_10=edge_2;
    goto block_7;
  }
block_36: ;
  return v_37;
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
  uint64_t v_17=0; (void)v_17;
  uint32_t v_19=0; (void)v_19;
  uint64_t v_20=0; (void)v_20;
  uint64_t v_22=0; (void)v_22;
  uint32_t v_24=0; (void)v_24;
  uint64_t v_25=0; (void)v_25;
  uint64_t v_27=0; (void)v_27;
  uint32_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_33=0; (void)v_33;
  uint64_t v_34=0; (void)v_34;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_38=0; (void)v_38;
  uint64_t v_39=0; (void)v_39;
  uint64_t v_40=0; (void)v_40;
  uint64_t v_41=0; (void)v_41;
  uint64_t v_43=0; (void)v_43;
  uint32_t v_45=0; (void)v_45;
  uint64_t v_47=0; (void)v_47;
  uint32_t v_49=0; (void)v_49;
  uint64_t v_50=0; (void)v_50;
  uint64_t v_52=0; (void)v_52;
  uint32_t v_54=0; (void)v_54;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_58=0; (void)v_58;
  uint64_t v_60=0; (void)v_60;
  uint64_t v_61=0; (void)v_61;
  uint64_t v_63=0; (void)v_63;
  uint64_t v_65=0; (void)v_65;
  uint64_t v_66=0; (void)v_66;
  uint64_t v_68=0; (void)v_68;
  uint32_t v_70=0; (void)v_70;
  uint64_t v_72=0; (void)v_72;
  uint64_t v_73=0; (void)v_73;
  uint64_t v_74=0; (void)v_74;
  uint64_t v_75=0; (void)v_75;
  uint64_t v_76=0; (void)v_76;
  uint64_t v_77=0; (void)v_77;
  uint64_t v_78=0; (void)v_78;
  uint64_t v_80=0; (void)v_80;
  uint32_t v_82=0; (void)v_82;
  uint64_t v_84=0; (void)v_84;
  uint32_t v_86=0; (void)v_86;
  uint64_t v_87=0; (void)v_87;
  uint64_t v_89=0; (void)v_89;
  uint32_t v_91=0; (void)v_91;
  uint64_t v_92=0; (void)v_92;
  uint64_t v_94=0; (void)v_94;
  uint32_t v_96=0; (void)v_96;
  uint64_t v_97=0; (void)v_97;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_100=0; (void)v_100;
  uint64_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_104=0; (void)v_104;
  uint64_t v_105=0; (void)v_105;
  uint64_t v_106=0; (void)v_106;
  uint64_t v_107=0; (void)v_107;
  uint64_t v_108=0; (void)v_108;
  uint64_t v_110=0; (void)v_110;
  uint32_t v_112=0; (void)v_112;
  uint64_t v_114=0; (void)v_114;
  uint32_t v_116=0; (void)v_116;
  uint64_t v_117=0; (void)v_117;
  uint64_t v_119=0; (void)v_119;
  uint32_t v_121=0; (void)v_121;
  v_11=UINT64_C(0x0000000000000007);
  v_20=UINT64_C(0x0000000000000005);
  v_25=UINT64_C(0x0000000000000001);
  v_30=UINT64_C(0x0000000000000000);
  v_41=UINT64_C(0x00000000000003ff);
  v_50=UINT64_C(0x0000000000000001);
  v_61=UINT64_C(0x0000000000000000);
  v_66=UINT64_C(0x0000000000000001);
  v_75=UINT64_C(0x0000000000000225);
  v_76=UINT64_C(0x000000005a513a25);
  v_77=UINT64_C(0x0000000000000000);
  v_78=UINT64_C(0x0000000000000007);
  v_87=UINT64_C(0x0000000000000005);
  v_92=UINT64_C(0x0000000000000001);
  v_97=UINT64_C(0x0000000000000000);
  v_108=UINT64_C(0x00000000000003ff);
  v_117=UINT64_C(0x0000000000000001);
  v_55=argument_0;
  goto block_56;
block_56: ;
  {
    uint64_t edge_0=v_55;
    v_58=edge_0;
    goto block_57;
  }
block_57: ;
  {
    uint64_t edge_0=v_58;
    v_60=edge_0;
    goto block_59;
  }
block_59: ;
  if(v_60!=v_61){
  {
    uint64_t edge_0=v_60;
    v_63=edge_0;
    goto block_62;
  }
  }
  {
    uint64_t edge_0=v_60;
    v_65=edge_0;
    goto block_64;
  }
block_62: ;
  v_68=v_63-v_66;
  v_70=(uint32_t)v_68;
  {
    uint64_t edge_0=v_75;
    uint64_t edge_1=v_76;
    uint64_t edge_2=v_70;
    v_72=edge_0;
    v_73=edge_1;
    v_74=edge_2;
    goto block_71;
  }
block_64: ;
  return v_77;
block_71: ;
  v_80=(v_78>=64?0:v_73>>v_78);
  v_82=(uint32_t)v_80;
  v_84=v_73^v_82;
  v_86=(uint32_t)v_84;
  v_89=v_86*v_87;
  v_91=(uint32_t)v_89;
  v_94=v_91+v_92;
  v_96=(uint32_t)v_94;
  if(v_74!=v_97){
  {
    uint64_t edge_0=v_72;
    uint64_t edge_1=v_73;
    uint64_t edge_2=v_74;
    uint64_t edge_3=v_96;
    v_99=edge_0;
    v_100=edge_1;
    v_101=edge_2;
    v_102=edge_3;
    goto block_98;
  }
  }
  {
    uint64_t edge_0=v_72;
    uint64_t edge_1=v_73;
    uint64_t edge_2=v_74;
    uint64_t edge_3=v_96;
    v_104=edge_0;
    v_105=edge_1;
    v_106=edge_2;
    v_107=edge_3;
    goto block_103;
  }
block_98: ;
  v_110=v_102&v_108;
  v_112=(uint32_t)v_110;
  v_114=v_99+v_112;
  v_116=(uint32_t)v_114;
  v_119=v_101-v_117;
  v_121=(uint32_t)v_119;
  {
    uint64_t edge_0=v_116;
    uint64_t edge_1=v_102;
    uint64_t edge_2=v_121;
    v_72=edge_0;
    v_73=edge_1;
    v_74=edge_2;
    goto block_71;
  }
block_103: ;
  return v_104;
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
