import 'package:flutter/material.dart';
import '../../../core/theme/plobby_theme.dart';
import '../domain/social_models.dart';

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar(this.p, {super.key, this.size = 46});
  final PlayerSummary p;
  final double size;
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        CircleAvatar(
          radius: size / 2,
          backgroundColor: PlobbyColors.forest,
          foregroundImage: p.avatarUrl == null ? null : NetworkImage(p.avatarUrl!),
          child: Text(p.initials, style: const TextStyle(color: PlobbyColors.lime, fontWeight: FontWeight.w800)),
        ),
        if (p.online)
          Positioned(right: 0, bottom: 0, child: Semantics(label: 'En línea', child: Container(width: 12, height: 12,
              decoration: BoxDecoration(color: PlobbyColors.lime, shape: BoxShape.circle, border: Border.all(color: PlobbyColors.ivory, width: 2))))),
      ]);
}
