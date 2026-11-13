import 'package:flutter/material.dart';
import '../domain/auth_models.dart';

/// Avatares deportivos predefinidos (no son círculos de color liso): fondo de pista con degradado, líneas de pista,
/// pelota, jugador con visera/cinta/gorra. Se guarda solo el id (`a1`..`a12`) en `profiles.avatar_id`.
enum _Gear { head, visor, band, cap }
class _Def {
  const _Def(this.name, this.c1, this.c2, this.accent, this.skin, this.gear);
  final String name; final Color c1, c2, accent, skin; final _Gear gear;
}
const _defs = <String, _Def>{
  'a1': _Def('Remate', Color(0xFFD2F548), Color(0xFF8FB91B), Color(0xFF171C19), Color(0xFFE8B98F), _Gear.head),
  'a2': _Def('Víbora', Color(0xFF171C19), Color(0xFF3A453F), Color(0xFFD2F548), Color(0xFFC58C5E), _Gear.visor),
  'a3': _Def('Bandeja', Color(0xFF2F6FDE), Color(0xFF1C3F8A), Colors.white, Color(0xFFF1C9A5), _Gear.band),
  'a4': _Def('Smash', Color(0xFFF97316), Color(0xFFB83E0B), Colors.white, Color(0xFF8A5A3B), _Gear.cap),
  'a5': _Def('Globo', Color(0xFF14B8A6), Color(0xFF0B6E63), Colors.white, Color(0xFFE8B98F), _Gear.head),
  'a6': _Def('Chiquita', Color(0xFFEC4899), Color(0xFF9D1F63), Colors.white, Color(0xFFC58C5E), _Gear.band),
  'a7': _Def('Pared', Color(0xFF6D5BD0), Color(0xFF3B2E94), Color(0xFFD2F548), Color(0xFFF1C9A5), _Gear.visor),
  'a8': _Def('Volea', Color(0xFFEAB308), Color(0xFF9A7203), Color(0xFF171C19), Color(0xFF8A5A3B), _Gear.cap),
  'a9': _Def('Derecha', Color(0xFF22C55E), Color(0xFF0F7A37), Colors.white, Color(0xFFE8B98F), _Gear.band),
  'a10': _Def('Revés', Color(0xFFEF4444), Color(0xFF9B1C1C), Colors.white, Color(0xFFC58C5E), _Gear.head),
  'a11': _Def('Red', Color(0xFF0EA5E9), Color(0xFF0A6389), Color(0xFF171C19), Color(0xFFF1C9A5), _Gear.visor),
  'a12': _Def('Pista', Color(0xFF171C19), Color(0xFF2F6FDE), Color(0xFFD2F548), Color(0xFF8A5A3B), _Gear.cap),
};
/// Pinta un avatar predefinido en un Canvas (cuadrado `s`×`s` en el origen). Lo usa el exportador PNG de Match Recap.
bool paintPlobbyAvatar(Canvas canvas, double s, String id) {
  final d = _defs[id];
  if (d == null) return false;
  _AvatarPainter(d).paint(canvas, Size(s, s));
  return true;
}
String avatarName(String id) => _defs[id]?.name ?? 'Avatar';

