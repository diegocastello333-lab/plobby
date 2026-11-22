import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/share/canvas_text.dart';
import 'package:plobby/features/gamification/application/gamification_providers.dart';
import 'package:plobby/features/gamification/application/gamification_share.dart';
import 'package:plobby/features/gamification/data/mock_gamification_repository.dart';
import 'package:plobby/features/gamification/domain/gamification_models.dart';
import 'package:plobby/features/matches/application/lifecycle_providers.dart';
import 'package:plobby/features/matches/domain/match_lifecycle.dart';
import 'package:plobby/features/matches/domain/match_models.dart';
import 'package:plobby/features/matches/domain/post_match_summary.dart';
import 'package:plobby/features/matches/presentation/post_match_screen.dart';
import 'package:plobby/features/rating/application/rating_providers.dart';
import 'package:plobby/features/rating/domain/rating_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/layout_checks.dart';

/// Pantalla post-partido (GP1): el resumen sale SOLO de datos del servidor, la secuencia se puede saltar, respeta
/// «reducir movimiento», vibra una vez por evento y la derrota se cuenta con respeto.
const _scale = RatingScale(800, 2000, [RatingTier('Principiante', 800), RatingTier('Intermedio', 1200), RatingTier('Avanzado', 1400), RatingTier('Experto', 1600)]);
final _at = DateTime.utc(2026, 11, 20, 21);

LifecycleMatch _match({List<SetScore> sets = const [SetScore(6, 3), SetScore(6, 4)]}) => LifecycleMatch(
      id: 'm1', type: MatchType.friendly, scheduledAt: _at, endedAt: _at, club: 'Club Alameda', status: MatchStatus.confirmed, createdBy: 'me', sets: sets,
      players: const [
        MatchPlayer(id: 'me', name: 'Diego Castelló', team: 1, isCaptain: true, elo: 1210),
        MatchPlayer(id: 'p', name: 'Lucía Pérez', team: 1),
        MatchPlayer(id: 'r1', name: 'Ana Ruiz', team: 2, isCaptain: true),
        MatchPlayer(id: 'r2', name: 'Bea Gil', team: 2),
      ],
      eloDelta: const {'me': 16},
    );

RatingDetail _rating({int before = 1194, int delta = 16}) => RatingDetail(name: 'Diego', username: 'diego', elo: before + delta, bestElo: 1210, delta30: delta,
    confirmedMatches: 10, wins: 6, losses: 4, scale: _scale,
    history: [RatingChange(matchId: 'm1', at: _at, won: delta > 0, score: '6-3 6-4', opponents: 'Ana y Bea', before: before, delta: delta)]);

const _ach = AchievementItem(id: 'first_win', category: 'wins', title: 'Primera victoria', description: 'Gana tu primer partido confirmado.',
    icon: 'trophy', goal: 1, xp: 100, seen: false);

AchievementsData _achData({bool later = false}) {
  final xp = 300 + 100 + 50 + 100 + (later ? 150 : 0);
  final lvl = levelForXp(xp);
  return AchievementsData(xp: xp, level: lvl, levelFloor: xpForLevel(lvl), levelCeiling: xpForLevel(lvl + 1),
      items: [AchievementItem(id: _ach.id, category: _ach.category, title: _ach.title, description: _ach.description, icon: _ach.icon,
          goal: 1, xp: 100, unlockedAt: _at, seen: false)],
      history: [
        if (later) XpEvent('match', 'm2', 150, _at.add(const Duration(hours: 3))),
        XpEvent('achievement', 'first_win', 100, _at),
        XpEvent('win', 'm1', 50, _at),
        XpEvent('match', 'm1', 100, _at),
        XpEvent('match', 'm0', 100, _at.subtract(const Duration(days: 2))),
      ]);
}

class _Repo extends MockGamificationRepository {
  int seenCalls = 0;
  @override
  Future<void> markAchievementsSeen() async => seenCalls++;
}

Widget _app(_Repo repo, {bool reduce = false, LifecycleMatch? m, RatingDetail? r, AchievementsData? a}) => ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('me'),
        matchProvider('m1').overrideWith((ref) => Stream.value(m ?? _match())),
        myRatingProvider.overrideWith((ref) async => r ?? _rating()),
        achievementsProvider.overrideWith((ref) async => a ?? _achData()),
        gamificationRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 900), disableAnimations: reduce),
        child: const PostMatchScreen(matchId: 'm1'),
      )),
    );

