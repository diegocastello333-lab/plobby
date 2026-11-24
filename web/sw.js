/* Service worker de Plobby (PWA).
 *
 * Qué se guarda en caché: SOLO la propia aplicación (código, CanvasKit, fuentes, imágenes empaquetadas), en una caché
 * con el identificador de cada despliegue. Así la app abre al instante y funciona con mala cobertura.
 *
 * Qué NO se guarda nunca: nada que venga de otro origen (Supabase: datos, fotos, tiempo real, autenticación). Los
 * partidos, resultados, rankings y mensajes siempre se piden a Supabase, nunca se sirven desde caché.
 *
 * Actualizaciones: al desplegar, cambia BUILD_ID → el navegador instala este archivo de nuevo → la app muestra
 * «Hay una versión nueva» y, al aceptar, se recarga con la versión nueva. Las cachés antiguas se borran al activarse.
 */
const BUILD_ID = '__PLOBBY_BUILD_ID__';
const CACHE = `plobby-app-${BUILD_ID}`;
// Motor de Flutter (canvaskit/skwasm) y fuentes de respaldo: solo cambian al actualizar Flutter, no en cada despliegue.
// Van en su propia caché, identificada por la versión del motor, que SOBREVIVE a los despliegues de la app: tras
// publicar una versión nueva no se vuelven a descargar ~1,4 MB de motor.
const ENGINE_ID = '__PLOBBY_ENGINE_ID__';
const ENGINE_CACHE = `plobby-engine-${ENGINE_ID}`;
const isEngine = (path) => path.startsWith('/canvaskit/') || path.startsWith('/fonts/fallback/');

// La página (index.html) y los ficheros que la arrancan: primero red, para recoger despliegues nuevos.
const NETWORK_FIRST = ['/', '/index.html', '/flutter_bootstrap.js', '/app_boot.js', '/manifest.json'];
// Nunca a caché.
const NEVER = ['/sw.js', '/version.json', '/flutter_service_worker.js'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(['/', '/flutter_bootstrap.js', '/manifest.json'])).catch(() => {}));
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('plobby-app-') && key !== CACHE) await caches.delete(key);
      if (key.startsWith('plobby-engine-') && key !== ENGINE_CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

// La página pide activar la versión nueva cuando la persona pulsa «Actualizar».
self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;          // Supabase y cualquier tercero: siempre red
  if (NEVER.includes(url.pathname) || req.headers.has('range')) return;

  const isPage = req.mode === 'navigate' || NETWORK_FIRST.includes(url.pathname);
  event.respondWith(isPage ? networkFirst(req) : cacheFirst(req, isEngine(url.pathname) ? ENGINE_CACHE : CACHE));
});

async function networkFirst(req) {
  const cache = await caches.open(CACHE);
  try {
    const res = await fetch(req, { cache: 'no-store' });
    if (res.ok) cache.put(req.mode === 'navigate' ? '/' : req, res.clone());
    return res;
  } catch (e) {
    // Sin conexión: la última versión de la app (los datos de Supabase mostrarán su propio aviso de «sin conexión»).
    return (await cache.match(req.mode === 'navigate' ? '/' : req)) || Response.error();
  }
}

async function cacheFirst(req, name) {
  const cache = await caches.open(name);
  const hit = await cache.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok && res.type === 'basic') cache.put(req, res.clone());
  return res;
}
