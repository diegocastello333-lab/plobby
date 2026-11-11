import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../auth/presentation/avatar_catalog.dart';
import '../application/lifecycle_providers.dart';
import '../domain/match_lifecycle.dart';

String formatWhen(DateTime d) {
  const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'], meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final n = DateTime.now(); final today = d.year == n.year && d.month == n.month && d.day == n.day;
  String p(int x) => x.toString().padLeft(2, '0');
  return '${today ? 'Hoy' : '${dias[d.weekday - 1]} ${d.day} ${meses[d.month - 1]}'} · ${p(d.hour)}:${p(d.minute)}';
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final MatchStatus status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      MatchStatus.live => (AppColors.inverse, AppColors.brand),
      MatchStatus.pendingResult || MatchStatus.pendingConfirmation => (AppColors.warningSoft, AppColors.warning),
      MatchStatus.disputed => (AppColors.dangerSoft, AppColors.danger),
      MatchStatus.confirmed => (AppColors.brandSoft, AppColors.brandText),
      _ => (AppColors.surfaceSunken, AppColors.text),
    };
    return Container(height: 24, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (status == MatchStatus.live) const Padding(padding: EdgeInsets.only(right: 6), child: _Pulse()),
          Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ]));
  }
}

class _Pulse extends StatefulWidget { const _Pulse(); @override State<_Pulse> createState() => _PulseState(); }
class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(opacity: Tween(begin: .35, end: 1.0).animate(_c), child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)));
}

/// Foto (si la hay) o avatar deportivo predefinido o iniciales.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.player, this.size = 40});
  final MatchPlayer player; final double size;
  @override
  Widget build(BuildContext context) {
    final w = player.avatarUrl != null && player.avatarUrl!.isNotEmpty
        ? ClipOval(child: Image.network(player.avatarUrl!, width: size, height: size, fit: BoxFit.cover))
        : player.avatarId != null ? PlobbyAvatar(id: player.avatarId!, size: size)
        : CircleAvatar(radius: size / 2, backgroundColor: AppColors.surfaceSunken, child: Text(player.name.isEmpty ? '?' : player.name.split(' ').map((s) => s.isEmpty ? '' : s[0]).take(2).join(), style: TextStyle(fontSize: size * .34, fontWeight: FontWeight.w700)));
    return Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2)), child: w);
  }
}

/// Cronómetro VISIBLE. Calcula SIEMPRE `serverNow - startedAt` (sin contador local): igual para los cuatro jugadores,
/// continúa si se cierra la app y se corrige solo al reabrir. Se repinta con un tick de 1 s.
class MatchStopwatch extends ConsumerWidget {
  const MatchStopwatch({super.key, required this.match, this.compact = false});
  final LifecycleMatch match; final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tickProvider);
    final clock = ref.watch(serverClockProvider).valueOrNull ?? ServerClock();
    final t = formatElapsed(elapsedOf(match, clock));
    if (compact) return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.inverse, borderRadius: BorderRadius.circular(8)), child: Text(t, style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, color: AppColors.brand, fontFeatures: [FontFeature.tabularFigures()])));
    return Semantics(label: 'Tiempo de partido $t', child: Text(t, style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 44, letterSpacing: -1, fontFeatures: [FontFeature.tabularFigures()])));
  }
}

class ScoreBoard extends StatelessWidget {
  const ScoreBoard({super.key, required this.match, this.sets});
  final LifecycleMatch match; final List<dynamic>? sets;
  @override
  Widget build(BuildContext context) {
    final s = match.sets, w = match.winnerTeam;
    Widget row(int t) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
          Expanded(child: Text(match.team(t).map((p) => p.name.split(' ').first).join(' y '), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: w == t ? FontWeight.w700 : FontWeight.w500, color: w == t ? Colors.white : const Color(0x99FFFFFF)))),
          for (final x in s) Container(width: 34, height: 34, margin: const EdgeInsets.only(left: 6), alignment: Alignment.center,
              decoration: BoxDecoration(color: (t == 1 ? x.a > x.b : x.b > x.a) ? AppColors.brand : const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(8)),
              child: Text('${t == 1 ? x.a : x.b}', style: TextStyle(fontFamily: 'Unbounded', fontSize: 16, color: (t == 1 ? x.a > x.b : x.b > x.a) ? AppColors.brandInk : Colors.white))),
        ]));
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg), child: Column(children: [row(1), const Divider(height: 1, color: Color(0x1FFFFFFF)), row(2)]));
  }
}
