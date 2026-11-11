import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/matches/domain/match_models.dart';

MatchDraft d({MatchType t = MatchType.friendly, String? league, List<SetScore> sets = const [], DateTime? when}) => MatchDraft(
    type: t, leagueId: league, partnerId: 'a', rival1Id: 'b', rival2Id: 'c', when: when ?? DateTime.now().add(const Duration(days: 1)), club: 'X', sets: sets);

void main() {
  test('amistoso: no pide liga y no admite liga', () {
    expect(validateDraft(d(), resultRequired: false), isNull);
    expect(validateDraft(d(league: 'l1'), resultRequired: false), isNotNull);
  });
  test('liga: exige liga elegida', () {
    expect(validateDraft(d(t: MatchType.league), resultRequired: false), 'Elige la liga del partido.');
    expect(validateDraft(d(t: MatchType.league, league: 'l1'), resultRequired: false), isNull);
  });
  test('resultado: obligatorio solo al registrar desde una liga y con sets válidos', () {
    expect(validateDraft(d(t: MatchType.league, league: 'l1'), resultRequired: true), isNotNull);
    expect(validateDraft(d(sets: const [SetScore(6, 3), SetScore(7, 5)]), resultRequired: true), isNull);
    expect(validateDraft(d(sets: const [SetScore(6, 5), SetScore(7, 5)]), resultRequired: false), isNotNull);
  });
  test('sin resultado y fecha pasada: error', () {
    expect(validateDraft(d(when: DateTime(2020)), resultRequired: false), isNotNull);
  });
  test('jugadores distintos', () {
    final x = MatchDraft(type: MatchType.friendly, partnerId: 'a', rival1Id: 'a', rival2Id: 'c', when: DateTime.now().add(const Duration(days: 1)), club: 'X');
    expect(validateDraft(x, resultRequired: false), 'Los tres jugadores deben ser distintos.');
  });
}
