import 'tournament_models.dart';

/// Motor de competición en Dart: la MISMA lógica que las funciones SQL de `20261124b_tournaments.sql`
/// (`_t_seed_order`, `_t_build_knockout`, `_t_build_round_robin`, `_t_generate`, `_t_standings`, `_t_set_slot`,
/// `_t_reset_match`, `_t_seed_from_groups`, `_t_refresh`). Lo usan el modo demo y los tests; en producción manda el
/// servidor. Los tests comprueban los mismos casos que se validaron contra Supabase.
class TournamentEngine {
  TournamentEngine(this.tournament, List<TTeam> teams) : teams = [...teams]..sort((a, b) => a.seed.compareTo(b.seed));

  Tournament tournament;
  List<TTeam> teams;
  final Map<String, TMatch> _m = {};
  int _seq = 0;

  List<TMatch> get matches => _m.values.toList();
  TMatch match(String id) => _m[id]!;
  String _id() => '${tournament.id}_m${_seq++}';   // único entre torneos (el mock guarda varios)

  // ─────────────────────────── Generación ───────────────────────────

  /// Orden de siembra estándar de un cuadro de [p] huecos (1 vs p, 2 vs p-1…).
  static List<int> seedOrder(int p) {
    var o = [1];
    while (o.length < p) {
      final n = o.length * 2;
      o = [for (final s in o) ...[s, n + 1 - s]];
    }
    return o;
  }

  void generate() {
    _m.clear();
    teams = [for (final t in teams) t.withGroup(null)];
    final n = teams.length;
    switch (tournament.format) {
      case TournamentFormat.knockout:
        if (n < 2) throw TournamentException('not_enough_teams');
        _buildKnockout([for (final t in teams) t.id], sources: false);
      case TournamentFormat.roundRobin:
        if (n < 3) throw TournamentException('not_enough_teams');
        teams = [for (final t in teams) t.withGroup('A')];
        _buildRoundRobin('A');
      case TournamentFormat.groupsKnockout:
        final g = tournament.groupsCount, q = tournament.qualifiersPerGroup;
        if (g < 1 || n < 2 * g) throw TournamentException('not_enough_teams');
        if (q < 1 || q > n ~/ g || g * q < 2) throw TournamentException('invalid_qualifiers');
        const labels = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
        teams = [
          for (var i = 0; i < n; i++)
            teams[i].withGroup(labels[((i ~/ g) % 2 == 0) ? (i % g) : (g - 1 - (i % g))]),   // serpiente A B C D D C B A
        ];
        for (var gi = 0; gi < g; gi++) { _buildRoundRobin(labels[gi]); }
        _buildKnockout([for (var i = 1; i <= q; i++) for (var gi = 0; gi < g; gi++) '${labels[gi]}$i'], sources: true);
    }
  }

  void _buildKnockout(List<String> entrants, {required bool sources}) {
    final k = entrants.length;
    if (k < 2) throw TournamentException('not_enough_teams');
    var p = 2, rounds = 1;
    while (p < k) { p *= 2; rounds++; }
    final byPos = <(int, int), String>{};
    for (var r = rounds; r >= 1; r--) {
      final count = p ~/ (1 << r);
      for (var pos = 0; pos < count; pos++) {
        final next = byPos[(r + 1, pos ~/ 2)];
        final id = _id();
        byPos[(r, pos)] = id;
        _m[id] = TMatch(id: id, stage: MatchStage.knockout, round: r, position: pos, nextMatchId: next, nextSlot: next == null ? null : (pos % 2) + 1);
      }
    }
    final ord = seedOrder(p);
    for (var pos = 0; pos < p ~/ 2; pos++) {
      final a = ord[2 * pos], b = ord[2 * pos + 1];
      final id = byPos[(1, pos)]!;
      final bye = b > k;
      if (sources) {
        _m[id] = _m[id]!.copyWith(slot1Source: entrants[a - 1], slot2Source: bye ? null : entrants[b - 1], status: bye ? TMatchStatus.bye : TMatchStatus.pending);
      } else {
        _m[id] = _m[id]!.copyWith(team1Id: entrants[a - 1], team2Id: bye ? null : entrants[b - 1], status: bye ? TMatchStatus.bye : TMatchStatus.pending);
        _resolveBye(id);
      }
    }
  }

