import 'match_models.dart';

/// Estados del partido (mapean 1:1 a `matches.status` / enum `match_status`). Sustituyen/completan los estados
/// existentes (programado, pendiente, disputado, confirmado) sin duplicarlos.
enum MatchStatus { scheduled, live, pendingResult, pendingConfirmation, disputed, confirmed, cancelled }

extension MatchStatusX on MatchStatus {
  String get db => const ['scheduled', 'live', 'pending_result', 'pending_confirmation', 'disputed', 'confirmed', 'cancelled'][index];
  String get label => const ['Programado', 'En juego', 'Pendiente de resultado', 'Pendiente de confirmación', 'En disputa', 'Confirmado', 'Cancelado'][index];
  /// Se muestra en «Próximos partidos» mientras no esté cerrado.
  bool get isUpcoming => index <= MatchStatus.disputed.index;
  static MatchStatus fromDb(String s) => MatchStatus.values.firstWhere((x) => x.db == s);
}

class MatchPlayer {
  const MatchPlayer({required this.id, required this.name, required this.team, this.isCaptain = false, this.elo = 0, this.level = '', this.avatarUrl, this.avatarId});
  final String id, name, level;
  final int team;            // 1 | 2
  final bool isCaptain;
  final int elo;
  final String? avatarUrl, avatarId;
}

class ResultVersion {
  const ResultVersion({required this.version, required this.sets, required this.proposedBy});
  final int version;
  final List<SetScore> sets;
  final String proposedBy;
}

class Acceptance {
  const Acceptance({required this.userId, required this.team, required this.version, required this.accepted, this.reason});
  final String userId;
  final int team, version;
  final bool accepted;
  final String? reason;
}

class MatchEvent {
  const MatchEvent({required this.actorId, required this.kind, required this.text, required this.at});
  final String? actorId; final String kind, text; final DateTime at;
}

/// Partido con todo su ciclo de vida. Los instantes (`startedAt`, `endedAt`) son HORA DEL SERVIDOR.
class LifecycleMatch {
  const LifecycleMatch({required this.id, required this.type, this.leagueId, this.leagueName, required this.scheduledAt, required this.club, this.court,
      required this.status, required this.players, required this.createdBy, this.startedAt, this.endedAt, this.durationSeconds, this.startedBy,
      this.resultVersion = 0, this.sets = const [], this.acceptances = const [], this.rejectionReason, this.events = const [], this.eloDelta = const {}});
  final String id, club, createdBy;
  final MatchType type;
  final String? leagueId, leagueName, court, startedBy, rejectionReason;
  final DateTime scheduledAt;
  final MatchStatus status;
  final List<MatchPlayer> players;
  final DateTime? startedAt, endedAt;
  final int? durationSeconds;
  final int resultVersion;
  final List<SetScore> sets;                 // versión vigente del resultado
  final List<Acceptance> acceptances;        // de TODAS las versiones; solo cuentan las de [resultVersion]
  final List<MatchEvent> events;
  final Map<String, int> eloDelta;           // solo con partido confirmado (lo escribe el servidor)

  List<MatchPlayer> team(int t) => players.where((p) => p.team == t).toList();
  MatchPlayer? captainOf(int t) { for (final p in players) { if (p.team == t && p.isCaptain) return p; } return null; }
  MatchPlayer? player(String id) { for (final p in players) { if (p.id == id) return p; } return null; }
  int? get winnerTeam => sets.isEmpty ? null : winnerOfSets(sets);

  /// Capitanes que han aceptado la versión VIGENTE (una aceptación de otra versión no cuenta).
  Set<int> get acceptedTeams => {for (final a in acceptances) if (a.accepted && a.version == resultVersion && player(a.userId)?.isCaptain == true) a.team};
  bool get bothCaptainsAccepted => acceptedTeams.containsAll({1, 2});

  LifecycleMatch copyWith({MatchStatus? status, List<MatchPlayer>? players, DateTime? scheduledAt, String? club, String? court, DateTime? startedAt, DateTime? endedAt, int? durationSeconds,
          String? startedBy, int? resultVersion, List<SetScore>? sets, List<Acceptance>? acceptances, String? rejectionReason, bool clearRejection = false, List<MatchEvent>? events, Map<String, int>? eloDelta}) =>
      LifecycleMatch(id: id, type: type, leagueId: leagueId, leagueName: leagueName, scheduledAt: scheduledAt ?? this.scheduledAt, club: club ?? this.club, court: court ?? this.court,
          status: status ?? this.status, players: players ?? this.players, createdBy: createdBy, startedAt: startedAt ?? this.startedAt, endedAt: endedAt ?? this.endedAt,
          durationSeconds: durationSeconds ?? this.durationSeconds, startedBy: startedBy ?? this.startedBy, resultVersion: resultVersion ?? this.resultVersion, sets: sets ?? this.sets,
          acceptances: acceptances ?? this.acceptances, rejectionReason: clearRejection ? null : (rejectionReason ?? this.rejectionReason), events: events ?? this.events, eloDelta: eloDelta ?? this.eloDelta);
}

