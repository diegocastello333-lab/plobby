import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Modelos de Head to Head, Friends Ranking, Plobby Wrapped, logros y niveles.
///
/// Todo sale de la MISMA fuente: una fila por jugador y partido confirmado (`player_match_stats` en Supabase,
/// [StatRow] aquí). [GamificationEngine] replica en Dart las reglas del SQL (`20261126b_gamification.sql`); lo usan el
/// modo demo y los tests, para que las reglas estén comprobadas en los dos lados.

@immutable
class GPlayer {
  const GPlayer({required this.id, required this.name, this.username = '', this.avatarUrl});
  final String id, name, username;
  final String? avatarUrl;
  String get first => name.trim().split(RegExp(r'\s+')).first;
  String get initials {
    final w = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    return w.isEmpty ? '?' : w.take(2).map((s) => s[0]).join().toUpperCase();
  }
  factory GPlayer.fromJson(Map<String, dynamic> j, {String? idKey}) => GPlayer(
      id: (j[idKey ?? 'user_id'] ?? j['id'] ?? '') as String, name: (j['name'] ?? j['display_name'] ?? '') as String,
      username: (j['username'] ?? '') as String, avatarUrl: j['avatar_url'] as String?);
}

/// Una fila por jugador y partido confirmado (desde el punto de vista de ese jugador).
@immutable
class StatRow {
  const StatRow({required this.matchId, required this.userId, required this.playedAt, required this.team, required this.won,
      required this.sets, this.partnerId, this.rival1Id, this.rival2Id, this.isLeague = false});
  final String matchId, userId;
  final DateTime playedAt;
  final int team;
  final bool won, isLeague;
  /// Juegos por set (míos, suyos).
  final List<(int, int)> sets;
  final String? partnerId, rival1Id, rival2Id;
  int get setsWon => sets.where((s) => s.$1 > s.$2).length;
  int get setsLost => sets.where((s) => s.$2 > s.$1).length;
  int get gamesWon => sets.fold(0, (a, s) => a + s.$1);
  int get gamesLost => sets.fold(0, (a, s) => a + s.$2);
  List<String> get rivals => [if (rival1Id != null) rival1Id!, if (rival2Id != null) rival2Id!];
}

@immutable
class MonthPoint {
  const MonthPoint(this.month, this.played, this.winRate);
  final DateTime month;
  final int played;
  final int? winRate;
}

/// Estadísticas generales de un jugador (todas sus partidas confirmadas).
@immutable
class PlayerCard {
  const PlayerCard({required this.player, this.elo, this.level = 1, required this.played, required this.wins, required this.losses,
      required this.winRate, required this.setsWon, required this.setsLost, required this.bestStreak, required this.currentStreak,
      this.form = '', this.monthly = const []});
  final GPlayer player;
  final int? elo;
  final int level, played, wins, losses, winRate, setsWon, setsLost, bestStreak;
  /// > 0: victorias seguidas; < 0: derrotas seguidas; 0: sin partidos.
  final int currentStreak;
  /// Últimos resultados, el más reciente primero: «WWLWL».
  final String form;
  final List<MonthPoint> monthly;
  int get setDiff => setsWon - setsLost;

  factory PlayerCard.fromJson(Map<String, dynamic> j) => PlayerCard(
        player: GPlayer.fromJson(j), elo: (j['elo'] as num?)?.toInt(), level: ((j['level'] ?? 1) as num).toInt(),
        played: _i(j['played']), wins: _i(j['wins']), losses: _i(j['losses']), winRate: _i(j['win_rate']),
        setsWon: _i(j['sets_won']), setsLost: _i(j['sets_lost']), bestStreak: _i(j['best_streak']), currentStreak: _i(j['current_streak']),
        form: (j['form'] ?? '') as String,
        monthly: [for (final m in (j['monthly'] as List? ?? const []).cast<Map<String, dynamic>>())
          MonthPoint(DateTime.parse('${m['month']}-01'), _i(m['played']), (m['win_rate'] as num?)?.toInt())]);
}

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

@immutable
class DirectMatch {
  const DirectMatch({required this.matchId, required this.playedAt, required this.won, required this.sets, this.myPartner, this.theirPartner});
  final String matchId;
  final DateTime playedAt;
  final bool won;
  final List<(int, int)> sets;
  final String? myPartner, theirPartner;
  String get score => sets.map((s) => '${s.$1}-${s.$2}').join('  ');
}

enum H2HLeader { me, other, even, unknown }

/// Conclusión de un Head to Head. Nunca se inventa un ganador: sin datos suficientes es [H2HLeader.unknown].
@immutable
class H2HVerdict {
  const H2HVerdict(this.leader, this.title, this.detail);
  final H2HLeader leader;
  final String title, detail;
}

