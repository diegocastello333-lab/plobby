import '../../matches/domain/match_lifecycle.dart';
import '../../matches/domain/match_models.dart';

/// PLOBBY MATCH RECAP — modelo PURO (sin Flutter ni red). Se construye SOLO desde un partido confirmado por los
/// dos capitanes y nunca inventa datos: lo que no existe queda en `null` y la plantilla no lo dibuja.
enum RecapTemplate { result, stats, headToHead }
enum RecapFormat { story, feed, square }

extension RecapTemplateX on RecapTemplate {
  String get label => const ['MATCH RESULT', 'MATCH STATS', 'HEAD TO HEAD'][index];
}

extension RecapFormatX on RecapFormat {
  int get width => 1080;
  int get height => const [1920, 1350, 1080][index];
  String get label => const ['Story 9:16', 'Feed 4:5', 'Cuadrado 1:1'][index];
  String get fileTag => const ['story', 'feed', 'square'][index];
}

/// Opciones de privacidad/personalización de la UI. Cambian lo que se dibuja, no los datos del partido.
class RecapOptions {
  const RecapOptions({this.showStats = true, this.showDuration = true, this.showElo = true, this.showClub = true});
  final bool showStats, showDuration, showElo, showClub;
  RecapOptions copyWith({bool? showStats, bool? showDuration, bool? showElo, bool? showClub}) => RecapOptions(
      showStats: showStats ?? this.showStats, showDuration: showDuration ?? this.showDuration, showElo: showElo ?? this.showElo, showClub: showClub ?? this.showClub);
}

class RecapPlayer {
  const RecapPlayer({required this.id, required this.name, this.avatarUrl, this.avatarId});
  final String id, name;
  final String? avatarUrl, avatarId;
  String get first => name.trim().split(RegExp(r'\s+')).first;
  String get initials => name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).map((s) => s[0]).take(2).join().toUpperCase();
}

/// Estadísticas del usuario que comparte (de su perfil). Todas opcionales: solo se muestran las disponibles.
class RecapUserStats {
  const RecapUserStats({this.played, this.winRate, this.streak});
  final int? played, winRate, streak;
}

enum RecapRefusal { notConfirmed, notParticipant, noResult }

class RecapException implements Exception {
  RecapException(this.reason);
  final RecapRefusal reason;
  @override
  String toString() => 'RecapException($reason)';
}

class RecapData {
  const RecapData({required this.matchId, required this.winners, required this.opponents, required this.sets, required this.winnerIsTeam1, required this.playedAt,
      required this.club, required this.isLeague, this.leagueName, this.court, this.durationSeconds, this.eloDelta, this.eloBefore, this.eloAfter, this.stats, this.userWon, this.userName});

  final String matchId, club;
  final List<RecapPlayer> winners, opponents;
  /// Juegos por set, SIEMPRE (ganadores, rivales): primera línea = pareja ganadora.
  final List<(int, int)> sets;
  final bool winnerIsTeam1, isLeague;
  final DateTime playedAt;
  final String? leagueName, court, userName;
  final int? durationSeconds, eloDelta, eloBefore, eloAfter;
  final RecapUserStats? stats;
  final bool? userWon;

  String get typeLabel => isLeague ? 'LIGA' : 'AMISTOSO';
  String get contextLabel => isLeague && leagueName != null ? 'LIGA · ${leagueName!}' : typeLabel;
  int get winnerSets => sets.where((s) => s.$1 > s.$2).length;
  int get loserSets => sets.length - winnerSets;
  bool get hasElo => eloDelta != null;
  bool get hasDuration => durationSeconds != null && durationSeconds! > 0;
  String get courtLabel => (court ?? '').trim();

  /// Únicamente partidos CONFIRMADOS por los dos capitanes y con participación del usuario.
  static bool canShare(LifecycleMatch m, String uid) =>
      m.status == MatchStatus.confirmed && m.bothCaptainsAccepted && m.sets.isNotEmpty && m.player(uid) != null;

