#include "vm_internal.h"
#include "residualize.h"
#include "residual_builder.h"
#include "abc_tool.h"
#include <assert.h>

static unsigned checks;
#define CHECK(x) do { if(!(x)){fprintf(stderr,"C-entry check failed at %d: %s\n",__LINE__,#x);exit(1);}checks++; } while(0)

/* Exercise the actual shared resolver independently of VM image admission. No
   lifecycle body is executed, and this fixture is never published into a VM. */
static void resolver_checks(const abc_module *module) {
    CHECK(module->site_count==1 && module->reloc_count==1 && module->c_entry_count==3);
    uint32_t observation=0,index=UINT32_MAX;
    abc_image image={.module=module,.indirect_site_states=&observation};
    abc_exec_context run={.m=module,.image=&image};
    uint32_t pc=module->sites[0].entry;
    uint32_t ordinary=module->relocs[0].function,cleanup=module->c_entries[0].function;
    uint64_t ordinary_address=(uint64_t)(uintptr_t)(module->code+module->functions[ordinary].entry);
    uint64_t cleanup_identity=(uint64_t)(uintptr_t)(module->code+module->functions[cleanup].entry);
    CHECK(abc_same_signature(&module->functions[ordinary],&module->functions[cleanup]));
    CHECK(!module->functions[ordinary].c_entry && module->functions[cleanup].c_entry);
    CHECK(vm_resolve_indirect(&run,pc,cleanup_identity,&index)==ABC_INVALID && index==UINT32_MAX);
    CHECK(observation==0 && image.transitions==0);
    CHECK(vm_resolve_indirect(&run,pc,ordinary_address,&index)==ABC_OK && index==ordinary);
    CHECK(observation==ordinary+1 && image.transitions==1);
    CHECK(vm_resolve_indirect(&run,pc,ordinary_address,&index)==ABC_OK && image.transitions==1);
    index=UINT32_MAX;
    CHECK(vm_resolve_indirect(&run,pc,cleanup_identity,&index)==ABC_INVALID && index==UINT32_MAX);
    CHECK(observation==UINT32_MAX && image.transitions==2);
    CHECK(vm_resolve_indirect(&run,pc,cleanup_identity,&index)==ABC_INVALID && image.transitions==2);
    CHECK(vm_resolve_indirect(&run,pc,ordinary_address,&index)==ABC_OK && index==ordinary);
    CHECK(observation==UINT32_MAX && image.transitions==2);
}

/* These structurally valid fixtures call ordinary ABC from a lifecycle body.
   Real delivery must reject that unsafe cleanup contract before publication. */
static void execution_checks(const abc_module *module,const abc_module *ordinary) {
    abc_error error;
    unsigned references=atomic_load(&module->references);
    for(unsigned mode=0;mode<4;mode++) {
        abc_limits limits={.stack_cells=128,.mode=(abc_execution_mode)mode};abc_vm *vm=NULL;
        CHECK(abc_vm_create(&limits,&vm,&error)==ABC_OK);
        CHECK(abc_vm_load(vm,module,&error)==ABC_INVALID && strstr(error.message,"lifecycle C-entry body"));
        CHECK(!vm->images && atomic_load(&module->references)==references);
        CHECK(abc_vm_load(vm,module,NULL)==ABC_INVALID && !vm->images);
        uint8_t untouched=0xa5;
        CHECK(abc_vm_read_image(vm,module,0,&untouched,1,&error)==ABC_NOT_FOUND && untouched==0xa5);
        uint64_t result=991;size_t count=999;
        CHECK(abc_vm_call(vm,module,"main",NULL,0,&result,1,&count,&error)==ABC_INVALID);
        CHECK(result==991 && count==0 && !vm->images && !vm->executing);
        if(mode!=ABC_EXEC_INTERPRETED) {
            abc_execution_image *execution=(abc_execution_image *)(uintptr_t)1;
            CHECK(abc_residualize_module(module,module->image,vm,(abc_execution_mode)mode,&execution,&error)==ABC_INVALID);
            CHECK(!execution && strstr(error.message,"lifecycle C-entry body"));
        }
        CHECK(abc_vm_load(vm,ordinary,&error)==ABC_OK);
        abc_image *prior=vm->images;
        uint8_t before[32],after[32];
        CHECK(abc_vm_read_image(vm,ordinary,0,before,sizeof before,&error)==ABC_OK);
        CHECK(abc_vm_load(vm,module,&error)==ABC_INVALID && vm->images==prior);
        CHECK(abc_vm_read_image(vm,ordinary,0,after,sizeof after,&error)==ABC_OK && !memcmp(before,after,sizeof before));
        CHECK(abc_vm_call(vm,ordinary,"main",NULL,0,&result,1,&count,&error)==ABC_OK && count==1 && result==42);
        CHECK(atomic_load(&module->references)==references);
        abc_vm_free(vm);
    }
}

