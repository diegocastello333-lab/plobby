import '../../../../core/motion/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../../../core/theme/plobby_text.dart';
import '../../../../core/widgets/plobby_components.dart';
import '../../../../core/widgets/plobby_icon.dart';
import '../../../profile/presentation/widgets/win_streak_badge.dart';
import '../../domain/feed_models.dart';
import 'reaction_bar.dart';
import '../../../../core/widgets/net_image.dart';

String timeAgo(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 60) return 'hace ${m < 1 ? 1 : m} min';
  if (m < 1440) return 'hace ${m ~/ 60} h';
  if (m < 10080) return 'hace ${m ~/ 1440} d';
  return 'hace ${m ~/ 10080} sem';
}

/// Colores de las iniciales (`.av` del prototipo): tinta con lima, tinta con marfil, lima con tinta o salvia con tinta.
List<(Color, Color)> get _avPalette => [(AppColors.inverse, AppColors.brand), (AppColors.inverse, AppColors.ink50), (AppColors.brand, AppColors.brandInk), (AppColors.borderStrong, AppColors.brandInk)];

/// Relleno del avatar (foto o iniciales con color estable por usuario), sin recorte: lo pone quien lo usa.
Widget feedAvatarFill(FeedUser u, double size) {
  final initials = u.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();
  final (bg, fg) = _avPalette[u.id.codeUnits.fold<int>(0, (a, c) => a + c) % _avPalette.length];
  final fallback = ColoredBox(color: bg, child: Center(child: Text(initials.isEmpty ? '?' : initials,
      style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: size * .36, fontWeight: FontWeight.w800, letterSpacing: 0, color: fg))));
  return u.avatarUrl != null && u.avatarUrl!.isNotEmpty
      ? NetImage(u.avatarUrl!, width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => fallback)
      : fallback;
}

/// Avatar redondo de radio [r] con aro blanco de 2 px (`.av`).
Widget avatar(FeedUser u, double r, {double? radius, Color? ring}) => Container(
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring ?? AppColors.surface, width: 2)),
    child: ClipOval(child: SizedBox(width: r * 2 - 4, height: r * 2 - 4, child: feedAvatarFill(u, r * 2 - 4))));

/// Punto de entrada: elige la tarjeta según el tipo de actividad.
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.post});
  final FeedPost post;
  @override
  Widget build(BuildContext context) => switch (post.payload) {
        MatchPayload p => _Shell(post: post, sub: p.venue, child: _Match(post: post, p: p)),
        // Formato compacto y claro; el grande y oscuro queda para los momentos especiales (campeón de torneo).
        AchievementPayload p => _Shell(post: post, child: _Achievement(post: post, p: p)),
        StreakPayload p => _Shell(post: post, child: _Streak(p: p, own: post.author.id == 'me')),
        EloPayload p => _Shell(post: post, child: _Elo(post: post, p: p)),
        LeaguePayload p => _Shell(post: post, child: _League(post: post, p: p)),
        TournamentPayload p => _Shell(post: post, dark: true, child: _Champion(post: post, p: p)),
      };
}

class _Shell extends StatelessWidget {
  const _Shell({required this.post, required this.child, this.dark = false, this.sub});
  final FeedPost post; final Widget child; final bool dark; final String? sub;
  @override
  Widget build(BuildContext context) {
    final fg = dark ? AppColors.ink50 : AppColors.text, mute = dark ? const Color(0xA3F6F8F1) : AppColors.textMuted;
    // `.fcd`: blanca (o tinta en logros y rachas), radio 14, padding 14 16 12, sombra de tarjeta
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(color: dark ? AppColors.inverse : AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => context.push('/player/${post.author.id}'),
          child: Row(children: [
            avatar(post.author, 20, ring: dark ? AppColors.ink50 : AppColors.surface), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post.author.name, style: TextStyle(fontFamily: AppTypography.sansFamily, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0, color: fg)),
              const SizedBox(height: 1),
              Text('@${post.author.username} · ${timeAgo(post.createdAt)}${sub != null ? ' · $sub' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: mute)),
            ])),
          ]),
        ),
        DoubleTapFire(post: post, child: child),
        ReactionBar(post: post, onDark: dark),
      ]),
    );
  }
}

