const { chromium, devices } = require('playwright');
const url = process.argv[2];
(async () => {
  const browser = await chromium.launch({ proxy: process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined });
  const ctx = await browser.newContext({ ...devices['Pixel 7'] });
  const page = await ctx.newPage(); const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable'); const m = {}; const enc = {};
  cdp.on('Network.responseReceived', e => { m[e.requestId] = { url: e.response.url, ce: e.response.headers['content-encoding'] || e.response.headers['Content-Encoding'] || '-', cc: e.response.headers['cache-control'] || '' }; });
  cdp.on('Network.loadingFinished', e => { if (m[e.requestId]) m[e.requestId].kb = Math.round(e.encodedDataLength / 1024); });
  await page.goto(url); await page.waitForFunction(() => /welcome|home/.test(location.hash), null, { timeout: 120000 }); await page.waitForTimeout(3000);
  const rows = Object.values(m).sort((a, b) => (b.kb || 0) - (a.kb || 0));
  let tot = 0; for (const r of rows) { tot += r.kb || 0; console.log(String(r.kb).padStart(6), r.ce.padEnd(3), r.url.replace(/^https?:\/\/[^/]+/, '').slice(0, 90), '|', r.cc); }
  console.log('TOTAL KB', tot); await browser.close();
})();
