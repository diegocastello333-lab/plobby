// Servidor local parecido a Vercel: brotli, reescritura SPA a index.html y cabeceras de vercel.json (caché incluida).
// Uso: node serve.js <dir> <puerto> [vercel.json]
const http = require('http'), fs = require('fs'), path = require('path'), zlib = require('zlib');
const [dir, port, vj] = [process.argv[2], +process.argv[3], process.argv[4]];
const cfg = vj ? JSON.parse(fs.readFileSync(vj, 'utf8')) : { headers: [] };
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.txt': 'text/plain', '.css': 'text/css' };
const cache = new Map();
function headersFor(p) {
  const out = {};
  for (const h of cfg.headers || []) {
    const re = new RegExp('^' + h.source.replace(/\(\.\*\)/g, '.*').replace(/\//g, '\\/') + '$');
    if (re.test(p)) for (const { key, value } of h.headers) out[key] = value;
  }
  return out;
}
http.createServer((req, res) => { if (process.env.LOG) console.log('REQ', req.url);
  let p = decodeURIComponent(req.url.split('?')[0]);
  let f = path.join(dir, p);
  if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { f = path.join(dir, 'index.html'); if (p !== '/' && !path.extname(p)) p = '/'; }
  const ext = path.extname(f); const h = { 'Content-Type': types[ext] || 'application/octet-stream', ...headersFor(p) };
  let body = fs.readFileSync(f);
  if (/br/.test(req.headers['accept-encoding'] || '') && !/\.(png|jpg|webp|woff2)$/.test(f)) {
    if (!cache.has(f)) cache.set(f, zlib.brotliCompressSync(body, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 9 } }));
    body = cache.get(f); h['Content-Encoding'] = 'br';
  }
  const etag = '"' + require('crypto').createHash('md5').update(body).digest('hex') + '"'; h.ETag = etag;
  if (req.headers['if-none-match'] === etag) { res.writeHead(304, h); return res.end(); }
  res.writeHead(200, h); res.end(body);
}).listen(port, () => console.log('serving', dir, 'on', port));
