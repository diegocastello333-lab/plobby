import 'package:flutter/foundation.dart';

/// Formatos de torneo. El nombre de BD se guarda en `tournaments.format`.
enum TournamentFormat {
  knockout('knockout', 'Eliminación directa'),
  groupsKnockout('groups_knockout', 'Grupos + eliminatoria'),
  roundRobin('round_robin', 'Liguilla (todos contra todos)');

  const TournamentFormat(this.db, this.label);
  final String db, label;
  static TournamentFormat fromDb(String? s) => values.firstWhere((f) => f.db == s, orElse: () => knockout);
  bool get hasGroups => this != knockout;
  bool get hasBracket => this != roundRobin;
}

enum TournamentStatus {
  scheduled('scheduled'), inProgress('in_progress'), finished('finished');
  const TournamentStatus(this.db);
  final String db;
  static TournamentStatus fromDb(String? s) => values.firstWhere((v) => v.db == s, orElse: () => scheduled);
}

enum MatchStage { group, knockout }

enum TMatchStatus {
  pending('pending', 'Pendiente'), live('live', 'En juego'), finished('finished', 'Finalizado'), bye('bye', 'Pasa directo');
  const TMatchStatus(this.db, this.label);
  final String db, label;
  static TMatchStatus fromDb(String? s) => values.firstWhere((v) => v.db == s, orElse: () => pending);
}

/// Jugador tal y como se muestra en un torneo.
@immutable
class TPlayer {
  const TPlayer({required this.id, required this.name, this.username = '', this.avatarUrl});
  final String id, name, username;
  final String? avatarUrl;
  /// «Diego C.»: nombre y la inicial del primer apellido (para que quepan dos jugadores en una línea).
  String get short {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return username.isEmpty ? 'Jugador' : '@$username';
    return parts.length == 1 ? parts.first : '${parts.first} ${parts[1][0]}.';
  }
  @override
  bool operator ==(Object o) => o is TPlayer && o.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Pareja inscrita: dos jugadores, semilla (orden de inscripción) y grupo si el formato tiene fase de grupos.
@immutable
class TTeam {
  const TTeam({required this.id, required this.seed, required this.p1, required this.p2, this.groupLabel});
  final String id;
  final int seed;
  final TPlayer p1, p2;
  final String? groupLabel;
  String get name => '${p1.short} / ${p2.short}';
  bool has(String userId) => p1.id == userId || p2.id == userId;
  TTeam withGroup(String? g) => TTeam(id: id, seed: seed, p1: p1, p2: p2, groupLabel: g);
}

/// Partido de un torneo (de grupo o de cuadro). `version` sube con cada cambio: el servidor rechaza un resultado
/// enviado con una versión antigua (otra persona lo cambió antes).
@immutable
class TMatch {
  const TMatch({required this.id, required this.stage, required this.round, required this.position, this.groupLabel,
      this.team1Id, this.team2Id, this.slot1Source, this.slot2Source, this.nextMatchId, this.nextSlot,
      this.status = TMatchStatus.pending, this.sets, this.winnerTeamId, this.version = 0});
  final String id;
  final MatchStage stage;
  final String? groupLabel;
  final int round, position;
  final String? team1Id, team2Id, slot1Source, slot2Source, nextMatchId, winnerTeamId;
  final int? nextSlot;
  final TMatchStatus status;
  final List<(int, int)>? sets;
  final int version;

  bool get ready => team1Id != null && team2Id != null && status != TMatchStatus.bye;
  bool get finished => status == TMatchStatus.finished;
  bool involves(String? teamId) => teamId != null && (team1Id == teamId || team2Id == teamId);
  String get score => sets == null ? '' : sets!.map((s) => '${s.$1}-${s.$2}').join(' / ');

