import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../auth/presentation/avatar_catalog.dart';
import '../domain/league_models.dart';

/// Portada de liga: patrón vectorial sobre tinta (no depende de imágenes de red). Ids en [leagueCovers].
class LeagueCover extends StatelessWidget {
  const LeagueCover({super.key, required this.cover, this.height = 120, this.radius = AppRadius.lg});
  final String cover; final double height, radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _CoverPainter(cover))));
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.id);
  final String id;
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = AppColors.ink900);
    final lime = Paint()..color = AppColors.lime300..style = PaintingStyle.stroke..strokeWidth = 2;
    final soft = Paint()..color = AppColors.lime300.withOpacity(.16)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    switch (id) {
      case 'dots':
        for (var x = 10.0; x < s.width; x += 18) { for (var y = 10.0; y < s.height; y += 18) { c.drawCircle(Offset(x, y), (x + y) % 54 == 10 ? 3 : 1.6, Paint()..color = AppColors.lime300.withOpacity((x + y) % 54 == 10 ? .9 : .25)); } }
      case 'grid':
        for (var x = 0.0; x < s.width; x += 24) { c.drawLine(Offset(x, 0), Offset(x, s.height), soft); }
        for (var y = 0.0; y < s.height; y += 24) { c.drawLine(Offset(0, y), Offset(s.width, y), soft); }
        c.drawRect(Rect.fromLTWH(s.width * .62, s.height * .2, 48, 48), lime);
      case 'waves':
        for (var k = 0; k < 6; k++) {
          final p = Path()..moveTo(0, s.height * (.2 + k * .14));
          for (var x = 0.0; x <= s.width; x += 8) { p.lineTo(x, s.height * (.2 + k * .14) + math.sin(x / 26 + k) * 7); }
          c.drawPath(p, k == 2 ? lime : soft);
        }
      case 'court':
        final r = Rect.fromLTWH(s.width * .1, s.height * .18, s.width * .8, s.height * .64);
        c.drawRect(r, soft..strokeWidth = 2);
        c.drawLine(r.topCenter, r.bottomCenter, lime);
        c.drawLine(Offset(r.left + r.width * .22, r.top), Offset(r.left + r.width * .22, r.bottom), soft);
        c.drawLine(Offset(r.right - r.width * .22, r.top), Offset(r.right - r.width * .22, r.bottom), soft);
        c.drawLine(Offset(r.left + r.width * .22, r.center.dy), Offset(r.right - r.width * .22, r.center.dy), soft);
      case 'diagonal':
        for (var x = -s.height; x < s.width; x += 16) { c.drawLine(Offset(x, s.height), Offset(x + s.height, 0), x.toInt() % 64 == 0 ? lime : soft); }
      default: // lines
        for (var y = 8.0; y < s.height; y += 12) { c.drawLine(Offset(0, y), Offset(s.width, y), y.toInt() % 48 == 8 ? lime : soft); }
    }
    c.drawRect(Offset.zero & s, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00171C19), Color(0xB3171C19)]).createShader(Offset.zero & s));
  }
  @override
  bool shouldRepaint(_CoverPainter o) => o.id != id;
}

class LeagueChip extends StatelessWidget {
  const LeagueChip(this.text, {super.key, this.icon, this.tone = ChipTone.neutral});
  final String text; final IconData? icon; final ChipTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.lime => (AppColors.brand, AppColors.brandInk),
      ChipTone.glass => (const Color(0x33FFFFFF), Colors.white),
      ChipTone.dark => (AppColors.inverse, AppColors.onInverse),
      ChipTone.neutral => (AppColors.surfaceSunken, AppColors.text),
    };
    return Container(
      height: 24, padding: const EdgeInsets.symmetric(horizontal: 9), decoration: BoxDecoration(color: bg, borderRadius: AppRadius.rPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg, letterSpacing: .2)),
      ]));
  }
}
enum ChipTone { neutral, lime, glass, dark }

IconData visibilityIcon(LeagueVisibility v) => switch (v) { LeagueVisibility.public => Icons.public, LeagueVisibility.private => Icons.lock_outline, LeagueVisibility.club => Icons.apartment_outlined };

String fmtDay(DateTime? d) {
  if (d == null) return '—';
  const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// Avatar de un jugador de la liga: foto, avatar deportivo o iniciales.
class LeagueAvatar extends StatelessWidget {
  const LeagueAvatar({super.key, required this.name, this.avatarUrl, this.avatarId, this.size = 38, this.highlight = false});
  final String name; final String? avatarUrl, avatarId; final double size; final bool highlight;
  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();
    final w = avatarUrl != null && avatarUrl!.isNotEmpty
        ? ClipOval(child: Image.network(avatarUrl!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initials(initials)))
        : avatarId != null ? PlobbyAvatar(id: avatarId!, size: size) : _initials(initials);
    return Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: highlight ? AppColors.brand : AppColors.surface, width: 2)), child: w);
  }
  Widget _initials(String t) => CircleAvatar(radius: size / 2, backgroundColor: AppColors.inverse,
      child: Text(t.isEmpty ? '?' : t, style: TextStyle(fontSize: size * .34, fontWeight: FontWeight.w800, color: AppColors.onInverse)));
}

