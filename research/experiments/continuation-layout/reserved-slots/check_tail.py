from pathlib import Path
import subprocess, os, json
root=Path(__file__).parent
results=[]
for dst in ('A','B'):
    pc=(root/f'tail-{dst}.pc').read_text().strip()
    for config in ('original','reserved','transfer'):
        for mode in ('interpreted','compiled','lazy'):
            env=dict(os.environ);env.pop('ABC_RESERVED_PROBE_PC',None);env.pop('ABC_RESERVED_TRACE',None)
            if config=='transfer':env.update(ABC_RESERVED_PROBE_PC=pc,ABC_RESERVED_TRACE='1')
            runner=root/('original-runtime' if config=='original' else 'build/abc-runtime')
            p=subprocess.run([str(runner),'run',str(root/f'tail-{dst}.abc'),'main',f'--{mode}','--stack=1024'],env=env,text=True,capture_output=True,timeout=10)
            failure=config=='transfer' and mode!='interpreted'
            if failure:
                assert p.returncode==1 and 'language abort 12' in p.stderr,p.stderr
                assert 'versions_at_pc=2' in p.stderr,p.stderr
                assert p.stderr.count('GENERAL_ENTRY ')==(7 if mode=='compiled' else 8),p.stderr
            else:assert p.returncode==0 and p.stdout=='101\n',p.stderr
            results.append({'destination':dst,'config':config,'mode':mode,'status':p.returncode,'output':p.stdout.strip(),'diagnostic':next((s for s in p.stderr.splitlines() if s.startswith('abc:')),''),'expected_counterexample':failure,'general_entries':p.stderr.count('GENERAL_ENTRY '),'materialized_returns':p.stderr.count('MATERIALIZED_RETURN ')})
            (root/f'checked-tail-{dst}-{config}-{mode}.log').write_text(p.stderr)
(root/'tail-results.json').write_text(json.dumps(results,indent=2)+'\n')
print('18 executions: 14 successful controls; 4 reproduced native forced-transfer failures (NOT passing semantic cases).')
