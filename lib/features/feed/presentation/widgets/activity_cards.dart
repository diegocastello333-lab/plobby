import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../../../core/theme/plobby_text.dart';
import '../../../../core/widgets/plobby_components.dart';
import '../../../../core/widgets/plobby_icon.dart';
import '../../../profile/presentation/widgets/win_streak_badge.dart';
import '../../domain/feed_models.dart';
import 'reaction_bar.dart';

String timeAgo(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 60) return 'hace ${m < 1 ? 1 : m} min';
  if (m < 1440) return 'hace ${m ~/ 60} h';
  if (m < 10080) return 'hace ${m ~/ 1440} d';
  return 'hace ${m ~/ 10080} sem';
}

/// Colores de las iniciales (`.av` del prototipo): tinta con lima, tinta con marfil, lima con tinta o salvia con tinta.
const _avPalette = [(AppColors.inverse, AppColors.brand), (AppColors.inverse, AppColors.ink50), (AppColors.brand, AppColors.brandInk), (AppColors.borderStrong, AppColors.brandInk)];

/// Relleno del avatar (foto o iniciales con color estable por usuario), sin recorte: lo pone quien lo usa.
Widget feedAvatarFill(FeedUser u, double size) {
  final initials = u.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();
  final (bg, fg) = _avPalette[u.id.codeUnits.fold<int>(0, (a, c) => a + c) % _avPalette.length];
  final fallback = ColoredBox(color: bg, child: Center(child: Text(initials.isEmpty ? '?' : initials,
      style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: size * .36, fontWeight: FontWeight.w800, letterSpacing: 0, color: fg))));
  return u.avatarUrl != null && u.avatarUrl!.isNotEmpty
      ? Image.network(u.avatarUrl!, width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => fallback)
      : fallback;
}

/// Avatar redondo de radio [r] con aro blanco de 2 px (`.av`).
Widget avatar(FeedUser u, double r, {double? radius, Color ring = AppColors.surface}) => Container(
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
    child: ClipOval(child: SizedBox(width: r * 2 - 4, height: r * 2 - 4, child: feedAvatarFill(u, r * 2 - 4))));

/// Punto de entrada: elige la tarjeta según el tipo de actividad.
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.post});
  final FeedPost post;
  @override
  Widget build(BuildContext context) => switch (post.payload) {
        MatchPayload p => _Shell(post: post, sub: p.venue, child: _Match(post: post, p: p)),
        AchievementPayload p => _Shell(post: post, dark: true, child: _Achievement(post: post, p: p)),
        StreakPayload p => _Shell(post: post, dark: true, child: _Streak(p: p, own: post.author.id == 'me')),
        EloPayload p => _Shell(post: post, child: _Elo(post: post, p: p)),
        LeaguePayload p => _Shell(post: post, child: _League(post: post, p: p)),
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
        child,
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
        const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.symmetric(vertical: 3, horizontal: 10), child: Text('VS', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.borderStrong)))),
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
      decoration: BoxDecoration(color: win ? const Color(0x0F171C19) : null, borderRadius: BorderRadius.circular(10)),
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
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Column(children: [
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: Text.rich(TextSpan(style: const TextStyle(fontFamily: AppTypography.sansFamily, color: AppColors.ink50, fontSize: 13.5, height: 1.4, letterSpacing: 0), children: [
        TextSpan(text: widget.post.author.name.split(' ').first, style: const TextStyle(fontWeight: FontWeight.w700)),
        const TextSpan(text: ' acaba de desbloquear un nuevo logro'),
      ]))),
      InkWell(
        onTap: () => showPlobbySheet(context, (_) => Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
          _Disc(size: 92, id: p.achievementId), const SizedBox(height: 14),
          Text(p.title.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.text)),
          const SizedBox(height: 6), Text(p.description, textAlign: TextAlign.center, style: PlobbyText.sub),
        ]))),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Center(child: Column(children: [
          // insignia: disco lima dentro de un aro tinta con borde lima tenue (como en el HTML)
          ScaleTransition(scale: CurvedAnimation(parent: c, curve: MediaQuery.of(context).disableAnimations ? Curves.linear : Curves.elasticOut), child: AnimatedBuilder(animation: c, builder: (_, child) => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.ink800, border: Border.all(color: const Color(0x40D2F548), width: 1.5),
                  boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: .35 * (1 - c.value) + .12), blurRadius: 24, spreadRadius: 4)]), child: child), child: _Disc(size: 104, id: p.achievementId))),
          const SizedBox(height: 14),
          Text(p.title.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTypography.displayFamily, color: AppColors.ink50, fontSize: 22, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.22)),
          const SizedBox(height: 6),
          Text(p.description, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, letterSpacing: 0, color: Color(0xC7F6F8F1))),
          if (p.milestone != null) Padding(padding: const EdgeInsets.only(top: 10), child: Pill(p.milestone!, tone: PillTone.lime)),
        ]))),
      ),
    ]);
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
        WinStreakBadge(streak: p.count, size: 56, showNumber: false), const SizedBox(width: 14),
        Text('${p.count}', style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 60, fontWeight: FontWeight.w700, letterSpacing: -1.8, color: AppColors.brand, height: 1)),
        const SizedBox(width: 14),
        Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontFamily: AppTypography.sansFamily, color: AppColors.ink50, fontSize: 14, height: 1.35, letterSpacing: 0), children: [
          TextSpan(text: own ? 'Estás' : 'Está', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' en racha\n${p.count} victorias seguidas${p.count >= 7 ? ' · ¡a por las 10!' : ''}'),
        ]))),
      ]));
}

class _Elo extends StatelessWidget {
  const _Elo({required this.post, required this.p});
  final FeedPost post; final EloPayload p;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.4, letterSpacing: 0, color: AppColors.text), children: [
          TextSpan(text: post.author.name.split(' ').first, style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: ' ${p.headline}')])),
        const SizedBox(height: 8),
        Row(children: [
          Text('${p.from}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, letterSpacing: 0, color: AppColors.textMuted)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: PlobbyIcon(PlobbyIcons.chev, size: 14, color: AppColors.textMuted)),
          Text('${p.to}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.18, color: AppColors.text)),
          const Spacer(), Pill('+${p.delta} ELO', tone: PillTone.lime),
        ]),
        const SizedBox(height: 8),
        Semantics(label: 'ELO ${p.to}', excludeSemantics: true, child: Container(height: 6, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(3)), alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: ((p.to - 1200) / 400).clamp(0, 1).toDouble(), child: Container(decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(3)))))),
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
          Text('${post.author.name.split(' ').first} ${p.headline}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontWeight: FontWeight.w700, fontSize: 13.5, letterSpacing: 0, color: AppColors.text)),
          Text(p.leagueName.toUpperCase(), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: .3, color: AppColors.text)),
          Text(p.subtitle, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted)),
        ])),
      ]));
}
