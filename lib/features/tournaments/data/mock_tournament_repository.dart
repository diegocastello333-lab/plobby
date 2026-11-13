import 'dart:async';
import '../domain/tournament_engine.dart';
import '../domain/tournament_models.dart';
import 'tournament_repository.dart';

/// Torneos en memoria (modo demo y tests) con [TournamentEngine]: misma lógica que el servidor.
class MockTournamentRepository implements TournamentRepository {
  MockTournamentRepository({bool seed = true, DateTime Function()? now}) : _now = now ?? DateTime.now {
    if (seed) _seedDemo();
  }
  final DateTime Function() _now;
  final _engines = <String, TournamentEngine>{};
  final _admins = <String, Set<String>>{};
  final _ctl = StreamController<String>.broadcast();
  int _seq = 0;

  @override
  String get meId => 'me';

  static const demoPlayers = [
    TPlayer(id: 'me', name: 'Diego Castello', username: 'diego.c'), TPlayer(id: 'laura', name: 'Laura García', username: 'laura.g'),
    TPlayer(id: 'marcos', name: 'Marcos Ruiz', username: 'marcos.r'), TPlayer(id: 'raul', name: 'Raúl Díaz', username: 'ra.l.d'),
    TPlayer(id: 'lucia', name: 'Lucía Martín', username: 'lucia.m'), TPlayer(id: 'alvaro', name: 'Álvaro Pérez', username: 'alvaro.p'),
    TPlayer(id: 'carla', name: 'Carla Sanz', username: 'carla.s'), TPlayer(id: 'pablo', name: 'Pablo Soto', username: 'pablo.s'),
    TPlayer(id: 'sofia', name: 'Sofía Gil', username: 'sofia.g'), TPlayer(id: 'irene', name: 'Irene Vega', username: 'irene.v'),
    TPlayer(id: 'hugo', name: 'Hugo León', username: 'hugo.l'), TPlayer(id: 'nora', name: 'Nora Ríos', username: 'nora.r'),
  ];

  void _seedDemo() {
    final p = demoPlayers;
    final id = _create(TournamentDraft(name: 'Open de Otoño', description: 'Torneo social del club. Sets a 6 juegos, tie-break a 7.',
        startsOn: _now().subtract(const Duration(days: 1)), timeSlot: 'Sábado 10:00–14:00', location: 'Club La Moraleja', maxTeams: 8,
        teams: [(p[0], p[1]), (p[2], p[3]), (p[4], p[5]), (p[6], p[7]), (p[8], p[9]), (p[10], p[11])]));
    final e = _engines[id]!;
    // Primera ronda jugada: avanzan las parejas 1-2 y 4-5 (las mejores semillas pasaban directas).
    for (final m in e.matches.where((m) => m.round == 1 && m.ready).toList()) { e.record(m.id, const [(6, 3), (6, 4)], m.version); }
  }

  String _create(TournamentDraft d, {String? coverUrl}) {
    final id = 't${_seq++}';
    final t = Tournament(id: id, name: d.name.trim(), description: d.description.trim().isEmpty ? null : d.description.trim(), startsOn: d.startsOn!,
        endsOn: d.endsOn, timeSlot: d.timeSlot.trim().isEmpty ? null : d.timeSlot.trim(), location: d.location.trim().isEmpty ? null : d.location.trim(),
        coverUrl: coverUrl, maxTeams: d.maxTeams, format: d.format, groupsCount: d.format == TournamentFormat.groupsKnockout ? d.groupsCount : 1,
        qualifiersPerGroup: d.format == TournamentFormat.groupsKnockout ? d.qualifiersPerGroup : 0, createdBy: meId, organizerName: 'Diego Castello');
    final e = TournamentEngine(t, _teams(id, d.teams));
    e.generate();
    _engines[id] = e;
    _admins[id] = {meId};
    return id;
  }

  List<TTeam> _teams(String tid, List<(TPlayer, TPlayer)> teams) {
    final seen = <String>{};
    for (final (a, b) in teams) {
      if (a.id == b.id || !seen.add(a.id) || !seen.add(b.id)) throw TournamentException('duplicate_player');
    }
    return [for (var i = 0; i < teams.length; i++) TTeam(id: '$tid-k${i + 1}', seed: i + 1, p1: teams[i].$1, p2: teams[i].$2)];
  }

  TournamentEngine _e(String id) => _engines[id] ?? (throw TournamentException('not_allowed'));
  void _admin(String id) { if (!(_admins[id]?.contains(meId) ?? false)) throw TournamentException('not_tournament_admin'); }
  String _tidOf(String matchId) => _engines.entries.firstWhere((e) => e.value.matches.any((m) => m.id == matchId), orElse: () => throw TournamentException('match_not_found')).key;
  void _changed(String id) => _ctl.add(id);

  @override
  Future<List<TournamentSummary>> myTournaments() async => [
        for (final e in _engines.entries)
          if (_admins[e.key]!.contains(meId) || e.value.teams.any((t) => t.has(meId))) _summary(e.key, e.value),
      ]..sort((a, b) => (a.status == TournamentStatus.finished ? 1 : 0) - (b.status == TournamentStatus.finished ? 1 : 0));

