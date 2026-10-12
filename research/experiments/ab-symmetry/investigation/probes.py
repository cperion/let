#!/usr/bin/env python3
"""Investigation only: generate independent old/new assembly probes, no ISA adapter."""
import csv, json, os, statistics, subprocess
from pathlib import Path

here=Path(__file__).resolve().parent
root=here.parents[3]
old_tools=Path('/tmp/abc-r6-investigate/old-build/abc')
old_runner=Path('/tmp/abc-before-ab-symmetry.tdOxjk/performance/runlet')
new_runner=here.parent/'final-comparison/runlet'
env=dict(os.environ);env.pop('ABC_DUMP_NATIVE',None)

def assemble(name,old,new):
    for version,text,tool in [('old',old,old_tools),('new',new,root/'build/abc')]:
        source=here/f'{version}-{name}.abcasm';source.write_text(text)
        subprocess.run(['/tmp/lua-compat',str(tool),'asm',str(source),'-o',str(here/f'{version}-{name}.abc')],check=True,cwd=root)

# Make the counter unknown to native compilation by reading writable image state.
for version in ('old','new'):
    source=(here.parent/('memory.abcasm' if version=='old' else 'final-comparison/memory.abcasm')).read_text()
    suffix='' if version=='old' else '.A'
    source=source.replace('.datazero 8','.datazero 16').replace('    PUSH.A 1000000\n    CPUSH.A',
        f'    PUSH.A 1000000\n    GST64{suffix} 8\n    GLD64{suffix} 8\n    CPUSH.A')
    if version=='old': old_memory=source
    else: new_memory=source
assemble('memory-runtime-counter',old_memory,new_memory)

# A tight loop with identical semantic work, with or without a leaf call.
# Every result is compared with 42; a wrong result aborts before timing succeeds.
cases=[]
for arity in (0,1,2):
    for call in (False,True):
        name=f'leaf{arity}-'+('call' if call else 'inline');texts=[]
        for version in ('old','new'):
            selected=version=='new';ret='RET.A' if selected else 'RET'
            beqi='BEQI.A' if selected else 'BEQI';bne='BNE.A' if selected else 'BNE'
            args=['','PUSH.A 41','PUSH.A 40\nPUSH.A 2'][arity]
            inline=['PUSH.A 42','ADDI.A 1',('MOVE.A' if selected else 'MOVE_AB')+'\nADD.A'][arity]
            leaf=['PUSH.A 42','CGET.A 0\nADDI.A 1','CGET.A 0\nCGET.B 1\nADD.A'][arity]
            action=f'CALL.A leaf {arity}' if call else inline
            text=f'''.function main 0 1
PUSH.A 1000000
CPUSH.A
loop:
CGET.A 0
{beqi} 0 done
{args}
{action}
PUSH.B 42
{bne} fail
CGET.A 0
SUBI.A 1
CSET.A 0
JMP loop
fail:
ABORT 5
done:
CPOP
PUSH.A 42
{ret} 0 1
'''
            if call:text+=f'.function leaf {arity} 1\n{leaf}\n{ret} {arity} 1\n'
            texts.append(text+'.export main\n')
        assemble(name,*texts);cases.append(name)

rows=[]
with (here/'leaf-raw.jsonl').open('x') as raw,(here/'leaf-timings.csv').open('x',newline='') as output:
    writer=csv.writer(output);writer.writerow(['round','case','version','result','steady_s','read_s','prepare_s','native_bytes','first_s'])
    for round_ in range(6):
        order=cases[round_:]+cases[:round_]
        for index,name in enumerate(order):
            versions=('old','new') if (round_+index)%2==0 else ('new','old')
            for version in versions:
                runner=old_runner if version=='old' else new_runner
                command=['taskset','-c','0',str(runner),'interpreted',str(here/f'{version}-{name}.abc'),'7']
                result=subprocess.run(command,capture_output=True,text=True,env=env)
                raw.write(json.dumps({'command':command,'status':result.returncode,'stdout':result.stdout,'stderr':result.stderr})+'\n');raw.flush()
                fields=result.stdout.split();assert result.returncode==0 and len(fields)==6 and fields[0]=='42',(command,result)
                writer.writerow([round_,name,version]+fields);output.flush()
                rows.append((round_,name,version,float(fields[1])))
for arity in (0,1,2):
    for version in ('old','new'):
        medians={kind:statistics.median(t for _,name,v,t in rows if name==f'leaf{arity}-{kind}' and v==version) for kind in ('call','inline')}
        # One million iterations: seconds become microseconds total / 1e6 = seconds per iteration;
        # multiplying total seconds by 1000 gives ns/iteration.
        print(f"arity={arity} {version}: inline={medians['inline']*1000:.3f} ns/iteration call={medians['call']*1000:.3f} ns/iteration increment={(medians['call']-medians['inline'])*1000:.3f} ns/iteration")
