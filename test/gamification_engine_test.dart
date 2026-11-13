import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/gamification/data/mock_gamification_repository.dart';
import 'package:plobby/features/gamification/domain/gamification_models.dart';

/// Mismos escenarios que supabase/tests/gamification_test.sql, sobre el motor Dart.
final _p = {for (final id in ['a', 'b', 'c', 'd', 'f']) id: GPlayer(id: id, name: id.toUpperCase())};
var _n = 0;
List<StatRow> match(String a, String b, String c, String d, List<(int, int)> sets, DateTime at) {
  final id = 'm${_n++}', w1 = sets.where((s) => s.$1 > s.$2).length > sets.length / 2;
  StatRow r(String u, String partner, int team, String r1, String r2) => StatRow(matchId: id, userId: u, playedAt: at, team: team,
      won: team == 1 ? w1 : !w1, sets: team == 1 ? sets : [for (final s in sets) (s.$2, s.$1)], partnerId: partner, rival1Id: r1, rival2Id: r2);
  return [r(a, b, 1, c, d), r(b, a, 1, c, d), r(c, d, 2, a, b), r(d, c, 2, a, b)];
}

GamificationEngine eng(List<StatRow> rows, DateTime now) =>
    GamificationEngine(rows: rows, players: _p, friends: {for (final u in _p.keys) u: _p.keys.where((x) => x != u).toSet()}, now: () => now);

