require('./core.js'); const S = globalThis.SimCore;
const src = require('fs').readFileSync(__dirname + '/../lab/ui.js', 'utf8');
const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
/* C access trace: push(kind), pop, read(depth), write(depth); kind is 'ret' or 'bind'; depth = call depth for frames */
function trace(code, snaps) {
  const t = []; let calls = 0;
  for (const sn of snaps) {
    if (sn.last < 0) continue;
    const o = code[sn.last];
    if (o.op === 'CALL') { t.push(['push', 'ret', calls]); calls++; }
    else if (o.op === 'RET') { t.push(['pop']); calls--; }
    else if (o.op === 'CPUSH') t.push(['push', 'bind', calls]);
    else if (o.op === 'CPOP') t.push(['pop']);
    else if (o.op === 'CGET') t.push(['read', o.n]);
    else if (o.op === 'CSET') t.push(['write', o.n]);
  }
  return t;
}
/* replay one logical C stack over physical lanes; lazy caching per lane: spill the deepest cached cell, read in place, never refill */
function replay(t, caps, laneOf) {
  const g = [], cached = caps.map(() => 0), sizes = caps.map(() => 0); let mem = 0;
  const laneDepth = idx => { const l = g[idx].lane; let d = 0; for (let j = g.length - 1; j > idx; j--) if (g[j].lane === l) d++; return d; };
  for (const [op, a, b] of t) {
    if (op === 'push') {
      const l = laneOf(a, b, g.length);
      if (caps[l] === 0) mem++; else if (cached[l] === caps[l]) mem++; else cached[l]++;
      g.push({ lane: l }); sizes[l]++;
    } else if (op === 'pop') {
      const l = g.pop().lane; sizes[l]--; if (cached[l] > 0) cached[l]--;
    } else {
      const idx = g.length - 1 - a, d = laneDepth(idx), l = g[idx].lane;
      if (d >= cached[l]) mem++;
    }
  }
  return mem;
}
const layouts = [
  ['one C lane, 4 cached (today)', [4], () => 0],
  ['two lanes 2+2: return addresses | bindings', [2, 2], k => (k === 'ret' ? 0 : 1)],
  ['two lanes 1+3: return addresses | bindings', [1, 3], k => (k === 'ret' ? 0 : 1)],
  ['two lanes 2+2: alternate by call depth', [2, 2], (k, d) => d & 1],
  ['two lanes 2+2: round robin per push', [2, 2], (k, d, n) => n & 1],
  ['two lanes 0+4: return addresses uncached', [0, 4], k => (k === 'ret' ? 0 : 1)],
];
const tot = layouts.map(() => 0); const rows = [];
for (const [title, code] of ex) {
  let asm; try { asm = S.assemble(S.wcompile(code).asm).code; } catch (e) { continue; }
  const t = trace(asm, S.run(asm, 200000));
  const r = layouts.map(([, caps, f], i) => { const v = replay(t, caps, f); tot[i] += v; return v; });
  if (r.some(v => v !== r[0])) rows.push([title, r]);
}
console.log('C memory operations over the 19 programs, same four C registers in every layout:');
layouts.forEach(([name], i) => console.log('  ' + name.padEnd(46), String(tot[i]).padStart(6), i ? `(${((tot[i] / tot[0] - 1) * 100).toFixed(0)}%)` : ''));
console.log('\nprograms where layouts differ:');
rows.forEach(([t, r]) => console.log('  ' + t.padEnd(34), r.map(v => String(v).padStart(5)).join(' ')));
/* lower bound: four registers holding ANY C cells, perfect-foresight eviction (Belady).
   A miss on a read costs a load; evicting a cell that is read again later costs a spill. */
function belady(t, cap) {
  const ev = []; const st = []; let id = 0;
  for (const [op, a] of t) {
    if (op === 'push') { const c = id++; st.push(c); ev.push(['def', c]); }
    else if (op === 'pop') ev.push(['die', st.pop()]);
    else ev.push(['use', st[st.length - 1 - a]]);
  }
  const nextUse = new Array(ev.length); const last = new Map();
  for (let i = ev.length - 1; i >= 0; i--) { const [k, c] = ev[i]; nextUse[i] = last.has(c) ? last.get(c) : Infinity; if (k === 'die') last.delete(c); else last.set(c, i); }
  const regs = new Map(); let mem = 0;
  const evict = i => {
    let worst = null, far = -1;
    for (const [c, nu] of regs) if (nu > far) { far = nu; worst = c; }
    if (far !== Infinity) mem++;                        /* still needed: spill */
    regs.delete(worst);
  };
  ev.forEach(([k, c], i) => {
    if (k === 'die') { regs.delete(c); return; }
    if (!regs.has(c)) { if (k === 'use') mem++; if (regs.size === cap) evict(i); }
    regs.set(c, nextUse[i]);
  });
  return mem;
}
let opt = 0, today = 0;
for (const [title, code] of ex) {
  let asm; try { asm = S.assemble(S.wcompile(code).asm).code; } catch (e) { continue; }
  const t = trace(asm, S.run(asm, 200000));
  opt += belady(t, 4); today += replay(t, [4], () => 0);
}
console.log(`\nceiling: any four C cells in registers, perfect eviction: ${opt} memory operations vs ${today} today (${((1 - opt / today) * 100).toFixed(0)}% less)`);
/* a static policy: classify each push SITE (instruction) once as hot or cold from how soon its
   cells are reused; cold cells go straight to memory, hot cells share the four registers */
function traceSites(code, snaps) {
  const t = [];
  for (const sn of snaps) {
    if (sn.last < 0) continue;
    const o = code[sn.last];
    if (o.op === 'CALL' || o.op === 'CPUSH') t.push(['push', sn.last]);
    else if (o.op === 'RET' || o.op === 'CPOP') t.push(['pop']);
    else if (o.op === 'CGET' || o.op === 'CSET') t.push(['read', o.n]);
  }
  return t;
}
function classify(t, window) {
  /* for each push site: share of its cells whose next access comes within `window` later pushes */
  const st = [], site = new Map();
  let pushes = 0;
  for (const [op, a] of t) {
    if (op === 'push') { st.push({ site: a, at: pushes, reused: false, decided: false }); pushes++; }
    else if (op === 'pop') { const c = st.pop(); if (!c.decided) { const s = site.get(c.site) || [0, 0]; s[1]++; site.set(c.site, s); } }
    else { const c = st[st.length - 1 - a]; if (!c.decided) { c.decided = true; const s = site.get(c.site) || [0, 0]; if (pushes - c.at <= window) s[0]++; s[1]++; site.set(c.site, s); } }
  }
  const hot = new Set(); for (const [k, [h, n]] of site) if (h / n >= 0.5) hot.add(k);
  return hot;
}
for (const window of [2, 4, 8]) {
  let total = 0;
  for (const [title, code] of ex) {
    let asm; try { asm = S.assemble(S.wcompile(code).asm).code; } catch (e) { continue; }
    const snaps = S.run(asm, 200000);
    const ts = traceSites(asm, snaps), hot = classify(ts, window);
    total += replay(ts.map(e => (e[0] === 'push' ? ['push', hot.has(e[1]) ? 'hot' : 'cold', 0] : e)), [4, 0], k => (k === 'hot' ? 0 : 1));
  }
  console.log(`per-site hot/cold, reuse window ${window} pushes: ${total} memory operations`);
}
