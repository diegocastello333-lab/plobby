import 'dart:math' as math;

/// Réplica EXACTA de la función SQL `apply_match_rating` (migración 20261118_policies_rating_storage.sql):
/// pareja contra pareja con la media de ELO de cada equipo, K = 32, redondeo al entero más cercano y límites de
/// `rating_config` (800–2000 por defecto).
///
/// El ELO oficial lo calcula y escribe SIEMPRE el servidor al confirmar el partido (el cliente no tiene permisos de
/// escritura en `player_ratings`). Esta clase solo sirve para mostrar una ESTIMACIÓN antes de confirmar y para
/// probar que la fórmula del cliente y la del servidor coinciden (test/elo_calculator_test.dart usa valores reales
/// obtenidos ejecutando la función SQL).
class EloCalculator {
  const EloCalculator({this.k = 32, this.minRating = 800, this.maxRating = 2000});
  final double k;
  final int minRating, maxRating;

  /// Probabilidad esperada de que gane el equipo con media [a] frente a [b].
  static double expected(double a, double b) => 1 / (1 + math.pow(10, (b - a) / 400));

  /// Cambio de ELO de cada jugador. [team1]/[team2]: id → ELO antes del partido; [winnerTeam]: 1 o 2.
  /// Un partido sin ganador (empate en sets) no cambia nada, igual que en SQL.
  Map<String, int> deltas({required Map<String, int> team1, required Map<String, int> team2, required int? winnerTeam}) {
    if (winnerTeam != 1 && winnerTeam != 2) return {for (final id in [...team1.keys, ...team2.keys]) id: 0};
    double avg(Map<String, int> t) => t.values.fold<int>(0, (s, x) => s + x) / t.length;
    final e1 = expected(avg(team1), avg(team2));
    int delta(int elo, int team) {
      final score = team == winnerTeam ? 1.0 : 0.0, exp = team == 1 ? e1 : 1 - e1;
      final d = _roundHalfAwayFromZero(k * (score - exp));
      return (elo + d).clamp(minRating, maxRating) - elo;           // greatest(min, least(max, elo + d)) - elo
    }
    return {for (final e in team1.entries) e.key: delta(e.value, 1), for (final e in team2.entries) e.key: delta(e.value, 2)};
  }

  /// `round(numeric)` de PostgreSQL redondea .5 alejándose de cero; `double.round()` de Dart hace lo mismo.
  static int _roundHalfAwayFromZero(double x) => x.round();
}
