import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/design_tokens.dart';

/// Sistema centralizado de movimiento. SOLO presentación: no toca lógica, rutas ni datos.
/// (AppSpacing/AppRadius/AppTypography/AppButtonStyles viven en `core/theme`; aquí se amplían.)
///
/// REGLA (test/motion_system_test.dart): ninguna pantalla escribe duraciones, curvas ni vibraciones sueltas. Todo sale de
/// [Motion] (tokens), [AppSprings] (muelles) y [AppHaptics] (vibración). Las duraciones que NO son animación (esperas de
/// red, retardos de búsqueda, tiempo de lectura de una historia…) se marcan con el comentario `// timing`.

/// Tokens de movimiento de Plobby.
class Motion {
  Motion._();
  // ── Duraciones ──
  /// Al pulsar: el elemento encoge (escala 0,97) en 100 ms.
  static const press = Duration(milliseconds: 100);
  /// Taps, toggles, cambios de estado pequeños.
  static const fast = Duration(milliseconds: 150);
  /// Transiciones y entradas de elementos.
  static const normal = Duration(milliseconds: 250);
  /// Cambios de pantalla y movimientos importantes.
  static const emphasis = Duration(milliseconds: 400);
  /// Celebraciones (victoria, logro, cifra que sube).
  static const celebration = Duration(milliseconds: 900);
  /// Celebraciones largas (subida de nivel, gráfica que se dibuja). Máximo de una celebración: 1200 ms.
  static const celebrationLong = Duration(milliseconds: 1200);

  // ── Bucles decorativos (periodos; en web se detienen tras unos ciclos: [IdleMotion]) ──
  /// Punto «en directo», latido.
  static const loopPulse = Duration(milliseconds: 1200);
  /// Brillos y barridos.
  static const loopShimmer = Duration(milliseconds: 1400);
  /// Resplandor lento de barras.
  static const loopGlow = Duration(milliseconds: 2400);
  /// Fondo de la bienvenida.
  static const loopAmbient = Duration(milliseconds: 5000);
  /// Deriva del fondo ambiental.
  static const ambientDrift = Duration(seconds: 24);

  // ── Curvas ──
  /// Entradas: arranca rápido y frena (ease-out).
  static const Curve enter = Curves.easeOutCubic;
  /// Salidas: arranca suave y se va (ease-in).
  static const Curve exit = Curves.easeInCubic;
  /// Desplazamientos de un punto a otro (scroll, reordenaciones).
  static const Curve move = Curves.easeInOutCubic;
  /// Progreso constante (bucles, cronómetros).
  static const Curve linear = Curves.linear;
  /// Elementos interactivos: muelle suave, sin rebote apreciable.
  static const Curve spring = AppSprings.snappy;
  /// Hojas y páginas: muelle sin rebote.
  static const Curve springSoft = AppSprings.smooth;
  /// SOLO celebraciones: muelle con un rebote visible y breve.
  static const Curve springBounce = AppSprings.bouncy;

  // ── Reducir movimiento (Android: «Quitar animaciones»/escala de animación 0; web: prefers-reduced-motion) ──
  /// Único punto de verdad. Con él activo, las animaciones se sustituyen por fundidos cortos o cambios instantáneos;
  /// el estado final es idéntico.
  static bool reduced(BuildContext c) => forceReduced ?? (MediaQuery.maybeOf(c)?.disableAnimations ?? false);
  /// Solo para tests y capturas.
  static bool? forceReduced;
  /// Duración efectiva: cero con «reducir movimiento».
  static Duration of(BuildContext c, Duration d) => reduced(c) ? Duration.zero : d;
  /// Fundido sustituto con «reducir movimiento» (cuando un cambio instantáneo resultaría brusco).
  static Duration fadeOr(BuildContext c, Duration d) => reduced(c) ? fast : d;
}

/// Duraciones, curvas y escalas con NOMBRE de uso. Todas salen de [Motion].
class AppAnimations {
  AppAnimations._();
  static const press = Motion.press;
  static const pressRelease = Motion.normal;   // vuelta con muelle
  static const tab = Motion.normal;
  static const appear = Motion.normal;
  static const appearStep = Duration(milliseconds: 40);  // retraso progresivo entre elementos de una lista
  static const appearMaxDelay = Motion.normal;
  static const appearOffset = 10.0;                       // 8–12 px
  static const pressScale = 0.97;
  static const badge = Motion.normal;
  static const countUp = Motion.celebration;
  static const shimmer = Motion.loopShimmer;
  static const emphasis = Motion.enter;
  static const standard = Motion.enter;
  static const settle = Motion.springBounce;
  /// Soltar un botón: muelle con un rebote apenas perceptible, como los controles de iOS.
  static const release = Motion.spring;
  /// Cambio de página en selectores paginados (pestañas ↔ PageView).
  static const page = Motion.emphasis;
  static const pageCurve = Motion.springSoft;
  /// Cambio entre pestañas de la barra inferior: fundido rápido del contenido.
  static const branch = Motion.normal;

