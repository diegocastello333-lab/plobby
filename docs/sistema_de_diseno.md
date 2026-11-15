# Sistema de diseño de Plobby

Guía de referencia para cualquier cambio de interfaz. Criterios: las Human Interface Guidelines de Apple (skill
`apple-design`, `.claude/skills/apple-design/references/hig/`) aplicadas a la identidad de Plobby. Las referencias citadas
van como `fichero.md › Apartado`.

## 1. Dónde vive cada cosa

| Qué | Fichero |
|---|---|
| Colores, espaciados, radios, sombras, familias tipográficas | `lib/core/theme/design_tokens.dart` |
| Estilos de texto (`PlobbyText.*`) | `lib/core/theme/plobby_text.dart` |
| Tema de Material (botones, campos, transiciones) | `lib/core/theme/plobby_theme.dart` |
| Movimiento: duraciones, muelles (`AppSprings`), hápticos (`AppHaptics`) | `lib/core/motion/app_motion.dart` |
| Piezas animadas (`Pressable`, `AppearOnce`, `SlidingTabs`, `ScrollLinkedTabs`, `LiveNumber`, `SkeletonBox`) | `lib/core/widgets/motion_widgets.dart` |
| Componentes (`PlobbyButton`, `IconSquareButton`, `PlobbyFilterChip`, `Pill`, hojas…) | `lib/core/widgets/plobby_components.dart` |
| Estados (vacío, error, carga, confirmación) | `lib/core/widgets/state_views.dart` |
| Fondo vivo de las pestañas | `lib/core/widgets/ambient_background.dart` |

Regla: nada de colores, tamaños ni curvas sueltos en las pantallas si existe un token o un componente.

## 2. Color (contraste medido, WCAG)

| Rol | Valor | Contraste | Uso |
|---|---|---|---|
| Fondo | marfil `#F6F8F1` | — | fondo de pantalla |
| Superficie | blanco `#FFFFFF` | — | tarjetas |
| Texto | tinta `#171C19` | 16,1:1 sobre marfil | texto principal |
| Texto secundario | `#5C6660` | 5,57:1 sobre marfil · 5,96:1 sobre blanco | subtítulos, metadatos |
| Marca / acción | lima `#D2F548` con texto tinta | 13,9:1 | acción principal, selección, estados |
| Texto de marca | `#5F7410` | 5,26:1 sobre blanco | texto lima legible sobre claro |
| Peligro | `#C4282E` | 5,69:1 (blanco encima) | errores, eliminar |
| Desactivado / bordes | `#8A938D` | 2,95:1 | **solo** bordes e iconos decorativos, nunca texto |

- Un color = un significado (`color.md › Best practices`). Lima = seleccionado o acción principal en TODA la app (las
  pestañas de Torneos usaban tinta; se unificaron).
