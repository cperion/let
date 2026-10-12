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
  uint32_t v_25=0; (void)v_25;
  uint64_t v_26=0; (void)v_26;
  uint64_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_31=0; (void)v_31;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_34=0; (void)v_34;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_36=0; (void)v_36;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_38=0; (void)v_38;
  uint64_t v_39=0; (void)v_39;
  uint64_t v_41=0; (void)v_41;
  uint32_t v_43=0; (void)v_43;
  uint64_t v_44=0; (void)v_44;
  uint64_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  uint64_t v_48=0; (void)v_48;
  uint64_t v_49=0; (void)v_49;
  uint64_t v_50=0; (void)v_50;
  uint64_t v_52=0; (void)v_52;
  uint64_t v_53=0; (void)v_53;
  uint64_t v_54=0; (void)v_54;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_56=0; (void)v_56;
  uint64_t v_57=0; (void)v_57;
  uint64_t v_59=0; (void)v_59;
  uint32_t v_61=0; (void)v_61;
  uint64_t v_63=0; (void)v_63;
  uint32_t v_65=0; (void)v_65;
  uint64_t v_66=0; (void)v_66;
  uint64_t v_68=0; (void)v_68;
  uint32_t v_70=0; (void)v_70;
  uint64_t v_71=0; (void)v_71;
  uint64_t v_73=0; (void)v_73;
  uint32_t v_75=0; (void)v_75;
  uint64_t v_77=0; (void)v_77;
  uint32_t v_79=0; (void)v_79;
  uint64_t v_80=0; (void)v_80;
  uint64_t v_82=0; (void)v_82;
  uint32_t v_84=0; (void)v_84;
  uint64_t v_85=0; (void)v_85;
  uint64_t v_88=0; (void)v_88;
  uint64_t v_90=0; (void)v_90;
  uint64_t v_91=0; (void)v_91;
  uint64_t v_93=0; (void)v_93;
  uint64_t v_95=0; (void)v_95;
  uint64_t v_97=0; (void)v_97;
  uint64_t v_98=0; (void)v_98;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_101=0; (void)v_101;
  uint32_t v_103=0; (void)v_103;
  uint64_t v_105=0; (void)v_105;
  uint64_t v_106=0; (void)v_106;
  uint64_t v_107=0; (void)v_107;
  uint64_t v_108=0; (void)v_108;
  uint64_t v_109=0; (void)v_109;
  uint64_t v_110=0; (void)v_110;
  uint64_t v_112=0; (void)v_112;
  uint32_t v_114=0; (void)v_114;
  uint64_t v_115=0; (void)v_115;
  uint64_t v_117=0; (void)v_117;
  uint32_t v_119=0; (void)v_119;
  uint64_t v_120=0; (void)v_120;
  uint64_t v_122=0; (void)v_122;
  uint32_t v_124=0; (void)v_124;
  uint64_t v_125=0; (void)v_125;
  uint64_t v_127=0; (void)v_127;
  uint64_t v_128=0; (void)v_128;
  uint64_t v_129=0; (void)v_129;
  uint64_t v_130=0; (void)v_130;
  uint64_t v_131=0; (void)v_131;
  uint64_t v_133=0; (void)v_133;
  uint64_t v_134=0; (void)v_134;
  uint64_t v_135=0; (void)v_135;
  uint64_t v_136=0; (void)v_136;
  uint64_t v_137=0; (void)v_137;
  uint64_t v_138=0; (void)v_138;
  uint64_t v_140=0; (void)v_140;
  uint32_t v_142=0; (void)v_142;
  uint64_t v_143=0; (void)v_143;
  uint64_t v_145=0; (void)v_145;
  uint64_t v_146=0; (void)v_146;
  uint64_t v_147=0; (void)v_147;
  uint64_t v_148=0; (void)v_148;
  uint64_t v_149=0; (void)v_149;
  uint64_t v_151=0; (void)v_151;
  uint64_t v_152=0; (void)v_152;
  uint64_t v_153=0; (void)v_153;
  uint64_t v_154=0; (void)v_154;
  uint64_t v_155=0; (void)v_155;
  uint64_t v_156=0; (void)v_156;
  uint64_t v_158=0; (void)v_158;
  uint32_t v_160=0; (void)v_160;
  uint64_t v_162=0; (void)v_162;
  uint32_t v_164=0; (void)v_164;
  uint64_t v_165=0; (void)v_165;
  uint64_t v_167=0; (void)v_167;
  uint32_t v_169=0; (void)v_169;
  uint64_t v_170=0; (void)v_170;
  uint64_t v_172=0; (void)v_172;
  uint32_t v_174=0; (void)v_174;
  uint64_t v_176=0; (void)v_176;
  uint32_t v_178=0; (void)v_178;
  uint64_t v_179=0; (void)v_179;
  uint64_t v_181=0; (void)v_181;
  uint32_t v_183=0; (void)v_183;
  v_11=UINT64_C(0x0000000000000001);
  v_16=UINT64_C(0x0000000000000003);
  v_21=UINT64_C(0x0000000000000001);
  v_26=UINT64_C(0x0000000000000000);
  v_39=UINT64_C(0x0000000000000001);
  v_44=UINT64_C(0x0000000000000000);
  v_57=UINT64_C(0x00000000000000ff);
  v_66=UINT64_C(0x0000000000000001);
  v_71=UINT64_C(0x00000000000000ff);
  v_80=UINT64_C(0x0000000000000001);
  v_91=UINT64_C(0x0000000000000000);
  v_98=UINT64_C(0x0000000000000000);
  v_99=UINT64_C(0x0000000000000001);
  v_108=UINT64_C(0x000000000000003c);
  v_109=UINT64_C(0x00000000091a2b3c);
  v_110=UINT64_C(0x0000000000000001);
  v_115=UINT64_C(0x0000000000000003);
  v_120=UINT64_C(0x0000000000000001);
  v_125=UINT64_C(0x0000000000000000);
  v_138=UINT64_C(0x0000000000000001);
  v_143=UINT64_C(0x0000000000000000);
  v_156=UINT64_C(0x00000000000000ff);
  v_165=UINT64_C(0x0000000000000001);
  v_170=UINT64_C(0x00000000000000ff);
  v_179=UINT64_C(0x0000000000000001);
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
  v_18=v_9*v_16;
  v_20=(uint32_t)v_18;
  v_23=v_20+v_21;
  v_25=(uint32_t)v_23;
  if(v_10!=v_26){
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_15;
    uint64_t edge_4=v_25;
    v_28=edge_0;
    v_29=edge_1;
    v_30=edge_2;
    v_31=edge_3;
    v_32=edge_4;
    goto block_27;
  }
  }
  {
    uint64_t edge_0=v_8;
    uint64_t edge_1=v_9;
    uint64_t edge_2=v_10;
    uint64_t edge_3=v_15;
    uint64_t edge_4=v_25;
    v_34=edge_0;
    v_35=edge_1;
    v_36=edge_2;
    v_37=edge_3;
    v_38=edge_4;
    goto block_33;
  }