  factory RecapData.fromMatch(LifecycleMatch m, String uid, {RecapUserStats? stats}) {
    if (m.status != MatchStatus.confirmed || !m.bothCaptainsAccepted) throw RecapException(RecapRefusal.notConfirmed);
    if (m.sets.isEmpty || m.winnerTeam == null) throw RecapException(RecapRefusal.noResult);
    final me = m.player(uid);
    if (me == null) throw RecapException(RecapRefusal.notParticipant);
    final w = m.winnerTeam!, t1 = w == 1;
    RecapPlayer rp(MatchPlayer p) => RecapPlayer(id: p.id, name: p.name, avatarUrl: p.avatarUrl, avatarId: p.avatarId);
    final win = m.team(w).map(rp).toList(), opp = m.team(w == 1 ? 2 : 1).map(rp).toList();
    final sets = [for (final s in m.sets) t1 ? (s.a, s.b) : (s.b, s.a)];
    final delta = m.eloDelta.containsKey(uid) ? m.eloDelta[uid] : null;
    return RecapData(
      matchId: m.id, winners: win, opponents: opp, sets: sets, winnerIsTeam1: t1, playedAt: m.endedAt ?? m.scheduledAt, club: m.club,
      isLeague: m.type == MatchType.league, leagueName: m.leagueName, court: m.court, durationSeconds: m.durationSeconds,
      eloDelta: delta, eloBefore: delta == null ? null : me.elo, eloAfter: delta == null ? null : me.elo + delta,
      stats: stats, userWon: me.team == w, userName: me.name,
    );
  }
}

/// Snapshot en el MISMO formato que devuelve la función SQL `get_match_recap` (lo usa el mock; el servidor real lo genera él).
Map<String, dynamic> matchServerJson(LifecycleMatch m) => {
      'match_id': m.id, 'status': m.status.db, 'result_version': m.resultVersion,
      'sets': [for (final s in m.sets) [s.a, s.b]], 'winner_team': m.winnerTeam,
      'club': m.club, 'court': m.court, 'played_at': (m.endedAt ?? m.scheduledAt).toIso8601String(), 'duration_seconds': m.durationSeconds,
      'type': m.type == MatchType.league ? 'league' : 'friendly', 'league_id': m.leagueId, 'league_name': m.leagueName,
      'players': [for (final p in m.players) {'user_id': p.id, 'team': p.team, 'is_captain': p.isCaptain, 'elo_delta': m.eloDelta[p.id], 'name': p.name, 'avatar_url': p.avatarUrl, 'avatar_id': p.avatarId}],
    };

/// Reconstruye el modelo de la tarjeta a partir del snapshot guardado en `messages.payload`.
/// `sharerId` = quien envió la tarjeta (su ELO/resultado son los que se destacan).
RecapData recapFromServerJson(Map<String, dynamic> j, {String? sharerId}) {
  final w = (j['winner_team'] as num).toInt(), t1 = w == 1;
  final ps = [for (final p in (j['players'] as List).cast<Map>()) p.cast<String, dynamic>()];
  RecapPlayer rp(Map<String, dynamic> p) => RecapPlayer(id: p['user_id'] as String, name: (p['name'] as String?) ?? '', avatarUrl: p['avatar_url'] as String?, avatarId: p['avatar_id'] as String?);
  final win = [for (final p in ps) if ((p['team'] as num).toInt() == w) rp(p)], opp = [for (final p in ps) if ((p['team'] as num).toInt() != w) rp(p)];
  final sharer = ps.where((p) => p['user_id'] == sharerId).firstOrNull;
  final sets = [for (final s in (j['sets'] as List)) t1 ? ((s as List)[0] as int, s[1] as int) : ((s as List)[1] as int, s[0] as int)];
  return RecapData(
    matchId: j['match_id'] as String, winners: win, opponents: opp, sets: sets, winnerIsTeam1: t1, playedAt: DateTime.parse(j['played_at'] as String),
    club: (j['club'] as String?) ?? '', isLeague: j['type'] == 'league', leagueName: j['league_name'] as String?, court: j['court'] as String?,
    durationSeconds: (j['duration_seconds'] as num?)?.toInt(), eloDelta: (sharer?['elo_delta'] as num?)?.toInt(),
    userWon: sharer == null ? null : (sharer['team'] as num).toInt() == w, userName: sharer?['name'] as String?,
  );
}

String recapDuration(int seconds) {
  final h = seconds ~/ 3600, mn = (seconds ~/ 60) % 60;
  return h > 0 ? '$h h ${mn.toString().padLeft(2, '0')} min' : '$mn min';
}

String recapDate(DateTime d) {
  const meses = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];
  return '${d.day} ${meses[d.month - 1]} ${d.year}';
}

String recapFileName(RecapData d, RecapTemplate t, RecapFormat f) =>
    'plobby-recap-${d.matchId}-${t.name}-${f.fileTag}-${f.width}x${f.height}';
