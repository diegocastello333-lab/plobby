import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/home/presentation/home_screen.dart';

/// Inicio con los repositorios mock: se dibuja sin errores y cada acción sigue llevando a su pantalla.
void main() {
  late List<String> visited;

  Future<void> pumpHome(WidgetTester t, {Size size = const Size(390, 844)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    visited = [];
    GoRoute stub(String path) => GoRoute(path: path, builder: (_, s) { visited.add(s.uri.toString()); return const Scaffold(body: Text('destino')); });
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      for (final p in ['/friends', '/friends/add', '/rating', '/notifications', '/messages', '/profile', '/feed', '/match/:id/final']) stub(p),
    ]);
    await t.pumpWidget(ProviderScope(child: MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: router)));
    for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 300)); }
  }

  testWidgets('se dibuja sin errores con todas las secciones', (t) async {
    await pumpHome(t);
    expect(t.takeException(), isNull);
    for (final s in ['Próximos partidos', 'Últimas partidas de amigos', 'Últimos partidos jugados', 'Logros', 'Racha de victorias', 'Amigos', 'ELO']) {
      expect(find.text(s, skipOffstage: false), findsWidgets, reason: s);
    }
  });

  testWidgets('en pantalla estrecha (320 px) no hay desbordamientos', (t) async {
    await pumpHome(t, size: const Size(320, 640));
    expect(t.takeException(), isNull);
  });

  testWidgets('las tarjetas y botones del banner navegan a su pantalla', (t) async {
    for (final (label, dest) in const [('Añadir amigos', '/friends/add'), ('Notificaciones', '/notifications'), ('Mensajes', '/messages'), ('Ver mi perfil', '/profile')]) {
      await pumpHome(t);
      await t.tap(find.bySemanticsLabel(RegExp('^$label')).first);
      await t.pump(const Duration(milliseconds: 400));
      expect(visited, contains(dest), reason: label);
    }
    for (final (label, dest) in const [('Amigos:', '/friends'), ('ELO', '/rating')]) {
      await pumpHome(t);
      await t.tap(find.bySemanticsLabel(RegExp('^$label')).first);
      await t.pump(const Duration(milliseconds: 400));
      expect(visited, contains(dest), reason: label);
    }
  });

  testWidgets('la racha abre su hoja y un partido jugado abre el resultado final', (t) async {
    await pumpHome(t);
    await t.tap(find.bySemanticsLabel(RegExp('^Racha actual')).first);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(BottomSheet), findsOneWidget);
    await pumpHome(t);
    final card = find.bySemanticsLabel(RegExp(r'^(Victoria|Derrota) con'), skipOffstage: false).first;
    await t.ensureVisible(card);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(card);
    await t.pump(const Duration(milliseconds: 400));
    expect(visited.any((v) => v.startsWith('/match/') && v.endsWith('/final')), isTrue);
  });

  test('antetítulo de fecha de los partidos jugados', () {
    final now = DateTime(2026, 11, 12, 10);
    expect(playedEyebrow(DateTime(2026, 11, 12, 8), now), 'HOY');
    expect(playedEyebrow(DateTime(2026, 11, 11, 20), now), 'AYER');
    expect(playedEyebrow(DateTime(2026, 11, 6, 21), now), '6 NOV');
  });
}
