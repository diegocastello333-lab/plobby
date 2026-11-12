import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../application/lifecycle_providers.dart';
import 'match_detail_screen.dart' show MatchEventLog, durationText;
import 'match_widgets.dart';

/// Resultado final (solo partidos CONFIRMADOS) — `scMFinal` del prototipo HTML. Accesible desde el historial de cada
/// jugador: `/match/:id/final`.
class FinalResultScreen extends ConsumerWidget {
  const FinalResultScreen({super.key, required this.matchId});
  final String matchId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(matchProvider(matchId)).valueOrNull, uid = ref.watch(currentUserIdProvider);
    if (m == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.text)));
    final w = m.winnerTeam, mine = m.player(uid)?.team;
    String hm(DateTime? d) => d == null ? '—' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(body: Column(children: [
      PlobbyHeaderBar(title: 'Resultado final', onBack: () => context.pop()),
      Expanded(child: ListView(padding: EdgeInsets.fromLTRB(20, 16, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
        // .fn-hero
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg),
          child: Column(children: [
            Text('${mine == w ? 'VICTORIA' : 'DERROTA'} · CONFIRMADO', textAlign: TextAlign.center, style: PlobbyText.eb.copyWith(color: AppColors.brand)),
            const SizedBox(height: 14),
            Semantics(label: 'Sets: ${m.sets.map((s) => '${s.a}-${s.b}').join(', ')}', excludeSemantics: true, child: Wrap(alignment: WrapAlignment.center, spacing: 10, children: [
              for (var i = 0; i < m.sets.length; i++) _SetIn(delay: reduce ? Duration.zero : Duration(milliseconds: 100 * i), animate: !reduce, child: Text('${m.sets[i].a}-${m.sets[i].b}',
                  style: const TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, fontSize: 34, letterSpacing: -0.68, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]))),
            ])),
            const SizedBox(height: 10),
            if (w != null) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const PlobbyIcon(PlobbyIcons.trophy, size: 16, color: Color(0xD9FFFFFF)), const SizedBox(width: 8),
              Flexible(child: Text('Ganan ${m.team(w).map((p) => p.name.split(' ').first).join(' y ')}',
                  style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, letterSpacing: 0, color: Color(0xD9FFFFFF)))),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        for (final t in [1, 2]) Padding(padding: const EdgeInsets.only(bottom: 10), child: TeamCard(
          match: m, team: t, winner: w == t, uid: uid, avatarSize: 44,
          subtitle: (p) => p.elo > 0 ? '${p.elo} ELO' : p.level,
          trailing: (p) {
            final d = m.eloDelta[p.id];
            if (d == null) return null;
            return Text('${d > 0 ? '+' : ''}$d', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0, color: d >= 0 ? const Color(0xFF2E7D32) : AppColors.danger));
          },
        )),
        const SizedBox(height: 2),
        // .fn-info: rejilla 2 columnas
        LayoutBuilder(builder: (_, c) {
          final cw = (c.maxWidth - 10) / 2;
          Widget info(String k, String v) => Container(width: cw, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.toUpperCase(), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .55, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                Text(v, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontWeight: FontWeight.w700, fontSize: 13.5, letterSpacing: 0, color: AppColors.text)),
              ]));
          return Wrap(spacing: 10, runSpacing: 10, children: [
            info('Fecha', formatWhen(m.scheduledAt)), info('Club', '${m.club}${m.court != null && m.court!.isNotEmpty ? ' · ${m.court}' : ''}'),
            info('Duración total', m.durationSeconds == null ? '—' : durationText(m.durationSeconds!)), info('Inicio / fin', m.startedAt == null ? '—' : '${hm(m.startedAt)} – ${hm(m.endedAt)}'),
            info(m.leagueName != null ? 'Liga' : 'Tipo', m.leagueName ?? 'Amistoso'), info('Confirmado', 'Los dos capitanes'),
          ]);
        }),
        if (m.bothCaptainsAccepted && m.player(uid) != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: PlobbyButton(label: 'Compartir resultado', icon: PlobbyIcons.share, onPressed: () => context.push('/match/${m.id}/share'))),
        if (m.events.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: MatchEventLog(m: m)),
      ])),
    ]));
  }
}

/// Entrada de cada set (`@keyframes fnin`): escala con rebote suave y aparición escalonada; sin animación con «reducir movimiento».
class _SetIn extends StatelessWidget {
  const _SetIn({required this.child, required this.delay, required this.animate});
  final Widget child; final Duration delay; final bool animate;
  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    final total = const Duration(milliseconds: 500) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: total,
      builder: (_, v, c) {
        final t = Curves.easeOutBack.transform(((v - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: .6 + .4 * t, child: c));
      },
      child: child,
    );
  }
}
