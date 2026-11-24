import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_rating_repository.dart';
import '../data/rating_repository.dart';
import '../domain/rating_models.dart';

final ratingRepositoryProvider = Provider<RatingRepository>((ref) => MockRatingRepository());
/// Rating con el histórico completo: solo la pantalla de detalle del ELO.
final myRatingProvider = FutureProvider<RatingDetail>((ref) => ref.read(ratingRepositoryProvider).myRating());

/// Rating con los últimos [homeHistory] cambios: Inicio y resumen post-partido (antes pedían 500 filas).
/// Si el detalle ya está cargado, se reutiliza en vez de pedirlo otra vez.
const homeHistory = 20;
final myRatingSummaryProvider = FutureProvider<RatingDetail>((ref) {
  // `exists` no crea el proveedor: leerlo sin más lanzaría la consulta de 500 filas que queremos evitar.
  if (ref.exists(myRatingProvider)) {
    final full = ref.read(myRatingProvider);
    if (full.hasValue) return full.value!;
  }
  return ref.read(ratingRepositoryProvider).myRating(historyLimit: homeHistory);
});
final historyRangeProvider = StateProvider<HistoryRange>((ref) => HistoryRange.m3);