block_27: ;
  v_41=v_29&v_39;
  v_43=(uint32_t)v_41;
  if(v_43!=v_44){
  {
    uint64_t edge_0=v_28;
    uint64_t edge_1=v_29;
    uint64_t edge_2=v_30;
    uint64_t edge_3=v_31;
    uint64_t edge_4=v_32;
    v_46=edge_0;
    v_47=edge_1;
    v_48=edge_2;
    v_49=edge_3;
    v_50=edge_4;
    goto block_45;
  }
  }
  {
    uint64_t edge_0=v_28;
    uint64_t edge_1=v_29;
    uint64_t edge_2=v_30;
    uint64_t edge_3=v_31;
    uint64_t edge_4=v_32;
    v_52=edge_0;
    v_53=edge_1;
    v_54=edge_2;
    v_55=edge_3;
    v_56=edge_4;
    goto block_51;
  }
block_33: ;
  return v_34;
block_45: ;
  v_59=v_50&v_57;
  v_61=(uint32_t)v_59;
  v_63=v_46+v_61;
  v_65=(uint32_t)v_63;
  v_68=v_48-v_66;
  v_70=(uint32_t)v_68;
  {
    uint64_t edge_0=v_65;
    uint64_t edge_1=v_50;
    uint64_t edge_2=v_70;
    v_8=edge_0;
    v_9=edge_1;
    v_10=edge_2;
    goto block_7;
  }
