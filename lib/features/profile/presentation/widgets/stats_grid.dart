import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/profile_providers.dart';
import '../../domain/stats_calculator.dart';
import 'win_streak_badge.dart';
import '../../../../core/widgets/motion_widgets.dart';
import '../../../../core/motion/app_motion.dart';

const _order = [StatsPeriod.d30, StatsPeriod.d90, StatsPeriod.all];

class StatsGrid extends ConsumerWidget {
  const StatsGrid({super.key, required this.view, this.full = false});
  final ProfileView view;
  final bool full;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = view.stats, k = view.streak, period = ref.watch(statsPeriodProvider);
    return Column(children: [
      // `.seg` del prototipo, mismo orden que el HTML: 30 días · 3 meses · Todo.
      SlidingTabs(labels: const ['30 días', '3 meses', 'Todo'], index: _order.indexOf(period),
          onChanged: (i) => ref.read(statsPeriodProvider.notifier).state = _order[i]),
      const SizedBox(height: 14),
      // IntrinsicHeight + altura mínima: con texto grande (Dynamic Type) las tres tarjetas crecen juntas en vez de desbordar.
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _Tile(count: s.played, label: 'Partidos jugados')),
        const SizedBox(width: 10),
        Expanded(child: _Tile(count: s.winRate, suffix: '%', label: '% de victorias', bg: PlobbyColors.lime, fg: PlobbyColors.forest)),
        const SizedBox(width: 10),
        Expanded(child: _Tile(child: WinStreakBadge(streak: k.current), label: 'Racha actual', bg: PlobbyColors.forest, fg: PlobbyColors.ivory)),
      ])),
      if (full) ...[
        const SizedBox(height: 10),
        // Filas con altura mínima (no proporción fija): el texto grande las hace crecer en vez de cortarse.
        _pair(_Row('Victorias', '${s.won}'), _Row('Derrotas', '${s.lost}')),
        const SizedBox(height: 10),
        _pair(_Row('Mejor racha', '${k.best}'), _Row('Sets G / P', '${s.sw}/${s.sl}')),
        const SizedBox(height: 10),
        _Row('Juegos ganados / perdidos', '${s.gw} / ${s.gl}'),
      ],
    ]);
  }
}

Widget _pair(Widget a, Widget b) => IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]));

class _Tile extends StatelessWidget {
  const _Tile({this.count, this.suffix = '', this.child, required this.label, Color? bg, Color? fg}) : _bg = bg, _fg = fg;
  final int? count; final String suffix; final Widget? child; final String label; final Color? _bg, _fg;
  Color get bg => _bg ?? AppColors.surface;
  Color get fg => _fg ?? PlobbyColors.charcoal;
  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minHeight: 100), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        // La cifra se reduce para caber en su tarjeta (nunca se corta): en móviles de 320 px y con texto grande.
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            // la cifra cuenta desde 0 al aparecer y de un valor a otro al cambiar de periodo
            child: child ?? Semantics(label: '$count$suffix', excludeSemantics: true, child: TweenAnimationBuilder<double>(
                tween: Tween(begin: Motion.reduced(context) ? count!.toDouble() : 0, end: count!.toDouble()), duration: Motion.celebration, curve: Motion.enter,
                builder: (_, v, __) => Text('${v.round()}$suffix', maxLines: 1, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 30, height: 1.1,
                    fontWeight: FontWeight.w800, letterSpacing: -0.6, color: fg, fontFeatures: const [FontFeature.tabularFigures()]))))),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: 0, color: fg.withValues(alpha: .7))),
      ]));
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minHeight: 48), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1.25, color: PlobbyColors.mute, fontWeight: FontWeight.w600, letterSpacing: 0))),
        const SizedBox(width: 8),
        Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2)))),
      ]));
}
