#!/usr/bin/env python3
"""Paired production-vs-pristine measurements on identical, ordinary ABC."""
import json, os, pathlib, re, statistics, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[3]
out=root/'build/type-version-bench';out.mkdir(parents=True,exist_ok=True)
abc=root/'build/abc';current=root/'research/experiments/engines/runlet'
baseline=pathlib.Path(sys.argv[1]);rounds=int(sys.argv[2]) if len(sys.argv)>2 else 5
perf=os.environ.get('ABC_BENCH_PERF')=='1'
def run(args,env=None):
    p=subprocess.run(list(map(str,args)),env=env,text=True,capture_output=True,timeout=60)
    assert p.returncode==0,(args,p.stdout,p.stderr)
    return p.stdout
cases=[]
for name,typ,initial,n in [('u8','u8',0,1000000),('u16','u16',0,1000000),('u32','u32',0,1000000),('i32','i32',0,1000000),('u64','u64',0,1000000),('i64','i64',0,1000000),('f64','f64',0,1000000),('heap-u64','u64',1<<63,100000)]:
    cast=' I2FU\n' if typ=='f64' else ''
    text=f'''.profile dynamic
.descriptor primitive T {typ}
.descriptor primitive W u64
.descriptor primitive D any
.datazero 8
.gcroot 0 D
.function main 0 1 - i
 PUSH64.A {initial}
{cast} ANY_BOX T
 GST64 0
 .loadkind any
 GLD64 0
 CPUSH.A
 PUSH.A 0
 CPUSH.A
loop:
 CGET0.A
 PUSH32.B {n}
 BLTU body
 CGET1.A
 ANY_CAST W
 RET 2 1
body:
 CGET1.A
 PUSH.A 1
{cast} ANY_BOX T
 DADD
 CSET.A 1
 CGET0.A
 ADDI.A 1
 CSET.A 0
 JMP loop
.export main
'''
    src=out/(name+'.abcasm');src.write_text(text);binary=src.with_suffix('.abc')
    run([abc,'asm',src,'-o',binary]);expected=(initial+n)%(1<<{'u8':8,'u16':16,'u32':32,'i32':32}.get(typ,64))
    cases.append((name,binary,n,expected))
source=out/'source.let'
source.write_text('''let loop(n: u32, x: any): any = do
  if n == 0 then return x end
  return loop(n - 1, x + any(u32(1)))
end
let main(): u32 = u32(loop(1000000, any(u32(0))))
''')
binary=source.with_suffix('.abc');run([abc,'compile',source,'-o',binary])
cases.append(('source-any',binary,1000000,1000000))
# Optional existing whole-engine fixtures (generate with run_bench.lua first).
for name,n in [('loop',5000000),('skip',3000000),('branch',3000000),('sum2',3000000),('mul',3000000),('divide',1000000),('mix',2000000),('fib',2692537)]:
    binary=root/'research/experiments/engines'/(name+'.abc')
    if binary.exists():
        expected=int(run(['taskset','-c','0',baseline,'interpreted',binary,'3']).split()[0])
        cases.append(('typed-'+name,binary,n,expected))
rows=[]
for round in range(rounds):
    order=[('baseline',baseline),('current',current)]
    if round%2:order.reverse()
    for name,binary,units,expected in cases:
        for mode in ('interpreted','compiled','lazy'):
            for variant,exe in order:
                command=['taskset','-c','0',str(exe),mode,str(binary),'5'];counters={}
                if perf:
                    p=subprocess.run(['perf','stat','-x,','-e','cycles,instructions']+command,env=dict(os.environ,LC_ALL='C'),text=True,capture_output=True,check=True,timeout=60)
                    fields=p.stdout.split()
                    for event in ('cycles','instructions'):
                        match=re.search(r'^(\d+),,'+event,p.stderr,re.M);assert match,p.stderr;counters[event]=int(match[1])
                else:fields=run(command).split()
                assert int(fields[0])==expected,(name,variant,mode,fields,expected)
                rows.append(dict(round=round,name=name,mode=mode,variant=variant,ns=float(fields[1])*1e9/units,bytes=int(fields[4]),prepare=float(fields[3]),**counters))
    print(f'round {round+1}/{rounds}',flush=True)
(out/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
print('case mode baseline-ns current-ns ratio baseline-B current-B')
for name,_,_,_ in cases:
    for mode in ('interpreted','compiled','lazy'):
        groups=[[r for r in rows if (r['name'],r['mode'],r['variant'])==(name,mode,v)] for v in ('baseline','current')]
        a,b=[statistics.median([r['ns'] for r in group]) for group in groups]
        extra=''
        if perf:
            ca,cb=[statistics.median(r['cycles'] for r in group) for group in groups];extra=f'cycles-ratio={cb/ca:.3f}'
        print(name,mode,f'{a:.3f}',f'{b:.3f}',f'{b/a:.3f}',groups[0][0]['bytes'],groups[1][0]['bytes'],extra)