block_51: ;
  v_73=v_55&v_71;
  v_75=(uint32_t)v_73;
  v_77=v_52+v_75;
  v_79=(uint32_t)v_77;
  v_82=v_54-v_80;
  v_84=(uint32_t)v_82;
  {
    uint64_t edge_0=v_79;
    uint64_t edge_1=v_55;
    uint64_t edge_2=v_84;
    v_8=edge_0;
    v_9=edge_1;
    v_10=edge_2;
    goto block_7;
  }
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
  uint32_t v_25=0; (void)v_25;
  uint64_t v_26=0; (void)v_26;
  uint64_t v_28=0; (void)v_28;
  uint64_t v_29=0; (void)v_29;
  uint64_t v_30=0; (void)v_30;
  uint64_t v_31=0; (void)v_31;
  uint64_t v_32=0; (void)v_32;
  uint64_t v_34=0; (void)v_34;
  uint64_t v_35=0; (void)v_35;
  uint64_t v_36=0; (void)v_36;
  uint64_t v_37=0; (void)v_37;
  uint64_t v_38=0; (void)v_38;
  uint64_t v_39=0; (void)v_39;
  uint64_t v_41=0; (void)v_41;
  uint32_t v_43=0; (void)v_43;
  uint64_t v_44=0; (void)v_44;
  uint64_t v_46=0; (void)v_46;
  uint64_t v_47=0; (void)v_47;
  uint64_t v_48=0; (void)v_48;
  uint64_t v_49=0; (void)v_49;
  uint64_t v_50=0; (void)v_50;
  uint64_t v_52=0; (void)v_52;
  uint64_t v_53=0; (void)v_53;
  uint64_t v_54=0; (void)v_54;
  uint64_t v_55=0; (void)v_55;
  uint64_t v_56=0; (void)v_56;
  uint64_t v_57=0; (void)v_57;
  uint64_t v_59=0; (void)v_59;
  uint32_t v_61=0; (void)v_61;
  uint64_t v_63=0; (void)v_63;
  uint32_t v_65=0; (void)v_65;
  uint64_t v_66=0; (void)v_66;
  uint64_t v_68=0; (void)v_68;
  uint32_t v_70=0; (void)v_70;
  uint64_t v_71=0; (void)v_71;
  uint64_t v_73=0; (void)v_73;
  uint32_t v_75=0; (void)v_75;
  uint64_t v_77=0; (void)v_77;
  uint32_t v_79=0; (void)v_79;
  uint64_t v_80=0; (void)v_80;
  uint64_t v_82=0; (void)v_82;
  uint32_t v_84=0; (void)v_84;
  uint64_t v_85=0; (void)v_85;
  uint64_t v_88=0; (void)v_88;
  uint64_t v_90=0; (void)v_90;
  uint64_t v_91=0; (void)v_91;
  uint64_t v_93=0; (void)v_93;
  uint64_t v_95=0; (void)v_95;
  uint64_t v_97=0; (void)v_97;
  uint64_t v_98=0; (void)v_98;
  uint64_t v_99=0; (void)v_99;
  uint64_t v_101=0; (void)v_101;
  uint32_t v_103=0; (void)v_103;
  uint64_t v_105=0; (void)v_105;
  uint64_t v_106=0; (void)v_106;
  uint64_t v_107=0; (void)v_107;
  uint64_t v_108=0; (void)v_108;
  uint64_t v_109=0; (void)v_109;
  uint64_t v_110=0; (void)v_110;
  uint64_t v_112=0; (void)v_112;
  uint32_t v_114=0; (void)v_114;
  uint64_t v_115=0; (void)v_115;
  uint64_t v_117=0; (void)v_117;
  uint32_t v_119=0; (void)v_119;
  uint64_t v_120=0; (void)v_120;
  uint64_t v_122=0; (void)v_122;
  uint32_t v_124=0; (void)v_124;
  uint64_t v_125=0; (void)v_125;
  uint64_t v_127=0; (void)v_127;
  uint64_t v_128=0; (void)v_128;
  uint64_t v_129=0; (void)v_129;
  uint64_t v_130=0; (void)v_130;
  uint64_t v_131=0; (void)v_131;
  uint64_t v_133=0; (void)v_133;
  uint64_t v_134=0; (void)v_134;
  uint64_t v_135=0; (void)v_135;
  uint64_t v_136=0; (void)v_136;
  uint64_t v_137=0; (void)v_137;
  uint64_t v_138=0; (void)v_138;
  uint64_t v_140=0; (void)v_140;
  uint32_t v_142=0; (void)v_142;
  uint64_t v_143=0; (void)v_143;
  uint64_t v_145=0; (void)v_145;
  uint64_t v_146=0; (void)v_146;
  uint64_t v_147=0; (void)v_147;
  uint64_t v_148=0; (void)v_148;
  uint64_t v_149=0; (void)v_149;
  uint64_t v_151=0; (void)v_151;
  uint64_t v_152=0; (void)v_152;
  uint64_t v_153=0; (void)v_153;
  uint64_t v_154=0; (void)v_154;
  uint64_t v_155=0; (void)v_155;
  uint64_t v_156=0; (void)v_156;
  uint64_t v_158=0; (void)v_158;
  uint32_t v_160=0; (void)v_160;
  uint64_t v_162=0; (void)v_162;
  uint32_t v_164=0; (void)v_164;
  uint64_t v_165=0; (void)v_165;
  uint64_t v_167=0; (void)v_167;
  uint32_t v_169=0; (void)v_169;
  uint64_t v_170=0; (void)v_170;
  uint64_t v_172=0; (void)v_172;
  uint32_t v_174=0; (void)v_174;
  uint64_t v_176=0; (void)v_176;
  uint32_t v_178=0; (void)v_178;
  uint64_t v_179=0; (void)v_179;
  uint64_t v_181=0; (void)v_181;
  uint32_t v_183=0; (void)v_183;
  v_11=UINT64_C(0x0000000000000001);
  v_16=UINT64_C(0x0000000000000003);
  v_21=UINT64_C(0x0000000000000001);
  v_26=UINT64_C(0x0000000000000000);
  v_39=UINT64_C(0x0000000000000001);
  v_44=UINT64_C(0x0000000000000000);
  v_57=UINT64_C(0x00000000000000ff);
  v_66=UINT64_C(0x0000000000000001);
  v_71=UINT64_C(0x00000000000000ff);
  v_80=UINT64_C(0x0000000000000001);
  v_91=UINT64_C(0x0000000000000000);
  v_98=UINT64_C(0x0000000000000000);
  v_99=UINT64_C(0x0000000000000001);
  v_108=UINT64_C(0x000000000000003c);
  v_109=UINT64_C(0x00000000091a2b3c);
  v_110=UINT64_C(0x0000000000000001);
  v_115=UINT64_C(0x0000000000000003);
  v_120=UINT64_C(0x0000000000000001);
  v_125=UINT64_C(0x0000000000000000);
  v_138=UINT64_C(0x0000000000000001);
  v_143=UINT64_C(0x0000000000000000);
  v_156=UINT64_C(0x00000000000000ff);
  v_165=UINT64_C(0x0000000000000001);
  v_170=UINT64_C(0x00000000000000ff);
  v_179=UINT64_C(0x0000000000000001);
  v_85=argument_0;
  goto block_86;
