import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/tournaments/data/supabase_tournament_repository.dart';
import 'package:plobby/features/tournaments/domain/tournament_engine.dart';
import 'package:plobby/features/tournaments/domain/tournament_models.dart';

/// Mismos escenarios (y mismos resultados) que la validación de las funciones SQL contra Supabase.
TournamentEngine _engine(TournamentFormat f, int teams, {int groups = 1, int q = 0}) {
  final players = [for (var i = 1; i <= teams * 2; i++) TPlayer(id: 'u$i', name: 'Jugador $i')];
  final e = TournamentEngine(
    Tournament(id: 't', name: 'Test', startsOn: DateTime(2026, 11, 20), maxTeams: 64, format: f, groupsCount: groups, qualifiersPerGroup: q),
    [for (var i = 0; i < teams; i++) TTeam(id: 'S${i + 1}', seed: i + 1, p1: players[2 * i], p2: players[2 * i + 1])],
  );
  e.generate();
  return e;
}

TMatch _ko(TournamentEngine e, int round, int pos) => e.matches.firstWhere((m) => m.stage == MatchStage.knockout && m.round == round && m.position == pos);

/// Igual que `round_str` del test SQL: «S1v·:bye>S1 S4vS5:pending>·».
String _round(TournamentEngine e, int r) {
  final ms = e.matches.where((m) => m.stage == MatchStage.knockout && m.round == r).toList()..sort((a, b) => a.position.compareTo(b.position));
  return ms.map((m) => '${m.team1Id ?? '·'}v${m.team2Id ?? '·'}:${m.status.db}>${m.winnerTeamId ?? '·'}').join(' ');
}

void _win(TournamentEngine e, TMatch m, {required bool first}) => e.record(m.id, first ? const [(6, 3), (6, 4)] : const [(3, 6), (4, 6)], e.match(m.id).version);

