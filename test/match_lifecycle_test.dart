import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/matches/data/lifecycle_repository.dart';
import 'package:plobby/features/matches/data/mock_lifecycle_repository.dart';
import 'package:plobby/features/matches/domain/match_lifecycle.dart';
import 'package:plobby/features/matches/domain/match_models.dart';

List<MatchPlayer> four() => const [
      MatchPlayer(id: 'me', name: 'Diego C.', team: 1, isCaptain: true), MatchPlayer(id: 'marcos', name: 'Marcos R.', team: 1),
      MatchPlayer(id: 'carlos', name: 'Carlos M.', team: 2, isCaptain: true), MatchPlayer(id: 'laura', name: 'Laura G.', team: 2),
    ];
LifecycleMatch seed({MatchType t = MatchType.friendly, DateTime? at, MatchStatus st = MatchStatus.scheduled}) => LifecycleMatch(id: 'm1', type: t, leagueId: t == MatchType.league ? 'l1' : null, scheduledAt: at ?? DateTime.now().add(const Duration(days: 2)), club: 'Alameda', status: st, players: four(), createdBy: 'me');

/// Los mocks no comparten estado entre instancias: para probar concurrencia/varios usuarios usamos un único mock y
/// cambiamos el «usuario» creando vistas que comparten el mapa interno.
MockLifecycleRepository as(MockLifecycleRepository base, String uid) => base.asUser(uid);