  TMatch copyWith({String? team1Id, String? team2Id, bool clearTeam1 = false, bool clearTeam2 = false, TMatchStatus? status,
          List<(int, int)>? sets, bool clearSets = false, String? winnerTeamId, bool clearWinner = false, int? version,
          String? slot1Source, String? slot2Source, bool clearSlot2Source = false}) =>
      TMatch(id: id, stage: stage, round: round, position: position, groupLabel: groupLabel,
          team1Id: clearTeam1 ? null : (team1Id ?? this.team1Id), team2Id: clearTeam2 ? null : (team2Id ?? this.team2Id),
          slot1Source: slot1Source ?? this.slot1Source, slot2Source: clearSlot2Source ? null : (slot2Source ?? this.slot2Source),
          nextMatchId: nextMatchId, nextSlot: nextSlot, status: status ?? this.status,
          sets: clearSets ? null : (sets ?? this.sets), winnerTeamId: clearWinner ? null : (winnerTeamId ?? this.winnerTeamId),
          version: version ?? this.version);
}

/// Fila de clasificación de un grupo (calculada en el servidor con `tournament_standings`, o por [TournamentEngine]).
@immutable
class TStanding {
  const TStanding({required this.groupLabel, required this.teamId, required this.seed, required this.played, required this.won,
      required this.lost, required this.setsFor, required this.setsAgainst, required this.gamesFor, required this.gamesAgainst,
      required this.points, required this.pos});
  final String groupLabel, teamId;
  final int seed, played, won, lost, setsFor, setsAgainst, gamesFor, gamesAgainst, points, pos;
  int get setDiff => setsFor - setsAgainst;
  int get gameDiff => gamesFor - gamesAgainst;
}

@immutable
class Tournament {
  const Tournament({required this.id, required this.name, required this.startsOn, required this.maxTeams, required this.format,
      this.description, this.endsOn, this.timeSlot, this.location, this.coverUrl, this.groupsCount = 1, this.qualifiersPerGroup = 0,
      this.pointsWin = 3, this.pointsLoss = 0, this.status = TournamentStatus.scheduled, this.championTeamId,
      this.createdBy = '', this.organizerName = ''});
  final String id, name, createdBy, organizerName;
  final String? description, timeSlot, location, coverUrl, championTeamId;
  final DateTime startsOn;
  final DateTime? endsOn;
  final int maxTeams, groupsCount, qualifiersPerGroup, pointsWin, pointsLoss;
  final TournamentFormat format;
  final TournamentStatus status;

  Tournament copyWith({TournamentStatus? status, String? championTeamId, bool clearChampion = false, String? name, String? description,
          String? location, String? timeSlot, String? coverUrl, DateTime? startsOn, DateTime? endsOn, int? maxTeams}) =>
      Tournament(id: id, name: name ?? this.name, startsOn: startsOn ?? this.startsOn, maxTeams: maxTeams ?? this.maxTeams, format: format,
          description: description ?? this.description, endsOn: endsOn ?? this.endsOn, timeSlot: timeSlot ?? this.timeSlot,
          location: location ?? this.location, coverUrl: coverUrl ?? this.coverUrl, groupsCount: groupsCount,
          qualifiersPerGroup: qualifiersPerGroup, pointsWin: pointsWin, pointsLoss: pointsLoss, status: status ?? this.status,
          championTeamId: clearChampion ? null : (championTeamId ?? this.championTeamId), createdBy: createdBy, organizerName: organizerName);
}

/// Estado visible del torneo (próximamente / en curso / finalizado) a partir del estado y las fechas.
enum TournamentPhase { upcoming, inProgress, finished }

TournamentPhase phaseOf(TournamentStatus s, DateTime startsOn, {DateTime? now}) {
  if (s == TournamentStatus.finished) return TournamentPhase.finished;
  final n = now ?? DateTime.now(), today = DateTime(n.year, n.month, n.day);
  if (s == TournamentStatus.scheduled && startsOn.isAfter(today)) return TournamentPhase.upcoming;
  return TournamentPhase.inProgress;
}

String phaseLabel(TournamentPhase p) => switch (p) {
      TournamentPhase.upcoming => 'Próximamente',
      TournamentPhase.inProgress => 'En curso',
      TournamentPhase.finished => 'Finalizado',
    };

/// Nombre de una ronda de eliminatoria contando desde la final (la última ronda es la final).
String roundName(int round, int totalRounds) => switch (totalRounds - round) {
      0 => 'Final',
      1 => 'Semifinales',
      2 => 'Cuartos de final',
      3 => 'Octavos de final',
      4 => 'Dieciseisavos',
      _ => 'Ronda $round',
    };

/// Toda la información de un torneo para su pantalla.
@immutable
class TournamentDetail {
  const TournamentDetail({required this.tournament, required this.teams, required this.matches, required this.standings,
      required this.isAdmin, required this.meId});
  final Tournament tournament;
  final List<TTeam> teams;
  final List<TMatch> matches;
  final List<TStanding> standings;
  final bool isAdmin;
  final String meId;