  void _buildRoundRobin(String group) {
    var ids = <String?>[for (final t in teams) if (t.groupLabel == group) t.id];
    if (ids.length < 2) throw TournamentException('group_too_small');
    if (ids.length.isOdd) ids.add(null);
    final n = ids.length;
    for (var r = 1; r <= n - 1; r++) {
      var pos = 0;
      for (var i = 0; i < n ~/ 2; i++) {
        final a = ids[i], b = ids[n - 1 - i];
        if (a != null && b != null) {
          final id = _id();
          _m[id] = TMatch(id: id, stage: MatchStage.group, groupLabel: group, round: r, position: pos++, team1Id: a, team2Id: b);
        }
      }
      ids = [ids[0], ids[n - 1], ...ids.sublist(1, n - 1)];   // rota todos menos el primero
    }
  }

  // ─────────────────────────── Resultados ───────────────────────────

  /// Registra o corrige un resultado. Lanza [TournamentException] con los mismos códigos que el servidor.
  void record(String matchId, List<(int, int)> sets, int version) {
    final m = _m[matchId];
    if (m == null) throw TournamentException('match_not_found');
    if (m.version != version) throw TournamentException('result_conflict');
    if (m.status == TMatchStatus.bye || m.team1Id == null || m.team2Id == null) throw TournamentException('match_not_ready');
    final err = validateTournamentSets(sets);
    if (err != null) throw TournamentException(sets.length < 2 || sets.length > 3 ? 'invalid_sets' : 'invalid_set');
    final winner = setsWinner(sets) == 1 ? m.team1Id! : m.team2Id!;
    _m[matchId] = m.copyWith(sets: sets, winnerTeamId: winner, status: TMatchStatus.finished, version: m.version + 1);
    if (m.stage == MatchStage.knockout && m.nextMatchId != null) {
      _setSlot(m.nextMatchId!, m.nextSlot!, winner);
    } else if (m.stage == MatchStage.group) {
      _seedFromGroups();
    }
    _refresh();
  }

  void clear(String matchId, int version) {
    final m = _m[matchId]!;
    if (m.version != version) throw TournamentException('result_conflict');
    if (m.status == TMatchStatus.bye) throw TournamentException('match_not_ready');
    _reset(matchId);
    if (m.stage == MatchStage.group) _seedFromGroups();
    _refresh();
  }

  void setLive(String matchId, bool live) {
    final m = _m[matchId]!;
    if (m.status == TMatchStatus.finished || !m.ready) throw TournamentException('match_not_ready');
    _m[matchId] = m.copyWith(status: live ? TMatchStatus.live : TMatchStatus.pending, version: m.version + 1);
    _refresh();
  }

  void _reset(String id) {
    final m = _m[id]!;
    if (m.status == TMatchStatus.finished || m.status == TMatchStatus.live || m.winnerTeamId != null) {
      _m[id] = m.copyWith(clearSets: true, clearWinner: true, status: TMatchStatus.pending, version: m.version + 1);
      if (m.nextMatchId != null) _setSlot(m.nextMatchId!, m.nextSlot!, null);
    }
  }

  void _setSlot(String id, int slot, String? team) {
    var m = _m[id]!;
    final cur = slot == 1 ? m.team1Id : m.team2Id;
    if (cur == team) return;
    if (m.status == TMatchStatus.finished || m.status == TMatchStatus.live) { _reset(id); m = _m[id]!; }
    _m[id] = slot == 1
        ? m.copyWith(team1Id: team, clearTeam1: team == null, version: m.version + 1)
        : m.copyWith(team2Id: team, clearTeam2: team == null, version: m.version + 1);
  }

  void _resolveBye(String id) {
    final m = _m[id]!;
    if (m.status != TMatchStatus.bye) return;
    final w = m.team1Id ?? m.team2Id;
    if (m.winnerTeamId == w) return;
    _m[id] = m.copyWith(winnerTeamId: w, clearWinner: w == null, version: m.version + 1);
    if (m.nextMatchId != null) _setSlot(m.nextMatchId!, m.nextSlot!, w);
  }

