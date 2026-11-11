/// Umbral de categoría tal y como lo define la configuración del sistema de rating (backend).
class RatingTier {
  final String name;
  final int from;
  const RatingTier(this.name, this.from);
}

class RatingScale {
  final int min, max;
  final List<RatingTier> tiers; // ordenados por `from`
  const RatingScale(this.min, this.max, this.tiers);
  double fraction(int elo) => ((elo - min) / (max - min)).clamp(0.0, 1.0);
  RatingTier tierOf(int elo) => tiers.lastWhere((t) => elo >= t.from, orElse: () => tiers.first);
  RatingTier? nextTier(int elo) {
    final i = tiers.indexOf(tierOf(elo));
    return i + 1 < tiers.length ? tiers[i + 1] : null;
  }
}

/// Una fila de `rating_history`: SOLO LECTURA. Lo escribe el servidor al confirmarse un partido.
class RatingChange {
  final String matchId;
  final DateTime at;
  final bool won;
  final String score, opponents;
  final int before, delta;
  const RatingChange({required this.matchId, required this.at, required this.won, required this.score, required this.opponents, required this.before, required this.delta});
  int get after => before + delta;
}

enum HistoryRange { d30, m3, m12, all }

class RatingDetail {
  final String name, username;
  final String? avatarUrl;
  final int elo, bestElo, delta30, confirmedMatches, wins, losses;
  final RatingScale scale;
  final List<RatingChange> history; // más reciente primero
  const RatingDetail({
    required this.name, required this.username, this.avatarUrl, required this.elo, required this.bestElo, required this.delta30,
    required this.confirmedMatches, required this.wins, required this.losses, required this.scale, required this.history,
  });
  int get winRate => confirmedMatches == 0 ? 0 : (wins * 100 / confirmedMatches).round();

  /// Puntos de la gráfica (ELO tras cada cambio) dentro del rango. Solo filtra datos ya calculados por el servidor.
  List<RatingChange> inRange(HistoryRange r, DateTime now) {
    final from = switch (r) {
      HistoryRange.d30 => now.subtract(const Duration(days: 30)),
      HistoryRange.m3 => now.subtract(const Duration(days: 90)),
      HistoryRange.m12 => now.subtract(const Duration(days: 365)),
      HistoryRange.all => DateTime.fromMillisecondsSinceEpoch(0),
    };
    return history.where((c) => c.at.isAfter(from)).toList().reversed.toList();
  }
}