block_86: ;
  {
    uint64_t edge_0=v_85;
    v_88=edge_0;
    goto block_87;
  }
block_87: ;
  {
    uint64_t edge_0=v_88;
    v_90=edge_0;
    goto block_89;
  }
block_89: ;
  if(v_90!=v_91){
  {
    uint64_t edge_0=v_90;
    v_93=edge_0;
    goto block_92;
  }
  }
  {
    uint64_t edge_0=v_90;
    v_95=edge_0;
    goto block_94;
  }
block_92: ;
  {
    uint64_t edge_0=v_93;
    v_97=edge_0;
    goto block_96;
  }
block_94: ;
  return v_98;
block_96: ;
  v_101=v_97-v_99;
  v_103=(uint32_t)v_101;
  {
    uint64_t edge_0=v_108;
    uint64_t edge_1=v_109;
    uint64_t edge_2=v_103;
    v_105=edge_0;
    v_106=edge_1;
    v_107=edge_2;
    goto block_104;
  }
block_104: ;
  v_112=(v_110>=64?0:v_106>>v_110);
  v_114=(uint32_t)v_112;
  v_117=v_106*v_115;
  v_119=(uint32_t)v_117;
  v_122=v_119+v_120;
  v_124=(uint32_t)v_122;
  if(v_107!=v_125){
  {
    uint64_t edge_0=v_105;
    uint64_t edge_1=v_106;
    uint64_t edge_2=v_107;
    uint64_t edge_3=v_114;
    uint64_t edge_4=v_124;
    v_127=edge_0;
    v_128=edge_1;
    v_129=edge_2;
    v_130=edge_3;
    v_131=edge_4;
    goto block_126;
  }
  }
  {
    uint64_t edge_0=v_105;
    uint64_t edge_1=v_106;
    uint64_t edge_2=v_107;
    uint64_t edge_3=v_114;
    uint64_t edge_4=v_124;
    v_133=edge_0;
    v_134=edge_1;
    v_135=edge_2;
    v_136=edge_3;
    v_137=edge_4;
    goto block_132;
  }
