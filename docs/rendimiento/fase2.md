# Fase 2 · Fallos de la auditoría (24 nov 2026, rama `fixes`)

Capturas antes/después (375×812 y 1440×900, modo demo) en `docs/rendimiento/capturas/f2/cmp_<pantalla>_<movil|escritorio>.png`.
Tests: `test/phase2_fixes_test.dart` (14) + los existentes adaptados. `flutter analyze` sin errores ni avisos.

| # | Fallo | Causa | Arreglo |
|---|---|---|---|
| 1 | Feed: los filtros fijos no tenían fondo y se veía el contenido a través | El fondo dependía de `overlapsContent`, que en una cabecera fija no se activa de forma fiable | Se usa el desplazamiento real: al pasar contenido por debajo, material translúcido (marfil 85 % + desenfoque 20) y línea de 0,5 px. Tokens nuevos `AppMaterials.bar/barBlur/hairline` |
| 2 | El «+» central tapaba el final de las pantallas | Márgenes fijos (100–150 px) que no contaban la zona segura del iPhone (barra de 100 px + 30 px del «+») | `AppInsets.tabBarClearance(context)` = barra + zona segura + «+» + aire, en Inicio, Feed, Competiciones (ligas y torneos) y Perfil |
| 3 | Perfil: tres niveles a la vez («Nivel declarado: Iniciación», «Intermedio», «Nivel calculado 2,3») | Dos conceptos mezclados | Un solo **Nivel** en toda la app: el del ELO, «2,3 · Intermedio» (`StatsCalculator.levelLabel`). El elegido al registrarse aparece como «Nivel con el que empezaste» (secundario). Perfiles limitados (no amigos, sin ELO visible): «Nivel inicial». Onboarding: «¿Con qué nivel empiezas?» |
| 4a | Dos botones de crear liga | «Crear liga» arriba y «Crear una liga nueva» al final | Queda uno: arriba si ya tienes ligas; si no, la única acción de la tarjeta vacía |
| 4b | La pista dibujada en la tarjeta de liga no encajaba con sus bordes | El dibujo era de 390×120 y se recortaba con `cover` en tarjetas de 335×88 | `leagueCoverSvg(aspect:)` dibuja con la proporción real: pista y red relativas al alto, márgenes iguales (test con 5 proporciones) |
| 5a | «Añadir jugadores» duplicaba los campos «Elegir un amigo» | Dos flujos para lo mismo | Un único flujo: cada hueco abre el selector |
| 5b | Hora por defecto 02:26 | «Ahora + 2 h» | `defaultMatchTime`: siguiente hora en punto entre 8:00 y 23:00 (de madrugada → 19:00), o la hora a la que sueles jugar (`usualPlayHour`, la más repetida en tus partidos) |
| 5c | Sin sugerencias | — | «Sugeridos»: pareja habitual primero y luego con quién más juegas (compañeros pesan más que rivales), solo amigos/miembros; un toque llena el primer hueco libre |
| 6 | Inicio: tarjetas de distinto ancho, títulos en dos líneas, parejas cortadas | 135 : 100 : 68 px; títulos largos; nombres completos | Tres tarjetas iguales (las caras de amigos solo si caben); «De tus amigos» y «Tus partidos»; parejas como «Ana R. · Bea S.» (`shortName`) |
| 7 | Escritorio: a 1440 px todo se estiraba, incluida la barra inferior | Sin maquetación para pantallas anchas | `WideFrame` (≥ 840 px): columna centrada de 736 px con **barra lateral** (logo, «+», pestañas) y contenido de 640 px; pantallas completas, hojas y diálogos en la misma columna |
| 8 | Lector de pantalla en la web: solo «Enable accessibility» | Flutter web no crea el árbol de accesibilidad hasta que se pulsa ese botón oculto | `SemanticsBinding.ensureSemantics()` en la web. Verificado en Chromium: 31 nodos y 18 botones con nombre en el Inicio, sin el botón oculto. Todos los botones de icono tenían ya etiqueta (revisados) |
| 9 | Tooltips que aparecían al pasar el ratón y tapaban contenido | Tooltip de Material sin espera | Tema: aparecen tras 0,8 s quieto sobre el botón, debajo y pegados a él; en táctil, solo con pulsación larga (test con ratón simulado) |

## No verificado
- Lector de pantalla real (TalkBack, VoiceOver, NVDA): solo se comprobó el árbol de accesibilidad que expone Chromium.
- Safari y móviles reales.
