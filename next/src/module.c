#include "internal.h"
#include <errno.h>

const char *abc_status_name(abc_status status) {
    static const char *names[]={"ok","invalid","io","out-of-memory","export-not-found","arguments","abort","stack-limit","result-capacity"};
    return (unsigned)status<sizeof names/sizeof names[0]?names[status]:"unknown";
}
void abc_module_free(abc_module *module) {
    if(!module||atomic_fetch_sub_explicit(&module->references,1,memory_order_acq_rel)!=1)return;
    if(module->exports)for(uint32_t index=0;index<module->export_count;index++)free(module->exports[index].name);
    if(module->externs)for(uint32_t index=0;index<module->extern_count;index++)free(module->externs[index].name);
    free(module->exports);free(module->functions);free(module->code);free(module->image);free(module->load_kinds);
    free(module->sites);free(module->relocs);free(module->c_entries);free(module->externs);free(module);
}
int abc_find_export(const abc_module *module,const char *name) {
    if(!module||!name)return -1;
    for(uint32_t index=0;index<module->export_count;index++)if(!strcmp(module->exports[index].name,name))return (int)module->exports[index].function;
    return -1;
}
int abc_find_function(const abc_module *module,uint32_t entry) {
    const abc_function *function=abc_function_entry(module,entry);
    return function?(int)(function-module->functions):-1;
}
abc_status abc_module_export(const abc_module *module,const char *name,uint32_t *arguments,uint32_t *results,abc_error *error) {
    abc_clear(error);int index=abc_find_export(module,name);
    if(index<0)return abc_fail(error,ABC_NOT_FOUND,UINT32_MAX,"unknown export '%s'",name?name:"");
    if(arguments)*arguments=module->functions[index].arguments;
    if(results)*results=module->functions[index].results;
    return ABC_OK;
}
abc_status abc_module_export_signature(const abc_module *module,const char *name,abc_signature *out,abc_error *error) {
    abc_clear(error);
    if(!out)return abc_fail(error,ABC_INVALID,UINT32_MAX,"missing signature output");
    int index=abc_find_export(module,name);
    if(index<0)return abc_fail(error,ABC_NOT_FOUND,UINT32_MAX,"unknown export '%s'",name?name:"");
    const abc_function *function=&module->functions[index];abc_signature signature={0};
    signature.arguments=function->arguments;signature.results=function->results;signature.hidden_result_bytes=function->hidden_bytes;
    memcpy(signature.argument_kinds,function->argument_kinds,function->arguments);
    memcpy(signature.result_kinds,function->result_kinds,function->results);*out=signature;return ABC_OK;
}
const abc_function *abc_find_site(const abc_module *module,uint32_t pc) {
    uint32_t first=0,end=module->site_count;
    while(first<end){uint32_t middle=first+(end-first)/2;if(module->sites[middle].entry<pc)first=middle+1;else end=middle;}
    return first<module->site_count&&module->sites[first].entry==pc?&module->sites[first]:NULL;
}
abc_status abc_module_export_address(const abc_module *module,const char *name,uint64_t *out,abc_error *error) {
    abc_clear(error);if(!out)return abc_fail(error,ABC_INVALID,UINT32_MAX,"missing code address output");
    int index=abc_find_export(module,name);
    if(index<0)return abc_fail(error,ABC_NOT_FOUND,UINT32_MAX,"unknown export '%s'",name?name:"");
    if(module->functions[index].has_halt)return abc_fail(error,ABC_INVALID,UINT32_MAX,"HALT export is not bytecode-callable");
    *out=(uint64_t)(uintptr_t)(module->code+module->functions[index].entry);return ABC_OK;
}

