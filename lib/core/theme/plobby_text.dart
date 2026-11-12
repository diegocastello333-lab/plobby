import 'package:flutter/painting.dart';
import 'design_tokens.dart';

/// Estilos de texto del prototipo HTML, medidos con `getComputedStyle` sobre Plobby (4).html (no a ojo).
/// Cada constante indica la clase CSS de origen. Usar estos estilos en lugar de `TextStyle(fontSize: …)` sueltos.
///
/// letterSpacing en px = em × fontSize (CSS usa em; Flutter, píxeles lógicos). Se fija SIEMPRE (también a 0): si se
/// deja en null, Material mezcla su espaciado por defecto (+0.5 px en bodyLarge) y el texto queda más ancho que en el HTML.
class PlobbyText {
  PlobbyText._();
  static const _d = AppTypography.displayFamily, _s = AppTypography.sansFamily;

  // ── Titulares (Unbounded) ──
  /// `.t1` — título de pantalla: Unbounded 28/700, lh 1.2, −0.02em.
  static const t1 = TextStyle(fontFamily: _d, fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.56, color: AppColors.text);
  /// `.t2` — subtítulo de bloque: Unbounded 17/600, lh 1.3, −0.01em.
  static const t2 = TextStyle(fontFamily: _d, fontSize: 17, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.17, color: AppColors.text);
  /// `h2.sec` — título de sección (Inicio, Ligas…): Unbounded 18/700, −0.02em.
  static const sec = TextStyle(fontFamily: _d, fontSize: 18, height: 22 / 18, fontWeight: FontWeight.w700, letterSpacing: -0.36, color: AppColors.text);

  // ── Texto (Inter) ──
  /// `.sub` — entradilla bajo el título: Inter 14/400, lh 1.4, gris.
  static const sub = TextStyle(fontFamily: _s, fontSize: 14, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.textMuted);
  /// `.eb` — etiqueta en mayúsculas («ACTIVAS», «PASO 1 DE 5»): Inter 10.5/700, +0.14em. Escribir el texto en mayúsculas.
  static const eb = TextStyle(fontFamily: _s, fontSize: 10.5, height: 13 / 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.47, color: AppColors.textMuted);
  /// `.info .k` — clave de ficha («UBICACIÓN»): Inter 10.5/700, +0.12em, mayúsculas.
  static const key = TextStyle(fontFamily: _s, fontSize: 10.5, height: 13 / 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.26, color: AppColors.textMuted);
  /// `.info .vv` — valor de ficha: Inter 14/600, lh 1.3.
  static const value = TextStyle(fontFamily: _s, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text);
  /// `.desc` — párrafo descriptivo: Inter 14/400, lh 1.5, tinta 700.
  static const desc = TextStyle(fontFamily: _s, fontSize: 14, height: 1.5, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.ink700);
  /// `.lab` — etiqueta de campo de formulario: Inter 12/700, +0.04em.
  static const label = TextStyle(fontFamily: _s, fontSize: 12, height: 15 / 12, fontWeight: FontWeight.w700, letterSpacing: 0.48, color: AppColors.text);
  /// `.inp` — texto dentro de un campo: Inter 16/400.
  static const input = TextStyle(fontFamily: _s, fontSize: 16, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.text);
  /// Texto de ayuda / error bajo un campo (`.help`, `.errt`): Inter 12.5.
  static const help = TextStyle(fontFamily: _s, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.textMuted);
  /// Botones `.pbtn` / `.obtn`: Inter 14/600.
  static const button = TextStyle(fontFamily: _s, fontSize: 14, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0);
  /// Botón pequeño `.sbtn` y filtros `.fc`: Inter 13/600.
  static const buttonSmall = TextStyle(fontFamily: _s, fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0);
  /// `.chip` — píldora: Inter 12/600.
  static const chip = TextStyle(fontFamily: _s, fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0);
  /// Enlace «Ver todas» de cabecera de sección: Inter 13/600, tinta.
  static const link = TextStyle(fontFamily: _s, fontSize: 13, height: 1, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text);
  /// `.card2 h3` — título dentro de una tarjeta: Inter 15/800.
  static const cardTitle = TextStyle(fontFamily: _s, fontSize: 15, height: 19 / 15, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text);
  /// Pestaña de `.seg`: Inter 12.5/600.
  static const tab = TextStyle(fontFamily: _s, fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0);
  /// Etiqueta de la barra inferior: Inter 12 (700 activa / 500 inactiva).
  static const navLabel = TextStyle(fontFamily: _s, fontSize: 12, height: 15 / 12, fontWeight: FontWeight.w500, letterSpacing: 0);
  /// Cifra grande de tarjeta (Inicio: amigos, ELO): Inter 22/800, −0.01em.
  static const stat = TextStyle(fontFamily: _s, fontSize: 22, height: 1, fontWeight: FontWeight.w800, letterSpacing: -0.22, color: AppColors.text);
  /// Saludo del banner de Inicio: Inter 27/800, lh 1.12, −0.01em, blanco.
  static const hello = TextStyle(fontFamily: _s, fontSize: 27, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -0.27, color: AppColors.surface);
}
