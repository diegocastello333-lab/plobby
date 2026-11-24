import 'package:flutter/material.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/plobby_text.dart';
import '../../../../core/widgets/plobby_components.dart';
import '../../domain/feed_grouping.dart';
import '../../domain/feed_models.dart';
import 'activity_cards.dart' show ActivityCard, avatar;

/// Tarjeta compacta para varios logros seguidos; un toque la despliega y muestra cada publicación.
class AchievementGroupCard extends StatefulWidget {
  const AchievementGroupCard({super.key, required this.group});
  final AchievementGroup group;
  @override
  State<AchievementGroupCard> createState() => _AchievementGroupCardState();
}

class _AchievementGroupCardState extends State<AchievementGroupCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final g = widget.group, people = g.people.take(3).toList();
    final titles = [for (final p in g.posts) (p.payload as AchievementPayload).title];
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(children: [
      SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        onTap: () { AppHaptics.light(); setState(() => _open = !_open); },
        child: Semantics(button: true, expanded: _open, label: '${achievementGroupTitle(g)}. ${_open ? 'Ocultar' : 'Ver'} los ${g.posts.length} logros', excludeSemantics: true,
          child: Row(children: [
            SizedBox(width: 32.0 + 20 * (people.length - 1), height: 32, child: Stack(children: [
              for (var i = people.length - 1; i >= 0; i--) Positioned(left: 20.0 * i, child: avatar(people[i], 16, ring: AppColors.surface)),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(achievementGroupTitle(g), maxLines: 2, overflow: TextOverflow.ellipsis, style: PlobbyText.headline.copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              Text(titles.take(3).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.footnote),
            ])),
            AnimatedRotation(turns: _open ? .5 : 0, duration: Motion.normal, curve: Motion.move,
                child: const Icon(Icons.expand_more, color: AppColors.textMuted)),
          ]),
        ),
      ),
      AnimatedSize(duration: Motion.normal, curve: Motion.move, alignment: Alignment.topCenter, child: _open
          ? Padding(padding: const EdgeInsets.only(top: 12), child: Column(children: [
              for (final p in g.posts) ActivityCard(key: ValueKey(p.id), post: p),
            ]))
          : const SizedBox(width: double.infinity)),
    ]));
  }
}