abc_status abc_module_load(const void *bytes,size_t size,abc_module **out,abc_error *error) {
    abc_clear(error);if(out)*out=NULL;
    if(!out||!bytes||size<16||size>ABC_MAX_FILE)return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid module size or input");
    const uint8_t *header=bytes;
    unsigned revision=abc_u16(header+4),profile=header[7];
    if(memcmp(header,"ABC2",4)||(revision!=ABC_ISA_REVISION&&revision!=ABC_LIFECYCLE_REVISION))
        return abc_fail(error,ABC_INVALID,UINT32_MAX,"expected ABC2 revision 6 or lifecycle revision 7");
    if(revision==ABC_LIFECYCLE_REVISION&&profile!=4)
        return abc_fail(error,ABC_INVALID,UINT32_MAX,"lifecycle revision 7 requires profile 4");
    if(header[6]!=8||profile<1||profile>4||abc_u32(header+12))return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid typed capability profile header");
    if(profile>=2)return abc_load_memory(bytes,size,out,error);
    if(abc_u32(header+8)!=3)return abc_fail(error,ABC_INVALID,UINT32_MAX,"integer profile requires functions, code and exports");
    const uint8_t *sections[4]={0};uint32_t lengths[4]={0};size_t offset=16;
    for(unsigned index=0;index<3;index++) {
        if(size-offset<8)return abc_fail(error,ABC_INVALID,UINT32_MAX,"truncated section header");
        uint32_t tag=abc_u32(header+offset),length=abc_u32(header+offset+4);offset+=8;
        if(tag<1||tag>3||sections[tag]||length>size-offset)return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid, duplicate or unsupported section");
        sections[tag]=header+offset;lengths[tag]=length;offset+=length;
    }
    if(offset!=size||!sections[1]||!sections[2]||!sections[3]||lengths[1]<4||!lengths[2]||lengths[3]<4)
        return abc_fail(error,ABC_INVALID,UINT32_MAX,"missing sections or trailing bytes");
    uint32_t functions=abc_u32(sections[1]),exports=abc_u32(sections[3]);
    if(!functions||functions>ABC_MAX_FUNCTIONS||lengths[1]!=4+(uint64_t)functions*16||exports>ABC_MAX_FUNCTIONS)
        return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid function or export table");
    abc_module *module=calloc(1,sizeof *module);
    if(!module)return abc_fail(error,ABC_NOMEM,UINT32_MAX,"module allocation failed");
    atomic_init(&module->references,1);module->revision=revision;module->function_count=functions;module->export_count=exports;module->code_size=lengths[2];
    module->functions=calloc(functions,sizeof *module->functions);module->exports=calloc(exports?exports:1,sizeof *module->exports);module->code=malloc(lengths[2]);
    abc_status status=ABC_INVALID;
#define FAIL(...) do{status=abc_fail(error,ABC_INVALID,UINT32_MAX,__VA_ARGS__);goto failed;}while(0)
    if(!module->functions||!module->exports||!module->code){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"module allocation failed");goto failed;}
    memcpy(module->code,sections[2],lengths[2]);
    for(uint32_t index=0;index<functions;index++) {
        const uint8_t *record=sections[1]+4+index*16;abc_function *function=&module->functions[index];
        function->entry=abc_u32(record);function->arguments=abc_u32(record+4);function->results=abc_u32(record+8);
        if((!index&&function->entry)||function->entry>=lengths[2]||(index&&function->entry<=module->functions[index-1].entry)||function->arguments>255||function->results>255||abc_u32(record+12))FAIL("invalid function entry/count or aggregate result");
        if(index)module->functions[index-1].end=function->entry;
    }
    module->functions[functions-1].end=lengths[2];offset=4;
    for(uint32_t index=0;index<exports;index++) {
        if(lengths[3]-offset<6)FAIL("truncated export");
        uint32_t function=abc_u32(sections[3]+offset);unsigned length=abc_u16(sections[3]+offset+4);offset+=6;
        if(function>=functions||!length||length>255||length>lengths[3]-offset)FAIL("invalid export name or index");
        module->exports[index].name=malloc(length+1);
        if(!module->exports[index].name){status=abc_fail(error,ABC_NOMEM,UINT32_MAX,"export allocation failed");goto failed;}
        for(unsigned character=0;character<length;character++) {
            unsigned value=sections[3][offset+character];
            if(!(value=='_'||(value>='a'&&value<='z')||(value>='A'&&value<='Z')||(character&&value>='0'&&value<='9')))FAIL("export names must be ASCII identifiers");
        }
        memcpy(module->exports[index].name,sections[3]+offset,length);module->exports[index].name[length]=0;module->exports[index].function=function;offset+=length;
        for(uint32_t previous=0;previous<index;previous++)if(!strcmp(module->exports[previous].name,module->exports[index].name))FAIL("duplicate export name");
    }
    if(offset!=lengths[3])FAIL("trailing export bytes");
    status=abc_verify_module(module,error);if(status!=ABC_OK)goto failed;*out=module;return ABC_OK;
failed:abc_module_free(module);return status;
#undef FAIL
}
abc_status abc_module_read(const char *path,abc_module **out,abc_error *error) {
    abc_clear(error);if(out)*out=NULL;
    if(!path||!out)return abc_fail(error,ABC_INVALID,UINT32_MAX,"missing path or output");
    FILE *file=fopen(path,"rb");if(!file)return abc_fail(error,ABC_IO,UINT32_MAX,"cannot open '%s': %s",path,strerror(errno));
    if(fseek(file,0,SEEK_END)||ftell(file)<0){fclose(file);return abc_fail(error,ABC_IO,UINT32_MAX,"cannot size module");}
    long length=ftell(file);if(length>ABC_MAX_FILE||length<16){fclose(file);return abc_fail(error,ABC_INVALID,UINT32_MAX,"invalid module size");}
    rewind(file);uint8_t *bytes=malloc((size_t)length);if(!bytes){fclose(file);return abc_fail(error,ABC_NOMEM,UINT32_MAX,"file allocation failed");}
    size_t received=fread(bytes,1,(size_t)length,file);int failed=ferror(file);fclose(file);
    abc_status status=received!=(size_t)length||failed?abc_fail(error,ABC_IO,UINT32_MAX,"cannot read module"):abc_module_load(bytes,(size_t)length,out,error);
    free(bytes);return status;
}
