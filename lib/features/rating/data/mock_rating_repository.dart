import '../domain/rating_models.dart';
import 'rating_repository.dart';

/// DATOS MOCK (el cálculo real del ELO NO se hace aquí).
class MockRatingRepository implements RatingRepository {
  @override
  Future<RatingDetail> myRating() async {
    final now = DateTime.now();
    final h = <RatingChange>[
      RatingChange(matchId: 'm1', at: now.subtract(const Duration(days: 1)), won: true, score: '6-0 6-4', opponents: 'Lucía y Irene', before: 1474, delta: 8),
      RatingChange(matchId: 'm2', at: now.subtract(const Duration(days: 3)), won: true, score: '7-5 6-4', opponents: 'Pablo y Javi', before: 1462, delta: 12),
      RatingChange(matchId: 'm3', at: now.subtract(const Duration(days: 9)), won: false, score: '4-6 6-7', opponents: 'Carlos y Álvaro', before: 1470, delta: -8),
    ];
    return RatingDetail(
      name: 'Diego Castello', username: 'diego.c', elo: 1482, bestElo: 1490, delta30: 24, confirmedMatches: 42, wins: 28, losses: 14,
      scale: const RatingScale(800, 2000, [RatingTier('Principiante', 800), RatingTier('Intermedio', 1200), RatingTier('Avanzado', 1400), RatingTier('Experto', 1600)]),
      history: h,
    );
  }
}
