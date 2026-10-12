from pathlib import Path
import subprocess, json, os, re
root=Path(__file__).parent
report={'baseline':[], 'instrumented':[], 'stack_sweep':[], 'limitations':[
    'No new saturation policy or actual virtual-to-general transfer is implemented.',
    'Continuation insertion is tested on copied real native stack contents; live VM memory is not moved.',
    'Instrumentation canonicalizes values within the existing continuation family before capture.',
    'No performance inference is valid from the instrumented build.']}
for dst in ('A','B'):
    for mode in ('interpreted','compiled','lazy'):
        p=subprocess.run([str(root/'baseline-runtime'),'run',str(root/f'layout-{dst}.abc'),'main',f'--{mode}','--stack=1024'],text=True,capture_output=True)
        assert p.returncode==0 and p.stdout=='101\n',(dst,mode,p.stderr)
        report['baseline'].append({'destination':dst,'mode':mode,'result':101})
    for mode in ('compiled','lazy'):
        log=(root/f'probe-{dst}-{mode}.log').read_text()
        assert (root/f'probe-{dst}-{mode}.out').read_text()=='101\n'
        rows=re.findall(r'RUNTIME pc=(\d+) virtual=(\d+).* A=([^\n]*) B=([^\n]*)',log)
        assert len(rows)==10,(dst,mode,len(rows))
        for pc,n,aa,bb in rows:
            n=int(n)
            expected_a='111,333,555' if n==2 else '333,555' if n==1 else '555'
            expected_b='222,444,666' if n==2 else '444,666' if n==1 else '666'
            assert aa==expected_a and bb==expected_b,(n,aa,bb)
        nested=len([r for r in rows if r[1]=='2'])
        moved=[int(n) for n in re.findall(r'INSERTION_COUNTEREXAMPLE moved_roots=(\d+)',log)]
        assert nested and max(moved)==2
        report['instrumented'].append({'destination':dst,'mode':mode,'runtime_snapshots':len(rows),'nested_virtual_snapshots':nested,'snapshots_with_moved_roots':sum(n>0 for n in moved),'max_moved_roots':max(moved)})
    for stack in range(1,33):
        outcomes=[]
        for mode in ('interpreted','compiled','lazy'):
            p=subprocess.run([str(root/'baseline-runtime'),'run',str(root/f'layout-{dst}.abc'),'main',f'--{mode}',f'--stack={stack}'],text=True,capture_output=True)
            status='ok' if p.returncode==0 else 'stack' if 'abc: stack' in p.stderr else 'other'
            assert status!='other',(stack,dst,mode,p.stderr)
            outcomes.append({'mode':mode,'status':status,'diagnostic':p.stderr.strip(),'output':p.stdout.strip()})
        report['stack_sweep'].append({'destination':dst,'stack':stack,'status_agreement':len({o['status'] for o in outcomes})==1,'outcomes':outcomes})
(root/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print('baseline:',len(report['baseline']),'successful executions')
print('instrumented:',report['instrumented'])
print('stack-sweep:',len(report['stack_sweep'])*3,'executions;',sum(not r['status_agreement'] for r in report['stack_sweep']),'status disagreements')
for dst in ('A','B'):
    rows=[r for r in report['stack_sweep'] if r['destination']==dst]
    print(dst,'first successful stack capacities:',{m:next((r['stack'] for r in rows if next(o for o in r['outcomes'] if o['mode']==m)['status']=='ok'),None) for m in ('interpreted','compiled','lazy')})
