import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/messaging/presentation/chat_screen.dart';

/// V8 · Amigos, notificaciones y mensajes (repositorios mock): mismas acciones tras el rediseño y sin desbordamientos.
Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

Future<GoRouter> _app(WidgetTester t, String path, {double width = 390}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late GoRouter r;
  await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) { r = ref.watch(routerProvider); return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r); })));
  await _settle(t, 4);
  r.push(path);
  await _settle(t, 8);
  return r;
}

void main() {
  testWidgets('Amigos: busca y abre las opciones de un amigo', (t) async {
    await _app(t, '/friends');
    expect(find.text('Laura G.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'marcos');
    await _settle(t, 2);
    expect(find.text('Laura G.'), findsNothing);
    await t.tap(find.bySemanticsLabel('Opciones de Marcos R.'));
    await _settle(t);
    expect(find.text('Enviar mensaje'), findsOneWidget);
    expect(find.text('Eliminar amigo'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Añadir amigos: aceptar una solicitud la quita de «recibidas»', (t) async {
    await _app(t, '/friends/add');
    expect(find.text('SOLICITUDES RECIBIDAS'), findsOneWidget);
    await t.tap(find.text('Aceptar').first);
    await _settle(t, 4);
    expect(find.text('SOLICITUDES RECIBIDAS'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Notificaciones: agrupadas por día, acciones en línea y marcar leídas', (t) async {
    await _app(t, '/notifications');
    expect(find.text('HOY'), findsOneWidget);
    expect(find.text('Solicitud de amistad'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Sin leer')), findsWidgets);
    await t.tap(find.text('Marcar leídas'));
    await _settle(t, 3);
    expect(find.bySemanticsLabel(RegExp('Sin leer')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Mensajes: abrir una conversación y enviar un mensaje', (t) async {
    await _app(t, '/messages');
    await t.tap(find.text('Marcos R.').first);
    await _settle(t, 8);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('CONVERSACIÓN PRIVADA'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Allí estaré');
    await t.tap(find.bySemanticsLabel('Enviar'));
    await _settle(t, 4);
    expect(find.text('Allí estaré'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Acciones rápidas'));
    await _settle(t);
    expect(find.text('Invitar a jugar'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Nuevo grupo: sin participantes muestra el error; con uno se crea y abre el chat del grupo', (t) async {
    await _app(t, '/messages/group/new');
    await t.enterText(find.byType(TextFormField), 'Pádel de los jueves');
    await t.tap(find.bySemanticsLabel('Crear grupo'));
    await _settle(t, 2);
    expect(find.textContaining('amigo'), findsWidgets);
    // Los mocks de amigos y de mensajes no comparten la misma lista (en Supabase es la misma tabla): Marcos está en ambos.
    await t.tap(find.bySemanticsLabel(RegExp('^Marcos R.')));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Crear grupo'));
    await _settle(t, 8);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('GRUPO'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final w in [390.0, 320.0]) {
    testWidgets('sin desbordamientos a $w px', (t) async {
      final r = await _app(t, '/friends', width: w);
      expect(t.takeException(), isNull);
      for (final p in ['/friends/add', '/notifications', '/messages', '/messages/group/new']) {
        r.push(p);
        await _settle(t, 6);
        expect(t.takeException(), isNull, reason: p);
      }
    });
  }
}