void main() {
  final now = DateTime(2026, 11, 13, 20);   // viernes
  final monday = DateTime(2026, 11, 9, 10);

  test('rachas: mejor racha y racha actual (negativa = derrotas)', () {
    final rows = [...match('a', 'b', 'c', 'd', [(6, 1), (6, 1)], monday), ...match('a', 'b', 'c', 'd', [(6, 1), (6, 1)], monday.add(const Duration(hours: 1))),
      ...match('c', 'd', 'a', 'b', [(6, 1), (6, 1)], monday.add(const Duration(hours: 2)))];
    final e = eng(rows, now);
    expect((e.card('a').bestStreak, e.card('a').currentStreak, e.card('c').currentStreak), (2, -1, 1));
    expect(e.card('a').form, 'LWW');
  });

  test('Head to Head: separa enfrentamientos directos de partidos como pareja', () {
    final rows = [...match('a', 'b', 'c', 'd', [(6, 3), (6, 4)], monday), ...match('a', 'c', 'b', 'd', [(3, 6), (6, 4), (7, 5)], monday.add(const Duration(days: 1)))];
    final h = eng(rows, now).headToHead('a', 'c');
    expect((h.directTotal, h.myWins, h.theirWins, h.togetherTotal, h.togetherWins), (1, 1, 0, 1, 1));
    expect(h.matches.single.sets, [(6, 3), (6, 4)]);
    expect(h.verdict.leader, H2HLeader.unknown);   // 1 enfrentamiento no basta para declarar dominador
  });

  test('Head to Head: con ≥2 enfrentamientos y ventaja hay dominador; sin datos, nunca se inventa', () {
    final rows = [for (var i = 0; i < 3; i++) ...match('c', 'd', 'a', 'b', [(6, 2), (6, 2)], monday.add(Duration(hours: i)))];
    final h = eng(rows, now).headToHead('a', 'c');
    expect(h.verdict.leader, H2HLeader.other);
    expect(h.balance, [-1, -2, -3]);
    expect(eng(const [], now).headToHead('a', 'f').verdict.leader, H2HLeader.unknown);
  });

  test('ranking: empate total comparte puesto; desempate por % y por partidos; mínimo para el ranking de %', () {
    final rows = [...match('a', 'b', 'c', 'd', [(6, 1), (6, 1)], monday), ...match('a', 'b', 'c', 'd', [(6, 1), (6, 1)], monday.add(const Duration(hours: 1)))];
    final r = eng(rows, now).ranking('a', RankPeriod.week, 0);
    RankRow row(String id) => r.rows.firstWhere((x) => x.player.id == id);
    expect((row('a').posWins, row('b').posWins, row('c').posWins, row('d').posWins, row('f').posWins), (1, 1, 3, 3, 5));   // con 0 victorias, quien jugó va antes que quien no
    expect(row('f').posRate, isNull);
    expect(r.ranked(RankMetric.rate).first.player.id, anyOf('a', 'b'));
    expect(r.belowMinimum(RankMetric.rate), isEmpty);
    expect((row('a').posActivity, row('c').posActivity), (1, 3));   // actividad: mismos partidos → desempatan las victorias
  });

  test('ranking: movimiento respecto al periodo anterior', () {
    final last = monday.subtract(const Duration(days: 7));
    final rows = [...match('c', 'd', 'a', 'b', [(6, 1), (6, 1)], last), ...match('a', 'b', 'c', 'd', [(6, 1), (6, 1)], monday)];
    final r = eng(rows, now).ranking('a', RankPeriod.week, 0);
    expect(r.movement('a', RankMetric.wins), 2);   // del 3.º al 1.º
    expect(r.movement('c', RankMetric.wins), -2);
    expect(r.movement('f', RankMetric.wins), isNull);   // sin partidos antes: no se compara
  });

  test('Wrapped: cambio de año, periodo anterior, compañero y rival', () {
    final rows = [...match('a', 'b', 'c', 'd', [(6, 4), (6, 4)], DateTime(2026, 12, 31, 23, 30)),
      ...match('a', 'b', 'c', 'd', [(3, 6), (6, 4), (7, 5)], DateTime(2026, 11, 2)), ...match('c', 'd', 'a', 'b', [(6, 0), (6, 0)], DateTime(2026, 11, 3))];
    final e = eng(rows, DateTime(2027, 1, 3));
    expect(e.wrapped('a', WrappedKind.month, DateTime(2026, 12)).played, 1);
    expect(e.wrapped('a', WrappedKind.month, DateTime(2027, 1)).played, 0);
    final y = e.wrapped('a', WrappedKind.year, DateTime(2026));
    expect((y.played, y.wins, y.winRate, y.topPartner?.player.id, y.memorable?.sets.length), (3, 2, 67, 'b', 3));
    final dec = e.wrapped('a', WrappedKind.month, DateTime(2026, 12));
    expect((dec.prevPlayed, dec.prevWinRate), (2, 50));
    expect(wrappedSlides(e.wrapped('a', WrappedKind.month, DateTime(2027, 1))), [WrappedSlide.cover, WrappedSlide.summary]);   // sin datos: nada inventado
  });

  test('logros y nivel: mismas cifras que el servidor (XP = 100/partido + 50/victoria + logros)', () {
    final rows = [for (var i = 0; i < 3; i++) ...match('a', 'b', 'c', 'd', [(6, 1), (6, 1)], monday.add(Duration(hours: i)))];
    final a = eng(rows, now).achievements('a');
    final unlocked = a.items.where((i) => i.unlocked).map((i) => i.id).toSet();
    expect(unlocked, {'matches_1', 'wins_1', 'streak_3'});
    expect(a.xp, 3 * 150 + 50 + 50 + 100);
    expect((xpForLevel(1), xpForLevel(2), xpForLevel(3), levelForXp(399), levelForXp(400), levelForXp(900)), (0, 400, 900, 1, 2, 3));
    expect(a.level, levelForXp(a.xp));
  });

  test('datos de demostración coherentes: ranking, H2H, Wrapped y logros salen de los mismos partidos', () async {
    final repo = MockGamificationRepository(now: () => now);
    final r = await repo.ranking(RankPeriod.all);
    final me = r.me!;
    final a = await repo.achievements();
    final h = await repo.headToHead('laura');
    final periods = await repo.wrappedPeriods();
    final years = periods.where((p) => p.kind == WrappedKind.year).fold(0, (s, p) => s + p.played);
    expect(h.me.played, me.played);
    expect(years, me.played);
    expect(a.items.firstWhere((i) => i.id == 'matches_10').unlocked, me.played >= 10);
  });
}
