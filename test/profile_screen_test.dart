import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/profile/presentation/profile_screen.dart';

/// Regresión: el perfil PROPIO se quedaba en blanco porque «Próximos partidos» y «Últimos partidos» compartían la
/// misma GlobalKey («Duplicate keys found»). Se renderiza con los repositorios mock (sin Supabase).
void main() {
  Future<void> pumpProfile(WidgetTester t, String id) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(child: MaterialApp(theme: buildPlobbyTheme(), home: ProfileScreen(playerId: id))));
    for (var i = 0; i < 4; i++) { await t.pump(const Duration(milliseconds: 300)); }
  }

  testWidgets('el perfil propio se dibuja con sus dos secciones de partidos', (t) async {
    await pumpProfile(t, 'me');
    expect(t.takeException(), isNull);
    expect(find.text('Diego Castello'), findsWidgets);
    await t.scrollUntilVisible(find.text('Últimos partidos'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Próximos partidos', skipOffstage: false), findsOneWidget);
    expect(find.text('Últimos partidos'), findsOneWidget);
  });

  testWidgets('la pestaña «Partidos» navega sin errores (perfil propio y ajeno)', (t) async {
    for (final id in ['me', 'marcos']) {
      await pumpProfile(t, id);
      await t.tap(find.text('Partidos').first);
      for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 100)); }  // hay animaciones continuas (skeleton)
      expect(t.takeException(), isNull, reason: 'perfil $id');
    }
  });
}
