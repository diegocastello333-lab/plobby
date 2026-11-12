import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/matches/application/lifecycle_providers.dart';
import 'package:plobby/features/matches/data/mock_lifecycle_repository.dart';
import 'package:plobby/features/matches/domain/match_lifecycle.dart';
import 'package:plobby/features/matches/domain/match_models.dart';
import 'package:plobby/features/matches/presentation/create_match_screen.dart';
import 'package:plobby/features/matches/presentation/match_detail_screen.dart';
import 'package:plobby/features/matches/presentation/result_entry_screen.dart';

/// V5 · Partidos: el rediseño mantiene el ciclo completo (empezar → finalizar → resultado → confirmación),
/// las opciones de editar/eliminar y el menú «+». Repositorio de ciclo mock con un partido sembrado.
const _players = [
  MatchPlayer(id: 'me', name: 'Diego C.', team: 1, isCaptain: true, elo: 1482, level: 'Intermedio alto'),
  MatchPlayer(id: 'marcos', name: 'Marcos R.', team: 1, elo: 1455, level: 'Intermedio alto'),
  MatchPlayer(id: 'carlos', name: 'Carlos M.', team: 2, isCaptain: true, elo: 1590, level: 'Avanzado'),
  MatchPlayer(id: 'laura', name: 'Laura G.', team: 2, elo: 1545, level: 'Avanzado'),
];

LifecycleMatch _seed({MatchStatus st = MatchStatus.scheduled, List<SetScore> sets = const [], int version = 0}) => LifecycleMatch(
      id: 'm1', type: MatchType.friendly, scheduledAt: DateTime.now().add(const Duration(days: 2)), club: 'Club Alameda', court: 'Pista 3',
      status: st, players: _players, createdBy: 'me', sets: sets, resultVersion: version,
      startedAt: st.index > 0 ? DateTime.now().subtract(const Duration(minutes: 50)) : null,
      endedAt: st.index > 1 ? DateTime.now().subtract(const Duration(minutes: 2)) : null,
      durationSeconds: st.index > 1 ? 48 * 60 : null, eloDelta: st == MatchStatus.confirmed ? const {'me': 14, 'marcos': 14, 'carlos': -14, 'laura': -14} : const {});

Future<(MockLifecycleRepository, GoRouter)> _open(WidgetTester t, {LifecycleMatch? m, double width = 390, String path = '/match/m1'}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = MockLifecycleRepository(me: 'me', seed: [m ?? _seed()]);
  late GoRouter router;
  await t.pumpWidget(ProviderScope(
    overrides: [lifecycleRepositoryProvider.overrideWithValue(repo)],
    child: Consumer(builder: (_, ref, __) { router = ref.watch(routerProvider); return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: router); }),
  ));
  for (var i = 0; i < 4; i++) { await t.pump(const Duration(milliseconds: 300)); }
  router.push(path);
  await _settle(t);
  return (repo, router);
}

Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

/// Las pantallas usan listas perezosas: desplaza hasta que el elemento exista y sea visible.
Future<void> _reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  await t.ensureVisible(f);
  await t.pump();
}

Future<void> _tapText(WidgetTester t, String text) async {
  if (find.text(text).evaluate().isEmpty) await t.scrollUntilVisible(find.text(text), 150, scrollable: find.byType(Scrollable).first);
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.pump();
  await t.pump();
  await t.tap(f);
  await _settle(t);
}

