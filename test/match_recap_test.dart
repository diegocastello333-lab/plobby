import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/match_recap/application/recap_painter.dart';
import 'package:plobby/features/match_recap/domain/recap_data.dart';
import 'package:plobby/features/matches/domain/match_lifecycle.dart';
import 'package:plobby/features/matches/domain/match_models.dart';

const players = [
  MatchPlayer(id: 'me', name: 'Diego C.', team: 1, isCaptain: true, elo: 1470),
  MatchPlayer(id: 'marcos', name: 'Marcos R.', team: 1),
  MatchPlayer(id: 'carlos', name: 'Carlos M.', team: 2, isCaptain: true, avatarId: 'a3'),
  MatchPlayer(id: 'laura', name: 'Laura G.', team: 2),
];

LifecycleMatch match({MatchStatus st = MatchStatus.confirmed, List<SetScore> sets = const [SetScore(4, 6), SetScore(6, 3), SetScore(5, 7)], bool accepted = true, Map<String, int> elo = const {'me': 12}}) => LifecycleMatch(
    id: 'm1', type: MatchType.league, leagueName: 'Liga Moraleja', scheduledAt: DateTime(2026, 11, 8, 19), club: 'Club Alameda', court: 'Pista 2', status: st, players: players, createdBy: 'me',
    durationSeconds: 5400, resultVersion: 1, sets: sets, eloDelta: elo,
    acceptances: accepted ? const [Acceptance(userId: 'me', team: 1, version: 1, accepted: true), Acceptance(userId: 'carlos', team: 2, version: 1, accepted: true)] : const []);

void main() {
  group('RecapData: solo partidos confirmados, datos reales', () {
    test('rechaza no confirmados, sin aceptación de ambos capitanes y no participantes', () {
      for (final st in [MatchStatus.scheduled, MatchStatus.live, MatchStatus.pendingResult, MatchStatus.pendingConfirmation, MatchStatus.disputed, MatchStatus.cancelled]) {
        expect(() => RecapData.fromMatch(match(st: st), 'me'), throwsA(isA<RecapException>()), reason: st.name);
        expect(RecapData.canShare(match(st: st), 'me'), isFalse);
      }
      expect(() => RecapData.fromMatch(match(accepted: false), 'me'), throwsA(isA<RecapException>()));
      expect(() => RecapData.fromMatch(match(), 'intruso'), throwsA(isA<RecapException>()));
      expect(RecapData.canShare(match(), 'me'), isTrue);
    });

    test('ganadores primero y marcador orientado (ganadores, rivales) aunque ganen los del equipo 2', () {
      final d = RecapData.fromMatch(match(), 'me'); // sets 4-6, 6-3, 5-7 → gana el equipo 2
      expect(d.winnerIsTeam1, isFalse);
      expect(d.winners.map((p) => p.id), ['carlos', 'laura']);
      expect(d.opponents.map((p) => p.id), ['me', 'marcos']);
      expect(d.sets, [(6, 4), (3, 6), (7, 5)]);
      expect(d.winnerSets, 2);
      expect(d.userWon, isFalse);
    });

    test('ELO solo con dato real: delta del usuario; antes/después coherentes', () {
      final d = RecapData.fromMatch(match(), 'me');
      expect(d.eloDelta, 12);
      expect(d.eloBefore, 1470);
      expect(d.eloAfter, 1482);
      final none = RecapData.fromMatch(match(elo: const {}), 'me');
      expect(none.hasElo, isFalse);
      expect(none.eloAfter, isNull);
    });

    test('duración, liga y etiquetas', () {
      final d = RecapData.fromMatch(match(), 'me');
      expect(recapDuration(d.durationSeconds!), '1 h 30 min');
      expect(recapDuration(2700), '45 min');
      expect(d.contextLabel, 'LIGA · Liga Moraleja');
      expect(recapDate(DateTime(2026, 11, 8)), '8 NOV 2026');
    });

    test('amistoso y liga usan el mismo modelo: solo cambian las etiquetas', () {
      final lg = RecapData.fromMatch(match(), 'me');
      expect(lg.isLeague, isTrue);
      expect(lg.leagueName, 'Liga Moraleja');
      final fr = RecapData.fromMatch(LifecycleMatch(id: 'f1', type: MatchType.friendly, scheduledAt: DateTime(2026, 11, 9), club: 'Alameda', status: MatchStatus.confirmed, players: players, createdBy: 'me',
          resultVersion: 1, sets: const [SetScore(6, 1), SetScore(6, 2)], acceptances: const [Acceptance(userId: 'me', team: 1, version: 1, accepted: true), Acceptance(userId: 'carlos', team: 2, version: 1, accepted: true)]), 'me');
      expect(fr.isLeague, isFalse);
      expect(fr.contextLabel, 'AMISTOSO');
      expect(fr.hasElo, isFalse); // sin delta real no se inventa
      expect(fr.hasDuration, isFalse);
    });

    test('una corrección vigente (nueva versión) se refleja: se usan los sets actuales y solo aceptaciones de esa versión', () {
      final corrected = match().copyWith(resultVersion: 2, sets: const [SetScore(6, 0), SetScore(6, 0)]);
      expect(() => RecapData.fromMatch(corrected, 'me'), throwsA(isA<RecapException>())); // aceptaciones v1 no valen para v2
    });

    test('formatos: resoluciones exactas', () {
      expect([for (final f in RecapFormat.values) '${f.width}x${f.height}'], ['1080x1920', '1080x1350', '1080x1080']);
    });
  });

  group('RecapPainter: PNG real a resolución exacta (9 combinaciones)', () {
    for (final t in RecapTemplate.values) {
      for (final f in RecapFormat.values) {
        testWidgets('${t.name} × ${f.name}', (tester) async {
          await tester.runAsync(() async {
            final d = RecapData.fromMatch(match(), 'me', stats: const RecapUserStats(played: 24, winRate: 62, streak: 3));
            final png = await RecapPainter.toPng(d, t, f);
            expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // firma PNG
            final codec = await ui.instantiateImageCodec(png);
            final img = (await codec.getNextFrame()).image;
            expect(img.width, f.width);
            expect(img.height, f.height);
          });
        });
      }
    }

    testWidgets('opciones ocultas y sin ELO/duración no rompen el render', (tester) async {
      await tester.runAsync(() async {
        final d = RecapData.fromMatch(match(elo: const {}), 'me');
        const o = RecapOptions(showStats: false, showDuration: false, showElo: false, showClub: false);
        for (final t in RecapTemplate.values) {
          final png = await RecapPainter.toPng(d, t, RecapFormat.square, opts: o);
          expect(png.length, greaterThan(1000));
        }
      });
    });
  });
}