block_126: ;
  v_140=v_128&v_138;
  v_142=(uint32_t)v_140;
  if(v_142!=v_143){
  {
    uint64_t edge_0=v_127;
    uint64_t edge_1=v_128;
    uint64_t edge_2=v_129;
    uint64_t edge_3=v_130;
    uint64_t edge_4=v_131;
    v_145=edge_0;
    v_146=edge_1;
    v_147=edge_2;
    v_148=edge_3;
    v_149=edge_4;
    goto block_144;
  }
  }
  {
    uint64_t edge_0=v_127;
    uint64_t edge_1=v_128;
    uint64_t edge_2=v_129;
    uint64_t edge_3=v_130;
    uint64_t edge_4=v_131;
    v_151=edge_0;
    v_152=edge_1;
    v_153=edge_2;
    v_154=edge_3;
    v_155=edge_4;
    goto block_150;
  }
block_132: ;
  return v_133;
block_144: ;
  v_158=v_149&v_156;
  v_160=(uint32_t)v_158;
  v_162=v_145+v_160;
  v_164=(uint32_t)v_162;
  v_167=v_147-v_165;
  v_169=(uint32_t)v_167;
  {
    uint64_t edge_0=v_164;
    uint64_t edge_1=v_149;
    uint64_t edge_2=v_169;
    v_105=edge_0;
    v_106=edge_1;
    v_107=edge_2;
    goto block_104;
  }
block_150: ;
  v_172=v_154&v_170;
  v_174=(uint32_t)v_172;
  v_176=v_151+v_174;
  v_178=(uint32_t)v_176;
  v_181=v_153-v_179;
  v_183=(uint32_t)v_181;
  {
    uint64_t edge_0=v_178;
    uint64_t edge_1=v_154;
    uint64_t edge_2=v_183;
    v_105=edge_0;
    v_106=edge_1;
    v_107=edge_2;
    goto block_104;
  }
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
