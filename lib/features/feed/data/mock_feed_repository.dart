import 'dart:async';
import '../domain/feed_models.dart';
import 'feed_repository.dart';

/// DATOS MOCK. Solo se publican partidos confirmados; el mock incluye uno sin confirmar que se descarta.
class MockFeedRepository implements FeedRepository {
  MockFeedRepository() { _seed(); }
  final _now = DateTime.now();
  final _posts = <FeedPost>[];
  final _comments = <String, List<FeedComment>>{};
  final _users = <String, FeedUser>{};
  final _ctrl = StreamController<FeedPost>.broadcast();
  var _notifs = <AppNotification>[];
  var _cid = 0;

  @override
  final me = const FeedUser(id: 'me', name: 'Diego Castello', username: 'diego.c');
  FeedUser u(String id, String name) => _users.putIfAbsent(id, () => FeedUser(id: id, name: name, username: name.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '.').replaceAll(RegExp(r'^\.|\.$'), '')));

  void _seed() {
    final marcos = u('marcos', 'Marcos R.'), alvaro = u('alvaro', 'Álvaro P.'), laura = u('laura', 'Laura G.'), pablo = u('pablo', 'Pablo S.'),
        lucia = u('lucia', 'Lucía M.'), carla = u('carla', 'Carla N.'), carlos = u('carlos', 'Carlos M.'), sofia = u('sofia', 'Sofía G.');
    var i = 0;
    FeedPost p(FeedUser a, int minsAgo, FeedPayload pl, {Map<ReactionType, int> rx = const {}, List<FeedUser> who = const []}) =>
        FeedPost(id: 'p${i++}', author: a, createdAt: _now.subtract(Duration(minutes: minsAgo)), payload: pl, reactions: ReactionSummary(counts: rx, recent: who));
    _posts.addAll([
      p(laura, 55, MatchPayload(matchId: 'm1', teamA: [laura, carlos], teamB: [pablo, sofia], sets: const [(6, 1), (6, 1)], won: true, eloDelta: 15, venue: 'Padel Chamberí'), rx: {ReactionType.fire: 3, ReactionType.heart: 1}, who: [pablo, carlos]),
      p(marcos, 125, MatchPayload(matchId: 'm2', teamA: [marcos, me], teamB: [alvaro, lucia], sets: const [(6, 3), (6, 4)], won: true, eloDelta: 18, venue: 'Club La Moraleja', leagueName: 'BÜNKER PADEL LEAGUE'), rx: {ReactionType.fire: 2, ReactionType.clap: 2}),
      // El mismo partido m1 publicado también por Pablo (cada jugador lo comparte con sus amigos): el feed lo muestra una vez.
      p(pablo, 56, MatchPayload(matchId: 'm1', teamA: [pablo, sofia], teamB: [laura, carlos], sets: const [(1, 6), (1, 6)], won: false, eloDelta: -15, venue: 'Padel Chamberí')),
      p(sofia, 95, const TournamentPayload(tournamentId: 't0', name: 'Open de Otoño', partnerName: 'Irene Vega', teams: 6), rx: {ReactionType.clap: 6, ReactionType.fire: 2}, who: [laura, marcos]),
      p(marcos, 130, const AchievementPayload(achievementId: 'fire', title: 'En racha', description: '5 victorias consecutivas.'), rx: {ReactionType.fire: 4}),
      p(me, 300, const StreakPayload(5), rx: {ReactionType.fire: 2, ReactionType.strong: 1}),
      p(pablo, 760, const EloPayload(from: 1448, to: 1468, headline: 'bate su récord personal de ELO')),
      p(carla, 900, const AchievementPayload(achievementId: 'king', title: 'Rey de la pista', description: 'Ha alcanzado la primera posición en una liga.', milestone: 'CLUB LA MORALEJA · #1'), rx: {ReactionType.clap: 5}),
      p(alvaro, 1700, const StreakPayload(7), rx: {ReactionType.fire: 3}),
      p(lucia, 2500, const AchievementPayload(achievementId: 'rise', title: 'Estrella emergente', description: 'Ha mejorado su ELO en 100 puntos.', milestone: '+104 ELO')),
      p(carlos, 1300, const LeaguePayload(leagueName: 'CLUB LA MORALEJA', headline: 'lidera la clasificación de', subtitle: 'Temporada 03 · #1')),
      for (var k = 0; k < 12; k++)
        p(k.isEven ? marcos : alvaro, 3000 + k * 400, MatchPayload(matchId: 'x$k', teamA: [k.isEven ? marcos : alvaro, pablo], teamB: [laura, sofia], sets: k % 3 == 0 ? const [(3, 6), (4, 6)] : const [(6, 2), (6, 4)], won: k % 3 != 0, eloDelta: k % 3 == 0 ? -9 : 11, venue: 'Club Alameda')),
    ]);
    _posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _comments['p1'] = [FeedComment(id: 'c0', postId: 'p1', author: alvaro, content: 'La próxima revancha.', createdAt: _now.subtract(const Duration(minutes: 90)))];
    _notifs = [
      AppNotification(id: 'n1', type: NotificationType.reaction, actors: [marcos, alvaro, lucia, carla], text: 'Marcos y 3 más reaccionaron 🔥 a tu partido', createdAt: _now.subtract(const Duration(minutes: 18)), postId: 'p1'),
      AppNotification(id: 'n2', type: NotificationType.comment, actors: [alvaro], text: 'Álvaro comentó: «La próxima revancha.»', createdAt: _now.subtract(const Duration(minutes: 95)), postId: 'p1'),
      AppNotification(id: 'n3', type: NotificationType.friendRequest, actors: [u('raul', 'Raúl D.')], text: 'Raúl D. te ha enviado una solicitud de amistad', createdAt: _now.subtract(const Duration(hours: 4)), actionable: true),
      AppNotification(id: 'n5', type: NotificationType.leagueInvite, actors: [u('irene', 'Irene V.')], text: 'Irene V. te invita a AFTERWORK PADEL CLUB', createdAt: _now.subtract(const Duration(hours: 13)), actionable: true),
    ];
  }

  bool _match(FeedPost p, FeedFilter f) => switch (f) {
        FeedFilter.all => true,
        FeedFilter.friends => p.author.id != me.id,
        FeedFilter.matches => p.payload is MatchPayload,
        FeedFilter.achievements => p.payload is AchievementPayload || p.payload is StreakPayload,
        FeedFilter.leagues => p.payload is LeaguePayload || p.payload is TournamentPayload || (p.payload is MatchPayload && (p.payload as MatchPayload).leagueName != null),
      };

  @override
  Future<FeedPage> fetchPage({required FeedFilter filter, DateTime? before, int limit = 8}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final l = _posts.where((p) => _match(p, filter) && (before == null || p.createdAt.isBefore(before))).toList();
    final page = l.take(limit).toList();
    return FeedPage(page.map((p) => p.copyWith(commentCount: _comments[p.id]?.length ?? 0, previewComments: (_comments[p.id] ?? []).reversed.take(2).toList().reversed.toList())).toList(),
        l.length > limit ? page.last.createdAt : null);
  }

  @override
  Future<void> setReaction(String postId, ReactionType? type) async {}   // Supabase: upsert/delete en `reactions`
  @override
  Future<List<(FeedUser, ReactionType)>> reactionsFor(String postId) async => [(u('marcos', 'Marcos R.'), ReactionType.fire), (u('alvaro', 'Álvaro P.'), ReactionType.clap)];
  @override
  Future<List<FeedComment>> comments(String postId) async => List.of(_comments[postId] ?? []);
  @override
  Future<FeedComment> addComment(String postId, String content) async {
    final c = FeedComment(id: 'c${++_cid}', postId: postId, author: me, content: content.trim(), createdAt: DateTime.now());
    (_comments[postId] ??= []).add(c);
    return c;
  }
  @override
  Future<void> deleteComment(String id) async => _comments.forEach((_, l) => l.removeWhere((c) => c.id == id && c.author.id == me.id));
  @override
  Future<void> reportComment(String id) async => _comments.forEach((_, l) => l.removeWhere((c) => c.id == id)); // oculto + revisión
  @override
  Future<List<AppNotification>> notifications() async => List.of(_notifs);
  @override
  Future<void> markRead(String? id) async => _notifs = [for (final n in _notifs) (id == null || n.id == id) ? n.copyWith(isRead: true) : n];
  @override
  Future<void> respond(String id, bool accept) async => _notifs = [for (final n in _notifs) n.id == id ? n.copyWith(actionable: false, isRead: true) : n];
  @override
  Stream<FeedPost> watchNew() => _ctrl.stream;
}
