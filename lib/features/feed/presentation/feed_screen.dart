import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/silhouette_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/application/profile_providers.dart';
import '../application/feed_providers.dart';
import '../domain/feed_models.dart';
import 'widgets/activity_cards.dart';

const _filters = {FeedFilter.all: 'Todo', FeedFilter.friends: 'Amigos', FeedFilter.matches: 'Partidos', FeedFilter.achievements: 'Logros', FeedFilter.leagues: 'Competiciones'};

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _scroll.addListener(_onScroll); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _scroll.dispose(); super.dispose(); }
  void _onScroll() { if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) ref.read(feedControllerProvider.notifier).loadMore(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed) ref.read(feedControllerProvider.notifier).refresh(); } // refresco al volver

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feedControllerProvider);
    final filter = ref.watch(feedFilterProvider);
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.text,
        onRefresh: () => ref.read(feedControllerProvider.notifier).refresh(),
        child: CustomScrollView(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(child: _Header()),
          SliverPersistentHeader(pinned: true, delegate: _Chips(filter, (f) => ref.read(feedFilterProvider.notifier).state = f)),
          ...async.when(
            loading: () => [SliverList.builder(itemCount: 3, itemBuilder: (_, __) => const _Skeleton())],
            error: (e, _) => [SliverFillRemaining(hasScrollBody: false, child: _ErrorView(onRetry: () => ref.invalidate(feedControllerProvider)))],
            data: (s) => s.posts.isEmpty ? [SliverFillRemaining(hasScrollBody: false, child: _Empty(filter: filter))] : [
              if (s.pendingNew.isNotEmpty) SliverToBoxAdapter(child: Center(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: PlobbyButton(kind: PlobbyButtonKind.small, icon: PlobbyIcons.arrup, label: '${s.pendingNew.length} actividad nueva', onPressed: ref.read(feedControllerProvider.notifier).showPending)))),
              SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20), sliver: SliverList.builder(
                itemCount: s.posts.length + 1,  // padding superior de .fl2: 4
                itemBuilder: (_, i) => i < s.posts.length
                    ? RepaintBoundary(child: ActivityCard(key: ValueKey(s.posts[i].id), post: s.posts[i]))
                    : (s.loadingMore ? const _Skeleton() : Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(s.hasMore ? '' : 'Estás al día ✓', style: PlobbyText.sub)))),
              )),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ]),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final posts = ref.watch(feedControllerProvider).valueOrNull?.posts ?? const [];
    final seen = <String>{};
    final friends = [for (final p in posts) if (p.author.id != 'me' && seen.add(p.author.id)) p].take(9).toList();
    final me = ref.watch(profileProvider('me')).valueOrNull?.profile;
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // .fh .r1: logotipo lima con punto · campana con contador · avatar
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
          Semantics(label: 'Plobby', excludeSemantics: true, child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            const Text('PLOBBY', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 30, height: 1, fontWeight: FontWeight.w700, letterSpacing: -0.9, color: AppColors.brand)),
            Container(width: 6, height: 6, margin: const EdgeInsets.only(left: 2, bottom: 9), decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
          ])),
          const Spacer(),
          Stack(clipBehavior: Clip.none, children: [
            IconSquareButton(icon: PlobbyIcons.bell, tooltip: unread > 0 ? 'Notificaciones, $unread sin leer' : 'Notificaciones', onPressed: () => context.push('/notifications')),
            if (unread > 0) Positioned(right: -5, top: -5, child: IgnorePointer(child: Container(
              height: 18, constraints: const BoxConstraints(minWidth: 18), padding: const EdgeInsets.symmetric(horizontal: 5), alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.bg, width: 2)),
              child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, height: 1, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.brandInk)),
            ))),
          ]),
          const SizedBox(width: 10),
          Semantics(button: true, label: 'Mi perfil', excludeSemantics: true, child: GestureDetector(onTap: () => context.go('/profile'), child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2)),
            child: ClipOval(child: SizedBox(width: 40, height: 40, child: me?.avatarUrl != null && me!.avatarUrl!.isNotEmpty
                ? Image.network(me.avatarUrl!, fit: BoxFit.cover, cacheWidth: 120, errorBuilder: (_, __, ___) => SilhouetteAvatar(seed: me.id, size: 40))
                : SilhouetteAvatar(seed: me?.id ?? 'me', size: 40))),
          ))),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Semantics(header: true, child: const Text('Feed', style: PlobbyText.t1))),
        const Padding(padding: EdgeInsets.fromLTRB(20, 6, 20, 0), child: Text('Tu comunidad de pádel está jugando.', style: PlobbyText.sub)),
        // .bubs: burbujas de actividad reciente (aro tinta en las nuevas)
        SizedBox(height: 101, child: ListView.separated(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(20, 16, 20, 4), itemCount: friends.length, separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final p = friends[i];
            final (icon, dark) = switch (p.payload) { MatchPayload() => (PlobbyIcons.ball, true), AchievementPayload() => (PlobbyIcons.star, false), StreakPayload() => (PlobbyIcons.flame, false), EloPayload() => (PlobbyIcons.arrup, true), LeaguePayload() => (PlobbyIcons.trophy, true), TournamentPayload() => (PlobbyIcons.trophy, false) };
            final fresh = i < 5;
            return Semantics(button: true, label: '${p.author.name}, actividad reciente', excludeSemantics: true, child: GestureDetector(onTap: () => context.push('/player/${p.author.id}'), child: SizedBox(width: 62, child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(21), border: Border.all(color: fresh ? AppColors.text : const Color(0x1A171C19), width: 2)),
                    child: ClipRRect(borderRadius: BorderRadius.circular(17), child: SizedBox(width: 48, height: 48, child: feedAvatarFill(p.author, 48)))),
                Positioned(right: -4, bottom: -4, child: Container(width: 22, height: 22, decoration: BoxDecoration(color: dark ? AppColors.inverse : AppColors.brand, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.bg, width: 2)),
                    child: Center(child: PlobbyIcon(icon, size: 12, strokeWidth: 2.2, color: dark ? AppColors.brand : AppColors.brandInk)))),
              ]),
              const SizedBox(height: 6),
              Text(p.author.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text)),
            ]))));
          },
        )),
      ]),
    );
  }
}

