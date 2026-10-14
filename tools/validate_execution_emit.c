#include "execution_emit.h"
#include "threaded.h"
#include <assert.h>

static abc_exec_label label(abc_exec_emitter *e) {
    abc_exec_label l=ABC_EXEC_NO_LABEL;abc_error error;
    assert(e->ops->label(e,&l,77,&error)==ABC_OK);return l;
}
static void bind(abc_exec_emitter *e,abc_exec_label l) { abc_error error;assert(e->ops->bind(e,l,77,&error)==ABC_OK); }
static void emit(abc_exec_emitter *e,unsigned form,uint64_t value,abc_exec_label target) {
    const abc_exec_operands op={.value={value},.target=target};abc_error error;
    assert(e->ops->emit(e,form,&op,77,&error)==ABC_OK);
}
static abc_exec_emitter *create(unsigned threaded) {
    abc_exec_emitter *e=NULL;abc_error error;
    assert((threaded?abc_threaded_emitter_create(&e,&error):abc_native_emitter_create(32,&e,&error))==ABC_OK);
    assert(e->register_count==(threaded?7u:8u));return e;
}
static uint64_t *test_limit;
static uint64_t *bounds(unsigned stack){assert(stack==0);return test_limit;}
static uint64_t run(abc_exec_emitter *e,uintptr_t entry,uint64_t *a,uint64_t *b,uint64_t *c) {
    abc_exec_context context={0};abc_resume_state state={.entry=entry,.stack={a,b,c}};
    abc_exec_exit result=e->ops->enter(e,&context,&state);assert(result.disposition==ABC_EXEC_RETURNED);return result.packed_error;
}
int main(void) {
    for(unsigned threaded=0;threaded<2;threaded++){
        abc_exec_emitter *e=create(threaded);abc_error error;
        abc_exec_label entry=label(e),resume=label(e);bind(e,entry);
        /* A forward continuation survives builder growth; transport and transfer
           are separate records, with no recursive host invocation. */
        emit(e,ABC_FORM_STORE_LABEL,0,resume);
        emit(e,ABC_FORM_LOAD(2,1),0,ABC_EXEC_NO_LABEL);
        emit(e,ABC_FORM_CONTINUE(1),0,ABC_EXEC_NO_LABEL);
        for(unsigned i=0;i<100;i++)emit(e,ABC_FORM_CONST(0),99,ABC_EXEC_NO_LABEL);
        assert(e->ops->publish(e,77,&error)==ABC_INVALID&&error.offset==77);
        bind(e,resume);
        assert(e->ops->bind(e,resume,88,&error)==ABC_INVALID&&error.offset==88);
        emit(e,ABC_FORM_CONST(0),42,ABC_EXEC_NO_LABEL);
        emit(e,ABC_FORM_STORE(0,0),0,ABC_EXEC_NO_LABEL);
        emit(e,ABC_FORM_RETURN_OK,0,ABC_EXEC_NO_LABEL);
        assert(e->ops->publish(e,77,&error)==ABC_OK);
        assert(e->ops->publish(e,77,&error)==ABC_OK);
        uintptr_t start=e->ops->address(e,entry),target=e->ops->address(e,resume);
        assert(start&&target);
        abc_exec_storage storage=e->ops->storage(e);
        if(threaded){
            const abc_thread_word *t=(const abc_thread_word *)e->ops->region(e,0).base;
            assert(storage.body_bytes==(3+2+1+200+2+2+1)*8);
            assert(t[0].handler==abc_thread_forms[ABC_FORM_STORE_LABEL].handler);
            assert(t[1].bits==0&&(uintptr_t)t[2].target==target);
            assert(t[3].handler==abc_thread_forms[ABC_FORM_LOAD(2,1)].handler);
            assert(t[4].bits==0&&t[5].handler==abc_thread_forms[ABC_FORM_CONTINUE(1)].handler);
            assert(target==(uintptr_t)(t+206));
        }
        const abc_exec_operands op={.target=ABC_EXEC_NO_LABEL};
        assert(e->ops->emit(e,ABC_FORM_RETURN_OK,&op,99,&error)==ABC_INVALID&&error.offset==99);
        e->ops->discard_preparation(e);
        uint64_t a[2]={0,123},b[1]={456},c[1]={0};
        for(unsigned i=0;i<3;i++){
            assert(run(e,start,a,b,c)==ABC_OK);
            assert(a[0]==42&&a[1]==123&&b[0]==456&&c[0]==target);
        }
        e->ops->destroy(e);

        e=create(threaded);entry=label(e);bind(e,entry);
        const uint64_t packed=ABC_STACK|(UINT64_C(0x1234)<<16);
        test_limit=a+1;
        abc_exec_operands guard={.value={16,(uintptr_t)bounds,packed},.target=ABC_EXEC_NO_LABEL};
        assert(e->ops->emit(e,ABC_FORM_GUARD(0),&guard,0x1234,&error)==ABC_OK);
        emit(e,ABC_FORM_RETURN_OK,0,ABC_EXEC_NO_LABEL);
        assert(e->ops->publish(e,77,&error)==ABC_OK);
        assert(run(e,e->ops->address(e,entry),a,b,c)==packed);
        e->ops->destroy(e);

        e=create(threaded);
        abc_exec_operands bad={.target=ABC_EXEC_NO_LABEL};
        assert(e->ops->emit(e,ABC_FORM_COUNT,&bad,101,&error)==ABC_INVALID&&error.offset==101);
        if(threaded)assert(e->ops->emit(e,ABC_FORM_CONST(7),&bad,102,&error)==ABC_INVALID&&error.offset==102);
        e->ops->destroy(e);
    }
    puts("execution emitters: native/threaded labels, tape words, growth, continuations, publication and errors pass");
    return 0;
}
