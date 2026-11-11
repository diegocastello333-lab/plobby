import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_rating_repository.dart';
import '../data/rating_repository.dart';
import '../domain/rating_models.dart';

final ratingRepositoryProvider = Provider<RatingRepository>((ref) => MockRatingRepository());
final myRatingProvider = FutureProvider<RatingDetail>((ref) => ref.read(ratingRepositoryProvider).myRating());
final historyRangeProvider = StateProvider<HistoryRange>((ref) => HistoryRange.m3);
