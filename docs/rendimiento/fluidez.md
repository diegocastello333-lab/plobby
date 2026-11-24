# Fluidez (24 nov 2026, rama `fluidez`)

Queja: «antes iba mucho más fluido». Comprobado con medidas, no a ojo: trabajo de Flutter por interacción (perfil de CPU
de una build `--profile`, mismos gestos) frente a la versión anterior al encargo (`backup/web-v4-antes-de-rendimiento`).

| Interacción | Antes del encargo | Al empezar hoy | Tras optimizar |
|---|---|---|---|
| Scroll del Feed (trabajo de Flutter) | 352 ms | 834 ms | 476 ms (+ cabecera fija sin reconstruir) |
| Cambio de pestañas | 709 ms | 1221 ms | 765 ms |
| Scroll de Inicio | — | 362 ms | 117 ms |
| Competiciones | — | 570 ms | 206 ms |
| Hilo principal ocupado al hacer scroll en el Feed (web) | 10,9 s | 10,9 s | **1,4 s** |
| Fotogramas del hilo principal en el Feed (web) | 15 fps, p95 150 ms | 17 fps | **60 fps, p95 16,7 ms** |

(Entorno sin GPU: la GPU por software limita los fotogramas que se pintan; lo que se compara es el trabajo y lo libre
que queda el hilo donde llegan los toques.)

## Causas y arreglos
1. **Árbol de accesibilidad siempre activo en la web** (fase 2): ~40 % del trabajo de cada fotograma (actualizar cientos
   de nodos del DOM al desplazar). Ahora bajo demanda: botón «Activar lector de pantalla», invisible salvo con foco, el
   primero que encuentran VoiceOver/TalkBack/NVDA y el teclado; se recuerda en el dispositivo (`core/a11y/web_a11y*.dart`).
2. **Desenfoque en vivo** de la barra de pestañas, la barra de filtros del Feed, la de Crear partido y los botones de
   cristal del Inicio: se recalculaba en cada fotograma. `FrostedBar` + `AppMaterials.blur` (falso por defecto; las
   barras son opacas, que translúcidas sin desenfoque dejaban ver el texto de debajo).
3. **Cabeceras fijas** (filtros del Feed, pestañas del Perfil y de la liga) reconstruidas en cada fotograma de scroll:
   ahora la misma instancia en su propia capa.
4. **Bucles decorativos infinitos en el móvil** (fondo ambiente, brillo del sello, halo del ELO, racha): pasan 3 veces y
   se quedan quietos, como ya hacían en la web. El fondo sigue cambiando de color con las pestañas.
5. **Web aislada** (`Cross-Origin-Embedder-Policy: credentialless` junto al COOP que ya había): el motor wasm pinta en un
   hilo aparte en Chrome/Edge/Android. Comprobado contra Supabase real: fotos del almacenamiento, API e inicio con Google.
   Safari no admite `credentialless`: allí sigue como antes (sin romper nada).

## No verificado
- En un móvil real (Android/iPhone): la mejora del hilo aparte depende del navegador; Safari no la tiene.
- `test/fluidity_test.dart` vigila que estas decisiones no se deshagan sin querer.
