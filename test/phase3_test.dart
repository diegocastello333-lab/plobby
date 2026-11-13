import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plobby/core/live/presence.dart';
import 'package:plobby/core/net/timeout_client.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/messaging/presentation/chat_screen.dart';

/// Cliente que nunca responde (red colgada).
class _Hang extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => Completer<http.StreamedResponse>().future;
}

class _Presence implements PresenceService {
  final ctl = StreamController<bool>.broadcast();
  bool active = false;
  @override
  void setActive(bool a) => active = a;
  @override
  Stream<bool> watch(String userId) async* { yield false; yield* ctl.stream; }
}

Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

void main() {
  group('Consultas que no terminan', () {
    test('una petición colgada termina en TimeoutException (no deja la pantalla cargando)', () async {
      final c = TimeoutHttpClient(_Hang(), const Duration(milliseconds: 50));
      await expectLater(c.get(Uri.parse('https://x.supabase.co/rest/v1/rpc/create_match')), throwsA(isA<TimeoutException>()));
    });
    test('las subidas a Storage tienen más margen que las consultas', () {
      final c = TimeoutHttpClient(_Hang());
      expect(c.limitFor(http.Request('POST', Uri.parse('https://x.supabase.co/storage/v1/object/avatars/u/banner_1.jpg'))), const Duration(seconds: 60));
      expect(c.limitFor(http.Request('POST', Uri.parse('https://x.supabase.co/rest/v1/rpc/send_message'))), const Duration(seconds: 20));
    });
  });

  group('Presencia en el chat', () {
    testWidgets('«Desconectado» → «En línea» en tiempo real según la presencia del amigo', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final p = _Presence();
      await t.pumpWidget(ProviderScope(overrides: [presenceServiceProvider.overrideWithValue(p)],
          child: MaterialApp(theme: buildPlobbyTheme(), home: const ChatScreen(conversationId: 'c_marcos', title: 'Marcos R.', otherId: 'marcos'))));
      await _settle(t, 4);
      expect(find.text('Desconectado'), findsOneWidget);
      p.ctl.add(true);
      await _settle(t, 2);
      expect(find.text('En línea'), findsOneWidget);
      p.ctl.add(false);
      await _settle(t, 2);
      expect(find.text('Desconectado'), findsOneWidget);
    });
  });
}
