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
  uint32_t v_26=0; (void)v_26;
  uint32_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_31=0; (void)v_31;
  uint32_t v_33=0; (void)v_33;
  uint64_t v_35=0; (void)v_35;
  uint32_t v_37=0; (void)v_37;
  uint64_t v_38=0; (void)v_38;
  uint64_t v_40=0; (void)v_40;
  uint32_t v_42=0; (void)v_42;
  uint32_t v_44=0; (void)v_44;
  uint32_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  uint64_t v_49=0; (void)v_49;
  uint64_t v_50=0; (void)v_50;
  uint64_t v_51=0; (void)v_51;
  uint64_t v_52=0; (void)v_52;
  uint64_t v_53=0; (void)v_53;
  uint64_t v_54=0; (void)v_54;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_57=0; (void)v_57;
  uint64_t v_58=0; (void)v_58;
  uint64_t v_59=0; (void)v_59;
  uint64_t v_60=0; (void)v_60;
  uint64_t v_61=0; (void)v_61;
  uint64_t v_62=0; (void)v_62;
  uint64_t v_63=0; (void)v_63;
  uint64_t v_64=0; (void)v_64;
  uint64_t v_66=0; (void)v_66;
  uint32_t v_68=0; (void)v_68;
  uint64_t v_70=0; (void)v_70;
  uint32_t v_72=0; (void)v_72;
  uint64_t v_73=0; (void)v_73;
  uint64_t v_75=0; (void)v_75;
  uint32_t v_77=0; (void)v_77;
  uint64_t v_79=0; (void)v_79;
  uint32_t v_81=0; (void)v_81;
  uint64_t v_82=0; (void)v_82;
  uint64_t v_84=0; (void)v_84;
  uint32_t v_86=0; (void)v_86;
  uint64_t v_88=0; (void)v_88;
  uint32_t v_90=0; (void)v_90;
  uint64_t v_91=0; (void)v_91;
  uint64_t v_94=0; (void)v_94;
  uint64_t v_96=0; (void)v_96;
  uint64_t v_97=0; (void)v_97;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_104=0; (void)v_104;
  uint32_t v_106=0; (void)v_106;
  uint64_t v_108=0; (void)v_108;
  uint64_t v_109=0; (void)v_109;
  uint64_t v_110=0; (void)v_110;
  uint64_t v_111=0; (void)v_111;
  uint64_t v_112=0; (void)v_112;
  uint64_t v_113=0; (void)v_113;
  uint64_t v_114=0; (void)v_114;
  uint64_t v_116=0; (void)v_116;
  uint32_t v_118=0; (void)v_118;
  uint64_t v_120=0; (void)v_120;
  uint32_t v_122=0; (void)v_122;
  uint64_t v_123=0; (void)v_123;
  uint64_t v_125=0; (void)v_125;
  uint32_t v_127=0; (void)v_127;
  uint32_t v_129=0; (void)v_129;
  uint32_t v_131=0; (void)v_131;
  uint64_t v_132=0; (void)v_132;
  uint64_t v_134=0; (void)v_134;
  uint32_t v_136=0; (void)v_136;
  uint64_t v_138=0; (void)v_138;
  uint32_t v_140=0; (void)v_140;
  uint64_t v_141=0; (void)v_141;
  uint64_t v_143=0; (void)v_143;
  uint32_t v_145=0; (void)v_145;
  uint32_t v_147=0; (void)v_147;
  uint32_t v_149=0; (void)v_149;
  uint64_t v_150=0; (void)v_150;
  uint64_t v_152=0; (void)v_152;
  uint64_t v_153=0; (void)v_153;
  uint64_t v_154=0; (void)v_154;
  uint64_t v_155=0; (void)v_155;
  uint64_t v_156=0; (void)v_156;
  uint64_t v_157=0; (void)v_157;
  uint64_t v_158=0; (void)v_158;
  uint64_t v_160=0; (void)v_160;
  uint64_t v_161=0; (void)v_161;
  uint64_t v_162=0; (void)v_162;
  uint64_t v_163=0; (void)v_163;
  uint64_t v_164=0; (void)v_164;
  uint64_t v_165=0; (void)v_165;
  uint64_t v_166=0; (void)v_166;
  uint64_t v_167=0; (void)v_167;
  uint64_t v_169=0; (void)v_169;
  uint32_t v_171=0; (void)v_171;
  uint64_t v_173=0; (void)v_173;
  uint32_t v_175=0; (void)v_175;
  uint64_t v_176=0; (void)v_176;
  uint64_t v_178=0; (void)v_178;
  uint32_t v_180=0; (void)v_180;
  uint64_t v_182=0; (void)v_182;
  uint32_t v_184=0; (void)v_184;
  uint64_t v_185=0; (void)v_185;
  uint64_t v_187=0; (void)v_187;
  uint32_t v_189=0; (void)v_189;
  uint64_t v_191=0; (void)v_191;
  uint32_t v_193=0; (void)v_193;
  v_11=UINT64_C(0x000000000000000d);
  v_20=UINT64_C(0x0000000000000011);
  v_29=UINT64_C(0x000000000000000d);
  v_38=UINT64_C(0x0000000000000011);
  v_47=UINT64_C(0x0000000000000000);
  v_64=UINT64_C(0x0000000000000005);
  v_73=UINT64_C(0x0000000000000005);
  v_82=UINT64_C(0x0000000000000001);
  v_97=UINT64_C(0x0000000000000000);
  v_102=UINT64_C(0x0000000000000001);
  v_111=UINT64_C(0x00000000510c4619);
  v_112=UINT64_C(0x0000000087985aa5);
  v_113=UINT64_C(0x000000008c032fc1);
  v_114=UINT64_C(0x000000000000000d);
  v_123=UINT64_C(0x0000000000000011);
  v_132=UINT64_C(0x000000000000000d);
  v_141=UINT64_C(0x0000000000000011);
  v_150=UINT64_C(0x0000000000000000);
  v_167=UINT64_C(0x0000000000000005);
  v_176=UINT64_C(0x0000000000000005);
  v_185=UINT64_C(0x0000000000000001);
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
  v_13=(v_11>=64?0:v_9<<v_11);
  v_15=(uint32_t)v_13;
  v_17=v_9^v_15;
  v_19=(uint32_t)v_17;
  v_22=(v_20>=64?0:v_19>>v_20);
  v_24=(uint32_t)v_22;
  v_26=v_19^v_24;
  v_28=(uint32_t)v_26;
  v_31=(v_29>=64?0:v_8<<v_29);
  v_33=(uint32_t)v_31;
  v_35=v_8^v_33;
  v_37=(uint32_t)v_35;
  v_40=(v_38>=64?0:v_37>>v_38);
  v_42=(uint32_t)v_40;
  v_44=v_37^v_42;
  v_46=(uint32_t)v_44;
  if(v_10!=v_47){
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_19;
    uint64_t edge_4=v_28;
    uint64_t edge_5=v_37;
    uint64_t edge_6=v_46;
    v_49=edge_0;
    v_50=edge_1;
    v_51=edge_2;
    v_52=edge_3;
    v_53=edge_4;
    v_54=edge_5;
    v_55=edge_6;
    goto block_48;
  }
  }
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_19;
    uint64_t edge_4=v_28;
    uint64_t edge_5=v_37;
    uint64_t edge_6=v_46;
    v_57=edge_0;
    v_58=edge_1;
    v_59=edge_2;
    v_60=edge_3;
    v_61=edge_4;
    v_62=edge_5;
    v_63=edge_6;
    goto block_56;
  }
