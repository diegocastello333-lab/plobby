const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = process.argv[2], scene = process.argv[3] || 'pm';
const types = { '.js': 'text/javascript', '.html': 'text/html', '.wasm': 'application/wasm', '.json': 'application/json', '.otf': 'font/otf', '.ttf': 'font/ttf', '.png': 'image/png' };
const srv = http.createServer((q, r) => { let p = path.join(root, q.url.split('?')[0]); if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) p = path.join(root, 'index.html');
  r.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(r); }).listen(8766);
(async () => {
  const b = await chromium.launch(); const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 }); const page = await ctx.newPage();
  await page.goto('http://localhost:8766/'); await page.waitForSelector('flutter-view, flt-glass-pane'); await page.waitForTimeout(2500);
  await page.evaluate((s) => { window.__t = []; const st = performance.now(); const tick = (t) => { window.__t.push(t - st); if (t - st < 8000) requestAnimationFrame(tick); else window.__done = 1; }; requestAnimationFrame(tick); location.hash = '#/' + s; }, scene);
  await page.waitForFunction(() => window.__done, null, { timeout: 60000 });
  const t = await page.evaluate(() => window.__t);
  const per = []; for (let s = 0; s < 8; s++) per.push(t.filter(x => x >= s * 1000 && x < (s + 1) * 1000).length);
  console.log(scene, 'frames por segundo:', per.join(' '));
  await b.close(); srv.close();
})();