- El lima se reserva para acciones y estado (`branding.md`: «Apply your app's accent color judiciously»).

## 3. Tipografía

- Unbounded (display) para títulos y cifras protagonistas; Inter para todo lo demás. Sin más familias.
- **Mínimo 11 pt** (`accessibility.md › Vision`). Lo comprueba `test/accessibility_scaling_test.dart`. Las imágenes
  para compartir (pintores) quedan fuera: miden en píxeles de imagen.
- `letterSpacing` siempre explícito (Material añade +0,5 si es null).
- **Dynamic Type**: el texto escala con el ajuste del sistema. Nada de alturas fijas en contenedores con texto: usar
  `BoxConstraints(minHeight:)`, `IntrinsicHeight`, o calcular con `MediaQuery.textScalerOf(context)`. Las cifras grandes
  usan `FittedBox(fit: BoxFit.scaleDown)`. Con texto ≥130 %, las parejas de botones se apilan.
- Excepción deliberada: las etiquetas de la barra inferior no escalan (como la barra de pestañas de iOS); cada pestaña
  tiene etiqueta para el lector de pantalla.

## 4. Espaciado, radios, sombras

- Espaciado en múltiplos de 4: 4, 8, 12, 16, 24, 32. Margen lateral de pantalla 20 (16 en hojas).
- Radios: 8 (pequeño, filtros, botones pequeños), 14 (botones, campos, tarjetas medianas), 22 (tarjetas grandes, hojas),
  píldora (999) para pestañas y etiquetas.
- Sombras: `AppShadows.card` (tarjetas), `AppShadows.pop` (elementos flotantes: aviso, menú), `AppShadows.lifted`.
- Zonas táctiles ≥ 44 × 44 pt (mínimo absoluto 28) (`accessibility.md › Mobility`).

## 5. Movimiento

| Token | Valor | Para qué |
|---|---|---|
| `AppSprings.smooth` | muelle k=170, c=26 (sin rebote) | páginas, hojas, entrada de tarjetas |
| `AppSprings.snappy` | muelle k=300, c=26 (≈2 % de rebote) | respuesta de controles: soltar botón, píldora de pestañas |
| `AppSprings.bouncy` | muelle k=260, c=16 (rebote breve) | celebraciones, «pop» del icono de pestaña |
| `AppAnimations.press` / `pressRelease` | 120 / 320 ms | pulsar (escala 97 %) / soltar con muelle |
| `AppAnimations.tab` | 320 ms | cambio de segmento |
| `AppAnimations.page` | 420 ms | `PageView` ligado a pestañas |
| `AppAnimations.branch` | 240 ms | fundido entre pestañas de la barra inferior |
| Hojas | 420 ms `smooth` / salida 240 ms | `showPlobbySheet` |

Reglas (`motion.md`): movimiento con propósito, breve, cancelable y ligado al gesto; nada que haya que esperar.
«Reducir movimiento» del sistema → sin deriva del fondo, sin desplazamientos (solo fundidos o cambios instantáneos).
Un envoltorio animado devuelve SIEMPRE la misma estructura de widgets (si no, la sección pierde su estado).

## 6. Hápticos (`AppHaptics`, un significado cada uno)

| Llamada | Cuándo |
|---|---|
| `selection()` | cambiar pestaña, segmento, filtro o interruptor |
| `tap()` | pulsar una acción principal (botón lima o tinta) |
| `success()` | acción completada (aviso de confirmación, amistad aceptada, logro) |
| `error()` | acción que no se pudo completar |

Nunca `HapticFeedback` directo. Los botones secundarios no vibran (`playing-haptics.md`: «Avoid overusing haptics»).

## 7. Estados

- **Carga**: esqueleto con la forma final (`SkeletonBox`, `LoadingBlock`), nunca una pantalla en blanco con una rueda
  (`loading.md`: «Show something as soon as possible»).
- **Vacío**: `EmptyStateCard`: icono en disco lima suave, título, una frase y la acción siguiente.
- **Error**: `ErrorStateCard`: qué pasó, cómo arreglarlo y «Reintentar». Sin bloques rojos ni disculpas.
- **Confirmación**: `showPlobbySnack`: cápsula tinta flotante con icono (✓ o !) y háptico de éxito/error; se cierra
  sola o al tocarla (`feedback.md`: confirmación en la interfaz, no en alertas).

## 8. Navegación

- Barra inferior: 4 pestañas + «+» central (crear partido). El «+» es una acción dentro de la barra, cosa que
  `tab-bars.md` desaconseja («not to provide actions»); se mantiene a propósito porque crear partido es la acción
  principal de la app y forma parte de su identidad. Las pestañas conservan su estado (StatefulShellRoute).
- Títulos grandes a la izquierda con sus acciones en la misma fila (Feed, Competiciones…). El logotipo solo en Inicio.
- Competiciones: pestañas ligadas al deslizamiento (`ScrollLinkedTabs` + `PageView`).

## 9. Pendiente

- **Modo oscuro**: los tokens oscuros existen (`AppColorsDark`) pero la app solo usa el claro. Aplicarlo exige pasar los
  colores de cada pantalla a tokens semánticos que cambien con el tema (`color.md`, `dark-mode.md`).
- Comprobar en un iPhone y un Android reales: hápticos, 60 FPS del fondo vivo y del deslizamiento de Competiciones.
