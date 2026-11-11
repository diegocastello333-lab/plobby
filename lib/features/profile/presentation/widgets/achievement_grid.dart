import 'package:flutter/material.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../domain/achievements.dart';

class AchievementGrid extends StatelessWidget {
  const AchievementGrid({super.key, required this.items});
  final List<Achievement> items;
  @override
  Widget build(BuildContext context) => GridView.count(
      crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .86,
      children: [for (final a in items) _Item(a)]);
}

class _Item extends StatelessWidget {
  const _Item(this.a);
  final Achievement a;
  @override
  Widget build(BuildContext context) {
    final ok = a.unlocked;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 40, backgroundColor: ok ? PlobbyColors.lime : const Color(0xFFD5DAD6), child: Icon(Icons.emoji_events_outlined, size: 36, color: ok ? PlobbyColors.forest : PlobbyColors.sage)),
          const SizedBox(height: 14),
          Text(a.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(a.description, textAlign: TextAlign.center, style: const TextStyle(color: PlobbyColors.mute)),
          const SizedBox(height: 16),
          if (ok) const Text('Desbloqueado', style: TextStyle(fontWeight: FontWeight.w800, color: PlobbyColors.forest))
          else ...[LinearProgressIndicator(value: a.progress, minHeight: 6, borderRadius: BorderRadius.circular(3), color: PlobbyColors.forest, backgroundColor: const Color(0xFFD5DAD6)), const SizedBox(height: 8), Text('${a.current} de ${a.goal}')],
        ]),
      )),
      child: Ink(
        decoration: BoxDecoration(color: ok ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(14), border: ok ? null : Border.all(color: const Color(0x22171C19))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(radius: 28, backgroundColor: ok ? PlobbyColors.lime : const Color(0xFFD5DAD6), child: Icon(Icons.emoji_events_outlined, color: ok ? PlobbyColors.forest : PlobbyColors.sage)),
          const SizedBox(height: 8),
          Text(a.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text(ok ? 'Desbloqueado' : '${a.current}/${a.goal}', style: const TextStyle(fontSize: 11, color: PlobbyColors.mute)),
        ]),
      ),
    );
  }
}