  TTeam? team(String? id) => id == null ? null : teams.where((t) => t.id == id).firstOrNull;
  TTeam? get myTeam => teams.where((t) => t.has(meId)).firstOrNull;
  TTeam? get champion => team(tournament.championTeamId);
  List<TMatch> get knockout => matches.where((m) => m.stage == MatchStage.knockout).toList()
    ..sort((a, b) => a.round != b.round ? a.round.compareTo(b.round) : a.position.compareTo(b.position));
  int get knockoutRounds => knockout.fold(0, (m, x) => x.round > m ? x.round : m);
  List<String> get groupLabels => {for (final t in teams) if (t.groupLabel != null) t.groupLabel!}.toList()..sort();
  List<TMatch> groupMatches(String g) => matches.where((m) => m.stage == MatchStage.group && m.groupLabel == g).toList()
    ..sort((a, b) => a.round != b.round ? a.round.compareTo(b.round) : a.position.compareTo(b.position));
  List<TStanding> standingsOf(String g) => standings.where((s) => s.groupLabel == g).toList()..sort((a, b) => a.pos.compareTo(b.pos));
  bool get groupsDone => matches.where((m) => m.stage == MatchStage.group).every((m) => m.finished);
  bool get started => matches.any((m) => m.status == TMatchStatus.finished || m.status == TMatchStatus.live);

  /// Fase actual en texto: «Fase de grupos», «Cuartos de final», «Final», «Finalizado»…
  String get currentPhase {
    if (tournament.status == TournamentStatus.finished) return 'Finalizado';
    final f = tournament.format;
    if (f.hasGroups && !groupsDone) return f == TournamentFormat.roundRobin ? 'Liguilla' : 'Fase de grupos';
    final pending = knockout.where((m) => m.status == TMatchStatus.pending || m.status == TMatchStatus.live);
    if (pending.isEmpty) return f == TournamentFormat.roundRobin ? 'Liguilla' : 'Cuadro final';
    final r = pending.map((m) => m.round).reduce((a, b) => a < b ? a : b);
    return roundName(r, knockoutRounds);
  }

  /// Etiqueta de una ronda o grupo para un partido concreto.
  String matchLabel(TMatch m) => m.stage == MatchStage.group
      ? (tournament.format == TournamentFormat.roundRobin ? 'Jornada ${m.round}' : 'Grupo ${m.groupLabel} · Jornada ${m.round}')
      : roundName(m.round, knockoutRounds);

  /// Texto de un hueco del cuadro todavía sin pareja: «1.º Grupo A», «Ganador de Cuartos 2»…
  String slotLabel(TMatch m, int slot) {
    final src = slot == 1 ? m.slot1Source : m.slot2Source;
    if (src != null && src.length >= 2) return '${src.substring(1)}.º Grupo ${src[0]}';
    if (m.round > 1) {
      final prev = knockout.where((x) => x.nextMatchId == m.id && x.nextSlot == slot).firstOrNull;
      if (prev != null) return 'Ganador ${roundName(prev.round, knockoutRounds).toLowerCase()} ${prev.position + 1}';
    }
    return 'Por decidir';
  }
}

/// Fila de «Mis torneos» (RPC `my_tournaments`).
@immutable
class TournamentSummary {
  const TournamentSummary({required this.id, required this.name, required this.startsOn, required this.format, required this.status,
      required this.teamsCount, required this.maxTeams, this.endsOn, this.timeSlot, this.location, this.coverUrl, this.isAdmin = false,
      this.knockoutRounds, this.currentRound, this.groupPending = 0, this.championTeamId, this.myTeamId, this.nextMatch});
  final String id, name;
  final DateTime startsOn;
  final DateTime? endsOn;
  final String? timeSlot, location, coverUrl, championTeamId, myTeamId;
  final TournamentFormat format;
  final TournamentStatus status;
  final int teamsCount, maxTeams, groupPending;
  final int? knockoutRounds, currentRound;
  final bool isAdmin;
  final NextMatchInfo? nextMatch;

