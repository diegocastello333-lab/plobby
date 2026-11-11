import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../../auth/presentation/avatar_catalog.dart';
import '../../match_recap/domain/recap_data.dart';

/// Tarjeta compacta de resultado para el chat (inspirada en compartir actividades de Strava). Se pinta SOLO con el
/// snapshot del servidor (`messages.payload`): no hay forma de editar el resultado desde el chat, y se conserva
/// aunque el partido sea antiguo. Tocarla abre el detalle del partido (lo decide el llamador con `onTap`).
class MatchResultCard extends StatelessWidget {
  const MatchResultCard({super.key, required this.payload, this.sharerId, this.onTap, this.width = 268});
  final Map<String, dynamic> payload; final String? sharerId; final VoidCallback? onTap; final double width;

  @override
  Widget build(BuildContext context) {
    final RecapData d;
    try { d = recapFromServerJson(payload, sharerId: sharerId); } catch (_) { return const _Broken(); }
    final tag = [if (d.userWon != null) (d.userWon! ? 'VICTORIA' : 'DERROTA'), d.isLeague ? 'LIGA' : 'AMISTOSO'].join(' · ');
    final meta = [recapDate(d.playedAt), if (d.club.isNotEmpty) d.club, if (d.courtLabel.isNotEmpty) d.courtLabel].join(' · ');
    final chips = [if (d.hasDuration) recapDuration(d.durationSeconds!), if (d.eloDelta != null) '${d.eloDelta! > 0 ? '+' : ''}${d.eloDelta} ELO'];
    return Semantics(button: onTap != null, label: 'Resultado de partido ${d.sets.map((s) => '${s.$1}-${s.$2}').join(' ')}. Ganan ${d.winners.map((p) => p.first).join(' y ')}. Abrir detalle',
        child: Material(
          color: AppColors.ink900, borderRadius: AppRadius.rLg, clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Container(
            width: width, padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF232A26), AppColors.ink900], begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('plobby', style: TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -.42, color: AppColors.lime300)),
                const Spacer(),
                Flexible(child: Text(d.isLeague && d.leagueName != null ? '${tag.split(' · ').first} · ${d.leagueName}' : tag, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: Color(0xFF9AA39D)))),
              ]),
              const SizedBox(height: 10),
              // marcador por sets: el resultado es lo más visible
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(d.sets.map((s) => '${s.$1}-${s.$2}').join('   '),
                  style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w700, fontSize: 28, color: AppColors.lime300, fontFeatures: [FontFeature.tabularFigures()]))),
              const SizedBox(height: 10),
              _Side(players: d.winners, winner: true),
              const SizedBox(height: 6),
              _Side(players: d.opponents, winner: false),
              const SizedBox(height: 10),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFFB7BFB9), fontWeight: FontWeight.w500)),
              if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, children: [
                for (final c in chips) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.ink800, borderRadius: AppRadius.rSm),
                    child: Text(c, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.contains('ELO') ? (d.eloDelta! >= 0 ? AppColors.lime300 : const Color(0xFFFF8A8A)) : Colors.white))),
              ])),
            ]),
          )),
        ));
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.players, required this.winner});
  final List<RecapPlayer> players; final bool winner;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (final p in players) Padding(padding: const EdgeInsets.only(right: 4), child: _Av(p, winner)),
        const SizedBox(width: 6),
        Expanded(child: Text(players.map((p) => p.first).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: winner ? FontWeight.w800 : FontWeight.w600, color: winner ? Colors.white : const Color(0xFF9AA39D)))),
        if (winner) const Icon(Icons.emoji_events, size: 16, color: AppColors.lime300),
      ]);
}

class _Av extends StatelessWidget {
  const _Av(this.p, this.winner);
  final RecapPlayer p; final bool winner;
  @override
  Widget build(BuildContext context) {
    const s = 30.0;
    final Widget w = p.avatarUrl != null && p.avatarUrl!.isNotEmpty
        ? Image.network(p.avatarUrl!, width: s, height: s, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ini())
        : p.avatarId != null ? PlobbyAvatar(id: p.avatarId!, size: s) : _ini();
    return Container(width: s + 4, height: s + 4, padding: const EdgeInsets.all(1.5), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: winner ? AppColors.lime300 : const Color(0xFF5C6660), width: 1.5)), child: ClipOval(child: w));
  }
  Widget _ini() => Container(width: 30, height: 30, color: AppColors.ink800, alignment: Alignment.center, child: Text(p.initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)));
}

class _Broken extends StatelessWidget {
  const _Broken();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: AppRadius.rMd), child: const Text('Resultado no disponible'));
}
