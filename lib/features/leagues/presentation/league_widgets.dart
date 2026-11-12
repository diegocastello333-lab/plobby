import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../auth/presentation/avatar_catalog.dart';
import '../domain/league_models.dart';

/// SVG de portada (`cover(kind)` del prototipo HTML, viewBox 390×120, recorte «slice»). Los ids que guarda la base de
/// datos ([leagueCovers]) se asignan a los diseños del HTML: waves → arcs, diagonal → diag. Los patrones SVG
/// (`<pattern>`) se expanden a elementos porque flutter_svg no los admite.
String leagueCoverSvg(String id) {
  const lime = '#D2F548', ink = '#171C19';
  final (bg, body) = switch (id) {
    'waves' => (lime, '<g fill="none" stroke="$ink" stroke-opacity=".7" stroke-width="1.6"><circle cx="330" cy="120" r="50"/><circle cx="330" cy="120" r="82"/><circle cx="330" cy="120" r="114"/><circle cx="330" cy="120" r="146"/></g>'),
    'diagonal' => (ink, '<g transform="rotate(35)" stroke="#F6F8F1" stroke-opacity=".16" stroke-width="2">${[for (var x = -560; x <= 700; x += 14) '<path d="M$x -600v1400"/>'].join()}</g><circle cx="70" cy="60" r="26" fill="none" stroke="$lime" stroke-width="2"/>'),
    'grid' => ('#8A938D', '<g stroke="$ink" stroke-opacity=".35" stroke-width="1"><path d="M0 30h390M0 60h390M0 90h390M65 0v120M130 0v120M195 0v120M260 0v120M325 0v120"/></g><rect x="195" y="30" width="65" height="60" fill="$ink" fill-opacity=".85"/>'),
    'dots' => (ink, '${[for (var y = 3; y < 120; y += 16) for (var x = 3; x < 390; x += 16) '<circle cx="$x" cy="$y" r="1.6" fill="#8A938D" fill-opacity=".55"/>'].join()}<circle cx="300" cy="60" r="30" fill="$lime"/>'),
    'court' => ('#D5DAD6', '<g fill="none" stroke="$ink" stroke-opacity=".5" stroke-width="1.4"><rect x="60" y="14" width="270" height="92"/><path d="M195 14v92M60 60h270"/></g><rect x="60" y="14" width="135" height="92" fill="$ink" fill-opacity=".1"/>'),
    'rings' => (ink, '<g fill="none" stroke="#F6F8F1" stroke-opacity=".28" stroke-width="1.4"><circle cx="90" cy="60" r="20"/><circle cx="90" cy="60" r="40"/><circle cx="90" cy="60" r="60"/><circle cx="90" cy="60" r="80"/></g><circle cx="90" cy="60" r="7" fill="$lime"/>'),
    _ => (ink, '<g fill="none" stroke="$lime" stroke-opacity=".55" stroke-width="1.4"><rect x="40" y="18" width="310" height="84"/><path d="M195 18v84M40 60h310M105 18v84M285 18v84"/></g><circle cx="318" cy="38" r="7" fill="$lime"/>'),
  };
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 120"><rect width="390" height="120" fill="$bg"/>$body</svg>';
}

/// Portada de liga (`.cov`): SVG del prototipo a todo el ancho, recortado como `preserveAspectRatio="xMidYMid slice"`.
/// [shade] añade el degradado de la cabecera de detalle (`.dh .sh`) para leer el título encima.
class LeagueCover extends StatelessWidget {
  const LeagueCover({super.key, required this.cover, this.height = 120, this.radius = AppRadius.lg, this.shade = false});
  final String cover; final double height, radius; final bool shade;
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(height: height, width: double.infinity, child: Stack(fit: StackFit.expand, children: [
        ExcludeSemantics(child: SvgPicture.string(leagueCoverSvg(cover), fit: BoxFit.cover)),
        if (shade) const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x80171C19), Color(0x00171C19), Color(0xD1171C19)], stops: [0, .38, 1]))),
      ])));
}

