# Fase 3b · Modo oscuro (24 nov 2026, rama `dark`)

## Qué hace
- La app sigue el modo del sistema (claro/oscuro) en Android, iOS y web; cambia en vivo al cambiarlo en el sistema.
- Mismos tokens de siempre: `AppColors.bg/surface/text/textMuted/…` son ahora valores que dependen del modo
  (`AppColors.isDark`). Paleta oscura en `AppColorsDark` (fondo ink950, superficies ink900/ink800, texto F2F5EF).
- Lima sigue siendo el color de acción. **Sobre lima siempre tinta** (`brandInk`), en los dos modos.
- Nuevo token `textBody` (descripciones y explicaciones): ink700 en claro, C9D0CB en oscuro.
- Bloques que son oscuros por diseño (tarjeta ELO, «Racha actual», escala de Mi rating) usan colores fijos (`ink50`),
  no los semánticos: no se invierten.
- Imágenes para compartir: se dibujan siempre en claro (`AppColors.light`), sea cual sea el modo del móvil.
- Web: `color-scheme: light dark`, dos `theme-color` (barra del navegador) y fondo de carga oscuro.

## Títulos grandes que se encogen (pendiente de la fase 3)
- `core/widgets/collapsing_title.dart` (`CollapsingTitleScaffold`): Unbounded 28 a la izquierda → Inter 17 centrado
  tras 48 px de desplazamiento vertical; con «reducir movimiento» cambia de golpe. Aplicado en Competiciones
  (también funciona dentro del PageView Ligas | Torneos).
- No aplicado en Feed: sus filtros van fijos arriba y el título ya es pequeño al desplazar; en Inicio y Perfil la
  cabecera es parte del contenido (banner, tarjeta de identidad).

## Problemas encontrados en las capturas y corregidos
- Texto blanco sobre botones lima (Aceptar, Crear liga, Compartir mis stats, Unirme, chip «Puntos», crear partido).
- Textos de cuerpo casi invisibles (notificaciones, Mi rating, bio del perfil, descripción y tabla de la liga):
  usaban `ink700` fijo → `textBody`.
- Chips del onboarding sin seleccionar con texto tinta sobre superficie oscura.
- Etiquetas de la escala de Mi rating invisibles en oscuro; además «Intermedio» y «Avanzado» se solapaban a 375 px
  (fallo previo, también en claro): cada etiqueta llega como mucho hasta la siguiente marca.

## Verificación
- `flutter analyze` 0 errores/avisos · `flutter test` 479/479.
- `test/dark_mode_test.dart`: contraste AA de los pares oscuros, cambio de modo en vivo, pestañas sin excepciones,
  texto de botones lima = tinta (≥4,5:1), `textBody` ≥7:1, y ningún `ink700` fijo en pantallas.
- `test/collapsing_title_test.dart`: interpolación, vuelta arriba y «reducir movimiento».
- Modo claro: capturas idénticas píxel a píxel a las anteriores (salvo zonas animadas).
- Capturas: `capturas/f3b/` (14 pantallas en oscuro a 375×812 y `claro_vs_oscuro.png`).
- No verificado en un móvil real.