  TournamentSummary _summary(String id, TournamentEngine e) {
    final d = _detail(id);
    final ko = d.knockout;
    final pending = ko.where((m) => m.status == TMatchStatus.pending || m.status == TMatchStatus.live);
    final myTeam = d.myTeam;
    final next = myTeam == null ? null : (d.matches.where((m) => (m.status == TMatchStatus.pending || m.status == TMatchStatus.live) && m.involves(myTeam.id)).toList()
          ..sort((a, b) => a.stage != b.stage ? (a.stage == MatchStage.group ? -1 : 1) : a.round.compareTo(b.round)))
        .firstOrNull;
    final opp = next == null ? null : d.team(next.team1Id == myTeam!.id ? next.team2Id : next.team1Id);
    return TournamentSummary(id: id, name: e.tournament.name, startsOn: e.tournament.startsOn, endsOn: e.tournament.endsOn, timeSlot: e.tournament.timeSlot,
        location: e.tournament.location, coverUrl: e.tournament.coverUrl, format: e.tournament.format, status: e.tournament.status,
        teamsCount: e.teams.length, maxTeams: e.tournament.maxTeams, isAdmin: _admins[id]!.contains(meId), knockoutRounds: ko.isEmpty ? null : d.knockoutRounds,
        currentRound: pending.isEmpty ? null : pending.map((m) => m.round).reduce((a, b) => a < b ? a : b),
        groupPending: d.matches.where((m) => m.stage == MatchStage.group && !m.finished).length, championTeamId: e.tournament.championTeamId,
        myTeamId: myTeam?.id, nextMatch: next == null ? null : NextMatchInfo(label: d.matchLabel(next), opponent: opp?.name ?? 'Por decidir', live: next.status == TMatchStatus.live));
  }

  TournamentDetail _detail(String id) {
    final e = _e(id);
    return TournamentDetail(tournament: e.tournament, teams: e.teams, matches: e.matches, standings: e.standings(), isAdmin: _admins[id]!.contains(meId), meId: meId);
  }

  @override
  Future<TournamentDetail> detail(String id) async => _detail(id);

  @override
  Future<String> uploadCover(List<int> jpeg) async => 'https://example.invalid/tcover_${jpeg.length}.jpg';

  @override
  Future<String> create(TournamentDraft d, {String? coverUrl}) async {
    final err = validateTournamentInfo(d) ?? validateTournamentFormat(d);
    if (err != null) throw TournamentException(d.teams.length > d.maxTeams ? 'too_many_teams' : 'not_enough_teams');
    final id = _create(d, coverUrl: coverUrl);
    _changed(id);
    return id;
  }

  @override
  Future<void> updateInfo(String id, Map<String, dynamic> patch) async {
    _admin(id);
    final e = _e(id);
    e.tournament = e.tournament.copyWith(name: patch['name'] as String?, description: patch['description'] as String?, location: patch['location'] as String?,
        timeSlot: patch['time_slot'] as String?, coverUrl: patch['cover_url'] as String?, startsOn: patch['starts_on'] as DateTime?,
        endsOn: patch['ends_on'] as DateTime?, maxTeams: patch['max_teams'] as int?);
    _changed(id);
  }

  @override
  Future<void> replaceTeams(String id, List<(TPlayer, TPlayer)> teams, {TournamentFormat? format, int? groupsCount, int? qualifiersPerGroup}) async {
    _admin(id);
    final e = _e(id);
    if (e.matches.any((m) => m.status == TMatchStatus.finished || m.status == TMatchStatus.live)) throw TournamentException('tournament_started');
    if (teams.length > e.tournament.maxTeams) throw TournamentException('too_many_teams');
    final t = e.tournament;
    final n = TournamentEngine(Tournament(id: t.id, name: t.name, startsOn: t.startsOn, maxTeams: t.maxTeams, format: format ?? t.format, description: t.description,
        endsOn: t.endsOn, timeSlot: t.timeSlot, location: t.location, coverUrl: t.coverUrl, groupsCount: groupsCount ?? t.groupsCount,
        qualifiersPerGroup: qualifiersPerGroup ?? t.qualifiersPerGroup, createdBy: t.createdBy, organizerName: t.organizerName), _teams(id, teams));
    n.generate();
    _engines[id] = n;
    _changed(id);
  }

  @override
  Future<void> recordResult(String matchId, List<(int, int)> sets, int version) async {
    final id = _tidOf(matchId);
    _admin(id);
    _e(id).record(matchId, sets, version);
    _changed(id);
  }

  @override
  Future<void> clearResult(String matchId, int version) async {
    final id = _tidOf(matchId);
    _admin(id);
    _e(id).clear(matchId, version);
    _changed(id);
  }

  @override
  Future<void> setLive(String matchId, bool live) async {
    final id = _tidOf(matchId);
    _admin(id);
    _e(id).setLive(matchId, live);
    _changed(id);
  }

  @override
  Stream<String> changes() => _ctl.stream;
}
