import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/flame_paths.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_logo.dart';
import '../../../core/widgets/state_views.dart';
import '../../feed/application/feed_providers.dart';
import '../../feed/domain/feed_models.dart';
import '../../leagues/presentation/league_widgets.dart';
import '../../matches/presentation/upcoming_matches_section.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/achievements.dart';
import '../../profile/domain/models.dart';
import '../../profile/presentation/widgets/match_card.dart';
import '../../social/application/social_providers.dart';
import 'home_wiring.dart';

/// Últimas partidas confirmadas de amigos (fuente: feed, filtro «Partidos»; la RLS limita a amigos).
final friendMatchesProvider = FutureProvider.autoDispose<List<FeedPost>>((ref) async {
  final page = await ref.watch(feedRepositoryProvider).fetchPage(filter: FeedFilter.matches, limit: 20);
  return page.posts.where((p) => p.author.id != 'me' && p.payload is MatchPayload).toList();
});

String greeting(DateTime now) => now.hour < 6 ? 'Buenas noches,' : now.hour < 14 ? 'Buenos días,' : now.hour < 21 ? 'Buenas tardes,' : 'Buenas noches,';

/// Pantalla de Inicio (prototipo `#home`): banner, tarjetas de amigos/ELO/racha, próximos partidos, partidas de amigos,
/// mis últimos partidos y logros. TODOS los valores vienen de providers reales (ninguna cifra fija como 48, 1482 o 2).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(homeCountersProvider);
    final view = ref.watch(profileViewProvider('me'));
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileProvider('me')); ref.invalidate(friendsProvider); ref.invalidate(friendMatchesProvider); ref.invalidate(notificationsProvider);
          try { await ref.read(profileProvider('me').future); } catch (_) {/* el error se muestra en la sección */}
        },
        child: ListView(padding: EdgeInsets.zero, children: [
          _Banner(counters: c, profile: view.valueOrNull?.data.profile),
          Transform.translate(offset: const Offset(0, -34), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _Counters(counters: c))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 140), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const UpcomingMatchesSection(max: 3),
            const SizedBox(height: AppLayout.sectionGap),
            SectionHeader(title: 'Últimas partidas de amigos', actionLabel: 'Ver todas', onAction: () => HomeNav.seeAllFriendMatches(context)),
            const _FriendMatches(),
            const SizedBox(height: AppLayout.sectionGap),
            SectionHeader(title: 'Últimos partidos jugados', actionLabel: 'Ver todos', onAction: () => HomeNav.seeAllMyMatches(context)),
            view.when(
              loading: () => const Column(children: [MatchCardSkeleton(), SizedBox(height: 10), MatchCardSkeleton()]),
              error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(profileProvider('me'))),
              data: (v) {
                final ms = v.confirmed.take(3).toList();
                if (ms.isEmpty) {
                  return EmptyStateCard(icon: Icons.sports_tennis, title: 'Aún no has jugado partidos', text: 'Cuando se confirme tu primer resultado aparecerá aquí.',
                      primary: 'Crear partido', onPrimary: () => HomeNav.newMatch(context));
                }
                final me = PlayerRef('me', v.data.profile.fullName, v.data.profile.avatarUrl);
                return Column(children: [for (final m in ms) MatchCard(match: m, me: me, onTap: () => context.push('/match/${m.id}/final'))]);
              },
            ),
            const SizedBox(height: AppLayout.sectionGap),
            SectionHeader(title: 'Logros', actionLabel: 'Ver todos', onAction: () => HomeNav.seeAllAchievements(context)),
            view.when(
              loading: () => const LoadingBlock(height: 120),
              error: (_, __) => const SizedBox.shrink(),
              data: (v) => _Achievements(items: v.achievements),
            ),
          ])),
        ]),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.counters, required this.profile});
  final HomeCounters counters; final PlayerProfile? profile;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final first = (profile?.fullName ?? '').trim().split(RegExp(r'\s+')).first;
    Widget btn(IconData i, String label, VoidCallback f, [int badge = 0]) => Material(color: const Color(0x38171C19), shape: const CircleBorder(),
        child: HomeIconButton(icon: i, label: label, badge: badge, onTap: f));
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: SizedBox(height: 300 + top, child: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/images/home_banner.jpg', fit: BoxFit.cover, semanticLabel: 'Pistas de pádel al atardecer',
            errorBuilder: (_, __, ___) => const LeagueCover(cover: 'court', height: 300, radius: 0)),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x66171C19), Color(0x00171C19), Color(0xCC171C19)], stops: [0, .45, 1]))),
        Positioned(left: 20, top: top + 14, child: const PlobbyLogo(markHeight: 30)),
        Positioned(right: 12, top: top + 6, child: IconTheme(data: const IconThemeData(color: Colors.white), child: Row(children: [
          btn(Icons.person_add_alt_1_outlined, 'Añadir amigos', () => HomeNav.addFriends(context)),
          const SizedBox(width: 6),
          btn(Icons.notifications_none_rounded, 'Notificaciones', () => HomeNav.notifications(context), counters.unreadNotifications),
          const SizedBox(width: 6),
          btn(Icons.send_outlined, 'Mensajes', () => HomeNav.messages(context), counters.unreadMessages),
        ]))),
        Positioned(left: 20, right: 20, bottom: 52, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Semantics(button: true, label: 'Ver mi perfil', child: GestureDetector(onTap: () => HomeNav.profile(context),
              child: LeagueAvatar(name: profile?.fullName ?? '', avatarUrl: profile?.avatarUrl, size: 64, highlight: true))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(greeting(DateTime.now()), style: const TextStyle(color: Colors.white, fontSize: 27, height: 1.12, fontWeight: FontWeight.w800, shadows: [Shadow(color: Color(0x66000000), blurRadius: 14)])),
            Text(first.isEmpty ? '…' : first, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 27, height: 1.12, fontWeight: FontWeight.w800, shadows: [Shadow(color: Color(0x66000000), blurRadius: 14)])),
          ])),
        ])),
      ])),
    );
  }
}

