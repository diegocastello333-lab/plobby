# Fase 4 · Verificación final (24 nov 2026, rama `verificacion`)

Cierra el encargo «Rendimiento, corrección de fallos y rediseño premium» (fases 1, 2, 3 y 3b).

## Capturas (claro y oscuro · móvil 375×812 · tableta 768×1024 · escritorio 1440×900)
`capturas/f4/sheet_<claro|oscuro>_<movil|tableta|escritorio>.jpg`: splash, bienvenida, inicio, feed, competiciones,
detalle de liga, perfil, crear partido, mensajes y chat (60 capturas). Splash y bienvenida desde producción (sin sesión);
el resto desde la build de demostración (datos de ejemplo), con el mismo código que producción.
- Tableta (768 px) usa la disposición de móvil a todo el ancho; desde 840 px se usa la columna con barra lateral.
- La bienvenida es oscura en los dos modos (diseño original) y el splash lima en los dos (marca).

## Métricas finales
| Métrica | Antes (inicio del encargo) | Ahora |
|---|---|---|
| 1.ª visita a la web, contenido útil (4G lento + CPU 4×, producción) | 24,7 s | **20,8 s** |
| 2.ª visita sin sesión (producción) | 4,6 s | **2,8 s** |
| 2.ª visita con sesión (local) | no medible | 3,6–4,1 s (fase 1; hoy la medición dio timeout) |
| Descarga de la 1.ª visita | 3.869 KB | 3.178 KB |
| Splash | 2,8 s mínimo | ≤ 0,9 s; sin splash con sesión ya validada |
| Peticiones del Inicio | 16 | 15 |
| APK | 68,7 MB universal | **25,3 MB** arm64 · 23,4 MB armv7 |
| `flutter analyze` / tests | 0 / 433 | 0 / **479** |

Objetivos que NO se cumplen (explicado en la fase 1): 1.ª visita < 3 s en 4G lento (el motor de Flutter web pesa
~3 MB: imposible a 1,6 Mbps) y 2.ª visita < 1 s. Arranque en frío de Android: no medible aquí (sin dispositivo).

## Lector de pantalla
Revisado con el árbol de accesibilidad de Chromium (lo que lee VoiceOver/TalkBack en la web) en las 8 pantallas con
datos (`capturas/f4/a11y_*.txt`). No hay TalkBack ni VoiceOver en este entorno.
- 0 botones sin nombre en todas las pantallas.
- Corregido: nombres leídos dos veces («Volver Volver», «Enviar Enviar», «Ver todas Ver todas»…): el tooltip ya no
  repite la etiqueta (`IconSquareButton`, `MiniAction`, `SectionLink` y 4 botones sueltos).
- Corregido: los encabezados se fusionaban con lo que tenían al lado («Cerrar Partido amistoso Crear partido Cerrar»):
  ahora son nodo propio (34 encabezados). El nombre del perfil es encabezado.
- Queda: el chat no tiene encabezado propio (el título es el botón «Perfil de …», que sí se anuncia).

## Lo que no se ha hecho
- Pruebas en un móvil real (Android/iPhone), con VoiceOver/TalkBack reales ni con la app nativa en modo oscuro.
- `home_summary` (una sola llamada para el Inicio): requiere migración; pendiente de tu decisión.
- Miniaturas en servidor (transformaciones de imagen de Supabase): no disponibles en el plan actual (403).
- Firma propia del APK: sigue firmado con la clave de depuración.
- Títulos que se encogen solo en Competiciones (ver fase 3b por qué no en Feed/Inicio/Perfil).
- Pendientes anteriores sin cambios: proveedor de geocodificación, 7 posibles clubes duplicados, migración
  `20261128b_profile_visibility`, textos legales definitivos.
