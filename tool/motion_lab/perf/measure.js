const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = process.argv[2], out = process.argv[3];
const types = { '.js': 'text/javascript', '.html': 'text/html', '.wasm': 'application/wasm', '.json': 'application/json', '.otf': 'font/otf', '.ttf': 'font/ttf', '.png': 'image/png', '.svg': 'image/svg+xml', '.jpg': 'image/jpeg' };
const srv = http.createServer((q, r) => {
  let p = path.join(root, decodeURIComponent(q.url.split('?')[0]));
  if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) p = path.join(root, 'index.html');
  r.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(r);
}).listen(8765);
(async () => {
  const browser = await chromium.launch();
  const results = [];
  const SC = (process.env.SCENES || 'pm,cel,ranking,achievements,rating,feed').split(','), RATES = (process.env.RATES || '1,4,6').split(',').map(Number), RED = process.env.REDUCE === '0' ? [false] : [false, true];
  for (const reduce of RED) for (const rate of RATES) for (const scene of SC) {
    if (reduce && rate !== 4) continue;
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, reducedMotion: reduce ? 'reduce' : 'no-preference' });
    const page = await ctx.newPage();
    await page.goto('http://localhost:8765/');
    await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
    await page.waitForTimeout(2500);
    const cdp = await ctx.newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate });
    await page.evaluate(() => { window.__lt = 0; new PerformanceObserver(l => { for (const e of l.getEntries()) window.__lt += e.duration; }).observe({ type: 'longtask', buffered: false }); });
    // empezar a medir y navegar a la escena en el mismo instante
    await page.evaluate((s) => {
      window.__f = []; let last = performance.now(); const end = last + 6000;
      const tick = (t) => { window.__f.push(t - last); last = t; if (t < end) requestAnimationFrame(tick); else window.__done = true; };
      requestAnimationFrame(tick);
      location.hash = '#/' + s;
    }, scene);
    if (scene === 'feed') { await page.waitForTimeout(2500); await page.mouse.move(195, 600); for (let i = 0; i < 6; i++) { await page.mouse.wheel(0, 350); await page.waitForTimeout(250); } }
    await page.waitForFunction(() => window.__done, null, { timeout: 60000 });
    if (rate === 4) await page.screenshot({ path: `${out}/${scene}_${reduce ? 'reducido' : 'normal'}.png` });
    const f = await page.evaluate(() => window.__f.slice(1));
    const lt = await page.evaluate(() => window.__lt);
    f.sort((a, b) => a - b);
    const total = f.reduce((a, b) => a + b, 0);
    results.push({ scene, rate, reduce, fps: +(f.length / (total / 1000)).toFixed(1), p50: +f[Math.floor(f.length * .5)].toFixed(1),
      p95: +f[Math.floor(f.length * .95)].toFixed(1), max: +f[f.length - 1].toFixed(1), jank: +(100 * f.filter(x => x > 25).length / f.length).toFixed(1), longtaskMs: Math.round(lt) });
    console.log(JSON.stringify(results[results.length - 1]));
    await ctx.close();
  }
  fs.writeFileSync(`${out}/${process.env.TAG || 'results'}.json`, JSON.stringify(results, null, 1));
  await browser.close(); srv.close();
})();
