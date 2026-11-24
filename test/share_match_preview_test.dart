import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/match_recap/application/recap_painter.dart';
import 'package:plobby/features/match_recap/application/recap_providers.dart';
import 'package:plobby/features/match_recap/presentation/share_match_screen.dart';
import 'support/share_fixtures.dart';

/// La vista previa de Share Match salía en negro (app y web): dentro del AnimatedSwitcher el CustomPaint medía 0×0.
void main() {
  testWidgets('la vista previa ocupa todo su recuadro, también al cambiar de plantilla y formato', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [recapDataProvider.overrideWith((ref, id) => AsyncValue.data(recapCases['normal']!))],
      child: MaterialApp(theme: buildPlobbyTheme(), home: const ShareMatchScreen(matchId: 'm1')),
    ));
    await t.pump(const Duration(milliseconds: 500));
    Size previewSize() => t.renderObject<RenderCustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is RecapPainter).last).size;
    expect(previewSize().width, greaterThan(150));
    expect(previewSize().height, greaterThan(300));
    await t.tap(find.text('MATCH STATS'));
    await t.pump(const Duration(milliseconds: 600));
    expect(previewSize().width, greaterThan(150));
    await t.tap(find.text('Cuadrado 1:1'));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 200)); }
    final s = previewSize();
    expect(s.width, greaterThan(150));
    expect((s.width - s.height).abs(), lessThan(2), reason: 'cuadrado');
    expect(t.takeException(), isNull);
  });
}
