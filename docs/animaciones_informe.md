# Plobby · Animaciones, gamificación y acabado premium — informe final (23 nov 2026)

Rama `gamificacion-premium` (desde `seguridad-legal`, `a84f15c`). Fases aprobadas: 0, 1, 2 y 4. **La Fase 3 (mecánicas
nuevas) no se hizo**, por decisión tuya. **No hay ningún cambio en la base de datos.**

## Qué se ha hecho

### Fase 0 · Sistema de movimiento
- `lib/core/motion/app_motion.dart` es la única fuente de duraciones, curvas y vibraciones:
  - **Duraciones** (`Motion`): rápida 150 ms, normal 250 ms, énfasis 400 ms y celebración 900–1200 ms, más los bucles decorativos.
  - **Curvas**: entrar, salir, mover, muelle y muelle con rebote (este último, solo para celebraciones).
- **Reducir movimiento** (`Motion.reduced`): lee el ajuste del sistema; en Android, la escala de animaciones a 0, y en la web, `prefers-reduced-motion`.
- **Vibración** (`AppHaptics`), con un significado por tipo:
  - ligera: toques, pestañas e interruptores;
  - media: reaccionar o conseguir un logro;
  - éxito: victoria, subida de nivel o resultado guardado;
  - error: como mucho un toque ligero, nunca fuerte.
  - Siempre una sola vibración por evento.
- **Interruptor «Vibración»**: Perfil → **Ajustes y privacidad** (antes «Privacidad y datos»). Se guarda en el dispositivo.
- **Tests de control** (`test/motion_tokens_test.dart`): fallan si en la interfaz aparece una duración o una curva escrita a mano, o una vibración que no pase por `AppHaptics`. Los plazos que no son animaciones (temporizadores, esperas) se marcan con `// timing`.

### Fase 1 · Pantalla post-partido (`/match/:id/summary`)
- **Secuencia**:
  1. los sets aparecen uno a uno y los juegos cuentan;
  2. «Victoria», o «Buen partido» si pierdes (con respeto: sin la palabra «derrota» y sin usar el rojo como única señal);
  3. el ELO cuenta desde el valor anterior (`rating_history`), con el cambio flotante y la barra de categoría;
  4. la XP con su desglose (`xp_events`);
  5. los logros nuevos, que se voltean y se marcan como vistos (`seen_at`).
- **«Saltar»** está visible desde el principio, y también se puede terminar tocando cualquier parte.
- **Con «reducir movimiento»**, la pantalla muestra directamente el estado final.
- **Cuándo se abre**: al confirmar el resultado, y una sola vez por partido al ver un partido confirmado de los últimos 7 días. También desde el botón «Ver resumen del partido».
- **Imagen para compartir** en formato historia (1080×1920) o publicación.
- **Si falta un dato**, ese bloque no se muestra; no se inventa nada.

### Fase 2 · Animaciones por pantalla
| Pantalla | Animación |
|---|---|
| Subida de nivel o de categoría | Pantalla completa con confeti dibujado en código. Unos 2,4 s y una sola vez por evento. Con «reducir movimiento», sin confeti. |
| Ranking | Las filas se deslizan desde su puesto anterior y el podio sube escalonado desde la base. Tu fila se fija abajo cuando no se ve. |
| Feed | Partículas al reaccionar y contador que rueda. Doble toque = 🔥 (solo añade, nunca la quita). |
| Logros | El anillo de progreso se llena y los bloqueados llevan candado. Destello una sola vez al conseguir un logro. |
| Torneos | Las líneas de los ganadores se dibujan; corona del campeón con rebote. |
| Perfil y Mi rating | La gráfica de ELO se dibuja y las cifras de estadísticas cuentan. |
| Chat | Las burbujas entran con efecto muelle desde su esquina. |
| Introducir resultado | La casilla da un pequeño salto, con vibración ligera, al anotar un juego. |
| Estados vacíos | El icono entra con un pequeño rebote. |

## Fase 4 · Calidad y verificación

### Pruebas automáticas
- `flutter analyze`: 0 errores, 0 avisos. `flutter test`: **433/433**.
- Pruebas nuevas:
  - `motion_tokens_test.dart`: tests de control y vibración.
  - `post_match_test.dart` (16):
    - datos reales;
    - derrota respetuosa;
    - «Saltar»;
    - una vibración por evento;
    - celebración que no se repite;
    - reducir movimiento;
    - imagen sin solapes;
    - texto al 100 % y al 200 % en pantallas de 320 y 390 pt.
  - `screen_motion_test.dart`: confeti, celebración única, candado y destello, contador y doble toque.
