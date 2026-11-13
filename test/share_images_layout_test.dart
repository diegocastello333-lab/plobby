import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/share/canvas_text.dart';
import 'package:plobby/features/match_recap/application/recap_painter.dart';
import 'package:plobby/features/match_recap/domain/recap_data.dart';
import 'package:plobby/features/share_stats/application/share_card_painter.dart';
import 'support/share_fixtures.dart';

/// Caracteres que existen de verdad en un TTF (tabla `cmap`, formatos 4 y 12). Si un texto usa un carácter que la fuente
/// no tiene, en el móvil sale un cuadro o una fuente distinta: los tests lo detectan aquí.
Set<int> _cmap(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  final n = b.getUint16(4);
  var cmapOff = -1;
  for (var i = 0; i < n; i++) {
    final rec = 12 + i * 16;
    if (String.fromCharCodes([for (var k = 0; k < 4; k++) b.getUint8(rec + k)]) == 'cmap') cmapOff = b.getUint32(rec + 8);
  }
  final out = <int>{};
  final tables = b.getUint16(cmapOff + 2);
  for (var i = 0; i < tables; i++) {
    final sub = cmapOff + b.getUint32(cmapOff + 4 + i * 8 + 4);
    final fmt = b.getUint16(sub);
    if (fmt == 4) {
      final segX2 = b.getUint16(sub + 6), ends = sub + 14, starts = ends + segX2 + 2;
      for (var s = 0; s < segX2 ~/ 2; s++) {
        final end = b.getUint16(ends + s * 2), start = b.getUint16(starts + s * 2);
        for (var c = start; c <= end && c != 0xFFFF; c++) { out.add(c); }
      }
    } else if (fmt == 12) {
      final groups = b.getUint32(sub + 12);
      for (var g = 0; g < groups; g++) {
        final start = b.getUint32(sub + 16 + g * 12), end = b.getUint32(sub + 20 + g * 12);
        for (var c = start; c <= end; c++) { out.add(c); }
      }
    }
  }
  return out;
}

final _glyphs = {
  ShareFonts.inter: _cmap('assets/fonts/Inter-ExtraBold.ttf'),
  ShareFonts.unbounded: _cmap('assets/fonts/Unbounded-Bold.ttf'),
};

/// Todas las reglas de maquetación sobre el registro de un pintor. Devuelve los problemas encontrados.
List<String> _problems(ShareLayoutLog log, Size size, {required bool allowTruncatedNames}) {
  final out = <String>[];
  final canvas = Offset.zero & size, safe = canvas.deflate(24);
  final texts = log.texts.toList(), shapes = log.shapes.toList();
  for (final t in texts) {
    if (!safe.contains(t.rect.topLeft) || !safe.contains(t.rect.bottomRight)) out.add('fuera de la imagen: $t');
    if (t.container != null && !t.container!.deflate(6).inflate(.5).contains(t.rect.topLeft)) out.add('fuera de su caja: $t en ${t.container}');
    if (t.container != null && !t.container!.deflate(6).inflate(.5).contains(t.rect.bottomRight)) out.add('fuera de su caja: $t en ${t.container}');
    for (final r in (t.text ?? '').runes) {
      if (r == 0x20 || r == 0x2026) continue;
      if (!_glyphs[t.family]!.contains(r)) out.add('carácter «${String.fromCharCode(r)}» sin glifo en ${t.family}: $t');
    }
    // «…» solo en textos libres (nombres, club, liga…) y solo en el caso extremo; cifras y títulos, nunca.
    const free = {'nombre', 'usuario', 'club/pareja', 'marcador nombres', 'fecha/club', 'etiqueta', 'delta'};
    if (t.truncated && !(allowTruncatedNames && free.contains(t.label))) out.add('recortado con «…»: $t');
    for (final s in shapes) {
      if (overlaps(t.rect, s.rect, tolerance: 2)) out.add('texto sobre ${s.label}: $t');
    }
  }
  for (var i = 0; i < texts.length; i++) {
    for (var j = i + 1; j < texts.length; j++) {
      if (overlaps(texts[i].rect, texts[j].rect, tolerance: 1)) out.add('solape: ${texts[i]}  ↔  ${texts[j]}');
    }
  }
  return out;
}

void _paint(CustomPainter p, Size s) => p.paint(Canvas(ui.PictureRecorder(), Offset.zero & s), s);

void main() {
  group('Compartir mis stats', () {
    for (final c in cardCases.entries) {
      for (final tpl in ShareTemplate.values) {
        for (final f in ShareFormat.values) {
          test('${c.key} · ${tpl.name} · ${f.name}: sin solapes, recortes ni caracteres sin glifo', () {
            final log = ShareLayoutLog();
            _paint(ShareCardPainter(c.value, tpl, log: log), f.size);
            expect(log.texts, isNotEmpty);
            final pr = _problems(log, f.size, allowTruncatedNames: c.key == 'largo');
            expect(pr, isEmpty, reason: pr.join('\n'));
          });
        }
      }
    }
  });

  group('Match Recap', () {
    for (final c in recapCases.entries) {
      for (final tpl in RecapTemplate.values) {
        for (final f in RecapFormat.values) {
          test('${c.key} · ${tpl.name} · ${f.name}: sin solapes, recortes ni caracteres sin glifo', () {
            final log = ShareLayoutLog();
            final size = Size(f.width.toDouble(), f.height.toDouble());
            _paint(RecapPainter(c.value, tpl, f, log: log), size);
            expect(log.texts, isNotEmpty);
            final pr = _problems(log, size, allowTruncatedNames: c.key == 'largo');
            expect(pr, isEmpty, reason: pr.join('\n'));
          });
        }
      }
    }
  });

  test('las cifras y nombres de los casos normales se ven al tamaño de diseño (no se encogen)', () {
    final log = ShareLayoutLog();
    _paint(ShareCardPainter(cardCases['normal']!, ShareTemplate.performance, log: log), ShareFormat.story.size);
    for (final t in log.texts.where((t) => t.label.startsWith('valor') || t.label == 'nombre' || t.label == 'elo')) {
      expect(t.scale, 1, reason: '$t');
    }
  });

  test('el motor de texto ajusta antes de recortar y centra en la altura real de las mayúsculas', () {
    final f = ShareText.fit('Maximiliano Alejandro', 68, maxWidth: 500, minFontSize: 40);
    expect(f.truncated, isFalse);
    expect(f.width, lessThanOrEqualTo(500));
    expect(f.fontSize, inInclusiveRange(40, 68));
    final g = ShareText.fit('Maximiliano Alejandro Fernández-Villaverde', 68, maxWidth: 500, minFontSize: 50);
    expect((g.truncated, g.width <= 500.5, g.fontSize), (true, true, 50));
    final log = ShareLayoutLog();
    ShareText(Canvas(ui.PictureRecorder()), log: log).draw('88', 100, 300, 100, Colors.white, v: VAnchor.capCenter, family: ShareFonts.unbounded);
    expect(log.texts.single.rect.center.dy, closeTo(300, .5));   // cifras centradas exactamente en y
  });
}