void main() {
  group('validateSets (al mejor de 3)', () {
    test('2-0, 2-1 válidos; ganador correcto', () {
      expect(validateSets(const [SetScore(6, 4), SetScore(6, 3)]).winner, 1);
      expect(validateSets(const [SetScore(6, 4), SetScore(3, 6), SetScore(7, 5)]).winner, 1);
      expect(validateSets(const [SetScore(4, 6), SetScore(5, 7)]).winner, 2);
    });
    test('1-1 exige tercer set; 2-0 no admite tercero; sets imposibles', () {
      expect(validateSets(const [SetScore(6, 4), SetScore(3, 6)]).valid, isFalse);
      expect(validateSets(const [SetScore(6, 4), SetScore(6, 3), SetScore(6, 1)]).valid, isFalse);
      expect(validateSets(const [SetScore(6, 5), SetScore(6, 3)]).valid, isFalse);
      expect(validateSets(const [SetScore(6, 4)]).valid, isFalse);
    });
  });

  group('cronómetro por hora de servidor', () {
    test('elapsed = serverNow - startedAt (no contador local) y coincide para todos', () {
      final start = DateTime.utc(2026, 11, 11, 18, 0, 0);
      final m = seed(st: MatchStatus.live).copyWith(startedAt: start);
      final server = DateTime.utc(2026, 11, 11, 18, 23, 41);
      // dos dispositivos con relojes distintos, ambos corregidos con su desfase respecto al servidor
      final a = ServerClock.fromServerSample(server, DateTime.utc(2026, 11, 11, 18, 20, 0), DateTime.utc(2026, 11, 11, 18, 20, 0));
      final b = ServerClock.fromServerSample(server, DateTime.utc(2026, 11, 11, 17, 59, 0), DateTime.utc(2026, 11, 11, 17, 59, 0));
      expect(formatElapsed(Duration(seconds: elapsedOf(m, ServerClock(a.offset, () => DateTime.utc(2026, 11, 11, 18, 20))).inSeconds)), '23:41');
      expect(formatElapsed(elapsedOf(m, ServerClock(b.offset, () => DateTime.utc(2026, 11, 11, 17, 59)))), '23:41');
    });
    test('al cerrar y reabrir la app el tiempo sigue (solo depende de startedAt)', () {
      final m = seed(st: MatchStatus.live).copyWith(startedAt: DateTime.utc(2026, 1, 1, 10));
      expect(formatElapsed(elapsedOf(m, ServerClock(Duration.zero, () => DateTime.utc(2026, 1, 1, 11, 5, 3)))), '01:05:03');
    });
    test('finalizado: duración guardada, ya no corre', () {
      final m = seed(st: MatchStatus.pendingResult).copyWith(startedAt: DateTime.utc(2026, 1, 1, 10), durationSeconds: 4320);
      expect(formatElapsed(elapsedOf(m, ServerClock(Duration.zero, () => DateTime.utc(2030)))), '01:12:00');
    });
  });

  group('EMPEZAR / FINALIZAR (atómico)', () {
    test('dos pulsaciones simultáneas ⇒ una sola hora oficial', () async {
      var t = DateTime.utc(2026, 11, 11, 18);
      final base = MockLifecycleRepository(me: 'me', seed: [seed()], now: () => t);
      final r1 = await base.start('m1');
      t = t.add(const Duration(milliseconds: 40));
      final r2 = await as(base, 'carlos').start('m1');
      expect(r1.started, isTrue); expect(r2.started, isFalse);
      expect(r2.startedAt, r1.startedAt); expect(r2.startedBy, 'me');
    });
    test('no participantes no pueden iniciar; finish exige LIVE', () async {
      final base = MockLifecycleRepository(me: 'me', seed: [seed()]);
      expect(() => as(base, 'intruso').start('m1'), throwsA(isA<LifecycleException>()));
      expect(() => base.finish('m1'), throwsA(isA<LifecycleException>()));
    });
    test('finalizar guarda hora de fin y duración total y pasa a pendiente de resultado', () async {
      var t = DateTime.utc(2026, 11, 11, 18);
      final base = MockLifecycleRepository(me: 'me', seed: [seed()], now: () => t);
      await base.start('m1'); t = t.add(const Duration(minutes: 72, seconds: 8));
      await as(base, 'marcos').finish('m1');
      final m = (await base.watchMatch('m1').first)!;
      expect(m.status, MatchStatus.pendingResult); expect(m.durationSeconds, 72 * 60 + 8); expect(m.endedAt, t);
    });
  });

  group('resultado y confirmación de los dos capitanes', () {
    Future<MockLifecycleRepository> toResult() async { final b = MockLifecycleRepository(me: 'me', seed: [seed()]); await b.start('m1'); await b.finish('m1'); return b; }
    const sets = [SetScore(6, 4), SetScore(3, 6), SetScore(7, 5)];

    test('sin confirmar NO se aplica ELO/estadísticas', () async {
      final b = await toResult(); await b.submitResult('m1', sets);
      await b.respond('m1', 1, accept: true);
      expect(b.ratingApplications('m1'), 0);
      expect((await b.watchMatch('m1').first)!.status, MatchStatus.pendingConfirmation);
    });
    test('solo capitanes pueden aceptar', () async {
      final b = await toResult(); await b.submitResult('m1', sets);
      expect(() => as(b, 'marcos').respond('m1', 1, accept: true), throwsA(predicate((e) => e is LifecycleException && e.code == 'only_captains_can_confirm')));
    });
    test('los dos capitanes aceptan la MISMA versión ⇒ confirmado, ELO aplicado una vez', () async {
      final b = await toResult(); await b.submitResult('m1', sets);
      expect(await b.respond('m1', 1, accept: true), MatchStatus.pendingConfirmation);
      expect(await as(b, 'carlos').respond('m1', 1, accept: true), MatchStatus.confirmed);
      expect(b.ratingApplications('m1'), 1);
      final m = (await b.watchMatch('m1').first)!;
      expect(m.eloDelta['me'], greaterThan(0)); expect(m.eloDelta['carlos'], lessThan(0));
    });
    test('reintentar la aceptación no duplica ni vuelve a aplicar ELO (idempotente)', () async {
      final b = await toResult(); await b.submitResult('m1', sets);
      await b.respond('m1', 1, accept: true); await as(b, 'carlos').respond('m1', 1, accept: true);
      expect(() => b.respond('m1', 1, accept: true), throwsA(isA<LifecycleException>()));   // ya no está pendiente de confirmación
      expect(b.ratingApplications('m1'), 1);
    });
    test('editar tras una aceptación invalida las aceptaciones y la versión antigua se rechaza', () async {
      final b = await toResult(); await b.submitResult('m1', sets);
      await b.respond('m1', 1, accept: true);
      await as(b, 'laura').submitResult('m1', const [SetScore(6, 4), SetScore(6, 3)]);       // v2
      final m = (await b.watchMatch('m1').first)!;
      expect(m.resultVersion, 2); expect(m.acceptedTeams, isEmpty);
      expect(() => as(b, 'carlos').respond('m1', 1, accept: true), throwsA(predicate((e) => e is LifecycleException && e.code == 'stale_version')));
      expect(await as(b, 'carlos').respond('m1', 2, accept: true), MatchStatus.pendingConfirmation);   // el capitán 1 debe aceptar la v2 otra vez
      expect(b.ratingApplications('m1'), 0);
    });
    test('un capitán rechaza ⇒ DISPUTED con motivo; se corrige y se vuelve a pedir confirmación', () async {
      final b = await toResult(); await b.submitResult('m1', sets);
      await as(b, 'carlos').respond('m1', 1, accept: false, reason: 'el 2º set fue 6-3');
      var m = (await b.watchMatch('m1').first)!;
      expect(m.status, MatchStatus.disputed); expect(m.rejectionReason, 'el 2º set fue 6-3'); expect(b.ratingApplications('m1'), 0);
      await b.submitResult('m1', const [SetScore(6, 4), SetScore(3, 6), SetScore(7, 6)]);
      m = (await b.watchMatch('m1').first)!;
      expect(m.status, MatchStatus.pendingConfirmation); expect(m.resultVersion, 2);
    });
    test('marcador inválido no se acepta', () async {
      final b = await toResult();
      expect(() => b.submitResult('m1', const [SetScore(6, 4), SetScore(3, 6)]), throwsA(isA<LifecycleException>()));
    });
  });

  group('editar / eliminar y reglas de liga', () {
    EditMatch edit(MatchPlayer? swap, DateTime at) => EditMatch(scheduledAt: at, club: 'Nuevo', court: 'Pista 2', players: [for (final p in four()) (swap != null && p.id == 'laura') ? swap : p]);
    test('solo el creador edita/elimina y solo si está programado', () async {
      final b = MockLifecycleRepository(me: 'me', seed: [seed()]);
      expect(() => as(b, 'marcos').update('m1', edit(null, DateTime.now().add(const Duration(days: 3)))), throwsA(isA<LifecycleException>()));
      await b.update('m1', edit(null, DateTime.now().add(const Duration(days: 3))));
      expect((await b.watchMatch('m1').first)!.club, 'Nuevo');
      await b.start('m1');
      expect(() => b.cancel('m1'), throwsA(isA<LifecycleException>()));
    });
    test('liga: a menos de 2 h no se cambian jugadores ni se elimina', () async {
      final soon = DateTime.now().add(const Duration(hours: 1));
      final b = MockLifecycleRepository(me: 'me', seed: [seed(t: MatchType.league, at: soon)]);
      expect(() => b.update('m1', edit(const MatchPlayer(id: 'nuevo', name: 'Nuevo', team: 2), soon.add(const Duration(minutes: 30)))), throwsA(predicate((e) => e is LifecycleException && e.code == 'league_rule_players_locked')));
      expect(() => b.cancel('m1'), throwsA(predicate((e) => e is LifecycleException && e.code == 'league_rule_delete_locked')));
    });
    test('eliminar quita el partido de «próximos» para todos', () async {
      final b = MockLifecycleRepository(me: 'me', seed: [seed()]);
      expect((await b.watchUpcoming().first).length, 1);
      await b.cancel('m1');
      expect((await b.watchUpcoming().first), isEmpty);
    });
  });

  group('próximos partidos', () {
    test('orden cronológico y solo estados abiertos', () async {
      final a = seed(at: DateTime.now().add(const Duration(days: 5))), c = LifecycleMatch(id: 'm0', type: MatchType.friendly, scheduledAt: DateTime.now().add(const Duration(days: 1)), club: 'X', status: MatchStatus.live, players: four(), createdBy: 'me');
      final d = LifecycleMatch(id: 'mc', type: MatchType.friendly, scheduledAt: DateTime.now(), club: 'X', status: MatchStatus.confirmed, players: four(), createdBy: 'me');
      final b = MockLifecycleRepository(me: 'me', seed: [a, c, d]);
      expect([for (final m in await b.watchUpcoming().first) m.id], ['m0', 'm1']);
    });
    test('permisos de la UI', () {
      final m = seed();
      expect(MatchPerms(m, 'me').canEdit, isTrue); expect(MatchPerms(m, 'marcos').canEdit, isFalse);
      expect(MatchPerms(m, 'marcos').canStart, isTrue); expect(MatchPerms(m, 'intruso').canView, isFalse);
    });
  });
}
