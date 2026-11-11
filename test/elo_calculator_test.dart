import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/rating/domain/elo_calculator.dart';

/// Los valores esperados («golden») se obtuvieron ejecutando la función SQL `apply_match_rating` en el proyecto
/// Supabase dentro de una transacción revertida (ver README › Pruebas). Si cambias la fórmula en un lado, cámbiala
/// en el otro: estas pruebas fallarán si cliente y servidor dejan de coincidir.
void main() {
  const elo = EloCalculator();

  test('igualados (1500 vs 1500): el ganador suma 16 y el perdedor resta 16', () {
    final d = elo.deltas(team1: {'u1': 1500, 'u2': 1500}, team2: {'u3': 1500, 'u4': 1500}, winnerTeam: 1);
    expect(d, {'u1': 16, 'u2': 16, 'u3': -16, 'u4': -16});
  });

  test('sorpresa: gana la pareja con menor media (1408 vs 1500) ⇒ ±20 (golden SQL)', () {
    final d = elo.deltas(team1: {'u5': 1600, 'u6': 1400}, team2: {'u7': 1300, 'u1': 1516}, winnerTeam: 2);
    expect(d, {'u5': -20, 'u6': -20, 'u7': 20, 'u1': 20});
  });

  test('favorito claro (1062,5 vs 1548) gana ⇒ solo ±2 (golden SQL)', () {
    final d = elo.deltas(team1: {'u8': 805, 'u7': 1320}, team2: {'u5': 1580, 'u2': 1516}, winnerTeam: 2);
    expect(d, {'u8': -2, 'u7': -2, 'u5': 2, 'u2': 2});
  });

  test('la media es por equipo: los dos miembros de una pareja reciben el mismo cambio', () {
    final d = elo.deltas(team1: {'a': 1900, 'b': 1100}, team2: {'c': 1500, 'd': 1500}, winnerTeam: 1);
    expect(d['a'], d['b']);
    expect(d['c'], d['d']);
    expect(d['a'], -d['c']!);
  });

  test('límites de rating_config: nunca baja de 800 ni sube de 2000', () {
    final low = elo.deltas(team1: {'x': 801, 'y': 1500}, team2: {'z': 1150, 'w': 1150}, winnerTeam: 2);
    expect(801 + low['x']!, 800);                    // −16 recortado a −1
    expect(low['y'], isNot(low['x']));
    final high = elo.deltas(team1: {'x': 1995, 'y': 1005}, team2: {'z': 1500, 'w': 1500}, winnerTeam: 1);
    expect(1995 + high['x']!, 2000);
  });

  test('sin ganador (empate en sets) no cambia nada, igual que el servidor', () {
    expect(elo.deltas(team1: {'a': 1500, 'b': 1500}, team2: {'c': 1500, 'd': 1500}, winnerTeam: null).values, everyElement(0));
  });

  test('probabilidad esperada simétrica y en (0, 1)', () {
    expect(EloCalculator.expected(1500, 1500), closeTo(.5, 1e-9));
    expect(EloCalculator.expected(1600, 1400) + EloCalculator.expected(1400, 1600), closeTo(1, 1e-9));
    expect(EloCalculator.expected(2000, 800), lessThan(1));
  });

  test('suma cero entre equipos cuando ningún jugador toca los límites', () {
    for (final (a, b) in const [(1500, 1500), (1400, 1650), (1720, 1210), (1333, 1334)]) {
      for (final w in const [1, 2]) {
        final d = elo.deltas(team1: {'a1': a, 'a2': a}, team2: {'b1': b, 'b2': b}, winnerTeam: w);
        expect(d['a1']! + d['b1']!, 0, reason: '$a vs $b gana $w');
      }
    }
  });
}
