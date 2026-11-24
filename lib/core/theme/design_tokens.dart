import 'package:flutter/material.dart';

/// Design tokens de Plobby (fuente: sistema de diseño de referencia, `tokens.json`).
/// Lima = acción/selección · tinta = lectura. Nunca texto blanco sobre lima: sobre `brand` siempre `brandInk`.
/// Cambiar aquí cambia toda la app; ningún widget debe definir colores propios.
class AppColors {
  AppColors._();
  // Primitivas
  static const lime50 = Color(0xFFF8FDE3), lime100 = Color(0xFFEEFBC0), lime200 = Color(0xFFE3F88E);
  static const lime300 = Color(0xFFD2F548), lime400 = Color(0xFFC3EA2C), lime500 = Color(0xFFAED21A), lime700 = Color(0xFF5F7410);
  static const ink50 = Color(0xFFF6F8F1), ink100 = Color(0xFFEEF1EA), ink200 = Color(0xFFD5DAD6), ink400 = Color(0xFF8A938D);
  static const ink500 = Color(0xFF5C6660), ink600 = Color(0xFF6F7A73), ink700 = Color(0xFF343D38), ink800 = Color(0xFF232A26);
  static const ink900 = Color(0xFF171C19), ink950 = Color(0xFF0D110F);
  static const court500 = Color(0xFF2F6FDE), court300 = Color(0xFF6EA8FF);

  // ── Modo claro / oscuro ──
  /// true con el modo oscuro del sistema. Lo fija la raíz de la app (`PlobbyApp`) ANTES de construir y, al cambiar,
  /// toda la app se reconstruye: por eso los colores semánticos son getters (no constantes).
  static bool isDark = false;
  static Color _m(Color light, Color dark) => isDark ? dark : light;

  // Semánticos (cambian con el modo). Las primitivas de arriba no cambian.
  static Color get bg => _m(ink50, AppColorsDark.bg);
  static Color get surface => _m(const Color(0xFFFFFFFF), AppColorsDark.surface);
  static Color get surfaceRaised => _m(const Color(0xFFFFFFFF), AppColorsDark.surfaceRaised);
  static Color get surfaceSunken => _m(ink100, AppColorsDark.surfaceSunken);
  /// Bloque destacado (tarjeta de ELO, campeón…): oscuro en los dos modos (en oscuro, un poco más claro que el fondo),
  /// para que su texto marfil y sus cifras lima se lean siempre.
  static Color get inverse => _m(ink900, AppColorsDark.inverse);
  static Color get onInverse => lime300;
  static Color get text => _m(ink900, AppColorsDark.text);
  static Color get textMuted => _m(ink500, AppColorsDark.textMuted);
  /// Texto de cuerpo (descripciones, explicaciones): un punto menos que [text], más legible que [textMuted].
  static Color get textBody => _m(ink700, const Color(0xFFC9D0CB));
  static Color get textDisabled => _m(ink400, AppColorsDark.textDisabled);
  static Color get border => _m(ink200, AppColorsDark.border);
  static Color get borderStrong => _m(ink400, AppColorsDark.borderStrong);
  static const brand = lime300, brandHover = lime400, brandPressed = lime500, brandInk = ink900;
  static Color get brandSoft => _m(lime100, AppColorsDark.brandSoft);
  static Color get brandText => _m(lime700, AppColorsDark.brandText);
  static Color get accent => _m(court500, AppColorsDark.accent);
  static Color get onAccent => _m(const Color(0xFFFFFFFF), AppColorsDark.onAccent);
  static Color get focus => _m(court500, AppColorsDark.focus);
  static Color get success => _m(const Color(0xFF12754D), AppColorsDark.success);
  static Color get successSoft => _m(const Color(0xFFE3F5EC), AppColorsDark.successSoft);
  static Color get warning => _m(const Color(0xFF9A5B00), AppColorsDark.warning);
  static Color get warningSoft => _m(const Color(0xFFFFF3DC), AppColorsDark.warningSoft);
  static Color get danger => _m(const Color(0xFFC4282E), AppColorsDark.danger);
  static Color get dangerSoft => _m(const Color(0xFFFDE7E7), AppColorsDark.dangerSoft);

