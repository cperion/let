from pathlib import Path
import subprocess, re
root=Path(__file__).parent
for dst in ('A','B'):
    text=(root/f'alias-{dst}.abcasm').read_text()
    old='.function leaf 3 2 aai ii\n'
    wrapper=('.function leaf 3 2 aai ii\nCGET.A 0\nCGET.A 1\nCGET.A 2\nPUSH.A 123\nTCALL leafwide 3 4\n'
             '.function leafwide 4 2 aaii ii\n')
    text=text.replace(old,wrapper).replace('RET 3 2\n','RET 4 2\n')
    path=root/f'tail-{dst}.abcasm';path.write_text(text)
    subprocess.run([str(root/'build/abc'),'asm',str(path),'-o',str(path.with_suffix('.abc'))],check=True)
    dis=subprocess.check_output([str(root/'build/abc-runtime'),'dis',str(path.with_suffix('.abc'))],text=True)
    (root/f'tail-{dst}.dis').write_text(dis)
    pc=int(re.search(r'\bJMP\s+0x([0-9a-f]+)',dis).group(1),16)
    (root/f'tail-{dst}.pc').write_text(hex(pc)+'\n')
    print(dst,hex(pc))
