import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/profile_providers.dart';
import '../../domain/stats_calculator.dart';
import 'win_streak_badge.dart';
import '../../../../core/widgets/motion_widgets.dart';

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
      Row(children: [
        Expanded(child: _Tile(value: '${s.played}', label: 'Partidos jugados')),
        const SizedBox(width: 10),
        Expanded(child: _Tile(value: '${s.winRate}%', label: '% de victorias', bg: PlobbyColors.lime, fg: PlobbyColors.forest)),
        const SizedBox(width: 10),
        Expanded(child: _Tile(child: WinStreakBadge(streak: k.current), label: 'Racha actual', bg: PlobbyColors.forest, fg: PlobbyColors.ivory)),
      ]),
      if (full) ...[
        const SizedBox(height: 10),
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3.2, children: [
          _Row('Victorias', '${s.won}'), _Row('Derrotas', '${s.lost}'),
          _Row('Mejor racha', '${k.best}'), _Row('Sets G / P', '${s.sw}/${s.sl}'),
        ]),
        const SizedBox(height: 10),
        _Row('Juegos ganados / perdidos', '${s.gw} / ${s.gl}', height: 48),
      ],
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({this.value, this.child, required this.label, this.bg = Colors.white, this.fg = PlobbyColors.charcoal});
  final String? value; final Widget? child; final String label; final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
      height: 100, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        child ?? Text(value!, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: fg)),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg.withOpacity(.65))),
      ]));
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.height});
  final String label, value; final double? height;
  @override
  Widget build(BuildContext context) => Container(
      height: height, padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: PlobbyColors.mute, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ]));
}
