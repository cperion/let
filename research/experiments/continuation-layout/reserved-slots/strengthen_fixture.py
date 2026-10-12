from pathlib import Path
import subprocess
root=Path(__file__).parent
for dst in ('A','B'):
    source=(root/f'layout-{dst}.abcasm').read_text()
    extra=[]
    for base,label in ((16,'leaf'),(8,'middle'),(0,'main')):
        extra += ['FADDR.B 16' if base==16 else f'CGET.B {3 if base==8 else 2}',
                  '.loadkind addr',f'GLD64 {base}',f'BEQ identity_{label}','ABORT 12',f'identity_{label}:']
    # Write through escaped address, then original leaf computes its result
    # using FLD64: verifies that pointer and frame access still alias.
    extra += ['.loadkind addr','GLD64 16','PUSH.B 304','ST64 0']
    source=source.replace('probe:\n','probe:\n'+'\n'.join(extra)+'\n').replace(' 606\n',' 607\n')
    path=root/f'alias-{dst}.abcasm';path.write_text(source)
    subprocess.run([str(root/'build/abc'),'asm',str(path),'-o',str(path.with_suffix('.abc'))],check=True)