static void tooling_checks(const char *path,const abc_module *module) {
    abc_residual_bundle *bundle=(abc_residual_bundle *)(uintptr_t)1;
    abc_residual_build_diagnostic diagnostic;
    CHECK(abc_residual_build(module,NULL,&bundle,&diagnostic)==ABC_RESIDUAL_BUILD_UNSUPPORTED);
    CHECK(!bundle && diagnostic.status==ABC_RESIDUAL_BUILD_UNSUPPORTED && strstr(diagnostic.message,"lifecycle entry ABI"));
    FILE *file=fopen(path,"rb");CHECK(file!=NULL);
    CHECK(!fseek(file,0,SEEK_END));long length=ftell(file);CHECK(length>0);rewind(file);
    char *bytes=malloc((size_t)length);CHECK(bytes!=NULL);
    CHECK(fread(bytes,1,(size_t)length,file)==(size_t)length);CHECK(!fclose(file));
    char *source=(char *)(uintptr_t)1;size_t size=999;abc_error error;
    CHECK(abc_emit_c(bytes,(size_t)length,&source,&size,&error)==ABC_INVALID);
    CHECK(!source && !size && strstr(error.message,"portable C lifecycle entries"));
    free(bytes);
}

int main(int argc,char **argv) {
    if(argc!=5){fprintf(stderr,"usage: validate-c-entries entries.abc optimized.abc ordinary.abc empty.abc\n");return 2;}
    abc_module *ordinary=NULL;abc_error error;
    CHECK(abc_module_read(argv[3],&ordinary,&error)==ABC_OK);
    CHECK(ordinary->revision==ABC_ISA_REVISION && !ordinary->c_entry_count);
    for(unsigned input=1;input<=2;input++) {
        abc_module *module=NULL;CHECK(abc_module_read(argv[input],&module,&error)==ABC_OK);
        CHECK(module->revision==ABC_LIFECYCLE_REVISION && module->foreign_profile);
        resolver_checks(module);execution_checks(module,ordinary);tooling_checks(argv[input],module);
        for(uint32_t i=0;i<module->export_count;i++)CHECK(!module->functions[module->exports[i].function].c_entry);
        abc_module_free(module);
    }
    abc_module *empty=NULL;CHECK(abc_module_read(argv[4],&empty,&error)==ABC_OK);
    CHECK(empty->revision==ABC_LIFECYCLE_REVISION && !empty->c_entry_count);
    for(uint32_t i=0;i<empty->function_count;i++)CHECK(!empty->functions[i].c_entry);
    for(unsigned mode=0;mode<4;mode++) {
        abc_limits limits={.mode=(abc_execution_mode)mode};abc_vm *vm=NULL;uint64_t result=0;size_t count=0;
        CHECK(abc_vm_create(&limits,&vm,&error)==ABC_OK && abc_vm_load(vm,empty,&error)==ABC_OK);
        CHECK(abc_vm_call(vm,empty,"main",NULL,0,&result,1,&count,&error)==ABC_OK && count==1 && result==42);
        abc_vm_free(vm);
    }
    abc_module_free(empty);abc_module_free(ordinary);
    printf("C-entry boundaries: %u checks; ABC target exclusion and fail-closed delivery in four modes; no lifecycle execution\n",checks);
    return 0;
}
