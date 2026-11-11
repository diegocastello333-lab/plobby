import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/profile/domain/models.dart';
import 'package:plobby/features/profile/domain/stats_calculator.dart';

MatchResult m(int daysAgo, bool won, {bool confirmed = true, int elo = 10}) => MatchResult(
    id: '$daysAgo$won$confirmed', playedAt: DateTime(2026, 11, 11).subtract(Duration(days: daysAgo)), won: won,
    partner: const PlayerRef('p', 'P'), opponents: const [PlayerRef('a', 'A'), PlayerRef('b', 'B')],
    sets: won ? const [(6, 3), (6, 4)] : const [(3, 6), (4, 6)], venue: 'X', eloDelta: won ? elo : -elo, side: PlaySide.right, confirmed: confirmed);

void main() {
  final calc = StatsCalculator(now: DateTime(2026, 11, 11));
  test('un partido sin confirmar no incrementa ni reinicia la racha', () {
    final all = [m(0, true, confirmed: false), m(1, true), m(2, true), m(3, false)];
    expect(calc.streak(all).current, 2);
    final all2 = [m(0, false, confirmed: false), m(1, true), m(2, true)];
    expect(calc.streak(all2).current, 2);
  });
  test('mejor racha', () {
    expect(calc.streak([m(1, true), m(2, false), m(3, true), m(4, true), m(5, true), m(6, false)]).best, 3);
  });
  test('filtros de periodo y porcentaje', () {
    final all = [m(5, true), m(20, false), m(60, true), m(200, true)];
    expect(calc.stats(all, StatsPeriod.d30).played, 2);
    expect(calc.stats(all, StatsPeriod.all).winRate, 75);
  });
  test('la serie de ELO termina en el ELO actual y no usa pendientes', () {
    final all = [m(0, true, confirmed: false, elo: 50), m(2, true), m(9, false)];
    final s = calc.eloSeries(all, 1500, EloRange.d30);
    expect(s.last.elo, 1500);
    expect(calc.eloChange(all, 1500, EloRange.d30), 1500 - (1500 - 10 + 10));
  });
}
