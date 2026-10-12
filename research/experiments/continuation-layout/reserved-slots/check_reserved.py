from pathlib import Path
import subprocess, os, re, json
root=Path(__file__).parent
summary={'ample_stack':[], 'sweeps':[], 'limits':[
    'Forced interior edge, not the production eight-version policy.',
    'Return adapters are experimental emitted code, not a validated bounded continuation design.',
    'Typed fixtures only; no GC/dynamic validation or performance claims.',
    'This checker covers fixed arity; check_tail.py separately reproduces argument-count-changing tail failures.']}
for fixture in ('layout','alias'):
    for dst in ('A','B'):
        for config in ('original','reserved','transfer'):
            runner=root/('original-runtime' if config=='original' else 'build/abc-runtime')
            env=dict(os.environ)
            env.pop('ABC_RESERVED_PROBE_PC',None)
            if config=='transfer':env['ABC_RESERVED_PROBE_PC']='0x319'
            first={m:None for m in ('interpreted','compiled','lazy')}
            disagreements=[];diagnostic_disagreements=[]
            for capacity in list(range(1,33))+[1024]:
                outcomes=[]
                for mode in ('interpreted','compiled','lazy'):
                    p=subprocess.run([str(runner),'run',str(root/f'{fixture}-{dst}.abc'),'main',f'--{mode}',f'--stack={capacity}'],env=env,text=True,capture_output=True)
                    status='ok' if p.returncode==0 else 'stack' if 'abc: stack-limit' in p.stderr else 'other'
                    assert status!='other',(fixture,dst,config,capacity,mode,p.returncode,p.stderr)
                    if status=='ok':
                        assert p.stdout=='101\n',(fixture,dst,config,capacity,mode,p.stdout)
                        if first[mode] is None:first[mode]=capacity
                    diagnostic=next((s for s in p.stderr.splitlines() if s.startswith('abc:')),'')
                    outcomes.append({'mode':mode,'status':status,'diagnostic':diagnostic})
                    if capacity==1024:
                        item={'fixture':fixture,'destination':dst,'config':config,'mode':mode,'result':101}
                        if config=='transfer' and mode!='interpreted':
                            item.update(activations=p.stderr.count('ACTIVATION '),general_entries=p.stderr.count('GENERAL_ENTRY '),materialized_returns=p.stderr.count('MATERIALIZED_RETURN '),materializations=p.stderr.count('MATERIALIZE '))
                            assert item['activations']==10 and item['general_entries']==10 and item['materialized_returns']>0,item
                            assert set(re.findall(r'general_versions_at_pc=(\d+)',p.stderr))=={'1'},p.stderr
                        summary['ample_stack'].append(item)
                        (root/f'checked-{fixture}-{dst}-{config}-{mode}.log').write_text(p.stderr)
                if len({r['status'] for r in outcomes})>1:disagreements.append({'capacity':capacity,'outcomes':outcomes})
                elif outcomes[0]['status']=='stack' and len({r['diagnostic'] for r in outcomes})>1:diagnostic_disagreements.append({'capacity':capacity,'outcomes':outcomes})
            row={'fixture':fixture,'destination':dst,'config':config,'first_successful_capacity':first,'status_disagreements':disagreements,'stack_diagnostic_disagreements':diagnostic_disagreements}
            summary['sweeps'].append(row)
            if config!='original':assert not disagreements,row
summary['executions']=len(summary['sweeps'])*33*3
(root/'reserved-results.json').write_text(json.dumps(summary,indent=2)+'\n')
print('executions:',summary['executions'],'ample-stack:',len(summary['ample_stack']))
for row in summary['sweeps']:
    print(row['fixture'],row['destination'],row['config'],'first-success:',row['first_successful_capacity'],'status-disagreements:',len(row['status_disagreements']),'diagnostic-disagreements:',len(row['stack_diagnostic_disagreements']))
for item in summary['ample_stack']:
    if 'materializations' in item:print(item)