void main() {
  test('siembra estándar', () {
    expect(TournamentEngine.seedOrder(4), [1, 4, 2, 3]);
    expect(TournamentEngine.seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
  });

  group('Eliminación directa con 5 parejas (impar)', () {
    test('cuadro de 8 con 3 BYE que avanzan solos', () {
      final e = _engine(TournamentFormat.knockout, 5);
      expect(_round(e, 1), 'S1v·:bye>S1 S4vS5:pending>· S2v·:bye>S2 S3v·:bye>S3');
      expect(_round(e, 2), 'S1v·:pending>· S2vS3:pending>·');
      expect(e.matches.length, 7);
    });

    test('el ganador avanza, se decide el campeón y una corrección anula la final', () {
      final e = _engine(TournamentFormat.knockout, 5);
      _win(e, _ko(e, 1, 1), first: false);
      expect(_round(e, 2), 'S1vS5:pending>· S2vS3:pending>·');
      _win(e, _ko(e, 2, 0), first: true);
      _win(e, _ko(e, 2, 1), first: true);
      expect(_round(e, 3), 'S1vS2:pending>·');
      expect(e.tournament.status, TournamentStatus.inProgress);
      _win(e, _ko(e, 3, 0), first: false);
      expect((e.tournament.championTeamId, e.tournament.status), ('S2', TournamentStatus.finished));
      // Corrección de la semifinal ya jugada: la final se vacía y desaparece el campeón.
      _win(e, _ko(e, 2, 0), first: false);
      expect(_round(e, 3), 'S5vS2:pending>·');
      expect((e.tournament.championTeamId, e.tournament.status), (null, TournamentStatus.inProgress));
    });

    test('conflicto de versión, sets inválidos y partido sin parejas', () {
      final e = _engine(TournamentFormat.knockout, 5);
      final m = _ko(e, 1, 1);
      expect(() => e.record(m.id, const [(6, 1), (6, 1)], m.version - 1), throwsA(isA<TournamentException>().having((x) => x.code, 'code', 'result_conflict')));
      expect(() => e.record(m.id, const [(6, 5), (6, 1)], m.version), throwsA(isA<TournamentException>()));
      expect(() => e.record(m.id, const [(6, 1), (1, 6)], m.version), throwsA(isA<TournamentException>()));
      final waiting = _ko(e, 3, 0);
      expect(() => e.record(waiting.id, const [(6, 1), (6, 1)], waiting.version), throwsA(isA<TournamentException>().having((x) => x.code, 'code', 'match_not_ready')));
    });

    test('2 parejas: solo la final', () {
      final e = _engine(TournamentFormat.knockout, 2);
      expect(_round(e, 1), 'S1vS2:pending>·');
      _win(e, _ko(e, 1, 0), first: true);
      expect(e.tournament.championTeamId, 'S1');
    });
  });

  group('Grupos + eliminatoria (8 parejas, 2 grupos, pasan 2)', () {
    test('reparto en serpiente, liguilla por grupo y cruces 1.º vs 2.º', () {
      final e = _engine(TournamentFormat.groupsKnockout, 8, groups: 2, q: 2);
      expect([for (final t in e.teams) '${t.groupLabel}:${t.seed}']..sort(), ['A:1', 'A:4', 'A:5', 'A:8', 'B:2', 'B:3', 'B:6', 'B:7']);
      expect(e.matches.where((m) => m.groupLabel == 'A').length, 6);
      expect(e.matches.where((m) => m.groupLabel == 'B').length, 6);
      final r1 = e.matches.where((m) => m.stage == MatchStage.knockout && m.round == 1).toList()..sort((a, b) => a.position.compareTo(b.position));
      expect(r1.map((m) => '${m.slot1Source}v${m.slot2Source}'), ['A1vB2', 'B1vA2']);
      // Cada pareja juega como mucho una vez por jornada.
      for (final g in ['A', 'B']) {
        for (final r in {for (final m in e.matches.where((m) => m.groupLabel == g)) m.round}) {
          final teams = [for (final m in e.matches.where((m) => m.groupLabel == g && m.round == r)) ...[m.team1Id, m.team2Id]];
          expect(teams.toSet().length, teams.length);
        }
      }
    });

    test('clasificación, cruces rellenados y re-siembra tras corregir un resultado de grupo', () {
      final e = _engine(TournamentFormat.groupsKnockout, 8, groups: 2, q: 2);
      int seed(String? id) => int.parse(id!.substring(1));
      for (final m in e.matches.where((m) => m.stage == MatchStage.group).toList()) {
        e.record(m.id, seed(m.team1Id) < seed(m.team2Id) ? const [(6, 2), (6, 3)] : const [(2, 6), (3, 6)], e.match(m.id).version);
      }
      expect(e.standings().map((s) => '${s.groupLabel}${s.pos}=S${s.seed}(${s.points}p,${s.setDiff})').join(' '),
          'A1=S1(9p,6) A2=S4(6p,2) A3=S5(3p,-2) A4=S8(0p,-6) B1=S2(9p,6) B2=S3(6p,2) B3=S6(3p,-2) B4=S7(0p,-6)');
      expect(_round(e, 1), 'S1vS3:pending>· S2vS4:pending>·');
      _win(e, _ko(e, 1, 0), first: true);
      // La semilla 5 gana a la 1 y a la 4: cambian el 1.º y el 2.º del grupo A.
      for (final m in e.matches.where((m) => m.groupLabel == 'A' && m.involves('S5') && (m.involves('S1') || m.involves('S4'))).toList()) {
        e.record(m.id, m.team1Id == 'S5' ? const [(6, 2), (6, 3)] : const [(2, 6), (3, 6)], e.match(m.id).version);
      }
      expect(e.standings().where((s) => s.groupLabel == 'A').map((s) => 'A${s.pos}=S${s.seed}').join(' '), 'A1=S5 A2=S1 A3=S4 A4=S8');
      expect(_round(e, 1), 'S5vS3:pending>· S2vS1:pending>·');   // el cruce ya jugado se anula y se re-siembra
    });

    test('combinaciones imposibles se rechazan', () {
      expect(() => _engine(TournamentFormat.groupsKnockout, 6, groups: 4, q: 2), throwsA(isA<TournamentException>()));
      expect(() => _engine(TournamentFormat.groupsKnockout, 6, groups: 2, q: 4), throwsA(isA<TournamentException>()));
    });
  });

  test('Liguilla de 3 parejas: 3 partidos y campeón al terminar', () {
    final e = _engine(TournamentFormat.roundRobin, 3);
    expect(e.matches.length, 3);
    for (final m in e.matches.toList()) { e.record(m.id, const [(6, 0), (6, 0)], e.match(m.id).version); }
    expect((e.tournament.championTeamId, e.tournament.status), ('S1', TournamentStatus.finished));
  });

  group('Asistente y validaciones', () {
    const a = TPlayer(id: 'a', name: 'Ana'), b = TPlayer(id: 'b', name: 'Bea'), c = TPlayer(id: 'c', name: 'Carla'), d = TPlayer(id: 'd', name: 'Dani');
    test('partidos estimados', () {
      expect(estimatedMatches(TournamentFormat.knockout, 5), 4);
      expect(estimatedMatches(TournamentFormat.roundRobin, 4), 6);
      expect(estimatedMatches(TournamentFormat.groupsKnockout, 8, groups: 2, qualifiers: 2), 12 + 3);
      expect(estimatedMatches(TournamentFormat.groupsKnockout, 7, groups: 2, qualifiers: 1), 6 + 3 + 1);
    });
    test('información y formato', () {
      expect(validateTournamentInfo(const TournamentDraft(name: 'ab')), isNotNull);
      expect(validateTournamentInfo(TournamentDraft(name: 'Open', startsOn: DateTime(2026, 11, 20), endsOn: DateTime(2026, 11, 19))), isNotNull);
      expect(validateTournamentInfo(TournamentDraft(name: 'Open', startsOn: DateTime(2026, 11, 20))), isNull);
      expect(validateTournamentFormat(const TournamentDraft(teams: [(a, b)])), isNotNull);                    // 1 pareja
      expect(validateTournamentFormat(const TournamentDraft(teams: [(a, b), (c, d)])), isNull);
      expect(validateTournamentFormat(const TournamentDraft(format: TournamentFormat.roundRobin, teams: [(a, b), (c, d)])), isNotNull);
      expect(validateTournamentFormat(const TournamentDraft(maxTeams: 1, teams: [(a, b), (c, d)])), isNotNull);
    });
    test('sets: mismas reglas que el servidor', () {
      expect(validateTournamentSets(const [(6, 3), (6, 4)]), isNull);
      expect(validateTournamentSets(const [(6, 3), (4, 6), (7, 6)]), isNull);
      expect(validateTournamentSets(const [(6, 3), (4, 6)]), contains('tercer set'));
      expect(validateTournamentSets(const [(6, 3), (6, 4), (6, 1)]), isNotNull);
      expect(validateTournamentSets(const [(6, 5), (6, 4)]), isNotNull);
    });
    test('mapeo de errores del servidor', () {
      expect(TournamentException.fromServer('result_conflict').code, 'result_conflict');
      expect(TournamentException.fromServer('invalid_set_2').code, 'invalid_set');
      expect(TournamentException.fromServer('algo raro').message, isNotEmpty);
    });
  });

  test('filas de Supabase → modelos', () {
    final m = SupabaseTournamentRepository.matchFrom({'id': 'm', 'stage': 'knockout', 'round': 2, 'position': 1, 'team1_id': 'a', 'team2_id': null,
        'next_match_id': 'n', 'next_slot': 2, 'status': 'finished', 'sets': [[6, 3], [6, 4]], 'winner_team_id': 'a', 'version': 3});
    expect((m.score, m.version, m.nextSlot, m.status), ('6-3 / 6-4', 3, 2, TMatchStatus.finished));
    final s = SupabaseTournamentRepository.summaryFrom({'id': 't', 'name': 'Open', 'starts_on': '2026-11-20', 'format': 'knockout', 'status': 'in_progress',
        'teams_count': 5, 'max_teams': 8, 'knockout_rounds': 3, 'current_round': 2, 'group_pending': 0,
        'next_match': {'stage': 'knockout', 'round': 2, 'status': 'pending', 'opponent': {'p1': 'Ana', 'p2': 'Bea'}}});
    expect((s.phaseText, s.nextMatch!.label, s.nextMatch!.opponent), ('Semifinales', 'Semifinales', 'Ana / Bea'));
  });
}
