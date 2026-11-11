import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/feed_repository.dart';
import '../data/mock_feed_repository.dart';
import '../domain/feed_models.dart';

final feedRepositoryProvider = Provider<FeedRepository>((ref) => MockFeedRepository());
final feedFilterProvider = StateProvider<FeedFilter>((ref) => FeedFilter.all);

class FeedState {
  const FeedState({this.posts = const [], this.cursor, this.hasMore = true, this.loadingMore = false, this.pendingNew = const []});
  final List<FeedPost> posts;
  final DateTime? cursor;
  final bool hasMore, loadingMore;
  final List<FeedPost> pendingNew; // actividad llegada en tiempo real (banner "1 actividad nueva")
  FeedState copyWith({List<FeedPost>? posts, DateTime? cursor, bool clearCursor = false, bool? hasMore, bool? loadingMore, List<FeedPost>? pendingNew}) => FeedState(
      posts: posts ?? this.posts, cursor: clearCursor ? null : (cursor ?? this.cursor), hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore, pendingNew: pendingNew ?? this.pendingNew);
}

class FeedController extends AsyncNotifier<FeedState> {
  FeedRepository get _repo => ref.read(feedRepositoryProvider);
  StreamSubscription<FeedPost>? _sub;

  @override
  Future<FeedState> build() async {
    final filter = ref.watch(feedFilterProvider);
    _sub?.cancel();
    _sub = _repo.watchNew().listen((p) {
      final s = state.valueOrNull;
      if (s == null || s.posts.any((x) => x.id == p.id) || s.pendingNew.any((x) => x.id == p.id)) return; // sin duplicados
      state = AsyncData(s.copyWith(pendingNew: [p, ...s.pendingNew]));
    });
    ref.onDispose(() => _sub?.cancel());
    final page = await _repo.fetchPage(filter: filter);
    return FeedState(posts: page.posts, cursor: page.nextCursor, hasMore: page.nextCursor != null);
  }

  Future<void> refresh() async { ref.invalidateSelf(); await future; }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || s.loadingMore || !s.hasMore) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final page = await _repo.fetchPage(filter: ref.read(feedFilterProvider), before: s.cursor);
      final ids = s.posts.map((p) => p.id).toSet();
      state = AsyncData(s.copyWith(posts: [...s.posts, ...page.posts.where((p) => !ids.contains(p.id))], cursor: page.nextCursor, clearCursor: page.nextCursor == null, hasMore: page.nextCursor != null, loadingMore: false));
    } catch (_) {
      state = AsyncData(s.copyWith(loadingMore: false)); // el fallo de red no rompe el feed ya cargado
    }
  }

  void showPending() {
    final s = state.valueOrNull;
    if (s == null || s.pendingNew.isEmpty) return;
    state = AsyncData(s.copyWith(posts: [...s.pendingNew, ...s.posts], pendingNew: const []));
  }

  /// Reacción optimista (una activa por usuario): se revierte si el backend falla.
  Future<void> react(String postId, ReactionType t) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final before = s.posts;
    final me = _repo.me;
    _patch(postId, (p) => p.copyWith(reactions: p.reactions.toggle(t, me)));
    final mine = state.value!.posts.firstWhere((p) => p.id == postId).reactions.mine;
    try {
      await _repo.setReaction(postId, mine);
    } catch (_) {
      state = AsyncData(state.value!.copyWith(posts: before));
    }
  }

  void _patch(String id, FeedPost Function(FeedPost) f) {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(posts: [for (final p in s.posts) p.id == id ? f(p) : p]));
  }

  void setComments(String postId, List<FeedComment> all) =>
      _patch(postId, (p) => p.copyWith(commentCount: all.length, previewComments: all.reversed.take(2).toList().reversed.toList()));
}

final feedControllerProvider = AsyncNotifierProvider<FeedController, FeedState>(FeedController.new);

class CommentsNotifier extends FamilyAsyncNotifier<List<FeedComment>, String> {
  FeedRepository get _repo => ref.read(feedRepositoryProvider);
  @override
  Future<List<FeedComment>> build(String postId) => _repo.comments(postId);

  Future<void> add(String text) async {
    final t = text.trim();
    if (t.isEmpty || t.length > 140) return;
    final c = await _repo.addComment(arg, t);
    state = AsyncData([...?state.valueOrNull, c]);
    ref.read(feedControllerProvider.notifier).setComments(arg, state.value!);
  }

  Future<void> remove(FeedComment c) async {
    if (c.author.id != _repo.me.id) return; // solo el propio autor (y la RLS lo valida)
    await _repo.deleteComment(c.id);
    state = AsyncData(state.value!.where((x) => x.id != c.id).toList());
    ref.read(feedControllerProvider.notifier).setComments(arg, state.value!);
  }

  Future<void> report(FeedComment c) async {
    await _repo.reportComment(c.id);
    state = AsyncData(state.value!.where((x) => x.id != c.id).toList());
    ref.read(feedControllerProvider.notifier).setComments(arg, state.value!);
  }
}

final commentsProvider = AsyncNotifierProvider.family<CommentsNotifier, List<FeedComment>, String>(CommentsNotifier.new);

class NotificationsNotifier extends AsyncNotifier<List<AppNotification>> {
  FeedRepository get _repo => ref.read(feedRepositoryProvider);
  @override
  Future<List<AppNotification>> build() => _repo.notifications();
  Future<void> markRead([String? id]) async { await _repo.markRead(id); ref.invalidateSelf(); }
  Future<void> respond(String id, bool accept) async { await _repo.respond(id, accept); ref.invalidateSelf(); }
}

final notificationsProvider = AsyncNotifierProvider<NotificationsNotifier, List<AppNotification>>(NotificationsNotifier.new);
final unreadCountProvider = Provider<int>((ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.isRead).length ?? 0);
