import 'dart:async';
import '../domain/social_models.dart';
import 'social_repository.dart';

/// DATOS MOCK para desarrollo/tests. Sustituir por SupabaseSocialRepository.
class MockSocialRepository implements SocialRepository {
  @override
  String get meId => 'me';
  @override
  Stream<SocialChange> changes() => const Stream.empty();
  @override
  Future<int> friendCount(String userId) async => userId == meId ? _friends.length : 12;
  static const _a = PlayerSummary(id: 'marcos', name: 'Marcos R.', username: 'marcos.r', elo: 1455, level: 'Intermedio alto', online: true, city: 'Madrid', club: 'La Moraleja');
  static const _b = PlayerSummary(id: 'laura', name: 'Laura G.', username: 'laura.g', elo: 1545, level: 'Avanzado');
  late final List<Friend> _friends = [
    const Friend(_b, FriendActivity(lastMatch: 'Ganó 6-1 6-1 · ayer', streak: 4)),
    const Friend(_a, FriendActivity(lastMatch: 'Perdió 1-6 1-6 · ayer')),
  ];
  final List<FriendRequest> _in = [
    FriendRequest('r1', const PlayerSummary(id: 'raul', name: 'Raúl D.', username: 'ra.l.d', elo: 1360, level: 'Intermedio'), DateTime.now()),
  ];
  final List<FriendRequest> _out = [];
  final _pool = const [
    PlayerSummary(id: 'paula', name: 'Paula A.', username: 'paula.a', elo: 1520, level: 'Avanzado', mutualFriends: 5, city: 'Madrid'),
    PlayerSummary(id: 'dani', name: 'Dani R.', username: 'dani.r', elo: 1495, level: 'Intermedio alto', mutualFriends: 4, city: 'Madrid'),
  ];

  RelationState _rel(String id) => _friends.any((f) => f.player.id == id)
      ? RelationState.friend
      : _out.any((r) => r.player.id == id)
          ? RelationState.requestSent
          : _in.any((r) => r.player.id == id) ? RelationState.requestReceived : RelationState.none;

  @override
  Future<List<Friend>> friends() async => List.of(_friends)..sort((a, b) => b.player.elo.compareTo(a.player.elo));
  @override
  Future<FriendRequests> requests() async => FriendRequests(incoming: List.of(_in), outgoing: List.of(_out));
  @override
  Future<List<SearchHit>> search(String q) async {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return [];
    return [..._pool, _a, _b]
        .where((p) => p.id != meId && (p.name.toLowerCase().contains(s) || p.username.toLowerCase().contains(s)))
        .map((p) => SearchHit(p, _rel(p.id))).toList();
  }
  @override
  Future<List<SearchHit>> suggestions() async => _pool.where((p) => _rel(p.id) == RelationState.none)
      .map((p) => SearchHit(p, RelationState.none, reason: '${p.mutualFriends} amigos en común')).toList();
  @override
  Future<void> sendRequest(String id) async {
    if (id == meId || _rel(id) != RelationState.none) return; // evita duplicados y auto-solicitud
    final p = _pool.firstWhere((x) => x.id == id);
    _out.add(FriendRequest('o_$id', p, DateTime.now()));
  }
  @override
  Future<void> cancelRequest(String requestId) async => _out.removeWhere((r) => r.id == requestId);
  @override
  Future<void> respondRequest(String requestId, {required bool accept}) async {
    final r = _in.firstWhere((x) => x.id == requestId);
    _in.remove(r);
    if (accept) _friends.add(Friend(r.player, const FriendActivity()));
  }
  @override
  Future<void> removeFriend(String userId) async => _friends.removeWhere((f) => f.player.id == userId);
}
