import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/tournaments/application/tournament_providers.dart';
import 'package:plobby/features/tournaments/data/mock_tournament_repository.dart';
import 'package:plobby/features/tournaments/domain/tournament_models.dart';
import 'package:plobby/features/tournaments/presentation/create_tournament_screen.dart';
import 'package:plobby/features/tournaments/presentation/tournament_detail_screen.dart';

Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

Future<(GoRouter, MockTournamentRepository)> _app(WidgetTester t, {double width = 390}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = MockTournamentRepository(now: () => DateTime(2026, 11, 14));
  late GoRouter r;
  await t.pumpWidget(ProviderScope(overrides: [tournamentRepositoryProvider.overrideWithValue(repo)], child: Consumer(builder: (_, ref, __) {
    r = ref.watch(routerProvider);
    return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r);
  })));
  await _settle(t);
  return (r, repo);
}

Future<void> _openTorneos(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Competiciones').last);
  await _settle(t);
  await t.tap(find.text('Torneos'));
  await _settle(t);
}

void main() {
  testWidgets('Competiciones muestra Ligas y Torneos; Torneos lista mis torneos con su información', (t) async {
    await _app(t);
    await t.tap(find.bySemanticsLabel('Competiciones').last);
    await _settle(t);
    expect(find.text('Competiciones'), findsWidgets);
    expect(find.text('Compite con tu comunidad.'), findsOneWidget);   // Ligas, como siempre
    await t.tap(find.text('Torneos'));
    await _settle(t);
    expect(find.text('Mis torneos'), findsOneWidget);
    expect(find.text('Open de Otoño'), findsOneWidget);
    expect(find.text('6/8 parejas'), findsOneWidget);
    expect(find.text('Semifinales'), findsOneWidget);                // fase actual
    expect(find.text('Crear torneo'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('el cuadro se ve, y registrar un resultado hace avanzar a la pareja ganadora', (t) async {
    final (r, repo) = await _app(t);
    final id = (await repo.myTournaments()).first.id;
    r.push('/tournaments/$id');
    await _settle(t);
    expect(find.byType(TournamentDetailScreen), findsOneWidget);
    expect(find.text('SEMIFINALES'), findsOneWidget);
    expect(find.text('FINAL'), findsOneWidget);
    expect(find.text('CAMPEÓN'), findsOneWidget);
    // Semifinal 1: abrir, introducir 6-3 6-4 y guardar.
    final semi = (await repo.detail(id)).knockout.firstWhere((m) => m.round == 2 && m.position == 0);
    await t.tap(find.bySemanticsLabel(RegExp('^Semifinales:')).first);
    await _settle(t, 3);
    await t.tap(find.text('Introducir resultado'));
    await _settle(t, 2);
    await t.enterText(find.bySemanticsLabel('Set 1, pareja 1'), '6');
    await t.enterText(find.bySemanticsLabel('Set 1, pareja 2'), '3');
    await t.enterText(find.bySemanticsLabel('Set 2, pareja 1'), '6');
    await t.enterText(find.bySemanticsLabel('Set 2, pareja 2'), '4');
    await t.pump();
    expect(find.textContaining('Gana '), findsOneWidget);
    await t.tap(find.text('Guardar resultado'));
    await _settle(t);
    final d = await repo.detail(id);
    final fin = d.knockout.firstWhere((m) => m.round == 3);
    expect(fin.team1Id, semi.team1Id);                                 // el ganador está ya en la final
    expect(find.text('Resultado guardado'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('crear torneo: pasos, parejas sin duplicados, resumen y cuadro generado', (t) async {
    final (r, repo) = await _app(t);
    await _openTorneos(t);
    await t.tap(find.text('Crear torneo').first);
    await _settle(t);
    expect(find.byType(CreateTournamentScreen), findsOneWidget);
    // Paso 1: sin nombre no deja seguir.
    await t.tap(find.text('Siguiente'));
    await t.pump();
    expect(find.textContaining('Ponle un nombre'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'p. ej. Open de Otoño'), 'Torneo de prueba');
    await t.tap(find.text('Siguiente'));
    await _settle(t, 2);
    // Paso 2: eliminación directa (por defecto).
    expect(find.text('¿Cómo se juega?'), findsOneWidget);
    await t.tap(find.text('Siguiente'));
    await _settle(t, 2);
    // Paso 3: con 0 parejas no deja seguir.
    await t.tap(find.text('Siguiente'));
    await t.pump();
    expect(find.textContaining('al menos 2 parejas'), findsOneWidget);
    Future<void> addPair(String a, String b, {String? search}) async {
      await t.tap(find.text('Añadir pareja').first);
      await _settle(t, 3);
      await t.tap(find.text(a).last);
      await t.pump();
      if (search != null) {
        await t.enterText(find.byType(TextField).last, search);
        await t.pump(const Duration(milliseconds: 400));
        await _settle(t, 2);
      }
      await t.tap(find.text(b).last);
      await t.pump();
      await t.tap(find.text('Añadir pareja').last);
      await _settle(t, 3);
    }
    await addPair('Diego Castello (tú)', 'Laura G.');
    // Laura ya está inscrita: en el selector aparece bloqueada.
    await t.tap(find.text('Añadir pareja').first);
    await _settle(t, 3);
    expect(find.text('Ya está en otra pareja'), findsNWidgets(2));
    await t.tap(find.byTooltip('Cerrar'));
    await _settle(t, 2);
    await addPair('Marcos R.', 'Paula A.', search: 'paula');
    expect(find.text('2 parejas · 4 jugadores'), findsOneWidget);
    await t.tap(find.text('Siguiente'));
    await _settle(t, 2);
    // Paso 4: resumen.
    expect(find.text('PAREJAS INSCRITAS'), findsOneWidget);
    expect(find.text('1 en total'), findsOneWidget);
    await t.tap(find.text('Crear torneo').last);
    await _settle(t, 8);
    expect(find.byType(TournamentDetailScreen), findsOneWidget);
    final mine = await repo.myTournaments();
    final created = mine.firstWhere((x) => x.name == 'Torneo de prueba');
    final d = await repo.detail(created.id);
    expect((d.teams.length, d.knockout.length, d.tournament.format), (2, 1, TournamentFormat.knockout));
    expect(t.takeException(), isNull);
    r.pop();
  });

  for (final w in [390.0, 320.0]) {
    testWidgets('pantallas de torneo sin desbordamientos a $w px', (t) async {
      final (r, repo) = await _app(t, width: w);
      await _openTorneos(t);
      expect(t.takeException(), isNull);
      final id = (await repo.myTournaments()).first.id;
      r.push('/tournaments/$id');
      await _settle(t);
      for (final tab in ['Información', 'Parejas', 'Partidos', 'Cuadro']) {
        await t.ensureVisible(find.text(tab).first);
        await t.pump();
        await t.tap(find.text(tab).first);
        await _settle(t, 2);
        expect(t.takeException(), isNull, reason: tab);
      }
      r.push('/tournaments/new');
      await _settle(t);
      expect(t.takeException(), isNull);
    });
  }
}
