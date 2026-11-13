import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../social/application/social_providers.dart' show friendsProvider, requestsProvider;
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

/// Un partido genera una publicación por cada jugador (cada uno la comparte con SUS amigos). Si ves a varios de ellos,
/// el mismo partido saldría repetido: se muestra una sola vez (la primera que llega, que es la más reciente).
List<FeedPost> collapseDuplicateMatches(List<FeedPost> shown, List<FeedPost> incoming) {
  final seen = {for (final p in shown) if (p.payload case MatchPayload(:final matchId)) matchId};
  final ids = {for (final p in shown) p.id};
  return [
    for (final p in incoming)
      if (ids.add(p.id) && (p.payload is! MatchPayload || seen.add((p.payload as MatchPayload).matchId))) p,
  ];
}

class FeedController extends AsyncNotifier<FeedState> {
  FeedRepository get _repo => ref.read(feedRepositoryProvider);
  StreamSubscription<FeedPost>? _sub;
  final _reactionQueue = <String, Future<void>>{};

  @override
  Future<FeedState> build() async {
    final filter = ref.watch(feedFilterProvider);
    _sub?.cancel();
    _sub = _repo.watchNew().listen((p) {
      final s = state.valueOrNull;
      if (s == null || collapseDuplicateMatches([...s.posts, ...s.pendingNew], [p]).isEmpty) return; // sin duplicados
      state = AsyncData(s.copyWith(pendingNew: [p, ...s.pendingNew]));
    });
    ref.onDispose(() => _sub?.cancel());
    final page = await _repo.fetchPage(filter: filter);
    return FeedState(posts: collapseDuplicateMatches(const [], page.posts), cursor: page.nextCursor, hasMore: page.nextCursor != null);
  }

  Future<void> refresh() async { ref.invalidateSelf(); await future; }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || s.loadingMore || !s.hasMore) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final page = await _repo.fetchPage(filter: ref.read(feedFilterProvider), before: s.cursor);
      state = AsyncData(s.copyWith(posts: [...s.posts, ...collapseDuplicateMatches(s.posts, page.posts)], cursor: page.nextCursor, clearCursor: page.nextCursor == null, hasMore: page.nextCursor != null, loadingMore: false));
    } catch (_) {
      state = AsyncData(s.copyWith(loadingMore: false)); // el fallo de red no rompe el feed ya cargado
    }
  }

  void showPending() {
    final s = state.valueOrNull;
    if (s == null || s.pendingNew.isEmpty) return;
    state = AsyncData(s.copyWith(posts: [...collapseDuplicateMatches(const [], s.pendingNew), ...collapseDuplicateMatches(s.pendingNew, s.posts)], pendingNew: const []));
  }

  /// Reacción optimista (una activa por usuario, única también en el servidor). Las pulsaciones seguidas sobre la misma
  /// publicación se envían EN ORDEN (cola por publicación): el último estado que ves es el que queda guardado. Si el
  /// servidor falla, se restaura solo esa publicación (no se pisan otros cambios del feed).
  Future<void> react(String postId, ReactionType t) {
    final s = state.valueOrNull;
    if (s == null) return Future.value();
    final previous = s.posts.where((p) => p.id == postId).firstOrNull;
    if (previous == null) return Future.value();
    final me = _repo.me;
    _patch(postId, (p) => p.copyWith(reactions: p.reactions.toggle(t, me)));
    final mine = state.value!.posts.firstWhere((p) => p.id == postId).reactions.mine;
    final job = (_reactionQueue[postId] ?? Future.value()).then((_) => _repo.setReaction(postId, mine)).catchError((Object _) {
      _patch(postId, (p) => p.copyWith(reactions: previous.reactions));
    });
    _reactionQueue[postId] = job;
    return job;
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
  /// Acepta/rechaza (solicitud de amistad o invitación a liga). Refresca también amigos y solicitudes: antes, al aceptar
  /// desde aquí, la lista de amigos seguía vacía hasta reiniciar la app.
  Future<void> respond(String id, bool accept) async {
    try {
      await _repo.respond(id, accept);
    } finally {
      ref.invalidateSelf();
      ref.invalidate(friendsProvider);
      ref.invalidate(requestsProvider);
    }
  }
}

final notificationsProvider = AsyncNotifierProvider<NotificationsNotifier, List<AppNotification>>(NotificationsNotifier.new);
final unreadCountProvider = Provider<int>((ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.isRead).length ?? 0);
