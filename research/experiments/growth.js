const FL = require('./fourlane.js');
const src = require('fs').readFileSync(__dirname + '/explode.js', 'utf8');
const P = eval('(' + src.slice(src.indexOf('const P = {') + 10, src.indexOf('};\nconst allLocal') + 1) + ')');
const seen = new Set(); const out = [];
for (const [name, s] of Object.entries(P)) {
  const r = FL.run(FL.compile(s).code);
  const before = seen.size;
  for (const k of r.local.keys()) seen.add(k);
  out.push(`${name}+${seen.size - before}`);
}
console.log('new combinations per program, in order:', out.join('  '), ' total', seen.size);