  /// Ejecuta [f] con los colores del modo CLARO (imágenes para compartir: salen siempre con los colores de marca,
  /// sea cual sea el modo del móvil; así la vista previa y el PNG coinciden).
  static T light<T>(T Function() f) {
    final prev = isDark;
    isDark = false;
    try { return f(); } finally { isDark = prev; }
  }

  /// Tinta con transparencia (bordes, separadores, velos) en claro; marfil con la misma transparencia en oscuro.
  static Color inkA(int alpha) => isDark ? Color.fromARGB(alpha, 0xF2, 0xF5, 0xEF) : Color.fromARGB(alpha, 0x17, 0x1C, 0x19);
}

/// Tema oscuro (definido en la referencia). Se aplica con el modo oscuro del sistema (`AppColors.isDark`).
class AppColorsDark {
  AppColorsDark._();
  static const bg = AppColors.ink950, surface = AppColors.ink900, surfaceRaised = AppColors.ink800, surfaceSunken = Color(0xFF111512);
  /// Bloques destacados: siguen oscuros (algo más claros que el fondo) con texto marfil y cifras lima.
  static const inverse = AppColors.ink800, onInverse = AppColors.lime300;
  static const text = Color(0xFFF2F5EF), textMuted = Color(0xFF9AA39D), textDisabled = AppColors.ink600;
  static const border = AppColors.ink700, borderStrong = AppColors.ink600;
  static const brandSoft = Color(0xFF2C3510), brandText = AppColors.lime300;
  static const accent = AppColors.court300, onAccent = AppColors.ink900, focus = AppColors.lime300;
  static const success = Color(0xFF3DDC97), successSoft = Color(0xFF0F2A1E);
  static const warning = Color(0xFFFFB84D), warningSoft = Color(0xFF2E2210);
  static const danger = Color(0xFFFF6B6F), dangerSoft = Color(0xFF33161A);
}

/// Materiales (barras y cabeceras sobre contenido que se desplaza): fondo translúcido + desenfoque + línea fina.
class AppMaterials {
  AppMaterials._();
  /// Fondo de barra fija sobre contenido (marfil al 85 %; en oscuro, el fondo oscuro al 85 %).
  static Color get bar => !blur ? AppColors.bg : AppColors.isDark ? const Color(0xD90D110F) : const Color(0xD9F6F8F1);
  /// Barra de pestañas: blanco al 90 % sobre el contenido que pasa por debajo. Con 80 % las etiquetas grises bajaban a
  /// 3,9:1 sobre una tarjeta oscura; al 90 % el peor caso es 4,86:1 (AA). En oscuro: superficie oscura al 90 %.
  // Sin desenfoque (por defecto, ver [blur]) las barras son opacas: translúcidas sin desenfoque dejaban ver el texto de debajo.
  static Color get tabBar => !blur ? AppColors.surface : AppColors.isDark ? const Color(0xE6171C19) : const Color(0xE6FFFFFF);
  /// Desenfoque de las barras translúcidas (sigma).
  static const barBlur = 20.0;
  /// Si las barras desenfocan el contenido de debajo (ver `FrostedBar`).
  static const blur = bool.fromEnvironment('PLOBBY_BLUR', defaultValue: false);
  /// Línea divisoria de 0,5 px bajo una barra cuando hay contenido debajo.
  static Color get hairline => AppColors.inkA(0x1F);
}