class _Match extends StatelessWidget {
  const _Match({required this.post, required this.p});
  final FeedPost post; final MatchPayload p;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: () => context.push('/match/${p.matchId}'),
      child: Padding(padding: const EdgeInsets.only(top: 12), child: Column(children: [
        _Team(users: p.teamA, scores: p.sets.map((s) => s.$1).toList(), win: p.won),
        Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.symmetric(vertical: 3, horizontal: 10), child: Text('VS', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.textMuted)))),
        _Team(users: p.teamB, scores: p.sets.map((s) => s.$2).toList(), win: !p.won),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Wrap(spacing: 8, runSpacing: 6, children: [
            _Chip(p.won ? 'VICTORIA' : 'DERROTA', dark: p.won),
            if (p.leagueName != null) _Chip(p.leagueName!, outlined: true, icon: PlobbyIcons.trophy),
          ])),
          const SizedBox(width: 8),
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('${p.eloDelta > 0 ? '+' : ''}${p.eloDelta} ELO', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0, color: p.eloDelta >= 0 ? AppColors.success : AppColors.danger))),
        ]),
      ])));
}

class _Team extends StatelessWidget {
  const _Team({required this.users, required this.scores, required this.win});
  final List<FeedUser> users; final List<int> scores; final bool win;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: win ? AppColors.inkA(0x0F) : null, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        // avatares de 26 px solapados (18 px de paso)
        SizedBox(width: 26 + 18.0 * (users.length.clamp(1, 2) - 1), height: 26, child: Stack(children: [
          for (var i = 0; i < users.length && i < 2; i++) Positioned(left: 18.0 * i, child: GestureDetector(onTap: () => context.push('/player/${users[i].id}'), child: avatar(users[i], 13))),
        ])),
        const SizedBox(width: 8),
        Expanded(child: Text(users.map((u) => u.name).join(' + '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, letterSpacing: 0, fontWeight: win ? FontWeight.w800 : FontWeight.w500, color: win ? AppColors.text : AppColors.textMuted))),
        if (win) const Padding(padding: EdgeInsets.only(left: 6), child: PlobbyIcon(PlobbyIcons.check, size: 16, strokeWidth: 2.4)),
        for (final s in scores) Padding(padding: const EdgeInsets.only(left: 9), child: SizedBox(width: 9, child: Text('$s', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, letterSpacing: 0, fontWeight: win ? FontWeight.w800 : FontWeight.w600, color: win ? AppColors.text : AppColors.textMuted)))),
      ]));
}

/// `.chip`: 24 px en píldora; `dark` = tinta con texto lima (VICTORIA), neutra (DERROTA) o con borde (liga).
class _Chip extends StatelessWidget {
  const _Chip(this.t, {this.dark = false, this.outlined = false, this.icon});
  final String t; final bool dark, outlined; final PlobbyIcons? icon;
  @override
  Widget build(BuildContext context) {
    final fg = dark ? AppColors.brand : AppColors.text;
    return Container(
      height: 24, padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: outlined ? null : (dark ? AppColors.inverse : AppColors.surfaceSunken), border: outlined ? Border.all(color: AppColors.border, width: 1.5) : null, borderRadius: AppRadius.rPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[PlobbyIcon(icon!, size: 13, color: fg), const SizedBox(width: 5)],
        Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0, color: fg))),
      ]));
  }
}

/// Logro: tarjeta oscura con insignia grande; entra con escala + brillo.
class _Achievement extends StatefulWidget {
  const _Achievement({required this.post, required this.p});
  final FeedPost post; final AchievementPayload p;
  @override
  State<_Achievement> createState() => _AchievementState();
}

class _AchievementState extends State<_Achievement> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: Motion.celebration)..forward();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    // Compacta: insignia de 52 px + título y descripción a su lado. Un toque abre el detalle del logro.
    return InkWell(
      borderRadius: AppRadius.rMd,
      onTap: () => showPlobbySheet(context, (_) => Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
        _Disc(size: 92, id: p.achievementId), const SizedBox(height: 14),
        Text(p.title, textAlign: TextAlign.center, style: PlobbyText.sec),
        const SizedBox(height: 6), Text(p.description, textAlign: TextAlign.center, style: PlobbyText.sub),
      ]))),
      child: Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
        ScaleTransition(scale: CurvedAnimation(parent: c, curve: Motion.reduced(context) ? Motion.linear : Motion.springBounce), child: _Disc(size: 52, id: p.achievementId)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nuevo logro', style: PlobbyText.footnote),
          Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: PlobbyText.headline),
          const SizedBox(height: 2),
          Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: PlobbyText.footnote.copyWith(color: AppColors.textBody)),
        ])),
        if (p.milestone != null) Padding(padding: const EdgeInsets.only(left: 8), child: Pill(p.milestone!, tone: PillTone.lime)),
      ])),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.size, required this.id});
  final double size; final String id;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.brand),
      child: id == 'fire' ? Center(child: WinStreakBadge(streak: 5, size: size * .5, showNumber: false))
          : Center(child: PlobbyIcon(switch (id) { 'king' => PlobbyIcons.star, 'rise' => PlobbyIcons.arrup, 'social' => PlobbyIcons.users, _ => PlobbyIcons.trophy }, size: size * .42, strokeWidth: 1.8, color: AppColors.brandInk)));
}