/// Fila de comparación: valor de cada uno y quién lidera (null = empate o no comparable).
@immutable
class H2HStat {
  const H2HStat(this.label, this.mine, this.theirs, this.mineText, this.theirsText, {this.higherIsBetter = true});
  final String label, mineText, theirsText;
  final num mine, theirs;
  final bool higherIsBetter;
  H2HLeader get leader => mine == theirs ? H2HLeader.even : ((mine > theirs) == higherIsBetter ? H2HLeader.me : H2HLeader.other);
  /// Fracción de la barra para «mí» (0..1). Valores negativos (diferencias) se desplazan para poder compararse.
  double get myShare {
    final shift = math.min(0, math.min(mine, theirs)).abs();
    final a = mine + shift, b = theirs + shift;
    return a + b == 0 ? .5 : (a / (a + b)).toDouble();
  }
}

@immutable
class H2HData {
  const H2HData({required this.me, required this.other, required this.directTotal, required this.myWins, required this.theirWins,
      this.lastAt, this.matches = const [], this.togetherTotal = 0, this.togetherWins = 0});
  final PlayerCard me, other;
  /// Enfrentamientos directos: partidos en los que jugaron en equipos CONTRARIOS.
  final int directTotal, myWins, theirWins;
  final DateTime? lastAt;
  final List<DirectMatch> matches;   // el más reciente primero
  /// Partidos jugados como pareja (no cuentan como enfrentamientos).
  final int togetherTotal, togetherWins;

  /// Saldo acumulado del cara a cara, del más antiguo al más reciente (+1 si gano yo, −1 si gana el otro).
  List<int> get balance {
    var acc = 0;
    return [for (final m in matches.reversed) acc += m.won ? 1 : -1];
  }

  List<H2HStat> get stats => [
        H2HStat('Partidos', me.played, other.played, '${me.played}', '${other.played}'),
        H2HStat('Victorias', me.wins, other.wins, '${me.wins}', '${other.wins}'),
        H2HStat('% victorias', me.winRate, other.winRate, '${me.winRate}%', '${other.winRate}%'),
        H2HStat('Diferencia de sets', me.setDiff, other.setDiff, _signed(me.setDiff), _signed(other.setDiff)),
        H2HStat('Mejor racha', me.bestStreak, other.bestStreak, '${me.bestStreak}', '${other.bestStreak}'),
        if (me.elo != null && other.elo != null) H2HStat('ELO', me.elo!, other.elo!, '${me.elo}', '${other.elo}'),
      ];

  H2HVerdict get verdict {
    if (directTotal >= 2 && myWins != theirWins) {
      final mine = myWins > theirWins;
      return H2HVerdict(mine ? H2HLeader.me : H2HLeader.other, '${mine ? me.player.first : other.player.first} domina el cara a cara',
          '${math.max(myWins, theirWins)}-${math.min(myWins, theirWins)} en $directTotal enfrentamientos directos');
    }
    if (directTotal >= 2) return H2HVerdict(H2HLeader.even, 'Empate en el cara a cara', '$myWins-$theirWins en $directTotal enfrentamientos');
    if (me.played >= 5 && other.played >= 5 && (me.winRate - other.winRate).abs() >= 10) {
      final mine = me.winRate > other.winRate;
      return H2HVerdict(mine ? H2HLeader.me : H2HLeader.other, 'Mejor momento: ${mine ? me.player.first : other.player.first}',
          'Más % de victorias en general. Aún ${directTotal == 0 ? 'no se han enfrentado' : 'solo hay 1 enfrentamiento directo'}.');
    }
    return const H2HVerdict(H2HLeader.unknown, 'Todavía no hay un dominador', 'Faltan partidos para sacar conclusiones. ¡Organizad un partido!');
  }

  factory H2HData.fromJson(Map<String, dynamic> j) {
    final d = (j['direct'] as Map?)?.cast<String, dynamic>() ?? const {};
    final t = (j['together'] as Map?)?.cast<String, dynamic>() ?? const {};
    return H2HData(
      me: PlayerCard.fromJson((j['me'] as Map).cast<String, dynamic>()), other: PlayerCard.fromJson((j['other'] as Map).cast<String, dynamic>()),
      directTotal: _i(d['total']), myWins: _i(d['my_wins']), theirWins: _i(d['their_wins']),
      lastAt: d['last_at'] == null ? null : DateTime.parse(d['last_at'] as String).toLocal(),
      matches: [for (final m in (d['matches'] as List? ?? const []).cast<Map<String, dynamic>>())
        DirectMatch(matchId: m['match_id'] as String, playedAt: DateTime.parse(m['played_at'] as String).toLocal(), won: m['won'] as bool,
            sets: _sets(m['sets']), myPartner: m['my_partner'] as String?, theirPartner: m['their_partner'] as String?)],
      togetherTotal: _i(t['total']), togetherWins: _i(t['wins']),
    );
  }
}

String _signed(int v) => v > 0 ? '+$v' : '$v';
List<(int, int)> _sets(Object? v) => [for (final s in (v as List? ?? const []).cast<List>()) ((s[0] as num).toInt(), (s[1] as num).toInt())];

// ───────────────────────────── Ranking ─────────────────────────────

enum RankPeriod {
  week('Semana', 'semanal'), month('Mes', 'mensual'), year('Año', 'anual'), all('Histórico', 'histórico');
  const RankPeriod(this.label, this.adjective);
  final String label, adjective;
}

enum RankMetric {
  wins('Victorias'), rate('% victorias'), activity('Actividad');
  const RankMetric(this.label);
  final String label;
}

