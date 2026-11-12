import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/auth/application/auth_providers.dart';
import 'package:plobby/features/auth/data/mock_auth_repository.dart';
import 'package:plobby/features/matches/domain/match_models.dart';
import 'package:plobby/features/social/data/supabase_social_repository.dart';
import 'package:plobby/features/social/presentation/friends_screen.dart';

/// Mejoras de amigos, pareja habitual y foto/avatar (repositorios mock; la parte de Supabase se verificó en la BD real).
Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

Future<GoRouter> _app(WidgetTester t, {List<Override> overrides = const []}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late GoRouter r;
  await t.pumpWidget(ProviderScope(overrides: overrides, child: Consumer(builder: (_, ref, __) {
    r = ref.watch(routerProvider);
    return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r);
  })));
  await _settle(t);
  return r;
}

Future<void> _openTab(WidgetTester t, String label) async {
  await t.tap(find.bySemanticsLabel(label).last);
  await _settle(t);
}

void main() {
  group('Solicitudes de amistad', () {
    test('una solicitud de alguien que aún no es amigo (ELO oculto por RLS, llega null) se lee sin fallar', () {
      final p = playerSummaryFromRow({'user_id': '3015d769-783a-4d00-b643-7ff9b656587f', 'display_name': 'Antonio Cuesta', 'username': 'antocuesta',
          'avatar_url': null, 'elo': null, 'level': null, 'mutual_friends': null});
      expect((p.id, p.name, p.username, p.elo, p.level, p.mutualFriends), ('3015d769-783a-4d00-b643-7ff9b656587f', 'Antonio Cuesta', 'antocuesta', 0, '', 0));
    });

    testWidgets('Amigos muestra las pendientes con el remitente; aceptar lo convierte en amigo y quita la solicitud', (t) async {
      final r = await _app(t);
      r.push('/friends');
      await _settle(t);
      expect(find.text('SOLICITUDES PENDIENTES'), findsOneWidget);
      expect(find.text('Raúl D.'), findsOneWidget);
      await t.tap(find.text('Aceptar'));
      await _settle(t);
      expect(find.text('SOLICITUDES PENDIENTES'), findsNothing);
      expect(find.text('Aceptar'), findsNothing);
      expect(find.text('Raúl D.'), findsOneWidget);   // ahora en la lista de amigos
      expect(t.takeException(), isNull);
    });

    testWidgets('rechazar quita la solicitud y no lo añade a amigos', (t) async {
      final r = await _app(t);
      r.push('/friends');
      await _settle(t);
      await t.tap(find.text('Rechazar'));
      await _settle(t);
      expect(find.text('Raúl D.'), findsNothing);
      expect(find.text('SOLICITUDES PENDIENTES'), findsNothing);
    });
  });

  group('Selector de amigos', () {
    testWidgets('respeta el máximo, no deja repetir a quien ya está y devuelve la selección', (t) async {
      final r = await _app(t);
      final res = r.push<List<PlayerOption>>('/friends/pick', extra: const FriendPick(title: 'Rival 1', blocked: {'laura'}, confirmLabel: 'Elegir'));
      await _settle(t);
      expect(find.text('Ya está en el partido'), findsOneWidget);   // Laura ya ocupa otro hueco
      await t.tap(find.text('Laura G.'));
      await _settle(t, 2);
      expect(find.text('Elegir'), findsNothing);                    // bloqueada: no se selecciona
      await t.tap(find.text('Marcos R.'));
      await _settle(t, 2);
      await t.tap(find.text('Elegir'));
      await _settle(t);
      final picked = await res;
      expect(picked!.map((p) => p.id), ['marcos']);
    });
  });

  group('Pareja habitual', () {
    testWidgets('cambiarla abre Amigos (solo amigos), se elige una y se guarda; la «×» la quita', (t) async {
      await _app(t);
      await _openTab(t, 'Perfil');
      final row = find.text('Marcos Ruiz');   // pareja del perfil de demo
      await t.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await t.tap(row);
      await _settle(t);
      expect(find.byType(FriendsScreen), findsOneWidget);
      await t.tap(find.text('Laura G.'));
      await _settle(t, 2);
      await t.tap(find.text('Elegir pareja'));
      await _settle(t);
      expect(find.byType(FriendsScreen), findsNothing);
      expect(find.text('Laura G. es tu pareja habitual'), findsOneWidget);
      expect(find.text('Marcos Ruiz'), findsNothing);

      await t.tap(find.descendant(of: find.ancestor(of: find.text('PAREJA HABITUAL'), matching: find.byType(ListTile)), matching: find.byType(IconButton)));
      await _settle(t);
      expect(find.text('Pareja habitual quitada'), findsOneWidget);
      expect(find.text('Añadir pareja habitual'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('Foto de perfil y avatares', () {
    Future<MockAuthRepository> openEditor(WidgetTester t) async {
      final auth = MockAuthRepository();
      await _app(t, overrides: [authRepositoryProvider.overrideWithValue(auth)]);
      await _openTab(t, 'Perfil');
      await t.tap(find.bySemanticsLabel('Editar perfil'));
      await _settle(t);
      return auth;
    }

    Future<void> openSheet(WidgetTester t) async {
      await t.tap(find.byTooltip('Cambiar foto o avatar'));
      await _settle(t, 3);
    }

    testWidgets('elegir un avatar lo guarda (url + id), borra las imágenes anteriores y se puede eliminar después', (t) async {
      final auth = await openEditor(t);
      await openSheet(t);
      expect(find.text('Subir foto de la galería'), findsOneWidget);
      expect(find.text('AVATARES'), findsOneWidget);
      expect(find.text('Eliminar foto'), findsNothing);   // aún no hay imagen
      await t.tap(find.bySemanticsLabel('Avatar Bandeja'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));   // PNG del avatar (toImage)
      await _settle(t);
      var d = await auth.loadOnboarding();
      expect(d.avatarId, 'a3');
      expect(d.avatarUrl, isNotNull);
      expect(auth.deletedKeeping.last, d.avatarUrl);   // se conserva solo la imagen nueva
      expect(find.text('Avatar actualizado'), findsOneWidget);

      // Aunque ya tenga imagen, la galería sigue disponible y aparece «Eliminar foto».
      await openSheet(t);
      expect(find.text('AVATARES'), findsOneWidget);
      await t.tap(find.text('Eliminar foto'));
      await _settle(t);
      d = await auth.loadOnboarding();
      expect((d.avatarUrl, d.avatarId), (null, null));
      expect(auth.deletedKeeping.last, isNull);          // se borran todas las imágenes del usuario
      expect(find.text('Foto eliminada'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
