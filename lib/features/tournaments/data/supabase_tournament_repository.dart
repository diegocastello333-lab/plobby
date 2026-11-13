import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/user_channel.dart';
import '../domain/tournament_models.dart';
import 'tournament_repository.dart';

/// Torneos en Supabase. Lecturas con RLS (solo organizadores y jugadores del torneo); escrituras SOLO por RPC
/// (`create_tournament`, `record_tournament_result`…), que validan y mantienen el cuadro coherente en una transacción.
class SupabaseTournamentRepository implements TournamentRepository {
  SupabaseTournamentRepository(this._db, {UserChannel? channel}) : _channel = channel;
  final SupabaseClient _db;
  final UserChannel? _channel;
  @override
  String get meId => _db.auth.currentUser!.id;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      throw TournamentException.fromServer(e.message);
    } on SocketException {
      throw TournamentException('network');
    } on TimeoutException {
      throw TournamentException('network');
    }
  }

  static DateTime? _date(Object? s) => s == null ? null : DateTime.parse(s as String);

  static TPlayer _player(Map<String, dynamic>? p) => TPlayer(
      id: (p?['id'] ?? '') as String, name: (p?['display_name'] ?? '') as String, username: (p?['username'] ?? '') as String, avatarUrl: p?['avatar_url'] as String?);

  static List<(int, int)>? _sets(Object? j) => j is List ? [for (final s in j.cast<List>()) ((s[0] as num).toInt(), (s[1] as num).toInt())] : null;

  /// Fila de `tournament_matches` → [TMatch]. Pública para los tests.
  static TMatch matchFrom(Map<String, dynamic> r) => TMatch(
        id: r['id'] as String, stage: r['stage'] == 'group' ? MatchStage.group : MatchStage.knockout, groupLabel: r['group_label'] as String?,
        round: (r['round'] as num).toInt(), position: (r['position'] as num).toInt(), team1Id: r['team1_id'] as String?, team2Id: r['team2_id'] as String?,
        slot1Source: r['slot1_source'] as String?, slot2Source: r['slot2_source'] as String?, nextMatchId: r['next_match_id'] as String?,
        nextSlot: (r['next_slot'] as num?)?.toInt(), status: TMatchStatus.fromDb(r['status'] as String?), sets: _sets(r['sets']),
        winnerTeamId: r['winner_team_id'] as String?, version: ((r['version'] ?? 0) as num).toInt(),
      );

  static Tournament tournamentFrom(Map<String, dynamic> r, {String organizer = ''}) => Tournament(
        id: r['id'] as String, name: (r['name'] ?? '') as String, description: r['description'] as String?, startsOn: _date(r['starts_on'])!,
        endsOn: _date(r['ends_on']), timeSlot: r['time_slot'] as String?, location: r['location'] as String?, coverUrl: r['cover_url'] as String?,
        maxTeams: ((r['max_teams'] ?? 2) as num).toInt(), format: TournamentFormat.fromDb(r['format'] as String?),
        groupsCount: ((r['groups_count'] ?? 1) as num).toInt(), qualifiersPerGroup: ((r['qualifiers_per_group'] ?? 0) as num).toInt(),
        pointsWin: ((r['points_win'] ?? 3) as num).toInt(), pointsLoss: ((r['points_loss'] ?? 0) as num).toInt(),
        status: TournamentStatus.fromDb(r['status'] as String?), championTeamId: r['champion_team_id'] as String?,
        createdBy: (r['created_by'] ?? '') as String, organizerName: organizer,
      );

  /// Fila de `my_tournaments` → [TournamentSummary]. Pública para los tests.
  static TournamentSummary summaryFrom(Map<String, dynamic> r) {
    final nm = r['next_match'] as Map<String, dynamic>?;
    NextMatchInfo? next;
    if (nm != null) {
      final opp = nm['opponent'] as Map<String, dynamic>?;
      final rounds = (r['knockout_rounds'] as num?)?.toInt() ?? 0;
      final label = nm['stage'] == 'group'
          ? (r['format'] == 'round_robin' ? 'Jornada ${nm['round']}' : 'Grupo ${nm['group_label']}')
          : roundName((nm['round'] as num).toInt(), rounds);
      next = NextMatchInfo(label: label, opponent: opp == null ? 'Por decidir' : '${opp['p1']} / ${opp['p2']}', live: nm['status'] == 'live');
    }
    return TournamentSummary(
      id: r['id'] as String, name: (r['name'] ?? '') as String, startsOn: _date(r['starts_on'])!, endsOn: _date(r['ends_on']),
      timeSlot: r['time_slot'] as String?, location: r['location'] as String?, coverUrl: r['cover_url'] as String?,
      format: TournamentFormat.fromDb(r['format'] as String?), status: TournamentStatus.fromDb(r['status'] as String?),
      teamsCount: ((r['teams_count'] ?? 0) as num).toInt(), maxTeams: ((r['max_teams'] ?? 0) as num).toInt(), isAdmin: r['is_admin'] == true,
      knockoutRounds: (r['knockout_rounds'] as num?)?.toInt(), currentRound: (r['current_round'] as num?)?.toInt(),
      groupPending: ((r['group_pending'] ?? 0) as num).toInt(), championTeamId: r['champion_team_id'] as String?, myTeamId: r['my_team_id'] as String?,
      nextMatch: next,
    );
  }

  @override
  Future<List<TournamentSummary>> myTournaments() => _guard(() async {
        final rows = await _db.rpc('my_tournaments') as List;
        return [for (final r in rows) summaryFrom(r as Map<String, dynamic>)];
      });

  @override
  Future<TournamentDetail> detail(String id) => _guard(() async {
        final res = await Future.wait<dynamic>([
          _db.from('tournaments').select().eq('id', id).maybeSingle(),
          _db.from('tournament_teams').select('id, seed, group_label, '
              'p1:profiles!tournament_teams_player1_id_fkey(id, display_name, username, avatar_url), '
              'p2:profiles!tournament_teams_player2_id_fkey(id, display_name, username, avatar_url)').eq('tournament_id', id).order('seed'),
          _db.from('tournament_matches').select().eq('tournament_id', id),
          _db.rpc('tournament_standings', params: {'p_t': id}),
          _db.from('tournament_admins').select('user_id, role, profiles(display_name)').eq('tournament_id', id),
        ]);
        final t = res[0] as Map<String, dynamic>?;
        if (t == null) throw TournamentException('not_allowed');
        final admins = (res[4] as List).cast<Map<String, dynamic>>();
        final owner = admins.where((a) => a['role'] == 'owner').firstOrNull;
        return TournamentDetail(
          tournament: tournamentFrom(t, organizer: ((owner?['profiles'] as Map?)?['display_name'] ?? '') as String),
          teams: [
            for (final r in (res[1] as List).cast<Map<String, dynamic>>())
              TTeam(id: r['id'] as String, seed: (r['seed'] as num).toInt(), groupLabel: r['group_label'] as String?,
                  p1: _player(r['p1'] as Map<String, dynamic>?), p2: _player(r['p2'] as Map<String, dynamic>?)),
          ],
          matches: [for (final r in (res[2] as List).cast<Map<String, dynamic>>()) matchFrom(r)],
          standings: [
            for (final r in (res[3] as List).cast<Map<String, dynamic>>())
              TStanding(groupLabel: r['group_label'] as String, teamId: r['team_id'] as String, seed: (r['seed'] as num).toInt(),
                  played: (r['played'] as num).toInt(), won: (r['won'] as num).toInt(), lost: (r['lost'] as num).toInt(),
                  setsFor: (r['sets_for'] as num).toInt(), setsAgainst: (r['sets_against'] as num).toInt(),
                  gamesFor: (r['games_for'] as num).toInt(), gamesAgainst: (r['games_against'] as num).toInt(),
                  points: (r['points'] as num).toInt(), pos: (r['pos'] as num).toInt()),
          ],
          isAdmin: admins.any((a) => a['user_id'] == meId),
          meId: meId,
        );
      });

  @override
  Future<String> uploadCover(List<int> jpeg) => _guard(() async {
        // Carpeta propia del bucket público `avatars` (su política solo deja escribir en <uid>/).
        final path = '$meId/tcover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _db.storage.from('avatars').uploadBinary(path, Uint8List.fromList(jpeg), fileOptions: const FileOptions(contentType: 'image/jpeg'));
        return _db.storage.from('avatars').getPublicUrl(path);
      });

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static List<List<String>> _teams(List<(TPlayer, TPlayer)> t) => [for (final x in t) [x.$1.id, x.$2.id]];

  @override
  Future<String> create(TournamentDraft d, {String? coverUrl}) => _guard(() async => (await _db.rpc('create_tournament', params: {
        'p': {
          'name': d.name.trim(), 'description': d.description.trim(), 'starts_on': _day(d.startsOn!), 'ends_on': d.endsOn == null ? '' : _day(d.endsOn!),
          'time_slot': d.timeSlot.trim(), 'location': d.location.trim(), 'cover_url': coverUrl ?? '', 'max_teams': d.maxTeams, 'format': d.format.db,
          'groups_count': d.format == TournamentFormat.groupsKnockout ? d.groupsCount : 1,
          'qualifiers_per_group': d.format == TournamentFormat.groupsKnockout ? d.qualifiersPerGroup : 0,
          'teams': _teams(d.teams),
        },
      })) as String);

  @override
  Future<void> updateInfo(String id, Map<String, dynamic> patch) =>
      _guard(() => _db.rpc('update_tournament_info', params: {'p_t': id, 'p': {for (final e in patch.entries) e.key: e.value is DateTime ? _day(e.value as DateTime) : e.value}}));

  @override
  Future<void> replaceTeams(String id, List<(TPlayer, TPlayer)> teams, {TournamentFormat? format, int? groupsCount, int? qualifiersPerGroup}) =>
      _guard(() => _db.rpc('replace_tournament_teams', params: {'p_t': id, 'p': {
            'teams': _teams(teams), if (format != null) 'format': format.db, if (groupsCount != null) 'groups_count': groupsCount,
            if (qualifiersPerGroup != null) 'qualifiers_per_group': qualifiersPerGroup}}));

  @override
  Future<void> recordResult(String matchId, List<(int, int)> sets, int version) => _guard(() =>
      _db.rpc('record_tournament_result', params: {'p_match': matchId, 'p_sets': [for (final s in sets) [s.$1, s.$2]], 'p_version': version}));

  @override
  Future<void> clearResult(String matchId, int version) => _guard(() => _db.rpc('clear_tournament_result', params: {'p_match': matchId, 'p_version': version}));

  @override
  Future<void> setLive(String matchId, bool live) => _guard(() => _db.rpc('set_tournament_match_live', params: {'p_match': matchId, 'p_live': live}));

  /// Ids de torneos que han cambiado; '*' tras recuperar la conexión (lo perdido durante el corte no se reenvía).
  @override
  Stream<String> changes() {
    final uc = _channel;
    if (uc == null) return const Stream.empty();
    late final StreamController<String> out;
    final subs = <StreamSubscription<Object?>>[];
    out = StreamController<String>.broadcast(
      onListen: () => subs
        ..add(uc.events.where((e) => e is TournamentEvent).listen((e) => out.add((e as TournamentEvent).tournamentId)))
        ..add(uc.resyncs.listen((_) => out.add('*'))),
      onCancel: () { for (final s in subs) { s.cancel(); } subs.clear(); },
    );
    return out.stream;
  }
}
