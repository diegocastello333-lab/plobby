import 'package:flutter/foundation.dart';

/// Visibilidad de la liga (↔ `leagues.visibility`).
/// public: cualquiera entra · private: con código o invitación · club: se solicita acceso y lo aprueba un gestor.
enum LeagueVisibility { public, private, club }

/// Rol en la liga (↔ `league_members.role`). Organizador y admin de club son «gestores».
enum LeagueRole { organizer, admin, player }

/// Estado de la temporada (↔ función SQL `league_status`): inscripción abierta, en curso o cerrada.
enum LeagueStatus { open, running, ended }

extension LeagueVisibilityX on LeagueVisibility {
  String get label => const ['Pública', 'Privada', 'Club'][index];
  String get description => const ['Cualquier jugador puede unirse.', 'Solo con invitación o código.', 'Los socios solicitan acceso y lo apruebas tú.'][index];
  static LeagueVisibility fromDb(String? s) => LeagueVisibility.values.asNameMap()[s] ?? LeagueVisibility.private;
}

extension LeagueRoleX on LeagueRole {
  bool get isManager => this != LeagueRole.player;
  String get label => const ['Organizador', 'Admin del club', 'Jugador'][index];
  static LeagueRole? fromDb(String? s) => LeagueRole.values.asNameMap()[s];
}

extension LeagueStatusX on LeagueStatus {
  String get label => const ['Inscripción abierta', 'En curso', 'Cerrada'][index];
  static LeagueStatus fromDb(String? s) => LeagueStatus.values.asNameMap()[s] ?? LeagueStatus.running;
}

/// Portadas disponibles (patrones dibujados, sin imágenes externas). Se guardan por id en `leagues.cover`.
const leagueCovers = ['lines', 'dots', 'grid', 'waves', 'court', 'diagonal'];

/// Fila de «Mis ligas» (RPC `my_leagues`).
@immutable
class LeagueSummary {
  const LeagueSummary({required this.id, required this.name, required this.visibility, this.cover = 'lines', this.location = '', this.season = '01',
      this.startsOn, this.endsOn, this.status = LeagueStatus.running, this.role = LeagueRole.player, this.members = 1, this.myRank, this.myPoints = 0,
      this.myPlayed = 0, this.myWins = 0, this.matchesDone = 0, this.matchesTotal = 0, this.organizerName = ''});
  final String id, name, cover, location, season, organizerName;
  final LeagueVisibility visibility;
  final DateTime? startsOn, endsOn;
  final LeagueStatus status;
  final LeagueRole role;
  final int members, myPoints, myPlayed, myWins, matchesDone, matchesTotal;
  final int? myRank;
  double get progress => matchesTotal == 0 ? 0 : (matchesDone / matchesTotal).clamp(0, 1).toDouble();
}

/// Resultado de «Descubrir ligas» (RPC `discover_leagues`).
@immutable
class DiscoverLeague {
  const DiscoverLeague({required this.id, required this.name, required this.visibility, this.cover = 'lines', this.location = '', this.levelMin = '', this.levelMax = '',
      this.season = '01', this.startsOn, this.endsOn, this.status = LeagueStatus.open, this.organizerName = '', this.members = 0, this.maxPlayers = 16,
      this.friendsIn = 0, this.friendIds = const [], this.invited = false, this.requestPending = false});
  final String id, name, cover, location, levelMin, levelMax, season, organizerName;
  final LeagueVisibility visibility;
  final DateTime? startsOn, endsOn;
  final LeagueStatus status;
  final int members, maxPlayers, friendsIn;
  final List<String> friendIds;
  final bool invited, requestPending;
  bool get full => members >= maxPlayers;
  String get levelLabel => levelMin == levelMax ? levelMin : '$levelMin – $levelMax';
}

/// Ficha completa de la liga (`leagues` + mi rol).
@immutable
class LeagueDetail {
  const LeagueDetail({required this.id, required this.name, this.description = '', this.visibility = LeagueVisibility.private, this.cover = 'lines', this.location = '',
      this.levelMin = 'Iniciación', this.levelMax = 'Avanzado', this.season = '01', this.startsOn, this.endsOn, this.status = LeagueStatus.running,
      this.minPlayers = 2, this.maxPlayers = 16, this.matchesPerPlayer = 10, this.rules = const LeagueRules(), this.challengesEnabled = true,
      this.createdBy, this.organizerName = '', this.myRole});
  final String id, name, description, cover, location, levelMin, levelMax, season, organizerName;
  final LeagueVisibility visibility;
  final DateTime? startsOn, endsOn;
  final LeagueStatus status;
  final int minPlayers, maxPlayers, matchesPerPlayer;
  final LeagueRules rules;
  final bool challengesEnabled;
  final String? createdBy;
  final LeagueRole? myRole;   // null = no soy miembro
  bool get isMember => myRole != null;
  bool get canManage => myRole?.isManager ?? false;
}

