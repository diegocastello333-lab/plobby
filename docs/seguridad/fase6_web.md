# Plobby · Fase 6: web

## Cabeceras (vercel.json, para todas las rutas)
| Cabecera | Valor |
|---|---|
| Content-Security-Policy | `default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://niwognkvoifrvlizcdvb.supabase.co; font-src 'self' data:; connect-src 'self' blob: data: https://niwognkvoifrvlizcdvb.supabase.co wss://niwognkvoifrvlizcdvb.supabase.co; worker-src 'self' blob:; manifest-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; frame-src 'none'; upgrade-insecure-requests` |
| Strict-Transport-Security | `max-age=63072000; includeSubDomains` (2 años). Sin `preload`: es un compromiso difícil de deshacer; se puede añadir con el dominio definitivo |
| X-Frame-Options | `DENY` (y `frame-ancestors 'none'` en la CSP) |
| X-Content-Type-Options | `nosniff` |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| Permissions-Policy | cámara, micrófono, ubicación, pagos, USB, sensores… desactivados; pantalla completa y portapapeles solo para Plobby |
| Cross-Origin-Opener-Policy / Resource-Policy | `same-origin` |

- `'wasm-unsafe-eval'` es necesario para el motor gráfico de Flutter (CanvasKit, WebAssembly); **no** permite `eval()` de JavaScript.
- `'unsafe-inline'` solo para **estilos** (Flutter crea etiquetas `<style>`); los **scripts en línea están prohibidos**: el
  script que había en `index.html` se ha movido a `web/app_boot.js`.
- Solo HTTPS: Vercel redirige HTTP→HTTPS y HSTS hace que el navegador no vuelva a intentar HTTP.

## Verificación (build real `flutter build web --release`, servido con estas mismas cabeceras, Chromium 390×844)
- **0 violaciones de CSP**, 0 errores ni avisos en consola; la app pinta la bienvenida.
- «Continuar con Google» lleva a `accounts.google.com` (el inicio de sesión no se rompe).
- Al abrir la web solo se contacta con el propio dominio: **ningún tercero** (ni fuentes de Google, ni CDN, ni analítica).
- **Secretos en el JS**: solo la clave publicable (`sb_publishable_…`) y la URL. Las dos apariciones de «sb_secret_» son el
  código de la librería que comprueba prefijos de claves; no hay ninguna clave secreta ni `service_role`.
- Test automático `test/web_security_headers_test.dart`: si alguien quita una cabecera, relaja la CSP o añade un script en
  línea o un recurso externo, el test falla.

## Cookies (criterio de la AEPD)
Inventario real en el navegador:
- **Cookies: ninguna** (ni propias ni de terceros).
- Antes de iniciar sesión: localStorage vacío. Al iniciar sesión, `supabase_flutter` guarda en localStorage la sesión
  (`sb-…-auth-token`) y, durante unos segundos, el verificador PKCE del login. Son **imprescindibles** para el servicio
  que el usuario pide expresamente (estar conectado).
- Cache Storage del service worker: solo los archivos de la propia app (para cargar rápido y funcionar sin conexión).

Según la Guía sobre el uso de las cookies de la AEPD, el almacenamiento estrictamente necesario para prestar un servicio
solicitado por el usuario está **exento de consentimiento**. Al no haber cookies analíticas, publicitarias ni de terceros,
**no hace falta banner de consentimiento** (un botón «Rechazar» no tendría nada que rechazar). Basta con la **Política de
Cookies** informativa (Fase 7), enlazada desde la bienvenida y los ajustes.
**Si en el futuro se añade analítica o publicidad**, habrá que poner un banner con «Aceptar» y «Rechazar» al mismo nivel y no
cargar esos scripts antes del consentimiento (y ampliar la CSP).

**Corrección (23 nov 2026):** `connect-src` incluye `blob:` y `data:`. Al elegir una foto de la galería en la web, el
selector de imágenes la entrega como URL `blob:` y la app la lee con una petición a esa URL; sin `blob:` la CSP la
bloqueaba y no se podía subir la foto (onboarding, Editar perfil, portada de torneo, imagen de grupo). `blob:`/`data:` son
datos locales del propio navegador: no abre conexiones a terceros.
