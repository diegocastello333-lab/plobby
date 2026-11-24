import 'dart:io';
import 'dart:typed_data';
import 'package:plobby/core/net/pixel_decode.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/match_recap/application/recap_painter.dart';
import 'package:plobby/features/match_recap/domain/recap_data.dart';
import 'package:plobby/features/share_stats/application/share_card_painter.dart';
import 'support/share_fixtures.dart';

/// Imágenes para compartir con FOTOS DE PERFIL reales (JPEG apaisado y PNG con transparencia, como las del almacenamiento):
/// se generan en todas las plantillas y formatos sin errores y la foto aparece (no el círculo gris ni las iniciales).
Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync(), targetWidth: 400);
  return (await codec.getNextFrame()).image;
}

void main() {
  test('Share Match: 3 plantillas × 3 formatos con fotos reales de los 4 jugadores', () async {
    final jpg = await _decode('test/fixtures/avatar_sample.jpg'), png = await _decode('test/fixtures/avatar_sample.png');
    final d = recapCases['normal']!;
    final imgs = <String, ui.Image>{for (final (i, p) in [...d.winners, ...d.opponents].indexed) p.id: i.isEven ? jpg : png};
    for (final t in RecapTemplate.values) {
      for (final f in RecapFormat.values) {
        final bytes = await RecapPainter.toPng(d, t, f, images: imgs);
        expect(bytes.length, greaterThan(10000), reason: '${t.name}/${f.name}');
        expect(bytes.sublist(1, 4), [0x50, 0x4E, 0x47], reason: 'es un PNG');   // «PNG»
      }
    }
  });

  test('Compartir mis stats: la foto de perfil se dibuja; sin foto, el avatar de Plobby o las iniciales (no un círculo gris)', () async {
    final photo = await _decode('test/fixtures/avatar_sample.png');
    ShareCardData data({ui.Image? avatar, String? avatarId}) => ShareCardData(name: 'Diego Castello', username: 'diego.c', elo: 1482, eloDelta: 60,
        category: 'Avanzado', played: 9, winRate: 78, wins: 7, losses: 2, streak: 5, bestStreak: 6, periodLabel: 'Últimos 30 días',
        last: const [true, true, false], avatar: avatar, avatarId: avatarId);
    Future<ui.Color> centerOfAvatar(ShareCardData d) async {
      final png = await ShareCardPainter.toPng(d, ShareTemplate.performance, ShareFormat.story);
      final img = await (await ui.instantiateImageCodec(png)).getNextFrame().then((f) => f.image);
      final bd = (await img.toByteData())!;
      // centro del avatar: margen + radio (105) en x; 230 + 105 en y (formato story)
      const x = 80 + 105, y = 230 + 105;
      final o = (y * img.width + x) * 4;
      return ui.Color.fromARGB(bd.getUint8(o + 3), bd.getUint8(o), bd.getUint8(o + 1), bd.getUint8(o + 2));
    }
    final grey = await centerOfAvatar(data());
    final withPhoto = await centerOfAvatar(data(avatar: photo));
    final withPreset = await centerOfAvatar(data(avatarId: 'a1'));
    expect(withPhoto, isNot(grey), reason: 'la foto se ve');
    expect(withPreset, isNot(grey), reason: 'el avatar de Plobby se ve');
    expect(grey, isNot(const ui.Color(0xFF8A938D)), reason: 'ya no es el círculo gris «sage»');
  });

  test('decodificación en Dart (la que usa la web): JPEG y PNG reales a píxeles, reducidos al ancho pedido', () async {
    for (final f in ['test/fixtures/avatar_sample.jpg', 'test/fixtures/avatar_sample.png']) {
      final img = await decodeToPixels(File(f).readAsBytesSync(), 120);
      expect(img, isNotNull, reason: f);
      expect(img!.width, lessThanOrEqualTo(120));
      final bytes = await RecapPainter.toPng(recapCases['normal']!, RecapTemplate.result, RecapFormat.story, images: {'a': img});
      expect(bytes.length, greaterThan(10000));
    }
    expect(await decodeToPixels(Uint8List.fromList([1, 2, 3]), 100), isNull, reason: 'bytes que no son imagen → sin foto, sin excepción');
  });

  test('duración corta: «<1 min» en vez de «0 min»', () {
    expect(recapDuration(10), '<1 min');
    expect(recapDuration(125), '2 min');
  });

  test('sello de verificado en las imágenes: aparece en el jugador verificado y no en los demás', () async {
    const vid = '48eee197-dc9e-4f4f-bddd-b45f8b88c3a0';
    ShareCardData data(bool v) => ShareCardData(name: 'Diego Castello', username: 'diego.c', elo: 1482, eloDelta: 60, category: 'Avanzado',
        played: 9, winRate: 78, wins: 7, losses: 2, streak: 5, bestStreak: 6, periodLabel: 'Últimos 30 días', last: const [true], verified: v);
    final a = await ShareCardPainter.toPng(data(false), ShareTemplate.performance, ShareFormat.story);
    final b = await ShareCardPainter.toPng(data(true), ShareTemplate.performance, ShareFormat.story);
    expect(a, isNot(equals(b)), reason: 'stats: con sello la imagen cambia');
    final base = recapCases['normal']!;
    RecapData withIds(String firstId) => RecapData(matchId: base.matchId, winners: [RecapPlayer(id: firstId, name: base.winners.first.name), base.winners[1]],
        opponents: base.opponents, sets: base.sets, winnerIsTeam1: true, playedAt: base.playedAt, club: base.club, isLeague: false);
    for (final t in RecapTemplate.values) {
      final plain = await RecapPainter.toPng(withIds('x'), t, RecapFormat.story), seal = await RecapPainter.toPng(withIds(vid), t, RecapFormat.story);
      expect(plain, isNot(equals(seal)), reason: 'Share Match ${t.name}: el verificado lleva sello');
    }
  });
}
