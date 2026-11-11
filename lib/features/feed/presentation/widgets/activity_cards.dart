import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/plobby_theme.dart';
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

Widget avatar(FeedUser u, double r, {double? radius}) => CircleAvatar(radius: r, backgroundColor: PlobbyColors.forest,
    backgroundImage: u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null,
    child: u.avatarUrl == null ? Text(u.name[0], style: TextStyle(color: PlobbyColors.ivory, fontSize: r * .8, fontWeight: FontWeight.w700)) : null);

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
    final fg = dark ? PlobbyColors.ivory : PlobbyColors.charcoal, mute = dark ? const Color(0xA3F6F8F1) : PlobbyColors.mute;
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(color: dark ? PlobbyColors.forest : Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => context.push('/player/${post.author.id}'),
          child: Row(children: [
            avatar(post.author, 20), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post.author.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: fg)),
              Text('@${post.author.username} · ${timeAgo(post.createdAt)}${sub != null ? ' · $sub' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: mute)),
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
        const Padding(padding: EdgeInsets.symmetric(vertical: 3), child: Text('VS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: PlobbyColors.sage))),
        _Team(users: p.teamB, scores: p.sets.map((s) => s.$2).toList(), win: !p.won),
        const SizedBox(height: 10),
        Row(children: [
          _Chip(p.won ? 'VICTORIA' : 'DERROTA', dark: p.won),
          if (p.leagueName != null) ...[const SizedBox(width: 8), _Chip(p.leagueName!, outlined: true)],
          const Spacer(),
          Text('${p.eloDelta > 0 ? '+' : ''}${p.eloDelta} ELO', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.eloDelta >= 0 ? const Color(0xFF12754D) : PlobbyColors.loss)),
        ]),
      ])));
}

class _Team extends StatelessWidget {
  const _Team({required this.users, required this.scores, required this.win});
  final List<FeedUser> users; final List<int> scores; final bool win;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: win ? const Color(0xFFEEF1EA) : null, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (final u in users) Padding(padding: const EdgeInsets.only(right: 4), child: GestureDetector(onTap: () => context.push('/player/${u.id}'), child: avatar(u, 13))),
        const SizedBox(width: 4),
        Expanded(child: Text(users.map((u) => u.name).join(' + '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: win ? FontWeight.w800 : FontWeight.w500, color: win ? PlobbyColors.charcoal : PlobbyColors.mute))),
        if (win) const Icon(Icons.check, size: 16, color: PlobbyColors.forest),
        for (final s in scores) Padding(padding: const EdgeInsets.only(left: 10), child: Text('$s', style: TextStyle(fontWeight: win ? FontWeight.w800 : FontWeight.w600, color: win ? PlobbyColors.forest : PlobbyColors.mute))),
      ]));
}

class _Chip extends StatelessWidget {
  const _Chip(this.t, {this.dark = false, this.outlined = false});
  final String t; final bool dark, outlined;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: outlined ? null : (dark ? PlobbyColors.forest : const Color(0x478A938D)), border: outlined ? Border.all(color: PlobbyColors.sage) : null, borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: dark ? Colors.white : PlobbyColors.charcoal)));
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
      Align(alignment: Alignment.centerLeft, child: Text('${widget.post.author.name.split(' ').first} acaba de desbloquear un nuevo logro', style: const TextStyle(color: PlobbyColors.ivory, fontSize: 13.5))),
      InkWell(
        onTap: () => showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), child: Column(mainAxisSize: MainAxisSize.min, children: [
          _Disc(size: 92, id: p.achievementId), const SizedBox(height: 14),
          Text(p.title.toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 6), Text(p.description, textAlign: TextAlign.center, style: const TextStyle(color: PlobbyColors.mute)),
        ]))),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Center(child: Column(children: [
          ScaleTransition(scale: CurvedAnimation(parent: c, curve: Curves.elasticOut), child: AnimatedBuilder(animation: c, builder: (_, child) => DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: PlobbyColors.lime.withOpacity(.35 * (1 - c.value) + .12), blurRadius: 24, spreadRadius: 6)]), child: child), child: _Disc(size: 104, id: p.achievementId))),
          const SizedBox(height: 12),
          Text(p.title.toUpperCase(), style: const TextStyle(color: PlobbyColors.ivory, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          Text(p.description, style: const TextStyle(color: Color(0xC7F6F8F1))),
          if (p.milestone != null) Padding(padding: const EdgeInsets.only(top: 10), child: Chip(label: Text(p.milestone!), backgroundColor: PlobbyColors.lime, labelStyle: const TextStyle(color: PlobbyColors.forest, fontWeight: FontWeight.w800, fontSize: 12))),
        ]))),
      ),
    ]);
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.size, required this.id});
  final double size; final String id;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: const BoxDecoration(shape: BoxShape.circle, color: PlobbyColors.lime),
      child: id == 'fire' ? Center(child: WinStreakBadge(streak: 5, size: size * .5, showNumber: false)) : Icon(switch (id) { 'king' => Icons.workspace_premium_outlined, 'rise' => Icons.trending_up, 'social' => Icons.groups_2_outlined, _ => Icons.emoji_events_outlined }, size: size * .42, color: PlobbyColors.forest));
}

class _Streak extends StatelessWidget {
  const _Streak({required this.p, required this.own});
  final StreakPayload p; final bool own;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
        WinStreakBadge(streak: p.count, size: 56, showNumber: false), const SizedBox(width: 14),
        Text('${p.count}', style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w800, color: PlobbyColors.lime, height: 1)),
        const SizedBox(width: 14),
        Expanded(child: Text('${own ? 'Estás' : 'Está'} en racha\n${p.count} victorias seguidas${p.count >= 7 ? ' · ¡a por las 10!' : ''}', style: const TextStyle(color: PlobbyColors.ivory, height: 1.35))),
      ]));
}

class _Elo extends StatelessWidget {
  const _Elo({required this.post, required this.p});
  final FeedPost post; final EloPayload p;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${post.author.name.split(' ').first} ${p.headline}', style: const TextStyle(fontSize: 14, height: 1.4)),
        const SizedBox(height: 8),
        Row(children: [Text('${p.from} → ', style: const TextStyle(color: PlobbyColors.mute)), Text('${p.to}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(), _Chip('+${p.delta}')]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: ((p.to - 1200) / 400).clamp(0, 1).toDouble(), minHeight: 6, color: PlobbyColors.lime, backgroundColor: const Color(0xFFEEF1EA))),
      ]));
}

class _League extends StatelessWidget {
  const _League({required this.post, required this.p});
  final FeedPost post; final LeaguePayload p;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFEEF1EA), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: PlobbyColors.forest, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.emoji_events_outlined, size: 18, color: PlobbyColors.lime)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${post.author.name.split(' ').first} ${p.headline}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          Text(p.leagueName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          Text(p.subtitle, style: const TextStyle(fontSize: 12, color: PlobbyColors.mute)),
        ])),
      ]));
}
