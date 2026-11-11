import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../application/lifecycle_providers.dart';
import '../domain/match_lifecycle.dart';
import 'match_widgets.dart';

/// Resultado final (solo partidos CONFIRMADOS). Accesible desde el historial de cada jugador: `/match/:id/final`.
class FinalResultScreen extends ConsumerWidget {
  const FinalResultScreen({super.key, required this.matchId});
  final String matchId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(matchProvider(matchId)).valueOrNull, uid = ref.watch(currentUserIdProvider);
    if (m == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final w = m.winnerTeam, mine = m.player(uid)?.team;
    String hm(DateTime? d) => d == null ? '—' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    Widget info(String k, String v) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: AppColors.textMuted)), const SizedBox(height: 4), Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))]));
    return Scaffold(appBar: AppBar(title: const Text('Resultado final'), centerTitle: true), body: ListView(padding: const EdgeInsets.all(20), children: [
      Container(padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16), decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg), child: Column(children: [
        Text('${mine == w ? 'VICTORIA' : 'DERROTA'} · CONFIRMADO', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, letterSpacing: 1.1, fontSize: 11)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, children: [for (final s in m.sets) Text('${s.a}-${s.b}', style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 34, color: Colors.white))]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.emoji_events_outlined, color: Colors.white, size: 16), const SizedBox(width: 8), Text('Ganan ${m.team(w!).map((p) => p.name.split(' ').first).join(' y ')}', style: const TextStyle(color: Colors.white))]),
      ])),
      const SizedBox(height: 12),
      for (final t in [1, 2]) Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: w == t ? AppColors.brandSoft : AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: w == t ? AppColors.brand : AppColors.border, width: w == t ? 2 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('EQUIPO $t${w == t ? ' · GANADOR' : ''}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
            for (final p in m.team(t)) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [PlayerAvatar(player: p, size: 44), const SizedBox(width: 12), Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${(m.eloDelta[p.id] ?? 0) > 0 ? '+' : ''}${m.eloDelta[p.id] ?? 0} ELO', style: TextStyle(fontWeight: FontWeight.w800, color: (m.eloDelta[p.id] ?? 0) >= 0 ? AppColors.success : AppColors.danger))]))])),
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 2.3, mainAxisSpacing: 10, crossAxisSpacing: 10, children: [
        info('Fecha', formatWhen(m.scheduledAt)), info('Club', '${m.club}${m.court != null && m.court!.isNotEmpty ? ' · ${m.court}' : ''}'),
        info('Duración total', m.durationSeconds == null ? '—' : '${m.durationSeconds! ~/ 3600 > 0 ? '${m.durationSeconds! ~/ 3600} h ' : ''}${(m.durationSeconds! ~/ 60) % 60} min'), info('Inicio / fin', '${hm(m.startedAt)} – ${hm(m.endedAt)}'),
        info(m.leagueName != null ? 'Liga' : 'Tipo', m.leagueName ?? 'Amistoso'), info('Confirmado', 'Los dos capitanes'),
      ]),
      if (m.bothCaptainsAccepted && m.player(uid) != null) Padding(padding: const EdgeInsets.only(top: 14), child: FilledButton.icon(onPressed: () => context.push('/match/${m.id}/share'), icon: const Icon(Icons.ios_share, size: 18), label: const Text('COMPARTIR RESULTADO'))),
    ]));
  }
}