/// Reglas de puntuación (S1 en la migración): victoria, derrota y bonus por ganar sin ceder set.
@immutable
class LeagueRules {
  const LeagueRules({this.pointsWin = 3, this.pointsLoss = 1, this.bonusEnabled = true});
  final int pointsWin, pointsLoss;
  final bool bonusEnabled;
}

/// Fila de la clasificación (RPC `league_standings`).
@immutable
class StandingRow {
  const StandingRow({required this.userId, required this.name, this.username = '', this.avatarUrl, this.avatarId, this.elo = 1200, this.role = LeagueRole.player,
      this.played = 0, this.wins = 0, this.bonus = 0, this.points = 0, this.rank = 1});
  final String userId, name, username;
  final String? avatarUrl, avatarId;
  final int elo, played, wins, bonus, points, rank;
  final LeagueRole role;
  int get losses => played - wins;
  int get winPct => played == 0 ? 0 : (wins * 100 / played).round();
}

/// Solicitud de acceso pendiente (ligas de club).
@immutable
class JoinRequest {
  const JoinRequest({required this.id, required this.userId, required this.name, this.avatarUrl, this.message = '', required this.createdAt});
  final String id, userId, name, message;
  final String? avatarUrl;
  final DateTime createdAt;
}

enum JoinOutcome { joined, requested, alreadyMember }

class LeagueException implements Exception {
  LeagueException(this.code);
  final String code;
  /// Mensaje en español para cada error de las RPC de liga.
  String get message => switch (code) {
        'invite_code_required' => 'Esta liga es privada: necesitas un código o una invitación.',
        'invalid_invite_code' => 'Ese código no corresponde a ninguna liga.',
        'league_full' => 'La liga está completa.',
        'league_ended' => 'La temporada ya está cerrada.',
        'not_league_manager' => 'Solo el organizador o el administrador pueden hacer esto.',
        'organizer_cannot_leave' => 'Eres el organizador: no puedes salir mientras haya otros jugadores.',
        'cannot_remove_organizer' => 'No se puede quitar al organizador.',
        'invalid_league_name' => 'Escribe un nombre de entre 3 y 40 caracteres.',
        'invalid_league_dates' => 'La fecha de fin debe ser posterior a la de inicio.',
        'max_below_members' => 'El máximo no puede ser menor que los jugadores actuales.',
        'network' => 'Parece que no hay conexión. Revisa tu red e inténtalo de nuevo.',
        _ => 'No se pudo completar la acción. Inténtalo de nuevo.',
      };
  @override
  String toString() => 'LeagueException($code)';
}

// ────────────────────────────────────────────────────────────────────────────────
// Clasificación (misma fórmula que la función SQL `league_standings`). La usa el repositorio mock y los tests;
// con Supabase el cálculo lo hace siempre el servidor.
// ────────────────────────────────────────────────────────────────────────────────

/// Resultado de un partido de liga ya CONFIRMADO: ids por equipo y sets (juegos equipo 1, equipo 2).
@immutable
class LeagueMatchResult {
  const LeagueMatchResult({required this.team1, required this.team2, required this.sets, this.confirmed = true});
  final List<String> team1, team2;
  final List<(int, int)> sets;
  final bool confirmed;
}

/// Miembro para el cálculo (datos de perfil que se copian a la fila).
@immutable
class LeagueMemberRef {
  const LeagueMemberRef(this.userId, this.name, {this.elo = 1200, this.role = LeagueRole.player, this.avatarUrl, this.avatarId});
  final String userId, name;
  final int elo;
  final LeagueRole role;
  final String? avatarUrl, avatarId;
}

/// Puntos = victorias·pointsWin + derrotas·pointsLoss + bonus (ganar sin ceder set, si está activo).
/// Orden: puntos, victorias, ELO (desc). Empates comparten puesto (rank estándar: 1, 1, 3…).
/// Ignora partidos no confirmados, empatados en sets o de jugadores que no son miembros.
List<StandingRow> computeStandings(List<LeagueMemberRef> members, List<LeagueMatchResult> matches, LeagueRules rules) {
  final played = <String, int>{}, wins = <String, int>{}, bonus = <String, int>{};
  final ids = {for (final m in members) m.userId};
  for (final m in matches) {
    if (!m.confirmed) continue;
    final t1 = m.sets.where((s) => s.$1 > s.$2).length, t2 = m.sets.where((s) => s.$2 > s.$1).length;
    if (t1 == t2) continue;
    final clean = t1 == 0 || t2 == 0;
    final winners = t1 > t2 ? m.team1 : m.team2;
    for (final u in [...m.team1, ...m.team2]) {
      if (!ids.contains(u)) continue;
      played[u] = (played[u] ?? 0) + 1;
      if (winners.contains(u)) {
        wins[u] = (wins[u] ?? 0) + 1;
        if (clean) bonus[u] = (bonus[u] ?? 0) + 1;
      }
    }
  }
  final rows = [
    for (final m in members)
      () {
        final p = played[m.userId] ?? 0, w = wins[m.userId] ?? 0, b = rules.bonusEnabled ? (bonus[m.userId] ?? 0) : 0;
        return StandingRow(userId: m.userId, name: m.name, avatarUrl: m.avatarUrl, avatarId: m.avatarId, elo: m.elo, role: m.role,
            played: p, wins: w, bonus: b, points: w * rules.pointsWin + (p - w) * rules.pointsLoss + b);
      }(),
  ];
  int cmp(StandingRow a, StandingRow b) => b.points != a.points ? b.points - a.points : b.wins != a.wins ? b.wins - a.wins : b.elo - a.elo;
  rows.sort((a, b) { final c = cmp(a, b); return c != 0 ? c : a.name.compareTo(b.name); });
  final out = <StandingRow>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final rank = i > 0 && cmp(rows[i - 1], r) == 0 ? out[i - 1].rank : i + 1;
    out.add(StandingRow(userId: r.userId, name: r.name, username: r.username, avatarUrl: r.avatarUrl, avatarId: r.avatarId, elo: r.elo, role: r.role,
        played: r.played, wins: r.wins, bonus: r.bonus, points: r.points, rank: rank));
  }
  return out;
}

