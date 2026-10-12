#!/usr/bin/env python3
"""Paired phase-3 checkpoint, never overwrites the preserved baseline evidence."""
import hashlib, json, random, statistics, subprocess, sys
from pathlib import Path
baseline, current, optimizer, programs, output = map(lambda p: Path(p).resolve(), sys.argv[1:6])
output.mkdir(parents=True, exist_ok=True)
optimized = output / 'optimized'
optimized.mkdir(exist_ok=True)
workloads = []
for row in (programs / 'workloads.tsv').read_text().splitlines():
    name, expected, kind = row.split('\t')
    if kind != 'bench':
        continue
    source, target = programs / (name + '.abc'), optimized / (name + '.abc')
    subprocess.run([str(optimizer), str(source), '-o', str(target)], check=True)
    workloads.append((name, int(expected)))
variants = ['baseline', 'current', 'optimized']
modes = ['interpreted', 'compiled', 'lazy']
records = []
rng = random.Random(20260810)
for iteration in range(6):
    order = workloads.copy()
    rng.shuffle(order)
    for name, expected in order:
        shift = iteration % 3
        for mode in modes[shift:] + modes[:shift]:
            for variant in variants[shift:] + variants[:shift]:
                runner = baseline if variant == 'baseline' else current
                module = (optimized if variant == 'optimized' else programs) / (name + '.abc')
                command = ['taskset', '-c', '0', str(runner), mode, str(module), '7']
                p = subprocess.run(command, text=True, capture_output=True, timeout=60)
                record = dict(round=iteration, workload=name, mode=mode, variant=variant,
                              command=command, returncode=p.returncode, stdout=p.stdout, stderr=p.stderr)
                records.append(record)
                (output / 'timings.json').write_text(json.dumps(records, indent=2) + '\n')
                assert p.returncode == 0, record
                fields = p.stdout.split()
                assert int(fields[0]) == expected, record
                record.update(result=int(fields[0]), steady=float(fields[1]), read=float(fields[2]),
                              prepare=float(fields[3]), native_bytes=int(fields[4]), first=float(fields[5]),
                              samples=list(map(float, fields[6:])))
                assert len(record['samples']) == 7
                (output / 'timings.json').write_text(json.dumps(records, indent=2) + '\n')
lines = ['workload mode current/baseline optimized/current baseline_ms current_ms optimized_ms native_bytes_baseline/current/optimized']
for name, _ in workloads:
    for mode in modes:
        times, sizes = [], []
        for variant in variants:
            rows = [r for r in records if (r['workload'], r['mode'], r['variant']) == (name, mode, variant)]
            times.append(statistics.median(s for r in rows for s in r['samples']) * 1000)
            size = {r['native_bytes'] for r in rows}
            assert len(size) == 1
            sizes.append(str(size.pop()))
        lines.append(f'{name} {mode} {times[1]/times[0]:.4f} {times[2]/times[1]:.4f} '
                     + ' '.join(f'{t:.3f}' for t in times) + ' ' + '/'.join(sizes))
text = '\n'.join(lines) + '\n'
(output / 'summary.txt').write_text(text)
paths = [baseline, current, optimizer, Path(__file__).resolve()]
paths += list(programs.glob('*.abc')) + list(optimized.glob('*.abc'))
(output / 'artifact-sha256.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, indent=2) + '\n')
(output / 'changed-modules.json').write_text(json.dumps({name: (programs/(name+'.abc')).read_bytes() != (optimized/(name+'.abc')).read_bytes() for name, _ in workloads}, indent=2) + '\n')
print(text, end='')