  TournamentPhase get phase => phaseOf(status, startsOn);
  String get phaseText {
    if (status == TournamentStatus.finished) return 'Finalizado';
    if (format.hasGroups && groupPending > 0) return format == TournamentFormat.roundRobin ? 'Liguilla' : 'Fase de grupos';
    if (currentRound != null && knockoutRounds != null) return roundName(currentRound!, knockoutRounds!);
    return format.label;
  }
}

@immutable
class NextMatchInfo {
  const NextMatchInfo({required this.label, required this.opponent, this.live = false});
  final String label, opponent;
  final bool live;
}

/// Borrador del asistente «Crear torneo». Nada se guarda hasta confirmar.
@immutable
class TournamentDraft {
  const TournamentDraft({this.name = '', this.description = '', this.startsOn, this.endsOn, this.timeSlot = '', this.location = '',
      this.coverBytes, this.maxTeams = 8, this.format = TournamentFormat.knockout, this.groupsCount = 2, this.qualifiersPerGroup = 2,
      this.teams = const []});
  final String name, description, timeSlot, location;
  final DateTime? startsOn, endsOn;
  final List<int>? coverBytes;
  final int maxTeams, groupsCount, qualifiersPerGroup;
  final TournamentFormat format;
  final List<(TPlayer, TPlayer)> teams;

  Set<String> get playerIds => {for (final t in teams) ...[t.$1.id, t.$2.id]};

  TournamentDraft copyWith({String? name, String? description, DateTime? startsOn, DateTime? endsOn, bool clearEnd = false, String? timeSlot,
          String? location, List<int>? coverBytes, bool clearCover = false, int? maxTeams, TournamentFormat? format, int? groupsCount,
          int? qualifiersPerGroup, List<(TPlayer, TPlayer)>? teams}) =>
      TournamentDraft(name: name ?? this.name, description: description ?? this.description, startsOn: startsOn ?? this.startsOn,
          endsOn: clearEnd ? null : (endsOn ?? this.endsOn), timeSlot: timeSlot ?? this.timeSlot, location: location ?? this.location,
          coverBytes: clearCover ? null : (coverBytes ?? this.coverBytes), maxTeams: maxTeams ?? this.maxTeams, format: format ?? this.format,
          groupsCount: groupsCount ?? this.groupsCount, qualifiersPerGroup: qualifiersPerGroup ?? this.qualifiersPerGroup, teams: teams ?? this.teams);
}

/// Validación del paso «Información» (mismas reglas que las restricciones de la tabla).
String? validateTournamentInfo(TournamentDraft d) {
  if (d.name.trim().length < 3) return 'Ponle un nombre al torneo (mínimo 3 letras).';
  if (d.name.trim().length > 60) return 'El nombre no puede superar 60 caracteres.';
  if (d.startsOn == null) return 'Elige la fecha de inicio.';
  if (d.endsOn != null && d.endsOn!.isBefore(d.startsOn!)) return 'La fecha de fin no puede ser anterior a la de inicio.';
  if (d.maxTeams < 2 || d.maxTeams > 64) return 'El máximo de parejas debe estar entre 2 y 64.';
  return null;
}

/// Validación del formato frente al número de parejas (igual que `_t_generate` en el servidor).
String? validateTournamentFormat(TournamentDraft d) {
  final n = d.teams.length;
  if (n > d.maxTeams) return 'Hay $n parejas y el máximo es ${d.maxTeams}.';
  switch (d.format) {
    case TournamentFormat.knockout:
      if (n < 2) return 'Para una eliminatoria hacen falta al menos 2 parejas.';
    case TournamentFormat.roundRobin:
      if (n < 3) return 'Para una liguilla hacen falta al menos 3 parejas.';
    case TournamentFormat.groupsKnockout:
      final g = d.groupsCount, q = d.qualifiersPerGroup;
      if (n < 2 * g) return 'Con $g grupos hacen falta al menos ${2 * g} parejas (2 por grupo).';
      if (q < 1 || q > n ~/ g) return 'En cada grupo pueden clasificarse entre 1 y ${n ~/ g} parejas.';
      if (g * q < 2) return 'Deben clasificarse al menos 2 parejas para jugar la eliminatoria.';
  }
  return null;
}

/// Partidos que se jugarán (sin contar los pases directos).
int estimatedMatches(TournamentFormat f, int teams, {int groups = 1, int qualifiers = 0}) {
  int rr(int n) => n * (n - 1) ~/ 2;
  switch (f) {
    case TournamentFormat.knockout:
      return teams < 2 ? 0 : teams - 1;
    case TournamentFormat.roundRobin:
      return rr(teams);
    case TournamentFormat.groupsKnockout:
      if (groups < 1 || teams < 2 * groups) return 0;
      var total = 0;
      for (var g = 0; g < groups; g++) {
        final size = teams ~/ groups + (g < teams % groups ? 1 : 0);
        total += rr(size);
      }
      final k = groups * qualifiers;
      return total + (k >= 2 ? k - 1 : 0);
  }
}

/// Error de una operación de torneo, con mensaje para el usuario.
class TournamentException implements Exception {
  TournamentException(this.code);
  final String code;
  static TournamentException fromServer(String message) {
    for (final c in ['result_conflict', 'not_tournament_admin', 'duplicate_player', 'not_enough_teams', 'too_many_teams', 'invalid_qualifiers',
        'tournament_started', 'match_not_ready', 'third_set_required', 'match_already_decided', 'invalid_set', 'invalid_sets',
        'unknown_player', 'tournament_not_decided', 'group_too_small', 'not_allowed']) {
      if (message.contains(c)) return TournamentException(c);
    }
    return TournamentException('server');
  }