// ────────────────────────────────────────────────────────────────────────────────
// Creación de liga (asistente de 5 pasos del prototipo)
// ────────────────────────────────────────────────────────────────────────────────

@immutable
class LeagueDraft {
  const LeagueDraft({this.name = '', this.description = '', this.cover = 'lines', this.visibility = LeagueVisibility.private, this.invited = const [],
      this.minPlayers = 6, this.maxPlayers = 16, this.format = 'individual', this.matchesPerPlayer = 10, this.pointsWin = 3, this.bonus = true,
      this.challenges = true, required this.startsOn, required this.endsOn, this.levelMin = 'Iniciación', this.levelMax = 'Avanzado', this.location = 'Madrid · Centro'});
  final String name, description, cover, format, levelMin, levelMax, location;
  final LeagueVisibility visibility;
  final List<String> invited;
  final int minPlayers, maxPlayers, matchesPerPlayer, pointsWin;
  final bool bonus, challenges;
  final DateTime startsOn, endsOn;

  LeagueDraft copyWith({String? name, String? description, String? cover, LeagueVisibility? visibility, List<String>? invited, int? minPlayers, int? maxPlayers,
          String? format, int? matchesPerPlayer, int? pointsWin, bool? bonus, bool? challenges, DateTime? startsOn, DateTime? endsOn, String? levelMin, String? levelMax, String? location}) =>
      LeagueDraft(name: name ?? this.name, description: description ?? this.description, cover: cover ?? this.cover, visibility: visibility ?? this.visibility,
          invited: invited ?? this.invited, minPlayers: minPlayers ?? this.minPlayers, maxPlayers: maxPlayers ?? this.maxPlayers, format: format ?? this.format,
          matchesPerPlayer: matchesPerPlayer ?? this.matchesPerPlayer, pointsWin: pointsWin ?? this.pointsWin, bonus: bonus ?? this.bonus,
          challenges: challenges ?? this.challenges, startsOn: startsOn ?? this.startsOn, endsOn: endsOn ?? this.endsOn, levelMin: levelMin ?? this.levelMin,
          levelMax: levelMax ?? this.levelMax, location: location ?? this.location);
}

const leagueLevels = ['Iniciación', 'Intermedio', 'Avanzado'];

/// Validación de cada paso (pura; el servidor repite las mismas reglas en `create_league`). Devuelve campo → mensaje.
Map<String, String> validateLeagueStep(LeagueDraft d, int step) {
  final e = <String, String>{};
  if (step == 1 || step == 5) {
    final n = d.name.trim().length;
    if (n < 3) e['name'] = 'Escribe un nombre de al menos 3 caracteres.';
    if (n > 40) e['name'] = 'El nombre no puede superar 40 caracteres.';
    if (d.description.trim().length > 180) e['description'] = 'La descripción no puede superar 180 caracteres.';
  }
  if ((step == 2 || step == 5) && d.minPlayers > d.maxPlayers) e['players'] = 'El máximo no puede ser menor que el mínimo.';
  if (step == 4 || step == 5) {
    if (!d.endsOn.isAfter(d.startsOn)) e['dates'] = 'La fecha de fin debe ser posterior a la de inicio.';
    if (leagueLevels.indexOf(d.levelMin) > leagueLevels.indexOf(d.levelMax)) e['level'] = 'El nivel mínimo no puede ser mayor que el máximo.';
  }
  return e;
}

/// Total previsto de partidos de la temporada: cada partido reúne a 4 jugadores (misma fórmula que `my_leagues`).
int plannedMatches(int members, int matchesPerPlayer) => (members * matchesPerPlayer / 4).ceil();