@immutable
class RankRow {
  const RankRow({required this.player, required this.wins, required this.losses, required this.played, required this.winRate,
      required this.posWins, this.posRate, required this.posActivity, this.level = 1});
  final GPlayer player;
  final int wins, losses, played, winRate, posWins, posActivity, level;
  /// null = no llega al mínimo de partidos del ranking de %.
  final int? posRate;
  int? pos(RankMetric m) => switch (m) { RankMetric.wins => posWins, RankMetric.rate => posRate, RankMetric.activity => posActivity };
  factory RankRow.fromJson(Map<String, dynamic> j) => RankRow(player: GPlayer.fromJson(j), wins: _i(j['wins']), losses: _i(j['losses']),
      played: _i(j['played']), winRate: _i(j['win_rate']), posWins: _i(j['pos_wins']), posRate: (j['pos_rate'] as num?)?.toInt(),
      posActivity: _i(j['pos_activity']), level: ((j['level'] ?? 1) as num).toInt());
}

@immutable
class RankingData {
  const RankingData({required this.period, required this.offset, required this.start, required this.end, required this.closed,
      required this.minMatches, required this.rows, required this.previous, required this.meId});
  final RankPeriod period;
  final int offset, minMatches;
  final DateTime start, end;
  final bool closed;
  final List<RankRow> rows, previous;
  final String meId;

  /// Clasificación principal de una métrica (ordenada). En % solo quien llega al mínimo de partidos.
  List<RankRow> ranked(RankMetric m) {
    final list = rows.where((r) => r.pos(m) != null).toList()
      ..sort((a, b) => a.pos(m)!.compareTo(b.pos(m)!) != 0 ? a.pos(m)!.compareTo(b.pos(m)!) : a.player.name.compareTo(b.player.name));
    return list;
  }

  /// Sección secundaria del ranking de %: con partidos pero por debajo del mínimo.
  List<RankRow> belowMinimum(RankMetric m) => m != RankMetric.rate ? const [] :
      (rows.where((r) => r.posRate == null && r.played > 0).toList()..sort((a, b) => b.played.compareTo(a.played)));

  /// Puestos ganados (+) o perdidos (−) respecto al periodo anterior; null si no se puede comparar.
  int? movement(String userId, RankMetric m) {
    final now = rows.where((r) => r.player.id == userId).firstOrNull?.pos(m);
    final before = previous.where((r) => r.player.id == userId).firstOrNull;
    if (now == null || before == null || before.played == 0) return null;
    final b = before.pos(m);
    return b == null ? null : b - now;
  }

  RankRow? get me => rows.where((r) => r.player.id == meId).firstOrNull;
  bool get anyActivity => rows.any((r) => r.played > 0);

  factory RankingData.fromJson(Map<String, dynamic> j, String meId) => RankingData(
        period: RankPeriod.values.byName(j['period'] as String), offset: _i(j['offset']),
        start: DateTime.parse(j['starts_on'] as String), end: DateTime.parse(j['ends_on'] as String), closed: j['closed'] == true,
        minMatches: _i(j['min_matches']),
        rows: [for (final r in (j['rows'] as List? ?? const []).cast<Map<String, dynamic>>()) RankRow.fromJson(r)],
        previous: [for (final r in (j['previous'] as List? ?? const []).cast<Map<String, dynamic>>()) RankRow.fromJson(r)],
        meId: (j['me'] as String?) ?? meId,
      );
}

// ───────────────────────────── Wrapped ─────────────────────────────

enum WrappedKind { month, year }

@immutable
class WrappedPeriod {
  const WrappedPeriod(this.kind, this.start, this.played, this.inProgress);
  final WrappedKind kind;
  final DateTime start;
  final int played;
  final bool inProgress;
  /// «Nuevo» durante los primeros 7 días tras cerrarse el mes.
  bool isNew(DateTime now) => !inProgress && kind == WrappedKind.month && now.difference(DateTime(start.year, start.month + 1)).inDays < 7;
  String get label => kind == WrappedKind.year ? '${start.year}' : '${monthName(start.month)} ${start.year}';
}

const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos'];
String monthName(int m) => _months[m - 1];
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

@immutable
class WrappedPerson {
  const WrappedPerson(this.player, this.played, this.wins);
  final GPlayer player;
  final int played, wins;
  int get winRate => played == 0 ? 0 : (100 * wins / played).round();
}

@immutable
class WrappedBucket {
  const WrappedBucket(this.start, this.played, this.wins);
  final DateTime start;
  final int played, wins;
  int get winRate => played == 0 ? 0 : (100 * wins / played).round();
}

