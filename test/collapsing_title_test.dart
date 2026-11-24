import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/widgets/collapsing_title.dart';

Widget _app({bool reduce = false}) => MaterialApp(home: MediaQuery(
    data: MediaQueryData(size: const Size(390, 844), disableAnimations: reduce),
    child: Scaffold(body: CollapsingTitleScaffold(title: 'Competiciones',
        child: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('fila $i'))])))));

double _size(WidgetTester t) => t.widget<Text>(find.text('Competiciones')).style!.fontSize!;

void main() {
  testWidgets('el título grande se encoge al desplazar y vuelve al subir', (t) async {
    await t.pumpWidget(_app());
    expect(_size(t), 28);
    await t.drag(find.byType(ListView), const Offset(0, -24));
    await t.pump();
    expect(_size(t), inExclusiveRange(17, 28));          // a mitad: interpolado
    await t.drag(find.byType(ListView), const Offset(0, -200));
    await t.pumpAndSettle();
    expect(_size(t), 17);
    await t.drag(find.byType(ListView), const Offset(0, 600));
    await t.pumpAndSettle();
    expect(_size(t), 28);
    expect(find.bySemanticsLabel('Competiciones'), findsOneWidget);
  });

  testWidgets('con reducir movimiento cambia de golpe, sin tamaños intermedios', (t) async {
    await t.pumpWidget(_app(reduce: true));
    await t.drag(find.byType(ListView), const Offset(0, -20));
    await t.pump();
    expect(_size(t), 28);
    await t.drag(find.byType(ListView), const Offset(0, -30));
    await t.pump();
    expect(_size(t), 17);
  });
}
