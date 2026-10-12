#!/usr/bin/env python3
"""Check recorded execution, then evaluate the proposed coordinate change.
This does NOT execute a new return ABI or a canonicalized general-entry edge.
"""
from pathlib import Path
import collections,json,re
root=Path(__file__).resolve().parent
rows=[]
for dst in ('A','B'):
    reference=(root/f'interpreter-return-{dst}.txt').read_text()
    assert f'destination={dst}' in reference and 'caller_C_top=8 results=607,17' in reference,reference
    for mode in ('compiled','lazy'):
        assert (root/f'return-{dst}-{mode}.out').read_text()=='101\n'
        text=(root/f'return-{dst}-{mode}.log').read_text()
        entries={int(n):(int(base),int(bias)) for n,base,bias in re.findall(r'GENERAL_ENTRY (\d+) roots_stable=3 A=555 B=666 cbase=(\d+) bias=(\d+)',text)}
        returns={int(n):(int(base),int(slot),int(delta)) for n,base,slot,delta in re.findall(r'LEAF_RETURN activation=(\d+) cbase=(\d+) slot=(\d+) displacement=(-?\d+)',text)}
        before={int(n):(kind,int(base),int(delta)) for kind,n,base,delta in re.findall(r'(REAL|MATERIALIZED)_RESUME_BEFORE activation=(\d+) cbase=(\d+) displacement=(-?\d+)',text)}
        after={int(n):(kind,int(base)) for kind,n,base in re.findall(r'(REAL|MATERIALIZED)_RESUME_AFTER activation=(\d+) cbase=(\d+)',text)}
        contracts={int(n):(kind,int(top)) for kind,n,top in re.findall(r'(REAL|MATERIALIZED)_CALLER_CONTRACT activation=(\d+) caller_ctop=(-?\d+)',text)}
        assert set(entries)==set(returns)==set(before)==set(after)==set(contracts)==set(range(1,11))
        assert {v[0] for v in before.values()}=={'REAL','MATERIALIZED'}
        for n in entries:
            base,bias=entries[n];retbase,slot,ret_delta=returns[n]
            kind,resbase,res_delta=before[n];afterkind,parentbase=after[n]
            assert base==retbase==resbase and slot==8 and ret_delta==slot-base
            contractkind,parent_ctop=contracts[n]
            assert kind==afterkind==contractkind and parentbase in (1,6) and resbase+res_delta==parentbase
            assert parentbase+parent_ctop==slot
            if kind=='MATERIALIZED':assert parentbase==6 and parent_ctop==2
            else:assert res_delta==-(parent_ctop+3+1) # original CALL has three arguments
            assert (base,bias)==((12,1) if kind=='REAL' else (13,0))
            # Only coordinate arithmetic below; not a modified-engine execution.
            canonical_base=base+bias
            old_cells=[base+bias-4+i for i in range(6)]
            canonical_cells=[canonical_base-4+i for i in range(6)]
            assert old_cells==canonical_cells==list(range(9,15))
            naive_resume=canonical_base+res_delta
            assert naive_resume==parentbase+(kind=='REAL')
            proposed_return=canonical_base-4-1
            proposed_resume=proposed_return-parent_ctop
            assert proposed_return==slot and proposed_resume==parentbase
            rows.append(dict(destination=dst,mode=mode,activation=n,kind=kind,
                observed_base=base,observed_bias=bias,observed_continuation_slot=slot,
                observed_resume_delta=res_delta,observed_parent_base=parentbase,observed_parent_ctop=parent_ctop,
                model_canonical_base=canonical_base,model_naive_resume_base=naive_resume,
                model_RET_pop_base=proposed_return,model_parent_resume_base=proposed_resume))
(root/'return-results.json').write_text(json.dumps(rows,indent=2)+'\n')
print('4 native executions returned 101; 40 observed leaf-return/caller-resume pairs checked.')
print('2 interpreter executions returned ordered 607,17 results to A/B and popped C to cell 8.')
print('Observed paths:',dict(collections.Counter((r['mode'],r['kind']) for r in rows)))
print('Coordinate model: all six C homes stay at cells 9..14 under normalization.')
print('Coordinate model: normalize-only resumes one cell too high on every real return.')
print('Coordinate model: project RET pop to cell 8, then restore the recorded caller cache base (1 or 6).')
print('No new return convention, entry merging, budget enforcement or performance validated.')