@immutable
class WrappedData {
  const WrappedData({required this.kind, required this.start, required this.inProgress, required this.name, required this.played,
      required this.wins, required this.losses, this.winRate, required this.setsPlayed, required this.setsWon, required this.bestStreak,
      required this.prevPlayed, this.prevWinRate, this.buckets = const [], this.weekdays = const [], this.topPartner, this.topRival,
      this.bestRival, this.topFriend, this.memorable, this.recordElo, this.isRecord = false, this.achievements = const []});
  final WrappedKind kind;
  final DateTime start;
  final bool inProgress, isRecord;
  final String name;
  final int played, wins, losses, setsPlayed, setsWon, bestStreak, prevPlayed;
  final int? winRate, prevWinRate, recordElo;
  final List<WrappedBucket> buckets;
  /// (día ISO 1 = lunes, partidos), de más a menos.
  final List<(int, int)> weekdays;
  final WrappedPerson? topPartner, topRival, bestRival, topFriend;
  final DirectMatch? memorable;
  final List<(String, String)> achievements;   // (id, título)

  String get periodLabel => kind == WrappedKind.year ? '${start.year}' : '${capitalize(monthName(start.month))} ${start.year}';
  String? get topWeekday => weekdays.isEmpty ? null : _weekdays[weekdays.first.$1 - 1];
  WrappedBucket? get bestBucket {
    final eligible = buckets.where((b) => b.played >= (kind == WrappedKind.year ? 3 : 2)).toList();
    if (eligible.length < 2) return null;
    eligible.sort((a, b) => b.winRate != a.winRate ? b.winRate.compareTo(a.winRate) : b.played.compareTo(a.played));
    return eligible.first;
  }
  WrappedBucket? get busiestBucket {
    if (buckets.length < 2) return null;
    final s = [...buckets]..sort((a, b) => b.played.compareTo(a.played));
    return s.first;
  }

