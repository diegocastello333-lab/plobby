import '../domain/rating_models.dart';

/// Solo lectura. No existe ningún método que escriba ELO: el cálculo vive en el backend
/// (función `apply_match_rating`, ejecutada por trigger al confirmar un partido).
abstract class RatingRepository {
  Future<RatingDetail> myRating();
}
