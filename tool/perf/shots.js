// node shots.js <url> <prefijo> <dir>: Inicio en 375×812 y 1440×900 (modo demo).
const { chromium } = require('playwright');
const [url, prefix, dir] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch();
  for (const [w, h, dpr, tag] of [[375, 812, 2, 'movil'], [1440, 900, 1, 'escritorio']]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: dpr, isMobile: w < 500, hasTouch: w < 500 });
    const p = await ctx.newPage();
    await p.goto(url + '#/home'); await p.waitForFunction(() => /home/.test(location.hash) && !document.getElementById('plobby-splash'), null, { timeout: 120000 });
    await p.waitForTimeout(4000);
    await p.screenshot({ path: `${dir}/${prefix}_inicio_${tag}.png` });
    await ctx.close();
  }
  await b.close();
})();
