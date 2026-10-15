#include "internal.h"

/* Decode profile-specific metadata; every profile uses abc_verify_module. */
static int value_kind(unsigned kind) {return kind==ABC_KIND_INT||kind==ABC_KIND_ADDR||kind==ABC_KIND_FLOAT;}
abc_status abc_load_memory(const void *bytes,size_t size,abc_module **out,abc_error *error) {
    const uint8_t *header=bytes;const uint16_t endian=1;
    if(*(const uint8_t *)&endian!=1)return abc_fail(error,ABC_INVALID,UINT32_MAX,"memory profile requires little-endian host memory");
    unsigned profile=header[7],foreign=profile==4,callable=profile>=3,section_count=foreign?9:callable?8:6;
    if(abc_u32(header+8)!=section_count)return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid profile section count");
    const uint8_t *sections[10]={0};uint32_t lengths[10]={0};size_t offset=16;
    for(unsigned index=0;index<section_count;index++) {
        if(size-offset<8)return abc_fail(error,ABC_INVALID,UINT32_MAX,"truncated section header");
        uint32_t tag=abc_u32(header+offset),length=abc_u32(header+offset+4);offset+=8;
        if(tag<1||tag>section_count||sections[tag]||length>size-offset)return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid, duplicate or unsupported section");
        sections[tag]=header+offset;lengths[tag]=length;offset+=length;
    }
    if(offset!=size||lengths[1]<4||!lengths[2]||lengths[3]<4||lengths[6]<4||(callable&&(lengths[7]<4||lengths[8]<4))||(foreign&&lengths[9]<4))
        return abc_fail(error,ABC_INVALID,UINT32_MAX,"missing sections or trailing bytes");
    uint32_t functions=abc_u32(sections[1]),exports=abc_u32(sections[3]),annotations=abc_u32(sections[6]);
    uint32_t sites=callable?abc_u32(sections[7]):0,relocations=callable?abc_u32(sections[8]):0,externs=foreign?abc_u32(sections[9]):0;
    if(!functions||functions>ABC_MAX_FUNCTIONS||exports>ABC_MAX_FUNCTIONS||sites>ABC_MAX_FUNCTIONS||relocations>ABC_MAX_FUNCTIONS||externs>65535||lengths[6]!=4+(uint64_t)annotations*5||(callable&&lengths[8]!=4+(uint64_t)relocations*8)||(uint64_t)lengths[4]+lengths[5]>ABC_MAX_FILE)
        return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid table or image size");
    abc_module *module=calloc(1,sizeof *module);
    if(!module)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"module allocation failed");
    atomic_init(&module->references,1);module->memory_profile=1;module->callable_profile=callable;module->foreign_profile=foreign;
    module->function_count=functions;module->export_count=exports;module->site_count=sites;module->reloc_count=relocations;module->extern_count=externs;
    module->code_size=lengths[2];module->data_size=lengths[4];module->image_size=lengths[4]+lengths[5];
    module->functions=calloc(functions,sizeof *module->functions);module->exports=calloc(exports?exports:1,sizeof *module->exports);
    module->code=malloc(lengths[2]);module->load_kinds=calloc(lengths[2],1);module->image=malloc(module->image_size?module->image_size:1);
    abc_status status=ABC_INVALID;
