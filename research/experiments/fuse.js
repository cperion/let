require('./core_frame.js'); const S = globalThis.SimCore;
const src = require('fs').readFileSync(__dirname + '/../../lab/ui.js', 'utf8');
const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
let total = 0;
const pat = { 'CGET.B + op (C second, other from A)': 0, 'CGET.A + op (C first, other from B)': 0, 'CGET + compare-and-branch': 0,
  'CGET + unary': 0, 'op + CSET (result into C)': 0, 'PUSH + op (immediate, for comparison)': 0, 'PUSH + compare-and-branch': 0 };
const byOp = {}, depth = {};
for (const [title, code] of ex) {
  const a = S.assemble(S.wcompile(code).asm).code; const sn = S.run(a, 500000);
  total += sn.length - 1;
  for (let i = 2; i < sn.length; i++) {
    const p = a[sn[i - 1].last], q = a[sn[i].last];
    if (!p || !q || sn[i].last !== sn[i - 1].last + 1) continue;              /* straight-line pairs only */
    if (p.op === 'CGET' && q.op === 'BIN') {
      /* the CGET'd value is X0, and the op consumes both tops, so it is always an operand */
      pat[p.x === 'B' ? 'CGET.B + op (C second, other from A)' : 'CGET.A + op (C first, other from B)']++;
      byOp[q.fn] = (byOp[q.fn] || 0) + 1; depth[Math.min(p.n, 4)] = (depth[Math.min(p.n, 4)] || 0) + 1;
    }
    if (p.op === 'CGET' && q.op === 'CB') pat['CGET + compare-and-branch']++;
    if (p.op === 'CGET' && q.op === 'UN' && q.x === p.x) pat['CGET + unary']++;
    if (p.op === 'BIN' && q.op === 'CSET' && q.x === p.x) pat['op + CSET (result into C)']++;
    if (p.op === 'PUSH' && q.op === 'BIN') pat['PUSH + op (immediate, for comparison)']++;
    if (p.op === 'PUSH' && q.op === 'CB') pat['PUSH + compare-and-branch']++;
  }
}
console.log(`executed instructions: ${total}`);
for (const [k, v] of Object.entries(pat)) console.log(`  ${k.padEnd(40)} ${String(v).padStart(5)}  ${(100 * v / total).toFixed(1)}%`);
console.log('  ops fused with CGET:', JSON.stringify(Object.entries(byOp).sort((x, y) => y[1] - x[1])));
console.log('  CGET depth in those pairs (0,1,2,3,4+):', JSON.stringify(depth));
