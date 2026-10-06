const src = require('fs').readFileSync(__dirname + '/../lab/ui.js', 'utf8');
const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
function load(f) { delete require.cache[require.resolve(f)]; delete globalThis.SimCore; require(f); return globalThis.SimCore; }
const A = load('./core_exp.js'), B = load('./core_frame.js');
let ta = 0, tb = 0, ma = 0, mb = 0, bad = 0, sa = 0, sb = 0;
const rows = [];
for (const [title, code] of ex) {
  let want; try { want = A.weval(code).map(String).join(','); } catch (e) { want = 'abort ' + e.code; }
  const run = S => { const asm = S.assemble(S.wcompile(code).asm).code; const sn = S.run(asm, 500000); const l = sn.at(-1);
    return { steps: sn.length - 1, mem: l.stats.memReads + l.stats.memWrites, size: asm.length, got: l.reason ? 'abort ' + l.reason : l.A.slice().reverse().map(x => String(x.v)).join(',') }; };
  const a = run(A), b = run(B);
  let w2 = want; if (a.got.startsWith('abort')) w2 = a.got;
  if (a.got !== w2 || b.got !== w2) { bad++; console.log('MISMATCH', title, a.got, b.got, w2); }
  ta += a.steps; tb += b.steps; ma += a.mem; mb += b.mem; sa += a.size; sb += b.size;
  rows.push([title, a.steps, b.steps]);
}
rows.sort((x, y) => (y[1] - y[2]) / y[1] - (x[1] - x[2]) / x[1]);
rows.slice(0, 8).forEach(([t, a, b]) => console.log('  ' + t.padEnd(34), String(a).padStart(6), '->', String(b).padStart(6), `(${((1 - b / a) * 100).toFixed(0)}% fewer)`));
console.log(`\nall 19 programs: executed instructions ${ta} -> ${tb} (${((1 - tb / ta) * 100).toFixed(1)}% fewer); code size ${sa} -> ${sb} instructions; memory operations ${ma} -> ${mb}; ${bad ? bad + ' MISMATCHES' : 'all results match the reference'}`);
