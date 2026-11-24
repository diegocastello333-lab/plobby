import 'dart:math' as math;
import 'dart:ui';
import '../widgets/verified_badge.dart' show VerifiedSealPainter;

/// Sello de verificado en las imágenes para compartir: la misma roseta lima del perfil, como insignia en la esquina
/// inferior derecha de la foto ([avatar] = círculo de la foto), con un aro de tinta para separarla del fondo.
void paintVerifiedMark(Canvas c, Rect avatar) {
  final r = avatar.width / 2, size = math.max(28.0, avatar.width * .34);
  final center = avatar.center + Offset(math.cos(math.pi / 4), math.sin(math.pi / 4)) * r * .92;
  c.drawCircle(center, size * .58, Paint()..color = const Color(0xFF171C19)..isAntiAlias = true);
  c.save();
  c.translate(center.dx - size / 2, center.dy - size / 2);
  VerifiedSealPainter(.35).paint(c, Size(size, size));
  c.restore();
}
