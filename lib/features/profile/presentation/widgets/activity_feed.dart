import 'package:flutter/material.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/profile_providers.dart';
import 'win_streak_badge.dart';

/// Actividad compacta derivada de los datos confirmados. Los likes/comentarios se
/// persistirán en una tabla `activity_reactions` (pendiente de backend).
class ActivityFeed extends StatefulWidget {
  const ActivityFeed({super.key, required this.view});
  final ProfileView view;
  @override
  State<ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<ActivityFeed> {
  final liked = <String>{};
  @override
  Widget build(BuildContext context) {
    final v = widget.view, last = v.confirmed.isEmpty ? null : v.confirmed.first, k = v.streak;
    final items = <(String, String, Widget)>[
      if (last != null) ('m', '${last.won ? 'Ganó' : 'Perdió'} ${last.scoreLabel} con ${last.partner.name} en ${last.venue}', Icon(last.won ? Icons.emoji_events_outlined : Icons.sports_tennis, size: 18, color: PlobbyColors.forest)),
      if (k.current >= 3) ('s', 'Racha de ${k.current} victorias seguidas', WinStreakBadge(streak: k.current, size: 20, showNumber: false)),
      ('e', 'Superó los ${(v.data.currentElo ~/ 100) * 100} de ELO', const Icon(Icons.trending_up, size: 18, color: PlobbyColors.forest)),
      ('l', 'Se unió a BÜNKER PADEL LEAGUE · Temporada 02', const Icon(Icons.groups_2_outlined, size: 18, color: PlobbyColors.forest)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [for (final it in items) ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(radius: 18, backgroundColor: const Color(0xFFEEF1EA), child: it.$3),
        title: Text(it.$2, style: const TextStyle(fontSize: 13.5)),
        trailing: IconButton(
          tooltip: 'Me gusta', onPressed: () => setState(() => liked.contains(it.$1) ? liked.remove(it.$1) : liked.add(it.$1)),
          icon: Icon(liked.contains(it.$1) ? Icons.thumb_up : Icons.thumb_up_outlined, size: 18, color: liked.contains(it.$1) ? PlobbyColors.forest : PlobbyColors.mute)),
      )]),
    );
  }
}
