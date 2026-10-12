#!/usr/bin/env python3
"""Counterbalanced, CPU-pinned real-interpreter comparisons; preserves raw samples."""
import json, random, statistics, subprocess, sys
from pathlib import Path
root=Path(sys.argv[1]); rounds=int(sys.argv[2]) if len(sys.argv)>2 else 6
workloads=[]
for line in (root/'programs/workloads.tsv').read_text().splitlines():
    name,expected,kind=line.split('\t')
    if kind=='bench': workloads.append((name,int(expected)))
records=[]; rng=random.Random(20260809)
for round_index in range(rounds):
    order=workloads.copy();rng.shuffle(order)
    for index,(name,expected) in enumerate(order):
        modes=['current','eager'] if (round_index+workloads.index((name,expected)))%2==0 else ['eager','current']
        for mode in modes:
            command=['taskset','-c','0',str(root/mode/'build/c-cache-bench'),str(root/'programs'/f'{name}.abc'),'7']
            output=subprocess.check_output(command,text=True).split()
            assert int(output[0])==expected,(name,mode,output)
            record=dict(round=round_index,workload=name,mode=mode,result=int(output[0]),
                        prepare=float(output[1]),warmup=float(output[2]),samples=list(map(float,output[3:])))
            records.append(record)
            (root/'timings.json').write_text(json.dumps(records,indent=2)+'\n')
lines=['workload current_ms eager_ms eager/current paired_ratio_min paired_ratio_max']
for name,_ in workloads:
    per={mode:[r for r in records if r['workload']==name and r['mode']==mode] for mode in ['current','eager']}
    current=statistics.median([s for r in per['current'] for s in r['samples']])
    eager=statistics.median([s for r in per['eager'] for s in r['samples']])
    paired=[]
    for i in range(rounds):
        c=next(r for r in per['current'] if r['round']==i)
        e=next(r for r in per['eager'] if r['round']==i)
        paired.append(statistics.median(e['samples'])/statistics.median(c['samples']))
    lines.append(f'{name} {current*1000:.3f} {eager*1000:.3f} {eager/current:.4f} {min(paired):.4f} {max(paired):.4f}')
text='\n'.join(lines)+'\n';print(text,end='');(root/'summary.txt').write_text(text)
