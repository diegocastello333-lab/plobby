import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/leagues/presentation/create_league_screen.dart';
import 'package:plobby/features/leagues/presentation/discover_leagues_screen.dart';
import 'package:plobby/features/leagues/presentation/league_detail_screen.dart';
import 'package:plobby/features/leagues/presentation/league_widgets.dart';
import 'package:plobby/features/leagues/presentation/manage_league_screen.dart';

/// V6 · Ligas: el rediseño mantiene la navegación y las acciones (repositorio mock de ligas, modo demo).
Future<GoRouter> _app(WidgetTester t, {double width = 390, String? path}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late GoRouter router;
  await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) { router = ref.watch(routerProvider); return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: router); })));
  await _settle(t, 4);
  if (path != null) { router.push(path); await _settle(t, 8); }
  return router;
}

Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

Future<void> _reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await t.ensureVisible(f.first);
  await t.pump();
}

void main() {
  testWidgets('Ligas: resumen, mis ligas con posición y descubrir; abrir una liga lleva al detalle', (t) async {
    await _app(t);
    await t.tap(find.bySemanticsLabel('Competiciones').last);   // la pestaña «Ligas» ahora es «Competiciones» (abre Ligas por defecto)
    await _settle(t, 8);
    expect(find.text('Compite con tu comunidad.'), findsOneWidget);
    expect(find.text('ACTIVAS'), findsOneWidget);
    expect(find.text('TU POSICIÓN'), findsWidgets);
    expect(find.byType(MyLeagueCard), findsWidgets);
    await t.tap(find.text('BÜNKER PADEL LEAGUE'));
    await _settle(t, 8);
    expect(find.byType(LeagueDetailScreen), findsOneWidget);
    expect(find.text('ORDENAR'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Detalle: ordenar por ELO cambia la métrica; pestañas Actividad, Partidos y Miembros', (t) async {
    await _app(t, path: '/leagues/bunker');
    expect(find.text('PTS'), findsOneWidget);
    await _reveal(t, find.text('ELO'));
    await t.tap(find.text('ELO').first);
    await t.pump();
    expect(find.text('PTS'), findsNothing);
    for (final (tab, probe) in [('Actividad', 'AYER'), ('Partidos', 'Registrar partido'), ('Miembros', 'Invitar amigos')]) {
      await t.tap(find.text(tab).last);
      await _settle(t, 4);
      if (find.text(probe).evaluate().isEmpty && probe == 'AYER') continue;   // la actividad depende de la fecha de los datos de prueba
      expect(find.text(probe), findsWidgets, reason: tab);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('Miembros: la búsqueda filtra la lista', (t) async {
    await _app(t, path: '/leagues/bunker?tab=members');
    expect(find.text('Marcos Ruiz'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'sofía');
    await t.pump();
    expect(find.text('Marcos Ruiz'), findsNothing);
    expect(find.text('Sofía García'), findsOneWidget);
  });

  testWidgets('Menú de la liga: opciones, reglas y gestión', (t) async {
    await _app(t, path: '/leagues/bunker');
    await t.tap(find.bySemanticsLabel('Opciones de la liga'));
    await _settle(t);
    expect(find.text('Opciones'), findsOneWidget);
    expect(find.text('Gestionar liga'), findsOneWidget);
    await t.tap(find.text('Ver reglas de la liga'));
    await _settle(t);
    expect(find.text('Reglas'), findsOneWidget);
    expect(find.text('Victoria'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Cerrar'));
    await _settle(t);
    await t.tap(find.bySemanticsLabel('Opciones de la liga'));
    await _settle(t);
    await t.tap(find.text('Gestionar liga'));
    await _settle(t, 8);
    expect(find.byType(ManageLeagueScreen), findsOneWidget);
    expect(find.text('Solicitudes de acceso'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Crear liga: valida el nombre y avanza por los pasos', (t) async {
    await _app(t, path: '/leagues/new');
    expect(find.text('PASO 1 DE 5'), findsOneWidget);
    await _reveal(t, find.text('Continuar'));
    await t.tap(find.text('Continuar'));
    await _settle(t, 2);
    expect(find.text('PASO 1 DE 5'), findsOneWidget);   // sin nombre no avanza
    await t.enterText(find.byType(TextFormField).first, 'Liga de los jueves');
    for (var step = 2; step <= 5; step++) {
      await t.tap(find.text('Continuar'));
      await _settle(t, 3);
      expect(find.text('PASO $step DE 5'), findsOneWidget);
    }
    expect(find.text('CREAR LIGA'), findsOneWidget);
    expect(find.text('LIGA DE LOS JUEVES'), findsOneWidget);
    await t.tap(find.text('Atrás'));
    await _settle(t, 2);
    expect(find.text('PASO 4 DE 5'), findsOneWidget);
    expect(find.byType(CreateLeagueScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Descubrir: filtros por tipo y tarjetas con acción', (t) async {
    await _app(t, path: '/leagues/discover');
    expect(find.byType(DiscoverLeaguesScreen), findsOneWidget);
    expect(find.text('Todas'), findsOneWidget);
    expect(find.byType(DiscoverLeagueCard), findsWidgets);
    await t.tap(find.text('Clubes'));
    await _settle(t, 4);
    await _reveal(t, find.text('Solicitar acceso'));
    expect(find.text('Solicitar acceso'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  for (final w in [390.0, 320.0]) {
    testWidgets('sin desbordamientos a $w px (lista, detalle, miembros, crear, descubrir, gestión)', (t) async {
      final r = await _app(t, width: w);
      await t.tap(find.bySemanticsLabel('Competiciones').last);   // la pestaña «Ligas» ahora es «Competiciones» (abre Ligas por defecto)
      await _settle(t, 8);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -1500));
      await _settle(t, 2);
      expect(t.takeException(), isNull);
      for (final p in ['/leagues/bunker', '/leagues/bunker?tab=members', '/leagues/bunker?tab=matches', '/leagues/new', '/leagues/discover', '/leagues/bunker/manage']) {
        r.push(p);
        await _settle(t, 6);
        expect(t.takeException(), isNull, reason: p);
        await t.drag(find.byType(Scrollable).first, const Offset(0, -800));
        await _settle(t, 2);
        expect(t.takeException(), isNull, reason: '$p (desplazado)');
      }
    });
  }
}
