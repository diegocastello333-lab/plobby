import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../social/domain/social_models.dart' show PlayerSummary;
import '../../social/presentation/player_tile.dart' show PlayerAvatar;
import '../domain/tournament_models.dart';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// «20 nov» o «20–22 nov» / «30 nov – 2 dic».
String tournamentDates(DateTime start, DateTime? end) {
  String d(DateTime x) => '${x.day} ${_months[x.month - 1]}';
  if (end == null || (end.year == start.year && end.month == start.month && end.day == start.day)) return d(start);
  if (end.month == start.month && end.year == start.year) return '${start.day}–${end.day} ${_months[start.month - 1]}';
  return '${d(start)} – ${d(end)}';
}

/// Avatar de un jugador de torneo (misma paleta e iniciales que el resto de la app).
class TPlayerAvatar extends StatelessWidget {
  const TPlayerAvatar(this.p, {super.key, this.size = 24});
  final TPlayer p;
  final double size;
  @override
  Widget build(BuildContext context) => PlayerAvatar(PlayerSummary(id: p.id, name: p.name, username: p.username, elo: 0, level: '', avatarUrl: p.avatarUrl), size: size);
}

/// Pareja: dos avatares solapados y «Ana G. / Bea S.».
class TeamLine extends StatelessWidget {
  const TeamLine({super.key, required this.team, this.emptyLabel = 'Por decidir', this.bold = false, this.muted = false, this.size = 22, this.style});
  final TTeam? team;
  final String emptyLabel;
  final bool bold, muted;
  final double size;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final t = team;
    final ts = style ?? TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, height: 1.2, letterSpacing: 0,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: muted ? AppColors.textMuted : AppColors.text);
    if (t == null) return Text(emptyLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: size * 1.6, height: size, child: Stack(children: [
        TPlayerAvatar(t.p1, size: size),
        Positioned(left: size * .6, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 1.5)), child: TPlayerAvatar(t.p2, size: size - 3))),
      ])),
      const SizedBox(width: 6),
      Flexible(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts)),
    ]);
  }
}

/// Estado del torneo: «Próximamente» (neutro), «En curso» (lima), «Finalizado» (tinta).
class TournamentStatusPill extends StatelessWidget {
  const TournamentStatusPill(this.phase, {super.key, this.onCover = false});
  final TournamentPhase phase;
  final bool onCover;
  @override
  Widget build(BuildContext context) => Pill(phaseLabel(phase),
      tone: onCover ? PillTone.glass : switch (phase) { TournamentPhase.upcoming => PillTone.neutral, TournamentPhase.inProgress => PillTone.lime, TournamentPhase.finished => PillTone.dark },
      icon: switch (phase) { TournamentPhase.upcoming => PlobbyIcons.cal, TournamentPhase.inProgress => PlobbyIcons.play, TournamentPhase.finished => PlobbyIcons.trophy });
}

/// Portada: la foto del torneo o, si no tiene, una pista dibujada en los colores de Plobby (variante por nombre).
class TournamentCover extends StatelessWidget {
  const TournamentCover({super.key, this.url, this.bytes, required this.seed, this.height = 132, this.radius = 14});
  final String? url;
  final Uint8List? bytes;
  final String seed;
  final double height, radius;
  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();
    Widget child;
    if (bytes != null) {
      child = Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (url != null && url!.isNotEmpty) {
      child = Image.network(url!, fit: BoxFit.cover, cacheWidth: w, errorBuilder: (_, __, ___) => _CourtArt(seed: seed));
    } else {
      child = _CourtArt(seed: seed);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox(height: height, width: double.infinity, child: child));
  }
}

class _CourtArt extends StatelessWidget {
  const _CourtArt({required this.seed});
  final String seed;
  static const _palettes = [
    (Color(0xFF171C19), Color(0xFF2E3D33), Color(0xFFD2F548)),
    (Color(0xFF1C3F8A), Color(0xFF2F6FDE), Color(0xFFF6F8F1)),
    (Color(0xFF9E4527), Color(0xFFD9774E), Color(0xFFF6F8F1)),
    (Color(0xFF0B6E63), Color(0xFF14B8A6), Color(0xFFD2F548)),
  ];
  @override
  Widget build(BuildContext context) {
    final p = _palettes[seed.codeUnits.fold<int>(0, (a, c) => a + c) % _palettes.length];
    return CustomPaint(painter: _CourtPainter(p.$1, p.$2, p.$3), child: const SizedBox.expand());
  }
}

