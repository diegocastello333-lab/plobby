import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/ambient_background.dart';
import 'package:plobby/core/widgets/motion_widgets.dart';
import 'package:plobby/features/tournaments/application/tournament_providers.dart';
import 'package:plobby/features/tournaments/presentation/competitions_screen.dart';

Future<void> _settle(WidgetTester t, [int n = 8]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

Future<(GoRouter, ProviderContainer)> _app(WidgetTester t, {bool reduceMotion = false}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late GoRouter r;
  late ProviderContainer c;
  await t.pumpWidget(ProviderScope(child: Consumer(builder: (ctx, ref, __) {
    r = ref.watch(routerProvider);
    c = ProviderScope.containerOf(ctx);
    return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: child!));
  })));
  await _settle(t);
  return (r, c);
}

/// Posición horizontal de la píldora lima del selector.
double _pillLeft(WidgetTester t) {
  final pill = find.descendant(of: find.byType(ScrollLinkedTabs), matching: find.byType(Positioned));
  return t.getTopLeft(pill.first).dx;
}

void main() {
  testWidgets('Competiciones: la píldora y el fondo siguen al dedo durante el deslizamiento y la sección cambia al soltar', (t) async {
    final (r, c) = await _app(t);
    r.go('/leagues');
    await _settle(t);
    expect(find.byType(AmbientBackground), findsOneWidget);
    final start = _pillLeft(t);
    final g = await t.startGesture(const Offset(330, 520));
    for (var i = 0; i < 8; i++) { await g.moveBy(const Offset(-15, 0)); await t.pump(const Duration(milliseconds: 16)); }
    final mid = _pillLeft(t);
    expect(mid, greaterThan(start), reason: 'la píldora se mueve mientras se arrastra, no al soltar');
    expect(CompetitionsScreen.page.value, inExclusiveRange(0.0, 1.0), reason: 'el fondo recibe la posición intermedia');
    for (var i = 0; i < 8; i++) { await g.moveBy(const Offset(-20, 0)); await t.pump(const Duration(milliseconds: 16)); }
    await g.up();
    await _settle(t);
    expect(c.read(competitionsTabProvider), 1);
    expect(CompetitionsScreen.page.value, 1.0);
    expect(find.text('Mis torneos'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Competiciones: tocar la pestaña anima hasta la sección; cambiarla desde fuera también', (t) async {
    final (r, c) = await _app(t);
    r.go('/leagues');
    await _settle(t);
    await t.tap(find.text('Torneos'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));    // primer fotograma: fija el inicio de la animación
    await t.pump(const Duration(milliseconds: 120));
    expect(CompetitionsScreen.page.value, inExclusiveRange(0.0, 1.0), reason: 'transición animada, no un salto');
    await _settle(t);
    expect(CompetitionsScreen.page.value, 1.0);
    c.read(competitionsTabProvider.notifier).state = 0;   // p. ej. desde un aviso
    await _settle(t);
    expect(CompetitionsScreen.page.value, 0.0);
    expect(t.takeException(), isNull);
  });

  testWidgets('con «reducir movimiento» el cambio de sección es inmediato', (t) async {
    final (r, _) = await _app(t, reduceMotion: true);
    r.go('/leagues');
    await _settle(t);
    await t.tap(find.text('Torneos'));
    await t.pump();
    await t.pump();
    expect(CompetitionsScreen.page.value, 1.0);
  });

  testWidgets('cambiar de pestaña inferior conserva el estado de cada sección (fundido sin reconstruir)', (t) async {
    final (r, c) = await _app(t);
    r.go('/leagues');
    await _settle(t);
    await t.tap(find.text('Torneos'));
    await _settle(t);
    r.go('/feed');
    await _settle(t);
    r.go('/leagues');
    await _settle(t);
    expect(c.read(competitionsTabProvider), 1);
    expect(find.text('Mis torneos'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Pressable: se encoge al pulsar y vuelve a su tamaño al soltar', (t) async {
    await t.pumpWidget(MaterialApp(home: Center(child: Pressable(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: const SizedBox(width: 100, height: 50))))));
    double scale() => t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    final g = await t.startGesture(t.getCenter(find.byType(Pressable)));
    await t.pump();
    expect(scale(), lessThan(1));
    await g.up();
    await t.pumpAndSettle();
    expect(scale(), 1);
  });

  test('las paletas del fondo solo usan colores de Plobby y se mezclan sin saltos', () {
    final m = AmbientPalette.lerp(AmbientPalette.leagues, AmbientPalette.tournaments, .5);
    expect(m.a, Color.lerp(AmbientPalette.leagues.a, AmbientPalette.tournaments.a, .5));
    expect(AmbientPalette.lerp(AmbientPalette.home, AmbientPalette.feed, 0).a, AmbientPalette.home.a);
  });
}
