import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/feed/presentation/widgets/activity_cards.dart';
import 'package:plobby/features/feed/presentation/widgets/comments_sheet.dart';

/// V7 · Feed: cabecera, burbujas, filtros fijos, tarjetas, reacciones y comentarios (repositorio mock).
Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

Future<void> _openFeed(WidgetTester t, {double width = 390}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) => MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider)))));
  await _settle(t, 4);
  await t.tap(find.bySemanticsLabel('Feed').last);
  await _settle(t, 8);
}

void main() {
  testWidgets('cabecera, burbujas y tarjetas de actividad', (t) async {
    await _openFeed(t);
    expect(find.bySemanticsLabel('Plobby'), findsOneWidget);
    expect(find.text('Tu comunidad de pádel está jugando.'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('actividad reciente')), findsWidgets);
    expect(find.byType(ActivityCard), findsWidgets);
    expect(find.text('VICTORIA'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('filtro «Logros» deja solo logros; «Todo» vuelve a mostrar partidos', (t) async {
    await _openFeed(t);
    await t.tap(find.bySemanticsLabel('Logros'));
    await _settle(t);
    expect(find.text('VICTORIA'), findsNothing);
    expect(find.textContaining('acaba de desbloquear'), findsWidgets);
    await t.tap(find.bySemanticsLabel('Todo'));
    await _settle(t);
    expect(find.text('VICTORIA'), findsWidgets);
  });

  testWidgets('reaccionar marca la reacción y suma uno', (t) async {
    await _openFeed(t);
    List<String> state() => [for (final e in find.bySemanticsLabel(RegExp('^Reaccionar con')).evaluate()) '${t.getSemantics(find.byWidget(e.widget)).flagsCollection.isSelected}'];
    final before = state();
    await t.tap(find.bySemanticsLabel(RegExp('^Reaccionar con')).first);
    await _settle(t, 3);
    expect(state(), isNot(equals(before)));
  });

  testWidgets('comentarios: la hoja tapa la barra inferior, valida vacío y publica', (t) async {
    await _openFeed(t);
    await t.tap(find.text('Comentar').first);
    await _settle(t);
    expect(find.byType(CommentsSheet), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Enviar comentario'));
    await t.pump();
    expect(find.text('Escribe algo antes de enviar.'), findsOneWidget);
    await t.enterText(find.descendant(of: find.byType(CommentsSheet), matching: find.byType(TextField)), '¡Qué partidazo!');
    await t.tap(find.bySemanticsLabel('Enviar comentario'));
    await _settle(t, 4);
    expect(find.textContaining('¡Qué partidazo!'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  for (final w in [390.0, 320.0]) {
    testWidgets('sin desbordamientos a $w px al recorrer el feed', (t) async {
      await _openFeed(t, width: w);
      for (var i = 0; i < 6; i++) {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await _settle(t, 2);
        expect(t.takeException(), isNull, reason: 'desplazamiento $i');
      }
    });
  }
}
