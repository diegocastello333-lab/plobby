import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/design_tokens.dart';

/// Pantalla de carga de Plobby (inicio de la app).
///
/// El primer fotograma es idéntico al splash nativo (fondo lima y la P en tinta centrada a
/// [markHeight] dp), así que el paso nativo → Flutter no se nota. Después anima: golpe de pala,
/// la bola hace un globo y bota, los agujeros de la pala laten, se dibuja una pista de pádel
/// de fondo, la marca sube y aparecen «plobby» y la frase. Unas bolas botando indican la carga.
///
/// Llama a [onFinished] una sola vez, cuando ha terminado la animación de entrada y, si se
/// pasa, cuando [ready] ha completado (con éxito o con error: los errores se gestionan después).
/// Con «reducir movimiento» activado muestra directamente el estado final.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished, this.ready});

  /// Se llama al terminar; normalmente navega a la primera pantalla real.
  final VoidCallback onFinished;

  /// Trabajo de arranque opcional (sesión, configuración…) que la carga debe esperar.
  final Future<void>? ready;

  /// Altura de la P en dp: la misma que en el splash nativo de Android e iOS.
  static const markHeight = 120.0;

  /// Duración de la animación de entrada.
  static const introDuration = Duration(milliseconds: 2100);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: SplashScreen.introDuration);
  late final AnimationController _loader = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _started = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_run(reduceMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false));
  }

  Future<void> _run({required bool reduceMotion}) async {
    final ready = (widget.ready ?? Future<void>.value()).catchError((Object _) {});
    if (reduceMotion) {
      _intro.value = 1;
      await Future.wait([ready, Future<void>.delayed(const Duration(milliseconds: 700))]);
    } else {
      unawaited(_loader.repeat());
      await Future.wait([ready, _intro.forward().orCancel.catchError((Object _) {})]);
    }
    if (!mounted || _finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _intro.dispose();
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const markWidth = SplashScreen.markHeight * 72 / 76;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.lime300,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.lime300,
        body: Semantics(
          label: 'Plobby. Cargando',
          liveRegion: true,
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _intro,
              builder: (context, _) {
                final t = _intro.value;
                return Stack(fit: StackFit.expand, children: [
                  CustomPaint(painter: _CourtPainter(progress: SplashTimeline.court(t))),
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, -SplashTimeline.lift(t)),
                      child: SizedBox(
                        width: markWidth,
                        height: SplashScreen.markHeight,
                        child: Stack(clipBehavior: Clip.none, children: [
                          Positioned.fill(
                            child: Transform.scale(
                              scale: SplashTimeline.hit(t),
                              child: CustomPaint(
                                painter: _AnimatedMarkPainter(
                                  ball: SplashTimeline.ball(t),
                                  dotScales: [for (var i = 0; i < 9; i++) SplashTimeline.dot(t, i)],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: SplashScreen.markHeight + 28,
                            left: -200,
                            right: -200,
                            child: _Title(title: SplashTimeline.title(t), tagline: SplashTimeline.tagline(t)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 44),
                        child: Opacity(opacity: SplashTimeline.loader(t), child: _LoadingBalls(animation: _loader)),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Curvas de la animación de entrada en función del progreso `t` (0 → 1). Puras y testeables.
class SplashTimeline {
  SplashTimeline._();

  static double _iv(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

  /// Golpe inicial: la marca se comprime un 6 % y recupera su tamaño.
  static double hit(double t) => 1 - .06 * math.sin(math.pi * _iv(t, 0, .12));

  /// Desplazamiento de la bola (en unidades del logo): globo alto y un bote corto al caer.
  static Offset ball(double t) {
    final lob = _iv(t, .06, .40);
    if (lob < 1) return Offset(8 * math.sin(math.pi * lob), -80 * math.sin(math.pi * lob));
    return Offset(0, -9 * math.sin(math.pi * _iv(t, .40, .50)));
  }

  /// Escala de cada agujero de la pala (0–8, por filas): laten en cadena cuando bota la bola.
  static double dot(double t, int i) => 1 + .7 * math.sin(math.pi * _iv(t, .38 + i * .025, .54 + i * .025));

  /// Cuánto sube la marca (dp) para dejar sitio al nombre.
  static double lift(double t) => 56 * Curves.easeInOutCubic.transform(_iv(t, .45, .72));

  /// Aparición del wordmark «plobby».
  static double title(double t) => Curves.easeOutCubic.transform(_iv(t, .56, .80));

  /// Aparición de la frase.
  static double tagline(double t) => Curves.easeOutCubic.transform(_iv(t, .68, .92));

  /// Trazado de las líneas de la pista de fondo.
  static double court(double t) => Curves.easeInOutCubic.transform(_iv(t, .08, .85));

  /// Aparición del indicador de carga.
  static double loader(double t) => _iv(t, .80, 1);
}

class _Title extends StatelessWidget {
  const _Title({required this.title, required this.tagline});
  final double title;
  final double tagline;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Opacity(
          opacity: title,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - title)),
            child: Text(
              'plobby',
              style: const TextStyle(
                fontFamily: AppTypography.displayFamily,   // Unbounded empaquetada (sin google_fonts)
                fontSize: 44,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.03 * 44,
                height: 1,
                color: AppColors.ink900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: tagline,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - tagline)),
            child: Text(
              'Tu comunidad de pádel',
              style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w500, height: 20 / 15, letterSpacing: 0, color: AppColors.ink700),
            ),
          ),
        ),
      ]);
}

/// Tres bolas que botan en cadena, en tinta sobre lima.
class _LoadingBalls extends StatelessWidget {
  const _LoadingBalls({required this.animation});
  final Animation<double> animation;

  static double _bounce(double p) => math.max(0.0, math.sin(2 * math.pi * p));

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Transform.translate(
                    offset: Offset(0, -12 * _bounce((animation.value - i * .15) % 1)),
                    child: const SizedBox(
                      width: 10,
                      height: 10,
                      child: DecoratedBox(decoration: BoxDecoration(color: AppColors.ink900, shape: BoxShape.circle)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// La P-pala de Plobby (misma geometría que `PlobbyMark`, viewBox 16 12 72 76) con la bola y
/// los agujeros animables.
class _AnimatedMarkPainter extends CustomPainter {
  _AnimatedMarkPainter({required this.ball, required this.dotScales});
  final Offset ball;
  final List<double> dotScales;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.scale(s.width / 72, s.height / 76);
    canvas.translate(-16, -12);
    final fill = Paint()
      ..color = AppColors.ink900
      ..isAntiAlias = true;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(24, 22, 14, 64), const Radius.circular(7)), fill);
    canvas.drawCircle(
      const Offset(54, 40),
      19.5,
      Paint()
        ..color = AppColors.ink900
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..isAntiAlias = true,
    );
    var i = 0;
    for (final y in [34.5, 40.0, 45.5]) {
      for (final x in [48.5, 54.0, 59.5]) {
        canvas.drawCircle(Offset(x, y), 1.7 * dotScales[i++], fill);
      }
    }
    canvas.drawCircle(const Offset(78, 78) + ball, 7, fill);
  }

  @override
  bool shouldRepaint(_AnimatedMarkPainter o) => o.ball != ball || !listEquals(o.dotScales, dotScales);
}

/// Pista de pádel vista desde arriba (10 × 20 m) que se dibuja sutilmente alrededor del logo.
class _CourtPainter extends CustomPainter {
  _CourtPainter({required this.progress});
  final double progress;

  static const _line = Color(0x73AED21A); // lime500 al 45 %: se intuye, no compite con el logo

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = math.min(size.width - 48, (size.height - 96) / 2);
    final r = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: w * 2);
    final service = r.height * 6.95 / 20;
    final c = r.center;
    // La línea central se corta alrededor del logo y el nombre, y no se dibuja la red:
    // la pista enmarca el contenido sin pasar por encima.
    final gapTop = math.min(service, 150.0), gapBottom = math.min(service, 140.0);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)))
      ..moveTo(r.left, c.dy - service)
      ..lineTo(r.right, c.dy - service)
      ..moveTo(r.left, c.dy + service)
      ..lineTo(r.right, c.dy + service)
      ..moveTo(c.dx, c.dy - service)
      ..lineTo(c.dx, c.dy - gapTop)
      ..moveTo(c.dx, c.dy + service)
      ..lineTo(c.dx, c.dy + gapBottom);
    final paint = Paint()
      ..color = _line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_CourtPainter o) => o.progress != progress;
}
