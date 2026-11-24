import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:plobby/core/net/net_activity.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/loading_bar.dart';
import 'package:plobby/features/feed/domain/feed_models.dart';
import 'package:plobby/features/feed/presentation/feed_screen.dart';

/// Pulido del 24 nov 2026: barra de carga global, reacciones desplegadas, racha legible, «+» y pestaña del Feed.
void main() {
  testWidgets('la barra de carga solo aparece si algo tarda más de 0,4 s y se va al terminar', (t) async {
    await t.pumpWidget(const MaterialApp(home: LoadingBar(child: SizedBox.expand())));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    NetActivity.begin();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsNothing, reason: 'lo rápido no parpadea');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    NetActivity.end();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(NetActivity.inFlight.value, 0);
  });

  testWidgets('las cinco reacciones se ven sin pulsación larga', (t) async {
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(child: MaterialApp(theme: buildPlobbyTheme(), home: const FeedScreen())));
    for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 250)); }
    for (final r in ReactionType.values) {
      expect(find.bySemanticsLabel(RegExp('^Reaccionar con ${r.emoji}')), findsWidgets, reason: r.name);
    }
    expect(t.takeException(), isNull);
  });

  test('número de la racha en tinta sobre la llama lima; hueco del icono del Feed = color de la barra; «+» 42 px', () {
    expect(File('lib/features/home/presentation/home_screen.dart').readAsStringSync(), contains('color: c.streak > 0 ? AppColors.brandInk'));
    final shell = File('lib/core/router/app_shell.dart').readAsStringSync();
    expect(shell, contains('holeColor: AppMaterials.tabBar'));
    expect(shell, contains('static const tabSize = 42.0;'));
  });
}
