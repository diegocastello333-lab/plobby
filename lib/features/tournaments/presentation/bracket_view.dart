import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../domain/tournament_models.dart';
import 'tournament_widgets.dart';

/// Cuadro de eliminatoria conectado a los datos reales: columnas por ronda, líneas que unen cada partido con el
/// siguiente y, al final, el campeón. Se arrastra y se amplía con los dedos (InteractiveViewer) para verlo entero en
/// un móvil. Cada partido muestra las dos parejas, el resultado por sets y su estado.
class BracketView extends StatelessWidget {
  const BracketView({super.key, required this.detail, required this.onMatch});
  final TournamentDetail detail;
  final ValueChanged<TMatch> onMatch;

  static const cardW = 200.0, cardH = 84.0, gapX = 40.0, gapY = 16.0, headerH = 34.0;

  @override
  Widget build(BuildContext context) {
    final ko = detail.knockout;
    final rounds = detail.knockoutRounds;
    if (rounds == 0) return const SizedBox.shrink();
    final first = ko.where((m) => m.round == 1).length;
    final slot = cardH + gapY;
    final height = headerH + first * slot;
    final width = (rounds + 1) * (cardW + gapX);
    double centerY(TMatch m) => headerH + slot * (1 << (m.round - 1)) * (m.position + .5);
    double left(int round) => (round - 1) * (cardW + gapX);
    final myTeam = detail.myTeam?.id;
    final champion = detail.champion;
    final finalMatch = ko.where((m) => m.round == rounds).firstOrNull;

    return LayoutBuilder(builder: (context, c) => InteractiveViewer(
          constrained: false, minScale: .45, maxScale: 1.6, boundaryMargin: const EdgeInsets.all(48),
          child: SizedBox(width: width, height: math.max(height, 200), child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _Connectors([
              for (final m in ko)
                if (m.nextMatchId != null)
                  () {
                    final next = ko.firstWhere((x) => x.id == m.nextMatchId);
                    return (Offset(left(m.round) + cardW, centerY(m)), Offset(left(next.round), centerY(next)), m.winnerTeamId != null && m.status != TMatchStatus.bye);
                  }(),
              if (finalMatch != null) (Offset(left(rounds) + cardW, centerY(finalMatch)), Offset(left(rounds + 1), centerY(finalMatch)), champion != null),
            ]))),
            for (var r = 1; r <= rounds; r++)
              Positioned(left: left(r), top: 0, width: cardW, height: headerH - 8, child: Center(child: Text(roundName(r, rounds).toUpperCase(), style: PlobbyText.eb))),
            Positioned(left: left(rounds + 1), top: 0, width: cardW, height: headerH - 8, child: const Center(child: Text('CAMPEÓN', style: PlobbyText.eb))),
            for (final m in ko)
              Positioned(left: left(m.round), top: centerY(m) - cardH / 2, width: cardW, height: cardH,
                  child: BracketMatchCard(detail: detail, m: m, myTeamId: myTeam, onTap: () => onMatch(m))),
            if (finalMatch != null)
              Positioned(left: left(rounds + 1), top: centerY(finalMatch) - 40, width: cardW, height: 80, child: _ChampionCard(team: champion)),
          ])),
        ));
  }
}

/// Partido en el cuadro: dos filas (pareja + sets), ganador en negrita, mi pareja marcada en lima y estado.
class BracketMatchCard extends StatelessWidget {
  const BracketMatchCard({super.key, required this.detail, required this.m, required this.onTap, this.myTeamId});
  final TournamentDetail detail;
  final TMatch m;
  final VoidCallback onTap;
  final String? myTeamId;
  @override
  Widget build(BuildContext context) {
    final mine = myTeamId != null && m.involves(myTeamId);
    final live = m.status == TMatchStatus.live;
    Widget row(int slot) {
      final team = detail.team(slot == 1 ? m.team1Id : m.team2Id);
      final won = m.winnerTeamId != null && m.winnerTeamId == team?.id && m.status != TMatchStatus.bye;
      final lost = m.finished && team != null && !won;
      return Expanded(child: Row(children: [
        Expanded(child: team == null && m.status == TMatchStatus.bye
            ? Text('Pasa directo', style: PlobbyText.help.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic))
            : TeamLine(team: team, emptyLabel: detail.slotLabel(m, slot), bold: won, muted: lost, size: 18,
                style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, fontWeight: won ? FontWeight.w800 : FontWeight.w600, color: lost ? AppColors.textMuted : AppColors.text))),
        if (m.sets != null) for (final s in m.sets!) SizedBox(width: 15, child: Text('${slot == 1 ? s.$1 : s.$2}', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, fontWeight: FontWeight.w800,
                color: (slot == 1 ? s.$1 > s.$2 : s.$2 > s.$1) ? AppColors.text : AppColors.textMuted))),
        if (won) const Padding(padding: EdgeInsets.only(left: 4), child: PlobbyIcon(PlobbyIcons.check, size: 12, strokeWidth: 3)),
      ]));
    }
    return Semantics(button: true, container: true, label: '${roundName(m.round, detail.knockoutRounds)}: '
        '${detail.team(m.team1Id)?.name ?? detail.slotLabel(m, 1)} contra ${detail.team(m.team2Id)?.name ?? (m.status == TMatchStatus.bye ? 'nadie, pasa directo' : detail.slotLabel(m, 2))}. '
        '${m.finished ? 'Resultado ${m.score}' : m.status.label}', excludeSemantics: true,
      child: Material(color: AppColors.surface, borderRadius: AppRadius.rSm, clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        decoration: BoxDecoration(borderRadius: AppRadius.rSm, boxShadow: AppShadows.card,
            border: Border(left: BorderSide(color: live ? const Color(0xFF1FA463) : mine ? AppColors.brand : Colors.transparent, width: 4))),
        child: Column(children: [
          row(1),
          Container(height: 1, color: const Color(0x14171C19)),
          row(2),
          if (live) const Align(alignment: Alignment.centerRight, child: Text('EN JUEGO', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .8, color: Color(0xFF1FA463)))),
        ]),
      ))),
    );
  }
}

class _ChampionCard extends StatelessWidget {
  const _ChampionCard({required this.team});
  final TTeam? team;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: team == null ? AppColors.surfaceSunken : AppColors.inverse, borderRadius: AppRadius.rMd,
            boxShadow: team == null ? null : const [BoxShadow(color: Color(0x66D2F548), blurRadius: 18, spreadRadius: -4)]),
        child: Row(children: [
          PlobbyIcon(PlobbyIcons.trophy, size: 26, color: team == null ? AppColors.textMuted : AppColors.brand),
          const SizedBox(width: 10),
          Expanded(child: team == null
              ? Text('Por decidir', style: PlobbyText.help.copyWith(fontStyle: FontStyle.italic))
              : TeamLine(team: team, bold: true, size: 22, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.lime300))),
        ]),
      );
}

class _Connectors extends CustomPainter {
  _Connectors(this.lines);
  final List<(Offset, Offset, bool)> lines;
  @override
  void paint(Canvas c, Size s) {
    final idle = Paint()..color = const Color(0x33171C19)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final done = Paint()..color = AppColors.text..strokeWidth = 2..style = PaintingStyle.stroke;
    for (final (a, b, d) in lines) {
      final mid = (a.dx + b.dx) / 2;
      final path = Path()..moveTo(a.dx, a.dy)..lineTo(mid, a.dy)..lineTo(mid, b.dy)..lineTo(b.dx, b.dy);
      c.drawPath(path, d ? done : idle);
    }
  }
  @override
  bool shouldRepaint(_Connectors o) => true;
}
