import 'package:plobby/features/match_recap/domain/recap_data.dart';
import 'package:plobby/features/share_stats/application/share_card_painter.dart';

/// Datos de prueba de las imágenes para compartir: casos normales y extremos (nombres largos, 3 sets, cifras de 1 a 4
/// dígitos, ELO negativo, sin duración/ELO, liga con nombre largo, club largo).
RecapPlayer p(String id, String name, {String? avatarId}) => RecapPlayer(id: id, name: name, avatarId: avatarId);

final recapCases = <String, RecapData>{
  'normal': RecapData(matchId: 'm1', winners: [p('a', 'Diego Castello'), p('b', 'Laura García')], opponents: [p('c', 'Marcos Ruiz'), p('d', 'Ana Pérez')],
      sets: const [(6, 3), (6, 4)], winnerIsTeam1: true, playedAt: DateTime(2026, 11, 13, 19, 30), club: 'Club La Moraleja', isLeague: false,
      durationSeconds: 5400, eloDelta: 16, eloBefore: 1466, eloAfter: 1482, stats: const RecapUserStats(played: 24, winRate: 67, streak: 3), userWon: true, userName: 'Diego'),
  'largo': RecapData(matchId: 'm2',
      winners: [p('a', 'Maximiliano Alejandro Fernández-Villaverde'), p('b', 'Guadalupe Concepción Bartolomé')],
      opponents: [p('c', 'Bartholomew Christopherson'), p('d', 'Anastasiopoulou Konstantina')],
      sets: const [(7, 6), (4, 6), (7, 5)], winnerIsTeam1: false, playedAt: DateTime(2026, 9, 28, 9, 5),
      club: 'Real Sociedad Deportiva de Pádel Indoor Valdebebas Norte', court: 'Pista Central Cubierta 12', isLeague: true,
      leagueName: 'Liga Interclubes Comunidad de Madrid Temporada de Otoño', durationSeconds: 11640, eloDelta: -24, eloBefore: 1999, eloAfter: 1975,
      stats: const RecapUserStats(played: 1287, winRate: 100, streak: 0), userWon: false, userName: 'Bartholomew'),
  'minimo': RecapData(matchId: 'm3', winners: [p('a', 'Al'), p('b', 'Bo')], opponents: [p('c', 'Cy'), p('d', 'Di')], sets: const [(6, 0), (6, 0)],
      winnerIsTeam1: true, playedAt: DateTime(2026, 1, 2), club: '', isLeague: false),
  'tres_sets_sin_elo': RecapData(matchId: 'm4', winners: [p('a', 'Lucía Martín'), p('b', 'Álvaro Pérez')], opponents: [p('c', 'Sofía Gil'), p('d', 'Irene Vega')],
      sets: const [(6, 7), (7, 6), (10, 8)], winnerIsTeam1: true, playedAt: DateTime(2026, 6, 30, 21), club: 'Padel Chamberí', isLeague: false,
      durationSeconds: 7260, stats: const RecapUserStats(played: 7, winRate: 9, streak: 12), userWon: true),
};

ShareCardData card({String name = 'Diego Castello', String username = 'diego.c', int elo = 1482, int delta = 24, int played = 24, int winRate = 67,
        int wins = 16, int losses = 8, int streak = 3, int best = 5, String period = 'Noviembre', List<bool>? last, String? club = 'Club La Moraleja',
        String? partner = 'Laura García', String category = 'Avanzado'}) =>
    ShareCardData(name: name, username: username, elo: elo, eloDelta: delta, category: category, played: played, winRate: winRate, wins: wins,
        losses: losses, streak: streak, bestStreak: best, periodLabel: period, last: last ?? const [true, true, true, false, true, false, true, true],
        club: club, partner: partner);

final cardCases = <String, ShareCardData>{
  'normal': card(),
  'largo': card(name: 'Maximiliano Alejandro Fernández-Villaverde', username: 'maximiliano.fernandez.villaverde', elo: 1999, delta: -132,
      played: 1287, winRate: 100, wins: 1287, losses: 999, streak: 125, best: 999, period: 'Últimos 12 meses',
      club: 'Real Sociedad Deportiva de Pádel Indoor Valdebebas Norte', partner: 'Guadalupe Concepción Bartolomé', category: 'Intermedio-alto',
      last: List.generate(10, (i) => i.isEven)),
  'minimo': card(name: 'Al', username: 'al', elo: 800, delta: 0, played: 0, winRate: 0, wins: 0, losses: 0, streak: 0, best: 0, period: 'Hoy',
      club: null, partner: null, last: const []),
};
