import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../auth/presentation/avatar_catalog.dart';
import '../application/lifecycle_providers.dart';
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';

String formatWhen(DateTime d) {
  const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'], meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final n = DateTime.now(); final today = d.year == n.year && d.month == n.month && d.day == n.day;
  String p(int x) => x.toString().padLeft(2, '0');
  return '${today ? 'Hoy' : '${dias[d.weekday - 1]} ${d.day} ${meses[d.month - 1]}'} · ${p(d.hour)}:${p(d.minute)}';
}

/// Estado del partido · `.um-s` (24 px, pastilla, Inter 11/700). En juego: tinta con punto lima latiendo.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final MatchStatus status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      MatchStatus.live => (AppColors.inverse, AppColors.brand),
      MatchStatus.pendingResult || MatchStatus.pendingConfirmation => (const Color(0xFFFFF4CC), const Color(0xFF7A5A00)),
      MatchStatus.disputed => (AppColors.dangerSoft, AppColors.danger),
      MatchStatus.confirmed => (AppColors.brandSoft, AppColors.brandText),
      _ => (AppColors.surfaceSunken, AppColors.text),
    };
    return Container(height: 24, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: bg, borderRadius: AppRadius.rPill),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (status == MatchStatus.live) const Padding(padding: EdgeInsets.only(right: 6), child: _Pulse()),
          Text(status.label, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: 0, color: fg)),
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
    if (compact) return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.inverse, borderRadius: BorderRadius.circular(8)), child: Text(t, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.brand, fontFeatures: [FontFeature.tabularFigures()])));
    return Semantics(label: 'Tiempo de partido $t', child: Text(t, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, fontSize: 44, height: 55 / 44, letterSpacing: -0.88, color: AppColors.text, fontFeatures: [FontFeature.tabularFigures()])));
  }
}

/// Marcador oscuro · `.md-scc` (radio 22, padding 6 16): una fila por equipo (`.md-sr`, 10 px vertical) con
/// cajas de 34 px radio 8 en Unbounded 16/700; lima en los sets que ganó ese equipo.
class ScoreBoard extends StatelessWidget {
  const ScoreBoard({super.key, required this.match, this.sets, this.names});
  final LifecycleMatch match;
  /// Sets a mostrar (por defecto los del partido). Se usa para la vista previa del resultado.
  final List<SetScore>? sets;
  /// Nombres de cada equipo (por defecto los nombres de pila unidos con «y»).
  final String Function(int team)? names;
  static const _dim = Color(0x99FFFFFF);
  @override
  Widget build(BuildContext context) {
    final s = sets ?? match.sets;
    final w = sets == null ? match.winnerTeam : (s.isEmpty ? null : winnerOfSets(s));
    String name(int t) => names?.call(t) ?? match.team(t).map((p) => p.name.split(' ').first).join(' y ');
    Widget row(int t) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
          Expanded(child: Text(name(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, letterSpacing: 0,
              fontWeight: w == t ? FontWeight.w700 : FontWeight.w400, color: w == t ? Colors.white : _dim))),
          for (final x in s) Builder(builder: (_) {
            final won = t == 1 ? x.a > x.b : x.b > x.a;
            return Container(width: 34, height: 34, margin: const EdgeInsets.only(left: 6), alignment: Alignment.center,
                decoration: BoxDecoration(color: won ? AppColors.brand : const Color(0x14FFFFFF), borderRadius: AppRadius.rSm),
                child: Text('${t == 1 ? x.a : x.b}', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0, color: won ? AppColors.brandInk : _dim)));
          }),
        ]));
    return Semantics(
      label: 'Marcador: ${name(1)} ${s.map((x) => x.a).join(', ')}; ${name(2)} ${s.map((x) => x.b).join(', ')}',
      excludeSemantics: true,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg),
          child: Column(children: [row(1), const Divider(height: 1, thickness: 1, color: Color(0x1FFFFFFF)), row(2)])),
    );
  }
}