class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.d);
  final _Def d;
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 104;
    c.save(); c.scale(k);
    final rect = const Rect.fromLTWH(0, 0, 104, 104);
    c.drawRect(rect, Paint()..shader = LinearGradient(colors: [d.c1, d.c2], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(rect));
    final line = Paint()..color = Colors.white.withOpacity(.22)..style = PaintingStyle.stroke..strokeWidth = 1.6;
    c.drawRect(const Rect.fromLTWH(10, 14, 84, 84), line);
    c.drawLine(const Offset(10, 56), const Offset(94, 56), line); c.drawLine(const Offset(52, 14), const Offset(52, 98), line);
    c.drawCircle(const Offset(86, 22), 7, Paint()..color = const Color(0xFFD2F548));
    final body = Path()..moveTo(14, 104)..quadraticBezierTo(16, 74, 52, 74)..quadraticBezierTo(88, 74, 90, 104)..close();
    c.drawPath(body, Paint()..color = d.accent);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(45, 64, 14, 14), const Radius.circular(6)), Paint()..color = d.skin);
    c.drawOval(const Rect.fromLTWH(35, 31, 34, 38), Paint()..color = d.skin);
    final gear = Paint()..color = d.accent;
    switch (d.gear) {
      case _Gear.head: c.drawPath(Path()..moveTo(34, 41)..cubicTo(34, 29, 43, 22, 52, 22)..cubicTo(61, 22, 70, 29, 70, 41)..cubicTo(64, 38, 58, 37, 52, 37)..cubicTo(46, 37, 40, 38, 34, 41), gear); break;
      case _Gear.visor: c.drawPath(Path()..moveTo(33, 40)..cubicTo(36, 30, 44, 25, 52, 25)..cubicTo(60, 25, 68, 30, 71, 40)..close(), gear); c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 38, 42, 5), const Radius.circular(2.5)), gear); break;
      case _Gear.band: c.drawPath(Path()..moveTo(35, 38)..cubicTo(35, 27, 43, 21, 52, 21)..cubicTo(61, 21, 69, 27, 69, 38)..close(), Paint()..color = const Color(0xD92A2F2C)); c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(34, 35, 36, 6), const Radius.circular(3)), gear); break;
      case _Gear.cap: c.drawPath(Path()..moveTo(34, 40)..cubicTo(34, 29, 42, 22, 52, 22)..cubicTo(62, 22, 70, 29, 70, 40)..close(), gear); c.drawPath(Path()..moveTo(52, 38)..lineTo(78, 38)..cubicTo(78, 42, 72, 44, 52, 41)..close(), Paint()..color = d.accent.withOpacity(.85)); break;
    }
    final dark = Paint()..color = const Color(0xFF171C19);
    c.drawCircle(const Offset(46, 52), 1.7, dark); c.drawCircle(const Offset(58, 52), 1.7, dark);
    c.drawPath(Path()..moveTo(47, 60)..quadraticBezierTo(52, 64, 57, 60), Paint()..color = const Color(0xFF171C19)..style = PaintingStyle.stroke..strokeWidth = 1.8..strokeCap = StrokeCap.round);
    c.restore();
  }
  @override
  bool shouldRepaint(_AvatarPainter o) => o.d != d;
}

/// Muestra un avatar predefinido (circular). `semanticsLabel` para accesibilidad.
class PlobbyAvatar extends StatelessWidget {
  const PlobbyAvatar({super.key, required this.id, this.size = 48});
  final String id; final double size;
  @override
  Widget build(BuildContext context) {
    final d = _defs[id] ?? _defs['a1']!;
    return Semantics(label: 'Avatar ${d.name}', image: true, child: ClipOval(child: SizedBox(width: size, height: size, child: CustomPaint(painter: _AvatarPainter(d)))));
  }
}

/// Vista previa + selección. Foto de galería o avatar (uno u otro). Reutilizable en onboarding y en Editar perfil.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({super.key, required this.data, required this.onAvatar, required this.onPickPhoto, this.error, this.busy = false});
  final OnboardingData data; final ValueChanged<String> onAvatar; final VoidCallback onPickPhoto; final String? error; final bool busy;
  @override
  Widget build(BuildContext context) {
    final hasPhoto = data.avatarUrl != null && data.avatarUrl!.isNotEmpty;
    return Column(children: [
      Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFD2F548), width: 2)),
          child: hasPhoto ? ClipOval(child: Image.network(data.avatarUrl!, width: 104, height: 104, fit: BoxFit.cover, cacheWidth: 312, errorBuilder: (_, __, ___) => const SizedBox(width: 104, height: 104)))
              : data.avatarId != null ? PlobbyAvatar(id: data.avatarId!, size: 104)
              : const CircleAvatar(radius: 52, backgroundColor: Color(0xFFEEF1EA), child: Icon(Icons.person_outline, size: 44))),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: busy ? null : onPickPhoto, icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image_outlined), label: const Text('Subir foto de la galería'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
      const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('o elige un avatar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5C6660)))),
      GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, children: [
        for (final id in avatarIds)
          Semantics(button: true, selected: data.avatarId == id && !hasPhoto, label: 'Avatar ${avatarName(id)}',
              child: GestureDetector(onTap: () => onAvatar(id), child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: data.avatarId == id && !hasPhoto ? const Color(0xFF171C19) : Colors.transparent, width: 2.5)),
                  padding: const EdgeInsets.all(2), child: PlobbyAvatar(id: id, size: 64)))),
      ]),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Color(0xFFC4282E), fontWeight: FontWeight.w600, fontSize: 12))),
    ]);
  }
}
