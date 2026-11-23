import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/clubs/application/club_providers.dart';
import 'package:plobby/features/clubs/data/mock_club_repository.dart';
import 'package:plobby/features/clubs/domain/club_models.dart';
import 'package:plobby/features/clubs/presentation/club_screen.dart';
import 'package:plobby/features/clubs/presentation/club_search_sheet.dart';

Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }   // timing

/// App mínima: un botón abre el buscador y guarda el resultado; rutas del club y de moderación.
Future<List<ClubHit?>> _app(WidgetTester t, MockClubRepository repo, {String initial = '/'}) async {
  final picked = <ClubHit?>[];
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/', builder: (c, _) => Scaffold(body: Center(child: TextButton(
        onPressed: () async => picked.add(await pickClub(c, allowRemove: true)), child: const Text('abrir'))))),
    GoRoute(path: '/club/:id', builder: (_, s) => ClubScreen(clubId: s.pathParameters['id']!)),
    GoRoute(path: '/admin/clubs', builder: (_, __) => const ClubModerationScreen()),
  ]);
  await t.pumpWidget(ProviderScope(overrides: [clubRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: router)));
  await _settle(t);
  return picked;
}

Future<void> _type(WidgetTester t, String q) async {
  await t.enterText(find.byType(TextField).first, q);
  await t.pump(const Duration(milliseconds: 300));   // timing: pasa el debounce
  await _settle(t, 3);
}

void main() {
  group('Búsqueda del catálogo (mock con la puntuación de search_clubs)', () {
    test('nombre exacto, sin tildes ni mayúsculas → seguro', () async {
      final r = await MockClubRepository().search('club mirasierra');
      expect(r.first.name, 'Club Mirasierra');
      expect(r.first.confident, isTrue);
    });
    test('un alias encuentra el club oficial y dice por qué', () async {
      final r = await MockClubRepository().search('RCPH');
      expect((r.first.name, r.first.matchedAlias), ('Real Club Puerta de Hierro', 'RCPH'));
    });
    test('palabras sueltas en otro orden', () async {
      final r = await MockClubRepository().search('raqueta ciudad');
      expect(r.first.name, 'BamVolea Ciudad de la Raqueta');
    });
    test('ambiguo («hierro»: club social y parque de la federación) → no se elige solo', () async {
      final r = await MockClubRepository().search('hierro');
      expect(r.length, greaterThanOrEqualTo(2));
      expect(r.first.confident, isFalse);
    });
    test('menos de 2 letras → nada', () async => expect(await MockClubRepository().search('a'), isEmpty));
    test('normalizeClubName quita tildes, signos, espacios repetidos y la palabra genérica «club»', () =>
        expect(normalizeClubName('  Club  Más-Pádel! '), 'mas padel'));
  });

  group('Buscador (hoja)', () {
    testWidgets('escribir, ver el alias y elegir devuelve el club del catálogo', (t) async {
      final picked = await _app(t, MockClubRepository());
      await t.tap(find.text('abrir'));
      await _settle(t);
      await _type(t, 'ccvm');
      expect(find.textContaining('Real Club de Campo Villa de Madrid'), findsWidgets);
      expect(find.text('También conocido como CCVM'), findsOneWidget);
      await t.tap(find.textContaining('Real Club de Campo Villa de Madrid').first);
      await _settle(t);
      expect(picked.single?.id, 'c-campo');
      expect(t.takeException(), isNull);
    });

    testWidgets('«Quitar mi club» devuelve el centinela', (t) async {
      final picked = await _app(t, MockClubRepository());
      await t.tap(find.text('abrir'));
      await _settle(t);
      await t.tap(find.text('Quitar mi club'));
      await _settle(t);
      expect(identical(picked.single, clubRemoved), isTrue);
    });

    testWidgets('proponer un club parecido avisa del duplicado; «No, es otro club» lo crea pendiente', (t) async {
      final repo = MockClubRepository();
      final picked = await _app(t, repo);
      await t.tap(find.text('abrir'));
      await _settle(t);
      await _type(t, 'Club Mirasierra Norte');
      await t.ensureVisible(find.text('Proponer nuevo club'));
      await t.tap(find.text('Proponer nuevo club'));
      await _settle(t);
      await t.enterText(find.widgetWithText(TextFormField, 'p. ej. Alcobendas'), 'Madrid');
      await t.enterText(find.byType(TextFormField).first, 'Club Mirasierra');
      await t.ensureVisible(find.text('Enviar propuesta'));
      await t.tap(find.text('Enviar propuesta'));
      await _settle(t);
      expect(find.text('¿Es alguno de estos?'), findsOneWidget);
      await t.ensureVisible(find.text('No, es otro club'));
      await t.tap(find.text('No, es otro club'));
      await _settle(t);
      expect((picked.single?.name, picked.single?.pending), ('Club Mirasierra', true));
      expect(t.takeException(), isNull);
    });
  });

  group('Página del club y moderación', () {
    testWidgets('la página muestra datos, alias y el ranking con el jugador', (t) async {
      final repo = MockClubRepository();
      await repo.setMyClub('c-rcph');
      await _app(t, repo, initial: '/club/c-rcph');
      expect(find.text('Real Club Puerta de Hierro'), findsOneWidget);
      expect(find.textContaining('También conocido como RCPH'), findsOneWidget);
      expect(find.text('1 jugador lo tiene como club habitual'), findsOneWidget);
      expect(find.text('Diego Castelló'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('club inexistente o pendiente → aviso, no pantalla rota', (t) async {
      await _app(t, MockClubRepository(), initial: '/club/no-existe');
      expect(find.text('Club no disponible'), findsOneWidget);
    });

    testWidgets('un administrador aprueba una propuesta y desaparece de la cola', (t) async {
      final repo = MockClubRepository(isAdmin: true);
      await repo.propose(name: 'Pádel Vértice Norte', municipality: 'Tres Cantos', force: true);
      await _app(t, repo, initial: '/admin/clubs');
      expect(find.text('Pádel Vértice Norte'), findsOneWidget);
      await t.tap(find.text('Aprobar'));
      await _settle(t);
      expect(find.text('No hay propuestas pendientes'), findsOneWidget);
      expect((await repo.search('vertice norte')).first.pending, isFalse);
    });

    testWidgets('sin permisos de administrador la cola muestra el error del servidor', (t) async {
      await _app(t, MockClubRepository(), initial: '/admin/clubs');
      expect(find.text('No hay propuestas pendientes'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