/// `.chip` (24 px, pastilla, Inter 12/600): `glass` sobre portada, `lime`, `dark` o neutra.
class LeagueChip extends StatelessWidget {
  const LeagueChip(this.text, {super.key, this.icon, this.tone = ChipTone.neutral});
  final String text; final IconData? icon; final ChipTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.lime => (AppColors.brand, AppColors.brandInk),
      ChipTone.glass => (const Color(0x8C171C19), Colors.white),
      ChipTone.dark => (AppColors.inverse, AppColors.onInverse),
      ChipTone.neutral => (AppColors.surfaceSunken, AppColors.text),
    };
    final pi = icon == null ? null : _plobbyFor(icon!);
    return Container(
      height: 24, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: bg, borderRadius: AppRadius.rPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pi != null) ...[PlobbyIcon(pi, size: 14, color: fg), const SizedBox(width: 6)]
        else if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
        Text(text, style: PlobbyText.chip.copyWith(color: fg)),
      ]));
  }
}
enum ChipTone { neutral, lime, glass, dark }

PlobbyIcons? _plobbyFor(IconData i) => i == Icons.public ? PlobbyIcons.globe : i == Icons.lock_outline ? PlobbyIcons.lock : i == Icons.apartment_outlined ? PlobbyIcons.building : null;

IconData visibilityIcon(LeagueVisibility v) => switch (v) { LeagueVisibility.public => Icons.public, LeagueVisibility.private => Icons.lock_outline, LeagueVisibility.club => Icons.apartment_outlined };
PlobbyIcons visibilityPlobbyIcon(LeagueVisibility v) => switch (v) { LeagueVisibility.public => PlobbyIcons.globe, LeagueVisibility.private => PlobbyIcons.lock, LeagueVisibility.club => PlobbyIcons.building };

/// `.badge-r` (22 px, radio 6, 10.5/800 mayúsculas +.08em): organizador en lima con estrella, admin del club en tinta con escudo.
class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key, this.compact = false});
  final LeagueRole role; final bool compact;
  @override
  Widget build(BuildContext context) {
    final org = role == LeagueRole.organizer;
    final fg = org ? AppColors.brandInk : AppColors.brand;
    return Container(
      height: compact ? 18 : 22, padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: org ? AppColors.brand : AppColors.inverse, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        PlobbyIcon(org ? PlobbyIcons.star : PlobbyIcons.shield, size: compact ? 10 : 12, strokeWidth: 2.2, color: fg), const SizedBox(width: 5),
        Text(role.label.toUpperCase(), style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: compact ? 9 : 10.5, fontWeight: FontWeight.w800, letterSpacing: compact ? .72 : .84, color: fg)),
      ]),
    );
  }
}

/// Nombre de liga `.ln`: Inter 14.5/800 en mayúsculas con +.045em.
const leagueNameStyle = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: .65, color: AppColors.text);

/// Barra de progreso `.prog .tk`: 5 px, radio 3, tinta sobre tinta .12.
class LeagueProgressBar extends StatelessWidget {
  const LeagueProgressBar({super.key, required this.value, required this.semanticsLabel});
  final double value; final String semanticsLabel;
  @override
  Widget build(BuildContext context) => Semantics(label: semanticsLabel, value: '${(value * 100).round()}%', excludeSemantics: true,
      child: Container(height: 5, decoration: BoxDecoration(color: const Color(0x1F171C19), borderRadius: BorderRadius.circular(3)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(widthFactor: value.clamp(0, 1).toDouble(), child: Container(decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(3))))));
}

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

