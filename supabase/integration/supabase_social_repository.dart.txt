import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/social_models.dart';
import 'social_repository.dart';

/// Integración Supabase (NO verificada contra una base real). Usa solo la anon key + sesión del usuario;
/// la service role key NUNCA está en la app. Las vistas/RPCs están en `supabase/migrations/20261112_home_social.sql`.
class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._db);
  final SupabaseClient _db;
  @override
  String get meId => _db.auth.currentUser!.id;

  PlayerSummary _player(Map<String, dynamic> j) => PlayerSummary(
        id: j['user_id'] as String,
        name: j['display_name'] as String,
        username: j['username'] as String,
        avatarUrl: j['avatar_url'] as String?,
        elo: (j['elo'] as num).toInt(),
        level: j['level'] as String,
        city: j['city'] as String?,
        club: j['club'] as String?,
        mutualFriends: (j['mutual_friends'] as num?)?.toInt() ?? 0,
      );

  @override
  Future<List<Friend>> friends() async {
    final rows = await _db.from('v_my_friends').select().order('elo', ascending: false);
    return [
      for (final r in rows as List)
        Friend(_player(r as Map<String, dynamic>),
            FriendActivity(lastMatch: r['last_match_label'] as String?, streak: (r['streak'] as num?)?.toInt() ?? 0)),
    ];
  }

  @override
  Future<FriendRequests> requests() async {
    final rows = await _db.from('v_my_friend_requests').select();
    FriendRequest map(Map<String, dynamic> r) =>
        FriendRequest(r['request_id'] as String, _player(r), DateTime.parse(r['created_at'] as String));
    final all = (rows as List).cast<Map<String, dynamic>>();
    return FriendRequests(
      incoming: all.where((r) => r['direction'] == 'incoming').map(map).toList(),
      outgoing: all.where((r) => r['direction'] == 'outgoing').map(map).toList(),
    );
  }

  @override
  Future<List<SearchHit>> search(String q) async {
    final rows = await _db.rpc('search_players', params: {'q': q});
    return [for (final r in rows as List) SearchHit(_player(r), RelationState.values.byName(r['relation'] as String))];
  }

  @override
  Future<List<SearchHit>> suggestions() async {
    final rows = await _db.rpc('suggest_friends');
    return [for (final r in rows as List) SearchHit(_player(r), RelationState.none, reason: r['reason'] as String?)];
  }

  @override
  Future<void> sendRequest(String userId) => _db.rpc('send_friend_request', params: {'target': userId});
  @override
  Future<void> cancelRequest(String requestId) => _db.rpc('cancel_friend_request', params: {'req': requestId});
  @override
  Future<void> respondRequest(String requestId, {required bool accept}) =>
      _db.rpc('respond_friend_request', params: {'req': requestId, 'accept': accept});
  @override
  Future<void> removeFriend(String userId) => _db.rpc('remove_friend', params: {'target': userId});
}
