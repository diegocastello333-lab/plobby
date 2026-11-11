import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../matches/data/supabase_lifecycle_repository.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../domain/league_models.dart';
import 'league_repository.dart';

/// Ligas contra Supabase. Requiere la migración `20261120_leagues_profile.sql`.
class SupabaseLeagueRepository implements LeagueRepository {
  SupabaseLeagueRepository(this._db) : _matches = SupabaseLifecycleRepository(_db);
  final SupabaseClient _db;
  final SupabaseLifecycleRepository _matches;
  String get _uid => _db.auth.currentUser!.id;

  static const _codes = ['invite_code_required', 'invalid_invite_code', 'league_full', 'league_ended', 'not_league_manager', 'organizer_cannot_leave',
      'cannot_remove_organizer', 'invalid_league_name', 'invalid_league_dates', 'max_below_members', 'invalid_league_players', 'request_not_pending'];

  Future<T> _guard<T>(Future<T> Function() f) async {
    try { return await f(); }
    on PostgrestException catch (e) { throw LeagueException(_codes.firstWhere(e.message.contains, orElse: () => 'server')); }
    on LeagueException { rethrow; }
    catch (_) { throw LeagueException('network'); }
  }

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String);
  static int _int(dynamic v, [int d = 0]) => (v as num?)?.toInt() ?? d;

  @override
  Future<List<LeagueSummary>> myLeagues() => _guard(() async => [
        for (final r in (await _db.rpc('my_leagues') as List).cast<Map<String, dynamic>>())
          LeagueSummary(id: r['league_id'] as String, name: r['name'] as String, visibility: LeagueVisibilityX.fromDb(r['visibility'] as String?),
              cover: (r['cover'] ?? 'lines') as String, location: (r['location'] ?? '') as String, season: (r['season'] ?? '01') as String,
              startsOn: _date(r['starts_on']), endsOn: _date(r['ends_on']), status: LeagueStatusX.fromDb(r['status'] as String?),
              role: LeagueRoleX.fromDb(r['role'] as String?) ?? LeagueRole.player, members: _int(r['members'], 1), myRank: (r['my_rank'] as num?)?.toInt(),
              myPoints: _int(r['my_points']), myPlayed: _int(r['my_played']), myWins: _int(r['my_wins']), matchesDone: _int(r['matches_done']),
              matchesTotal: _int(r['matches_total']), organizerName: (r['organizer_name'] ?? '') as String),
      ]);

  @override
  Future<List<DiscoverLeague>> discover(String query) => _guard(() async => [
        for (final r in (await _db.rpc('discover_leagues', params: {'p_query': query}) as List).cast<Map<String, dynamic>>())
          DiscoverLeague(id: r['league_id'] as String, name: r['name'] as String, visibility: LeagueVisibilityX.fromDb(r['visibility'] as String?),
              cover: (r['cover'] ?? 'lines') as String, location: (r['location'] ?? '') as String, levelMin: (r['level_min'] ?? '') as String,
              levelMax: (r['level_max'] ?? '') as String, season: (r['season'] ?? '01') as String, startsOn: _date(r['starts_on']), endsOn: _date(r['ends_on']),
              status: LeagueStatusX.fromDb(r['status'] as String?), organizerName: (r['organizer_name'] ?? '') as String, members: _int(r['members']),
              maxPlayers: _int(r['max_players'], 16), friendsIn: _int(r['friends_in']), friendIds: [for (final x in (r['friend_ids'] as List? ?? const [])) x as String],
              invited: r['invited'] == true, requestPending: r['request_pending'] == true),
      ]);

  @override
  Future<LeagueDetail> league(String id) => _guard(() async {
        // `invite_code` no es legible con select() (concesión por columnas): se pide aparte con league_invite_code().
        final r = await _db.from('leagues').select('id, name, description, visibility, cover, location, level_min, level_max, season, starts_on, ends_on, ended_at, '
            'min_players, max_players, matches_per_player, points_win, points_loss, bonus_enabled, challenges_enabled, created_by, '
            'organizer:profiles!leagues_created_by_fkey(display_name)').eq('id', id).single();
        final role = await _db.rpc('league_role', params: {'p_league': id}) as String?;
        final starts = _date(r['starts_on']);
        return LeagueDetail(
          id: r['id'] as String, name: r['name'] as String, description: (r['description'] ?? '') as String, visibility: LeagueVisibilityX.fromDb(r['visibility'] as String?),
          cover: (r['cover'] ?? 'lines') as String, location: (r['location'] ?? '') as String, levelMin: (r['level_min'] ?? '') as String, levelMax: (r['level_max'] ?? '') as String,
          season: (r['season'] ?? '01') as String, startsOn: starts, endsOn: _date(r['ends_on']),
          status: r['ended_at'] != null ? LeagueStatus.ended : (starts != null && starts.isAfter(DateTime.now()) ? LeagueStatus.open : LeagueStatus.running),
          minPlayers: _int(r['min_players'], 2), maxPlayers: _int(r['max_players'], 16), matchesPerPlayer: _int(r['matches_per_player'], 10),
          rules: LeagueRules(pointsWin: _int(r['points_win'], 3), pointsLoss: _int(r['points_loss'], 1), bonusEnabled: r['bonus_enabled'] != false),
          challengesEnabled: r['challenges_enabled'] != false, createdBy: r['created_by'] as String?,
          organizerName: ((r['organizer'] as Map?)?['display_name'] ?? '') as String, myRole: LeagueRoleX.fromDb(role),
        );
      });

  @override
  Future<List<StandingRow>> standings(String id) => _guard(() async => [
        for (final r in (await _db.rpc('league_standings', params: {'p_league': id}) as List).cast<Map<String, dynamic>>())
          StandingRow(userId: r['user_id'] as String, name: (r['display_name'] ?? '') as String, username: (r['username'] ?? '') as String,
              avatarUrl: r['avatar_url'] as String?, avatarId: r['avatar_id'] as String?, elo: _int(r['elo'], 1200),
              role: LeagueRoleX.fromDb(r['role'] as String?) ?? LeagueRole.player, played: _int(r['played']), wins: _int(r['wins']),
              bonus: _int(r['bonus']), points: _int(r['points']), rank: _int(r['rank'], 1)),
      ]);

  @override
  Future<List<LifecycleMatch>> matches(String id) => _guard(() async {
        final rows = await _db.from('matches').select(SupabaseLifecycleRepository.selectColumns)
            .eq('league_id', id).eq('match_type', 'league').neq('status', 'cancelled').order('scheduled_at', ascending: false).limit(100);
        return [for (final r in rows) _matches.fromRow(r)];
      });

  @override
  Future<List<JoinRequest>> joinRequests(String id) => _guard(() async => [
        for (final r in await _db.from('league_join_requests')
            .select('id, user_id, message, created_at, user:profiles!league_join_requests_user_fk(display_name, avatar_url)')
            .eq('league_id', id).eq('status', 'pending').order('created_at'))
          JoinRequest(id: r['id'] as String, userId: r['user_id'] as String, name: ((r['user'] as Map?)?['display_name'] ?? '') as String,
              avatarUrl: (r['user'] as Map?)?['avatar_url'] as String?, message: (r['message'] ?? '') as String, createdAt: DateTime.parse(r['created_at'] as String).toLocal()),
      ]);

  @override
  Future<String?> inviteCode(String id) => _guard(() async => await _db.rpc('league_invite_code', params: {'p_league': id}) as String?);

  String _d(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Future<({String id, String code})> create(LeagueDraft d) => _guard(() async {
        final r = await _db.rpc('create_league', params: {
          'p_name': d.name, 'p_description': d.description, 'p_visibility': d.visibility.name, 'p_cover': d.cover, 'p_location': d.location,
          'p_level_min': d.levelMin, 'p_level_max': d.levelMax, 'p_starts_on': _d(d.startsOn), 'p_ends_on': _d(d.endsOn),
          'p_min_players': d.minPlayers, 'p_max_players': d.maxPlayers, 'p_format': d.format, 'p_matches_per_player': d.matchesPerPlayer,
          'p_points_win': d.pointsWin, 'p_bonus': d.bonus, 'p_challenges': d.challenges, 'p_invited': d.invited,
        }) as Map<String, dynamic>;
        return (id: r['id'] as String, code: r['invite_code'] as String);
      });

  @override
  Future<JoinOutcome> join(String id, {String? code, String? message}) => _guard(() async {
        final r = await _db.rpc('join_league', params: {'p_league': id, 'p_code': code, 'p_message': message}) as String;
        return switch (r) { 'requested' => JoinOutcome.requested, 'already_member' => JoinOutcome.alreadyMember, _ => JoinOutcome.joined };
      });

  @override
  Future<String> joinByCode(String code) => _guard(() async => await _db.rpc('join_league_by_code', params: {'p_code': code}) as String);

  @override
  Future<void> respondRequest(String requestId, {required bool accept}) => _guard(() => _db.rpc('respond_join_request', params: {'p_request': requestId, 'p_accept': accept}));

  @override
  Future<void> leave(String id) => _guard(() => _db.rpc('leave_league', params: {'p_league': id}));

  @override
  Future<void> removeMember(String id, String userId) => _guard(() => _db.rpc('remove_league_member', params: {'p_league': id, 'p_user': userId}));

  @override
  Future<int> invite(String id, List<String> userIds) => _guard(() async => await _db.rpc('invite_to_league', params: {'p_league': id, 'p_user_ids': userIds}) as int);

  @override
  Future<void> update(String id, Map<String, Object?> patch) => _guard(() => _db.rpc('update_league', params: {'p_league': id, 'p_patch': patch}));

  /// Realtime: altas/bajas de miembros, solicitudes y cambios de partidos de ESTA liga (la RLS filtra también el canal).
  @override
  Stream<void> watch(String id) {
    late final RealtimeChannel ch;
    final ctl = StreamController<void>(onCancel: () => _db.removeChannel(ch));
    PostgresChangeFilter f(String col) => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: col, value: id);
    void ping(PostgresChangePayload _) { if (!ctl.isClosed) ctl.add(null); }
    ch = _db.channel('league:$id:$_uid')
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'league_members', filter: f('league_id'), callback: ping)
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'league_join_requests', filter: f('league_id'), callback: ping)
      ..onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'matches', filter: f('league_id'), callback: ping)
      ..subscribe();
    return ctl.stream;
  }
}