/// Espacios que dependen de la pantalla (zona segura, barra de pestañas).
class AppInsets {
  AppInsets._();
  /// Alto de la barra de pestañas sin la zona segura, cuánto sobresale el «+» por encima y aire extra.
  static const tabBarBase = 66.0, tabBarMinSafe = 26.0, breathing = 20.0;
  /// Alto total de la barra de pestañas (incluida la zona segura inferior).
  static double tabBarHeight(BuildContext c) {
    final b = MediaQuery.paddingOf(c).bottom;
    return tabBarBase + (b > tabBarMinSafe ? b : tabBarMinSafe);
  }
  /// Margen inferior que necesita el contenido de una pestaña para que su último elemento (título, tarjeta, botón) no
  /// quede debajo de la barra (el «+» ya va dentro de la barra, no sobresale).
  static double tabBarClearance(BuildContext c) =>
      WideLayout.isWide(c) ? breathing * 2 + MediaQuery.paddingOf(c).bottom : tabBarHeight(c) + breathing;
}

/// Pantallas anchas (escritorio, tablet en horizontal): a partir de [breakpoint] px la app se muestra en una columna
/// centrada de [frameWidth] px (barra lateral [railWidth] + contenido [contentWidth]) en vez de estirarse a todo el ancho.
class WideLayout extends InheritedWidget {
  const WideLayout({super.key, required this.wide, required super.child});
  final bool wide;
  static const breakpoint = 840.0, railWidth = 96.0, contentWidth = 640.0, frameWidth = railWidth + contentWidth;
  static bool isWide(BuildContext c) => c.dependOnInheritedWidgetOfExactType<WideLayout>()?.wide ?? false;
  @override
  bool updateShouldNotify(WideLayout old) => old.wide != wide;
}

class AppSpacing {
  AppSpacing._();
  // Rejilla de 8 pt (4 para ajustes finos).
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0, s8 = 32.0;
  static const screenH = s5; // margen lateral (20, como iOS)
}

class AppRadius {
  AppRadius._();
  // Tres radios en toda la app (estilo iOS): 12 pequeño (botones pequeños, chips), 16 tarjetas y campos, 24 hojas y
  // bloques grandes. En tarjetas, botones y hojas se dibujan con esquinas continuas ([AppShapes]).
  static const sm = 12.0, md = 16.0, lg = 24.0, pill = 999.0;
  /// Radio de las formas continuas (squircle, `ContinuousRectangleBorder`): equivale visualmente a ~12 px redondos.
  static const squircleSm = 26.0;
  static const rSm = BorderRadius.all(Radius.circular(sm)), rMd = BorderRadius.all(Radius.circular(md)),
      rLg = BorderRadius.all(Radius.circular(lg)), rPill = BorderRadius.all(Radius.circular(pill));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(lg));
}

/// Formas con esquinas continuas (superelipse, como iOS): sin el «codo» de un arco de círculo.
class AppShapes {
  AppShapes._();
  static RoundedSuperellipseBorder of(double radius, {BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(radius)), side: side);
  static final card = of(AppRadius.md), small = of(AppRadius.sm), large = of(AppRadius.lg);
  static const sheet = RoundedSuperellipseBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)));
}

class AppShadows {
  AppShadows._();
  /// Una sola elevación sutil para tarjetas (sin borde a la vez).
  static const card = [BoxShadow(color: Color(0x0D171C19), blurRadius: 12, offset: Offset(0, 2))];
  static const pop = [BoxShadow(color: Color(0x29171C19), blurRadius: 32, offset: Offset(0, 8))];
  /// Tarjetas que solapan el banner de Inicio (`#hb-fr`, `#hb-elo`, `#hb-st`): 0 6 18 −8 .28 + 0 1 0 .04.
  static const lifted = [BoxShadow(color: Color(0x47171C19), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -8), BoxShadow(color: Color(0x0A171C19), offset: Offset(0, 1))];
}

/// Unbounded solo en titulares (display-xl, display-l, title); Inter para todo lo demás.
class AppTypography {
  AppTypography._();
  static const displayFamily = 'Unbounded', sansFamily = 'Inter';
}
