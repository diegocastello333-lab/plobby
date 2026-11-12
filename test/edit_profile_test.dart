import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/profile/presentation/edit_profile_screen.dart';

/// «Editar perfil»: antes el botón llevaba a una ruta inexistente. Repositorios mock (modo demo).
void main() {
  Future<void> openProfile(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) =>
        MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider)))));
    for (var i = 0; i < 4; i++) { await t.pump(const Duration(milliseconds: 300)); }
    await t.tap(find.bySemanticsLabel('Perfil').last);   // pestaña Perfil de la barra inferior
    for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 300)); }
  }

  Future<void> openEditor(WidgetTester t) async {
    await openProfile(t);
    await t.tap(find.bySemanticsLabel('Editar perfil'));
    for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 300)); }
  }

  Finder field(String label) => find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first, matching: find.byType(TextFormField));

  testWidgets('«Editar perfil» abre la pantalla con los datos actuales', (t) async {
    await openEditor(t);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.text('EDITAR PERFIL'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Diego'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'diego.c'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('guardar actualiza la bio del perfil y vuelve', (t) async {
    await openEditor(t);
    // El mock de autenticación marca «diego.c» como ocupado incluso para su propio usuario; la RPC real
    // (is_username_available) excluye al propio usuario. Se usa un usuario nuevo para no depender de esa diferencia.
    await t.enterText(field('Nombre de usuario'), 'diego.castello');
    await t.enterText(field('Bio'), 'Revés a dos manos.');
    await t.ensureVisible(find.text('Guardar'));
    await t.tap(find.text('Guardar'));
    for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 300)); }
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.text('Revés a dos manos.'), findsOneWidget);
  });

  testWidgets('usuario no válido o ya en uso: muestra el error y no sale', (t) async {
    await openEditor(t);
    await t.enterText(field('Nombre de usuario'), 'Con Espacios');
    await t.tap(find.text('Guardar'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Usa 3–24 letras'), findsOneWidget);
    await t.enterText(field('Nombre de usuario'), 'admin');   // ocupado en el mock (igual que la RPC is_username_available)
    await t.tap(find.text('Guardar'));
    for (var i = 0; i < 4; i++) { await t.pump(const Duration(milliseconds: 300)); }
    expect(find.text('Ese usuario ya está en uso.'), findsOneWidget);
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  test('validación (mismas reglas que save_onboarding_step)', () {
    expect(validateProfileEdit(first: 'Diego', last: 'Castello', username: 'diego.c', bio: ''), isEmpty);
    expect(validateProfileEdit(first: 'D', last: 'C', username: 'Diego C', bio: 'x' * 161).keys, containsAll(['first', 'last', 'username', 'bio']));
  });
}
