import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../auth/presentation/avatar_catalog.dart';
import '../application/lifecycle_providers.dart';
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';
import 'match_widgets.dart';
import 'new_match_menu.dart';

/// «PRÓXIMOS PARTIDOS». Se coloca en el Home JUSTO ENCIMA de «Últimas partidas de amigos» y, con `max: null`,
/// en el perfil (antes del historial). Ambos leen `upcomingMatchesProvider`: una sola fuente, sin duplicados.
class UpcomingMatchesSection extends ConsumerWidget {
  const UpcomingMatchesSection({super.key, this.max = 3, this.showTitle = true});
  final int? max; final bool showTitle;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingMatchesProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showTitle) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Próximos partidos', style: TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 16))),
      async.when(
        loading: () => Column(children: [for (var i = 0; i < 2; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: MatchCardSkeleton())]),
        error: (_, __) => Card(child: ListTile(leading: const Icon(Icons.wifi_off), title: const Text('No se pudieron cargar tus partidos'), trailing: TextButton(onPressed: () => ref.invalidate(upcomingMatchesProvider), child: const Text('Reintentar')))),
        data: (l) {
          if (l.isEmpty) return const _Empty();
          final v = max == null ? l : l.take(max!).toList();
          return Column(children: [for (var i = 0; i < v.length; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: AppearOnce(animationKey: 'upc:${v[i].id}', index: i, child: Pressable(child: UpcomingMatchCard(match: v[i])))), if (max != null && l.length > max!) OutlinedButton(onPressed: () => context.go('/profile'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppLayout.buttonHeightCompact), alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4)), child: Text('Ver los ${l.length} partidos', textAlign: TextAlign.center))]);
        }),
    ]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: AppColors.border)),
      child: Column(children: [
        const CircleAvatar(radius: 26, backgroundColor: AppColors.brandSoft, child: Icon(Icons.sports_tennis, color: AppColors.brandText)),
        const SizedBox(height: 10),
        const Text('Todavía no tienes partidos programados.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('¡Es hora de organizar uno!', style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 14),
        ElevatedButton(onPressed: () => showNewMatchMenu(context), style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: AppColors.brandInk), child: const Text('Crear partido')),
      ]));
}

class UpcomingMatchCard extends ConsumerWidget {
  const UpcomingMatchCard({super.key, required this.match});
  final LifecycleMatch match;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    return Semantics(button: true, label: 'Partido ${formatWhen(m.scheduledAt)}, ${m.club}, ${m.status.label}', child: InkWell(
      borderRadius: AppRadius.rLg, onTap: () => context.push('/match/${m.id}'),
      child: Ink(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: AppColors.border), boxShadow: AppShadows.card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatWhen(m.scheduledAt), style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 3), Text('${m.club}${m.court != null && m.court!.isNotEmpty ? ' · ${m.court}' : ''}', style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ])),
            StatusChip(status: m.status),
          ]),
          const SizedBox(height: 14),
          Row(children: [Expanded(child: _Team(m.team(1))), const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('VS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: AppColors.textMuted))), Expanded(child: _Team(m.team(2)))]),
          const Divider(height: 24),
          Row(children: [
            Icon(m.type == MatchType.league ? Icons.emoji_events_outlined : Icons.sports_tennis, size: 14, color: m.type == MatchType.league ? AppColors.brandText : AppColors.textMuted), const SizedBox(width: 6),
            Expanded(child: Text(m.type == MatchType.league ? 'Liga · ${m.leagueName ?? ''}' : 'Amistoso', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            if (m.status == MatchStatus.live) MatchStopwatch(match: m, compact: true),
          ]),
        ]))));
  }
}

class _Team extends StatelessWidget {
  const _Team(this.players);
  final List<MatchPlayer> players;
  @override
  Widget build(BuildContext context) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 0; i < players.length; i++) Transform.translate(offset: Offset(i * -9.0, 0), child: PlayerAvatar(player: players[i], size: 34))]),
        const SizedBox(height: 6),
        Text(players.map((p) => p.name.split(' ').first).join(' y '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]);
}
