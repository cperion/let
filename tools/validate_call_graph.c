#include "residual_analysis.h"
#include <assert.h>
#include <stdio.h>

static void check(const char *path) {
    abc_module *module=NULL;abc_error error;
    if(abc_module_read(path,&module,&error)!=ABC_OK){fprintf(stderr,"%s: %s\n",path,error.message);abort();}
    assert(module->function_count==9);
    abc_residual_call_graph graph={0};
    assert(abc_residual_analysis_build_call_graph(module,&graph));
    assert(graph.count==9&&graph.edge_count==7&&graph.component_count==7);
    const int targets[]={1,2,1,3,-1,6,5,4,-1};
    const unsigned recursive[]={0,1,1,1,0,1,1,0,0};
    const unsigned nested[]={0,1,1,0,0,0,0,0,0};
    unsigned extended=0,switches=0,indirect=0,indirect_tail=0;
    for(unsigned function=0;function<9;function++) {
        assert(graph.recursive[function]==recursive[function]);
        assert(graph.nested_eligible[function]==nested[function]);
        uint32_t edges=graph.offsets[function+1]-graph.offsets[function];
        assert(edges==(targets[function]>=0?1u:0u));
        if(edges)assert(graph.edges[graph.offsets[function]]==(unsigned)targets[function]);
        const abc_function *definition=&module->functions[function];
        unsigned calls=0;
        for(uint32_t pc=definition->entry;pc<definition->end;) {
            abc_decoded_instruction instruction;
            assert(abc_decode_instruction(module->code+pc,definition->end-pc,&instruction));
            unsigned kind=instruction.metadata->kind;
            extended+=abc_core_instructions[module->code[pc]].kind==K_EXT;
            switches+=kind==K_SWITCH;indirect+=kind==K_ICALL;indirect_tail+=kind==K_ITCALL;
            uint32_t target=UINT32_MAX;
            int found=abc_residual_analysis_direct_target(module,pc,&target);
            assert(found==(kind==K_CALL||kind==K_TCALL));
            if(found){assert(target==module->functions[targets[function]].entry);calls++;}
            else assert(target==UINT32_MAX);
            pc+=instruction.length;
        }
        assert(calls==edges);
        for(unsigned other=0;other<9;other++) {
            int together=function==other||(function==1&&other==2)||(function==2&&other==1)||
                (function==5&&other==6)||(function==6&&other==5);
            assert((graph.component[function]==graph.component[other])==together);
        }
    }
    assert(extended==1&&switches==1&&indirect==1&&indirect_tail==1);
    abc_residual_analysis_call_graph_free(&graph);abc_module_free(module);
}
int main(int argc,char **argv) {
    if(argc<2){fprintf(stderr,"usage: validate-call-graph module...\n");return 2;}
    for(int index=1;index<argc;index++)check(argv[index]);
    printf("revision-6 call graph: %d module(s), boundaries and recursion policy passed\n",argc-1);
    return 0;
}
