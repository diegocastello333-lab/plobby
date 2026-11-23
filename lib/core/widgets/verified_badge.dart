import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../motion/app_motion.dart';
import '../theme/design_tokens.dart';

/// Sello de perfil verificado: roseta lima de Plobby con un brillo holográfico (reflejo iridiscente que gira y una
/// franja de luz que lo cruza) y el check en tinta. Con «reducir movimiento» queda quieto; en la web el brillo se
/// detiene tras unos ciclos (IdleMotion) para no gastar batería en reposo.
class VerifiedBadge extends StatefulWidget {
  const VerifiedBadge({super.key, this.size = 22});
  final double size;
  @override
  State<VerifiedBadge> createState() => _VerifiedBadgeState();
}

class _VerifiedBadgeState extends State<VerifiedBadge> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));   // timing: una vuelta del reflejo

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
      _c.value = .18;   // pose fija con el reflejo visible
    } else if (!_c.isAnimating) {
      IdleMotion.loop(_c, rest: .18);
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Perfil verificado', image: true,
        child: ExcludeSemantics(child: RepaintBoundary(child: SizedBox.square(dimension: widget.size,
            child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: VerifiedSealPainter(_c.value)))))),
      );
}

/// Pinta el sello en `t` (0–1, fase del brillo). Público para los tests.
class VerifiedSealPainter extends CustomPainter {
  VerifiedSealPainter(this.t);
  final double t;

  static const _lobes = 9;

  /// Roseta de [_lobes] lóbulos redondeados: «valles» en un radio interior y curvas que se hinchan hacia fuera.
  static Path seal(Size s) {
    final c = s.center(Offset.zero), r = s.shortestSide / 2;
    final valley = r * .80, bulge = r * 1.14;
    final p = Path();
    for (var i = 0; i <= _lobes; i++) {
      final a = -math.pi / 2 + (i + .5) * 2 * math.pi / _lobes;
      final pt = c + Offset(math.cos(a), math.sin(a)) * valley;
      if (i == 0) { p.moveTo(pt.dx, pt.dy); continue; }
      final m = a - math.pi / _lobes;
      final ctrl = c + Offset(math.cos(m), math.sin(m)) * bulge;
      p.quadraticBezierTo(ctrl.dx, ctrl.dy, pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size, path = seal(size), r = size.shortestSide / 2;
    // halo lima suave (se lee sobre la cabecera oscura)
    canvas.drawPath(path, Paint()..color = AppColors.lime300.withValues(alpha: .45)..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .35));
    canvas.save();
    canvas.clipPath(path);
    // base lima con volumen (más clara arriba a la izquierda)
    canvas.drawRect(rect, Paint()..shader = const RadialGradient(center: Alignment(-.45, -.55), radius: 1.05,
        colors: [Color(0xFFEAFF8C), AppColors.lime300, Color(0xFF9CC414)], stops: [0, .5, 1]).createShader(rect));
    // reflejo holográfico: barrido iridiscente que gira con t, mezclado suave sobre el lima
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.overlay
      ..shader = SweepGradient(transform: GradientRotation(t * 2 * math.pi), colors: const [
        Color(0x9966FFD8), Color(0x9980B8FF), Color(0x99E09CFF), Color(0x99FFE36A), Color(0x99B8FF5A), Color(0x9966FFD8),
      ]).createShader(rect));
    // franja de luz diagonal que cruza el sello
    final x = -1.6 + t * 3.2;
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(begin: Alignment(x - .5, -1), end: Alignment(x + .5, 1), colors: const [
        Color(0x00FFFFFF), Color(0x73FFFFFF), Color(0x00FFFFFF),
      ], stops: const [.40, .5, .60]).createShader(rect));
    canvas.restore();
    // canto fino para separar el sello del fondo
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = math.max(.8, r * .07)..color = const Color(0x80F4FFD0));
    // check en tinta
    final check = Path()
      ..moveTo(size.width * .31, size.height * .52)
      ..lineTo(size.width * .45, size.height * .65)
      ..lineTo(size.width * .70, size.height * .38);
    canvas.drawPath(check, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round
      ..strokeWidth = r * .22..color = AppColors.ink900);
  }

  @override
  bool shouldRepaint(VerifiedSealPainter old) => old.t != t;
}
