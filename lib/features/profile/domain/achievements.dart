import 'models.dart';
import 'stats_calculator.dart';

class Achievement {
  const Achievement({required this.id, required this.title, required this.description, required this.current, required this.goal});
  final String id, title, description;
  final int current, goal;
  bool get unlocked => current >= goal;
  double get progress => (current / goal).clamp(0, 1).toDouble();
}

List<Achievement> buildAchievements({required StatsCalculator calc, required List<MatchResult> matches, required int leagues, required int eloGain12m}) {
  final conf = calc.confirmed(matches);
  final streak = calc.streak(matches);
  final partners = conf.map((m) => m.partner.id).toSet().length;
  return [
    Achievement(id: 'first', title: 'Primer partido', description: 'Jugaste tu primer partido.', current: conf.length, goal: 1),
    Achievement(id: 'fire', title: 'En racha', description: 'Gana 5 partidos seguidos.', current: streak.best, goal: 5),
    Achievement(id: 'unbeatable', title: 'Imbatible', description: 'Gana 10 partidos consecutivos.', current: streak.best, goal: 10),
    Achievement(id: 'social', title: 'Jugador social', description: 'Juega con 10 compañeros distintos.', current: partners, goal: 10),
    Achievement(id: 'competitor', title: 'Competidor', description: 'Participa en 5 ligas.', current: leagues, goal: 5),
    Achievement(id: 'rising', title: 'Estrella emergente', description: 'Mejora tu ELO en 100 puntos.', current: eloGain12m < 0 ? 0 : eloGain12m, goal: 100),
  ];
}