class _Counters extends ConsumerWidget {
  const _Counters({required this.counters});
  final HomeCounters counters;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = counters;
    final friends = ref.watch(friendsProvider).valueOrNull ?? const [];
    BoxDecoration deco() => const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [BoxShadow(color: Color(0x47171C19), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -8)]);
    Widget tile({required int flex, required String label, required VoidCallback onTap, required Widget child, double? width}) => Expanded(flex: flex, child: Semantics(button: true, label: label,
        child: Pressable(child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: const BorderRadius.all(Radius.circular(20)),
            child: Ink(height: 68, decoration: deco(), padding: const EdgeInsets.symmetric(horizontal: 14), child: child))))));
    return Row(children: [
      tile(flex: 135, label: 'Amigos: ${c.friends}. Ver todos', onTap: () => HomeNav.friends(context), child: Row(children: [
        SizedBox(width: 20.0 + 18 * (friends.take(3).length - 1).clamp(0, 2), height: 32, child: Stack(children: [
          for (var i = 0; i < friends.take(3).length; i++) Positioned(left: i * 18.0, child: LeagueAvatar(name: friends[i].player.name, avatarUrl: friends[i].player.avatarUrl, size: 32)),
        ])),
        const SizedBox(width: 10),
        _Value(value: '${c.friends}', label: 'Amigos'),
      ])),
      const SizedBox(width: 10),
      tile(flex: 100, label: c.elo == null ? 'ELO' : 'ELO ${c.elo}${(c.delta30 ?? 0) == 0 ? '' : ', ${c.delta30! > 0 ? 'sube' : 'baja'} ${c.delta30!.abs()} puntos'}',
          onTap: () => HomeNav.elo(context), child: Row(children: [
        _Value(value: c.elo == null ? '—' : '${c.elo}', label: 'ELO', trailing: (c.delta30 ?? 0) == 0 ? null : Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(c.delta30! > 0 ? Icons.north_east : Icons.south_east, size: 11, color: c.delta30! > 0 ? AppColors.text : AppColors.danger),
          Text('${c.delta30!.abs()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.delta30! > 0 ? AppColors.text : AppColors.danger)),
        ])),
      ])),
      const SizedBox(width: 10),
      Semantics(button: true, label: 'Racha actual: ${c.streak} ${c.streak == 1 ? 'partido ganado' : 'partidos ganados'} seguidos', child: Pressable(child: Material(color: Colors.transparent,
          child: InkWell(onTap: () => HomeNav.streak(context, c), borderRadius: const BorderRadius.all(Radius.circular(20)), child: Ink(width: 68, height: 68, decoration: deco(),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 30, height: 30, child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(size: const Size(30, 30), painter: _Flame(active: c.streak > 0)),
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text('${c.streak}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.brandInk))),
                ])),
                const SizedBox(height: 2),
                const Text('Racha', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              ])))))),
    ]);
  }
}

class _Flame extends CustomPainter {
  _Flame({required this.active});
  final bool active;
  @override
  void paint(Canvas c, Size s) {
    final k = s.height / 130;                          // flameOuter() vive en una caja de 100 × 130
    c.save(); c.translate((s.width - 100 * k) / 2, 0); c.scale(k, k);
    c.drawPath(flameOuter(), Paint()..color = active ? AppColors.brand : AppColors.surfaceSunken);
    c.restore();
  }
  @override
  bool shouldRepaint(_Flame o) => o.active != active;
}