- **Bugs reales encontrados por las pruebas y corregidos**:
  1. Marcar los logros como vistos recargaba los datos y **reiniciaba la secuencia**, que vibraba dos veces.
  2. Con «reducir movimiento» seguían quedando fundidos.
  3. **Dos desbordes** a 320 pt y con texto grande: la fila de XP y la de categoría.
  4. La fila fija del ranking se leía dos veces con el lector de pantalla.

### Capturas con y sin «reducir movimiento»
Están en `docs/capturas/movimiento/` (a mitad de animación, con la CPU ralentizada ×4), y también en `docs/capturas/post_partido/` y `docs/capturas/animaciones/`.

### Fluidez (Chrome, 390×844 a 2×, CPU ralentizada)
**Cómo**:
- Banco de pruebas `tool/motion_lab/main.dart`, que no se incluye en la app.
- Build de release para la web y Playwright con `Emulation.setCPUThrottlingRate`.
- Se miden los fotogramas reales del navegador durante 6 s.
- Scripts y resultados en `tool/motion_lab/perf/`.

Fotogramas por segundo de media (60 = perfecto):

| Escena | CPU normal | CPU ×4 | CPU ×6 | ×4 con reducir movimiento | Antes de estas fases (×1 / ×4) |
|---|---|---|---|---|---|
| Ranking | 51 | 43 | 38 | 47 | 51 / 43 |
| Logros | 53 | 46 | 41 | 50 | 55 / 46 |
| Celebración | 49 | 34 | 30 | 53 | — (nueva) |
| Post-partido (secuencia de 5 s) | 32 | 7,5 | 5 | 45 | — (nueva) |
| Mi rating | 26 | 8 | 6 | 48 | 25 / 8 |
| Feed (desplazándose) | 21 | 5 | 3 | 8 | 22 / 4 |

**Qué significan estas cifras (importante)**:
- **El entorno de medida no tiene GPU.** Chrome dibuja todo con la CPU y, según el perfilador, **el 74 % del tiempo** se va en copiar cada fotograma a la pantalla (`createImageBitmap`), no en el código de la app.
- **El código Dart de las animaciones** (construir, maquetar y pintar) cuesta unos **2,5 ms por fotograma**, más unos 2 ms de dibujo de Skia.
- En un móvil Android **ese trabajo no pasa por el navegador**: la app va compilada y el dibujo lo hace la GPU en otro hilo. Estas cifras **no son las del móvil** y **no demuestran 60 fps en un Android de gama baja (ni lo contrario)**.
- **Mi rating y Feed ya iban igual antes** de este trabajo (columna «Antes»), así que la lentitud medida no la han introducido estas fases.
  - En Mi rating, el coste viene del brillo en bucle de la barra de ELO, que ya existía: con «reducir movimiento» sube a 48 fps.
  - En Feed, el coste es el propio desplazamiento.
- **Optimizaciones hechas tras medir**:
  - la pantalla post-partido ya no se reconstruye entera en cada fotograma (de 24,5 a unos 32 fps a CPU normal);
  - cada bloque, y cada set dentro de la tarjeta de resultado, se redibuja solo durante su propio tramo y con su propia capa.

**Lo que falta para confirmar los 60 fps**: probarlo en un Android de gama baja real con `flutter run --profile` y el monitor de rendimiento de DevTools. Hay que mirar sobre todo el resumen post-partido, la celebración y el ranking. Aquí no hay ningún móvil disponible.

## Pendiente o descartado (con motivo)
- **Tirar para recargar con una pelota que bota**: no hecho. Con lo que trae Flutter no se puede personalizar bien, y hacerlo a mano en Android es frágil. Sigue el indicador actual.
- **Fondo del perfil con efecto de profundidad y paso animado del avatar entre pantallas**: no hechos, para no arriesgar la navegación (el avatar aparece en muchas listas a la vez).
- **«Escribiendo…» en el chat**: necesita un cambio en la base de datos (política de Realtime), y en esta tarea acordamos no tocarla.
- **Sonidos**: no hay; solo vibración, como se acordó.
- **Modo oscuro**: fuera de alcance.
- **Doble toque en las publicaciones**: un toque simple sobre el contenido (por ejemplo, abrir el partido) tarda unos 0,3 s más en responder, porque Flutter espera a saber si viene un segundo toque.
- **Prueba en un móvil real** (fluidez, vibración y «reducir movimiento» del sistema): pendiente.

## Qué pediría a un diseñador (opcional)
1. Una **ilustración o animación propia de celebración** (Rive o Lottie) que sustituya al confeti genérico. Hoy todo se dibuja en código para no añadir dependencias.
2. **Iconos de logros específicos**: hoy los 20 logros comparten unos pocos iconos (trofeo, llama, lupa…).
3. **Una corona** con el estilo de los iconos de la app (la actual es una forma sencilla dibujada en código).
4. Revisar los textos del resumen tras una derrota («Buen partido», «Se decidió por detalles…») con el tono de la marca.
