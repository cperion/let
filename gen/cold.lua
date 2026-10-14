-- Emit the shared checked target resolver and the flushed foreign boundary.
-- Neither helper executes ABC or changes instruction bytes.
local output=assert(arg[1],'output file required')
local file=assert(io.open(output..'.tmp','wb'))
assert(file:write([=[
abc_status vm_resolve_indirect(abc_exec_context *run, uint32_t pc, uint64_t target,
                               uint32_t *callee_index) {
    const abc_module *module=run->m;
    const abc_function *signature=abc_find_site(module,pc);
    uint32_t *observation=&run->image->indirect_site_states[signature-module->sites];
    uint64_t code_base=(uint64_t)(uintptr_t)module->code;
    if(*observation && *observation!=UINT32_MAX) {
        uint32_t observed_index=*observation-1;
        if(target==code_base+module->functions[observed_index].entry) {
            *callee_index=observed_index;
            return ABC_OK;
        }
        *observation=UINT32_MAX;
        run->image->transitions++;
    }
    const abc_function *callee=NULL;
    if(target>=code_base && target-code_base<module->code_size)
        callee=abc_function_entry(module,(uint32_t)(target-code_base));
    if(!callee || callee->has_halt)
        return abc_fail(&run->error,ABC_INVALID,pc,"indirect target is not a callable function entry in this module");
    if(!abc_same_signature(signature,callee))
        return abc_fail(&run->error,ABC_ARGUMENTS,pc,"indirect target signature disagrees with call site");
    *callee_index=(uint32_t)(callee-module->functions);
    if(!*observation) {
        *observation=*callee_index+1;
        run->image->transitions++;
    }
    return ABC_OK;
}

abc_status vm_foreign(abc_exec_context *run, unsigned extern_index,
                       unsigned selected_stack, uint32_t pc) {
    abc_exec_context *vm=run;
    abc_image *image=run->image;
    if(extern_index>=run->m->extern_count || !image->foreign_bridges || !image->foreign_bridges[extern_index])
        return abc_fail(&run->error,ABC_INVALID,pc,"unbound foreign call");
    const abc_extern *signature=&run->m->externs[extern_index];
    char argument_stack=selected_stack==ABC_STACK_A?'a':'b';
    uint64_t arguments[10],result=0;
    for(unsigned index=signature->arguments;index;index--)
        arguments[index-1]=vm_pop(vm,argument_stack);
    abc_status status=image->foreign_bridges[extern_index](signature,image->foreign[extern_index],arguments,&result);
    if(status!=ABC_OK){
        if(run->error.status==status) {run->error.offset=pc;return status;}
        return abc_fail(&run->error,status,pc,"foreign bridge failed");
    }
    if(signature->results)vm_push(vm,argument_stack,result);
    vm_publish_all(vm);
    return ABC_OK;
}
]=]))
assert(file:close());assert(os.rename(output..'.tmp',output))