class _Value extends StatelessWidget {
  const _Value({required this.value, required this.label, this.trailing});
  final String value, label; final Widget? trailing;
  @override
  Widget build(BuildContext context) => Flexible(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(child: Text(value, style: const TextStyle(fontSize: 22, height: 1, fontWeight: FontWeight.w800, letterSpacing: -.2))),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)), if (trailing != null) ...[const SizedBox(width: 6), trailing!]]),
      ]));
}

/// «Últimas partidas de amigos»: fila de amigos (stories) + tarjeta del partido del amigo seleccionado.
class _FriendMatches extends ConsumerStatefulWidget {
  const _FriendMatches();
  @override
  ConsumerState<_FriendMatches> createState() => _FriendMatchesState();
}

class _FriendMatchesState extends ConsumerState<_FriendMatches> {
  int _sel = 0;
  @override
  Widget build(BuildContext context) => ref.watch(friendMatchesProvider).when(
        loading: () => const LoadingBlock(height: 170),
        error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(friendMatchesProvider)),
        data: (posts) {
          final seen = <String>{};
          final latest = [for (final p in posts) if (seen.add(p.author.id)) p].take(10).toList();
          if (latest.isEmpty) {
            return EmptyStateCard(icon: Icons.group_outlined, title: 'Tus amigos aún no han jugado', text: 'Cuando un amigo confirme un partido lo verás aquí.',
                primary: 'Añadir amigos', onPrimary: () => HomeNav.addFriends(context));
          }
          final sel = _sel.clamp(0, latest.length - 1);
          final p = latest[sel], m = p.payload as MatchPayload;
          return Column(children: [
            SizedBox(height: 86, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: latest.length, separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final a = latest[i].author;
                return Semantics(button: true, selected: i == sel, label: 'Partido de ${a.name}', child: GestureDetector(onTap: () => setState(() => _sel = i), child: SizedBox(width: 62, child: Column(children: [
                  Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: i == sel ? AppColors.brand : AppColors.border, width: 2.5)),
                      child: LeagueAvatar(name: a.name, avatarUrl: a.avatarUrl, size: 50)),
                  const SizedBox(height: 4),
                  Text(a.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: i == sel ? FontWeight.w700 : FontWeight.w500)),
                ]))));
              })),
            const SizedBox(height: 10),
            Material(color: AppColors.inverse, borderRadius: AppRadius.rLg, child: InkWell(borderRadius: AppRadius.rLg, onTap: () => context.go('/feed'), child: Padding(padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    LeagueChip(m.won ? 'Victoria' : 'Derrota', tone: m.won ? ChipTone.lime : ChipTone.glass),
                    const SizedBox(width: 8),
                    if (m.leagueName != null) Flexible(child: Text(m.leagueName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12))),
                    const Spacer(),
                    if (m.eloDelta != 0) Text('${m.eloDelta > 0 ? '+' : ''}${m.eloDelta} ELO', style: const TextStyle(color: AppColors.lime300, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                  const SizedBox(height: 12),
                  Text('${m.teamA.map((u) => u.name.split(' ').first).join(' y ')}  vs  ${m.teamB.map((u) => u.name.split(' ').first).join(' y ')}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(m.score, style: const TextStyle(fontFamily: 'Unbounded', color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  if (m.venue != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(m.venue!, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12))),
                ])))),
          ]);
        },
      );
}

class _Achievements extends StatelessWidget {
  const _Achievements({required this.items});
  final List<Achievement> items;
  @override
  Widget build(BuildContext context) {
    final list = [...items]..sort((a, b) => (b.unlocked ? 1 : 0) - (a.unlocked ? 1 : 0));
    return SizedBox(height: 132, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, i) {
        final a = list[i];
        return Semantics(label: '${a.title}: ${a.unlocked ? 'conseguido' : '${a.current} de ${a.goal}'}', child: SizedBox(width: 96, child: Column(children: [
          Container(width: 72, height: 72, alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: a.unlocked ? AppColors.inverse : AppColors.surfaceSunken, border: Border.all(color: a.unlocked ? AppColors.brand : AppColors.border, width: 3)),
              child: a.unlocked ? const Icon(Icons.emoji_events, color: AppColors.lime300, size: 30)
                  : Stack(alignment: Alignment.center, children: [
                      SizedBox(width: 60, height: 60, child: CircularProgressIndicator(value: a.progress, strokeWidth: 4, color: AppColors.brand, backgroundColor: Colors.transparent)),
                      const Icon(Icons.lock_outline, color: AppColors.ink400)])),
          const SizedBox(height: 6),
          Text(a.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text(a.unlocked ? 'Conseguido' : '${a.current} de ${a.goal}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ])));
      }));
  }
}
