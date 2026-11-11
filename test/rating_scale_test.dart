import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/rating/data/mock_rating_repository.dart';
import 'package:plobby/features/rating/domain/rating_models.dart';

void main() {
  test('posición en la escala y categoría salen de la configuración', () async {
    final d = await MockRatingRepository().myRating();
    expect(d.scale.tierOf(1482).name, 'Avanzado');
    expect(d.scale.nextTier(1482)!.name, 'Experto');
    expect(d.scale.fraction(1400), closeTo(0.5, 1e-9));
  });
  test('el historial filtra por rango sin recalcular ELO', () async {
    final d = await MockRatingRepository().myRating();
    final now = DateTime.now();
    expect(d.inRange(HistoryRange.d30, now).length, 3);
    expect(d.history.first.after, d.history.first.before + d.history.first.delta);
  });
}
