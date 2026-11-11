import 'models.dart';

enum StatsPeriod { all, d30, d90 }
enum EloRange { d30, d90, d365 }

int _days(StatsPeriod p) => switch (p) { StatsPeriod.all => 100000, StatsPeriod.d30 => 30, StatsPeriod.d90 => 90 };
int eloRangeDays(EloRange r) => switch (r) { EloRange.d30 => 30, EloRange.d90 => 90, EloRange.d365 => 365 };

class Stats {
  const Stats({this.played = 0, this.won = 0, this.sw = 0, this.sl = 0, this.gw = 0, this.gl = 0});
  final int played, won, sw, sl, gw, gl;
  int get lost => played - won;
  int get winRate => played == 0 ? 0 : (won * 100 / played).round();
}

class Streak {
  const Streak(this.current, this.best);
  final int current, best;
}

class EloPoint {
  const EloPoint(this.date, this.elo);
  final DateTime date;
  final int elo;
}

class StatsCalculator {
  StatsCalculator({required this.now});
  final DateTime now;

  /// Solo partidos confirmados, de más reciente a más antiguo.
  List<MatchResult> confirmed(List<MatchResult> all) =>
      all.where((m) => m.confirmed).toList()..sort((a, b) => b.playedAt.compareTo(a.playedAt));

  List<MatchResult> inPeriod(List<MatchResult> all, StatsPeriod p) {
    final limit = now.subtract(Duration(days: _days(p)));
    return confirmed(all).where((m) => !m.playedAt.isBefore(limit)).toList();
  }

  Stats stats(List<MatchResult> all, StatsPeriod p) {
    var won = 0, sw = 0, sl = 0, gw = 0, gl = 0;
    final list = inPeriod(all, p);
    for (final m in list) {
      if (m.won) won++;
      for (final s in m.sets) {
        s.$1 > s.$2 ? sw++ : sl++;
        gw += s.$1;
        gl += s.$2;
      }
    }
    return Stats(played: list.length, won: won, sw: sw, sl: sl, gw: gw, gl: gl);
  }

  /// La racha ignora el filtro de periodo y los partidos sin confirmar.
  Streak streak(List<MatchResult> all) {
    final c = confirmed(all);
    var current = 0;
    for (final m in c) {
      if (!m.won) break;
      current++;
    }
    var best = 0, run = 0;
    for (final m in c) {
      if (m.won) { run++; if (run > best) best = run; } else { run = 0; }
    }
    return Streak(current, best);
  }

  /// Serie de ELO reconstruida hacia atrás desde el ELO actual.
  List<EloPoint> eloSeries(List<MatchResult> all, int currentElo, EloRange r) {
    final c = confirmed(all);
    final days = eloRangeDays(r);
    final limit = now.subtract(Duration(days: days));
    var after = currentElo;
    final pts = <EloPoint>[];
    var atLimit = currentElo;
    for (final m in c) {
      if (m.playedAt.isBefore(limit)) break;
      pts.add(EloPoint(m.playedAt, after));
      after -= m.eloDelta;
      atLimit = after;
    }
    return [EloPoint(limit, atLimit), ...pts.reversed, EloPoint(now, currentElo)];
  }

  int eloChange(List<MatchResult> all, int currentElo, EloRange r) {
    final s = eloSeries(all, currentElo, r);
    return s.last.elo - s.first.elo;
  }

  /// Nivel calculado a partir del ELO (1.0 – 7.0). Distinto del nivel declarado.
  double estimatedLevel(int elo) => ((elo - 900) / 140).clamp(1.0, 7.0).toDouble();

  String category(int elo) =>
      elo < 1200 ? 'Principiante' : elo < 1400 ? 'Intermedio' : elo < 1600 ? 'Avanzado' : 'Experto';

  ({int played, int won}) bySide(List<MatchResult> all, PlaySide s) {
    final l = confirmed(all).where((m) => m.side == s);
    return (played: l.length, won: l.where((m) => m.won).length);
  }

  Map<String, ({int played, int won})> withPartners(List<MatchResult> all) {
    final out = <String, ({int played, int won})>{};
    for (final m in confirmed(all)) {
      final p = out[m.partner.id] ?? (played: 0, won: 0);
      out[m.partner.id] = (played: p.played + 1, won: p.won + (m.won ? 1 : 0));
    }
    return out;
  }

  /// Registro (victorias, derrotas) contra cada rival.
  Map<String, ({int won, int lost})> headToHead(List<MatchResult> all) {
    final out = <String, ({int won, int lost})>{};
    for (final m in confirmed(all)) {
      for (final o in m.opponents) {
        final r = out[o.id] ?? (won: 0, lost: 0);
        out[o.id] = (won: r.won + (m.won ? 1 : 0), lost: r.lost + (m.won ? 0 : 1));
      }
    }
    return out;
  }
}