/// `.fchips`: fijas al hacer scroll; activa en lima (píldora), inactivas transparentes con borde interior .1 (34 px, 13/700).
class _Chips extends SliverPersistentHeaderDelegate {
  _Chips(this.sel, this.onSel);
  final FeedFilter sel; final ValueChanged<FeedFilter> onSel;
  @override double get minExtent => 58;
  @override double get maxExtent => 58;
  @override
  Widget build(BuildContext c, double s, bool o) => Container(color: AppColors.bg, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(20, 14, 20, 10), children: [
        for (final e in _filters.entries) Padding(padding: const EdgeInsets.only(right: 8), child: Semantics(button: true, selected: sel == e.key, label: e.value, excludeSemantics: true, child: Material(
          color: sel == e.key ? AppColors.brand : Colors.transparent,
          shape: sel == e.key ? const StadiumBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(9), side: const BorderSide(color: Color(0x1A171C19))),
          child: InkWell(customBorder: sel == e.key ? const StadiumBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)), onTap: () => onSel(e.key),
            child: Container(height: 34, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center,
              child: Text(e.value, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0, color: sel == e.key ? AppColors.brandInk : AppColors.textMuted)))),
        ))),
      ]));
  @override
  bool shouldRebuild(_Chips o) => o.sel != sel;
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12), padding: const EdgeInsets.all(16), height: 196,  // 32 + 164 de contenido (con 190 se desbordaba 6 px)
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_bone(40, 40, r: 20), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_bone(110, 12), const SizedBox(height: 6), _bone(70, 10)])]),
        const SizedBox(height: 14), _bone(double.infinity, 70), const SizedBox(height: 12), _bone(150, 28),
      ]));
  Widget _bone(double w, double h, {double r = 8}) => Container(width: w, height: h, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(r)));
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});
  final FeedFilter filter;
  @override
  Widget build(BuildContext context) {
    final ach = filter == FeedFilter.achievements;
    return Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), child: Align(alignment: Alignment.topCenter, child: EmptyStateCard(
      icon: ach ? Icons.emoji_events_outlined : Icons.groups_2_outlined,
      title: ach ? 'Tus amigos todavía no han desbloqueado ningún logro.' : 'Tu comunidad de pádel acaba de empezar.',
      text: ach ? 'Cuando alguien consiga un logro aparecerá aquí.' : 'Añade amigos para ver sus partidos, logros y rachas.',
      primary: ach ? null : 'Buscar amigos', onPrimary: () => context.push('/friends'),
    )));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), child: Align(alignment: Alignment.topCenter,
      child: ErrorStateCard(title: 'No se pudo cargar el feed', onRetry: onRetry)));
}