block_48: ;
  v_66=(v_64>=64?0:v_55<<v_64);
  v_68=(uint32_t)v_66;
  v_70=v_55^v_68;
  v_72=(uint32_t)v_70;
  v_75=(v_73>=64?0:v_53<<v_73);
  v_77=(uint32_t)v_75;
  v_79=v_53^v_77;
  v_81=(uint32_t)v_79;
  v_84=v_51-v_82;
  v_86=(uint32_t)v_84;
  {
    uint64_t edge_0=v_72;
    uint64_t edge_1=v_81;
    uint64_t edge_2=v_86;
    v_8=edge_0;
    v_9=edge_1;
    v_10=edge_2;
    goto block_7;
  }
block_56: ;
  v_88=v_58^v_57;
  v_90=(uint32_t)v_88;
  return v_90;
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
  uint32_t v_26=0; (void)v_26;
  uint32_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_31=0; (void)v_31;
  uint32_t v_33=0; (void)v_33;
  uint64_t v_35=0; (void)v_35;
  uint32_t v_37=0; (void)v_37;
  uint64_t v_38=0; (void)v_38;
  uint64_t v_40=0; (void)v_40;
  uint32_t v_42=0; (void)v_42;
  uint32_t v_44=0; (void)v_44;
  uint32_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  uint64_t v_49=0; (void)v_49;
  uint64_t v_50=0; (void)v_50;
  uint64_t v_51=0; (void)v_51;
  uint64_t v_52=0; (void)v_52;
  uint64_t v_53=0; (void)v_53;
  uint64_t v_54=0; (void)v_54;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_57=0; (void)v_57;
  uint64_t v_58=0; (void)v_58;
  uint64_t v_59=0; (void)v_59;
  uint64_t v_60=0; (void)v_60;
  uint64_t v_61=0; (void)v_61;
  uint64_t v_62=0; (void)v_62;
  uint64_t v_63=0; (void)v_63;
  uint64_t v_64=0; (void)v_64;
  uint64_t v_66=0; (void)v_66;
  uint32_t v_68=0; (void)v_68;
  uint64_t v_70=0; (void)v_70;
  uint32_t v_72=0; (void)v_72;
  uint64_t v_73=0; (void)v_73;
  uint64_t v_75=0; (void)v_75;
  uint32_t v_77=0; (void)v_77;
  uint64_t v_79=0; (void)v_79;
  uint32_t v_81=0; (void)v_81;
  uint64_t v_82=0; (void)v_82;
  uint64_t v_84=0; (void)v_84;
  uint32_t v_86=0; (void)v_86;
  uint64_t v_88=0; (void)v_88;
  uint32_t v_90=0; (void)v_90;
  uint64_t v_91=0; (void)v_91;
  uint64_t v_94=0; (void)v_94;
  uint64_t v_96=0; (void)v_96;
  uint64_t v_97=0; (void)v_97;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_101=0; (void)v_101;
  uint64_t v_102=0; (void)v_102;
  uint64_t v_104=0; (void)v_104;
  uint32_t v_106=0; (void)v_106;
  uint64_t v_108=0; (void)v_108;
  uint64_t v_109=0; (void)v_109;
  uint64_t v_110=0; (void)v_110;
  uint64_t v_111=0; (void)v_111;
  uint64_t v_112=0; (void)v_112;
  uint64_t v_113=0; (void)v_113;
  uint64_t v_114=0; (void)v_114;
  uint64_t v_116=0; (void)v_116;
  uint32_t v_118=0; (void)v_118;
  uint64_t v_120=0; (void)v_120;
  uint32_t v_122=0; (void)v_122;
  uint64_t v_123=0; (void)v_123;
  uint64_t v_125=0; (void)v_125;
  uint32_t v_127=0; (void)v_127;
  uint32_t v_129=0; (void)v_129;
  uint32_t v_131=0; (void)v_131;
  uint64_t v_132=0; (void)v_132;
  uint64_t v_134=0; (void)v_134;
  uint32_t v_136=0; (void)v_136;
  uint64_t v_138=0; (void)v_138;
  uint32_t v_140=0; (void)v_140;
  uint64_t v_141=0; (void)v_141;
  uint64_t v_143=0; (void)v_143;
  uint32_t v_145=0; (void)v_145;
  uint32_t v_147=0; (void)v_147;
  uint32_t v_149=0; (void)v_149;
  uint64_t v_150=0; (void)v_150;
  uint64_t v_152=0; (void)v_152;
  uint64_t v_153=0; (void)v_153;
  uint64_t v_154=0; (void)v_154;
  uint64_t v_155=0; (void)v_155;
  uint64_t v_156=0; (void)v_156;
  uint64_t v_157=0; (void)v_157;
  uint64_t v_158=0; (void)v_158;
  uint64_t v_160=0; (void)v_160;
  uint64_t v_161=0; (void)v_161;
  uint64_t v_162=0; (void)v_162;
  uint64_t v_163=0; (void)v_163;
  uint64_t v_164=0; (void)v_164;
  uint64_t v_165=0; (void)v_165;
  uint64_t v_166=0; (void)v_166;
  uint64_t v_167=0; (void)v_167;
  uint64_t v_169=0; (void)v_169;
  uint32_t v_171=0; (void)v_171;
  uint64_t v_173=0; (void)v_173;
  uint32_t v_175=0; (void)v_175;
  uint64_t v_176=0; (void)v_176;
  uint64_t v_178=0; (void)v_178;
  uint32_t v_180=0; (void)v_180;
  uint64_t v_182=0; (void)v_182;
  uint32_t v_184=0; (void)v_184;
  uint64_t v_185=0; (void)v_185;
  uint64_t v_187=0; (void)v_187;
  uint32_t v_189=0; (void)v_189;
  uint64_t v_191=0; (void)v_191;
  uint32_t v_193=0; (void)v_193;
  v_11=UINT64_C(0x000000000000000d);
  v_20=UINT64_C(0x0000000000000011);
  v_29=UINT64_C(0x000000000000000d);
  v_38=UINT64_C(0x0000000000000011);
  v_47=UINT64_C(0x0000000000000000);
  v_64=UINT64_C(0x0000000000000005);
  v_73=UINT64_C(0x0000000000000005);
  v_82=UINT64_C(0x0000000000000001);
  v_97=UINT64_C(0x0000000000000000);
  v_102=UINT64_C(0x0000000000000001);
  v_111=UINT64_C(0x00000000510c4619);
  v_112=UINT64_C(0x0000000087985aa5);
  v_113=UINT64_C(0x000000008c032fc1);
  v_114=UINT64_C(0x000000000000000d);
  v_123=UINT64_C(0x0000000000000011);
  v_132=UINT64_C(0x000000000000000d);
  v_141=UINT64_C(0x0000000000000011);
  v_150=UINT64_C(0x0000000000000000);
  v_167=UINT64_C(0x0000000000000005);
  v_176=UINT64_C(0x0000000000000005);
  v_185=UINT64_C(0x0000000000000001);
  v_91=argument_0;
  goto block_92;
