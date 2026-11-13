import 'dart:math' as math;
import '../domain/gamification_models.dart';
import 'gamification_repository.dart';

/// DATOS DE DEMOSTRACIÓN (sin Supabase): partidos de ejemplo deterministas de los últimos 14 meses, procesados con
/// [GamificationEngine] — las mismas reglas que el servidor. Los ids coinciden con los demás mocks (me, laura, marcos…).
class MockGamificationRepository implements GamificationRepository {
  MockGamificationRepository({DateTime Function()? now, List<StatRow>? rows}) : _now = now ?? DateTime.now {
    engine = GamificationEngine(rows: rows ?? _demo(_now()), players: players, friends: {'me': players.keys.where((k) => k != 'me').toSet()}, now: _now);
  }
  final DateTime Function() _now;
  late final GamificationEngine engine;
  var _prefs = const NotificationPrefs();
  final _seen = <String>{};

  static const players = {
    'me': GPlayer(id: 'me', name: 'Diego Castello', username: 'diego.c'),
    'laura': GPlayer(id: 'laura', name: 'Laura G.', username: 'laura.g'),
    'marcos': GPlayer(id: 'marcos', name: 'Marcos R.', username: 'marcos.r'),
    'lucia': GPlayer(id: 'lucia', name: 'Lucía M.', username: 'lucia.m'),
    'alvaro': GPlayer(id: 'alvaro', name: 'Álvaro P.', username: 'alvaro.p'),
    'sofia': GPlayer(id: 'sofia', name: 'Sofía G.', username: 'sofia.g'),
    'pablo': GPlayer(id: 'pablo', name: 'Pablo S.', username: 'pablo.s'),
  };

  /// ~70 partidos repartidos en 14 meses (más en los recientes), siempre 2 contra 2.
  static List<StatRow> _demo(DateTime now) {
    final rnd = math.Random(7), ids = players.keys.toList(), rows = <StatRow>[];
    var n = 0;
    for (var day = 420; day >= 0; day -= 1 + rnd.nextInt(day < 60 ? 3 : 9)) {
      final pool = [...ids]..shuffle(rnd);
      final four = pool.contains('me') && rnd.nextDouble() < .75 ? (['me', ...pool.where((x) => x != 'me')]).take(4).toList() : pool.take(4).toList();
      final t1 = [four[0], four[1]], t2 = [four[2], four[3]];
      final win1 = rnd.nextDouble() < (t1.contains('me') ? .6 : .5);
      final three = rnd.nextDouble() < .3;
      List<(int, int)> score(bool w) => three
          ? [w ? (6, 4) : (4, 6), w ? (3, 6) : (6, 3), w ? (7, 5) : (5, 7)]
          : [w ? (6, 2 + rnd.nextInt(4)) : (2 + rnd.nextInt(4), 6), w ? (6, 1 + rnd.nextInt(5)) : (1 + rnd.nextInt(5), 6)];
      final s1 = score(win1);
      final at = DateTime(now.year, now.month, now.day, 19, 30).subtract(Duration(days: day));
      final id = 'g${n++}';
      for (final (team, members, sets) in [(1, t1, s1), (2, t2, [for (final s in s1) (s.$2, s.$1)])]) {
        for (final u in members) {
          final rivals = team == 1 ? t2 : t1;
          rows.add(StatRow(matchId: id, userId: u, playedAt: at, team: team, won: team == 1 ? win1 : !win1, sets: sets,
              partnerId: members.firstWhere((x) => x != u), rival1Id: rivals[0], rival2Id: rivals[1]));
        }
      }
    }
    return rows;
  }

  @override
  String get meId => 'me';
  Future<T> _later<T>(T Function() f) => Future<T>.delayed(const Duration(milliseconds: 250), f);

  @override
  Future<H2HData> headToHead(String otherId) => _later(() {
        if (!players.containsKey(otherId) || otherId == 'me') throw GamificationException('not_friends');
        return engine.headToHead('me', otherId);
      });
  @override
  Future<RankingData> ranking(RankPeriod period, {int offset = 0}) => _later(() => engine.ranking('me', period, offset));
  @override
  Future<List<WrappedPeriod>> wrappedPeriods() => _later(() => engine.wrappedPeriods('me'));
  @override
  Future<WrappedData> wrapped(WrappedKind kind, DateTime start) => _later(() => engine.wrapped('me', kind, start));
  @override
  Future<AchievementsData> achievements() => _later(() {
        final a = engine.achievements('me');
        return AchievementsData(xp: a.xp, level: a.level, levelFloor: a.levelFloor, levelCeiling: a.levelCeiling,
            items: [for (final i in a.items) AchievementItem(id: i.id, category: i.category, title: i.title, description: i.description,
                icon: i.icon, goal: i.goal, xp: i.xp, unlockedAt: i.unlockedAt, progress: i.progress, seen: true)]);
      });
  @override
  Future<void> markAchievementsSeen() async => _seen.add('all');
  @override
  Future<NotificationPrefs> prefs() async => _prefs;
  @override
  Future<void> savePrefs(NotificationPrefs p) async => _prefs = p;
}