void main() {
  testWidgets('detalle programado: cabecera, progreso, equipos y acciones del creador', (t) async {
    await _open(t);
    expect(find.text('Detalle del partido'), findsOneWidget);
    expect(find.text('Programado'), findsWidgets);                       // estado + paso actual
    expect(find.text('Club Alameda · Pista 3'), findsOneWidget);
    expect(find.text('Diego C. (tú)'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Progreso del partido: Programado')), findsOneWidget);
    await _reveal(t, find.text('Eliminar partido'));
    expect(find.bySemanticsLabel('EMPEZAR PARTIDO'), findsOneWidget);
    expect(find.bySemanticsLabel('Editar partido'), findsOneWidget);
    expect(find.bySemanticsLabel('Eliminar partido'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('ciclo completo: empezar → finalizar (hoja) → resultado → confirmación del capitán', (t) async {
    final (repo, _) = await _open(t);
    await _reveal(t, find.text('EMPEZAR PARTIDO'));
    await t.tap(find.bySemanticsLabel('EMPEZAR PARTIDO'));
    await _settle(t);
    expect(find.text('¡Partido iniciado! Cronómetro en marcha para los cuatro.'), findsOneWidget);
    expect(find.text('CRONÓMETRO OFICIAL · HORA DEL SERVIDOR'), findsOneWidget);

    await _reveal(t, find.text('FINALIZAR PARTIDO'));
    await t.tap(find.bySemanticsLabel('FINALIZAR PARTIDO'));
    await _settle(t);
    expect(find.text('¿Finalizar el partido?'), findsOneWidget);
    await _tapText(t, 'Finalizar');
    expect(find.byType(ResultEntryScreen), findsOneWidget);
    expect((await repo.watchMatch('m1').first)!.status, MatchStatus.pendingResult);

    final fields = find.byType(TextField);
    for (final (i, v) in [(0, '6'), (1, '3'), (2, '6'), (3, '4')]) { await t.enterText(fields.at(i), v); }
    await t.pump();
    expect(find.text('VISTA PREVIA'), findsOneWidget);
    expect(find.text('Ganan Diego y Marcos · 2-0'), findsOneWidget);
    await t.ensureVisible(find.bySemanticsLabel('Enviar resultado'));
    await t.tap(find.bySemanticsLabel('Enviar resultado'));
    await _settle(t);
    expect(find.byType(MatchDetailScreen), findsOneWidget);
    await _reveal(t, find.text('CONFIRMACIÓN DE CAPITANES · VERSIÓN 1'));

    await _tapText(t, 'Aceptar resultado');
    expect(find.text('Has aceptado. Falta el otro capitán.'), findsOneWidget);
    await _reveal(t, find.text('Aceptado'));
    expect(t.takeException(), isNull);
  });

  testWidgets('resultado no válido: aviso y botón de envío desactivado', (t) async {
    await _open(t, m: _seed(st: MatchStatus.pendingResult), path: '/match/m1/result');
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), '6');
    await t.enterText(fields.at(1), '5');
    await t.enterText(fields.at(2), '6');
    await t.enterText(fields.at(3), '3');
    await t.pump();
    expect(find.textContaining('no válido'), findsOneWidget);
    await t.ensureVisible(find.bySemanticsLabel('Enviar resultado'));
    await t.tap(find.bySemanticsLabel('Enviar resultado'));
    await _settle(t);
    expect(find.byType(ResultEntryScreen), findsOneWidget);
  });

  testWidgets('rechazar abre la hoja con motivo y deja el partido en disputa', (t) async {
    final (repo, _) = await _open(t, m: _seed(st: MatchStatus.pendingConfirmation, sets: const [SetScore(6, 3), SetScore(6, 4)], version: 1));
    await _tapText(t, 'Rechazar');
    expect(find.text('Rechazar resultado'), findsOneWidget);
    await t.enterText(find.byType(TextFormField), 'El segundo set fue 6-3');
    await _tapText(t, 'Rechazar');
    expect((await repo.watchMatch('m1').first)!.status, MatchStatus.disputed);
    await _reveal(t, find.text('RESULTADO EN DISPUTA'));
    await _reveal(t, find.text('Corregir resultado'));
    expect(find.bySemanticsLabel('Corregir resultado'), findsOneWidget);
  });

  testWidgets('«Más opciones» → Eliminar pide confirmación y borra el partido', (t) async {
    final (repo, _) = await _open(t);
    await t.tap(find.bySemanticsLabel('Más opciones'));
    await _settle(t);
    expect(find.text('Opciones del partido'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Eliminar partido').last);
    await _settle(t);
    expect(find.text('¿Eliminar este partido?'), findsOneWidget);
    await _tapText(t, 'Eliminar');
    expect(find.text('Partido eliminado'), findsOneWidget);
    expect((await repo.watchMatch('m1').first)?.status, isNot(MatchStatus.scheduled));
  });

  testWidgets('«Más opciones» → Editar abre la hoja de edición', (t) async {
    await _open(t);
    await t.tap(find.bySemanticsLabel('Más opciones'));
    await _settle(t);
    await t.tap(find.bySemanticsLabel('Editar partido').last);
    await _settle(t);
    expect(find.text('Guardar cambios'), findsOneWidget);
    expect(find.text('Capitán equipo 1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('resultado final: sets, ELO ganado y datos del partido', (t) async {
    await _open(t, m: _seed(st: MatchStatus.confirmed, sets: const [SetScore(6, 3), SetScore(6, 4)], version: 1), path: '/match/m1/final');
    await _settle(t, 4);
    expect(find.text('VICTORIA · CONFIRMADO'), findsOneWidget);
    expect(find.text('6-3'), findsOneWidget);
    expect(find.text('+14'), findsNWidgets(2));
    expect(find.text('48 min'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final w in [390.0, 320.0]) {
    testWidgets('sin desbordamientos a $w px (detalle en confirmación, resultado, final)', (t) async {
      await _open(t, width: w, m: _seed(st: MatchStatus.pendingConfirmation, sets: const [SetScore(6, 3), SetScore(3, 6), SetScore(7, 5)], version: 1));
      expect(t.takeException(), isNull);
      await _reveal(t, find.text('Proponer corrección'));
      expect(t.takeException(), isNull);
      await _tapText(t, 'Proponer corrección');
      expect(find.text('Enviar corrección'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('menú «+»: dos tipos de partido y «Más opciones»; amistoso abre el formulario', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) => MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider)))));
    await _settle(t, 4);
    await t.tap(find.bySemanticsLabel('Nuevo partido'));
    await _settle(t);
    expect(find.text('¿Qué tipo de partido quieres crear?'), findsOneWidget);
    expect(find.text('MÁS OPCIONES'), findsOneWidget);
    expect(find.bySemanticsLabel('Crear una liga'), findsOneWidget);
    await t.tap(find.bySemanticsLabel(RegExp('^Crear partido amistoso')));
    await _settle(t);
    expect(find.byType(CreateMatchScreen), findsOneWidget);
    expect(find.text('Partido amistoso'), findsOneWidget);
    expect(find.text('Crear partido'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