block_92: ;
  {
    uint64_t edge_0=v_91;
    v_94=edge_0;
    goto block_93;
  }
block_93: ;
  {
    uint64_t edge_0=v_94;
    v_96=edge_0;
    goto block_95;
  }
block_95: ;
  if(v_96!=v_97){
  {
    uint64_t edge_0=v_96;
    v_99=edge_0;
    goto block_98;
  }
  }
  {
    uint64_t edge_0=v_96;
    v_101=edge_0;
    goto block_100;
  }
block_98: ;
  v_104=v_99-v_102;
  v_106=(uint32_t)v_104;
  {
    uint64_t edge_0=v_111;
    uint64_t edge_1=v_112;
    uint64_t edge_2=v_106;
    v_108=edge_0;
    v_109=edge_1;
    v_110=edge_2;
    goto block_107;
  }
block_100: ;
  return v_113;
block_107: ;
  v_116=(v_114>=64?0:v_109<<v_114);
  v_118=(uint32_t)v_116;
  v_120=v_109^v_118;
  v_122=(uint32_t)v_120;
  v_125=(v_123>=64?0:v_122>>v_123);
  v_127=(uint32_t)v_125;
  v_129=v_122^v_127;
  v_131=(uint32_t)v_129;
  v_134=(v_132>=64?0:v_108<<v_132);
  v_136=(uint32_t)v_134;
  v_138=v_108^v_136;
  v_140=(uint32_t)v_138;
  v_143=(v_141>=64?0:v_140>>v_141);
  v_145=(uint32_t)v_143;
  v_147=v_140^v_145;
  v_149=(uint32_t)v_147;
  if(v_110!=v_150){
  {
    uint64_t edge_0=v_108;
    uint64_t edge_1=v_109;
    uint64_t edge_2=v_110;
    uint64_t edge_3=v_122;
    uint64_t edge_4=v_131;
    uint64_t edge_5=v_140;
    uint64_t edge_6=v_149;
    v_152=edge_0;
    v_153=edge_1;
    v_154=edge_2;
    v_155=edge_3;
    v_156=edge_4;
    v_157=edge_5;
    v_158=edge_6;
    goto block_151;
  }
  }
  {
    uint64_t edge_0=v_108;
    uint64_t edge_1=v_109;
    uint64_t edge_2=v_110;
    uint64_t edge_3=v_122;
    uint64_t edge_4=v_131;
    uint64_t edge_5=v_140;
    uint64_t edge_6=v_149;
    v_160=edge_0;
    v_161=edge_1;
    v_162=edge_2;
    v_163=edge_3;
    v_164=edge_4;
    v_165=edge_5;
    v_166=edge_6;
    goto block_159;
  }
block_151: ;
  v_169=(v_167>=64?0:v_158<<v_167);
  v_171=(uint32_t)v_169;
  v_173=v_158^v_171;
  v_175=(uint32_t)v_173;
  v_178=(v_176>=64?0:v_156<<v_176);
  v_180=(uint32_t)v_178;
  v_182=v_156^v_180;
  v_184=(uint32_t)v_182;
  v_187=v_154-v_185;
  v_189=(uint32_t)v_187;
  {
    uint64_t edge_0=v_175;
    uint64_t edge_1=v_184;
    uint64_t edge_2=v_189;
    v_108=edge_0;
    v_109=edge_1;
    v_110=edge_2;
    goto block_107;
  }
block_159: ;
  v_191=v_161^v_160;
  v_193=(uint32_t)v_191;
  return v_193;
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
