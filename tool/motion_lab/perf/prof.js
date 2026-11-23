const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = process.argv[2], scene = process.argv[3] || 'pm';
const types = { '.js': 'text/javascript', '.html': 'text/html', '.wasm': 'application/wasm', '.json': 'application/json', '.otf': 'font/otf', '.ttf': 'font/ttf', '.png': 'image/png' };
const srv = http.createServer((q, r) => { let p = path.join(root, q.url.split('?')[0]); if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) p = path.join(root, 'index.html');
  r.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(r); }).listen(8767);
(async () => {
  const b = await chromium.launch(); const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 }); const page = await ctx.newPage();
  await page.goto('http://localhost:8767/'); await page.waitForSelector('flutter-view, flt-glass-pane'); await page.waitForTimeout(2500);
  const cdp = await ctx.newCDPSession(page); if (process.env.RATE) await cdp.send('Emulation.setCPUThrottlingRate', { rate: +process.env.RATE }); await cdp.send('Profiler.enable'); await cdp.send('Profiler.setSamplingInterval', { interval: 200 });
  await page.evaluate((s) => { location.hash = '#/' + s; }, scene);
  await page.waitForTimeout(400);
  await cdp.send('Profiler.start'); await page.waitForTimeout(4000); const { profile } = await cdp.send('Profiler.stop');
  const self = {}; const byId = {}; for (const n of profile.nodes) byId[n.id] = n;
  const dt = {}; for (let i = 0; i < profile.samples.length; i++) dt[profile.samples[i]] = (dt[profile.samples[i]] || 0) + (profile.timeDeltas[i] || 0);
  for (const n of profile.nodes) { const k = (n.callFrame.functionName || '(anon)') + ' ' + n.callFrame.url.split('/').pop() ; self[k] = (self[k] || 0) + (dt[n.id] || 0); }
  const tot = Object.values(self).reduce((a, b) => a + b, 0);
  const g = { dart: 0, skia: 0, present: 0, idle: 0, other: 0 };
  for (const [k, v] of Object.entries(self)) {
    if (k.includes('main.dart.js')) g.dart += v; else if (k.includes('canvaskit') || k.startsWith('wasm') || k.startsWith('js-to-wasm')) g.skia += v;
    else if (k.startsWith('createImageBitmap') || k.startsWith('transferFromImageBitmap')) g.present += v; else if (k.startsWith('(idle)')) g.idle += v; else g.other += v; }
  const ms = (x) => (x / 1000).toFixed(0);
  console.log(JSON.stringify({ scene, rate: +(process.env.RATE || 1), dartMs: +ms(g.dart), skiaMs: +ms(g.skia), presentMs: +ms(g.present), otherMs: +ms(g.other), idleMs: +ms(g.idle), windowMs: 4000 }));
  await b.close(); srv.close();
})();