void main() {
  group('resumen (datos del servidor)', () {
    test('ELO del historial de este partido, XP de sus eventos y logros de la misma transacción', () {
      final s = PostMatchSummary.build(m: _match(), uid: 'me', ratings: _rating(), ach: _achData(later: true));
      expect(s.won, isTrue);
      expect((s.eloBefore, s.eloDelta, s.eloAfter), (1194, 16, 1210));
      expect(s.tierUp, isTrue);                                   // 1194 Principiante → 1210 Intermedio
      expect(s.tierAfter, 'Intermedio');
      expect(s.xpLines.map((l) => l.xp), containsAll([100, 50, 100]));
      expect(s.xpGained, 250);
      expect(s.xpAfter, 550);                                     // sin los 150 XP del partido posterior
      expect(s.achievements.single.id, 'first_win');
      expect(s.partner, 'Lucía');
      expect(s.rivals, ['Ana', 'Bea']);
      expect(s.leveledUp, levelForXp(300) < levelForXp(550));
    });

    test('sin datos de XP ni historial: esos bloques no se inventan', () {
      final s = PostMatchSummary.build(m: _match(), uid: 'me');
      expect(s.hasXp, isFalse);
      expect(s.achievements, isEmpty);
      expect(s.eloDelta, 16);                                     // el cambio del partido sí viene del servidor
    });

    test('derrota: mensaje respetuoso, nunca «Derrota» ni «has perdido»', () {
      final m = _match(sets: const [SetScore(6, 7), SetScore(4, 6)]);
      final s = PostMatchSummary.build(m: m, uid: 'me', ratings: _rating(delta: -14));
      expect(s.won, isFalse);
      expect(s.headline, 'Buen partido');
      expect('${s.headline} ${s.subline}'.toLowerCase(), isNot(anyOf(contains('derrota'), contains('perdi'))));
      expect(s.subline, contains('detalles'));                    // 6-7 fue ajustado
      expect(s.score, '6-7  4-6');                                // desde mi lado
    });
  });

  group('secuencia', () {
    setUp(() {
      final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first as TestFlutterView;
      v.physicalSize = const Size(390, 1400);
      v.devicePixelRatio = 1;
      addTearDown(v.reset);
      SharedPreferences.setMockInitialValues({});
      AppHaptics.log.clear();
    });

    testWidgets('«Saltar» visible desde el principio y lleva al estado final; una vibración por evento', (t) async {
      final repo = _Repo();
      await t.pumpWidget(_app(repo));
      await t.pump(); await t.pump(); await t.pump();
      expect(find.text('Saltar'), findsOneWidget);
      expect(find.text('Victoria'), findsOneWidget);
      await t.pump(Motion.normal);
      await t.tap(find.text('Saltar'));
      await t.pump();
      await t.pump(Motion.normal);
      expect(find.text('1210'), findsOneWidget);                  // ELO final
      expect(find.text('+250 XP'), findsOneWidget);
      expect(find.text('Primera victoria'), findsOneWidget);
      expect(find.text('Compartir'), findsOneWidget);
      expect(repo.seenCalls, 1);                                  // seen_at en el servidor
      expect(AppHaptics.log.where((k) => k == 'success').length, lessThanOrEqualTo(1));
      expect(await PostMatchSeen.isSeen('m1'), isTrue);
    });

    testWidgets('secuencia completa: victoria vibra una vez (éxito) y el logro una vez (media)', (t) async {
      final repo = _Repo();
      await t.pumpWidget(_app(repo));
      for (var i = 0; i < 80; i++) { await t.pump(const Duration(milliseconds: 100)); }   // timing
      expect(AppHaptics.log.where((k) => k == 'success').length, 1);
      expect(AppHaptics.log.where((k) => k == 'medium').length, 1);
      expect(find.text('Compartir'), findsOneWidget);
    });

    testWidgets('reducir movimiento: estado final directo, sin animar', (t) async {
      await t.pumpWidget(_app(_Repo(), reduce: true));
      await t.pump(); await t.pump(); await t.pump();
      expect(find.text('1210'), findsOneWidget);
      expect(find.text('Compartir'), findsOneWidget);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('derrota: no vibra y no usa el color como única señal', (t) async {
      final m = _match(sets: const [SetScore(3, 6), SetScore(4, 6)]);
      await t.pumpWidget(_app(_Repo(), reduce: true, m: m, r: _rating(delta: -14), a: _achData()));
      await t.pump(); await t.pump(); await t.pump();
      expect(find.text('Buen partido'), findsOneWidget);
      expect(find.text('−14'), findsOneWidget);                   // signo + número (y flecha), no solo color
      expect(AppHaptics.log.where((k) => k == 'success'), isEmpty);
    });
  });

  group('imagen para compartir', () {
    final cases = {
      'victoria': PostMatchSummary.build(m: _match(), uid: 'me', ratings: _rating(), ach: _achData()),
      'derrota 3 sets': PostMatchSummary.build(m: _match(sets: const [SetScore(6, 4), SetScore(6, 7), SetScore(10, 12)]), uid: 'me', ratings: _rating(delta: -14)),
      'solo resultado': PostMatchSummary.build(m: _match(), uid: 'me'),
    };
    for (final c in cases.entries) {
      for (final f in ShareSize.values) {
        test('${c.key} · ${f.name}: sin solapes, nada fuera y todos los glifos', () {
          final log = ShareLayoutLog();
          PostMatchSharePainter(c.value, log: log).paint(Canvas(ui.PictureRecorder(), Offset.zero & f.size), f.size);
          final pr = layoutProblems(log, f.size, allowTruncatedNames: false);
          expect(pr, isEmpty, reason: pr.join('\n'));
        });
      }
    }
  });
}

