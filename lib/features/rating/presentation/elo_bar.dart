import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/plobby_theme.dart';
import '../domain/rating_models.dart';

/// Barra horizontal animada: base forest, relleno lime, destello que recorre el relleno,
/// marcador con halo y umbrales de la configuración. Con "reducir movimiento" se pinta final y sin destello.
class EloBar extends StatefulWidget {
  const EloBar({super.key, required this.elo, required this.scale});
  final int elo;
  final RatingScale scale;
  @override
  State<EloBar> createState() => _EloBarState();
}

class _EloBarState extends State<EloBar> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = MediaQuery.of(context).disableAnimations;
    if (r != _reduced || !_fill.isAnimating && _fill.value == 0) {
      _reduced = r;
      if (r) { _fill.value = 1; _glow.stop(); }
      else { _fill.forward(); _glow.repeat(); }
    }
  }

  @override
  void dispose() { _fill.dispose(); _glow.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'ELO ${widget.elo} en una escala de ${widget.scale.min} a ${widget.scale.max}',
        child: Column(children: [
          SizedBox(height: 28, width: double.infinity, child: AnimatedBuilder(
            animation: Listenable.merge([_fill, _glow]),
            builder: (_, __) => CustomPaint(painter: _BarPainter(widget.scale, widget.elo, Curves.easeOutCubic.transform(_fill.value), _glow.value, _reduced)),
          )),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (_, c) => SizedBox(height: 32, child: Stack(children: [
            for (final t in widget.scale.tiers)
              Positioned(
                left: (c.maxWidth * (t.from - widget.scale.min) / (widget.scale.max - widget.scale.min)).clamp(0, c.maxWidth - 60).toDouble(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: PlobbyColors.ivory)),
                  Text('${t.from}', style: TextStyle(fontSize: 10, color: PlobbyColors.ivory.withOpacity(.6))),
                ]),
              ),
          ]))),
        ]),
      );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.scale, this.elo, this.t, this.glow, this.reduced);
  final RatingScale scale; final int elo; final double t, glow; final bool reduced;

  @override
  void paint(Canvas canvas, Size s) {
    final h = 12.0, y = (s.height - h) / 2;
    final track = RRect.fromRectAndRadius(Rect.fromLTWH(0, y, s.width, h), const Radius.circular(6));
    canvas.drawRRect(track, Paint()..color = Colors.white.withOpacity(.12));
    final w = s.width * scale.fraction(elo) * t;
    if (w > 0) {
      final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, y, w, h), const Radius.circular(6));
      canvas.drawRRect(fill, Paint()..shader = const LinearGradient(colors: [AppColors.lime400, AppColors.lime300]).createShader(Rect.fromLTWH(0, y, w, h)));
      if (!reduced) {
        canvas.save();
        canvas.clipRRect(fill);
        final gx = -40 + (w + 80) * glow;
        canvas.drawRect(Rect.fromLTWH(gx - 30, y, 60, h), Paint()..shader = LinearGradient(colors: [Colors.white.withOpacity(0), Colors.white.withOpacity(.55), Colors.white.withOpacity(0)]).createShader(Rect.fromLTWH(gx - 30, y, 60, h)));
        canvas.restore();
      }
      final cx = w;
      canvas.drawCircle(Offset(cx, s.height / 2), 13, Paint()..color = PlobbyColors.lime.withOpacity(.25 + (reduced ? 0 : .15 * math.sin(glow * 2 * math.pi))));
      canvas.drawCircle(Offset(cx, s.height / 2), 8, Paint()..color = PlobbyColors.ivory);
      canvas.drawCircle(Offset(cx, s.height / 2), 8, Paint()..color = PlobbyColors.lime..style = PaintingStyle.stroke..strokeWidth = 3);
    }
    for (final tier in scale.tiers.skip(1)) {
      final x = s.width * (tier.from - scale.min) / (scale.max - scale.min);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + h + 3), Paint()..color = Colors.white.withOpacity(.35)..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.t != t || o.glow != glow || o.elo != elo;
}
