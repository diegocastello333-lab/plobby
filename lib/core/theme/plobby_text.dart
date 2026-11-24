import 'dart:ui' show FontFeature;
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
  static TextStyle get t1 => TextStyle(fontFamily: _d, fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.56, color: AppColors.text);
  /// Título de bloque o de formulario («Mis ligas», «Crear partido»): Inter 20/700 (Title 3 de iOS, algo más firme).
  static TextStyle get t2 => TextStyle(fontFamily: _s, fontSize: 20, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.text);
  /// Título de sección (Próximos partidos, Logros…): Inter 22/700 (Title 2). Unbounded queda para títulos de pantalla y cifras.
  static TextStyle get sec => TextStyle(fontFamily: _s, fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, letterSpacing: -0.44, color: AppColors.text);

  // ── Escala tipográfica (inspirada en iOS). Unbounded SOLO en títulos grandes y cifras destacadas. ──
  /// Large Title 34: título grande de pantalla.
  static TextStyle get largeTitle => TextStyle(fontFamily: _d, fontSize: 34, height: 41 / 34, fontWeight: FontWeight.w700, letterSpacing: -0.68, color: AppColors.text);
  /// Title 1 28 (= [t1]).
  static TextStyle get title1 => t1;
  /// Title 2 22 (= [sec]).
  static TextStyle get title2 => sec;
  /// Headline 17 semibold.
  static TextStyle get headline => TextStyle(fontFamily: _s, fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: AppColors.text);
  /// Body 17.
  static TextStyle get body => TextStyle(fontFamily: _s, fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w400, letterSpacing: -0.2, color: AppColors.text);
  /// Callout 16.
  static TextStyle get callout => TextStyle(fontFamily: _s, fontSize: 16, height: 21 / 16, fontWeight: FontWeight.w400, letterSpacing: -0.15, color: AppColors.text);
  /// Subhead 15.
  static TextStyle get subhead => TextStyle(fontFamily: _s, fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w400, letterSpacing: -0.1, color: AppColors.text);
  /// Footnote 13.
  static TextStyle get footnote => TextStyle(fontFamily: _s, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.textMuted);
  /// Caption 12.
  static TextStyle get caption => TextStyle(fontFamily: _s, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.textMuted);
  /// Cifras (ELO, marcador, contadores): dígitos tabulares para que no «bailen» al cambiar.
  static const tabular = [FontFeature.tabularFigures()];

  // ── Texto (Inter) ──
  /// `.sub` — entradilla bajo el título: Inter 14/400, lh 1.4, gris.
  static TextStyle get sub => TextStyle(fontFamily: _s, fontSize: 14, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.textMuted);
  /// `.eb` — etiqueta en mayúsculas («ACTIVAS», «PASO 1 DE 5»): Inter 10.5/700, +0.14em. Escribir el texto en mayúsculas.
  static TextStyle get eb => TextStyle(fontFamily: _s, fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w700, letterSpacing: 1.32, color: AppColors.textMuted);
  /// `.info .k` — clave de ficha («UBICACIÓN»): Inter 10.5/700, +0.12em, mayúsculas.
  static TextStyle get key => TextStyle(fontFamily: _s, fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted);
  /// `.info .vv` — valor de ficha: Inter 14/600, lh 1.3.
  static TextStyle get value => TextStyle(fontFamily: _s, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text);
  /// `.desc` — párrafo descriptivo: Inter 14/400, lh 1.5, tinta 700.
  static TextStyle get desc => TextStyle(fontFamily: _s, fontSize: 14, height: 1.5, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.isDark ? const Color(0xFFC9D0CB) : AppColors.ink700);
  /// `.lab` — etiqueta de campo de formulario: Inter 12/700, +0.04em.
  static TextStyle get label => TextStyle(fontFamily: _s, fontSize: 12, height: 15 / 12, fontWeight: FontWeight.w700, letterSpacing: 0.48, color: AppColors.text);
  /// `.inp` — texto dentro de un campo: Inter 16/400.
  static TextStyle get input => TextStyle(fontFamily: _s, fontSize: 16, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.text);
  /// Texto de ayuda / error bajo un campo (`.help`, `.errt`): Inter 12.5.
  static TextStyle get help => TextStyle(fontFamily: _s, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.textMuted);
  /// Botones `.pbtn` / `.obtn`: Inter 14/600.
  static const button = TextStyle(fontFamily: _s, fontSize: 14, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0);
  /// Botón pequeño `.sbtn` y filtros `.fc`: Inter 13/600.
  static const buttonSmall = TextStyle(fontFamily: _s, fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0);
  /// `.chip` — píldora: Inter 12/600.
  static const chip = TextStyle(fontFamily: _s, fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0);
  /// Enlace «Ver todas» de cabecera de sección: Inter 13/600, tinta.
  static TextStyle get link => TextStyle(fontFamily: _s, fontSize: 13, height: 1, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text);
  /// `.card2 h3` — título dentro de una tarjeta: Inter 15/800.
  static TextStyle get cardTitle => TextStyle(fontFamily: _s, fontSize: 15, height: 19 / 15, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text);
  /// Pestaña de `.seg`: Inter 12.5/600.
  static const tab = TextStyle(fontFamily: _s, fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0);
  /// Etiqueta de la barra inferior: Inter 12 (700 activa / 500 inactiva).
  static const navLabel = TextStyle(fontFamily: _s, fontSize: 12, height: 15 / 12, fontWeight: FontWeight.w500, letterSpacing: 0);
  /// Cifra grande de tarjeta (Inicio: amigos, ELO): Inter 22/800, −0.01em.
  static TextStyle get stat => TextStyle(fontFamily: _s, fontSize: 22, height: 1, fontWeight: FontWeight.w800, letterSpacing: -0.22, color: AppColors.text, fontFeatures: tabular);
  /// Saludo del banner de Inicio: Inter 27/800, lh 1.12, −0.01em, blanco.
  static const hello = TextStyle(fontFamily: _s, fontSize: 27, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -0.27, color: Color(0xFFFFFFFF));   // siempre sobre la foto del banner
}
