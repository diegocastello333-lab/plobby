import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/gamification_providers.dart';
import '../domain/gamification_models.dart';
import 'gamification_widgets.dart';
import 'head_to_head_screen.dart';

/// Perfil propio → «Progreso»: nivel y XP, últimas insignias y accesos a Head to Head, Ranking y Wrapped.
class ProgressSection extends ConsumerWidget {
  const ProgressSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(achievementsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      async.when(
        loading: () => const LoadingBlock(height: 96),
        error: (_, __) => ErrorStateCard(title: 'No se pudo cargar tu progreso', onRetry: () => ref.invalidate(achievementsProvider)),
        data: (a) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LevelCard(data: a, compact: true, onTap: () => context.push('/achievements')),
          if (a.unlocked.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(height: 92, child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final x in a.unlocked.take(8)) Padding(padding: const EdgeInsets.only(right: 12), child: SizedBox(width: 72, child: Column(children: [
                AchievementBadge(x, size: 52),
                const SizedBox(height: 6),
                Text(x.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: PlobbyText.help.copyWith(fontSize: 11, color: AppColors.text)),
              ]))),
            ])),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      _Action(icon: PlobbyIcons.swords, title: 'Head to Head', text: 'Compárate con un amigo', onTap: () => pickHeadToHead(context)),
      _Action(icon: PlobbyIcons.trophy, title: 'Ranking de amigos', text: 'Semana, mes, año e histórico', onTap: () => context.push('/ranking')),
      _Action(icon: PlobbyIcons.star, title: 'Plobby Wrapped', text: 'Tu mes y tu año en la pista', onTap: () => context.push('/wrapped')),
    ]);
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.text, required this.onTap});
  final PlobbyIcons icon;
  final String title, text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: SurfaceCard(onTap: onTap, child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: AppRadius.rSm),
            alignment: Alignment.center, child: PlobbyIcon(icon, size: 19)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: PlobbyText.cardTitle), Text(text, style: PlobbyText.help)])),
        const PlobbyIcon(PlobbyIcons.chev, size: 16, color: AppColors.textMuted),
      ])));
}

/// Perfil de un amigo → acceso directo a la comparativa.
class H2HTeaser extends StatelessWidget {
  const H2HTeaser({super.key, required this.otherId, required this.name});
  final String otherId, name;
  @override
  Widget build(BuildContext context) => SurfaceCard(onTap: () => context.push('/h2h/$otherId'), child: Row(children: [
        Container(width: 44, height: 44, decoration: const BoxDecoration(color: AppColors.inverse, shape: BoxShape.circle),
            alignment: Alignment.center, child: const PlobbyIcon(PlobbyIcons.swords, size: 20, color: AppColors.brand)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Head to Head', style: PlobbyText.cardTitle),
          Text('Compárate con ${name.split(' ').first}: estadísticas y enfrentamientos', style: PlobbyText.help),
        ])),
        const PlobbyIcon(PlobbyIcons.chev, size: 16, color: AppColors.textMuted),
      ]));
}

/// Amigos → tarjeta del ranking semanal con tu posición.
class RankingCard extends ConsumerWidget {
  const RankingCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(rankingProvider((RankPeriod.week, 0))).valueOrNull;
    final me = r?.me;
    final active = r?.anyActivity ?? false;
    final leader = active ? r!.ranked(RankMetric.wins).first : null;
    return Semantics(button: true, label: 'Ranking de amigos${me != null && active ? ', vas ${me.posWins}º esta semana' : ''}', excludeSemantics: true,
      child: GestureDetector(onTap: () => context.push('/ranking'), child: Container(
        padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg),
        child: Row(children: [
          Container(width: 52, height: 52, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle), alignment: Alignment.center,
              child: me != null && active
                  ? Text('${me.posWins}º', style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.brandInk))
                  : const PlobbyIcon(PlobbyIcons.trophy, size: 22, color: AppColors.brandInk)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ranking de amigos', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.ink50)),
            const SizedBox(height: 2),
            Text(!active ? 'Esta semana aún no ha jugado nadie' : leader!.player.id == r!.meId ? 'Lideras la semana con ${me!.wins} victorias'
                : 'Lidera ${leader.player.first} · tú vas ${me?.posWins ?? '-'}º', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: Color(0xB3F6F8F1))),
          ])),
          const PlobbyIcon(PlobbyIcons.chev, size: 16, color: Color(0x99F6F8F1)),
        ]),
      )));
  }
}
