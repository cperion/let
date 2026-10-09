#!/usr/bin/env python3
"""Inspect native cycles and independently count runtime helpers with GDB."""
import os, pathlib, re, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[3];out=root/'build/type-version-bench'
current=root/'research/experiments/engines/runlet';baseline=pathlib.Path(sys.argv[1])
sys.setrecursionlimit(20000)
def execute(args,**kwargs):
    return subprocess.run(list(map(str,args)),capture_output=True,text=True,check=True,timeout=60,**kwargs)
def cycles(asm):
    ins={}
    for line in asm.splitlines():
        m=re.match(r'^\s*([0-9a-f]+):\s+([a-z][a-z0-9.]*)\s*(.*)$',line)
        if m:ins[int(m[1],16)]=(m[2],m[3],line)
    addresses=sorted(ins);graph={a:[] for a in addresses};reverse={a:[] for a in addresses}
    for i,a in enumerate(addresses):
        op,args,_=ins[a]
        if op.startswith('j'):
            m=re.match(r'(?:0x)?([0-9a-f]+)(?:\s|$)',args)
            if m and int(m[1],16) in graph:graph[a].append(int(m[1],16))
        if op not in ('jmp','ret','retq') and i+1<len(addresses):graph[a].append(addresses[i+1])
        for b in graph[a]:reverse[b].append(a)
    seen=set();finish=[]
    def visit(a):
        if a in seen:return
        seen.add(a)
        for b in graph[a]:visit(b)
        finish.append(a)
    for a in addresses:visit(a)
    seen.clear();components=[]
    def collect(a,comp):
        if a in seen:return
        seen.add(a);comp.append(a)
        for b in reverse[a]:collect(b,comp)
    for a in reversed(finish):
        if a not in seen:
            comp=[];collect(a,comp)
            if len(comp)>1 or a in graph[a]:components.append(sorted(comp))
    return ins,components
for name in ('u32','source','u8'):
    for mode in ('compiled','lazy'):
        for variant,exe in [('baseline',baseline),('current',current)]:
            stem=f'{name}-{mode}-{variant}';binary=out/(stem+'.bin')
            p=execute([exe,mode,out/(name+'.abc'),'3'],env=dict(os.environ,ABC_DUMP_NATIVE=str(binary)))
            (out/(stem+'.trace')).write_text(p.stderr)
            asm=execute(['objdump','--no-show-raw-insn','-D','-b','binary','-m','i386:x86-64',binary]).stdout
            (out/(stem+'.asm')).write_text(asm);ins,components=cycles(asm)
            print(stem,'bytes',binary.stat().st_size)
            if mode=='lazy':print('  body-only dump: distant activation stubs are omitted')
            for comp in components:
                calls=sum(ins[a][0].startswith('call') for a in comp)
                print(f'  {comp[0]:x}..{comp[-1]:x}: {len(comp)} instructions, {calls} call sites')
                if not calls:print('\n'.join(ins[a][2] for a in comp))
commands='set pagination off\nset confirm off\n'
for var,func in [('dyn','vm_dynamic_native'),('classify','abc_dynamic_numeric_classify'),('decode','abc_dynamic_numeric_bits')]:
    commands+=f'set ${var}=0\nbreak {func}\ncommands\nsilent\nset ${var}=${var}+1\ncontinue\nend\n'
commands+='run\nprintf "HELPERS %d %d %d\\n", $dyn, $classify, $decode\n'
cmd=out/'count.gdb';cmd.write_text(commands)
for name,mode in [('u32','compiled'),('u32','lazy'),('source','compiled'),('source','lazy'),('u8','lazy')]:
    counts=[]
    for n in (200,1000000):
        if name=='source':
            src=out/f'count-{name}-{n}.let';src.write_text((out/'source.let').read_text().replace('1000000',str(n)));command='compile'
        else:
            src=out/f'count-{name}-{n}.abcasm';src.write_text((out/(name+'.abcasm')).read_text().replace('1000000',str(n)));command='asm'
        module=src.with_suffix('.abc');execute([root/'build/abc',command,src,'-o',module])
        p=execute(['gdb','-q','-batch','-x',cmd,'--args',current,mode,module,'3'])
        (out/f'count-{name}-{mode}-{n}.log').write_text(p.stdout+p.stderr)
        match=re.search(r'HELPERS (\d+) (\d+) (\d+)',p.stdout);assert match,p.stdout
        count=tuple(map(int,match.groups()));counts.append(count)
        print(name,mode,n,'four calls: dynamic/classifier/decoder',count,flush=True)
    assert counts[0]==counts[1],(name,mode,counts)