  factory WrappedData.fromJson(Map<String, dynamic> j) {
    WrappedPerson? person(Object? v) {
      final m = (v as Map?)?.cast<String, dynamic>();
      return m == null ? null : WrappedPerson(GPlayer.fromJson(m), _i(m['played']), _i(m['wins']));
    }
    final prev = (j['previous'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rec = (j['record'] as Map?)?.cast<String, dynamic>();
    final mem = (j['memorable'] as Map?)?.cast<String, dynamic>();
    return WrappedData(
      kind: WrappedKind.values.byName(j['kind'] as String), start: DateTime.parse(j['start'] as String), inProgress: j['in_progress'] == true,
      name: (j['name'] ?? '') as String, played: _i(j['played']), wins: _i(j['wins']), losses: _i(j['losses']),
      winRate: (j['win_rate'] as num?)?.toInt(), setsPlayed: _i(j['sets_played']), setsWon: _i(j['sets_won']), bestStreak: _i(j['best_streak']),
      prevPlayed: _i(prev['played']), prevWinRate: (prev['win_rate'] as num?)?.toInt(),
      buckets: [for (final b in (j['buckets'] as List? ?? const []).cast<Map<String, dynamic>>())
        WrappedBucket(DateTime.parse(b['start'] as String), _i(b['played']), _i(b['wins']))],
      weekdays: [for (final w in (j['weekdays'] as List? ?? const []).cast<Map<String, dynamic>>()) (_i(w['dow']), _i(w['played']))],
      topPartner: person(j['top_partner']), topRival: person(j['top_rival']), bestRival: person(j['best_rival']), topFriend: person(j['top_friend']),
      memorable: mem == null ? null : DirectMatch(matchId: mem['match_id'] as String, playedAt: DateTime.parse(mem['played_at'] as String).toLocal(),
          won: true, sets: _sets(mem['sets']), myPartner: mem['partner'] as String?,
          theirPartner: ((mem['rivals'] as List?) ?? const []).cast<String>().join(' y ')),
      recordElo: rec == null ? null : (rec['elo'] as num?)?.toInt(), isRecord: rec?['is_record'] == true,
      achievements: [for (final a in (j['achievements'] as List? ?? const []).cast<Map<String, dynamic>>()) (a['id'] as String, a['title'] as String)],
    );
  }
}

/// Diapositivas del Wrapped: solo las que tienen datos reales (nada se inventa).
enum WrappedSlide { cover, played, wins, partner, rival, streak, busiest, evolution, memorable, record, achievements, summary }

List<WrappedSlide> wrappedSlides(WrappedData w) => [
      WrappedSlide.cover,
      if (w.played > 0) WrappedSlide.played,
      if (w.played > 0) WrappedSlide.wins,
      if (w.topPartner != null) WrappedSlide.partner,
      if (w.topRival != null) WrappedSlide.rival,
      if (w.bestStreak >= 2) WrappedSlide.streak,
      if (w.busiestBucket != null || w.topWeekday != null) WrappedSlide.busiest,
      if (w.prevPlayed > 0 && w.played > 0) WrappedSlide.evolution,
      if (w.memorable != null) WrappedSlide.memorable,
      if (w.recordElo != null) WrappedSlide.record,
      if (w.achievements.isNotEmpty) WrappedSlide.achievements,
      WrappedSlide.summary,
    ];

// ───────────────────────────── Logros y niveles ─────────────────────────────

@immutable
class AchievementItem {
  const AchievementItem({required this.id, required this.category, required this.title, required this.description, required this.icon,
      required this.goal, required this.xp, this.unlockedAt, this.seen = true, this.progress = 0});
  final String id, category, title, description, icon;
  final int goal, xp, progress;
  final DateTime? unlockedAt;
  final bool seen;
  bool get unlocked => unlockedAt != null;
  double get fraction => unlocked ? 1 : (progress / goal).clamp(0, 1).toDouble();
  factory AchievementItem.fromJson(Map<String, dynamic> j) => AchievementItem(id: j['id'] as String, category: j['category'] as String,
      title: j['title'] as String, description: j['description'] as String, icon: j['icon'] as String, goal: _i(j['goal']), xp: _i(j['xp']),
      unlockedAt: j['unlocked_at'] == null ? null : DateTime.parse(j['unlocked_at'] as String).toLocal(), seen: j['seen'] != false,
      progress: _i(j['progress']));
}

@immutable
class XpEvent {
  const XpEvent(this.type, this.source, this.xp, this.at);
  final String type, source;
  final int xp;
  final DateTime at;
}

@immutable
class AchievementsData {
  const AchievementsData({required this.xp, required this.level, required this.levelFloor, required this.levelCeiling, required this.items, this.history = const []});
  final int xp, level, levelFloor, levelCeiling;
  final List<AchievementItem> items;
  final List<XpEvent> history;
  double get levelProgress => levelCeiling <= levelFloor ? 1 : ((xp - levelFloor) / (levelCeiling - levelFloor)).clamp(0, 1).toDouble();
  int get toNextLevel => math.max(0, levelCeiling - xp);
  List<AchievementItem> get unlocked => items.where((a) => a.unlocked).toList()..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
  List<AchievementItem> get unseen => items.where((a) => a.unlocked && !a.seen).toList();
  /// Próximos: bloqueados con más progreso relativo primero.
  List<AchievementItem> get next => items.where((a) => !a.unlocked).toList()..sort((a, b) => b.fraction.compareTo(a.fraction));

  factory AchievementsData.fromJson(Map<String, dynamic> j) => AchievementsData(
        xp: _i(j['xp']), level: _i(j['level']), levelFloor: _i(j['level_floor']), levelCeiling: _i(j['level_ceiling']),
        items: [for (final a in (j['achievements'] as List? ?? const []).cast<Map<String, dynamic>>()) AchievementItem.fromJson(a)],
        history: [for (final e in (j['history'] as List? ?? const []).cast<Map<String, dynamic>>())
          XpEvent(e['type'] as String, e['source'] as String, _i(e['xp']), DateTime.parse(e['at'] as String).toLocal())],
      );
}

/// Mismas cifras que `xp_for_level` / `level_for_xp` del servidor.
int xpForLevel(int level) { final l = math.max(level, 1); return 300 * (l - 1) + 50 * (l - 1) * l; }
int levelForXp(int xp) { var l = 1; while (l < 100 && xpForLevel(l + 1) <= xp) { l++; } return l; }

@immutable
class NotificationPrefs {
  const NotificationPrefs({this.ranking = true, this.achievements = true, this.levels = true, this.wrapped = true});
  final bool ranking, achievements, levels, wrapped;
  NotificationPrefs copyWith({bool? ranking, bool? achievements, bool? levels, bool? wrapped}) => NotificationPrefs(
      ranking: ranking ?? this.ranking, achievements: achievements ?? this.achievements, levels: levels ?? this.levels, wrapped: wrapped ?? this.wrapped);
}

/// Catálogo de logros (igual que `achievement_catalog` en Supabase).
const achievementCatalog = <(String, String, String, String, String, String, int, int)>[
  // id, categoría, título, descripción, icono, métrica, objetivo, XP
  ('matches_1', 'activity', 'Primer partido', 'Juega tu primer partido confirmado.', 'ball', 'matches', 1, 50),
  ('matches_10', 'activity', '10 partidos', 'Juega 10 partidos confirmados.', 'ball', 'matches', 10, 100),
  ('matches_25', 'activity', '25 partidos', 'Juega 25 partidos confirmados.', 'ball', 'matches', 25, 200),
  ('matches_50', 'activity', '50 partidos', 'Juega 50 partidos confirmados.', 'ball', 'matches', 50, 300),
  ('matches_100', 'activity', '100 partidos', 'Juega 100 partidos confirmados.', 'ball', 'matches', 100, 500),
  ('wins_1', 'wins', 'Primera victoria', 'Gana tu primer partido.', 'trophy', 'wins', 1, 50),
  ('wins_5', 'wins', '5 victorias', 'Gana 5 partidos.', 'trophy', 'wins', 5, 100),
  ('wins_10', 'wins', '10 victorias', 'Gana 10 partidos.', 'trophy', 'wins', 10, 150),
  ('wins_25', 'wins', '25 victorias', 'Gana 25 partidos.', 'trophy', 'wins', 25, 250),
  ('wins_50', 'wins', '50 victorias', 'Gana 50 partidos.', 'trophy', 'wins', 50, 400),
  ('streak_3', 'streak', 'En racha', 'Gana 3 partidos seguidos.', 'flame', 'best_streak', 3, 100),
  ('streak_5', 'streak', 'Imparable', 'Gana 5 partidos seguidos.', 'flame', 'best_streak', 5, 200),
  ('streak_10', 'streak', 'Leyenda', 'Gana 10 partidos seguidos.', 'flame', 'best_streak', 10, 400),
  ('partners_5', 'social', 'Buen compañero', 'Juega con 5 compañeros distintos.', 'users', 'partners', 5, 100),
  ('partners_10', 'social', 'Jugador social', 'Juega con 10 compañeros distintos.', 'users', 'partners', 10, 200),
  ('rivals_10', 'social', 'Sin miedo', 'Enfréntate a 10 rivales distintos.', 'users', 'rivals', 10, 150),
  ('week_winner', 'competition', 'Campeón semanal', 'Gana el ranking semanal entre tus amigos.', 'star', 'event', 1, 200),
  ('month_winner', 'competition', 'Campeón del mes', 'Gana el ranking mensual entre tus amigos.', 'star', 'event', 1, 400),
  ('top3_friends', 'competition', 'Podio', 'Termina una temporada en el Top 3 de tus amigos.', 'star', 'event', 1, 150),
  ('tournament_winner', 'competition', 'Campeón de torneo', 'Gana un torneo de Plobby.', 'trophy', 'event', 1, 500),
];

const categoryLabels = {'activity': 'Actividad', 'wins': 'Victorias', 'streak': 'Rachas', 'social': 'Social', 'competition': 'Competición'};

// ───────────────────────────── Motor (réplica del SQL) ─────────────────────────────

/// Reglas del servidor en Dart, sobre una lista de [StatRow]. Lo usan el repositorio de demo y los tests.
class GamificationEngine {
  GamificationEngine({required this.rows, required this.players, required this.friends, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final List<StatRow> rows;
  final Map<String, GPlayer> players;
  final Map<String, Set<String>> friends;
  final DateTime Function() _now;

  List<StatRow> of(String uid, {DateTime? from, DateTime? to}) => rows
      .where((r) => r.userId == uid && (from == null || !r.playedAt.isBefore(from)) && (to == null || r.playedAt.isBefore(to)))
      .toList()..sort((a, b) => a.playedAt.compareTo(b.playedAt) != 0 ? a.playedAt.compareTo(b.playedAt) : a.matchId.compareTo(b.matchId));

  static int bestStreak(List<StatRow> chronological) {
    var best = 0, cur = 0;
    for (final r in chronological) { cur = r.won ? cur + 1 : 0; best = math.max(best, cur); }
    return best;
  }

  static int currentStreak(List<StatRow> chronological) {
    if (chronological.isEmpty) return 0;
    final last = chronological.last.won;
    var n = 0;
    for (final r in chronological.reversed) { if (r.won != last) break; n++; }
    return last ? n : -n;
  }

  PlayerCard card(String uid) {
    final s = of(uid), w = s.where((r) => r.won).length, now = _now();
    return PlayerCard(
      player: players[uid] ?? GPlayer(id: uid, name: uid), played: s.length, wins: w, losses: s.length - w,
      winRate: s.isEmpty ? 0 : (100 * w / s.length).round(),
      setsWon: s.fold(0, (a, r) => a + r.setsWon), setsLost: s.fold(0, (a, r) => a + r.setsLost),
      bestStreak: bestStreak(s), currentStreak: currentStreak(s),
      form: s.reversed.take(5).map((r) => r.won ? 'W' : 'L').join(),
      level: levelForXp(xpOf(uid)),
      monthly: [for (var k = 5; k >= 0; k--) () {
        final m = DateTime(now.year, now.month - k), e = DateTime(now.year, now.month - k + 1);
        final x = of(uid, from: m, to: e), xw = x.where((r) => r.won).length;
        return MonthPoint(m, x.length, x.isEmpty ? null : (100 * xw / x.length).round());
      }()],
    );
  }

  int xpOf(String uid) {
    final s = of(uid);
    var xp = s.length * 100 + s.where((r) => r.won).length * 50;
    for (final a in achievements(uid).items.where((a) => a.unlocked)) { xp += a.xp; }
    return xp;
  }

  H2HData headToHead(String me, String other) {
    final mine = of(me);
    final direct = [for (final r in mine) if (r.rivals.contains(other)) r]..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final together = mine.where((r) => r.partnerId == other).toList();
    return H2HData(
      me: card(me), other: card(other), directTotal: direct.length, myWins: direct.where((r) => r.won).length,
      theirWins: direct.where((r) => !r.won).length, lastAt: direct.isEmpty ? null : direct.first.playedAt,
      matches: [for (final r in direct) DirectMatch(matchId: r.matchId, playedAt: r.playedAt, won: r.won, sets: r.sets,
          myPartner: players[r.partnerId]?.name,
          theirPartner: players[rows.where((x) => x.matchId == r.matchId && x.userId == other).firstOrNull?.partnerId]?.name)],
      togetherTotal: together.length, togetherWins: together.where((r) => r.won).length,
    );
  }

  /// Límites del periodo (lunes / día 1 / 1 de enero, hora local).
  static (DateTime, DateTime) period(RankPeriod p, int offset, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (p) {
      RankPeriod.week => (today.subtract(Duration(days: today.weekday - 1)).add(Duration(days: 7 * offset)),
          today.subtract(Duration(days: today.weekday - 1)).add(Duration(days: 7 * offset + 7))),
      RankPeriod.month => (DateTime(now.year, now.month + offset), DateTime(now.year, now.month + offset + 1)),
      RankPeriod.year => (DateTime(now.year + offset), DateTime(now.year + offset + 1)),
      RankPeriod.all => (DateTime(2000), DateTime(2100)),
    };
  }

  static const minMatches = {RankPeriod.week: 2, RankPeriod.month: 4, RankPeriod.year: 10, RankPeriod.all: 10};

  /// Mismas reglas que `_g_ranking_rows`: victorias (desempate % y menos partidos), % (mínimo de partidos) y actividad.
  List<RankRow> rankingRows(String viewer, DateTime from, DateTime to, int min) {
    final group = {viewer, ...?friends[viewer]};
    final agg = [for (final u in group) () {
      final s = of(u, from: from, to: to), w = s.where((r) => r.won).length;
      return (u, w, s.length - w, s.length);
    }()];
    double ratio((String, int, int, int) a) => a.$4 == 0 ? 0 : a.$2 / a.$4;
    int rankBy(List<(String, int, int, int)> all, (String, int, int, int) x, int Function((String, int, int, int), (String, int, int, int)) cmp) =>
        all.where((y) => cmp(y, x) < 0).length + 1;
    int cmpWins((String, int, int, int) a, (String, int, int, int) b) =>
        b.$2 != a.$2 ? b.$2.compareTo(a.$2) : ratio(b) != ratio(a) ? ratio(b).compareTo(ratio(a)) : b.$4.compareTo(a.$4);
    int cmpRate((String, int, int, int) a, (String, int, int, int) b) => ratio(b) != ratio(a) ? ratio(b).compareTo(ratio(a)) : b.$2.compareTo(a.$2);
    int cmpAct((String, int, int, int) a, (String, int, int, int) b) => b.$4 != a.$4 ? b.$4.compareTo(a.$4) : b.$2.compareTo(a.$2);
    final eligible = agg.where((a) => a.$4 >= min).toList();
    return [for (final a in agg) RankRow(
      player: players[a.$1] ?? GPlayer(id: a.$1, name: a.$1), wins: a.$2, losses: a.$3, played: a.$4,
      winRate: a.$4 == 0 ? 0 : (100 * a.$2 / a.$4).round(), level: levelForXp(xpOf(a.$1)),
      posWins: rankBy(agg, a, cmpWins), posRate: a.$4 >= min ? rankBy(eligible, a, cmpRate) : null, posActivity: rankBy(agg, a, cmpAct))];
  }

  RankingData ranking(String viewer, RankPeriod p, int offset) {
    final now = _now(), min = minMatches[p]!;
    final (from, to) = period(p, offset, now);
    final (pf, pt) = period(p, offset - 1, now);
    return RankingData(period: p, offset: offset, start: from, end: to, closed: to.isBefore(now) && p != RankPeriod.all && p != RankPeriod.year,
        minMatches: min, rows: rankingRows(viewer, from, to, min), previous: p == RankPeriod.all ? const [] : rankingRows(viewer, pf, pt, min), meId: viewer);
  }

  AchievementsData achievements(String uid) {
    final s = of(uid), w = s.where((r) => r.won).length;
    final metrics = {'matches': s.length, 'wins': w, 'best_streak': bestStreak(s),
      'partners': s.map((r) => r.partnerId).whereType<String>().toSet().length, 'rivals': s.expand((r) => r.rivals).toSet().length};
    final items = [for (final c in achievementCatalog) () {
      final v = metrics[c.$6] ?? 0;
      final reached = c.$6 != 'event' && v >= c.$7;
      DateTime? at;
      if (reached) {   // fecha en la que se alcanzó el objetivo
        var acc = 0, best = 0, cur = 0;
        final partners = <String>{}, rivals = <String>{};
        for (final r in s) {
          if (c.$6 == 'matches') acc++;
          if (c.$6 == 'wins' && r.won) acc++;
          if (c.$6 == 'best_streak') { cur = r.won ? cur + 1 : 0; best = math.max(best, cur); acc = best; }
          if (c.$6 == 'partners' && r.partnerId != null) { partners.add(r.partnerId!); acc = partners.length; }
          if (c.$6 == 'rivals') { rivals.addAll(r.rivals); acc = rivals.length; }
          if (acc >= c.$7) { at = r.playedAt; break; }
        }
      }
      return AchievementItem(id: c.$1, category: c.$2, title: c.$3, description: c.$4, icon: c.$5, goal: c.$7, xp: c.$8,
          unlockedAt: at, progress: c.$6 == 'event' ? 0 : v);
    }()];
    final xp = s.length * 100 + w * 50 + items.where((a) => a.unlocked).fold<int>(0, (a, b) => a + b.xp);
    final lvl = levelForXp(xp);
    return AchievementsData(xp: xp, level: lvl, levelFloor: xpForLevel(lvl), levelCeiling: xpForLevel(lvl + 1), items: items);
  }

  WrappedData wrapped(String uid, WrappedKind kind, DateTime start) {
    final from = kind == WrappedKind.month ? DateTime(start.year, start.month) : DateTime(start.year);
    final to = kind == WrappedKind.month ? DateTime(from.year, from.month + 1) : DateTime(from.year + 1);
    final pfrom = kind == WrappedKind.month ? DateTime(from.year, from.month - 1) : DateTime(from.year - 1);
    final s = of(uid, from: from, to: to), prev = of(uid, from: pfrom, to: from), w = s.where((r) => r.won).length;
    WrappedPerson? top(Iterable<(String, bool)> people, {int min = 1, bool byRate = false}) {
      final m = <String, (int, int)>{};
      for (final (id, won) in people) { final v = m[id] ?? (0, 0); m[id] = (v.$1 + 1, v.$2 + (won ? 1 : 0)); }
      final list = m.entries.where((e) => e.value.$1 >= min).toList()
        ..sort((a, b) => byRate
            ? (b.value.$2 / b.value.$1).compareTo(a.value.$2 / a.value.$1) != 0 ? (b.value.$2 / b.value.$1).compareTo(a.value.$2 / a.value.$1) : b.value.$1.compareTo(a.value.$1)
            : b.value.$1 != a.value.$1 ? b.value.$1.compareTo(a.value.$1) : b.value.$2.compareTo(a.value.$2));
      if (list.isEmpty) return null;
      return WrappedPerson(players[list.first.key] ?? GPlayer(id: list.first.key, name: list.first.key), list.first.value.$1, list.first.value.$2);
    }
    final buckets = <DateTime, (int, int)>{};
    for (final r in s) {
      final b = kind == WrappedKind.year ? DateTime(r.playedAt.year, r.playedAt.month)
          : DateTime(r.playedAt.year, r.playedAt.month, r.playedAt.day).subtract(Duration(days: r.playedAt.weekday - 1));
      final v = buckets[b] ?? (0, 0);
      buckets[b] = (v.$1 + 1, v.$2 + (r.won ? 1 : 0));
    }
    final days = <int, int>{};
    for (final r in s) { days[r.playedAt.weekday] = (days[r.playedAt.weekday] ?? 0) + 1; }
    final mem = s.where((r) => r.won).toList()
      ..sort((a, b) => b.sets.length != a.sets.length ? b.sets.length.compareTo(a.sets.length)
          : (b.gamesWon + b.gamesLost) != (a.gamesWon + a.gamesLost) ? (b.gamesWon + b.gamesLost).compareTo(a.gamesWon + a.gamesLost) : b.playedAt.compareTo(a.playedAt));
    final friendsOf = friends[uid] ?? const {};
    final ach = achievements(uid).items.where((a) => a.unlocked && !a.unlockedAt!.isBefore(from) && a.unlockedAt!.isBefore(to)).toList();
    return WrappedData(
      kind: kind, start: from, inProgress: _now().isBefore(to), name: players[uid]?.name ?? '', played: s.length, wins: w, losses: s.length - w,
      winRate: s.isEmpty ? null : (100 * w / s.length).round(), setsPlayed: s.fold(0, (a, r) => a + r.sets.length),
      setsWon: s.fold(0, (a, r) => a + r.setsWon), bestStreak: bestStreak(s), prevPlayed: prev.length,
      prevWinRate: prev.isEmpty ? null : (100 * prev.where((r) => r.won).length / prev.length).round(),
      buckets: [for (final e in buckets.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) WrappedBucket(e.key, e.value.$1, e.value.$2)],
      weekdays: (days.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1))),
      topPartner: top([for (final r in s) if (r.partnerId != null) (r.partnerId!, r.won)]),
      topRival: top([for (final r in s) for (final x in r.rivals) (x, r.won)]),
      bestRival: top([for (final r in s) for (final x in r.rivals) (x, r.won)], min: 2, byRate: true),
      topFriend: top([for (final r in s) for (final x in [if (r.partnerId != null) r.partnerId!, ...r.rivals]) if (friendsOf.contains(x)) (x, r.won)]),
      memorable: mem.isEmpty ? null : DirectMatch(matchId: mem.first.matchId, playedAt: mem.first.playedAt, won: true, sets: mem.first.sets,
          myPartner: players[mem.first.partnerId]?.name, theirPartner: mem.first.rivals.map((x) => players[x]?.name ?? '').join(' y ')),
      achievements: [for (final a in ach) (a.id, a.title)],
    );
  }

  List<WrappedPeriod> wrappedPeriods(String uid) {
    final now = _now(), s = of(uid);
    final months = <DateTime, int>{}, years = <DateTime, int>{};
    for (final r in s) {
      final m = DateTime(r.playedAt.year, r.playedAt.month), y = DateTime(r.playedAt.year);
      months[m] = (months[m] ?? 0) + 1; years[y] = (years[y] ?? 0) + 1;
    }
    return [
      for (final e in years.entries.toList()..sort((a, b) => b.key.compareTo(a.key))) WrappedPeriod(WrappedKind.year, e.key, e.value, e.key.year == now.year),
      for (final e in months.entries.toList()..sort((a, b) => b.key.compareTo(a.key)))
        WrappedPeriod(WrappedKind.month, e.key, e.value, e.key.year == now.year && e.key.month == now.month),
    ];
  }
}