class _CourtPainter extends CustomPainter {
  _CourtPainter(this.a, this.b, this.line);
  final Color a, b, line;
  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(r));
    final p = Paint()..color = line.withValues(alpha: .55)..style = PaintingStyle.stroke..strokeWidth = 2;
    final w = math.min(s.width * .62, s.height * 1.5), h = w / 2;
    final court = Rect.fromCenter(center: Offset(s.width * .62, s.height * .52), width: w, height: h);
    c.drawRRect(RRect.fromRectAndRadius(court, const Radius.circular(3)), p);
    c.drawLine(court.topCenter, court.bottomCenter, p..strokeWidth = 3);
    final sv = w * .35;
    c.drawLine(Offset(court.center.dx - sv, court.top), Offset(court.center.dx - sv, court.bottom), p..strokeWidth = 2);
    c.drawLine(Offset(court.center.dx + sv, court.top), Offset(court.center.dx + sv, court.bottom), p);
    c.drawLine(Offset(court.center.dx - sv, court.center.dy), Offset(court.center.dx + sv, court.center.dy), p);
    c.drawCircle(Offset(court.center.dx + sv * .55, court.center.dy - h * .22), 6, Paint()..color = const Color(0xFFD2F548));
  }
  @override
  bool shouldRepaint(_CourtPainter o) => o.a != a || o.b != b;
}

/// Tarjeta de «Mis torneos»: portada, estado, nombre, fecha/lugar, parejas, fase y próximo partido.
class TournamentCard extends StatelessWidget {
  const TournamentCard({super.key, required this.t, required this.onTap});
  final TournamentSummary t;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final where = [tournamentDates(t.startsOn, t.endsOn), if (t.location != null && t.location!.isNotEmpty) t.location!].join(' · ');
    return Semantics(button: true, container: true, label: '${t.name}. ${phaseLabel(t.phase)}. $where. ${t.teamsCount} de ${t.maxTeams} parejas. ${t.phaseText}',
      excludeSemantics: true,
      child: Material(color: AppColors.surface, borderRadius: AppRadius.rMd, clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Container(
        decoration: const BoxDecoration(borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(children: [
            TournamentCover(url: t.coverUrl, seed: t.id, height: 112, radius: 0),
            Positioned(left: 12, top: 12, child: TournamentStatusPill(t.phase, onCover: true)),
            if (t.isAdmin) const Positioned(right: 12, top: 12, child: Pill('Organizas', tone: PillTone.lime, icon: PlobbyIcons.shield)),
          ]),
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: PlobbyText.cardTitle),
            const SizedBox(height: 4),
            Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.help),
            const SizedBox(height: 12),
            Row(children: [
              _Fact(icon: PlobbyIcons.users, text: '${t.teamsCount}/${t.maxTeams} parejas'),
              const SizedBox(width: 14),
              Expanded(child: _Fact(icon: PlobbyIcons.trophy, text: t.phaseText)),
            ]),
            if (t.nextMatch != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: t.nextMatch!.live ? AppColors.brandSoft : AppColors.surfaceSunken, borderRadius: AppRadius.rSm),
                child: Row(children: [
                  PlobbyIcon(t.nextMatch!.live ? PlobbyIcons.play : PlobbyIcons.racket, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text.rich(TextSpan(children: [
                    TextSpan(text: t.nextMatch!.live ? 'En juego · ' : 'Tu próximo partido · ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: '${t.nextMatch!.label} vs ${t.nextMatch!.opponent}'),
                  ]), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, height: 1.3, letterSpacing: 0, color: AppColors.text))),
                ]),
              ),
            ],
          ])),
        ]),
      ))),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});
  final PlobbyIcons icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        PlobbyIcon(icon, size: 15, color: AppColors.textMuted), const SizedBox(width: 5),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text))),
      ]);
}
