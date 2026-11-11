import 'dart:async';
import '../../matches/domain/match_lifecycle.dart';
import '../../matches/domain/match_models.dart';
import '../domain/league_models.dart';
import 'league_repository.dart';

/// DATOS MOCK (modo demo y tests). Aplica las MISMAS reglas que las RPC de Supabase: visibilidad, código, aforo,
/// gestores y clasificación ([computeStandings]). La app real usa [SupabaseLeagueRepository].
class MockLeagueRepository implements LeagueRepository {
  MockLeagueRepository({this.me = 'me', DateTime? now, bool seed = true, this.latency = const Duration(milliseconds: 350)}) : _now = now ?? DateTime.now() {
    if (seed) _seed();
  }
  final String me;
  final DateTime _now;
  final Duration latency;
  bool failNext = false;                       // simula un error de red en la siguiente llamada

  final _leagues = <String, _L>{};
  final _names = <String, String>{'me': 'Diego Castello'};
  final _elo = <String, int>{'me': 1482};
  final _friends = <String>{'marcos', 'alvaro', 'lucia', 'laura', 'pablo'};
  final _ctl = StreamController<String>.broadcast();
  var _seq = 0;

  Future<void> _tick() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failNext) { failNext = false; throw LeagueException('network'); }
  }

  void _person(String id, String name, int elo) { _names[id] = name; _elo[id] = elo; }

  void _seed() {
    for (final p in const [('marcos', 'Marcos Ruiz', 1510), ('alvaro', 'Álvaro Pérez', 1455), ('lucia', 'Lucía Martín', 1390), ('laura', 'Laura Gómez', 1560),
      ('pablo', 'Pablo Sanz', 1420), ('sofia', 'Sofía García', 1475), ('carlos', 'Carlos Molina', 1350), ('javi', 'Javi Ortega', 1500),
      ('nuria', 'Nuria Vidal', 1300), ('ines', 'Inés Rey', 1610)]) { _person(p.$1, p.$2, p.$3); }
    _leagues['bunker'] = _L(id: 'bunker', name: 'BÜNKER PADEL LEAGUE', visibility: LeagueVisibility.private, cover: 'court', location: 'Madrid · Centro', createdBy: 'me',
        description: 'Liga entre amigos del Bünker. Partidos entre semana y los domingos por la mañana.', starts: _now.subtract(const Duration(days: 40)), ends: _now.add(const Duration(days: 50)),
        members: {'me': LeagueRole.organizer, 'marcos': LeagueRole.player, 'alvaro': LeagueRole.player, 'lucia': LeagueRole.player, 'laura': LeagueRole.player, 'pablo': LeagueRole.player, 'javi': LeagueRole.player, 'sofia': LeagueRole.player},
        code: 'BUNKERPA-01', requests: [JoinRequest(id: 'rq1', userId: 'carlos', name: 'Carlos Molina', message: 'Juego los martes, ¿me dejáis entrar?', createdAt: _now.subtract(const Duration(hours: 5)))]);
    _leagues['madrid'] = _L(id: 'madrid', name: 'LIGA MADRID CENTRO', visibility: LeagueVisibility.public, cover: 'lines', location: 'Madrid · Centro', createdBy: 'ines',
        description: 'Liga abierta para todos los niveles en la zona centro.', starts: _now.subtract(const Duration(days: 20)), ends: _now.add(const Duration(days: 70)),
        members: {'ines': LeagueRole.organizer, 'me': LeagueRole.player, 'sofia': LeagueRole.player, 'carlos': LeagueRole.player, 'nuria': LeagueRole.player, 'javi': LeagueRole.player}, code: 'MADRIDCE-01');
    _leagues['moraleja'] = _L(id: 'moraleja', name: 'CLUB LA MORALEJA · OTOÑO', visibility: LeagueVisibility.club, cover: 'grid', location: 'Alcobendas', createdBy: 'nuria',
        description: 'Liga oficial del club. Solo socios.', starts: _now.add(const Duration(days: 12)), ends: _now.add(const Duration(days: 100)),
        members: {'nuria': LeagueRole.organizer, 'me': LeagueRole.admin, 'laura': LeagueRole.player}, code: 'MORALEJA-01');
    _leagues['norte'] = _L(id: 'norte', name: 'NORTE PADEL SERIES', visibility: LeagueVisibility.public, cover: 'waves', location: 'Madrid · Norte', createdBy: 'javi',
        description: 'Temporada de invierno con final a cuatro.', starts: _now.add(const Duration(days: 5)), ends: _now.add(const Duration(days: 95)),
        members: {'javi': LeagueRole.organizer, 'marcos': LeagueRole.player, 'lucia': LeagueRole.player}, code: 'NORTEPAD-01', levelMin: 'Intermedio');
    _leagues['chamartin'] = _L(id: 'chamartin', name: 'CHAMARTÍN SOCIAL CLUB', visibility: LeagueVisibility.club, cover: 'dots', location: 'Chamartín', createdBy: 'laura',
        description: 'Liga social del club, partidos los jueves.', starts: _now.subtract(const Duration(days: 3)), ends: _now.add(const Duration(days: 60)),
        members: {'laura': LeagueRole.organizer, 'pablo': LeagueRole.player}, code: 'CHAMARTI-01');
    // Partidos confirmados de BÜNKER (8 jugadores) y MADRID.
    void m(String l, List<String> t1, List<String> t2, List<(int, int)> s, int daysAgo, {MatchStatus st = MatchStatus.confirmed}) =>
        _leagues[l]!.matches.add(_M('lm${_seq++}', t1, t2, s, _now.subtract(Duration(days: daysAgo)), st));
    m('bunker', ['me', 'marcos'], ['alvaro', 'lucia'], const [(6, 3), (6, 4)], 2);
    m('bunker', ['laura', 'pablo'], ['me', 'marcos'], const [(6, 4), (3, 6), (7, 5)], 6);
    m('bunker', ['javi', 'sofia'], ['alvaro', 'pablo'], const [(7, 6), (6, 2)], 9);
    m('bunker', ['me', 'lucia'], ['javi', 'laura'], const [(6, 2), (6, 1)], 13);
    m('bunker', ['marcos', 'sofia'], ['lucia', 'alvaro'], const [(4, 6), (6, 3), (6, 4)], 17);
    m('bunker', ['pablo', 'javi'], ['me', 'sofia'], const [(6, 4), (6, 4)], 1, st: MatchStatus.disputed);
    m('bunker', ['me', 'alvaro'], ['laura', 'lucia'], const [], -2, st: MatchStatus.scheduled);
    m('madrid', ['me', 'sofia'], ['carlos', 'nuria'], const [(6, 1), (6, 2)], 4);
    m('madrid', ['ines', 'javi'], ['me', 'sofia'], const [(6, 3), (6, 3)], 8);
  }

  List<StandingRow> _standings(_L l) => computeStandings(
      [for (final e in l.members.entries) LeagueMemberRef(e.key, _names[e.key] ?? e.key, elo: _elo[e.key] ?? 1200, role: e.value)],
      [for (final x in l.matches) LeagueMatchResult(team1: x.t1, team2: x.t2, sets: x.sets, confirmed: x.status == MatchStatus.confirmed)],
      l.rules);

  LeagueStatus _status(_L l) => l.ended ? LeagueStatus.ended : l.starts.isAfter(_now) ? LeagueStatus.open : LeagueStatus.running;
  _L _get(String id) => _leagues[id] ?? (throw LeagueException('league_not_found'));
  bool _canView(_L l) => l.members.containsKey(me) || l.visibility != LeagueVisibility.private || l.invited.contains(me);
  void _requireManager(_L l) { if (!(l.members[me]?.isManager ?? false)) throw LeagueException('not_league_manager'); }
  void _changed(String id) => _ctl.add(id);

  @override
  Future<List<LeagueSummary>> myLeagues() async {
    await _tick();
    return [
      for (final l in _leagues.values.where((l) => l.members.containsKey(me)))
        () {
          final st = _standings(l), mine = st.firstWhere((r) => r.userId == me);
          return LeagueSummary(id: l.id, name: l.name, visibility: l.visibility, cover: l.cover, location: l.location, season: l.season, startsOn: l.starts, endsOn: l.ends,
              status: _status(l), role: l.members[me]!, members: l.members.length, myRank: mine.rank, myPoints: mine.points, myPlayed: mine.played, myWins: mine.wins,
              matchesDone: l.matches.where((x) => x.status == MatchStatus.confirmed).length, matchesTotal: plannedMatches(l.members.length, l.matchesPerPlayer),
              organizerName: _names[l.createdBy] ?? '');
        }(),
    ];
  }

  @override
  Future<List<DiscoverLeague>> discover(String query) async {
    await _tick();
    final q = query.trim().toLowerCase();
    return [
      for (final l in _leagues.values)
        if (!l.ended && !l.members.containsKey(me) && (l.visibility != LeagueVisibility.private || l.invited.contains(me))
            && (q.isEmpty || '${l.name} ${l.location} ${_names[l.createdBy]}'.toLowerCase().contains(q)))
          DiscoverLeague(id: l.id, name: l.name, visibility: l.visibility, cover: l.cover, location: l.location, levelMin: l.levelMin, levelMax: l.levelMax,
              season: l.season, startsOn: l.starts, endsOn: l.ends, status: _status(l), organizerName: _names[l.createdBy] ?? '', members: l.members.length,
              maxPlayers: l.maxPlayers, friendsIn: l.members.keys.where(_friends.contains).length, friendIds: l.members.keys.where(_friends.contains).take(3).toList(),
              invited: l.invited.contains(me), requestPending: l.requests.any((r) => r.userId == me)),
    ]..sort((a, b) => b.friendsIn - a.friendsIn);
  }

  @override
  Future<LeagueDetail> league(String id) async {
    await _tick();
    final l = _get(id);
    if (!_canView(l)) throw LeagueException('league_not_found');
    return LeagueDetail(id: l.id, name: l.name, description: l.description, visibility: l.visibility, cover: l.cover, location: l.location, levelMin: l.levelMin,
        levelMax: l.levelMax, season: l.season, startsOn: l.starts, endsOn: l.ends, status: _status(l), minPlayers: l.minPlayers, maxPlayers: l.maxPlayers,
        matchesPerPlayer: l.matchesPerPlayer, rules: l.rules, challengesEnabled: l.challenges, createdBy: l.createdBy, organizerName: _names[l.createdBy] ?? '', myRole: l.members[me]);
  }

  @override
  Future<List<StandingRow>> standings(String id) async { await _tick(); final l = _get(id); return _canView(l) ? _standings(l) : const []; }

  @override
  Future<List<LifecycleMatch>> matches(String id) async {
    await _tick();
    final l = _get(id);
    if (!l.members.containsKey(me)) return const [];
    MatchPlayer p(String u, int team, bool cap) => MatchPlayer(id: u, name: _names[u] ?? u, team: team, isCaptain: cap, elo: _elo[u] ?? 1200);
    return [
      for (final x in l.matches..sort((a, b) => b.at.compareTo(a.at)))
        LifecycleMatch(id: x.id, type: MatchType.league, leagueId: l.id, leagueName: l.name, scheduledAt: x.at, club: l.location, status: x.status, createdBy: x.t1.first,
            players: [p(x.t1[0], 1, true), p(x.t1[1], 1, false), p(x.t2[0], 2, true), p(x.t2[1], 2, false)],
            sets: [for (final s in x.sets) SetScore(s.$1, s.$2)], resultVersion: x.sets.isEmpty ? 0 : 1,
            rejectionReason: x.status == MatchStatus.disputed ? 'El segundo set fue 6-4 para nosotros' : null),
    ];
  }

  @override
  Future<List<JoinRequest>> joinRequests(String id) async { await _tick(); final l = _get(id); return (l.members[me]?.isManager ?? false) ? List.of(l.requests) : const []; }

  @override
  Future<String?> inviteCode(String id) async {
    await _tick();
    final l = _get(id);
    final r = l.members[me];
    return r == null || (l.visibility == LeagueVisibility.club && !r.isManager) ? null : l.code;
  }

  @override
  Future<({String id, String code})> create(LeagueDraft d) async {
    await _tick();
    final e = validateLeagueStep(d, 5);
    if (e.isNotEmpty) throw LeagueException(e.containsKey('name') ? 'invalid_league_name' : e.containsKey('dates') ? 'invalid_league_dates' : 'invalid_league_players');
    final name = d.name.trim().toUpperCase();
    final id = 'liga${_seq++}';
    final base = name.replaceAll(RegExp('[^A-Z0-9]+'), '');
    final code = '${base.isEmpty ? 'LIGA' : base.substring(0, base.length < 8 ? base.length : 8)}-${1000 + _seq}';
    _leagues[id] = _L(id: id, name: name, visibility: d.visibility, cover: d.cover, location: d.location, createdBy: me, description: d.description.trim(),
        starts: d.startsOn, ends: d.endsOn, members: {me: LeagueRole.organizer}, code: code, levelMin: d.levelMin, levelMax: d.levelMax, maxPlayers: d.maxPlayers,
        minPlayers: d.minPlayers, matchesPerPlayer: d.matchesPerPlayer, rules: LeagueRules(pointsWin: d.pointsWin, bonusEnabled: d.bonus), challenges: d.challenges)
      ..invited.addAll(d.invited.where(_friends.contains));
    return (id: id, code: code);
  }

  @override
  Future<JoinOutcome> join(String id, {String? code, String? message}) async {
    await _tick();
    final l = _get(id);
    if (l.members.containsKey(me)) return JoinOutcome.alreadyMember;
    if (l.ended) throw LeagueException('league_ended');
    if (l.members.length >= l.maxPlayers) throw LeagueException('league_full');
    if (l.visibility == LeagueVisibility.public || l.invited.contains(me) || (code != null && code.trim().toUpperCase() == l.code)) {
      l.members[me] = LeagueRole.player; l.invited.remove(me); l.requests.removeWhere((r) => r.userId == me); _changed(id);
      return JoinOutcome.joined;
    }
    if (l.visibility == LeagueVisibility.private) throw LeagueException('invite_code_required');
    if (!l.requests.any((r) => r.userId == me)) l.requests.add(JoinRequest(id: 'rq${_seq++}', userId: me, name: _names[me]!, message: message ?? '', createdAt: _now));
    _changed(id);
    return JoinOutcome.requested;
  }

  @override
  Future<String> joinByCode(String code) async {
    final l = _leagues.values.where((l) => l.code == code.trim().toUpperCase()).firstOrNull;
    if (l == null) { await _tick(); throw LeagueException('invalid_invite_code'); }
    await join(l.id, code: code);
    return l.id;
  }

  @override
  Future<void> respondRequest(String requestId, {required bool accept}) async {
    await _tick();
    final l = _leagues.values.firstWhere((l) => l.requests.any((r) => r.id == requestId), orElse: () => throw LeagueException('request_not_pending'));
    _requireManager(l);
    final r = l.requests.firstWhere((r) => r.id == requestId);
    if (accept) {
      if (l.members.length >= l.maxPlayers) throw LeagueException('league_full');
      l.members[r.userId] = LeagueRole.player;
    }
    l.requests.remove(r); _changed(l.id);
  }

  @override
  Future<void> leave(String id) async {
    await _tick();
    final l = _get(id);
    final role = l.members[me];
    if (role == null) throw LeagueException('not_a_member');
    if (role == LeagueRole.organizer) {
      if (l.members.length > 1) throw LeagueException('organizer_cannot_leave');
      _leagues.remove(id);
    } else { l.members.remove(me); }
    _changed(id);
  }

  @override
  Future<void> removeMember(String id, String userId) async {
    await _tick();
    final l = _get(id);
    _requireManager(l);
    if (l.members[userId] == LeagueRole.organizer) throw LeagueException('cannot_remove_organizer');
    l.members.remove(userId); _changed(id);
  }

  @override
  Future<int> invite(String id, List<String> userIds) async {
    await _tick();
    final l = _get(id);
    _requireManager(l);
    final ok = userIds.where((u) => _friends.contains(u) && !l.members.containsKey(u)).toList();
    l.invited.addAll(ok);
    return ok.length;
  }

  @override
  Future<void> update(String id, Map<String, Object?> patch) async {
    await _tick();
    final l = _get(id);
    _requireManager(l);
    final name = patch['name'] as String?;
    if (name != null && (name.trim().length < 3 || name.trim().length > 40)) throw LeagueException('invalid_league_name');
    final max = patch['max_players'] as int?;
    if (max != null && max < l.members.length) throw LeagueException('max_below_members');
    if (name != null) l.name = name.trim().toUpperCase();
    if (patch['description'] is String) l.description = (patch['description'] as String).trim();
    if (max != null) l.maxPlayers = max;
    if (patch['ended'] == true) l.ended = true;
    _changed(id);
  }

  @override
  Stream<void> watch(String id) => _ctl.stream.where((x) => x == id).map((_) {});
}

class _L {
  _L({required this.id, required this.name, required this.visibility, required this.cover, required this.location, required this.createdBy, required this.description,
      required this.starts, required this.ends, required this.members, required this.code, this.levelMin = 'Iniciación', this.levelMax = 'Avanzado',
      this.maxPlayers = 16, this.minPlayers = 2, this.matchesPerPlayer = 10, this.rules = const LeagueRules(), this.challenges = true, List<JoinRequest>? requests})
      : requests = requests ?? [];
  final String id, cover, location, createdBy, code, levelMin, levelMax;
  String name, description;
  final LeagueVisibility visibility;
  final DateTime starts, ends;
  final Map<String, LeagueRole> members;
  int maxPlayers;
  final int minPlayers, matchesPerPlayer;
  final LeagueRules rules;
  final bool challenges;
  final String season = '01';
  bool ended = false;
  final List<JoinRequest> requests;
  final invited = <String>{};
  final matches = <_M>[];
}

class _M {
  _M(this.id, this.t1, this.t2, this.sets, this.at, this.status);
  final String id;
  final List<String> t1, t2;
  final List<(int, int)> sets;
  final DateTime at;
  final MatchStatus status;
}
