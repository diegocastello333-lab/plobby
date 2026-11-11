import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/matches/data/lifecycle_repository.dart';
import 'package:plobby/features/matches/data/mock_lifecycle_repository.dart';
import 'package:plobby/features/matches/domain/match_lifecycle.dart';
import 'package:plobby/features/matches/domain/match_models.dart';
import 'package:plobby/features/rating/domain/elo_calculator.dart';

/// Ciclo de vida completo de un partido con los cuatro jugadores en «móviles» distintos (vistas sobre el mismo
/// almacén, como varios clientes contra el servidor): programado → en juego → pendiente de resultado → pendiente de
/// confirmación → en disputa → corrección → confirmado. Mismas reglas que las RPC de 20261115_match_lifecycle.sql.
void main() {
  var clock = DateTime.utc(2026, 11, 20, 18);
  DateTime now() => clock;
  const players = [
    MatchPlayer(id: 'ana', name: 'Ana', team: 1, isCaptain: true, elo: 1500), MatchPlayer(id: 'bea', name: 'Bea', team: 1, elo: 1500),
    MatchPlayer(id: 'carla', name: 'Carla', team: 2, isCaptain: true, elo: 1600), MatchPlayer(id: 'dani', name: 'Dani', team: 2, elo: 1600),
  ];
  late MockLifecycleRepository ana, bea, carla, dani;

  setUp(() {
    clock = DateTime.utc(2026, 11, 20, 18);
    ana = MockLifecycleRepository(me: 'ana', now: now, seed: [
      LifecycleMatch(id: 'm', type: MatchType.friendly, scheduledAt: DateTime.utc(2026, 11, 20, 19), club: 'Club Alameda', status: MatchStatus.scheduled, players: players, createdBy: 'ana'),
    ]);
    bea = ana.asUser('bea'); carla = ana.asUser('carla'); dani = ana.asUser('dani');
  });

  Future<LifecycleMatch> current() async => (await ana.watchMatch('m').first)!;

  test('flujo completo con disputa y corrección; ELO aplicado una sola vez y igual al del servidor', () async {
    // 1. Programado: aparece en «Próximos» de los cuatro.
    for (final r in [ana, bea, carla, dani]) { expect((await r.watchUpcoming().first).map((m) => m.id), ['m']); }

    // 2. Empezar: dos jugadores pulsan a la vez → una sola hora oficial.
    final s = await Future.wait([bea.start('m'), dani.start('m')]);
    expect(s.where((x) => x.started).length, 1);
    expect(s[0].startedAt, s[1].startedAt);
    expect((await current()).status, MatchStatus.live);

    // 3. Finalizar a los 75 minutos (hora del servidor).
    clock = clock.add(const Duration(minutes: 75));
    await carla.finish('m');
    var m = await current();
    expect(m.status, MatchStatus.pendingResult);
    expect(m.durationSeconds, 75 * 60);
    await expectLater(ana.finish('m'), throwsA(isA<LifecycleException>().having((e) => e.code, 'code', 'match_not_live')));

    // 4. Resultado imposible (set después de 2-0) → rechazado; resultado válido → versión 1.
    await expectLater(bea.submitResult('m', const [SetScore(6, 4), SetScore(6, 3), SetScore(3, 6)]), throwsA(isA<LifecycleException>()));
    expect(await bea.submitResult('m', const [SetScore(6, 4), SetScore(6, 3)]), 1);
    expect((await current()).status, MatchStatus.pendingConfirmation);

    // 5. Un jugador que no es capitán no puede confirmar.
    await expectLater(bea.respond('m', 1, accept: true), throwsA(isA<LifecycleException>().having((e) => e.code, 'code', 'only_captains_can_confirm')));

    // 6. Capitán 1 acepta, capitán 2 rechaza con motivo → disputa. Nada de ELO todavía.
    expect(await ana.respond('m', 1, accept: true), MatchStatus.pendingConfirmation);
    expect(await carla.respond('m', 1, accept: false, reason: 'El primer set fue 6-4 para nosotros'), MatchStatus.disputed);
    m = await current();
    expect(m.status, MatchStatus.disputed);
    expect(m.rejectionReason, 'El primer set fue 6-4 para nosotros');
    expect(ana.ratingApplications('m'), 0);
    expect(m.eloDelta, isEmpty);

    // 7. Corrección → versión 2; la aceptación de la versión 1 ya no cuenta y aceptar la v1 es «stale».
    expect(await dani.submitResult('m', const [SetScore(4, 6), SetScore(6, 3), SetScore(6, 2)]), 2);
    m = await current();
    expect(m.status, MatchStatus.pendingConfirmation);
    expect(m.acceptedTeams, isEmpty);
    await expectLater(ana.respond('m', 1, accept: true), throwsA(isA<LifecycleException>().having((e) => e.code, 'code', 'stale_version')));

    // 8. Los dos capitanes aceptan la v2 → confirmado. Reintentar no reaplica nada.
    expect(await carla.respond('m', 2, accept: true), MatchStatus.pendingConfirmation);
    expect(await ana.respond('m', 2, accept: true), MatchStatus.confirmed);
    await expectLater(carla.respond('m', 2, accept: true), throwsA(isA<LifecycleException>()));   // ya no está pendiente
    expect(ana.ratingApplications('m'), 1);

    // 9. ELO: mismo resultado que la fórmula del servidor (equipo 1 de 1500 gana a 1600 → +20 / −20).
    m = await current();
    expect(m.winnerTeam, 1);
    expect(m.eloDelta, const EloCalculator().deltas(team1: {'ana': 1500, 'bea': 1500}, team2: {'carla': 1600, 'dani': 1600}, winnerTeam: 1));
    expect(m.eloDelta['ana'], 20);
    expect(m.eloDelta['carla'], -20);

    // 10. Sale de «Próximos» y aparece en el historial compartible de todos.
    expect(await ana.watchUpcoming().first, isEmpty);
    for (final r in [ana, bea, carla, dani]) { expect((await r.confirmedMatches()).map((x) => x.id), ['m']); }
  });

  test('un partido cancelado no se puede empezar ni aparece en próximos', () async {
    await ana.cancel('m');
    expect(await bea.watchUpcoming().first, isEmpty);
    expect((await current()).status, MatchStatus.cancelled);
    expect(MatchPerms(await current(), 'bea').canStart, isFalse);
  });

  test('solo se puede proponer resultado tras finalizar', () async {
    await expectLater(ana.submitResult('m', const [SetScore(6, 1), SetScore(6, 1)]), throwsA(isA<LifecycleException>()));
    await ana.start('m');
    await expectLater(ana.submitResult('m', const [SetScore(6, 1), SetScore(6, 1)]), throwsA(isA<LifecycleException>()));
  });

  test('validateSets: el partido acaba en cuanto una pareja gana 2 sets', () {
    expect(validateSets(const [SetScore(6, 4), SetScore(6, 3), SetScore(3, 6)]).valid, isFalse);   // antes se aceptaba
    expect(validateSets(const [SetScore(3, 6), SetScore(2, 6), SetScore(6, 0)]).valid, isFalse);
    expect(validateSets(const [SetScore(6, 4), SetScore(3, 6), SetScore(7, 6)]).winner, 1);
    expect(validateSets(const [SetScore(7, 6), SetScore(6, 7), SetScore(4, 6)]).winner, 2);
  });
}