  String get message => switch (code) {
        'result_conflict' => 'Otra persona acaba de cambiar este partido. Se ha actualizado: revisa el resultado y vuelve a intentarlo.',
        'not_tournament_admin' => 'Solo la organización del torneo puede hacer esto.',
        'duplicate_player' => 'Un jugador no puede estar en dos parejas del mismo torneo.',
        'not_enough_teams' || 'group_too_small' => 'No hay parejas suficientes para este formato.',
        'too_many_teams' => 'Hay más parejas que el máximo permitido.',
        'invalid_qualifiers' => 'Revisa cuántas parejas pasan de cada grupo.',
        'tournament_started' => 'El torneo ya tiene resultados: ya no se pueden cambiar las parejas.',
        'match_not_ready' => 'Este partido aún no tiene las dos parejas.',
        'third_set_required' => 'Empate a sets: añade el tercer set.',
        'match_already_decided' => 'El partido ya estaba decidido en dos sets: quita el tercero.',
        'invalid_set' || 'invalid_sets' => 'Revisa los sets: valen 6-0 a 6-4, 7-5 o 7-6.',
        'unknown_player' => 'Algún jugador ya no existe en Plobby.',
        'tournament_not_decided' => 'Aún no hay campeón: faltan partidos por jugar.',
        'network' => 'Sin conexión. Comprueba tu red e inténtalo de nuevo.',
        _ => 'No se pudo completar. Inténtalo de nuevo.',
      };
  @override
  String toString() => 'TournamentException($code)';
}

/// Validación de un resultado en la app (misma regla que `_t_validate_sets`): devuelve el error o null.
String? validateTournamentSets(List<(int, int)> sets) {
  if (sets.length < 2 || sets.length > 3) return 'Introduce 2 sets (o 3 si hubo empate a sets).';
  var a = 0, b = 0;
  for (var i = 0; i < sets.length; i++) {
    if (a == 2 || b == 2) return 'El partido ya estaba decidido en dos sets: quita el tercero.';
    final (x, y) = sets[i];
    final hi = x > y ? x : y, lo = x > y ? y : x;
    if (!((hi == 6 && lo <= 4) || (hi == 7 && (lo == 5 || lo == 6)))) return 'Set ${i + 1} no válido: vale 6-0 a 6-4, 7-5 o 7-6.';
    if (x > y) { a++; } else { b++; }
  }
  if (a < 2 && b < 2) return 'Empate a sets: añade el tercer set.';
  return null;
}

/// 1 si gana la primera pareja, 2 si gana la segunda (sets ya validados).
int setsWinner(List<(int, int)> sets) => sets.where((s) => s.$1 > s.$2).length >= 2 ? 1 : 2;
