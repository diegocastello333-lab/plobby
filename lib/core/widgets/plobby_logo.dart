import 'package:flutter/material.dart';
import '../theme/plobby_theme.dart';

/// Logo de Plobby EXACTO del artefacto de marca (concepto A «Pala»): P-pala perforada + bola, y el
/// wordmark «plobby» en Unbounded 700, tracking -0.03em. Geometría copiada del SVG original
/// (viewBox 16 12 72 76). Vectorial: nítido en Android e iOS a cualquier densidad.
/// Variante lima para fondos oscuros/foto (Home); `ink: true` para fondos claros.
class PlobbyMark extends StatelessWidget {
  const PlobbyMark({super.key, this.height = 30, this.color = AppColors.lime300});
  final double height;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: height * 72 / 76, height: height, child: CustomPaint(painter: _MarkPainter(color)));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.scale(s.width / 72, s.height / 76);
    canvas.translate(-16, -12);
    final fill = Paint()..color = c..isAntiAlias = true;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(24, 22, 14, 64), const Radius.circular(7)), fill);
    canvas.drawCircle(const Offset(54, 40), 19.5, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 13..isAntiAlias = true);
    for (final y in [34.5, 40.0, 45.5]) { for (final x in [48.5, 54.0, 59.5]) { canvas.drawCircle(Offset(x, y), 1.7, fill); } }
    canvas.drawCircle(const Offset(78, 78), 7, fill);
  }
  @override
  bool shouldRepaint(_MarkPainter o) => o.c != c;
}

class PlobbyLogo extends StatelessWidget {
  const PlobbyLogo({super.key, this.markHeight = 30, this.ink = false});
  final double markHeight;
  final bool ink;
  @override
  Widget build(BuildContext context) {
    final color = ink ? AppColors.ink900 : AppColors.lime300;
    return Semantics(
      label: 'Plobby',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Solo el texto «plobby» (sin el símbolo "P"): mismo tipo, peso y color.
        Text('plobby', style: TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w700, fontSize: markHeight * 0.8, letterSpacing: -0.03 * markHeight * 0.8, height: 1, color: color)),
      ]),
    );
  }
}
