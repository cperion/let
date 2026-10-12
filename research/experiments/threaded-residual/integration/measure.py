#!/usr/bin/env python3
"""Short four-mode pilot. Run after building runlet; never overwrite raw data."""
from pathlib import Path
import subprocess,json,statistics,sys
here=Path(__file__).resolve().parent
root=here.parents[3]
out=Path(sys.argv[1]) if len(sys.argv)>1 else here
runner=Path(sys.argv[2]) if len(sys.argv)>2 else here/'runlet'
out.mkdir(parents=True,exist_ok=True)
cases={'loop':3180325737,'branch':7015924,'fib':832040,'memory':1000000}
modes=['off','threaded','lazy','eager'];rows=[]
with (out/'four-mode-raw.jsonl').open('x') as raw:
 for round_ in range(4):
  names=list(cases);names=names[round_:]+names[:round_]
  for index,name in enumerate(names):
   rotation=(2*round_+index)%4;order=modes[rotation:]+modes[:rotation]
   for mode in order:
    command=['taskset','-c','0',str(runner),mode,str(root/'research/experiments/ab-symmetry/backedge-placement'/(name+'.abc')),str(cases[name])]
    p=subprocess.run(command,capture_output=True,text=True,timeout=30)
    row=dict(round=round_,name=name,mode=mode,command=command,status=p.returncode,stdout=p.stdout,stderr=p.stderr)
    raw.write(json.dumps(row)+'\n');raw.flush();assert p.returncode==0,row
    values=p.stdout.split();assert len(values)==7,row
    row.update(zip(['read','prepare','first','steady'],map(float,values[:4])))
    row.update(zip(['body_bytes','storage_bytes','versions'],map(int,values[4:])))
    rows.append(row)
for name in cases:
 first=[next(r['mode'] for r in rows if r['name']==name and r['round']==round_) for round_ in range(4)]
 assert set(first)==set(modes),(name,first)
summary=[]
for name in cases:
 groups={m:[r for r in rows if r['name']==name and r['mode']==m] for m in modes}
 measurements={}
 for mode in modes:
  ratios=[r['steady']/groups['off'][i]['steady'] for i,r in enumerate(groups[mode])]
  measurements[mode]={k:statistics.median(r[k] for r in groups[mode]) for k in ['read','prepare','first','steady','body_bytes','storage_bytes','versions']}
  measurements[mode].update(ratio_to_off=statistics.median(ratios),ratio_range=[min(ratios),max(ratios)])
 summary.append(dict(name=name,measurements=measurements))
 print(name,' | '.join(f"{m}: {measurements[m]['steady']*1000:.3f}ms ({measurements[m]['ratio_to_off']:.3f}x off), {measurements[m]['body_bytes']:g}B" for m in modes))
(out/'four-mode-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
