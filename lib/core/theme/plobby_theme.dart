import 'package:flutter/material.dart';
import 'design_tokens.dart';
import '../motion/app_motion.dart';
export 'design_tokens.dart';

/// Alias de compatibilidad: los widgets existentes siguen usando `PlobbyColors.*` y ahora resuelven a la
/// nueva paleta (lima/tinta). Nombres antiguos → rol nuevo. No se define ningún color nuevo aquí.
class PlobbyColors {
  PlobbyColors._();
  static const forest = AppColors.ink900;      // bloques/tinta de marca (antes verde bosque)
  static const ivory = AppColors.bg;           // fondo de pantalla
  static const charcoal = AppColors.text;      // texto principal
  static const lime = AppColors.brand;         // acción / selección
  static const sage = AppColors.ink400;        // bordes y elementos apagados
  static const mute = AppColors.textMuted;     // texto secundario
  static const loss = AppColors.danger;        // derrota / error
  static const win = AppColors.success;        // victoria / confirmado
}

/// Estilos de botón reutilizables (alturas 48/36, radio `md`, texto `label`).
class AppButtonStyles {
  AppButtonStyles._();
  static const _label = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600);
  static ButtonStyle primary({bool small = false}) => FilledButton.styleFrom(
        backgroundColor: AppColors.brand, foregroundColor: AppColors.brandInk,
        disabledBackgroundColor: AppColors.surfaceSunken, disabledForegroundColor: AppColors.textDisabled,
        minimumSize: Size(0, small ? 36 : 48), padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
        shape: RoundedRectangleBorder(borderRadius: small ? AppRadius.rSm : AppRadius.rMd), textStyle: _label, elevation: 0,
      ).copyWith(overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? AppColors.brandPressed.withOpacity(.5) : s.contains(WidgetState.hovered) ? AppColors.brandHover.withOpacity(.5) : null));
  static ButtonStyle secondary() => FilledButton.styleFrom(
        backgroundColor: AppColors.inverse, foregroundColor: AppColors.onInverse,
        minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd), textStyle: _label, elevation: 0);
  static ButtonStyle ghost({bool small = false}) => OutlinedButton.styleFrom(
        foregroundColor: AppColors.text, side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        minimumSize: Size(0, small ? 36 : 48), padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
        shape: RoundedRectangleBorder(borderRadius: small ? AppRadius.rSm : AppRadius.rMd), textStyle: _label);
  static ButtonStyle danger() => FilledButton.styleFrom(
        backgroundColor: AppColors.dangerSoft, foregroundColor: AppColors.danger,
        minimumSize: const Size(0, 48), shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd), textStyle: _label, elevation: 0);
}

/// Decoraciones de tarjeta reutilizables.
class AppCardStyles {
  AppCardStyles._();
  static const surface = BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card);
  static const inverse = BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg);
  static const sunken = BoxDecoration(color: AppColors.surfaceSunken, borderRadius: AppRadius.rMd);
}

/// Inter y Unbounded van EMPAQUETADAS en assets/fonts (pubspec `fonts:`), con los mismos pesos que carga el prototipo
/// HTML (Inter 400–800, Unbounded 500–700). Antes se descargaban en tiempo de ejecución con google_fonts, que las
/// registra como «Unbounded_700»: por eso `TextStyle(fontFamily: 'Unbounded')` caía en la fuente del sistema, y sin
/// red en el primer arranque toda la app salía sin sus fuentes.
TextTheme _textTheme(TextTheme base) {
  // letterSpacing 0 explícito: si queda en null, Theme.of mezcla la geometría de Material (+0.25/+0.5 px) y el texto
  // sale más espaciado que en el CSS (que no aplica espaciado salvo en .eb/.lab/titulares).
  TextStyle? z(TextStyle? x) => x?.copyWith(letterSpacing: 0);
  final b0 = base.apply(fontFamily: AppTypography.sansFamily, bodyColor: AppColors.text, displayColor: AppColors.text);
  final inter = b0.copyWith(
    displayLarge: z(b0.displayLarge), displayMedium: z(b0.displayMedium), displaySmall: z(b0.displaySmall),
    headlineLarge: z(b0.headlineLarge), headlineMedium: z(b0.headlineMedium), headlineSmall: z(b0.headlineSmall),
    titleLarge: z(b0.titleLarge), titleMedium: z(b0.titleMedium), titleSmall: z(b0.titleSmall),
    bodyLarge: z(b0.bodyLarge), bodyMedium: z(b0.bodyMedium), bodySmall: z(b0.bodySmall),
    labelLarge: z(b0.labelLarge), labelMedium: z(b0.labelMedium), labelSmall: z(b0.labelSmall));
  TextStyle uni(TextStyle? s, double size, double lh, FontWeight w, [double ls = -0.02]) =>
      (s ?? const TextStyle()).copyWith(fontFamily: AppTypography.displayFamily, fontSize: size, height: lh / size, fontWeight: w, letterSpacing: size * ls, color: AppColors.text);
  return inter.copyWith(
    displayLarge: uni(inter.displayLarge, 40, 44, FontWeight.w700),      // display-xl
    displayMedium: uni(inter.displayMedium, 28, 34, FontWeight.w700),    // display-l
    headlineMedium: uni(inter.headlineMedium, 28, 34, FontWeight.w700),
    headlineSmall: uni(inter.headlineSmall, 20, 26, FontWeight.w600, 0), // title
    titleLarge: uni(inter.titleLarge, 20, 26, FontWeight.w600, 0),
    titleMedium: inter.titleMedium?.copyWith(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600),   // body-strong
    bodyLarge: inter.bodyLarge?.copyWith(fontSize: 16, height: 24 / 16),                                   // body
    bodyMedium: inter.bodyMedium?.copyWith(fontSize: 14, height: 20 / 14),
    labelLarge: inter.labelLarge?.copyWith(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600),    // label
    bodySmall: inter.bodySmall?.copyWith(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w500, color: AppColors.textMuted), // caption
  );
}

