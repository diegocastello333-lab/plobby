import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/plobby_icon.dart';

/// Imágenes predeterminadas para grupos (se guarda solo el id en `conversations.avatar_id`). Colores e iconos de
/// `GPRE` del prototipo HTML; los ids p1–p8 no cambian.
class GroupPreset {
  const GroupPreset(this.id, this.icon, this.bg, this.fg);
  final String id; final PlobbyIcons icon; final Color bg, fg;
}

const groupPresets = <GroupPreset>[
  GroupPreset('p1', PlobbyIcons.ball, Color(0xFF171C19), Color(0xFFD2F548)),
  GroupPreset('p2', PlobbyIcons.trophy, Color(0xFF2F6B3A), Color(0xFFF6F8F1)),
  GroupPreset('p3', PlobbyIcons.star, Color(0xFFD2F548), Color(0xFF171C19)),
  GroupPreset('p4', PlobbyIcons.flame, Color(0xFF3B4A7A), Color(0xFFD2F548)),
  GroupPreset('p5', PlobbyIcons.whistle, Color(0xFF8A5A2B), Color(0xFFF6F8F1)),
  GroupPreset('p6', PlobbyIcons.swords, Color(0xFF7A3B5A), Color(0xFFF6F8F1)),
  GroupPreset('p7', PlobbyIcons.users, Color(0xFF1F6F78), Color(0xFFF6F8F1)),
  GroupPreset('p8', PlobbyIcons.timer, Color(0xFFC4282E), Color(0xFFF6F8F1)),
];

GroupPreset presetFor(String? id) => groupPresets.firstWhere((p) => p.id == id, orElse: () => groupPresets.first);

/// Foto circular del grupo: imagen subida (red o bytes) → predeterminada → icono por defecto.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, this.url, this.bytes, this.presetId, this.size = 48});
  final String? url, presetId; final Uint8List? bytes; final double size;
  @override
  Widget build(BuildContext context) {
    final Widget inner;
    if (bytes != null) {
      inner = Image.memory(bytes!, width: size, height: size, fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty) {
      inner = Image.network(url!, width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => _preset());
    } else {
      inner = _preset();
    }
    return Semantics(label: 'Foto del grupo', image: true, child: SizedBox(width: size, height: size, child: ClipOval(child: inner)));
  }
  Widget _preset() {
    final p = presetFor(presetId);
    return Container(width: size, height: size, color: p.bg, child: Center(child: PlobbyIcon(p.icon, size: size * .46, strokeWidth: size > 60 ? 1.6 : 1.9, color: p.fg)));
  }
}

/// Selector de imagen de grupo (`gPicker`): vista previa 72, botón discontinuo «Subir desde la galería» y fila de
/// predeterminadas de 36 px con aro de selección. El llamador decide qué hacer con el resultado.
class GroupAvatarPicker extends StatelessWidget {
  const GroupAvatarPicker({super.key, required this.presetId, required this.bytes, required this.onPreset, required this.onGallery});
  final String? presetId; final Uint8List? bytes; final ValueChanged<String> onPreset; final VoidCallback onGallery;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GroupAvatar(bytes: bytes, presetId: presetId, size: 72),
          const SizedBox(width: 14),
          Expanded(child: Semantics(button: true, label: 'Subir desde la galería', excludeSemantics: true, child: InkWell(
            borderRadius: BorderRadius.circular(12), onTap: onGallery,
            child: CustomPaint(painter: _DashedRRect(), child: const SizedBox(height: 48, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              PlobbyIcon(PlobbyIcons.image, size: 18), SizedBox(width: 8),
              Flexible(child: Text('Subir desde la galería', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text))),
            ]))),
          ))),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in groupPresets) Semantics(button: true, selected: bytes == null && presetId == p.id, label: 'Imagen ${p.id}', excludeSemantics: true, child: InkWell(
              customBorder: const CircleBorder(), onTap: () => onPreset(p.id),
              child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: bytes == null && presetId == p.id ? AppColors.ink900 : Colors.transparent, width: 2)),
                  child: GroupAvatar(presetId: p.id, size: 34)))),
        ]),
      ]);
}

class _DashedRRect extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()..color = AppColors.borderStrong..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(12)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) { c.drawPath(m.extractPath(d, d + 5), paint); }
    }
  }
  @override
  bool shouldRepaint(_DashedRRect o) => false;
}
