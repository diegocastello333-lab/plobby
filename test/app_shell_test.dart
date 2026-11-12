import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';

/// Barra inferior con el router real (modo demo, repositorios mock).
void main() {
  Future<void> pumpApp(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) =>
        MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider)))));
    for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 300)); }
  }

  bool selected(WidgetTester t, String label) => t.getSemantics(find.bySemanticsLabel(label).last).getSemanticsData().flagsCollection.isSelected.toBoolOrNull() == true;

  testWidgets('cada pestaña abre su sección y queda marcada como activa', (t) async {
    await pumpApp(t);
    expect(selected(t, 'Inicio'), isTrue);
    for (final (tab, marker) in const [('Ligas', 'Compite con tu comunidad.'), ('Feed', 'Tu comunidad de pádel está jugando.'), ('Perfil', 'Diego Castello')]) {
      await t.tap(find.bySemanticsLabel(tab).last);
      for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 300)); }
      expect(find.text(marker, skipOffstage: false), findsWidgets, reason: tab);
      expect(selected(t, tab), isTrue, reason: tab);
      expect(selected(t, 'Inicio'), isFalse);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('el botón «+» abre el menú de nuevo partido', (t) async {
    await pumpApp(t);
    await t.tap(find.bySemanticsLabel('Nuevo partido'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Crear partido amistoso'), findsOneWidget);
    expect(find.text('Crear partido de liga'), findsOneWidget);
  });

  testWidgets('la barra mide 92 px como en el HTML', (t) async {
    await pumpApp(t);
    final bar = find.ancestor(of: find.bySemanticsLabel('Ligas').last, matching: find.byType(Container)).last;
    expect(t.getSize(bar).height, 92);
  });
}
