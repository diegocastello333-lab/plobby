# Fase 1 · Rendimiento (24 nov 2026, rama `perf`)

## Cómo se ha medido
- **Web**: Chromium (Playwright) emulando un Pixel 7, red **4G lento** (1,6 Mbps de bajada, 750 kbps de subida, 150 ms de
  latencia) y **CPU 4× más lenta** (móvil de gama media). Mediana de 3 cargas. «Contenido útil» = la app ha salido de la
  pantalla de carga y se ve la primera pantalla real (Bienvenida sin sesión, Inicio con sesión).
- La base («antes») se midió dos veces: contra **producción real** (https://plobby.vercel.app) y con la misma build servida
  en local con las cabeceras de `vercel.json` y Brotli. Las cifras «después» son del servidor local (aún no está
  desplegado). En producción todo es algo más lento que en local por la latencia del CDN.
- **Peticiones del Inicio**: `test/home_requests_test.dart` abre la app completa con sesión usando los repositorios REALES de
  Supabase contra un servidor simulado y cuenta cada petición. La misma prueba se ejecutó sobre la versión anterior.
- Scripts en `tool/perf/` (`measure.js`, `measure_session.js`, `breakdown.js`, `serve.js`, `shots.js`; no forman parte de la app).

## Resultados

| Métrica | Antes | Después |
|---|---|---|
| Descarga de la primera visita (Brotli, Chrome) | 3.285 KB (3.869 KB medidos en Vercel) | **2.982 KB** |
| 1.ª visita, primer fotograma | 17,2 s (22,0 s en producción) | **9,2 s** |
| 1.ª visita, contenido útil | 19,9 s (24,7 s en producción) | **10,4 s** |
| 2.ª visita sin sesión (Bienvenida) | 4,2 s (4,6 s en producción) | **2,1 s** |
| 2.ª visita con sesión (Inicio) | no medible aquí¹ | **3,6–4,1 s** |
| Pantalla de carga (splash) | 2,1 s de animación fija + 0,7 s mínimo + espera al servidor | ≤ 0,9 s; **sin splash** si la sesión ya se validó en ese dispositivo |
| Peticiones del Inicio | 16 (`get_my_profile` ×2, historial de ELO de 500 filas) | **15** (sin duplicados, 20 filas) |
| Avatar en una lista | foto entera, 60–250 KB | **miniatura de 96 px** (~4 KB); 256 px en el perfil (~15 KB) |
| Banner del Inicio | JPEG 230–310 KB; se descargaban 2 | **WebP 142–237 KB**; 1 (la siguiente solo si el cambio de franja está a < 20 min) |
| APK Android | 68,7 MB (universal) | **25,2 MB** (arm64-v8a) · 23,3 MB (armeabi-v7a) |
| Arranque en frío Android | — | no medible aquí² |

¹ La versión anterior no muestra el Inicio hasta que el servidor valida la sesión y el onboarding; con la sesión de prueba
(no firmada) se queda esperando, así que no hay cifra comparable. La nueva pinta el Inicio sin esperar al servidor.
² No hay móvil ni emulador con aceleración en este entorno. Cómo medirlo: `adb shell am start -W -n io.plobby.plobby/.MainActivity`
(campo `TotalTime`, 3 veces en frío tras `adb shell am force-stop io.plobby.plobby`).

### Objetivos que NO se cumplen (y por qué)
- **Primera visita < 3 s en 4G lento**: imposible para cualquier app Flutter web en esa red. Solo el motor gráfico (skwasm)
  pesa 1,35 MB comprimido; a 1,6 Mbps, transferir los 2,9 MB mínimos lleva ~15 s antes de ejecutar nada. Se ha reducido a
  la mitad (19,9 → 10,4 s). En 4G normal (≥ 9 Mbps) la transferencia baja a ~3 s.
- **Segunda visita < 1 s**: 2,1 s sin sesión y 3,6–4,1 s con sesión, con la CPU limitada 4×. El primer fotograma con
  todo en caché tarda ~1,0 s (sin sesión) y ~2,5 s (con sesión: el Inicio es más pesado de construir que la Bienvenida).

## Qué se ha cambiado
**Web**
- Build **WebAssembly** (`--wasm`, motor skwasm) con **carga diferida** (`--enable-wasm-deferred-loading`). Comparado en las
  mismas condiciones: contenido útil 19,9 s (JavaScript + CanvasKit) → 10,4 s (wasm). Safari < 18.2 y navegadores sin
  WasmGC siguen usando la versión JavaScript (se generan las dos). Requirió `flutter_secure_storage` 9 → 10 (la web de la 9
  usaba `dart:html`); en Android migra sola la sesión guardada (`migrateWithBackup`).
- **Pantallas en carga diferida** (`DeferredScreen`): torneos, compartir partido/stats, Wrapped, ranking, ajustes de
  privacidad, documentos legales, editar perfil, detalle del ELO, crear/gestionar/descubrir ligas, clubes. Código inicial
  4,73 → 4,40 MB sin comprimir; el paquete `image` (437 KB) ya no se descarga al abrir. En la web se precargan en segundo
  plano 4 s después del primer fotograma; en Android se registran al arrancar (sin coste).
- **Fuentes**: fuera Roboto (85 KB que el motor descargaba siempre; «Roboto» apunta ahora al mismo fichero de Inter) y
  Unbounded Medium (no se usaba). Fuentes empaquetadas, sin `google_fonts`.
- **Pantalla de carga HTML**: ya existía (fondo lima + logo, sin pantalla en blanco).
- **Caché**: el service worker guarda el motor (`canvaskit/`, fuentes de respaldo) en una caché propia por versión del motor
  que **sobrevive a los despliegues** (tras publicar, no se vuelven a bajar ~1,4 MB). Cabeceras: `immutable` solo en las
  fuentes de respaldo (rutas versionadas). Flutter no pone huella en el nombre de `main.dart.*` ni de `canvaskit/*`, así que
  NO pueden ser `immutable` sin riesgo de servir código viejo; se revalidan (`no-cache`, respuesta 304 de pocos bytes) y las
  visitas repetidas las sirve el service worker. `--web-content-hash` existe pero es incompatible con la carga diferida.
- Se probó **precargar** `main.dart.wasm` y `skwasm.wasm` desde el HTML: el cargador de Flutter no reutiliza la precarga y se
  descargaban dos veces (2,8 MB → primer fotograma 15,9 s). Descartado.

**Splash e Inicio**
- Splash: animación de 2,1 s → 0,9 s, sin espera mínima; se va en cuanto termina la carga real. Con sesión ya validada en
  el dispositivo (`GateCache`) se entra **directo al Inicio**; la guardia se comprueba en segundo plano y redirige si cambia
  algo (p. ej. nueva versión de los Términos).
- Inicio: historial de ELO de 500 → 20 filas (`myRatingSummaryProvider`; el detalle del ELO sigue pidiendo el completo);
  `get_my_profile` una sola vez (lectura compartida 5 s en `SupabaseAuthRepository`).
- **Stale-while-revalidate** (`HomeSnapshot`): nombre, foto, banner, ELO, racha y nº de amigos se guardan en el dispositivo
  y se pintan al instante; se actualizan al llegar los datos. Por privacidad NO se guardan mensajes ni notificaciones.

**Imágenes**
- Las transformaciones de imagen de Supabase **no están activas en el plan actual** (`403 FeatureNotEnabled`). Por eso, al
  subir una foto la app genera dos miniaturas JPEG (96 y 256 px, `<foto>_t96.jpg` / `_t256.jpg`) y `NetImage` elige la
  adecuada según el tamaño en pantalla (si falta, carga la original). Las fotos ya subidas se completan solas una vez, la
  próxima vez que su dueño abra la app. El selector ya limitaba las fotos a 768 px.
- Banners: WebP (−32 %) y solo la franja visible.

**Android**
- APK por arquitectura (`--split-per-abi`), ofuscado, R8 (ya estaba). Al arrancar solo se leen las preferencias locales y
  se inicializa Supabase; lo demás va después del primer fotograma.

**Fallo encontrado y arreglado**: el servicio de presencia («En línea») no se liberaba al cerrar sesión o cambiar de
cuenta: el latido de la sesión anterior seguía enviándose cada 30 s hasta reiniciar la app.

## Pendiente de tu decisión: `home_summary`
Las 15 peticiones del Inicio salen **en paralelo** (≈ 1–2 viajes de red con HTTP/2); lo que retrasaba de verdad el Inicio era
la cadena en serie splash → guardia → Inicio, ya eliminada. Agruparlas en una RPC `home_summary` exige una migración y
reescribir la lectura de 8 repositorios (amigos, notificaciones, conversaciones, ELO, logros, perfil, feed, partidos) para
alimentar sus proveedores desde un único JSON. Ganancia estimada: ~0,3–0,6 s en 4G con sesión. Propuesta: dejarlo para
después de las fases 2 y 3 y decidir con datos reales de un móvil.

## No hecho en esta fase
- Caché de imágenes en disco en Android (requiere una dependencia nueva, p. ej. `cached_network_image`).
- Interfaz optimista nueva: las reacciones ya lo eran; comentarios y mensajes siguen esperando al servidor.
- Medición en Safari real e iPhone, y arranque en frío en un Android real.
