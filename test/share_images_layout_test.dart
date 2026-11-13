import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/share/canvas_text.dart';
import 'package:plobby/features/match_recap/application/recap_painter.dart';
import 'package:plobby/features/match_recap/domain/recap_data.dart';
import 'package:plobby/features/share_stats/application/share_card_painter.dart';
import 'support/layout_checks.dart';
import 'support/share_fixtures.dart';

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
            final pr = layoutProblems(log, f.size, allowTruncatedNames: c.key == 'largo');
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
            final pr = layoutProblems(log, size, allowTruncatedNames: c.key == 'largo');
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
