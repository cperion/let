#!/usr/bin/env python3
"""Execute generated typed fixtures against the real I/E/L engines.
Each jump is also tested with the existing general-home conformance forced there.
No new runtime transport or return convention is used.
"""
import json, os, pathlib, re, subprocess
ROOT = pathlib.Path(__file__).resolve().parent
os.chdir(ROOT)
OUT = ROOT / 'capture-cases'
OUT.mkdir(exist_ok=True)
ARGS = [101 + 17*i for i in range(12)]
ARGS[4] = 0x8765432101234567
ARGS[9] = 0xffffffffffffffff
cases = []
def add(name, body, expected, nargs=12, extra='', args=None):
    cases.append((name, f'.profile memory\n.function main {nargs} {len(expected)} '+('i'*nargs or '-')+' '+('i'*len(expected) or '-')+'\n'+'\n'.join(body)+f'\nRET {nargs} {len(expected)}\n'+extra+'\n.export main\n', expected, ARGS[:nargs] if args is None else args))
def gets(s, n=12): return [f'CGETR.{s} 0 {n}']
def drops(s, n=12): return [f'DROP.{s}']*n
for s, other in [('A','B'),('B','A')]:
    body=gets(s)
    for i in range(12): body += [f'PUSH.{other} {900+i}',f'CSET.{other} {i}']
    body += ['JMP end','end:']
    if s=='B': body += ['MOVE.BA']*12
    add('replace-C-'+s, body, ARGS if s=='A' else ARGS[::-1])
    body=gets(s)+['JMP homes','homes:']
    body += [f'CSET.{s} {i}' for i in range(12)]
    body += [f'PUSH.{s} {900+i}' for i in range(12)]
    body += ['JMP reused','reused:']+drops(s)+gets('A')
    add('cset-memory-'+s,body,ARGS[::-1])
    for op in ['MOVE','COPY','DUP']:
        body=gets(s)+['JMP homes','homes:']
        if op=='DUP': body += [f'DUP.{s}',f'MOVE.{s}{other}']
        else: body += [f'{op}.{s}{other}']
        if op!='MOVE': body += [f'DROP.{s}']
        body += [f'PUSH.{s} 900','JMP reused','reused:']+drops(s)
        if other=='B': body += ['MOVE.BA']
        add(op.lower()+'-memory-'+s,body,[ARGS[-1]])
    body=[f'CGET.{s} 0','JMP homes','homes:',f'CPUSH.{s}',f'PUSH.{s} 901','JMP reused','reused:',f'CGET.{s} 0','CPOP']
    if s=='B':body+=['MOVE.BA']*2
    add('cpush-memory-'+s,body,[901,ARGS[0]] if s=='A' else [ARGS[0],901])
    body=[]
    for i in range(10):
        body+=gets('A')+[f'ADDI.A {i}',f'CALL.{s} echo 12']
        if i<9:body+=drops(s)
    body+=['JMP end','end:']
    if s=='B':body+=['MOVE.BA']*12
    expected=ARGS[:-1]+[ARGS[-1]+9]
    add('wide-calls-'+s,body,expected if s=='A' else expected[::-1],extra='.function echo 12 12 '+ 'i'*12+' '+ 'i'*12+'\nCGETR.A 0 12\nRET 12 12')
add('cpushn-memory', gets('A')+['JMP homes','homes:','CPUSHN 12','PUSH.A 901','JMP reused','reused:']+gets('A')+['CPOP']*12, [901]+ARGS)
# Grow and shrink argument areas without changing the return convention.
for n in [9,13]:
    body=gets('A', min(n,12))
    if n==13:body+=['PUSH.A 123']
    body+=[f'TCALL echo 12 {n}']
    # add()'s RET is unreachable; assembler/verifier accept only reachable states.
    extra=f'.function echo {n} {n} '+ 'i'*n+' '+ 'i'*n+'\nJMP end\nend:\nCGETR.A 0 '+str(n)+f'\nRET {n} {n}'
    expected=ARGS[:n] if n==9 else ARGS+[123]
    add('wide-tail-'+str(n),body,expected,extra=extra)
# Captured B operand must remain live while a constant A operand is materialized.
add('branch-capture', ['PUSH.A 101','CGET.B 0','BEQ equal','PUSH.A 42','JMP end','equal:','PUSH.A 99','end:'], [42],nargs=1,args=[102])
rows=[]
for name, text, expected, args in cases:
    asm=OUT/(name+'.abcasm'); module=OUT/(name+'.abc');asm.write_text(text)
    p=subprocess.run(['build/abc','asm',str(asm),'-o',str(module)],text=True,capture_output=True)
    if p.returncode: raise RuntimeError(name+' assembly: '+p.stderr)
    dis=subprocess.check_output(['build/abc-runtime','dis',str(module)],text=True)
    (OUT/(name+'.dis')).write_text(dis)
    targets=sorted(set(int(v,16) for v in re.findall(r'\bJMP\s+0x([0-9a-f]+)',dis)))
    for engine in ['before-runtime','build/abc-runtime']:
        for mode in ['interpreted','compiled','lazy']:
            for target in [None]+targets:
                env=dict(os.environ);env.pop('ABC_FORCE_HOME_PC',None);env.pop('ABC_PROJECTION_TRACE',None)
                if target is not None:env['ABC_FORCE_HOME_PC']=hex(target)
                cmd=[str(ROOT/engine),'run',str(module),'main',*[str(v) for v in args], '--'+mode,'--stack=1024']
                p=subprocess.run(cmd,text=True,capture_output=True,env=env,timeout=20)
                # The CLI prints cells as signed decimal; compare their exact 64-bit payloads.
                got=[int(v)&((1<<64)-1) for v in p.stdout.split()] if p.returncode==0 else []
                ok=p.returncode==0 and got==expected
                rows.append(dict(case=name,engine=engine,mode=mode,target=target,status=p.returncode,stdout=p.stdout,stderr=p.stderr,expected=expected,ok=ok))
                if engine=='build/abc-runtime' and not ok: print('FAIL',name,mode,target,p.returncode,got,p.stderr,flush=True)
(OUT/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
for engine in ['before-runtime','build/abc-runtime']:
    selected=[r for r in rows if r['engine']==engine]
    print(engine,len(selected),'executions;',sum(not r['ok'] for r in selected),'failures')
raise SystemExit(any(not r['ok'] for r in rows if r['engine']=='build/abc-runtime'))