  /// Retraso escalonado con tope, para que una lista larga no resulte lenta.
  static Duration staggerDelay(int index) {
    final ms = appearStep.inMilliseconds * (index < 0 ? 0 : index);
    return Duration(milliseconds: ms > appearMaxDelay.inMilliseconds ? appearMaxDelay.inMilliseconds : ms);
  }

  /// Respeta «reducir movimiento» del sistema: duración mínima (transición casi instantánea).
  static Duration scaled(BuildContext c, Duration d) => Motion.of(c, d);
  static bool reduceMotion(BuildContext c) => Motion.reduced(c);
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

/// Vibración con UN significado cada una (HIG › Playing haptics: «Use haptics consistently»). Nadie llama a
/// HapticFeedback directamente. Una sola vibración por evento (nunca por fotograma) y NUNCA fuerte para errores.
/// El usuario la puede desactivar: Perfil → Ajustes y privacidad → Vibración ([enabled], guardado en el dispositivo).
class AppHaptics {
  AppHaptics._();
  static const _prefKey = 'plobby.haptics_enabled';
  static bool enabled = true;
  /// Lee la preferencia guardada (se llama al arrancar la app).
  static Future<void> load() async {
    try { enabled = (await SharedPreferences.getInstance()).getBool(_prefKey) ?? true; } catch (_) {}
  }
  static Future<void> setEnabled(bool v) async {
    enabled = v;
    try { await (await SharedPreferences.getInstance()).setBool(_prefKey, v); } catch (_) {}
  }
  /// Últimos eventos (solo tests): comprueba «una vibración por evento».
  @visibleForTesting
  static final log = <String>[];

  /// Ligera: apuntar un juego, un toggle, cambiar de pestaña o filtro, pulsar una acción principal.
  static void light() => _fire('light', HapticFeedback.selectionClick);
  /// Media: reaccionar, desbloquear un logro.
  static void medium() => _fire('medium', HapticFeedback.lightImpact);
  /// Éxito: victoria, subida de nivel, resultado guardado.
  static void success() => _fire('success', HapticFeedback.mediumImpact);
  /// Error: como mucho un toque ligero (nunca una vibración fuerte que «riña» al usuario).
  static void error() => _fire('error', HapticFeedback.selectionClick);

  static void _fire(String kind, Future<void> Function() f) {
    if (!enabled) return;
    if (log.length > 50) log.removeAt(0);
    log.add(kind);
    f();
  }
}

/// Animaciones decorativas en bucle (llama de racha, brillo de la barra de ELO, punto «en directo»).
///
/// En la WEB se limitan a unos ciclos y después quedan quietas en su pose de reposo: una animación infinita obliga al
/// navegador a volver a pintar TODA la pantalla en cada fotograma aunque nadie toque nada (medido en Chromium: de 5 a 17
/// fotogramas/s en reposo en Inicio, Feed, Competiciones, Perfil y Mi rating; 0 en las demás). En un iPhone eso es batería y
/// calor. En Android e iOS nativos el comportamiento no cambia.
class IdleMotion {
  IdleMotion._();
  static bool limitLoops = kIsWeb;   // modificable en tests
  static const cycles = 3;

  /// Igual que `c.repeat(reverse: …)`, pero en la web se detiene tras [cycles] ciclos y vuelve a [rest] (si se da).
  static void loop(AnimationController c, {bool reverse = false, double? rest}) {
    if (!limitLoops) { c.repeat(reverse: reverse); return; }
    c.repeat(reverse: reverse, count: cycles * (reverse ? 2 : 1)).whenCompleteOrCancel(() {
      if (rest != null && c.status != AnimationStatus.dismissed && c.value != rest) {
        try { c.animateTo(rest, duration: Motion.normal); } catch (_) {/* ya eliminado */}
      }
    });
  }
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
  static const duration = Motion.normal;
  static const reverse = Motion.normal;
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
    final curved = CurvedAnimation(parent: a, curve: Motion.enter, reverseCurve: Motion.exit);
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
void appTick() => AppHaptics.light();
