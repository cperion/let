#!/usr/bin/env python3
"""Focused repeat; unchanged bytecode and runners, independent raw output."""
import csv,json,os,statistics,subprocess
from pathlib import Path
here=Path(__file__).resolve().parent
before=here.parent/'final-comparison'
env=dict(os.environ);env.pop('ABC_DUMP_NATIVE',None)
rows=[]
with (here/'fib-followup.jsonl').open('x') as raw:
    for round_ in range(8):
        modes=['interpreted','compiled','lazy']
        modes=modes[round_%3:]+modes[:round_%3]
        for index,mode in enumerate(modes):
            for version in (('before','after') if (round_+index)%2==0 else ('after','before')):
                directory=before if version=='before' else here
                command=['taskset','-c','0',str(directory/'runlet'),mode,str(directory/'fib.abc'),'7']
                result=subprocess.run(command,capture_output=True,text=True,env=env)
                values=result.stdout.split()
                raw.write(json.dumps({'round':round_,'mode':mode,'version':version,'command':command,
                                      'status':result.returncode,'stdout':result.stdout,'stderr':result.stderr})+'\n');raw.flush()
                assert result.returncode==0 and len(values)==6 and values[0]=='832040',(command,result)
                rows.append((round_,mode,version,float(values[1])))
with (here/'fib-followup.csv').open('x',newline='') as file:
    writer=csv.writer(file);writer.writerow(['round','mode','version','median_seconds']);writer.writerows(rows)
for mode in ['interpreted','compiled','lazy']:
    def time(round_,version):return next(t for r,m,v,t in rows if (r,m,v)==(round_,mode,version))
    ratios=[time(r,'after')/time(r,'before') for r in range(8)]
    print(f'{mode}: paired after/before median {statistics.median(ratios):.3f}, range [{min(ratios):.3f},{max(ratios):.3f}]')