#define FAIL(...) do{status=abc_fail(error,ABC_INVALID,UINT32_MAX,__VA_ARGS__);goto failed;}while(0)
    if(!module->functions||!module->exports||!module->code||!module->load_kinds||!module->image){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"module allocation failed");goto failed;}
    memcpy(module->code,sections[2],lengths[2]);memcpy(module->image,sections[4],lengths[4]);memcpy(module->image+lengths[4],sections[5],lengths[5]);
    offset=4;
    for(uint32_t index=0;index<functions;index++) {
        if(lengths[1]-offset<16)FAIL("truncated function signature");
        const uint8_t *record=sections[1]+offset;abc_function *function=&module->functions[index];
        function->entry=abc_u32(record);function->arguments=abc_u32(record+4);function->results=abc_u32(record+8);function->hidden_bytes=abc_u32(record+12);offset+=16;
        if((!index&&function->entry)||function->entry>=lengths[2]||(index&&function->entry<=module->functions[index-1].entry)||function->arguments>255||function->results>255||function->hidden_bytes>ABC_MAX_FILE||function->arguments+function->results>lengths[1]-offset)FAIL("invalid function entry/count or hidden result size");
        memcpy(function->argument_kinds,sections[1]+offset,function->arguments);offset+=function->arguments;
        memcpy(function->result_kinds,sections[1]+offset,function->results);offset+=function->results;
        for(uint32_t argument=0;argument<function->arguments;argument++)if(!value_kind(function->argument_kinds[argument]))FAIL("unsupported argument kind");
        for(uint32_t result=0;result<function->results;result++)if(!value_kind(function->result_kinds[result]))FAIL("unsupported result kind");
        if(function->hidden_bytes&&(!function->arguments||function->argument_kinds[0]!=ABC_KIND_ADDR))FAIL("hidden aggregate result requires first argument address");
        if(index)module->functions[index-1].end=function->entry;
    }
    if(offset!=lengths[1])FAIL("trailing function signature bytes");
    module->functions[functions-1].end=lengths[2];offset=4;
    for(uint32_t index=0;index<exports;index++) {
        if(lengths[3]-offset<6)FAIL("truncated export");
        uint32_t function=abc_u32(sections[3]+offset);unsigned length=abc_u16(sections[3]+offset+4);offset+=6;
        if(function>=functions||!length||length>255||length>lengths[3]-offset)FAIL("invalid export name or index");
        for(unsigned character=0;character<length;character++) {
            unsigned value=sections[3][offset+character];
            if(!(value=='_'||(value>='a'&&value<='z')||(value>='A'&&value<='Z')||(character&&value>='0'&&value<='9')))FAIL("export names must be ASCII identifiers");
        }
        module->exports[index].name=malloc(length+1);if(!module->exports[index].name){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"export allocation failed");goto failed;}
        memcpy(module->exports[index].name,sections[3]+offset,length);module->exports[index].name[length]=0;module->exports[index].function=function;offset+=length;
        for(uint32_t previous=0;previous<index;previous++)if(!strcmp(module->exports[previous].name,module->exports[index].name))FAIL("duplicate export name");
    }
    if(offset!=lengths[3])FAIL("trailing export bytes");
    for(uint32_t index=0;index<annotations;index++) {
        const uint8_t *record=sections[6]+4+index*5;uint32_t pc=abc_u32(record);unsigned kind=record[4];
        if(pc>=lengths[2]||!value_kind(kind)||module->load_kinds[pc])FAIL("invalid or duplicate load kind annotation");
        module->load_kinds[pc]=(uint8_t)(kind+1);
    }
    if(callable) {
        module->sites=calloc(sites?sites:1,sizeof *module->sites);module->relocs=calloc(relocations?relocations:1,sizeof *module->relocs);
        if(!module->sites||!module->relocs){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"callable table allocation failed");goto failed;}
        offset=4;
        for(uint32_t index=0;index<sites;index++) {
            if(lengths[7]-offset<16)FAIL("truncated indirect signature");
            const uint8_t *record=sections[7]+offset;abc_function *site=&module->sites[index];
            site->entry=abc_u32(record);site->arguments=abc_u32(record+4);site->results=abc_u32(record+8);site->hidden_bytes=abc_u32(record+12);offset+=16;
            if(site->entry>=module->code_size||(index&&site->entry<=module->sites[index-1].entry)||!site->arguments||site->arguments>255||site->results>255||site->hidden_bytes>ABC_MAX_FILE||site->arguments+site->results>lengths[7]-offset)FAIL("invalid indirect signature offset/count");
            memcpy(site->argument_kinds,sections[7]+offset,site->arguments);offset+=site->arguments;
            memcpy(site->result_kinds,sections[7]+offset,site->results);offset+=site->results;
            for(uint32_t argument=0;argument<site->arguments;argument++)if(!value_kind(site->argument_kinds[argument]))FAIL("unsupported indirect argument kind");
            for(uint32_t result=0;result<site->results;result++)if(!value_kind(site->result_kinds[result]))FAIL("unsupported indirect result kind");
            if(site->argument_kinds[0]!=ABC_KIND_ADDR)FAIL("indirect signature needs environment address as first argument");
        }
        if(offset!=lengths[7])FAIL("trailing indirect signature bytes");
        for(uint32_t index=0;index<relocations;index++) {
            const uint8_t *record=sections[8]+4+index*8;abc_code_reloc *relocation=&module->relocs[index];relocation->offset=abc_u32(record);relocation->function=abc_u32(record+4);
            if((uint64_t)relocation->offset+8>module->data_size||relocation->function>=functions||(index&&relocation->offset<(uint64_t)module->relocs[index-1].offset+8))FAIL("invalid or overlapping code image relocation");
        }
    }
    if(foreign) {
        module->externs=calloc(externs?externs:1,sizeof *module->externs);if(!module->externs){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"extern allocation failed");goto failed;}
        offset=4;
        for(uint32_t index=0;index<externs;index++) {
            if(lengths[9]-offset<4)FAIL("truncated extern signature");
            abc_extern *external=&module->externs[index];external->arguments=sections[9][offset];external->results=sections[9][offset+1];unsigned length=abc_u16(sections[9]+offset+2);offset+=4;
            if(external->arguments>10||external->results>1||!length||length>255||(uint64_t)external->arguments+external->results+length>lengths[9]-offset)FAIL("invalid extern signature");
            unsigned integers=0,floats=0;
            for(unsigned argument=0;argument<external->arguments;argument++) {
                unsigned kind=sections[9][offset+argument];if(!value_kind(kind))FAIL("invalid extern argument kind");
                if(kind==ABC_KIND_FLOAT)floats++;else integers++;external->argument_kinds[argument]=(uint8_t)kind;
            }
            offset+=external->arguments;
            if(integers>6||floats>4)FAIL("extern exceeds C ABI argument limits");
            if(external->results){unsigned kind=sections[9][offset++];if(!value_kind(kind))FAIL("invalid extern result kind");external->result_kinds[0]=(uint8_t)kind;}
            external->name=malloc(length+1);if(!external->name){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"extern name allocation failed");goto failed;}
            memcpy(external->name,sections[9]+offset,length);external->name[length]=0;
            for(unsigned character=0;character<length;character++) {
                unsigned value=(unsigned char)external->name[character];
                if(!(value=='_'||(value>='a'&&value<='z')||(value>='A'&&value<='Z')||(character&&value>='0'&&value<='9')))FAIL("extern names must be ASCII identifiers");
            }
            offset+=length;
            if(!strncmp(external->name,"__let_rt_",9))FAIL("runtime primitive binding is not implemented");
            for(uint32_t previous=0;previous<index;previous++)if(!strcmp(module->externs[previous].name,external->name))FAIL("duplicate extern name");
        }
        if(offset!=lengths[9])FAIL("trailing extern bytes");
    }
    status=abc_verify_module(module,error);if(status!=ABC_OK)goto failed;*out=module;return ABC_OK;
failed:abc_module_free(module);return status;
#undef FAIL
}
