require('./core.js'); const S = globalThis.SimCore;
const src = require('fs').readFileSync(__dirname + '/../lab/ui.js', 'utf8');
const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
function trace(code, snaps) {
  const t = [];
  for (const sn of snaps) {
    if (sn.last < 0) continue;
    const o = code[sn.last];
    if (o.op === 'CALL') t.push(['push', 'ret']); else if (o.op === 'RET') t.push(['pop']);
    else if (o.op === 'CPUSH') t.push(['push', 'bind']); else if (o.op === 'CPOP') t.push(['pop']);
    else if (o.op === 'CGET') t.push(['read', o.n]); else if (o.op === 'CSET') t.push(['read', o.n]);
  }
  return t;
}
/* lazy (today): cache the newest cells, spill the deepest cached on overflow, never refill */
function lazy(t, cap) {
  let size = 0, k = 0, mem = 0;
  for (const [op, a] of t) {
    if (op === 'push') { size++; if (k === cap) mem++; else k++; }
    else if (op === 'pop') { size--; if (k) k--; }
    else if (a >= k) mem++;
  }
  return mem;
}
/* static: the bank holds exactly the top min(f, cap) cells of the current frame, where f is the
   frame depth the verifier knows; return addresses live in memory. Refills keep the invariant. */
function staticFrame(t, cap) {
  const frames = [[]];           /* each frame: array of cells, cell.cached */
  let mem = 0;
  const fr = () => frames[frames.length - 1];
  const settle = () => {          /* make exactly the top min(f, cap) cells of the current frame cached */
    const f = fr(); const want = Math.min(f.length, cap);
    for (let i = 0; i < f.length; i++) {
      const should = i >= f.length - want;
      if (should && !f[i].cached) { mem++; f[i].cached = true; }        /* refill: load */
      if (!should && f[i].cached) { mem++; f[i].cached = false; }       /* evict: spill */
    }
    /* the caller's cells cannot stay in registers while this frame uses them all */
    let used = want;
    for (let j = frames.length - 2; j >= 0; j--) for (const c of frames[j]) if (c.cached) { if (used >= cap) { mem++; c.cached = false; } else used++; }
  };
  for (const [op, a, kind] of t) {
    if (op === 'push' && a === 'ret') { mem++; frames.push([]); }       /* return address written to memory */
    else if (op === 'push') { fr().push({ cached: false }); fr()[fr().length - 1].cached = true; settle(); }
    else if (op === 'pop') {
      if (fr().length) { fr().pop(); settle(); }
      else { frames.pop(); mem++; settle(); }                          /* RET: read the return address, restore the caller's bank */
    }
    else { const f = fr(); const i = f.length - 1 - a; if (i < 0 || !f[i].cached) mem++; }
  }
  return mem;
}
let tl = 0, ts = 0; const rows = [];
for (const [title, code] of ex) {
  let asm; try { asm = S.assemble(S.wcompile(code).asm).code; } catch (e) { continue; }
  const t = trace(asm, S.run(asm, 200000));
  const l = lazy(t, 3), st = staticFrame(t, 3);
  tl += l; ts += st; if (l !== st) rows.push(`${title}: ${l} -> ${st}`);
}
console.log(`C memory operations, 3 C registers, 19 programs: lazy (today) ${tl}, static frame policy ${ts} (${((ts / tl - 1) * 100).toFixed(0)}%)`);
console.log(rows.slice(0, 8).join('\n'));
