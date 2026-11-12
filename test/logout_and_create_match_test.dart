import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/plobby_components.dart';
import 'package:plobby/features/auth/application/auth_providers.dart';
import 'package:plobby/features/auth/data/mock_auth_repository.dart';
import 'package:plobby/features/auth/domain/auth_models.dart';
import 'package:plobby/features/auth/presentation/welcome_screen.dart';
import 'package:plobby/features/home/presentation/home_screen.dart';
import 'package:plobby/features/matches/application/match_providers.dart';
import 'package:plobby/features/matches/data/match_repository.dart';
import 'package:plobby/features/matches/domain/match_models.dart';
import 'package:plobby/features/matches/presentation/create_match_screen.dart';
import 'package:plobby/features/profile/presentation/profile_screen.dart';
import 'package:plobby/features/social/application/social_providers.dart';
import 'package:plobby/features/social/data/mock_social_repository.dart';
import 'package:plobby/features/social/domain/social_models.dart';

/// Amigos del selector («Añadir jugadores» abre Amigos en modo selección).
class _Social extends MockSocialRepository {
  _Social({this.count = 3});
  final int count;
  @override
  Future<List<Friend>> friends() async => const [
        Friend(PlayerSummary(id: 'a', name: 'Ana R.', username: 'ana', elo: 1200, level: 'Intermedio'), FriendActivity()),
        Friend(PlayerSummary(id: 'b', name: 'Bea S.', username: 'bea', elo: 1200, level: 'Intermedio'), FriendActivity()),
        Friend(PlayerSummary(id: 'c', name: 'Carla N.', username: 'carla', elo: 1200, level: 'Intermedio'), FriendActivity()),
      ].take(count).toList();
}

Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

Future<GoRouter> _app(WidgetTester t, {List<Override> overrides = const [], MockSocialRepository? social}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late GoRouter r;
  await t.pumpWidget(ProviderScope(overrides: [socialRepositoryProvider.overrideWithValue(social ?? _Social()), ...overrides], child: Consumer(builder: (_, ref, __) { r = ref.watch(routerProvider); return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r); })));
  await _settle(t, 6);
  return r;
}

// ─────────────────────────────── Cierre de sesión ───────────────────────────────

/// Sesión iniciada y perfil completo, con la guardia del router ACTIVA (como con Supabase).
Future<MockAuthRepository> _signedIn() async {
  final a = MockAuthRepository(initial: const OnboardingData(firstName: 'Diego', lastName: 'Castello', username: 'diego.c', completed: true));
  await a.signInWithGoogle();
  return a;
}

class _FailingSignOut extends MockAuthRepository {
  _FailingSignOut() : super(initial: const OnboardingData(completed: true));
  @override
  Future<void> signOut() async => throw Exception('sin red');
}

Future<void> _openLogout(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Perfil').last);
  await _settle(t, 6);
  await t.scrollUntilVisible(find.bySemanticsLabel('Cerrar sesión'), 400, scrollable: find.byType(Scrollable).first);
  await t.drag(find.byType(Scrollable).first, const Offset(0, -300));   // por encima de la barra inferior
  await _settle(t, 2);
  await t.tap(find.bySemanticsLabel('Cerrar sesión'));
  await _settle(t, 3);
}

// ─────────────────────────────── Crear partido ───────────────────────────────

/// Repositorio de partidos que responde como la base real: lista de clubes (vacía hoy), amigos y RPC `create_match`.
class _Repo implements MatchRepository {
  _Repo({this.clubList = const [], this.friendList = const [PlayerOption('a', 'Ana R.'), PlayerOption('b', 'Bea S.'), PlayerOption('c', 'Carla N.')], this.clubsError = false, this.createError});
  final List<String> clubList; final List<PlayerOption> friendList; final bool clubsError; final Object? createError;
  final created = <MatchDraft>[];
  @override Future<List<LeagueOption>> myLeagues() async => const [];
  @override Future<List<PlayerOption>> leagueMembers(String id) async => const [];
  @override Future<List<PlayerOption>> friends() async => friendList;
  @override Future<List<String>> clubs() async => clubsError ? throw Exception('clubs') : clubList;
  @override Future<String> create(MatchDraft d) async { if (createError != null) throw createError!; created.add(d); return 'm-new'; }
}

Future<void> _openFriendlyForm(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Nuevo partido'));
  await _settle(t);
  await t.tap(find.bySemanticsLabel(RegExp('^Crear partido amistoso')));
  await _settle(t, 8);
}

