import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/auth/application/auth_providers.dart';
import 'package:plobby/features/auth/presentation/onboarding_screen.dart';
import 'package:plobby/features/auth/presentation/welcome_screen.dart';
import 'package:plobby/features/rating/application/rating_providers.dart';
import 'package:plobby/features/rating/domain/rating_models.dart';

/// V9 · Mi rating, compartir stats, bienvenida y onboarding (repositorios mock).
Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

Future<(GoRouter, ProviderContainer)> _app(WidgetTester t, String path, {double width = 390}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final c = ProviderContainer();
  addTearDown(c.dispose);
  late GoRouter r;
  await t.pumpWidget(UncontrolledProviderScope(container: c, child: Consumer(builder: (_, ref, __) { r = ref.watch(routerProvider); return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r); })));
  await _settle(t, 4);
  r.push(path);
  await _settle(t, 8);
  return (r, c);
}

void main() {
  testWidgets('Mi rating: ELO, explicación, factores y cambio de periodo del historial', (t) async {
    final (_, c) = await _app(t, '/rating');
    expect(find.text('MI RATING'), findsOneWidget);
    expect(find.text('Qué significa tu rating'), findsOneWidget);
    await t.scrollUntilVisible(find.text('12 meses'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('12 meses'));
    await _settle(t, 2);
    expect(c.read(historyRangeProvider), HistoryRange.m12);
    expect(t.takeException(), isNull);
  });

  testWidgets('Compartir mis stats: cambia plantilla, periodo y formato', (t) async {
    await _app(t, '/profile/share');
    expect(find.text('Compartir mis stats'), findsOneWidget);
    for (final o in ['Racha', '3 meses', 'Post 4:5']) {
      await t.scrollUntilVisible(find.text(o), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text(o));
      await t.pump();
      expect(t.getSemantics(find.bySemanticsLabel(o).first).flagsCollection.isSelected.toBoolOrNull(), isTrue, reason: o);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('Bienvenida: «Continuar con Google» inicia sesión (mock) y entra, sin errores de maquetación a 320 px', (t) async {
    final (r, c) = await _app(t, '/welcome', width: 320);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.bySemanticsLabel('Continuar con Google'));
    await _settle(t, 4);
    expect(c.read(authRepositoryProvider).currentUser, isNotNull);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.textContaining('No se pudo completar'), findsNothing);
    expect(r.routerDelegate.currentConfiguration.uri.path, '/home');
  });

  testWidgets('Onboarding: sin datos el paso 1 no avanza', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(child: MaterialApp(theme: buildPlobbyTheme(), home: OnboardingScreen(onDone: () {}))));
    await _settle(t, 6);
    expect(find.text('Cuéntanos quién eres'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Continuar'));
    await _settle(t, 3);
    expect(find.text('Cuéntanos quién eres'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(t.takeException(), isNull);
  });
}