ThemeData buildPlobbyTheme() {
  final scheme = ColorScheme.light(
    primary: AppColors.brand, onPrimary: AppColors.brandInk, secondary: AppColors.inverse, onSecondary: AppColors.onInverse,
    tertiary: AppColors.accent, onTertiary: AppColors.onAccent, surface: AppColors.surface, onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.surfaceSunken, outline: AppColors.borderStrong, outlineVariant: AppColors.border,
    error: AppColors.danger, onError: Colors.white, errorContainer: AppColors.dangerSoft, onErrorContainer: AppColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: AppColors.bg, fontFamily: AppTypography.sansFamily);
  // `.inp`: borde 1 px #8A938D, radio 14.
  OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    pageTransitionsTheme: AppTransitions.theme, // solo la animación; GoRouter y rutas intactos
    textTheme: _textTheme(base.textTheme),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    focusColor: AppColors.focus,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg, foregroundColor: AppColors.text, elevation: 0, scrolledUnderElevation: 0, centerTitle: true,
      titleTextStyle: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text, letterSpacing: -0.2),
    ),
    filledButtonTheme: FilledButtonThemeData(style: AppButtonStyles.primary()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: AppButtonStyles.primary()),
    outlinedButtonTheme: OutlinedButtonThemeData(style: AppButtonStyles.ghost()),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.brandText, textStyle: const TextStyle(fontWeight: FontWeight.w600))),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: AppColors.text, minimumSize: const Size(44, 44))),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: AppColors.brand, foregroundColor: AppColors.brandInk, elevation: 2, shape: CircleBorder()),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: AppColors.surface, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 16), labelStyle: const TextStyle(color: AppColors.textMuted), border: ob(AppColors.borderStrong), enabledBorder: ob(AppColors.borderStrong),
      focusedBorder: ob(AppColors.focus, 2), errorBorder: ob(AppColors.danger), focusedErrorBorder: ob(AppColors.danger, 2),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceSunken), elevation: const WidgetStatePropertyAll(0),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppRadius.rMd)),
      constraints: const BoxConstraints(minHeight: 48), hintStyle: const WidgetStatePropertyAll(TextStyle(color: AppColors.textMuted)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    ),
    cardTheme: CardThemeData(color: AppColors.surface, elevation: 0, margin: EdgeInsets.zero, shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd), shadowColor: const Color(0x14171C19)),
    // `.fc` del prototipo: 34 px, radio 8, Inter 13/600, sin ✓; activo lima, inactivo blanco con borde 1 px .12.
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface, selectedColor: AppColors.brand, side: const BorderSide(color: Color(0x1F171C19)),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm), showCheckmark: false,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
      padding: const EdgeInsets.symmetric(horizontal: 6), labelPadding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
      // `.seg`: fondo hundido, sin bordes, activa en lima; Inter 12.5/600.
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brand : AppColors.surfaceSunken),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brandInk : AppColors.textMuted),
      side: const WidgetStatePropertyAll(BorderSide(color: AppColors.surfaceSunken, width: 3)),
      shape: const WidgetStatePropertyAll(StadiumBorder()), textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    )),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surfaceRaised, shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop), showDragHandle: true, dragHandleColor: AppColors.border, modalBackgroundColor: AppColors.surfaceRaised),
    dialogTheme: DialogThemeData(backgroundColor: AppColors.surfaceRaised, shape: const RoundedRectangleBorder(borderRadius: AppRadius.rLg), elevation: 8),
    snackBarTheme: SnackBarThemeData(backgroundColor: AppColors.inverse, contentTextStyle: const TextStyle(color: AppColors.onInverse, fontWeight: FontWeight.w600), behavior: SnackBarBehavior.floating, shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd)),
    badgeTheme: const BadgeThemeData(backgroundColor: AppColors.brand, textColor: AppColors.brandInk),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface, indicatorColor: AppColors.brand, elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.brandInk : AppColors.textMuted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s.contains(WidgetState.selected) ? AppColors.text : AppColors.textMuted)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.text, textColor: AppColors.text),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.inverse, linearTrackColor: AppColors.surfaceSunken),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brandInk : AppColors.surface),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brand : AppColors.borderStrong),
    ),
  );
}
