import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/theme/plobby_text.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/motion_widgets.dart';
import 'package:plobby/core/widgets/plobby_components.dart';
import 'package:plobby/core/widgets/plobby_icon.dart';

/// Sistema de diseño: los componentes deben medir lo mismo que en el prototipo HTML (valores de getComputedStyle).
void main() {
  Future<void> pump(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(theme: buildPlobbyTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: 350, child: w)))));

  testWidgets('los 50 iconos del prototipo se dibujan sin errores', (t) async {
    expect(PlobbyIcons.values.length, 50);
    await pump(t, Wrap(children: [for (final i in PlobbyIcons.values) PlobbyIcon(i)]));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(PlobbyIcon).first), const Size(20, 20));   // ic(n, s = 20)
  });

  testWidgets('botones: .pbtn/.obtn 48 px · .sbtn 36 px', (t) async {
    await pump(t, Column(children: [
      PlobbyButton(label: 'Continuar', onPressed: () {}),
      PlobbyButton(label: 'Atrás', onPressed: () {}, kind: PlobbyButtonKind.outline),
      PlobbyButton(label: 'Crear liga', onPressed: () {}, kind: PlobbyButtonKind.small, icon: PlobbyIcons.plus),
    ]));
    expect(t.getSize(find.byType(PlobbyButton).at(0)).height, 48);
    expect(t.getSize(find.byType(PlobbyButton).at(0)).width, 350);         // ancho completo
    expect(t.getSize(find.byType(PlobbyButton).at(1)).height, 48);
    expect(t.getSize(find.byType(PlobbyButton).at(2)).height, 36);
    expect(t.getSize(find.byType(PlobbyButton).at(2)).width, lessThan(350)); // .sbtn: ancho del contenido
  });

  testWidgets('botón desactivado y ocupado no llaman al callback', (t) async {
    var n = 0;
    await pump(t, Column(children: [
      PlobbyButton(label: 'A', onPressed: () => n++, busy: true),
      const PlobbyButton(label: 'B', onPressed: null),
    ]));
    await t.tap(find.byType(PlobbyButton).first);
    await t.tap(find.text('B'));
    expect(n, 0);
  });

  testWidgets('filtro .fc 34 px, píldora .chip 24 px, botón de icono .ibtn 40 px, .mini 38 px', (t) async {
    var tapped = false;
    await pump(t, Wrap(children: [
      PlobbyFilterChip(label: 'Todas', selected: true, onTap: () => tapped = true),
      const Pill('Temporada 01'),
      IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', onPressed: () {}),
      MiniAction(approve: true, tooltip: 'Aprobar', onPressed: () {}),
    ]));
    expect(t.getSize(find.byType(PlobbyFilterChip)).height, 34);
    expect(t.getSize(find.byType(Pill)).height, 24);
    expect(t.getSize(find.byType(IconSquareButton)), const Size(40, 40));
    expect(t.getSize(find.byType(MiniAction)), const Size(38, 38));
    await t.tap(find.text('Todas'));
    expect(tapped, isTrue);
  });

  testWidgets('campo con etiqueta encima: escribe, respeta maxLength y no muestra contador', (t) async {
    String? v;
    await pump(t, LabeledField(label: 'Nombre de la liga', hint: 'Ej. Liga de los jueves', maxLength: 5, onChanged: (x) => v = x));
    expect(find.text('Nombre de la liga'), findsOneWidget);
    await t.enterText(find.byType(TextFormField), 'abcdefgh');
    expect(v, 'abcde');
    expect(find.text('5/5'), findsNothing);
    expect(t.getSize(find.byType(TextField)).height, closeTo(48, 1));   // .inp: 48 px
  });

  testWidgets('el texto de los campos no hereda el espaciado de Material (CSS: 0)', (t) async {
    await pump(t, const LabeledField(label: 'X', hint: 'Buscar'));
    final ctx = t.element(find.byType(TextField));
    expect(Theme.of(ctx).textTheme.bodyLarge?.letterSpacing, 0);
    expect(Theme.of(ctx).textTheme.bodyMedium?.letterSpacing, 0);
  });

  testWidgets('pestañas .seg cambian con onChanged', (t) async {
    var i = 0;
    await pump(t, StatefulBuilder(builder: (_, set) => SlidingTabs(labels: const ['Clasificación', 'Actividad', 'Partidos', 'Miembros'], index: i, onChanged: (x) => set(() => i = x))));
    await t.tap(find.text('Partidos'));
    await t.pumpAndSettle();
    expect(i, 2);
    expect(t.getSize(find.byType(SlidingTabs)).height, 46);
  });

  test('tipografía: familias empaquetadas, tamaños del CSS', () {
    expect(PlobbyText.t1.fontFamily, 'Unbounded');
    expect(PlobbyText.t1.fontSize, 28);
    expect(PlobbyText.sec.fontSize, 18);
    expect(PlobbyText.sub.fontFamily, 'Inter');
    expect(buildPlobbyTheme().textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(buildPlobbyTheme().textTheme.displayMedium?.fontFamily, 'Unbounded');
  });
}
