const src = require('fs').readFileSync(__dirname + '/../../lab/ui.js', 'utf8');
const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
function load(f) { delete require.cache[require.resolve(f)]; delete globalThis.SimCore; require(f); return globalThis.SimCore; }
const A = load('./core_frame.js'), B = load('./core_fuse.js');
let ta = 0, tb = 0, sa = 0, sb = 0, bad = 0; const rows = []; const used = {};
for (const [title, code] of ex) {
  let want; try { want = A.weval(code).map(String).join(','); } catch (e) { want = 'abort ' + e.code; }
  const run = S => { const asm = S.assemble(S.wcompile(code).asm).code; const sn = S.run(asm, 500000); const l = sn.at(-1);
    if (S === B) sn.forEach(x => { if (x.last >= 0) { const o = asm[x.last]; if (['BINI', 'BINC', 'CBI'].includes(o.op)) used[o.op] = (used[o.op] || 0) + 1; } });
    return { steps: sn.length - 1, size: asm.length, got: l.reason ? 'abort ' + l.reason : l.A.slice().reverse().map(x => String(x.v)).join(',') }; };
  const a = run(A), b = run(B);
  if (a.got !== want || b.got !== want) { bad++; console.log('MISMATCH', title, a.got, b.got, want); }
  ta += a.steps; tb += b.steps; sa += a.size; sb += b.size; rows.push([title, a.steps, b.steps]);
}
rows.sort((x, y) => (y[1] - y[2]) / y[1] - (x[1] - x[2]) / x[1]);
rows.slice(0, 7).forEach(([t, a, b]) => console.log('  ' + t.padEnd(34), String(a).padStart(6), '->', String(b).padStart(6), `(${((1 - b / a) * 100).toFixed(0)}% fewer)`));
console.log(`\nall 19: executed ${ta} -> ${tb} (${((1 - tb / ta) * 100).toFixed(1)}% fewer), code ${sa} -> ${sb} instructions; fused forms executed ${JSON.stringify(used)}; ${bad ? bad + ' MISMATCHES' : 'all results match'}`);
