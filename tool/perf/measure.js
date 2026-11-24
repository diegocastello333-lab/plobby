// Uso: node measure.js <url> [etiqueta] [runs]
// Mide primera y segunda visita con red «4G lento» (1,6 Mbps, 150 ms RTT) y CPU 4× más lenta (móvil medio).
const { chromium, devices } = require('playwright');
const url = process.argv[2], label = process.argv[3] || url, runs = +(process.argv[4] || 3);
const proxy = process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined;
async function visit(page, cdp) {
  const t0 = Date.now(); let bytes = 0, reqs = 0; const types = {};
  const onResp = e => { reqs++; };
  const onFin = e => { bytes += e.encodedDataLength; };
  cdp.on('Network.responseReceived', onResp); cdp.on('Network.loadingFinished', onFin);
  await page.goto(url, { waitUntil: 'commit' });
  const ff = await page.evaluate(() => new Promise(r => {
    if (window.__ff) return r(window.__ff);
    window.addEventListener('flutter-first-frame', () => r(performance.now()), { once: true });
  }));
  // contenido útil: la app sale del splash (ruta distinta de /splash) y el splash HTML ya no está
  await page.waitForFunction(() => !/splash/.test(location.hash) && location.hash.length > 2 && !document.getElementById('plobby-splash'), null, { timeout: 120000, polling: 50 });
  const useful = await page.evaluate(() => performance.now());
  await page.waitForTimeout(1500);
  cdp.off('Network.responseReceived', onResp); cdp.off('Network.loadingFinished', onFin);
  return { firstFrame: Math.round(ff), useful: Math.round(useful), route: await page.evaluate(() => location.hash), kb: Math.round(bytes / 1024), reqs };
}
(async () => {
  const browser = await chromium.launch({ proxy });
  const res = [];
  for (let i = 0; i < runs; i++) {
    const ctx = await browser.newContext({ ...devices['Pixel 7'], ignoreHTTPSErrors: false });
    const page = await ctx.newPage();
    const cdp = await ctx.newCDPSession(page);
    await cdp.send('Network.enable');
    await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 150, downloadThroughput: 1.6e6 / 8, uploadThroughput: 750e3 / 8 });
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
    const first = await visit(page, cdp);
    const second = await visit(page, cdp);
    res.push({ first, second });
    await ctx.close();
  }
  await browser.close();
  const med = (k, f) => { const v = res.map(r => r[k][f]).sort((a, b) => a - b); return v[Math.floor(v.length / 2)]; };
  console.log(JSON.stringify({ label, runs: res, median: {
    first: { firstFrame: med('first', 'firstFrame'), useful: med('first', 'useful'), kb: med('first', 'kb'), reqs: med('first', 'reqs') },
    second: { firstFrame: med('second', 'firstFrame'), useful: med('second', 'useful'), kb: med('second', 'kb'), reqs: med('second', 'reqs') } } }, null, 1));
})();
