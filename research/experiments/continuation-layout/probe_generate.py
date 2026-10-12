from pathlib import Path
import subprocess
root=Path(__file__).parent
for dst in ('A','B'):
    other='B' if dst=='A' else 'A'
    lines=['.profile memory','.datazero 24','.function main 0 1 - i',
           'CALLOC 8','PUSH.A 101','FST64.A 8','FADDR.A 8','GST64 0',
           'PUSH.A 777','CPUSH.A']
    for i in range(10):
        lines += ['PUSH.A 111','PUSH.B 222','FADDR.A 16',f'PUSH.A {i}',f'CALL.{dst} middle 2',
                  f'PUSH.{other} {i+10}',f'BEQ result2_{i}','ABORT 1',f'result2_{i}:',
                  f'PUSH.{other} 606',f'BEQ result1_{i}','ABORT 2',f'result1_{i}:',
                  'PUSH.A 222',f'BEQ live_b_{i}','ABORT 3',f'live_b_{i}:',
                  'PUSH.B 111',f'BEQ live_a_{i}','ABORT 4',f'live_a_{i}:',
                  'CGET.A 0','PUSH.B 777',f'BEQ live_c_{i}','ABORT 5',f'live_c_{i}:']
    lines += ['.loadkind int','FLD64.A 16','CPOP','CFREE 8','RET 0 1',
              '.function middle 2 2 ai ii','CALLOC 8','PUSH.A 202','FST64.A 8',
              'FADDR.A 8','GST64 8','PUSH.A 888','CPUSH.A',
              'PUSH.A 333','PUSH.B 444','CGET.A 2','FADDR.A 16','CGET.A 3',f'CALL.{dst} leaf 3']
    # Save the ordered pair to C before checking surviving operand cells.
    lines += [f'CPUSH.{dst}',f'CPUSH.{dst}',
              'PUSH.A 444','BEQ mid_b','ABORT 6','mid_b:',
              'PUSH.B 333','BEQ mid_a','ABORT 7','mid_a:',
              'CGET.A 2','PUSH.B 888','BEQ mid_c','ABORT 8','mid_c:',
              'CGET.A 0','CGET.A 1','CPOP','CPOP','CPOP','CFREE 8','RET 2 2',
              '.function leaf 3 2 aai ii','CALLOC 8','PUSH.A 303','FST64.A 8',
              'FADDR.A 8','GST64 16','PUSH.A 999','CPUSH.A',
              'PUSH.A 555','PUSH.B 666','JMP probe','probe:',
              # All three address-exposed objects must retain identity/content.
              'CGET.A 2','.loadkind int','LD64.A 0',
              'CGET.B 3','.loadkind int','LD64.B 0','ADD.A',
              '.loadkind int','FLD64.B 16','ADD.A','CPUSH.A',
              'PUSH.A 666','BEQ leaf_b','ABORT 9','leaf_b:',
              'PUSH.B 555','BEQ leaf_a','ABORT 10','leaf_a:',
              'CGET.A 1','PUSH.B 999','BEQ leaf_c','ABORT 11','leaf_c:',
              'CGET.A 0','CGET.A 5','ADDI.A 10','CPOP','CPOP','CFREE 8','RET 3 2',
              '.export main']
    path=root/f'layout-{dst}.abcasm';path.write_text('\n'.join(lines)+'\n')
    subprocess.run([str(root/'build/abc'),'asm',str(path),'-o',str(path.with_suffix('.abc'))],check=True)
    with (root/f'layout-{dst}.dis').open('w') as out:
        subprocess.run([str(root/'build/abc-runtime'),'dis',str(path.with_suffix('.abc'))],stdout=out,check=True)