/// Tarjeta de «Mis ligas» — `.card2.lc` del prototipo: portada 88 px con visibilidad y rol, cuerpo con nombre, jugadores y
/// temporada, progreso de partidos y caja «TU POSICIÓN». (La línea de última actividad del HTML no se muestra: el
/// resumen de `my_leagues` no la incluye.)
class MyLeagueCard extends StatelessWidget {
  const MyLeagueCard({super.key, required this.league});
  final LeagueSummary league;
  @override
  Widget build(BuildContext context) {
    final l = league;
    final pct = (l.progress * 100).round();
    return Semantics(button: true, label: '${l.name}. ${l.myRank == null ? '' : 'Tu posición ${l.myRank} de ${l.members}. '}${l.matchesDone} de ${l.matchesTotal} partidos', excludeSemantics: true,
      child: Pressable(child: DecoratedBox(
        decoration: const BoxDecoration(borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: Material(
          color: AppColors.surface, borderRadius: AppRadius.rMd, clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/leagues/${l.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: 88, child: Stack(children: [
                Positioned.fill(child: LeagueCover(cover: l.cover, height: 88, radius: 0)),
                Positioned(left: 12, top: 12, child: LeagueChip(l.visibility.label, icon: visibilityIcon(l.visibility), tone: ChipTone.glass)),
                Positioned(right: 12, top: 12, child: Row(children: [
                  if (l.status == LeagueStatus.ended) ...[const LeagueChip('Cerrada', tone: ChipTone.lime), if (l.role.isManager) const SizedBox(width: 6)],
                  if (l.role.isManager) RoleBadge(l.role),
                ])),
              ])),
              Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.name.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: leagueNameStyle),
                  const SizedBox(height: 5),
                  Text('${l.members} ${l.members == 1 ? 'jugador' : 'jugadores'} · Temporada ${l.season}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  LeagueProgressBar(value: l.progress, semanticsLabel: 'Progreso de la temporada'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: Text('${l.matchesDone} de ${l.matchesTotal} partidos', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted))),
                    Text('$pct%', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()])),
                  ]),
                ])),
                const SizedBox(width: 14),
                // .pos
                Container(
                  constraints: const BoxConstraints(minWidth: 74), padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
                  decoration: BoxDecoration(color: AppColors.inverse, borderRadius: BorderRadius.circular(10)),
                  child: Column(children: [
                    const Text('TU POSICIÓN', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.08, color: Color(0xB3F6F8F1))),
                    const SizedBox(height: 3),
                    Text(l.myRank == null ? '—' : '#${l.myRank}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 30, height: 1, fontWeight: FontWeight.w800, letterSpacing: -0.9, color: AppColors.brand)),
                    const SizedBox(height: 3),
                    Text('de ${l.members}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, letterSpacing: 0, color: Color(0xBFF6F8F1))),
                  ]),
                ),
              ])),
            ]),
          ),
        ),
      )),
    );
  }
}

