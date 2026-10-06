const src = require('fs').readFileSync(__dirname + '/../../lab/ui.js', 'utf8');
const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
require('./core_frame.js'); const S = globalThis.SimCore;
let total = 0, moves = 0, calls = 0, multi = 0; const per = [];
for (const [title, code] of ex) {
  const asm = S.assemble(S.wcompile(code).asm).code; const sn = S.run(asm, 500000);
  let mv = 0;
  for (let i = 1; i < sn.length; i++) {
    const ins = asm[sn[i].last]; if (!ins) continue;
    if (ins.op === 'CALL') calls++;
    if (ins.op === 'MOVE' && ins.x === 'AB' && sn[i].last > 0 && asm[sn[i].last - 1].op === 'CALL') mv++;
  }
  total += sn.length - 1; moves += mv;
  if (mv) per.push(`${title}: ${mv} of ${sn.length - 1}`);
}
console.log(`MOVE.AB right after a CALL: ${moves} of ${total} executed instructions (${(100 * moves / total).toFixed(1)}%), over ${calls} calls`);
per.forEach(p => console.log('  ' + p));
