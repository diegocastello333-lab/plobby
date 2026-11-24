# Fase 3 · Sistema de diseño premium (estilo Apple) (24 nov 2026, rama `premium`)

Capturas antes/después (375×812 y 1440×900, modo demo): `docs/rendimiento/capturas/f3/cmp_<pantalla>_<movil|escritorio>.png`.
Tests: 471/471. `flutter analyze` sin errores ni avisos.

## Hecho
**3.1 Tipografía** (`PlobbyText`)
- Escala tipo iOS: `largeTitle` 34, `title1` 28 (= `t1`), `title2` 22 (= `sec`), `headline` 17 semibold, `body` 17,
  `callout` 16, `subhead` 15, `footnote` 13, `caption` 12.
- Unbounded solo en títulos grandes de pantalla y cifras (ELO, marcadores, posiciones). Los títulos de sección (`sec`,
  `t2`, `SectionHeader`), las cabeceras de barra y las etiquetas que usaban Unbounded pasan a Inter 700.
- Cifras con dígitos tabulares (`PlobbyText.tabular`) en contadores, ELO y rachas.

**3.2 Color**
- Lima como acento; el perfil deja de ser un gran bloque negro: cabecera clara, y el único elemento oscuro es la
  tarjeta de ELO. En el feed, logros y rachas pasan a tarjeta clara; el formato oscuro queda para el campeón de torneo.
- Contraste AA medido (fórmula WCAG): gris sobre marfil 5,57:1; gris sobre chip 5,22:1; tinta sobre lima 13,9:1; pie de
  tarjeta 11,2:1. Las etiquetas inactivas de la barra translúcida bajaban a 3,9:1 sobre una tarjeta oscura → barra al
  90 % (peor caso 4,86:1).
- Modo oscuro: en su propia fase (decisión tuya).

**3.3 Superficies**
- Radios: solo 12 / 16 / 24 (`AppRadius`), con esquinas continuas (`RoundedSuperellipseBorder`, `AppShapes`) en
  tarjetas, botones y hojas.
- Una sola sombra sutil en tarjetas, sin borde a la vez.
- Rejilla de 8 pt y márgenes laterales de 20.
- Barra inferior y barras fijas con material translúcido (blanco/marfil + desenfoque 20) y línea de 0,5 px; el contenido
  pasa por debajo.

**3.4 Navegación**
- «+» = pestaña central con un botón cuadrado lima de 44 px sin etiqueta (opción A elegida, sin «Nuevo»), también en la
  barra lateral de escritorio. Ya no flota ni tapa contenido.
- Iconos de contorno en las pestañas inactivas y rellenos en la activa, con etiqueta.
- Hojas: asa de 36×5, esquinas de 24 continuas.
- Transición tipo iOS (deslizamiento con la pantalla anterior desplazándose detrás y gesto de borde) en todas las
  plataformas; en Android además el «atrás predictivo» del sistema (`enableOnBackInvokedCallback`). Web: el botón atrás
  del navegador lo gestiona GoRouter en todas las rutas.

**3.5 Jerarquía**
- Perfil: cabecera clara y compacta, una acción principal (lima) y una secundaria (blanca), nivel único.
- Feed: tarjetas compactas; logros seguidos agrupados («Jacobo y 2 amigos más han desbloqueado logros», se despliega con
  un toque); reacciones discretas: solo las que tiene la publicación + un botón (toque = 🔥, pulsación larga = las cinco).
- Competiciones: tu liga activa (posición y progreso) primero; resumen y «Descubrir» (con buscador) debajo.
- Crear partido: una sola pantalla limpia (sugeridos → jugadores → fecha, hora y club → resultado opcional) con el botón
  principal fijo abajo y el error justo encima.

**3.6 Movimiento y respuesta**
- Pulsación: escala 0,97 en 100 ms (`Motion.press`) en botones y tarjetas.
- Transición compartida (Hero) del ELO: del Inicio al detalle del rating.
- Vibración suave al crear partido y al reaccionar (ya existía en reaccionar y victorias); se puede desactivar en Ajustes.
- Esqueletos solo si la carga pasa de 300 ms (`Motion.skeletonDelay`).
- Duraciones y curvas solo de `app_motion.dart` (150 / 250 / 400 ms ya existían; añadidos `press` 100 y `skeletonDelay`).

## No hecho / diferencias
- **Títulos grandes que se encogen al hacer scroll** (`SliverAppBar` large title): no aplicados; las cabeceras actuales
  (Feed, Competiciones) tienen estructura propia y el cambio afecta a muchos tests de pantalla. Propuesto para la fase de
  pulido junto al modo oscuro.
- **Hero del avatar y de la tarjeta de partido**: el mismo jugador o partido aparece varias veces en una misma pantalla
  (feed, listas) y dos Hero con la misma etiqueta en una ruta hacen fallar la navegación. Solo se ha hecho el del ELO,
  que es único.
- **Listas agrupadas tipo iOS**: Ajustes y la ficha del perfil ya lo eran; el detalle de partido no se ha reestructurado.
- **Estados vacíos con ilustración**: siguen con icono + una acción (no hay ilustraciones de marca disponibles).
- Inicio: se mantuvo la estructura (banner + tres tarjetas iguales + próximos partidos con una sola acción).
