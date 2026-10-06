require('./core_frame.js'); const S = globalThis.SimCore;
const src = require('fs').readFileSync(__dirname + '/../../lab/ui.js', 'utf8');
const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
let tot = 0, saved = 0; const kinds = { CGET: 0, CSET: 0, CPUSH: 0 }; const per = [];
for (const [title, code] of ex) {
  const a = S.assemble(S.wcompile(code).asm).code; const sn = S.run(a, 500000);
  const hits = new Array(a.length).fill(0); sn.forEach(s => { if (s.last >= 0) hits[s.last]++; });
  let sv = 0;
  for (let i = 0; i < a.length;) {
    const x = a[i]; let j = i + 1;
    if (x.op === 'CGET') while (j < a.length && a[j].op === 'CGET' && a[j].x === x.x && a[j].n === a[j - 1].n + 1) j++;
    else if (x.op === 'CSET') while (j < a.length && a[j].op === 'CSET' && a[j].x === x.x && a[j].n === a[j - 1].n - 1) j++;
    else if (x.op === 'CPUSH') while (j < a.length && a[j].op === 'CPUSH' && a[j].x === x.x) j++;
    if (j - i > 1) { const s = (j - i - 1) * hits[i]; sv += s; kinds[x.op] += s; }
    i = j;
  }
  tot += sn.length - 1; saved += sv;
  if (sv) per.push(`${title} ${(100 * sv / (sn.length - 1)).toFixed(1)}%`);
}
console.log(`with frame instructions: range forms would remove ${saved} of ${tot} executed instructions (${(100 * saved / tot).toFixed(1)}%)`, JSON.stringify(kinds));
console.log(per.join(' | '));