class _Streak extends StatelessWidget {
  const _Streak({required this.p, required this.own});
  final StreakPayload p; final bool own;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
        WinStreakBadge(streak: p.count, size: 40, showNumber: false), const SizedBox(width: 12),
        Text('${p.count}', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: AppColors.text, height: 1, fontFeatures: PlobbyText.tabular)),
        const SizedBox(width: 12),
        Expanded(child: Text.rich(TextSpan(style: PlobbyText.subhead, children: [
          TextSpan(text: own ? 'Estás' : 'Está', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' en racha\n${p.count} victorias seguidas${p.count >= 7 ? ' · ¡a por las 10!' : ''}', style: PlobbyText.footnote.copyWith(color: AppColors.textBody)),
        ]))),
      ]));
}

class _Elo extends StatelessWidget {
  const _Elo({required this.post, required this.p});
  final FeedPost post; final EloPayload p;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.4, letterSpacing: 0, color: AppColors.text), children: [
          TextSpan(text: post.author.name.split(' ').first, style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: ' ${p.headline}')])),
        const SizedBox(height: 8),
        Row(children: [
          Text('${p.from}', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, letterSpacing: 0, color: AppColors.textMuted)),
          Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: PlobbyIcon(PlobbyIcons.chev, size: 14, color: AppColors.textMuted)),
          Text('${p.to}', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.18, color: AppColors.text)),
          const Spacer(), Pill('+${p.delta} ELO', tone: PillTone.lime),
        ]),
        const SizedBox(height: 8),
        Semantics(label: 'ELO ${p.to}', excludeSemantics: true, child: Container(height: 6, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(3)), alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: ((p.to - 800) / 1200).clamp(0, 1).toDouble(), child: Container(decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(3)))))),
      ]));
}

class _League extends StatelessWidget {
  const _League({required this.post, required this.p});
  final FeedPost post; final LeaguePayload p;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.inverse, borderRadius: BorderRadius.circular(9)), child: const Center(child: PlobbyIcon(PlobbyIcons.trophy, size: 18, color: AppColors.brand))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${post.author.name.split(' ').first} ${p.headline}', style: TextStyle(fontFamily: AppTypography.sansFamily, fontWeight: FontWeight.w700, fontSize: 13.5, letterSpacing: 0, color: AppColors.text)),
          Text(p.leagueName.toUpperCase(), style: TextStyle(fontFamily: AppTypography.sansFamily, fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: .3, color: AppColors.text)),
          Text(p.subtitle, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted)),
        ])),
      ]));
}

/// Campeón de torneo: la celebración más importante del feed. Trofeo que entra con rebote y un halo lima que se apaga;
/// toca para abrir el torneo. Con «reducir movimiento» aparece directamente en su estado final.
class _Champion extends StatefulWidget {
  const _Champion({required this.post, required this.p});
  final FeedPost post; final TournamentPayload p;
  @override
  State<_Champion> createState() => _ChampionState();
}

class _ChampionState extends State<_Champion> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: Motion.celebrationLong);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) { c.value = 1; } else if (!c.isAnimating && c.value == 0) { c.forward(); }
  }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final first = widget.post.author.name.split(' ').first;
    final partner = p.partnerName?.split(' ').first;
    return Semantics(button: true, label: '$first, campeón del torneo ${p.name}${partner != null ? ' con $partner' : ''}. Abrir torneo', excludeSemantics: true,
      child: InkWell(onTap: () => context.push('/tournaments/${p.tournamentId}'), borderRadius: AppRadius.rMd, child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          ScaleTransition(scale: CurvedAnimation(parent: c, curve: Motion.springBounce), child: AnimatedBuilder(animation: c, builder: (_, child) => Container(
              width: 76, height: 76,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.brand,
                  boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: .45 * (1 - c.value) + .15), blurRadius: 26, spreadRadius: 3)]),
              child: child), child: const Center(child: PlobbyIcon(PlobbyIcons.trophy, size: 36, strokeWidth: 1.9, color: AppColors.brandInk)))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CAMPEÓN', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: AppColors.brand)),
            const SizedBox(height: 4),
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 19, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.ink50)),
            const SizedBox(height: 4),
            Text([if (partner != null) 'Con $partner', if (p.teams > 1) '${p.teams} parejas'].join(' · '),
                style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: Color(0xC7F6F8F1))),
          ])),
          const PlobbyIcon(PlobbyIcons.chev, size: 16, color: Color(0x80F6F8F1)),
        ]),
      )));
  }
}
