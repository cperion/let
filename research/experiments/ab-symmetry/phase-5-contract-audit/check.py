#!/usr/bin/env python3
"""Documentation contract checks; no runtime/build source modifications."""
from pathlib import Path
import hashlib,re,struct,subprocess,tempfile
root=Path(__file__).resolve().parents[4]
out=Path(__file__).resolve().parent
checks=0

def run(*args):
    result=subprocess.run([str(root/'build/abc'),*map(str,args)],capture_output=True,text=True)
    assert result.returncode==0,(args,result.stdout,result.stderr)
    return result.stdout.strip()

with tempfile.TemporaryDirectory(prefix='abc-doc-contract-') as name:
    work=Path(name)
    source='''.function main 0 1
PUSH.A 10
PUSH.B 3
SUB.B
RET.B 0 1
.export main
'''
    for profile,sections in [('integer',3),('memory',6),('callables',8),('foreign',9)]:
        asm=work/(profile+'.abcasm');module=work/(profile+'.abc')
        asm.write_text('.profile '+profile+'\n'+source)
        run('asm',asm,'-o',module)
        header=struct.unpack('<4sHBBII',module.read_bytes()[:16])
        assert header==(b'ABC2',6,8,['integer','memory','callables','foreign'].index(profile)+1,sections,0),header
        checks+=1
        for mode in ['interpreted','compiled','lazy']:
            assert run('run',module,'--'+mode)=='-7';checks+=1
    for example,expected in [('memory','99 1 72'),('callables','42')]:
        module=work/(example+'-example.abc')
        run('asm',root/'examples'/(example+'.abcasm'),'-o',module)
        run('check',module)
        for mode in ['interpreted','compiled','lazy']:
            assert run('run',module,'--'+mode)==expected;checks+=1
    foreign=work/'foreign-example.abc'
    run('asm',root/'examples/foreign.abcasm','-o',foreign);run('check',foreign);checks+=1

lua="""package.path='tools/?.lua;'..package.path
local m=require('opcodes')
local seen=0
for _,op in ipairs(m.ops) do
 local name=m.operations[op.operation+1]
 if name=='CALLI' then assert(op.len==2 and op.layout_name=='U8');seen=seen+1 end
 if name=='TCALLI' then assert(op.len==3 and op.layout_name=='U8_U8');seen=seen+1 end
end
assert(seen==4)
"""
subprocess.run(['/tmp/lua-compat','-e',lua],cwd=root,check=True);checks+=4
for mode in ['compiled','lazy']:
    text=(out/f'budget-{mode}-trace.txt').read_text()
    versions=[int(n) for n in re.findall(r'AUDIT pc=50 versions=(\d+)',text)]
    assert max(versions)==10 and (out/f'budget-{mode}-result.txt').read_text().split()[0]=='42'
    checks+=1
files=['spec','architecture','memory-profile','callable-profile','foreign-profile','module-format']
links=0
for name in files:
    path=root/'docs'/(name+'.md')
    for link in re.findall(r'\]\(([^)]+)\)',path.read_text()):
        if '://' in link or link.startswith('#'):continue
        assert (path.parent/link.split('#')[0]).exists(),(path,link)
        links+=1
for line in (out/'implementation-before.sha256').read_text().splitlines():
    digest,path=line.split(None,1)
    assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest,path
print(f'{checks} encoding/header/example/budget-evidence checks pass; {links} local documentation links resolve.')
print('All recorded runtime/generator/frontend/tool/header/Makefile source hashes are unchanged.')