/// Progreso del partido · `.md-stp`: cinco tramos (barra 4 px radio 2 + etiqueta 10/700). Hechos en tinta, actual en lima.
class MatchStepper extends StatelessWidget {
  const MatchStepper({super.key, required this.status});
  final MatchStatus status;
  static const steps = ['Programado', 'En juego', 'Resultado', 'Confirmación', 'Confirmado'];
  static int indexOf(MatchStatus s) => switch (s) {
        MatchStatus.scheduled || MatchStatus.cancelled => 0,
        MatchStatus.live => 1,
        MatchStatus.pendingResult => 2,
        MatchStatus.pendingConfirmation || MatchStatus.disputed => 3,
        MatchStatus.confirmed => 4,
      };
  @override
  Widget build(BuildContext context) {
    final idx = indexOf(status);
    return Semantics(
      label: 'Progreso del partido: ${steps[idx]} (paso ${idx + 1} de ${steps.length})',
      excludeSemantics: true,
      child: Row(children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: Column(children: [
            Container(height: 4, decoration: BoxDecoration(color: i < idx ? AppColors.text : i == idx ? AppColors.brand : AppColors.surfaceSunken, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, child: Text(steps[i], maxLines: 1, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: .2,
                color: i == idx ? AppColors.text : AppColors.textMuted))),
          ])),
        ],
      ]),
    );
  }
}

/// Botón principal del ciclo · `.md-start`: 60 px, pastilla, máx. 340, Unbounded 14/600 (+.02em), sombra lima;
/// `.stop` en tinta con texto blanco. Se reduce a .97 al pulsar.
class MatchCtaButton extends StatelessWidget {
  const MatchCtaButton({super.key, required this.label, required this.onTap, this.icon, this.dark = false, this.busy = false});
  final String label; final VoidCallback? onTap; final PlobbyIcons? icon; final bool dark, busy;
  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.brandInk;
    final enabled = onTap != null && !busy;
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: Semantics(container: true, button: true, enabled: enabled, label: label, excludeSemantics: true, child: Pressable(enabled: enabled, child: Opacity(
      opacity: enabled || busy ? 1 : .55,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: AppRadius.rPill, boxShadow: [dark
            ? const BoxShadow(color: Color(0x4D171C19), blurRadius: 24, offset: Offset(0, 10))
            : const BoxShadow(color: Color(0x73AED21A), blurRadius: 24, offset: Offset(0, 10))]),
        child: Material(color: dark ? AppColors.inverse : AppColors.brand, shape: const StadiumBorder(), child: InkWell(customBorder: const StadiumBorder(), onTap: enabled ? onTap : null,
          child: SizedBox(height: 60, width: double.infinity, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else ...[
              if (icon != null) ...[PlobbyIcon(icon!, size: 20, strokeWidth: 2.2, color: fg), const SizedBox(width: 10)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .28, color: fg))),
            ],
          ])),
        )),
      ),
    )))));
  }
}

/// Tarjeta de equipo · `.md-tc` (blanca, radio 22, borde 1 px; ganador: anillo lima 2 px y degradado lima suave).
/// [trailing] permite sustituir el distintivo de capitán (p. ej. el ELO ganado en el resultado final).
class TeamCard extends StatelessWidget {
  const TeamCard({super.key, required this.match, required this.team, required this.winner, this.uid, this.trailing, this.subtitle, this.avatarSize = 40});
  final LifecycleMatch match; final int team; final bool winner; final String? uid;
  final Widget? Function(MatchPlayer p)? trailing;
  /// Segunda línea de cada jugador (por defecto «nivel · ELO n»).
  final String Function(MatchPlayer p)? subtitle;
  final double avatarSize;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: winner ? null : AppColors.surface,
        gradient: winner ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.brandSoft, AppColors.surface], stops: [0, .7]) : null,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: winner ? AppColors.brand : AppColors.border, width: winner ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('EQUIPO $team${winner ? ' · GANADOR' : ''}', style: PlobbyText.eb),
        for (final p in match.team(team)) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
          PlayerAvatar(player: p, size: avatarSize), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.id == uid ? '${p.name} (tú)' : p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, height: 17 / 14.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            if (subtitle != null || p.level.isNotEmpty || p.elo > 0) Text(subtitle?.call(p) ?? [if (p.level.isNotEmpty) p.level, if (p.elo > 0) 'ELO ${p.elo}'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 15 / 12, letterSpacing: 0, color: AppColors.textMuted)),
          ])),
          if (trailing != null) trailing!(p) ?? const SizedBox.shrink()
          else if (p.isCaptain) Semantics(label: 'Capitán', excludeSemantics: true, child: Container(width: 22, height: 22, alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.inverse, shape: BoxShape.circle),
              child: const Text('C', style: TextStyle(fontFamily: AppTypography.sansFamily, color: AppColors.brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0)))),
        ])),
      ]));
}
