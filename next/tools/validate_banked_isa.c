/* Execute revision-6 handlers and verifier without the migrating assembler.
   Modules below have explicit signatures; the verifier computes their shapes. */
#include "vm_internal.h"
#include "residualize.h"
#include "execution_emit.h"
#include <assert.h>
#include <stdio.h>

static unsigned cases;
static void run_program(uint8_t *code,size_t length,abc_function *functions,unsigned function_count,
                        const uint64_t *expected,unsigned result_count) {
    abc_export export={"main",0};
    abc_module module={.code=code,.code_size=length,.functions=functions,
        .function_count=function_count,.exports=&export,.export_count=1};
    atomic_init(&module.references,1);
    abc_limits limits={.stack_cells=64,.mode=ABC_EXEC_INTERPRETED};
    abc_vm *vm=NULL;abc_error error;
    if(abc_verify_module(&module,&error)!=ABC_OK) {
        fprintf(stderr,"verification case %u: %s at %u\n",cases,error.message,error.offset);abort();
    }
    assert(abc_vm_create(&limits,&vm,&error)==ABC_OK);
    for(unsigned repetition=0;repetition<2;repetition++) {
        uint64_t results[8]={0};size_t count=0;
        abc_status status=abc_vm_call(vm,&module,"main",NULL,0,results,8,&count,&error);
        if(status!=ABC_OK){fprintf(stderr,"case %u: %s at %u\n",cases,error.message,error.offset);abort();}
        assert(count==result_count);
        for(unsigned index=0;index<result_count;index++)assert(results[index]==expected[index]);
    }
    abc_vm_free(vm);
    assert(atomic_load(&module.references)==1);
    cases++;
}
static void kernel(uint8_t *code,size_t length,uint64_t expected) {
    abc_function function={.entry=0,.end=(uint32_t)length,.results=1,.max_a=8,.max_b=8,.max_c=8};
    run_program(code,length,&function,1,&expected,1);
}
static void call_matrix(void) {
    for(unsigned results=1;results<=2;results++)
    for(unsigned caller=0;caller<2;caller++)for(unsigned source=0;source<2;source++) {
        uint8_t code[64];unsigned length=0;
        code[length++]=OP_PUSH8_A;code[length++]=111;
        code[length++]=OP_PUSH8_B;code[length++]=122;
        code[length++]=(uint8_t)(OP_PUSH8_A+caller);code[length++]=11;
        code[length++]=(uint8_t)(OP_PUSH8_A+caller);code[length++]=7;
        unsigned call=length;
        code[length++]=(uint8_t)(OP_CALL_A+caller);
        for(unsigned index=0;index<4;index++)code[length++]=0;
        code[length++]=2;
        if(caller)for(unsigned index=0;index<results;index++)code[length++]=OP_MOVE_B;
        code[length++]=OP_MOVE_B;
        code[length++]=OP_RET_A;code[length++]=0;code[length++]=(uint8_t)(results+2);
        unsigned callee=length;
        code[length++]=(uint8_t)(OP_CGET0_A+source);
        code[length++]=(uint8_t)(OP_CGET1_A+(1-source));
        code[length++]=(uint8_t)(OP_SUB_A+source);
        if(results==2){code[length++]=(uint8_t)(OP_PUSH8_A+source);code[length++]=5;}
        code[length++]=(uint8_t)(OP_RET_A+source);code[length++]=2;code[length++]=(uint8_t)results;
        uint32_t displacement=callee-(call+6);
        for(unsigned index=0;index<4;index++)code[call+1+index]=(uint8_t)(displacement>>(8*index));
        abc_function functions[2]={
            {.entry=0,.end=callee,.results=results+2,.max_a=8,.max_b=8,.max_c=8},
            {.entry=callee,.end=length,.arguments=2,.results=results,.max_a=2,.max_b=2,.max_c=2},
        };
        uint64_t expected[]={111,4,122,0};
        if(results==2){expected[1]=caller?5:4;expected[2]=caller?4:5;expected[3]=122;}
        run_program(code,length,functions,2,expected,results+2);
    }
}
static uint64_t foreign_double(uint64_t value) {return value*2;}
static uint64_t foreign_observed;
static void foreign_double_void(uint64_t value) {foreign_observed=value*2;}
static void foreign_transport(unsigned returns) {
    uint8_t code[]={OP_PUSH8_A,11,OP_PUSH8_B,21,OP_FCALL_B,0,0,OP_MOVE_B,OP_RET_A,0,2};
    unsigned length=sizeof code;
    if(!returns){code[7]=OP_RET_A;code[8]=0;code[9]=1;length--;}
    abc_function function={.end=length,.results=1+returns};abc_export export={"main",0};
    abc_extern external={.name="twice",.arguments=1,.results=(uint8_t)returns};
    abc_module module={.code=code,.code_size=length,.functions=&function,.function_count=1,
        .exports=&export,.export_count=1,.memory_profile=1,.callable_profile=1,.foreign_profile=1,
        .externs=&external,.extern_count=1};
    atomic_init(&module.references,1);abc_error error;
    for(unsigned mirror=0;mirror<2;mirror++) {
        if(mirror){code[0]^=1;code[2]^=1;code[4]^=1;code[7]^=1;if(returns)code[8]^=1;}
        assert(abc_verify_module(&module,&error)==ABC_OK);
        for(unsigned mode=ABC_EXEC_INTERPRETED;mode<=ABC_EXEC_THREADED;mode++) {
            abc_vm *vm=NULL;abc_limits limits={.stack_cells=64,.mode=(abc_execution_mode)mode};
            assert(abc_vm_create(&limits,&vm,&error)==ABC_OK);
            assert(abc_vm_bind_foreign(vm,"twice",returns?(abc_foreign_address)foreign_double:(abc_foreign_address)foreign_double_void,&error)==ABC_OK);
            assert(abc_vm_load(vm,&module,&error)==ABC_OK);
            uint64_t results[2];size_t count;foreign_observed=0;
            assert(abc_vm_call(vm,&module,"main",NULL,0,results,2,&count,&error)==ABC_OK);
            assert(count==1+returns&&results[0]==11);
            assert(returns?results[1]==42:foreign_observed==42);
            abc_vm_free(vm);cases++;
        }
    }
}
static void indirect_history(abc_execution_mode mode,unsigned mirror,unsigned mixed) {
    uint8_t code[]={OP_CGET0_B,OP_CGET0_A,OP_CALLI_B,1,OP_RET_B,1,1,
        OP_PUSH8_B,42,OP_RET_B,1,1,OP_PUSH8_A,99,OP_RET_A,1,1,
        OP_PUSH8_A,55,OP_RET_A,1,1,OP_CPOP,OP_PUSH8_A,77,OP_HALT_A};
    if(mirror){const unsigned offsets[]={0,1,2,4,7,9,12,14,17,19,23,25};
        for(unsigned i=0;i<sizeof offsets/sizeof offsets[0];i++)code[offsets[i]]^=1;}
    uint8_t original[sizeof code];memcpy(original,code,sizeof code);
    abc_function functions[]={
        {.entry=0,.end=7,.arguments=1,.results=1,.argument_kinds={ABC_KIND_ADDR}},
        {.entry=7,.end=12,.arguments=1,.results=1,.argument_kinds={ABC_KIND_ADDR}},
        {.entry=12,.end=17,.arguments=1,.results=1,.argument_kinds={ABC_KIND_ADDR}},
        {.entry=17,.end=22,.arguments=1,.results=1},
        {.entry=22,.end=26,.arguments=1,.results=1,.argument_kinds={ABC_KIND_ADDR}},
    };
    abc_function signature={.entry=2,.arguments=1,.results=1,.argument_kinds={ABC_KIND_ADDR}};
    abc_export export={"main",0};
    abc_module module={.code=code,.code_size=sizeof code,.functions=functions,.function_count=5,
        .exports=&export,.export_count=1,.memory_profile=1,.callable_profile=1,.sites=&signature,.site_count=1};
    atomic_init(&module.references,1);abc_error error;abc_vm *vm=NULL;
    assert(abc_verify_module(&module,&error)==ABC_OK);
    abc_limits limits={.stack_cells=64,.mode=mixed?ABC_EXEC_INTERPRETED:mode};
    assert(abc_vm_create(&limits,&vm,&error)==ABC_OK);
    assert(abc_vm_load(vm,&module,&error)==ABC_OK);
    if(mixed){
        /* Prepare both existing bindings for this internal ownership probe.
           A native-only image intentionally has no interpreter call tables. */
        vm->mode=mode;
        assert(abc_residualize_module(&module,vm->images->bytes,vm,mode,&vm->images->execution,&error)==ABC_OK);
    }
    abc_vm *independent=NULL;assert(abc_vm_create(&limits,&independent,&error)==ABC_OK);
    assert(abc_vm_load(independent,&module,&error)==ABC_OK);
    uint64_t private_entry=mode==ABC_EXEC_INTERPRETED?17:(uint64_t)(uintptr_t)vm->images->execution->entries[1];
    uint64_t targets[]={0,7,1,(uint64_t)(uintptr_t)(code+8),(uint64_t)(uintptr_t)original,
        private_entry,(uint64_t)(uintptr_t)(code+17),(uint64_t)(uintptr_t)(code+7),
        (uint64_t)(uintptr_t)(code+7),0,(uint64_t)(uintptr_t)(code+17),(uint64_t)(uintptr_t)(code+12),
        (uint64_t)(uintptr_t)(code+22)};
    abc_status statuses[]={ABC_INVALID,ABC_INVALID,ABC_INVALID,ABC_INVALID,ABC_INVALID,ABC_INVALID,
        ABC_ARGUMENTS,ABC_OK,ABC_OK,ABC_INVALID,ABC_ARGUMENTS,ABC_OK,ABC_INVALID};
    unsigned transitions[]={0,0,0,0,0,0,0,1,1,2,2,2,2};
    size_t native_size=(mode==ABC_EXEC_COMPILED||mode==ABC_EXEC_THREADED)?vm->images->execution->code_size:0;
    uint8_t *native_snapshot=native_size?malloc(native_size):NULL;
    if(native_size){assert(native_snapshot);abc_exec_emitter *emitter=vm->images->execution->emitter;size_t offset=0;
        abc_exec_storage storage=emitter->ops->storage(emitter);
        for(size_t i=0;i<storage.regions;i++){abc_exec_region r=emitter->ops->region(emitter,i);memcpy(native_snapshot+offset,r.base,r.body_bytes);offset+=r.body_bytes;}
        assert(offset==native_size);
    }
    for(unsigned index=0;index<sizeof targets/sizeof targets[0];index++) {
        /* Internal contract probe, not a new public policy-switching API:
           interpreter establishes mono; native finalizes; interpreter sees it. */
        vm->mode=mixed&&(index==7||index==10)?ABC_EXEC_INTERPRETED:mode;
        uint64_t result=UINT64_MAX;size_t count;
        assert(abc_vm_call(vm,&module,"main",&targets[index],1,&result,1,&count,&error)==statuses[index]);
        if(statuses[index]==ABC_OK)assert(count==1&&result==(targets[index]==(uint64_t)(uintptr_t)(code+12)?99:42));
        else {assert(count==0&&result==UINT64_MAX);assert(error.offset==2);}
        abc_site_stats stats;assert(abc_vm_site_stats(vm,&module,&stats,&error)==ABC_OK);
        assert(stats.transitions==transitions[index]);
        assert(stats.specific==(transitions[index]==1));assert(stats.final_generic==(transitions[index]==2));
        assert(vm->images->indirect_site_states[0]==(transitions[index]==0?0:transitions[index]==1?2:UINT32_MAX));
        assert(abc_vm_site_stats(independent,&module,&stats,&error)==ABC_OK);
        assert(stats.transitions==0&&stats.specific==0&&stats.final_generic==0);
        assert(!memcmp(code,original,sizeof code));
        if(native_size){abc_exec_emitter *emitter=vm->images->execution->emitter;size_t offset=0;abc_exec_storage storage=emitter->ops->storage(emitter);
            for(size_t i=0;i<storage.regions;i++){abc_exec_region r=emitter->ops->region(emitter,i);assert(!memcmp(native_snapshot+offset,r.base,r.body_bytes));offset+=r.body_bytes;}assert(offset==native_size);
        }
    }
    free(native_snapshot);abc_vm_free(independent);abc_vm_free(vm);cases++;
}
int main(void) {
    uint8_t selected_subtract[]={OP_PUSH8_A,10,OP_PUSH8_B,3,OP_SUB_B,OP_RET_B,0,1};
    kernel(selected_subtract,sizeof selected_subtract,(uint64_t)-7);
    uint8_t nested[]={OP_PUSH8_A,20,OP_PUSH8_B,10,OP_PUSH8_A,3,OP_SUB_B,OP_SUB_A,OP_RET_A,0,1};
    kernel(nested,sizeof nested,13);
    uint8_t context[]={OP_PUSH8_B,7,OP_CPUSH_B,OP_PUSH8_B,10,OP_EXT_B,EXT_SUBC,0,OP_CPOP,OP_RET_B,0,1};
    kernel(context,sizeof context,3);
    uint8_t branch[]={OP_PUSH8_B,7,OP_EXT_B,EXT_BEQI,7,2,0,OP_ABORT,9,OP_PUSH8_B,42,OP_RET_B,0,1};
    kernel(branch,sizeof branch,42);
    uint8_t range[]={OP_PUSH8_B,11,OP_PUSH8_B,7,OP_CPUSHN_B,2,OP_CGETR_A,0,2,OP_MOVE_A,OP_SUB_A,OP_RET_A,2,1};
    kernel(range,sizeof range,4);
    uint8_t halt[]={OP_PUSH8_B,42,OP_HALT_B};
    kernel(halt,sizeof halt,42);
    call_matrix();foreign_transport(0);foreign_transport(1);
    for(unsigned mode=ABC_EXEC_INTERPRETED;mode<=ABC_EXEC_THREADED;mode++)
        for(unsigned mirror=0;mirror<2;mirror++){
            indirect_history((abc_execution_mode)mode,mirror,0);
            if(mode!=ABC_EXEC_INTERPRETED)indirect_history((abc_execution_mode)mode,mirror,1);
        }
    printf("revision-6 banked/call contracts: %u cases, including foreign transport and indirect history in all modes\n",cases);
    return 0;
}
