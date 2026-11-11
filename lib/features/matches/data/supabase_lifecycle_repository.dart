// Plobby · Ciclo de vida del partido contra Supabase. Se activa en lib/core/supabase/supabase_bootstrap.dart.
// Requiere las migraciones 20261115_match_lifecycle.sql y 20261120_leagues_profile.sql.
// Ninguna operación calcula ELO/estadísticas en el cliente; todas las escrituras van por RPC (no hay INSERT/UPDATE directo).

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';
import 'lifecycle_repository.dart';

class SupabaseLifecycleRepository implements LifecycleRepository {
  SupabaseLifecycleRepository(this._c);
  final sb.SupabaseClient _c;
  String get _uid => _c.auth.currentUser!.id;

  @override
  Future<DateTime> serverTime() async => DateTime.parse((await _c.rpc('server_time')) as String);

  LifecycleException _map(Object e) {
    if (e is sb.PostgrestException) { for (final k in ['stale_version', 'only_captains_can_confirm', 'not_a_participant', 'league_rule_players_locked', 'league_rule_delete_locked', 'match_not_live', 'only_creator_can_edit', 'only_creator_can_delete']) { if (e.message.contains(k)) return LifecycleException(k); } return LifecycleException('server'); }
    return LifecycleException('network');
  }

  /// Carga un partido con jugadores, resultado vigente, aceptaciones y eventos (RLS: solo si participas).
  Future<LifecycleMatch?> _load(String id) async {
    final m = await _c.from('matches').select('$_cols, match_events(actor_id, kind, payload, created_at)').eq('id', id).maybeSingle();
    return m == null ? null : _fromRow(m);
  }

  static const _player = 'match_players(team, is_captain, user_id, elo_delta, profiles(display_name, avatar_url, avatar_id, self_declared_level, player_ratings(elo)))';
  static const _cols = '*, leagues(name), $_player, match_result_versions(version, sets), match_result_acceptances(user_id, team, version, decision, reason)';
  /// Columnas y mapeo reutilizables (p. ej. la pestaña «Partidos» de una liga lee los mismos datos).
  static const selectColumns = _cols;
  LifecycleMatch fromRow(Map<String, dynamic> r) => _fromRow(r);

  /// Ids de mis partidos. Se consultan aparte: filtrar el embed con `match_players!inner` + `eq('match_players.user_id')`
  /// filtraría también los jugadores devueltos y el partido llegaría solo con el usuario actual.
  Future<List<String>> _myMatchIds() async =>
      [for (final r in await _c.from('match_players').select('match_id').eq('user_id', _uid)) r['match_id'] as String];

  static int? _elo(dynamic profile) {
    final pr = profile is Map ? profile['player_ratings'] : null;
    final x = pr is List ? (pr.isEmpty ? null : pr.first) : pr;
    return x is Map ? (x['elo'] as num?)?.toInt() : null;
  }

  LifecycleMatch _fromRow(Map<String, dynamic> r) {
    final versions = (r['match_result_versions'] as List? ?? []).cast<Map<String, dynamic>>();
    final cur = versions.where((v) => v['version'] == r['result_version']).toList();
    List<SetScore> sets(dynamic j) => [for (final s in (j as List)) SetScore((s as List)[0] as int, s[1] as int)];
    return LifecycleMatch(
      id: r['id'] as String, type: r['match_type'] == 'league' ? MatchType.league : MatchType.friendly, leagueId: r['league_id'] as String?, leagueName: (r['leagues'] as Map?)?['name'] as String?,
      scheduledAt: DateTime.parse((r['scheduled_at'] ?? r['played_at'] ?? r['created_at']) as String).toLocal(), club: (r['club'] ?? '') as String, court: r['court'] as String?, createdBy: (r['created_by'] ?? '') as String,
      status: MatchStatusX.fromDb(r['status'] as String), startedAt: r['started_at'] == null ? null : DateTime.parse(r['started_at'] as String), endedAt: r['ended_at'] == null ? null : DateTime.parse(r['ended_at'] as String),
      durationSeconds: r['duration_seconds'] as int?, startedBy: r['started_by'] as String?, resultVersion: r['result_version'] as int,
      sets: cur.isEmpty ? const [] : sets(cur.first['sets']),
      players: [for (final p in (r['match_players'] as List).cast<Map<String, dynamic>>()) MatchPlayer(id: p['user_id'] as String, name: (p['profiles']?['display_name'] ?? '') as String, team: p['team'] as int, isCaptain: p['is_captain'] as bool,
          elo: _elo(p['profiles']) ?? 0, level: (p['profiles']?['self_declared_level'] ?? '') as String, avatarUrl: p['profiles']?['avatar_url'] as String?, avatarId: p['profiles']?['avatar_id'] as String?)],
      eloDelta: {for (final p in (r['match_players'] as List).cast<Map<String, dynamic>>()) if (p['elo_delta'] != null) p['user_id'] as String: (p['elo_delta'] as num).toInt()},
      acceptances: [for (final a in (r['match_result_acceptances'] as List? ?? []).cast<Map<String, dynamic>>()) Acceptance(userId: a['user_id'] as String, team: a['team'] as int, version: a['version'] as int, accepted: a['decision'] == 'accepted', reason: a['reason'] as String?)],
      events: [for (final e in (r['match_events'] as List? ?? []).cast<Map<String, dynamic>>()) MatchEvent(actorId: e['actor_id'] as String?, kind: e['kind'] as String, text: e['kind'] as String, at: DateTime.parse(e['created_at'] as String))],
    );
  }

