import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/match_recap/application/recap_painter.dart';
import 'package:plobby/features/match_recap/domain/recap_data.dart';

/// El partido REAL que no mostraba la vista previa (24 nov 2026): amistoso confirmado, sin pista, 10 s de duración,
/// ELO ±16 y fotos de los cuatro jugadores.
void main() {
  test('Share Match con los datos del partido real: las 3 plantillas × 3 formatos se pintan enteras', () async {
    final codec = await ui.instantiateImageCodec(File('test/fixtures/avatar_sample.jpg').readAsBytesSync(), targetWidth: 400);
    final photo = (await codec.getNextFrame()).image;
    const w = [RecapPlayer(id: 'd', name: 'Diego Castello', avatarUrl: 'x'), RecapPlayer(id: 'b', name: 'Antonio Cuesta', avatarUrl: 'x')];
    const o = [RecapPlayer(id: 'c', name: 'Lucía Martín', avatarUrl: 'x'), RecapPlayer(id: 'e', name: 'Javi Ortega', avatarUrl: 'x')];
    for (final stats in [null, const RecapUserStats(played: 1, winRate: 100, streak: 1)]) {
      final d = RecapData(matchId: 'm', winners: w, opponents: o, sets: const [(6, 3), (6, 4)], winnerIsTeam1: true, playedAt: DateTime(2026, 11, 16, 14, 6),
          club: 'Club La Moraleja', isLeague: false, durationSeconds: 10, eloDelta: 16, eloBefore: 1466, eloAfter: 1482, stats: stats, userWon: true, userName: 'Diego Castello');
      for (final t in RecapTemplate.values) {
        for (final f in RecapFormat.values) {
          final png = await RecapPainter.toPng(d, t, f, images: {for (final p in [...w, ...o]) p.id: photo});
          expect(png.length, greaterThan(20000), reason: '${t.name}/${f.name}/stats=${stats != null}');
        }
      }
    }
  });
}