/// Ganador de una lista de sets ya válida (1 = equipo 1).
int winnerOfSets(List<SetScore> s) => s.where((x) => x.a > x.b).length > s.where((x) => x.b > x.a).length ? 1 : 2;

class SetsCheck {
  const SetsCheck.ok(this.sets, this.winner) : error = null;
  const SetsCheck.err(this.error) : sets = const [], winner = null;
  final List<SetScore> sets; final int? winner; final String? error;
  bool get valid => error == null;
}

/// Formato al mejor de 3 sets (mismo criterio que la función SQL `_validate_sets`).
SetsCheck validateSets(List<SetScore> raw) {
  if (raw.length < 2) return const SetsCheck.err('Introduce al menos dos sets.');
  if (raw.length > 3) return const SetsCheck.err('Como máximo tres sets.');
  for (var i = 0; i < raw.length; i++) { if (!isValidSet(raw[i].a, raw[i].b)) return SetsCheck.err('Set ${i + 1} no válido. Ejemplos: 6-3, 7-5, 7-6.'); }
  // El partido termina en cuanto una pareja gana 2 sets: no puede haber sets después (6-4 6-3 3-6 no es válido).
  var a = 0, b = 0;
  for (var i = 0; i < raw.length; i++) {
    if (a == 2 || b == 2) return const SetsCheck.err('Con 2-0 el partido termina: quita el tercer set.');
    raw[i].a > raw[i].b ? a++ : b++;
  }
  if (a < 2 && b < 2) return const SetsCheck.err('Con 1-1 hay que jugar el tercer set.');
  return SetsCheck.ok(raw, a > b ? 1 : 2);
}

/// Reloj de servidor: `offset = serverNow - deviceNow`, medido con `server_time()`. El cronómetro NUNCA usa un contador local.
class ServerClock {
  ServerClock([this.offset = Duration.zero, DateTime Function()? device]) : _device = device ?? DateTime.now;
  final Duration offset; final DateTime Function() _device;
  DateTime now() => _device().add(offset);
  factory ServerClock.fromServerSample(DateTime serverNow, DateTime deviceBefore, DateTime deviceAfter) {
    final mid = deviceBefore.add(deviceAfter.difference(deviceBefore) ~/ 2);      // compensa la latencia de ida y vuelta
    return ServerClock(serverNow.difference(mid));
  }
}

/// Tiempo transcurrido: siempre `serverNow - startedAt` (igual en los cuatro móviles, sobrevive a cerrar la app).
Duration elapsedOf(LifecycleMatch m, ServerClock c) => m.startedAt == null ? Duration.zero : (m.status == MatchStatus.live ? c.now().difference(m.startedAt!) : Duration(seconds: m.durationSeconds ?? 0));
String formatElapsed(Duration d) { final s = d.inSeconds < 0 ? 0 : d.inSeconds; String p(int n) => n.toString().padLeft(2, '0'); return (s >= 3600 ? '${p(s ~/ 3600)}:' : '') + '${p(s ~/ 60 % 60)}:${p(s % 60)}'; }

/// Permisos para la UI (el servidor repite las mismas comprobaciones en RPC/RLS; esto solo decide qué botones mostrar).
class MatchPerms {
  const MatchPerms(this.m, this.uid);
  final LifecycleMatch m; final String uid;
  bool get isParticipant => m.player(uid) != null;
  bool get canView => isParticipant;
  bool get canEdit => uid == m.createdBy && m.status == MatchStatus.scheduled;
  bool get canDelete => canEdit;
  bool get canStart => isParticipant && m.status == MatchStatus.scheduled;
  bool get canFinish => isParticipant && m.status == MatchStatus.live;
  bool get canSubmitResult => isParticipant && const [MatchStatus.pendingResult, MatchStatus.pendingConfirmation, MatchStatus.disputed].contains(m.status);
  bool get canConfirm => m.player(uid)?.isCaptain == true && m.status == MatchStatus.pendingConfirmation && !m.acceptances.any((a) => a.userId == uid && a.version == m.resultVersion);
}

/// Regla de liga (valor por defecto; ajustable por liga en backend): no se cambian jugadores ni se elimina a menos de 2 h del inicio.
const leagueLockWindow = Duration(hours: 2);
bool leagueLocked(LifecycleMatch m, DateTime serverNow) => m.type == MatchType.league && m.scheduledAt.difference(serverNow) < leagueLockWindow;
