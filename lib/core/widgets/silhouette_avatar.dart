import 'package:flutter/widgets.dart';
import '../theme/design_tokens.dart';

/// Avatar por defecto del prototipo para jugadores sin foto: silueta (cabeza + hombros) sobre un fondo de la paleta.
/// Reproduce el HTML (cabeza 34 % al 20 % de alto; hombros 78 % × 70 % al 60 %, esquinas superiores redondas).
/// El color se elige de forma estable a partir de [seed] (id del usuario), igual que los cuatro tonos del HTML.
class SilhouetteAvatar extends StatelessWidget {
  const SilhouetteAvatar({super.key, required this.seed, this.size = 44});
  final String seed;
  final double size;

  /// (fondo, silueta) — las combinaciones usadas en el prototipo.
  static const palette = [
    (AppColors.ink900, AppColors.ink50),
    (AppColors.lime300, AppColors.ink900),
    (AppColors.ink900, AppColors.lime300),
    (AppColors.ink50, AppColors.ink500),
  ];

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length];
    return ClipOval(child: SizedBox(width: size, height: size, child: CustomPaint(painter: _SilhouettePainter(bg, fg))));
  }
}

class _SilhouettePainter extends CustomPainter {
  _SilhouettePainter(this.bg, this.fg);
  final Color bg, fg;
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = bg);
    final p = Paint()..color = fg..isAntiAlias = true;
    final head = s.width * .34;
    c.drawOval(Rect.fromLTWH((s.width - head) / 2, s.height * .20, head, s.height * .34), p);
    final w = s.width * .78, h = s.height * .70;
    c.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH((s.width - w) / 2, s.height * .60, w, h),
        topLeft: Radius.elliptical(w / 2, h / 2), topRight: Radius.elliptical(w / 2, h / 2)), p);
  }
  @override
  bool shouldRepaint(_SilhouettePainter o) => o.bg != bg || o.fg != fg;
}
