// Banco de pruebas de movimiento (NO forma parte de la app ni de la APK). Sirve para medir la fluidez de las
// animaciones en Chrome con la CPU ralentizada: `flutter build web -t tool/motion_lab/main.dart`.
// Usa los repositorios de demostración y, para el resumen post-partido, datos de ejemplo fijos.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/celebration.dart';
import 'package:plobby/features/feed/presentation/feed_screen.dart';
import 'package:plobby/features/gamification/application/gamification_providers.dart';
import 'package:plobby/features/gamification/domain/gamification_models.dart';
import 'package:plobby/features/gamification/presentation/achievements_screen.dart';
import 'package:plobby/features/gamification/presentation/friends_ranking_screen.dart';
import 'package:plobby/features/matches/application/lifecycle_providers.dart';
import 'package:plobby/features/matches/domain/match_lifecycle.dart';
import 'package:plobby/features/matches/domain/match_models.dart';
import 'package:plobby/features/matches/presentation/post_match_screen.dart';
import 'package:plobby/features/rating/application/rating_providers.dart';
import 'package:plobby/features/rating/domain/rating_models.dart';
import 'package:plobby/features/rating/presentation/elo_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _at = DateTime.utc(2026, 11, 20, 21);
const _scale = RatingScale(800, 2000, [RatingTier('Principiante', 800), RatingTier('Intermedio', 1200), RatingTier('Avanzado', 1400), RatingTier('Experto', 1600)]);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await (await SharedPreferences.getInstance()).clear(); } catch (_) {}   // cada carga vuelve a celebrar
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const _Menu()),
    GoRoute(path: '/pm', builder: (_, __) => const PostMatchScreen(matchId: 'm1')),
    GoRoute(path: '/cel', builder: (_, __) => const _CelebrationLauncher()),
    GoRoute(path: '/ranking', builder: (_, __) => const FriendsRankingScreen()),
    GoRoute(path: '/achievements', builder: (_, __) => const AchievementsScreen()),
    GoRoute(path: '/rating', builder: (_, __) => const EloDetailScreen()),
    GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
  ]);
  runApp(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      matchProvider('m1').overrideWith((ref) => Stream.value(LifecycleMatch(
            id: 'm1', type: MatchType.friendly, scheduledAt: _at, endedAt: _at, club: 'Club Alameda', status: MatchStatus.confirmed, createdBy: 'me',
            sets: const [SetScore(6, 4), SetScore(4, 6), SetScore(10, 7)],
            players: const [
              MatchPlayer(id: 'me', name: 'Diego Castelló', team: 1, isCaptain: true, elo: 1210),
              MatchPlayer(id: 'p', name: 'Lucía Pérez', team: 1),
              MatchPlayer(id: 'r1', name: 'Ana Ruiz', team: 2, isCaptain: true),
              MatchPlayer(id: 'r2', name: 'Bea Gil', team: 2),
            ],
            eloDelta: const {'me': 16}))),
      myRatingProvider.overrideWith((ref) async => RatingDetail(name: 'Diego', username: 'diego', elo: 1210, bestElo: 1210, delta30: 16,
          confirmedMatches: 10, wins: 6, losses: 4, scale: _scale,
          history: [RatingChange(matchId: 'm1', at: _at, won: true, score: '6-4 4-6 10-7', opponents: 'Ana y Bea', before: 1194, delta: 16)])),
      achievementsProvider.overrideWith((ref) async => AchievementsData(xp: 550, level: 2, levelFloor: xpForLevel(2), levelCeiling: xpForLevel(3),
          items: [AchievementItem(id: 'first_win', category: 'wins', title: 'Primera victoria', description: 'Gana tu primer partido confirmado.',
              icon: 'trophy', goal: 1, xp: 100, unlockedAt: _at, seen: false)],
          history: [XpEvent('achievement', 'first_win', 100, _at), XpEvent('win', 'm1', 50, _at), XpEvent('match', 'm1', 100, _at)])),
    ],
    child: MaterialApp.router(debugShowCheckedModeBanner: false, theme: buildPlobbyTheme(), routerConfig: router),
  ));
}

class _Menu extends StatelessWidget {
  const _Menu();
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        for (final (p, l) in const [('/pm', 'Resumen post-partido'), ('/cel', 'Celebración'), ('/ranking', 'Ranking'), ('/achievements', 'Logros'),
          ('/rating', 'Mi rating'), ('/feed', 'Feed')])
          ListTile(title: Text(l), onTap: () => context.push(p)),
      ])));
}

class _CelebrationLauncher extends StatefulWidget {
  const _CelebrationLauncher();
  @override
  State<_CelebrationLauncher> createState() => _CelebrationLauncherState();
}

class _CelebrationLauncherState extends State<_CelebrationLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(showCelebration(context,
        const Celebration(eventKey: 'lab', title: '¡Nivel 4!', text: 'Has subido al nivel 4.'))));
  }
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
