import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/leagues/application/league_providers.dart';
import 'package:plobby/features/leagues/data/mock_league_repository.dart';
import 'package:plobby/features/leagues/domain/league_models.dart';
import 'package:plobby/features/leagues/presentation/league_detail_screen.dart';

void main() {
  group('computeStandings (misma fórmula que league_standings en SQL)', () {
    const members = [LeagueMemberRef('a', 'Ana', elo: 1500), LeagueMemberRef('b', 'Bea', elo: 1400), LeagueMemberRef('c', 'Carla', elo: 1600), LeagueMemberRef('d', 'Dani', elo: 1300)];

    test('victoria = 3, derrota = 1, bonus +1 por ganar sin ceder set', () {
      final rows = computeStandings(members, const [
        LeagueMatchResult(team1: ['a', 'b'], team2: ['c', 'd'], sets: [(6, 3), (6, 4)]),           // a, b ganan 2-0 → 3 + 1
        LeagueMatchResult(team1: ['a', 'c'], team2: ['b', 'd'], sets: [(6, 3), (3, 6), (6, 4)]),   // a, c ganan 2-1 → 3
      ], const LeagueRules());
      final by = {for (final r in rows) r.userId: r};
      expect(by['a']!.points, 4 + 3);
      expect(by['b']!.points, 4 + 1);
      expect(by['c']!.points, 1 + 3);
      expect(by['d']!.points, 1 + 1);
      expect(by['a']!.played, 2);
      expect(by['a']!.winPct, 100);
      expect(rows.first.userId, 'a');
      expect(rows.first.rank, 1);
    });

    test('solo partidos confirmados; sin bonus si está desactivado', () {
      final rows = computeStandings(members, const [
        LeagueMatchResult(team1: ['a', 'b'], team2: ['c', 'd'], sets: [(6, 0), (6, 0)]),
        LeagueMatchResult(team1: ['c', 'd'], team2: ['a', 'b'], sets: [(6, 0), (6, 0)], confirmed: false),
      ], const LeagueRules(bonusEnabled: false));
      final a = rows.firstWhere((r) => r.userId == 'a');
      expect(a.played, 1);
      expect(a.points, 3);
      expect(a.bonus, 0);
    });

    test('empates: mismo puesto si coinciden puntos, victorias y ELO; si no, desempata el ELO', () {
      const twins = [LeagueMemberRef('x', 'X', elo: 1500), LeagueMemberRef('y', 'Y', elo: 1500), LeagueMemberRef('z', 'Z', elo: 1700)];
      final rows = computeStandings(twins, const [], const LeagueRules());
      expect(rows.map((r) => r.userId).toList(), ['z', 'x', 'y']);
      expect(rows.map((r) => r.rank).toList(), [1, 2, 2]);
    });

    test('se ignoran jugadores que ya no son miembros', () {
      final rows = computeStandings(const [LeagueMemberRef('a', 'Ana')], const [LeagueMatchResult(team1: ['a', 'ex'], team2: ['p', 'q'], sets: [(6, 1), (6, 1)])], const LeagueRules());
      expect(rows.single.points, 4);
    });

    test('sortStandings: por ELO, % victorias o partidos sin alterar el rank del servidor', () {
      const rows = [StandingRow(userId: 'a', name: 'A', elo: 1300, played: 4, wins: 1, points: 7, rank: 1),
        StandingRow(userId: 'b', name: 'B', elo: 1700, played: 2, wins: 2, points: 6, rank: 2)];
      expect(sortStandings(rows, RankSort.points).map((r) => r.userId), ['a', 'b']);
      expect(sortStandings(rows, RankSort.elo).map((r) => r.userId), ['b', 'a']);
      expect(sortStandings(rows, RankSort.pct).map((r) => r.userId), ['b', 'a']);
      expect(sortStandings(rows, RankSort.played).map((r) => r.userId), ['a', 'b']);
    });
  });

  group('validateLeagueStep (asistente de 5 pasos)', () {
    final base = LeagueDraft(name: 'Liga de los jueves', startsOn: DateTime(2026, 11, 23), endsOn: DateTime(2027, 2, 28));
    test('nombre de 3 a 40 caracteres', () {
      expect(validateLeagueStep(base.copyWith(name: 'ab'), 1), contains('name'));
      expect(validateLeagueStep(base.copyWith(name: 'x' * 41), 1), contains('name'));
      expect(validateLeagueStep(base, 1), isEmpty);
    });
    test('mínimo ≤ máximo de participantes', () => expect(validateLeagueStep(base.copyWith(minPlayers: 10, maxPlayers: 8), 2), contains('players')));
    test('fin posterior al inicio y niveles coherentes', () {
      expect(validateLeagueStep(base.copyWith(endsOn: DateTime(2026, 11, 23)), 4), contains('dates'));
      expect(validateLeagueStep(base.copyWith(levelMin: 'Avanzado', levelMax: 'Iniciación'), 4), contains('level'));
    });
    test('la revisión final repite todas las validaciones', () => expect(validateLeagueStep(base.copyWith(name: '', minPlayers: 20, maxPlayers: 4), 5).keys, containsAll(['name', 'players'])));
    test('partidos previstos: 4 jugadores por partido', () => expect(plannedMatches(8, 10), 20));
  });

  group('MockLeagueRepository (mismas reglas que las RPC)', () {
    MockLeagueRepository repo([String me = 'me']) => MockLeagueRepository(me: me, now: DateTime(2026, 11, 11), latency: Duration.zero);

    test('crear: el creador es organizador y obtiene un código', () async {
      final r = repo();
      final c = await r.create(LeagueDraft(name: 'Liga de los jueves', startsOn: DateTime(2026, 11, 23), endsOn: DateTime(2027, 2, 28)));
      final d = await r.league(c.id);
      expect(d.name, 'LIGA DE LOS JUEVES');
      expect(d.myRole, LeagueRole.organizer);
      expect(await r.inviteCode(c.id), c.code);
      expect((await r.myLeagues()).any((l) => l.id == c.id), isTrue);
    });

    test('privada: sin código ni invitación no se entra; con código sí (sin distinguir mayúsculas)', () async {
      final nuria = repo('nuria');                             // no es miembro de «bunker» (privada)
      await expectLater(nuria.join('bunker'), throwsA(isA<LeagueException>().having((e) => e.code, 'code', 'invite_code_required')));
      expect((await nuria.discover('')).any((d) => d.id == 'bunker'), isFalse);   // las privadas no se descubren
      expect(await nuria.join('bunker', code: 'bunkerpa-01'), JoinOutcome.joined);
      expect(await nuria.join('bunker'), JoinOutcome.alreadyMember);
    });

    test('club: se solicita acceso y un gestor lo aprueba', () async {
      final r = repo('pablo');
      expect(await r.join('moraleja'), JoinOutcome.requested);
      expect((await r.discover('')).firstWhere((d) => d.id == 'moraleja').requestPending, isTrue);
      await expectLater(r.respondRequest('x', accept: true), throwsA(isA<LeagueException>()));
    });

    test('solo gestores ven solicitudes, quitan miembros o editan', () async {
      final player = repo();                                   // en «madrid» es jugador
      await expectLater(player.removeMember('madrid', 'sofia'), throwsA(isA<LeagueException>().having((e) => e.code, 'code', 'not_league_manager')));
      expect(await player.joinRequests('madrid'), isEmpty);
      expect(await player.joinRequests('bunker'), hasLength(1)); // en «bunker» es organizador
      await player.respondRequest('rq1', accept: true);
      expect((await player.standings('bunker')).any((r) => r.userId == 'carlos'), isTrue);
    });

    test('el organizador no puede salir con jugadores dentro; un jugador sí', () async {
      final r = repo();
      await expectLater(r.leave('bunker'), throwsA(isA<LeagueException>().having((e) => e.code, 'code', 'organizer_cannot_leave')));
      await r.leave('madrid');
      expect((await r.myLeagues()).any((l) => l.id == 'madrid'), isFalse);
    });

    test('código inexistente y liga completa', () async {
      final r = repo();
      await expectLater(r.joinByCode('NOPE-00'), throwsA(isA<LeagueException>().having((e) => e.code, 'code', 'invalid_invite_code')));
      await r.update('bunker', {'max_players': 8});
      await expectLater(r.update('bunker', {'max_players': 2}), throwsA(isA<LeagueException>().having((e) => e.code, 'code', 'max_below_members')));
    });

    test('clasificación del mock = computeStandings sobre partidos confirmados (la disputa no cuenta)', () async {
      final rows = await repo().standings('bunker');
      final me = rows.firstWhere((r) => r.userId == 'me');
      expect(me.played, 3);              // 3 confirmados; el partido en disputa y el programado no cuentan
      expect(me.wins, 2);
      expect(me.points, 2 * 3 + 1 + 2);  // 2 victorias 2-0 con bonus + 1 derrota
    });

    test('error de red se propaga como LeagueException con mensaje en español', () async {
      final r = repo()..failNext = true;
      await expectLater(r.myLeagues(), throwsA(isA<LeagueException>().having((e) => e.message, 'message', contains('conexión'))));
    });
  });

  test('applyDiscoverFilters: amigos, tipo, estado y zona', () {
    const all = [
      DiscoverLeague(id: '1', name: 'A', visibility: LeagueVisibility.public, friendsIn: 2, status: LeagueStatus.open, location: 'Norte'),
      DiscoverLeague(id: '2', name: 'B', visibility: LeagueVisibility.club, status: LeagueStatus.running, location: 'Centro'),
    ];
    expect(applyDiscoverFilters(all, const DiscoverFilters(kind: DiscoverKind.friends)).map((d) => d.id), ['1']);
    expect(applyDiscoverFilters(all, const DiscoverFilters(kind: DiscoverKind.club)).map((d) => d.id), ['2']);
    expect(applyDiscoverFilters(all, const DiscoverFilters(status: LeagueStatus.open)).map((d) => d.id), ['1']);
    expect(applyDiscoverFilters(all, const DiscoverFilters(zone: 'Centro')).map((d) => d.id), ['2']);
    expect(applyDiscoverFilters(all, const DiscoverFilters()), hasLength(2));
  });
}
