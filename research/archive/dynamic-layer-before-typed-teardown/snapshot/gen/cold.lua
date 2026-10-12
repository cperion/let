-- Generate the two explicit C boundaries used by interpreter handlers:
-- indirect-target resolution and the specification-mandated flushed FCALL ABI.
local output=assert(arg[1],'output file required')
local f=assert(io.open(output..'.tmp','wb'))
assert(f:write([=[abc_status vm_resolve_indirect(abc_run *r,const uint8_t *p,uint32_t pc,uint64_t target,unsigned form,int *result) {
    const abc_module *m=r->m; abc_image *image=r->image; abc_error *e=r->e; unsigned op=p[0],phase=(op-OP_CALLI_A)/3; int tail=form==2,callee=-1;
    uint64_t base=(uint64_t)(uintptr_t)m->code; uint32_t cache=abc_u32(p+(tail?3:2));
    if(phase==1&&cache<m->function_count&&target==base+m->functions[cache].entry)callee=(int)cache;
    else { if(phase==1){image->code[pc]=(uint8_t)(OP_CALLI_FINAL_A+form);image->transitions++;} if(target>=base&&target-base<m->code_size)callee=abc_find_function(m,(uint32_t)(target-base)); }
    if(callee<0||m->functions[callee].has_halt)return abc_fail(e,ABC_INVALID,pc,"indirect target is not a callable function entry in this module");
    const abc_function *site=abc_find_site(m,pc); if(!site||!abc_same_signature(site,&m->functions[callee]))return abc_fail(e,ABC_ARGUMENTS,pc,"indirect target signature disagrees with call site");
    if(!phase){vm_store(image->code+pc+(tail?3:2),4,(uint32_t)callee);image->code[pc]=(uint8_t)(OP_CALLI_MONO_A+form);image->transitions++;}
    *result=callee;return ABC_OK;
}
abc_status vm_foreign(abc_run *r,const uint8_t *p,uint32_t pc) {
    abc_vm *v=r->v;const abc_module *m=r->m;abc_image *image=r->image;abc_error *e=r->e;
    unsigned index=abc_u16(p+1);if(index>=m->extern_count||!image->foreign||!image->foreign[index])return abc_fail(e,ABC_INVALID,pc,"unbound foreign call");
    const abc_extern *ext=&m->externs[index];uint64_t args[10],result=0;for(unsigned j=ext->arguments;j;j--)args[j-1]=vm_pop(v,'a');
    abc_status status=image->foreign_bridges[index](ext,image->foreign[index],args,&result);if(status!=ABC_OK)return abc_fail(e,status,pc,"foreign bridge failed");
    if(ext->results)vm_push(v,'a',result);while(v->ca)vm_spill(v,'a');while(v->cb)vm_spill(v,'b');while(v->cc)vm_spill(v,'c');return ABC_OK;
}]=]))
assert(f:close())
assert(os.rename(output..'.tmp',output))
