import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/shared_realtime.dart';
import '../../../core/supabase/user_channel.dart';
import '../domain/social_models.dart';
import 'social_repository.dart';

/// Datos sociales contra Supabase (verificado con la base real y dos cuentas, 12 nov 2026). Usa solo la clave publicable
/// + sesión del usuario. Vistas/RPCs en `supabase/migrations/20261112_home_social.sql`.
class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._db, {UserChannel? channel}) : _channel = channel;
  final UserChannel? _channel;
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

  @override
  Future<int> friendCount(String userId) async => ((await _db.rpc('friend_count', params: {'p_user': userId})) as num?)?.toInt() ?? 0;

  /// Realtime en dos canales (uno por tipo de autorización):
  ///  - postgres_changes de mis solicitudes (enviadas y recibidas) y mis notificaciones; la RLS solo deja pasar mis filas;
  ///  - canal privado del usuario ([UserChannel], `user:<uid>`): el trigger de `friendships` avisa a LOS DOS usuarios
  ///    de altas y bajas de amistad (los DELETE de postgres_changes no se pueden filtrar sin exponer los de otros).
  /// También emite al recuperar la conexión, para recargar lo que pasó durante el corte.
  late final _rows = SharedRealtime<SocialChange>(_db, 'social:$meId', (ch, emit) {
    void req(PostgresChangePayload _) => emit(SocialChange.requests);
    ch
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'friend_requests',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'receiver_id', value: meId), callback: req)
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'friend_requests',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'sender_id', value: meId), callback: req)
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'recipient_user_id', value: meId),
          callback: (_) => emit(SocialChange.notifications));
  });

  /// Foto, avatar o nombre de alguien que aparece en mis pantallas (trigger de `profiles` → canal del usuario).
  @override
  Stream<ProfileEvent> profileUpdates() => _channel?.events.where((e) => e is ProfileEvent).cast<ProfileEvent>() ?? const Stream.empty();

  @override
  Stream<SocialChange> changes() {
    final subs = <StreamSubscription<Object?>>[];
    late final StreamController<SocialChange> out;
    void add(SocialChange c) { if (!out.isClosed) out.add(c); }
    out = StreamController<SocialChange>.broadcast(
      onListen: () {
        subs
          ..add(_rows.events.listen(add))
          ..add(_rows.resyncs.listen((_) => add(SocialChange.resync)));
        final uc = _channel;
        if (uc != null) {
          subs
            ..add(uc.events.where((e) => e is FriendshipEvent).listen((_) => add(SocialChange.friendships)))
            ..add(uc.resyncs.listen((_) => add(SocialChange.resync)));
        }
      },
      onCancel: () { for (final s in subs) { s.cancel(); } subs.clear(); },
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
