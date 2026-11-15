import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../theme/design_tokens.dart';

/// Sistema centralizado de movimiento. SOLO presentación: no toca lógica, rutas ni datos.
/// (AppSpacing/AppRadius/AppTypography/AppButtonStyles viven en `core/theme`; aquí se amplían.)

/// Duraciones, curvas y escalas. Un único sitio para ajustar «cómo se siente» Plobby.
class AppAnimations {
  AppAnimations._();
  static const press = Duration(milliseconds: 120);      // 100–180 ms
  static const pressRelease = Duration(milliseconds: 320);   // vuelta con rebote suave
  static const tab = Duration(milliseconds: 320);   // con muelle: el tramo final es la frenada
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
  static const settle = AppSprings.bouncy;
  /// Soltar un botón: muelle con un rebote apenas perceptible, como los controles de iOS.
  static const release = AppSprings.snappy;
  /// Cambio de página en selectores paginados (pestañas ↔ PageView).
  static const page = Duration(milliseconds: 420);
  static const pageCurve = AppSprings.smooth;
  /// Cambio entre pestañas de la barra inferior: fundido rápido del contenido.
  static const branch = Duration(milliseconds: 240);

  /// Retraso escalonado con tope, para que una lista larga no resulte lenta.
  static Duration staggerDelay(int index) {
    final ms = appearStep.inMilliseconds * (index < 0 ? 0 : index);
    return Duration(milliseconds: ms > appearMaxDelay.inMilliseconds ? appearMaxDelay.inMilliseconds : ms);
  }

  /// Respeta «reducir movimiento» del sistema: duración mínima (transición casi instantánea).
  static Duration scaled(BuildContext c, Duration d) => reduceMotion(c) ? Duration.zero : d;
  static bool reduceMotion(BuildContext c) => MediaQuery.maybeOf(c)?.disableAnimations ?? false;
}

/// Muelles al estilo de iOS (SwiftUI `.smooth`, `.snappy`, `.bouncy`), como curvas: la forma sale de una simulación
/// física real (masa 1, rigidez y amortiguación fijas), normalizada a la duración del Animation que la usa. Así toda la
/// app comparte la misma «física»: entra rápido, frena con suavidad y, si rebota, lo hace una vez y poco.
class SpringCurve extends Curve {
  const SpringCurve({required this.stiffness, required this.damping});
  final double stiffness, damping;
  static final _cache = <(double, double), (SpringSimulation, double)>{};
  (SpringSimulation, double) get _sim => _cache.putIfAbsent((stiffness, damping), () {
        final sim = SpringSimulation(SpringDescription(mass: 1, stiffness: stiffness, damping: damping), 0, 1, 0);
        var t = 0.0;
        while (t < 5 && !sim.isDone(t)) { t += 1 / 120; }   // tiempo hasta reposo (tolerancia por defecto)
        return (sim, t);
      });
  @override
  double transformInternal(double t) {
    final (sim, total) = _sim;
    return sim.x(t * total);
  }
}

class AppSprings {
  AppSprings._();
  /// Sin rebote: cambios de página, hojas, navegación.
  static const smooth = SpringCurve(stiffness: 170, damping: 26);
  /// Respuesta de controles: un 2–3 % de rebote.
  static const snappy = SpringCurve(stiffness: 300, damping: 26);
  /// Celebraciones y «pop» de iconos: un rebote visible pero breve.
  static const bouncy = SpringCurve(stiffness: 260, damping: 16);
}

/// Hápticos con UN significado cada uno (HIG › Playing haptics: «Use haptics consistently»). Nadie llama a
/// HapticFeedback directamente: así cada vibración enseña siempre lo mismo.
class AppHaptics {
  AppHaptics._();
  /// Cambiar de selección: pestañas, segmentos, filtros, interruptores.
  static void selection() => HapticFeedback.selectionClick();
  /// Pulsar una acción principal (crear, enviar, publicar).
  static void tap() => HapticFeedback.lightImpact();
  /// Acción completada con éxito (resultado guardado, amistad aceptada, logro).
  static void success() => HapticFeedback.mediumImpact();
  /// Acción que no se pudo completar.
  static void error() => HapticFeedback.heavyImpact();
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
  /// iOS usa la transición nativa de Apple: es la que trae el gesto de «deslizar desde el borde para volver», que los
  /// usuarios de iPhone esperan en todas las apps. El resto de plataformas (Android incluido) mantiene la de Plobby.
  static const theme = PageTransitionsTheme(builders: {
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
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
void appTick() => AppHaptics.selection();
