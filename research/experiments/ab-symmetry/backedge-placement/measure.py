#!/usr/bin/env python3
"""Backedge placement correction versus the preserved pre-fix revision-6 build."""
import csv, json, os, statistics, subprocess
from pathlib import Path

here = Path(__file__).resolve().parent
old = here.parent / 'final-comparison'
expected = {'loop': 3180325737, 'branch': 7015924, 'fib': 832040, 'memory': 1000000}
cases = [(name, mode) for name in expected for mode in ('interpreted', 'compiled', 'lazy')]
env = dict(os.environ, LC_ALL='C')
env.pop('ABC_DUMP_NATIVE', None)
fields = ['round', 'workload', 'mode', 'version', 'result', 'median_seconds',
          'read_seconds', 'prepare_seconds', 'native_bytes', 'first_call_seconds']

def run(name, mode, version):
    directory = old if version == 'old' else here
    command = ['taskset', '-c', '0', str(directory / 'runlet'), mode,
               str(directory / (name + '.abc')), '7']
    process = subprocess.run(command, capture_output=True, text=True, env=env)
    raw.write(json.dumps({'command': command, 'status': process.returncode,
                          'stdout': process.stdout, 'stderr': process.stderr}) + '\n')
    raw.flush()
    assert process.returncode == 0, process.stderr
    values = process.stdout.split()
    assert len(values) == 6 and int(values[0]) == expected[name], (command, values)
    return [name, mode, version] + values

rows = []
with (here / 'raw.jsonl').open('x') as raw, (here / 'timings.csv').open('x', newline='') as output:
    writer = csv.writer(output)
    writer.writerow(fields)
    for name, mode in cases:
        for version in ('old', 'new'):
            row = [-1] + run(name, mode, version)
            writer.writerow(row)  # independent correctness preflight; not summary samples
    for round_ in range(6):
        order = cases[round_:] + cases[:round_]
        for index, (name, mode) in enumerate(order):
            versions = ('old', 'new') if (round_ + index) % 2 == 0 else ('new', 'old')
            for version in versions:
                row = [round_] + run(name, mode, version)
                rows.append(dict(zip(fields, row)))
                writer.writerow(row)
                output.flush()

summary = []
for name, mode in cases:
    groups = {v: [r for r in rows if r['workload'] == name and r['mode'] == mode and r['version'] == v]
              for v in ('old', 'new')}
    entry = {'workload': name, 'mode': mode}
    for version, group in groups.items():
        entry[version] = {field: statistics.median(float(r[field]) for r in group)
                          for field in ('median_seconds', 'read_seconds', 'prepare_seconds', 'first_call_seconds')}
        entry[version]['native_bytes'] = sorted({int(r['native_bytes']) for r in group})
    ratios = [float(n['median_seconds']) / float(o['median_seconds'])
              for o, n in zip(groups['old'], groups['new'])]
    entry['paired_new_over_old'] = {'median': statistics.median(ratios), 'min': min(ratios), 'max': max(ratios)}
    summary.append(entry)
(here / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
for row in summary:
    ratio = row['paired_new_over_old']
    print(f"{row['workload']:6} {row['mode']:11} old={row['old']['median_seconds']*1000:.3f}ms "
          f"new={row['new']['median_seconds']*1000:.3f}ms ratio={ratio['median']:.3f} "
          f"[{ratio['min']:.3f},{ratio['max']:.3f}]")
