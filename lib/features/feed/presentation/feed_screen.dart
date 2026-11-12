import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../application/feed_providers.dart';
import '../domain/feed_models.dart';
import 'widgets/activity_cards.dart';

const _filters = {FeedFilter.all: 'Todo', FeedFilter.friends: 'Amigos', FeedFilter.matches: 'Partidos', FeedFilter.achievements: 'Logros', FeedFilter.leagues: 'Ligas'};

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
        color: PlobbyColors.forest,
        onRefresh: () => ref.read(feedControllerProvider.notifier).refresh(),
        child: CustomScrollView(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(child: _Header()),
          SliverPersistentHeader(pinned: true, delegate: _Chips(filter, (f) => ref.read(feedFilterProvider.notifier).state = f)),
          ...async.when(
            loading: () => [SliverList.builder(itemCount: 3, itemBuilder: (_, __) => const _Skeleton())],
            error: (e, _) => [SliverFillRemaining(hasScrollBody: false, child: _ErrorView(onRetry: () => ref.invalidate(feedControllerProvider)))],
            data: (s) => s.posts.isEmpty ? [SliverFillRemaining(hasScrollBody: false, child: _Empty(filter: filter))] : [
              if (s.pendingNew.isNotEmpty) SliverToBoxAdapter(child: Center(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: FilledButton.icon(onPressed: ref.read(feedControllerProvider.notifier).showPending, icon: const Icon(Icons.arrow_upward, size: 14), label: Text('${s.pendingNew.length} actividad nueva'))))),
              SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20), sliver: SliverList.builder(
                itemCount: s.posts.length + 1,
                itemBuilder: (_, i) => i < s.posts.length
                    ? RepaintBoundary(child: ActivityCard(key: ValueKey(s.posts[i].id), post: s.posts[i]))
                    : (s.loadingMore ? const _Skeleton() : Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(s.hasMore ? '' : 'Estás al día ✓', style: const TextStyle(color: PlobbyColors.mute))))),
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
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
          const Text('PLOBBY', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 4, fontSize: 13, color: PlobbyColors.forest)),
          const Spacer(),
          Badge(isLabelVisible: unread > 0, label: Text('$unread'), backgroundColor: PlobbyColors.lime, textColor: PlobbyColors.forest,
              child: IconButton(tooltip: 'Notificaciones, $unread sin leer', onPressed: () => context.push('/notifications'), icon: BellBadge(count: unread, showCount: false, icon: const Icon(Icons.notifications_none)))),
          const SizedBox(width: 8),
          GestureDetector(onTap: () => context.go('/profile'), child: const CircleAvatar(radius: 20, backgroundColor: PlobbyColors.forest, child: Text('D', style: TextStyle(color: PlobbyColors.ivory)))),
        ])),
        const Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 0), child: Text('Feed', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1))),
        const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 0), child: Text('Tu comunidad de pádel está jugando.', style: TextStyle(color: PlobbyColors.mute))),
        SizedBox(height: 100, child: ListView.separated(  // 16 + avatar 62 + 6 + nombre 16 = 100 (con 96 se desbordaba 4 px)
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), itemCount: friends.length, separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final p = friends[i];
            final (icon, dark) = switch (p.payload) { MatchPayload() => (Icons.sports_tennis, true), AchievementPayload() => (Icons.star, false), StreakPayload() => (Icons.local_fire_department, false), EloPayload() => (Icons.trending_up, true), LeaguePayload() => (Icons.emoji_events, true) };
            return GestureDetector(onTap: () => context.push('/player/${p.author.id}'), child: SizedBox(width: 62, child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(21), border: Border.all(color: i < 5 ? PlobbyColors.forest : const Color(0x33171C19), width: 2)),
                    child: ClipRRect(borderRadius: BorderRadius.circular(17), child: SizedBox(width: 52, height: 52, child: ColoredBox(color: PlobbyColors.forest, child: Center(child: Text(p.author.name[0], style: const TextStyle(color: PlobbyColors.ivory, fontWeight: FontWeight.w800, fontSize: 18))))))),
                Positioned(right: -2, bottom: -2, child: Container(width: 22, height: 22, decoration: BoxDecoration(color: dark ? PlobbyColors.forest : PlobbyColors.lime, borderRadius: BorderRadius.circular(8), border: Border.all(color: PlobbyColors.ivory, width: 2)), child: Icon(icon, size: 12, color: dark ? PlobbyColors.lime : PlobbyColors.forest))),
              ]),
              const SizedBox(height: 6),
              Text(p.author.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ])));
          },
        )),
      ]),
    );
  }
}

class _Chips extends SliverPersistentHeaderDelegate {
  _Chips(this.sel, this.onSel);
  final FeedFilter sel; final ValueChanged<FeedFilter> onSel;
  @override double get minExtent => 58;
  @override double get maxExtent => 58;
  @override
  Widget build(BuildContext c, double s, bool o) => Container(color: PlobbyColors.ivory, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(20, 12, 20, 10), children: [
        for (final e in _filters.entries) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
          label: Text(e.value), selected: sel == e.key, onSelected: (_) => onSel(e.key), showCheckmark: false,
          selectedColor: AppColors.brand, backgroundColor: AppColors.surface, labelStyle: TextStyle(fontWeight: FontWeight.w600, color: sel == e.key ? AppColors.brandInk : AppColors.text), side: BorderSide(color: sel == e.key ? AppColors.brand : AppColors.border, width: 1.5))),
      ]));
  @override
  bool shouldRebuild(_Chips o) => o.sel != sel;
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12), padding: const EdgeInsets.all(16), height: 196,  // 32 + 164 de contenido (con 190 se desbordaba 6 px)
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_bone(40, 40, r: 20), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_bone(110, 12), const SizedBox(height: 6), _bone(70, 10)])]),
        const SizedBox(height: 14), _bone(double.infinity, 70), const SizedBox(height: 12), _bone(150, 28),
      ]));
  Widget _bone(double w, double h, {double r = 8}) => Container(width: w, height: h, decoration: BoxDecoration(color: const Color(0xFFE9E6DB), borderRadius: BorderRadius.circular(r)));
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});
  final FeedFilter filter;
  @override
  Widget build(BuildContext context) {
    final ach = filter == FeedFilter.achievements;
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(ach ? Icons.emoji_events_outlined : Icons.groups_2_outlined, size: 56, color: PlobbyColors.sage),
      const SizedBox(height: 16),
      Text(ach ? 'Tus amigos todavía no han desbloqueado ningún logro.' : 'Tu comunidad de pádel acaba de empezar.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      if (!ach) ...[const SizedBox(height: 8), const Text('Añade amigos para ver sus partidos, logros y rachas.', textAlign: TextAlign.center, style: TextStyle(color: PlobbyColors.mute)), const SizedBox(height: 20), FilledButton(onPressed: () => context.push('/friends'), child: const Text('Buscar amigos'))],
    ])));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off, size: 40, color: PlobbyColors.mute), const SizedBox(height: 10),
        const Text('No se pudo cargar el feed'), const SizedBox(height: 10), OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
      ]));
}
