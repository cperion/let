#!/usr/bin/env python3
"""Tail materialization must succeed after capture correction.
The old check_tail.py is retained unchanged as a checker for the old failure.
"""
from pathlib import Path
import subprocess, os, json, re
root=Path(__file__).resolve().parent
rows=[]
for dst in ('A','B'):
    for config in ('original','reserved','transfer'):
        first={m:None for m in ('interpreted','compiled','lazy')}
        disagreements=[]
        for capacity in list(range(1,33))+[1024]:
            outcomes=[]
            for mode in first:
                env=dict(os.environ);env.pop('ABC_RESERVED_PROBE_PC',None);env.pop('ABC_RESERVED_TRACE',None)
                if config=='transfer':env['ABC_RESERVED_PROBE_PC']='0x326'
                runner=root/('original-runtime' if config=='original' else 'build/abc-runtime')
                p=subprocess.run([str(runner),'run',str(root/f'tail-{dst}.abc'),'main',f'--{mode}',f'--stack={capacity}'],env=env,text=True,capture_output=True,timeout=10)
                status='ok' if p.returncode==0 else 'stack' if 'abc: stack-limit' in p.stderr else 'other'
                assert status!='other',(dst,config,capacity,mode,p.returncode,p.stderr)
                if status=='ok':
                    assert p.stdout=='101\n',(dst,config,mode,p.stdout)
                    if first[mode] is None:first[mode]=capacity
                diagnostic=next((s for s in p.stderr.splitlines() if s.startswith('abc:')),'')
                row=dict(destination=dst,config=config,capacity=capacity,mode=mode,status=status,diagnostic=diagnostic)
                if capacity==1024:
                    assert status=='ok',row
                    row.update(general_entries=p.stderr.count('GENERAL_ENTRY '),materialized_returns=p.stderr.count('MATERIALIZED_RETURN '),general_version_counts=sorted(set(int(n) for n in re.findall(r'versions_at_pc=(\d+)',p.stderr))))
                    if config=='transfer' and mode!='interpreted':
                        assert row['general_entries']==10 and row['materialized_returns']>0,row
                        # Observe, do not excuse, the still-unfixed general-version duplication.
                        assert row['general_version_counts']==[1,2],row
                    (root/f'fixed-tail-{dst}-{config}-{mode}.log').write_text(p.stderr)
                rows.append(row);outcomes.append((status,diagnostic))
            if len(set(outcomes))>1:disagreements.append((capacity,outcomes))
        print(dst,config,'first successes',first,'status/diagnostic disagreements',disagreements)
        if config!='original':assert not disagreements,(dst,config,disagreements)
(root/'tail-capture-results.json').write_text(json.dumps(rows,indent=2)+'\n')
print(len(rows),'executions; all ample-stack results 101; no experimental policy or stack-diagnostic disagreements.')
print('NOT budget conformance: the tail forced edge still has two general contexts.')