  /// Realtime: cualquier cambio en `matches` / aceptaciones / versiones vuelve a pedir el partido (RLS filtra por participante).
  @override
  Stream<LifecycleMatch?> watchMatch(String id) {
    final ctl = StreamController<LifecycleMatch?>();
    Future<void> push() async { try { ctl.add(await _load(id)); } catch (e) { ctl.addError(_map(e)); } }
    final ch = _c.channel('match:$id')
      ..onPostgresChanges(event: sb.PostgresChangeEvent.all, schema: 'public', table: 'matches', filter: sb.PostgresChangeFilter(type: sb.PostgresChangeFilterType.eq, column: 'id', value: id), callback: (_) => push())
      ..onPostgresChanges(event: sb.PostgresChangeEvent.all, schema: 'public', table: 'match_result_acceptances', filter: sb.PostgresChangeFilter(type: sb.PostgresChangeFilterType.eq, column: 'match_id', value: id), callback: (_) => push())
      ..onPostgresChanges(event: sb.PostgresChangeEvent.insert, schema: 'public', table: 'match_result_versions', filter: sb.PostgresChangeFilter(type: sb.PostgresChangeFilterType.eq, column: 'match_id', value: id), callback: (_) => push())
      ..subscribe();
    push();
    ctl.onCancel = () { _c.removeChannel(ch); ctl.close(); };
    return ctl.stream;
  }

  @override
  Stream<List<LifecycleMatch>> watchUpcoming() {
    final ctl = StreamController<List<LifecycleMatch>>();
    Future<void> push() async {
      try {
        final ids = await _myMatchIds();
        if (ids.isEmpty) { ctl.add(const []); return; }
        final rows = await _c.from('matches').select(_cols)
            .inFilter('id', ids).inFilter('status', ['scheduled', 'live', 'pending_result', 'pending_confirmation', 'disputed']).order('scheduled_at');
        ctl.add([for (final r in rows) _fromRow(r)]);
      } catch (e) { ctl.addError(_map(e)); }
    }
    final ch = _c.channel('upcoming:$_uid')..onPostgresChanges(event: sb.PostgresChangeEvent.all, schema: 'public', table: 'matches', callback: (_) => push())..subscribe();
    push();
    ctl.onCancel = () { _c.removeChannel(ch); ctl.close(); };
    return ctl.stream;
  }

  @override
  Future<StartResult> start(String id) async {
    try { final r = await _c.rpc('start_match', params: {'p_match_id': id}) as Map<String, dynamic>; return StartResult(started: r['started'] as bool, startedAt: DateTime.parse(r['started_at'] as String), startedBy: r['started_by'] as String); }
    catch (e) { throw _map(e); }
  }
  @override
  Future<void> finish(String id) async { try { await _c.rpc('finish_match', params: {'p_match_id': id}); } catch (e) { throw _map(e); } }
  @override
  Future<int> submitResult(String id, List<SetScore> sets) async {
    try { return (await _c.rpc('submit_result', params: {'p_match_id': id, 'p_sets': [for (final s in sets) [s.a, s.b]]})) as int; } catch (e) { throw _map(e); }
  }
  @override
  Future<MatchStatus> respond(String id, int version, {required bool accept, String? reason}) async {
    try { final r = await _c.rpc('respond_result', params: {'p_match_id': id, 'p_version': version, 'p_accept': accept, 'p_reason': reason}) as Map<String, dynamic>; return MatchStatusX.fromDb(r['status'] as String); } catch (e) { throw _map(e); }
  }
  @override
  Future<void> update(String id, EditMatch e) async {
    try { await _c.rpc('update_match', params: {'p_match_id': id, 'p_scheduled_at': e.scheduledAt.toUtc().toIso8601String(), 'p_club': e.club, 'p_court': e.court, 'p_players': [for (final p in e.players) {'user_id': p.id, 'team': p.team, 'captain': p.isCaptain}]}); }
    catch (x) { throw _map(x); }
  }
  @override
  Future<void> cancel(String id) async { try { await _c.rpc('cancel_match', params: {'p_match_id': id}); } catch (e) { throw _map(e); } }
  /// Partidos del usuario FINALIZADOS Y CONFIRMADOS (selector de «compartir resultado» en mensajes). Más recientes primero.
  @override
  Future<List<LifecycleMatch>> confirmedMatches() async {
    try {
      final ids = await _myMatchIds();
      if (ids.isEmpty) return const [];
      final rows = await _c.from('matches').select(_cols).inFilter('id', ids).eq('status', 'confirmed').order('ended_at', ascending: false).limit(200);
      return [for (final r in rows) _fromRow(r)];
    } catch (e) { throw _map(e); }
  }

}
