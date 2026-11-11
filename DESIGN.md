# Plobby · Restyling visual (solo diseño)

Fuente única: sistema de diseño de referencia (https://claude.ai/artifact/8gFqZNpi9rASmTeZwgvkjH, `tokens.json` + README). No se ha tocado lógica, rutas, repositorios, Supabase ni providers.

## Tokens (`lib/core/theme/design_tokens.dart`)
- **Marca:** lima `#D2F548` (acción/selección) con tinta `#171C19` encima (nunca texto blanco sobre lima). Secundario: bloque tinta con texto lima. Acento azul pista `#2F6FDE` (info/reservas).
- **Fondos:** `bg #F6F8F1`, `surface #FFF`, `surfaceSunken #EEF1EA`. Bordes `#D5DAD6` / controles `#8A938D`. Texto `#171C19`, secundario `#5C6660`.
- **Estados (no lima):** éxito `#12754D`, aviso `#9A5B00`, peligro `#C4282E` (+ fondos *soft*). Tema oscuro definido en `AppColorsDark` (la app sigue en claro).
- **Tipografía:** Unbounded 700/600 solo en títulos (display-xl 40, display-l 28, title 20); Inter para todo lo demás (body 16, label 14/600, caption 13/500).
- **Forma:** radios 8 / 14 / 22 / pill; rejilla 4 px; sombra `card` y `pop`.
- **Botones:** 48 px (36 en filas densas), principal lima, secundario tinta, fantasma con borde 1,5 px, peligro rojo suave, deshabilitado hundido. Foco: anillo 2 px azul.

## Cómo se aplica sin tocar pantallas
1. `plobby_theme.dart` ahora construye el `ThemeData` completo (botones, inputs, SearchBar, chips, SegmentedButton, bottom sheets 22 px, diálogos, SnackBar, Badge, NavigationBar, AppBar, FAB, switches, progreso).
2. `PlobbyColors` se conserva como **alias** de los tokens nuevos (`forest→ink900`, `ivory→bg`, `lime→brand`, …): los widgets existentes cambian de piel sin editarse.
3. Colores sueltos con alfa se remapearon a la paleta nueva (11 archivos); chips del Feed pasan a lima/tinta; la barra de ELO usa `lime400→lime300`.
4. `AppButtonStyles` y `AppCardStyles` centralizan botones y tarjetas; `AppSpacing`, `AppRadius`, `AppShadows`, `AppTypography` completan el sistema.

## Pendiente / a verificar
- `flutter analyze` / `flutter build` no se han podido ejecutar (sin SDK aquí).
- Las fuentes Unbounded e Inter se cargan con `google_fonts` (red); para la imagen compartible exportada conviene incluirlas como assets.
- Algunos widgets conservan colores derivados con alfa (p. ej. texto marfil translúcido sobre tinta); equivalen a la paleta nueva pero no están como tokens con nombre.
- Ajustes de pantallas que no existen en este proyecto (Ajustes, Marcador en directo, Detalle de partido) no se han podido restilizar: heredarán el tema, pero revísalas en tu app.