  void _seedFromGroups() {
    final done = _m.values.where((m) => m.stage == MatchStage.group).every((m) => m.finished);
    final st = standings();
    String? teamAt(String? src) => src == null ? null : st.where((s) => '${s.groupLabel}${s.pos}' == src).firstOrNull?.teamId;
    final firstRound = _m.values.where((m) => m.stage == MatchStage.knockout && m.round == 1 && m.slot1Source != null).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final m0 in firstRound) {
      final t1 = done ? teamAt(m0.slot1Source) : null;
      final t2 = done && m0.slot2Source != null ? teamAt(m0.slot2Source) : null;
      _setSlot(m0.id, 1, t1);
      _setSlot(m0.id, 2, t2);
      if (m0.status == TMatchStatus.bye) {
        if (t1 != null) {
          _resolveBye(m0.id);
        } else if (_m[m0.id]!.winnerTeamId != null) {
          final m = _m[m0.id]!;
          _m[m0.id] = m.copyWith(clearWinner: true, version: m.version + 1);
          if (m.nextMatchId != null) _setSlot(m.nextMatchId!, m.nextSlot!, null);
        }
      }
    }
  }

  /// Clasificación: puntos → diferencia de sets → diferencia de juegos → victorias → semilla.
  List<TStanding> standings() {
    final out = <TStanding>[];
    final groups = {for (final t in teams) if (t.groupLabel != null) t.groupLabel!};
    for (final g in groups) {
      final rows = <TStanding>[];
      for (final t in teams.where((t) => t.groupLabel == g)) {
        var played = 0, won = 0, lost = 0, sf = 0, sa = 0, gf = 0, ga = 0;
        for (final m in _m.values.where((m) => m.stage == MatchStage.group && m.finished && m.involves(t.id))) {
          final first = m.team1Id == t.id;
          played++;
          if (m.winnerTeamId == t.id) { won++; } else { lost++; }
          for (final (a, b) in m.sets!) {
            final mine = first ? a : b, theirs = first ? b : a;
            if (mine > theirs) { sf++; } else { sa++; }
            gf += mine; ga += theirs;
          }
        }
        rows.add(TStanding(groupLabel: g, teamId: t.id, seed: t.seed, played: played, won: won, lost: lost, setsFor: sf, setsAgainst: sa,
            gamesFor: gf, gamesAgainst: ga, points: won * tournament.pointsWin + lost * tournament.pointsLoss, pos: 0));
      }
      rows.sort((a, b) {
        for (final c in [b.points - a.points, b.setDiff - a.setDiff, b.gameDiff - a.gameDiff, b.won - a.won, a.seed - b.seed]) {
          if (c != 0) return c;
        }
        return 0;
      });
      for (var i = 0; i < rows.length; i++) {
        final s = rows[i];
        out.add(TStanding(groupLabel: s.groupLabel, teamId: s.teamId, seed: s.seed, played: s.played, won: s.won, lost: s.lost,
            setsFor: s.setsFor, setsAgainst: s.setsAgainst, gamesFor: s.gamesFor, gamesAgainst: s.gamesAgainst, points: s.points, pos: i + 1));
      }
    }
    out.sort((a, b) => a.groupLabel != b.groupLabel ? a.groupLabel.compareTo(b.groupLabel) : a.pos.compareTo(b.pos));
    return out;
  }

  void _refresh() {
    String? champ;
    if (tournament.format == TournamentFormat.roundRobin) {
      if (_m.values.every((m) => m.finished)) champ = standings().firstWhere((s) => s.pos == 1).teamId;
    } else {
      final fin = _m.values.where((m) => m.stage == MatchStage.knockout && m.nextMatchId == null).firstOrNull;
      if (fin != null && (fin.status == TMatchStatus.finished || fin.status == TMatchStatus.bye)) champ = fin.winnerTeamId;
    }
    final anyDone = _m.values.any((m) => m.status == TMatchStatus.finished || m.status == TMatchStatus.live);
    tournament = tournament.copyWith(championTeamId: champ, clearChampion: champ == null,
        status: champ != null ? TournamentStatus.finished : anyDone ? TournamentStatus.inProgress : TournamentStatus.scheduled);
  }
}