/// Tarjeta de «Mis ligas».
class MyLeagueCard extends StatelessWidget {
  const MyLeagueCard({super.key, required this.league});
  final LeagueSummary league;
  @override
  Widget build(BuildContext context) {
    final l = league;
    return Pressable(child: Material(
      color: AppColors.surface, borderRadius: AppRadius.rLg, clipBehavior: Clip.antiAlias, elevation: 0,
      child: InkWell(
        onTap: () => context.push('/leagues/${l.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            LeagueCover(cover: l.cover, height: 92, radius: 0),
            Positioned(left: 14, right: 14, bottom: 10, child: Row(children: [
              Expanded(child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Unbounded', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
              if (l.role.isManager) const LeagueChip('Gestionas', tone: ChipTone.lime),
            ])),
            Positioned(left: 14, top: 10, child: Row(children: [
              LeagueChip(l.visibility.label, icon: visibilityIcon(l.visibility), tone: ChipTone.glass), const SizedBox(width: 6),
              LeagueChip('Temporada ${l.season}', tone: ChipTone.glass),
              if (l.status == LeagueStatus.ended) ...[const SizedBox(width: 6), const LeagueChip('Cerrada', tone: ChipTone.lime)],
            ])),
          ]),
          Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _Stat(label: 'Posición', value: l.myRank == null ? '—' : '#${l.myRank}'),
              _Stat(label: 'Puntos', value: '${l.myPoints}'),
              _Stat(label: 'Jugados', value: '${l.myPlayed}'),
              _Stat(label: 'Jugadores', value: '${l.members}'),
            ]),
            const SizedBox(height: 12),
            // semanticsValue debe ser numérico (porcentaje); la frase completa va en la etiqueta.
            ClipRRect(borderRadius: AppRadius.rPill, child: LinearProgressIndicator(value: l.progress, minHeight: 6, backgroundColor: AppColors.surfaceSunken, color: AppColors.brand,
                semanticsLabel: 'Progreso de la temporada: ${l.matchesDone} de ${l.matchesTotal} partidos', semanticsValue: '${(l.progress * 100).round()}')),
            const SizedBox(height: 6),
            Text('${l.matchesDone} de ${l.matchesTotal} partidos · ${l.location.isEmpty ? l.status.label : l.location}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ])),
        ]),
      ),
    ));
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ]));
}

/// Tarjeta de «Descubrir ligas» con la acción de unirse/solicitar.
class DiscoverLeagueCard extends StatelessWidget {
  const DiscoverLeagueCard({super.key, required this.league, required this.onJoin, this.busy = false});
  final DiscoverLeague league; final VoidCallback onJoin; final bool busy;
  @override
  Widget build(BuildContext context) {
    final d = league;
    final action = d.requestPending ? 'Solicitud enviada' : d.full ? 'Completa' : d.visibility == LeagueVisibility.club && !d.invited ? 'Solicitar acceso' : 'Unirme';
    return Container(
      margin: const EdgeInsets.only(bottom: 12), decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, boxShadow: AppShadows.card),
      child: InkWell(
        borderRadius: AppRadius.rLg, onTap: () => context.push('/leagues/${d.id}'),
        child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          SizedBox(width: 64, child: LeagueCover(cover: d.cover, height: 64, radius: AppRadius.md)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text([if (d.location.isNotEmpty) d.location, if (d.organizerName.isNotEmpty) d.organizerName].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              LeagueChip(d.visibility.label, icon: visibilityIcon(d.visibility)),
              LeagueChip('${d.members}/${d.maxPlayers}', icon: Icons.group_outlined),
              if (d.friendsIn > 0) LeagueChip(d.friendsIn == 1 ? '1 amigo' : '${d.friendsIn} amigos', icon: Icons.favorite_border, tone: ChipTone.lime),
              LeagueChip(d.status.label),
            ]),
          ])),
          const SizedBox(width: 8),
          SizedBox(height: 36, child: FilledButton(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            onPressed: busy || d.requestPending || d.full ? null : onJoin,
            child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(action))),
        ])),
      ),
    );
  }
}

/// Selector numérico «− n +» del asistente.
class NumberStepper extends StatelessWidget {
  const NumberStepper({super.key, required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.suffix = '', this.error});
  final String label, suffix; final int value, min, max; final ValueChanged<int> onChanged; final String? error;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton.outlined(tooltip: 'Menos', onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 56, child: Text('$value$suffix', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton.outlined(tooltip: 'Más', onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add)),
        ]),
        if (error != null) Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
      ]));
}