Future<void> _pickPlayers(WidgetTester t) async {
  // «Añadir jugadores» → Amigos en modo selección: el orden marcado es compañero, rival 1, rival 2.
  await t.ensureVisible(find.text('Añadir jugadores'));
  await t.tap(find.text('Añadir jugadores'));
  await _settle(t);
  for (final name in ['Ana R.', 'Bea S.', 'Carla N.']) {
    await t.tap(find.text(name).last);
    await _settle(t, 2);
  }
  await t.tap(find.text('Añadir al partido (3)'));
  await _settle(t);
}

Future<void> _tapCreate(WidgetTester t) async {
  // El formulario es una lista perezosa: tras volver del selector puede que el botón aún no esté construido.
  final btn = find.widgetWithText(PlobbyButton, 'Crear partido');
  await t.scrollUntilVisible(btn, 200, scrollable: find.byType(Scrollable).first);
  await t.tap(btn);
  await _settle(t, 6);
}

void main() {
  group('Cerrar sesión', () {
    testWidgets('pide confirmación; «Cancelar» no cierra la sesión', (t) async {
      final auth = await _signedIn();
      await _app(t, overrides: [authGuardEnabledProvider.overrideWithValue(true), authRepositoryProvider.overrideWithValue(auth)]);
      expect(find.byType(HomeScreen), findsOneWidget);
      await _openLogout(t);
      expect(find.text('¿Estás seguro de que quieres cerrar sesión?'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await _settle(t, 3);
      expect(auth.currentUser, isNotNull);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('confirmar: signOut, va a la bienvenida, «atrás» no vuelve y se puede volver a entrar', (t) async {
      final auth = await _signedIn();
      await _app(t, overrides: [authGuardEnabledProvider.overrideWithValue(true), authRepositoryProvider.overrideWithValue(auth)]);
      await _openLogout(t);
      await t.tap(find.bySemanticsLabel('Cerrar sesión').last);   // botón del diálogo
      await _settle(t, 8);
      expect(auth.currentUser, isNull);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
      // Botón «atrás» del sistema: no hay pantalla privada debajo a la que volver.
      await t.binding.handlePopRoute();
      await _settle(t, 4);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
      // Volver a entrar: la cuenta y su perfil siguen ahí (onboarding completo → Inicio, no onboarding de nuevo).
      await t.tap(find.bySemanticsLabel('Continuar con Google'));
      await _settle(t, 8);
      expect(auth.currentUser, isNotNull);
      expect(find.byType(HomeScreen), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Perfil').last);   // el perfil vuelve a cargarse con sus datos
      await _settle(t, 6);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.textContaining('Diego'), findsWidgets);
    });

    testWidgets('si signOut falla: mensaje de error y la sesión sigue abierta', (t) async {
      final auth = _FailingSignOut();
      await auth.signInWithGoogle();
      await _app(t, overrides: [authGuardEnabledProvider.overrideWithValue(true), authRepositoryProvider.overrideWithValue(auth)]);
      await _openLogout(t);
      await t.tap(find.bySemanticsLabel('Cerrar sesión').last);
      await _settle(t, 4);
      expect(find.textContaining('No se pudo cerrar sesión'), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(auth.currentUser, isNotNull);
    });

    testWidgets('modo demo (sin guardia): también lleva a la bienvenida y se vuelve a entrar', (t) async {
      final auth = await _signedIn();
      await _app(t, overrides: [authRepositoryProvider.overrideWithValue(auth)]);
      await _openLogout(t);
      await t.tap(find.bySemanticsLabel('Cerrar sesión').last);
      await _settle(t, 6);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Continuar con Google'));
      await _settle(t, 6);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('Crear partido desde «+»', () {
    testWidgets('con la tabla de clubes vacía (como en Supabase hoy) el formulario abre sin errores', (t) async {
      final repo = _Repo();
      await _app(t, overrides: [matchRepositoryProvider.overrideWithValue(repo)]);
      await _openFriendlyForm(t);
      expect(t.takeException(), isNull);   // antes: «Bad state: No element» → pantalla gris/negra
      expect(find.byType(CreateMatchScreen), findsOneWidget);
      expect(find.text('Club'), findsOneWidget);
    });

    testWidgets('rellenar y guardar: crea el partido con el club escrito, confirma y vuelve', (t) async {
      final repo = _Repo();
      await _app(t, overrides: [matchRepositoryProvider.overrideWithValue(repo)]);
      await _openFriendlyForm(t);
      await _pickPlayers(t);
      await _tapCreate(t);
      expect(find.text('Indica el club donde se juega el partido.'), findsOneWidget);   // club obligatorio
      expect(repo.created, isEmpty);
      await t.enterText(find.widgetWithText(TextFormField, 'p. ej. Club La Moraleja'), 'Pádel Chamberí');
      await _tapCreate(t);
      expect(repo.created, hasLength(1));
      final d = repo.created.single;
      expect((d.type, d.partnerId, d.rival1Id, d.rival2Id, d.club), (MatchType.friendly, 'a', 'b', 'c', 'Pádel Chamberí'));
      expect(find.text('Partido creado.'), findsOneWidget);
      expect(find.byType(CreateMatchScreen), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('con clubes en la base se guarda el club que se ve seleccionado (no uno fijo)', (t) async {
      final repo = _Repo(clubList: const ['Club Alameda', 'Pádel Vértice']);
      await _app(t, overrides: [matchRepositoryProvider.overrideWithValue(repo)]);
      await _openFriendlyForm(t);
      await _pickPlayers(t);
      await _tapCreate(t);
      expect(repo.created.single.club, 'Club Alameda');   // antes se enviaba «Club La Moraleja»
    });

    testWidgets('error de Supabase (create_match): mensaje comprensible y el formulario sigue abierto', (t) async {
      final repo = _Repo(clubList: const ['Club Alameda'], createError: MatchCreateException.fromServerMessage('player 1b2c is not your friend'));
      await _app(t, overrides: [matchRepositoryProvider.overrideWithValue(repo)]);
      await _openFriendlyForm(t);
      await _pickPlayers(t);
      await _tapCreate(t);
      expect(find.text('En un amistoso solo puedes jugar con amigos que hayan aceptado tu solicitud.'), findsOneWidget);
      expect(find.byType(CreateMatchScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('error de red: mensaje de conexión, sin bloqueo', (t) async {
      final repo = _Repo(clubList: const ['Club Alameda'], createError: Exception('SocketException'));
      await _app(t, overrides: [matchRepositoryProvider.overrideWithValue(repo)]);
      await _openFriendlyForm(t);
      await _pickPlayers(t);
      await _tapCreate(t);
      expect(find.textContaining('Comprueba tu conexión'), findsOneWidget);
      expect(find.byType(CreateMatchScreen), findsOneWidget);
    });

    testWidgets('si falla la lectura de clubes se puede escribir el club; sin amigos se explica qué falta', (t) async {
      final repo = _Repo(clubsError: true, friendList: const [PlayerOption('a', 'Ana R.')]);
      await _app(t, overrides: [matchRepositoryProvider.overrideWithValue(repo)], social: _Social(count: 1));
      await _openFriendlyForm(t);
      expect(find.widgetWithText(TextFormField, 'p. ej. Club La Moraleja'), findsOneWidget);
      expect(find.textContaining('necesitas tres amigos'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('doble toque rápido en la opción abre un solo formulario', (t) async {
      await _app(t, overrides: [matchRepositoryProvider.overrideWithValue(_Repo())]);
      await t.tap(find.bySemanticsLabel('Nuevo partido'));
      await _settle(t);
      final opt = find.bySemanticsLabel(RegExp('^Crear partido amistoso'));
      await t.tap(opt);
      await t.pump(const Duration(milliseconds: 30));
      if (opt.evaluate().isNotEmpty) await t.tap(opt, warnIfMissed: false);
      await _settle(t, 8);
      expect(find.byType(CreateMatchScreen), findsOneWidget);
    });
  });

  test('errores de create_match → mensaje para el usuario', () {
    expect(MatchCreateException.fromServerMessage('three different players required').code, 'players');
    expect(MatchCreateException.fromServerMessage('player x is not a member of the league').code, 'not_league_member');
    expect(MatchCreateException.fromServerMessage('invalid set 2').code, 'invalid_sets');
    expect(MatchCreateException.fromServerMessage('at least two sets required').code, 'invalid_sets');
    expect(MatchCreateException.fromServerMessage('not authenticated').code, 'auth');
    expect(MatchCreateException.fromServerMessage('algo raro').message, contains('No se pudo crear'));
  });
}