/// Tarjeta de «Descubrir ligas» — `.card2.dc`: portada 64 px con visibilidad y estado, organizador, zona, nivel, fechas,
/// ocupación y la acción de unirse/solicitar (44 px).
class DiscoverLeagueCard extends StatelessWidget {
  const DiscoverLeagueCard({super.key, required this.league, required this.onJoin, this.busy = false});
  final DiscoverLeague league; final VoidCallback onJoin; final bool busy;
  static const _meta = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: AppColors.textMuted);
  @override
  Widget build(BuildContext context) {
    final d = league;
    final club = d.visibility == LeagueVisibility.club && !d.invited;
    final code = d.visibility == LeagueVisibility.private && !d.invited;   // sin invitación: se une con el código
    final outline = (club || code) && !d.requestPending && !d.full;
    final action = d.requestPending ? 'Solicitud enviada' : d.full ? 'Completa' : club ? 'Solicitar acceso' : code ? 'Tengo un código' : 'Unirme a la liga';
    Widget meta(PlobbyIcons i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [PlobbyIcon(i, size: 14, color: AppColors.textMuted), const SizedBox(width: 5), Flexible(child: Text(t, style: _meta))]);
    final weeks = d.startsOn != null && d.endsOn != null ? (d.endsOn!.difference(d.startsOn!).inDays / 7).round() : null;
    final when = d.startsOn == null ? null : '${d.status == LeagueStatus.open ? 'Empieza' : 'Empezó'} el ${_dm(d.startsOn!)}${weeks != null && weeks > 0 ? ' · $weeks semanas' : ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
      child: Material(color: AppColors.surface, borderRadius: AppRadius.rMd, clipBehavior: Clip.antiAlias, child: InkWell(
        onTap: () => context.push('/leagues/${d.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 64, child: Stack(children: [
            Positioned.fill(child: LeagueCover(cover: d.cover, height: 64, radius: 0)),
            Positioned(left: 12, top: 12, child: LeagueChip(d.visibility.label, icon: visibilityIcon(d.visibility), tone: ChipTone.glass)),
            Positioned(right: 12, top: 12, child: LeagueChip(d.status.label, tone: d.status == LeagueStatus.open ? ChipTone.lime : ChipTone.glass)),
          ])),
          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: leagueNameStyle),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 6, children: [
              if (d.organizerName.isNotEmpty) meta(PlobbyIcons.building, d.organizerName),
              if (d.location.isNotEmpty) meta(PlobbyIcons.pin, d.location),
              if (d.levelMin.isNotEmpty) meta(PlobbyIcons.star, d.levelLabel),
              if (when != null) meta(PlobbyIcons.cal, when),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: LeagueProgressBar(value: d.maxPlayers == 0 ? 0 : d.members / d.maxPlayers, semanticsLabel: 'Plazas ocupadas')),
              const SizedBox(width: 10),
              Text('${d.members}/${d.maxPlayers} jugadores', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            ]),
            if (d.friendsIn > 0) Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
              const PlobbyIcon(PlobbyIcons.users, size: 16, color: AppColors.textMuted), const SizedBox(width: 8),
              Text(d.friendsIn == 1 ? '1 amigo juega aquí' : '${d.friendsIn} amigos juegan aquí', style: _meta.copyWith(fontSize: 12)),
            ])),
            const SizedBox(height: 14),
            PlobbyButton(
              label: action, height: 44, busy: busy,
              kind: outline ? PlobbyButtonKind.outline : PlobbyButtonKind.primary,
              icon: outline ? (club ? PlobbyIcons.building : PlobbyIcons.lock) : null,
              onPressed: d.requestPending || d.full ? null : onJoin,
            ),
          ])),
        ]),
      )),
    );
  }
  static String _dm(DateTime d) { const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']; return '${d.day} ${m[d.month - 1]}'; }
}

/// Selector numérico del asistente (`.stp`): etiqueta encima y caja de 48 px con el valor y botones − / + de 36 px.
class NumberStepper extends StatelessWidget {
  const NumberStepper({super.key, required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.suffix = '', this.error});
  final String label, suffix; final int value, min, max; final ValueChanged<int> onChanged; final String? error;
  @override
  Widget build(BuildContext context) {
    Widget btn(PlobbyIcons i, String tip, VoidCallback? f) => Semantics(button: true, label: '$tip $label', enabled: f != null, excludeSemantics: true, child: Opacity(opacity: f == null ? .4 : 1, child: Material(
          color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(10),
          child: InkWell(borderRadius: BorderRadius.circular(10), onTap: f, child: SizedBox(width: 36, height: 36, child: Center(child: PlobbyIcon(i, size: 16, strokeWidth: 2.4)))))));
    return Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: PlobbyText.label),
      const SizedBox(height: 8),
      Container(
        height: 48, padding: const EdgeInsets.only(left: 14, right: 6),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, border: Border.all(color: error != null ? AppColors.danger : const Color(0x1A171C19))),
        child: Row(children: [
          Expanded(child: Semantics(label: label, value: '$value$suffix', child: Text('$value$suffix', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)))),
          btn(PlobbyIcons.dash, 'Menos', value > min ? () => onChanged(value - 1) : null),
          const SizedBox(width: 6),
          btn(PlobbyIcons.plus, 'Más', value < max ? () => onChanged(value + 1) : null),
        ]),
      ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: PlobbyText.help.copyWith(color: AppColors.danger))),
    ]));
  }
}
