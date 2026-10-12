#!/usr/bin/env python3
"""Short existing-policy pilot; not a full region-budget/performance study."""
from pathlib import Path
import json,subprocess,statistics
here=Path(__file__).resolve().parent
root=here.parents[3]
build=Path((here/'build-root.txt').read_text().strip())
programs=here/'programs';programs.mkdir(exist_ok=True)
cases={}
for sites,inner in [(8,1),(32,1),(8,4)]:
    name=f'calls-{sites}x{inner}'
    target='helper' if inner==1 else 'middle'
    text='.function main 0 1\nPUSH.A 0\nPUSH.B 100000\nCPUSH.B\nloop:\n'
    text+=f'CALL.A {target} 1\n'*sites
    text+='CGET.B 0\nSUBI.B 1\nCSET.B 0\nCGET.B 0\nBNEI.B 0 loop\nRET.A 1 1\n'
    if inner>1:
        text+='.function middle 1 1\nCGET.A 0\n'+'CALL.A helper 1\n'*inner+'RET.A 1 1\n'
    text+='.function helper 1 1\nCGET.B 0\nADDI.B 1\nRET.B 1 1\n.export main\n'
    source=programs/(name+'.abcasm');module=programs/(name+'.abc');source.write_text(text)
    subprocess.run([str(root/'build/abc'),'asm',str(source),'-o',str(module)],check=True)
    cases[name]=(module,sites*inner*100000)
for name,value in [('fib',832040),('loop',3180325737),('branch',7015924),('memory',1000000)]:
    cases[name]=(root/'research/experiments/ab-symmetry/backedge-placement'/(name+'.abc'),value)
rows=[]
with (here/'quick-raw.jsonl').open('x') as raw:
    for round_ in range(3):
        ordered=list(cases);ordered=ordered[round_:]+ordered[:round_]
        for index,name in enumerate(ordered):
            path,expected=cases[name]
            for mode in ['compiled','lazy']:
                limits=[8,16,32];rotation=(round_+index)%3;limits=limits[rotation:]+limits[:rotation]
                for limit in limits:
                    command=['taskset','-c','0',str(build/str(limit)/'runlet'),mode,str(path),'3']
                    result=subprocess.run(command,capture_output=True,text=True,timeout=20)
                    record=dict(round=round_,name=name,mode=mode,limit=limit,command=command,status=result.returncode,stdout=result.stdout,stderr=result.stderr)
                    raw.write(json.dumps(record)+'\n');raw.flush()
                    assert result.returncode==0,record
                    fields=result.stdout.split();assert len(fields)==6 and int(fields[0])==expected,record
                    record.update(seconds=float(fields[1]),prepare=float(fields[3]),bytes=int(fields[4]),first=float(fields[5]))
                    rows.append(record)
summary=[]
for name in cases:
    for mode in ['compiled','lazy']:
        groups={n:[r for r in rows if (r['name'],r['mode'],r['limit'])==(name,mode,n)] for n in [8,16,32]}
        entry=dict(name=name,mode=mode,measurements={})
        for n in [8,16,32]:
            ratios=[r['seconds']/groups[8][i]['seconds'] for i,r in enumerate(groups[n])]
            entry['measurements'][n]=dict(ms=statistics.median(r['seconds'] for r in groups[n])*1000,
                ratio=statistics.median(ratios),range=[min(ratios),max(ratios)],
                bytes=sorted({r['bytes'] for r in groups[n]}),
                prepare_ms=statistics.median(r['prepare'] for r in groups[n])*1000,
                first_ms=statistics.median(r['first'] for r in groups[n])*1000)
        summary.append(entry)
        print(name,mode,' | '.join(f"{n}: {entry['measurements'][n]['ms']:.3f} ms, {entry['measurements'][n]['ratio']:.3f}x, {entry['measurements'][n]['bytes']} B" for n in [8,16,32]))
(here/'quick-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
