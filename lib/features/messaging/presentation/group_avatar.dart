import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';

/// Imágenes predeterminadas para grupos (se guarda solo el id en `conversations.avatar_id`).
class GroupPreset {
  const GroupPreset(this.id, this.icon, this.c1, this.c2);
  final String id; final IconData icon; final Color c1, c2;
}

const groupPresets = <GroupPreset>[
  GroupPreset('p1', Icons.sports_tennis, Color(0xFFD2F548), Color(0xFF8FB91B)),
  GroupPreset('p2', Icons.emoji_events, Color(0xFFEAB308), Color(0xFF9A7203)),
  GroupPreset('p3', Icons.local_fire_department, Color(0xFFF97316), Color(0xFFB83E0B)),
  GroupPreset('p4', Icons.groups, Color(0xFF2F6FDE), Color(0xFF1C3F8A)),
  GroupPreset('p5', Icons.bolt, Color(0xFF6D5BD0), Color(0xFF3B2E94)),
  GroupPreset('p6', Icons.sports_score, Color(0xFF14B8A6), Color(0xFF0B6E63)),
  GroupPreset('p7', Icons.star, Color(0xFFEC4899), Color(0xFF9D1F63)),
  GroupPreset('p8', Icons.flag, Color(0xFF171C19), Color(0xFF3A453F)),
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
      inner = Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _preset());
    } else {
      inner = _preset();
    }
    return Semantics(label: 'Foto del grupo', image: true, child: SizedBox(width: size, height: size, child: ClipOval(child: inner)));
  }
  Widget _preset() {
    final p = presetFor(presetId);
    final dark = p.c1.computeLuminance() < .3;
    return Container(width: size, height: size, decoration: BoxDecoration(gradient: LinearGradient(colors: [p.c1, p.c2], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Icon(p.icon, size: size * .5, color: dark ? AppColors.lime300 : AppColors.ink900));
  }
}

/// Selector de imagen de grupo: galería (callback) o predeterminadas. El llamador decide qué hacer con el resultado.
class GroupAvatarPicker extends StatelessWidget {
  const GroupAvatarPicker({super.key, required this.presetId, required this.bytes, required this.onPreset, required this.onGallery});
  final String? presetId; final Uint8List? bytes; final ValueChanged<String> onPreset; final VoidCallback onGallery;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GroupAvatar(bytes: bytes, presetId: presetId, size: 72),
          const SizedBox(width: 16),
          Expanded(child: OutlinedButton.icon(onPressed: onGallery, icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Subir desde la galería'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)))),
        ]),
        const SizedBox(height: 12),
        const Text('O elige una imagen', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final p in groupPresets) Semantics(button: true, selected: bytes == null && presetId == p.id, label: 'Imagen ${p.id}', child: InkWell(
              customBorder: const CircleBorder(), onTap: () => onPreset(p.id),
              child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: bytes == null && presetId == p.id ? AppColors.ink900 : Colors.transparent, width: 2)),
                  child: GroupAvatar(presetId: p.id, size: 44)))),
        ]),
      ]);
}
