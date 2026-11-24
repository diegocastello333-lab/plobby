// Plobby · arranque de la página (antes en línea en index.html; fuera de línea para que la CSP prohíba scripts en línea).

// Apariencia: oscuro por defecto; claro si el usuario lo eligió en la app (shared_preferences guarda «flutter.plobby.theme»
// como texto JSON) o si eligió «Como el sistema» y el sistema está en claro.
(function () {
  var pref = 'dark';
  try { pref = JSON.parse(localStorage.getItem('flutter.plobby.theme') || '"dark"'); } catch (e) {}
  var light = pref === 'light' || (pref === 'system' && window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches);
  if (light) {
    document.documentElement.classList.add('light');
    var m = document.getElementById('plobby-theme-color');
    if (m) m.setAttribute('content', '#F6F8F1');
  }
})();
// Quita la pantalla de carga cuando Flutter pinta su primer fotograma (la app muestra entonces su propio splash).
window.addEventListener('flutter-first-frame', function () {
  var s = document.getElementById('plobby-splash');
  if (!s) return;
  s.classList.add('done');
  setTimeout(function () { s.remove(); }, 400);
});

// Service worker propio (ver sw.js): solo la app va a caché, nunca los datos de Supabase.
if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost')) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').then(function (reg) {
      var banner = document.getElementById('plobby-update');
      function offer(worker) {
        if (!worker || !navigator.serviceWorker.controller) return;   // primera instalación: nada que actualizar
        banner.classList.add('show');
        document.getElementById('plobby-update-btn').onclick = function () { worker.postMessage('skipWaiting'); };
      }
      if (reg.waiting) offer(reg.waiting);
      reg.addEventListener('updatefound', function () {
        var w = reg.installing;
        w && w.addEventListener('statechange', function () { if (w.state === 'installed') offer(w); });
      });
      // Al volver a la app (desde otra app o la pantalla de inicio), buscar si hay un despliegue nuevo.
      document.addEventListener('visibilitychange', function () { if (!document.hidden) reg.update(); });
    });
    // Recargar solo cuando se sustituye una versión anterior (en la primera instalación no hace falta).
    var hadController = !!navigator.serviceWorker.controller, reloading = false;
    navigator.serviceWorker.addEventListener('controllerchange', function () {
      if (reloading || !hadController) return;
      reloading = true;
      location.reload();
    });
  });
}
