#!/usr/bin/env python3
"""Pre-tooling checkpoint: identical revision-6 modules in all runtime modes."""
import hashlib,json,random,statistics,subprocess,sys
from pathlib import Path
runner=Path(sys.argv[1]).resolve(); programs=Path(sys.argv[2]).resolve(); output=Path(sys.argv[3]).resolve()
rounds=int(sys.argv[4]) if len(sys.argv)>4 else 6
modes=['interpreted','compiled','lazy']; workloads=[]
for row in (programs/'workloads.tsv').read_text().splitlines():
    name,expected,kind=row.split('\t')
    if kind=='bench':workloads.append((name,int(expected)))
records=[]; rng=random.Random(20260810)
for iteration in range(rounds):
    order=workloads.copy();rng.shuffle(order)
    for name,expected in order:
        # Rotate mode order; six rounds put each mode in each position twice.
        shift=iteration%3
        for mode in modes[shift:]+modes[:shift]:
            command=['taskset','-c','0',str(runner),mode,str(programs/(name+'.abc')),'7']
            proc=subprocess.run(command,text=True,capture_output=True,timeout=60)
            record=dict(round=iteration,workload=name,mode=mode,returncode=proc.returncode,stdout=proc.stdout,stderr=proc.stderr)
            if proc.returncode==0:
                parts=proc.stdout.split();value=int(parts[0]);assert value==expected,(name,mode,value,expected)
                record.update(result=value,steady=float(parts[1]),read=float(parts[2]),prepare=float(parts[3]),
                              native_bytes=int(parts[4]),warmup=float(parts[5]),samples=list(map(float,parts[6:])))
            records.append(record);(output/'timings.json').write_text(json.dumps(records,indent=2)+'\n')
lines=['workload mode steady_ms prepare_ms first_call_ms native_bytes round_median_min_ms round_median_max_ms']
for name,_ in workloads:
    for mode in modes:
        rows=[r for r in records if r['workload']==name and r['mode']==mode]
        if any(r['returncode'] for r in rows):
            errors=sorted({r['stderr'].strip() for r in rows if r['returncode']})
            lines.append(f'{name} {mode} FAILED '+repr(errors));continue
        steady=statistics.median([s for r in rows for s in r['samples']])
        prepare=statistics.median(r['prepare'] for r in rows)
        warmup=statistics.median(r['warmup'] for r in rows)
        sizes={r['native_bytes'] for r in rows};assert len(sizes)==1,(name,mode,sizes)
        lines.append(f'{name} {mode} {steady*1000:.3f} {prepare*1000:.3f} {warmup*1000:.3f} {sizes.pop()} '
                     f'{min(r["steady"] for r in rows)*1000:.3f} {max(r["steady"] for r in rows)*1000:.3f}')
text='\n'.join(lines)+'\n';print(text,end='');(output/'summary.txt').write_text(text)
checksums={str(runner):hashlib.sha256(runner.read_bytes()).hexdigest()}
checksums.update({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in programs.glob('*.abc')})
(output/'artifact-sha256.json').write_text(json.dumps(checksums,indent=2)+'\n')
