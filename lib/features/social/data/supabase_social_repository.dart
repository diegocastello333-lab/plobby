import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/social_models.dart';
import 'social_repository.dart';

/// Datos sociales contra Supabase (verificado con la base real y dos cuentas, 12 nov 2026). Usa solo la clave publicable
/// + sesión del usuario. Vistas/RPCs en `supabase/migrations/20261112_home_social.sql`.
class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._db);
  final SupabaseClient _db;
  @override
  String get meId => _db.auth.currentUser!.id;

  /// Fila de vista/RPC → [PlayerSummary]. La RLS de `player_ratings` solo deja ver el ELO propio y el de los amigos:
  /// en una solicitud de alguien que aún no es amigo `elo` llega null. Antes `(j['elo'] as num)` lanzaba y TODA la
  /// lista de solicitudes fallaba (el destinatario no veía ni podía aceptar la solicitud). 0 = ELO no visible.
  PlayerSummary _player(Map<String, dynamic> j) => playerSummaryFromRow(j);

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

  /// Realtime: solicitudes enviadas o recibidas por mí y mis notificaciones (las dos tablas están en la publicación
  /// `supabase_realtime`; la RLS de cada una solo deja pasar mis filas).
  @override
  Stream<void> changes() {
    late final StreamController<void> out;
    RealtimeChannel? ch;
    out = StreamController<void>.broadcast(
      onListen: () {
        final me = meId;
        void ping(PostgresChangePayload _) { if (!out.isClosed) out.add(null); }
        ch = _db.channel('social:$me')
          ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'friend_requests',
              filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'receiver_id', value: me), callback: ping)
          ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'friend_requests',
              filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'sender_id', value: me), callback: ping)
          ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'notifications',
              filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'recipient_user_id', value: me), callback: ping)
          ..subscribe();
      },
      onCancel: () async { final c = ch; ch = null; if (c != null) await _db.removeChannel(c); },
    );
    return out.stream;
  }
}

/// Ver [SupabaseSocialRepository._player]. Pública para los tests (función pura).
PlayerSummary playerSummaryFromRow(Map<String, dynamic> j) => PlayerSummary(
        id: j['user_id'] as String,
        name: (j['display_name'] as String?) ?? '',
        username: (j['username'] as String?) ?? '',
        avatarUrl: j['avatar_url'] as String?,
        elo: (j['elo'] as num?)?.toInt() ?? 0,
        level: (j['level'] as String?) ?? '',
        city: j['city'] as String?,
        club: j['club'] as String?,
        mutualFriends: (j['mutual_friends'] as num?)?.toInt() ?? 0,
      );
