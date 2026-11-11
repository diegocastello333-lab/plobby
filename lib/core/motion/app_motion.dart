import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_tokens.dart';

/// Sistema centralizado de movimiento. SOLO presentación: no toca lógica, rutas ni datos.
/// (AppSpacing/AppRadius/AppTypography/AppButtonStyles viven en `core/theme`; aquí se amplían.)

/// Duraciones, curvas y escalas. Un único sitio para ajustar «cómo se siente» Plobby.
class AppAnimations {
  AppAnimations._();
  static const press = Duration(milliseconds: 120);      // 100–180 ms
  static const pressRelease = Duration(milliseconds: 160);
  static const tab = Duration(milliseconds: 220);
  static const appear = Duration(milliseconds: 260);     // 200–300 ms
  static const appearStep = Duration(milliseconds: 40);  // retraso progresivo
  static const appearMaxDelay = Duration(milliseconds: 240);
  static const appearOffset = 10.0;                       // 8–12 px
  static const pressScale = 0.97;
  static const badge = Duration(milliseconds: 260);
  static const countUp = Duration(milliseconds: 900);
  static const shimmer = Duration(milliseconds: 1400);
  static const emphasis = Curves.easeOutCubic;
  static const standard = Curves.easeOutCubic;
  static const settle = Curves.easeOutBack;

  /// Retraso escalonado con tope, para que una lista larga no resulte lenta.
  static Duration staggerDelay(int index) {
    final ms = appearStep.inMilliseconds * (index < 0 ? 0 : index);
    return Duration(milliseconds: ms > appearMaxDelay.inMilliseconds ? appearMaxDelay.inMilliseconds : ms);
  }

  /// Respeta «reducir movimiento» del sistema: duración mínima (transición casi instantánea).
  static Duration scaled(BuildContext c, Duration d) => reduceMotion(c) ? Duration.zero : d;
  static bool reduceMotion(BuildContext c) => MediaQuery.maybeOf(c)?.disableAnimations ?? false;
}

/// Tamaños y estilos de tarjetas/encabezados. Múltiplos de 4/8.
class AppLayout {
  AppLayout._();
  static const minTap = 44.0;
  static const headerHeight = 44.0;      // título + «Ver todos» comparten eje y altura
  static const sectionGap = 28.0;
  static const cardGap = 12.0;
  static const buttonHeight = 48.0, buttonHeightSmall = 36.0, buttonHeightCompact = 44.0;
}

class AppCardStyles {
  AppCardStyles._();
  static const padding = EdgeInsets.all(AppSpacing.s4);
  static BoxDecoration surface({Color? color}) => BoxDecoration(
      color: color ?? AppColors.surface, borderRadius: AppRadius.rLg,
      border: Border.all(color: AppColors.border), boxShadow: AppShadows.card);
}

/// Transiciones de página para el `PageTransitionsTheme`. No sustituye al GoRouter: solo la animación.
class AppTransitions {
  AppTransitions._();
  static const duration = Duration(milliseconds: 260);
  static const reverse = Duration(milliseconds: 220);
  static const slide = 0.04; // desplazamiento horizontal discreto (fracción del ancho)
  static const theme = PageTransitionsTheme(builders: {
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.iOS: AppPageTransitionsBuilder(),
    TargetPlatform.macOS: AppPageTransitionsBuilder(),
    TargetPlatform.windows: AppPageTransitionsBuilder(),
    TargetPlatform.linux: AppPageTransitionsBuilder(),
  });
}

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> a, Animation<double> sa, Widget child) {
    if (AppAnimations.reduceMotion(context)) return FadeTransition(opacity: a, child: child);
    final curved = CurvedAnimation(parent: a, curve: AppAnimations.standard, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: Tween(begin: const Offset(AppTransitions.slide, 0), end: Offset.zero).animate(curved), child: child));
  }
}

/// Registro de tarjetas ya animadas: la entrada ocurre UNA vez por clave (no al refrescar ni al volver).
class AppearRegistry {
  AppearRegistry._();
  static final Set<String> _seen = <String>{};
  static bool hasSeen(String key) => _seen.contains(key);
  static void markSeen(String key) => _seen.add(key);
  @visibleForTesting
  static void reset() => _seen.clear();
}

/// Feedback háptico discreto opcional (no se usa por defecto).
void appTick() => HapticFeedback.selectionClick();
