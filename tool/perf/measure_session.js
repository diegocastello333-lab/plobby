// Segunda visita CON sesión guardada (usuario que vuelve). Sesión de prueba con JWT no firmado: Supabase responderá 401
// a los datos, pero lo que se mide es cuánto tarda en verse el Inicio (sin red de por medio para decidir la ruta).
const { chromium, devices } = require('playwright');
const url = process.argv[2], label = process.argv[3] || url, runs = +(process.argv[4] || 3);
const uid = '00000000-0000-4000-8000-000000000001';
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const exp = Math.floor(Date.now() / 1000) + 3600 * 24;
const jwt = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: uid, exp, role: 'authenticated', aud: 'authenticated' })}.x`;
const session = JSON.stringify({ access_token: jwt, token_type: 'bearer', expires_in: 86400, expires_at: exp, refresh_token: 'r',
  user: { id: uid, aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {}, created_at: '2026-11-01T00:00:00Z' } });
(async () => {
  const browser = await chromium.launch(process.env.HTTPS_PROXY ? { proxy: { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' } } : {});
  const out = [];
  for (let i = 0; i < runs; i++) {
    const ctx = await browser.newContext({ ...devices['Pixel 7'] });
    const page = await ctx.newPage(); const cdp = await ctx.newCDPSession(page);
    await cdp.send('Network.enable');
    await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 150, downloadThroughput: 1.6e6 / 8, uploadThroughput: 750e3 / 8 });
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
    await page.goto(url); await page.waitForFunction(() => /welcome/.test(location.hash), null, { timeout: 120000 });
    await page.waitForTimeout(6000);   // SW instalado y módulos diferidos en caché
    const ref = process.env.SB_REF;
    await page.evaluate(([k, v, g]) => { localStorage.setItem(k, v); localStorage.setItem(g, 'true'); },
      [`sb-${ref}-auth-token`, session, `flutter.plobby.gate_ok.${uid}`]);
    await page.goto(url, { waitUntil: 'commit' });
    const ff = await page.evaluate(() => new Promise(r => window.addEventListener('flutter-first-frame', () => r(performance.now()), { once: true })));
    await page.waitForFunction(() => /home/.test(location.hash) && !document.getElementById('plobby-splash'), null, { timeout: 90000, polling: 50 });
    const home = await page.evaluate(() => performance.now());
    out.push({ firstFrame: Math.round(ff), home: Math.round(home), route: await page.evaluate(() => location.hash) });
    await ctx.close();
  }
  await browser.close();
  console.log(label, JSON.stringify(out));
})();
