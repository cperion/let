require('./core_exp.js'); const S = globalThis.SimCore;
const src = require('fs').readFileSync(__dirname + '/../lab/ui.js', 'utf8');
const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
const splits = [[4, 4], [3, 5], [5, 3], [6, 2], [2, 6]];
const tot = splits.map(() => 0); let oracle = 0, n = 0; const best = {};
for (const [title, code] of ex) {
  let asm; try { asm = S.assemble(S.wcompile(code).asm).code; } catch (e) { continue; }
  const row = splits.map(([a, k], i) => { S.setBanks(a, k); const st = S.run(asm, 100000).at(-1).stats; const t = st.memReads + st.memWrites; tot[i] += t; return t; });
  S.setBanks(4, 4);
  oracle += Math.min(...row); n++;
  const b = splits[row.indexOf(Math.min(...row))].join('/'); best[b] = (best[b] || 0) + 1;
}
console.log('programs', n);
console.log('split      ', splits.map(s => s.join('/').padStart(6)).join(''));
console.log('memory ops ', tot.map(v => String(v).padStart(6)).join(''));
console.log('oracle (best split per program):', oracle, 'vs 4/4:', tot[0], ((1 - oracle / tot[0]) * 100).toFixed(1) + '% less', JSON.stringify(best));
// fib(10) per-call numbers
S.setBanks(4, 4);
const fib = S.assemble(S.wcompile('let fib(n: u32) : u32 = if n < 2 then n else fib(n - 1) + fib(n - 2)\nlet main() : u32 = fib(10)').asm).code;
const st = S.run(fib, 100000).at(-1).stats; let calls = 0; const sn = S.run(fib, 100000); sn.forEach(x => { if (x.last >= 0 && fib[x.last].op === 'CALL') calls++; });
console.log('fib(10): calls', calls, 'memory ops', st.memReads + st.memWrites, 'per call', ((st.memReads + st.memWrites) / calls).toFixed(2), 'spills', st.spills);
