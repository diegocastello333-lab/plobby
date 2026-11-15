import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../motion/app_motion.dart';
import '../theme/design_tokens.dart';

/// Tres «luces» difusas sobre el marfil de Plobby. Solo colores de la paleta (lima, tinta, pista) con alfa bajo, para
/// dar profundidad sin competir con el contenido.
@immutable
class AmbientPalette {
  const AmbientPalette(this.a, this.b, this.c);
  final Color a, b, c;

  static AmbientPalette lerp(AmbientPalette x, AmbientPalette y, double t) =>
      AmbientPalette(Color.lerp(x.a, y.a, t)!, Color.lerp(x.b, y.b, t)!, Color.lerp(x.c, y.c, t)!);

  /// Inicio: lima cálida arriba a la izquierda.
  static const home = AmbientPalette(Color(0x66D2F548), Color(0x40E3F88E), Color(0x26EEFBC0));
  /// Feed: lima suave con un toque de tinta.
  /// (A la izquierda, tras el logotipo lima, solo tinta clara: el lima detrás del lima restaría contraste.)
  static const feed = AmbientPalette(Color(0x40D5DAD6), Color(0x5CD2F548), Color(0x26E3F88E));
  /// Ligas: lima intensa.
  static const leagues = AmbientPalette(Color(0x73D2F548), Color(0x33AED21A), Color(0x1FE3F88E));
  /// Torneos: azul pista + lima.
  static const tournaments = AmbientPalette(Color(0x386EA8FF), Color(0x52D2F548), Color(0x1F2F6FDE));
  /// Perfil: tinta clara + lima.
  static const profile = AmbientPalette(Color(0x40D5DAD6), Color(0x4DD2F548), Color(0x1F8A938D));
}

/// Fondo vivo: el marfil de Plobby con tres degradados radiales que se desplazan muy despacio (un ciclo de 24 s) y que
/// cambian de color con suavidad al moverse por [position] dentro de [palettes] (con decimales = mezcla de dos).
///
/// - [offset] se suma en vivo a la posición (p. ej. el desplazamiento de un `PageView`), sin animación propia: el color
///   sigue al dedo como en los selectores de plan paginados.
/// - Al cambiar [position], el color viaja hasta el nuevo valor en 650 ms (easeInOutCubic).
/// - Solo se repinta la capa del fondo (RepaintBoundary); el contenido no se reconstruye.
/// - Con «reducir movimiento» no hay deriva y los cambios son instantáneos.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, required this.palettes, this.position = 0, this.offset, this.child});
  final List<AmbientPalette> palettes;
  final double position;
  final ValueListenable<double>? offset;
  final Widget? child;

  /// Los tests lo desactivan (una animación infinita impediría `pumpAndSettle`).
  static bool driftEnabled = true;
  static const driftPeriod = Duration(seconds: 24);
  static const moveDuration = Duration(milliseconds: 650);

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with TickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(vsync: this, duration: AmbientBackground.driftPeriod);
  late final AnimationController _move = AnimationController(vsync: this, duration: AmbientBackground.moveDuration, value: 1);
  late double _from = widget.position;
  bool _reduce = false;

  double get _live => widget.offset?.value ?? 0;

  double _effective() {
    final t = Curves.easeInOutCubic.transform(_move.value);
    return _from + (widget.position + _live - _from) * t;
  }

  double _phase() => _drift.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = AppAnimations.reduceMotion(context);
    if (_reduce || !AmbientBackground.driftEnabled) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void didUpdateWidget(AmbientBackground old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position || old.offset != widget.offset) {
      // Parte del color que se ve ahora (con el desplazamiento anterior) para que no haya saltos.
      final t = Curves.easeInOutCubic.transform(_move.value);
      _from = _from + (old.position + (old.offset?.value ?? 0) - _from) * t;
      if (_reduce) {
        _move.value = 1;
        _from = widget.position + _live;
      } else {
        _move.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repaint = Listenable.merge([_drift, _move, if (widget.offset != null) widget.offset!]);
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: CustomPaint(painter: _AmbientPainter(widget.palettes, _effective, _phase, repaint))),
      if (widget.child != null) widget.child!,
    ]);
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.palettes, this.position, this.phase, Listenable repaint) : super(repaint: repaint);
  final List<AmbientPalette> palettes;
  final double Function() position, phase;

  AmbientPalette _paletteAt(double p) {
    if (palettes.length == 1) return palettes.first;
    final c = p.clamp(0.0, palettes.length - 1.0);
    final i = c.floor().clamp(0, palettes.length - 2);
    return AmbientPalette.lerp(palettes[i], palettes[i + 1], c - i);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.bg);
    final pal = _paletteAt(position());
    final a = phase() * 2 * math.pi, w = size.width, h = size.height;
    // Trayectorias de Lissajous lentas y pequeñas (≤ 8 % del ancho): se percibe vida, no movimiento.
    void blob(Color c, double cx, double cy, double r, double k, double ph) {
      final center = Offset(cx * w + math.sin(a * k + ph) * w * .08, cy * h + math.cos(a + ph) * h * .035);
      final radius = r * w;
      final paint = Paint()
        ..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
    blob(pal.a, .12, .06, .95, 1, 0);
    blob(pal.b, .92, .2, .8, 2, 1.7);
    blob(pal.c, .45, .7, 1.1, 1, 3.4);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.palettes != palettes;
}
