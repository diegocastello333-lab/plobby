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

  // Semánticos (tema claro; el oscuro está en [AppColorsDark])
  static const bg = ink50, surface = Color(0xFFFFFFFF), surfaceRaised = Color(0xFFFFFFFF), surfaceSunken = ink100;
  static const inverse = ink900, onInverse = lime300;
  static const text = ink900, textMuted = ink500, textDisabled = ink400;
  static const border = ink200, borderStrong = ink400;
  static const brand = lime300, brandHover = lime400, brandPressed = lime500, brandInk = ink900, brandSoft = lime100, brandText = lime700;
  static const accent = court500, onAccent = Color(0xFFFFFFFF), focus = court500;
  static const success = Color(0xFF12754D), successSoft = Color(0xFFE3F5EC);
  static const warning = Color(0xFF9A5B00), warningSoft = Color(0xFFFFF3DC);
  static const danger = Color(0xFFC4282E), dangerSoft = Color(0xFFFDE7E7);
}

/// Tema oscuro (definido en la referencia). La app sigue en claro; esto deja listo `ThemeMode.system`.
class AppColorsDark {
  AppColorsDark._();
  static const bg = AppColors.ink950, surface = AppColors.ink900, surfaceRaised = AppColors.ink800, surfaceSunken = Color(0xFF111512);
  static const inverse = Color(0xFFF2F5EF), onInverse = AppColors.ink900;
  static const text = Color(0xFFF2F5EF), textMuted = Color(0xFF9AA39D), textDisabled = AppColors.ink600;
  static const border = AppColors.ink700, borderStrong = AppColors.ink600;
  static const brandSoft = Color(0xFF2C3510), brandText = AppColors.lime300;
  static const accent = AppColors.court300, onAccent = AppColors.ink900, focus = AppColors.lime300;
  static const success = Color(0xFF3DDC97), successSoft = Color(0xFF0F2A1E);
  static const warning = Color(0xFFFFB84D), warningSoft = Color(0xFF2E2210);
  static const danger = Color(0xFFFF6B6F), dangerSoft = Color(0xFF33161A);
}

class AppSpacing {
  AppSpacing._();
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s6 = 24.0, s8 = 32.0;
  static const screenH = s4; // margen lateral
}

class AppRadius {
  AppRadius._();
  static const sm = 8.0, md = 14.0, lg = 22.0, pill = 999.0;
  static const rSm = BorderRadius.all(Radius.circular(sm)), rMd = BorderRadius.all(Radius.circular(md)),
      rLg = BorderRadius.all(Radius.circular(lg)), rPill = BorderRadius.all(Radius.circular(pill));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(lg));
}

class AppShadows {
  AppShadows._();
  static const card = [BoxShadow(color: Color(0x0F171C19), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: Color(0x0F171C19), blurRadius: 16, offset: Offset(0, 4))];
  static const pop = [BoxShadow(color: Color(0x29171C19), blurRadius: 32, offset: Offset(0, 8))];
  /// Tarjetas que solapan el banner de Inicio (`#hb-fr`, `#hb-elo`, `#hb-st`): 0 6 18 −8 .28 + 0 1 0 .04.
  static const lifted = [BoxShadow(color: Color(0x47171C19), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -8), BoxShadow(color: Color(0x0A171C19), offset: Offset(0, 1))];
}

/// Unbounded solo en titulares (display-xl, display-l, title); Inter para todo lo demás.
class AppTypography {
  AppTypography._();
  static const displayFamily = 'Unbounded', sansFamily = 'Inter';
}
