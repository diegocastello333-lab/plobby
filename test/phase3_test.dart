import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:plobby/core/live/presence.dart';
import 'package:plobby/core/net/timeout_client.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/home/presentation/banner_catalog.dart';
import 'package:plobby/features/home/presentation/banner_editor.dart';
import 'package:plobby/features/messaging/presentation/chat_screen.dart';
import 'package:plobby/features/profile/application/profile_providers.dart';
import 'package:plobby/features/profile/data/mock_profile_repository.dart';

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

  group('Banner de Inicio', () {
    Uint8List jpeg(int w, int h) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

    test('el recorte respeta la proporción y no amplía fotos pequeñas (no se pixela)', () {
      final small = img.decodeJpg(cropBannerJpeg(BannerCropJob(jpeg(800, 1200), const Rect.fromLTWH(0, 100, 800, 667))))!;
      expect((small.width, small.height), (800, 667));
      final big = img.decodeJpg(cropBannerJpeg(BannerCropJob(jpeg(2400, 2000), const Rect.fromLTWH(0, 0, 2400, 2000))))!;
      expect((big.width, big.height), (1200, 1000));   // reducida a 1200 px, 6:5
    });

    test('la foto se prepara enderezada y limitada a 2400 px', () {
      final s = prepareBannerSource(jpeg(3000, 2000));
      expect((s.width, s.height), (2400, 1600));
    });

    test('hay banners predeterminados con id válido para la base de datos', () {
      expect(bannerPresets.length, greaterThanOrEqualTo(8));
      for (final b in bannerPresets) { expect(RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(b.id), isTrue, reason: b.id); }
      expect(bannerPresetById('clasico')!.svg, isNull);   // la foto original
    });

    testWidgets('elegir un banner predeterminado lo guarda en el perfil y limpia la foto anterior', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = MockProfileRepository();
      await t.pumpWidget(ProviderScope(overrides: [profileRepositoryProvider.overrideWithValue(repo)],
          child: Consumer(builder: (_, ref, __) => MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider)))));
      await _settle(t);
      await t.tap(find.bySemanticsLabel('Personalizar banner'));
      await _settle(t);
      expect(find.text('Banner de Inicio'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Banner Pista de noche'));
      await _settle(t);
      expect((await t.runAsync(() => repo.load('me')))!.profile.bannerId, 'noche');
      expect(repo.deletedBannersKeeping, [null]);
      expect(find.text('Banner «Pista de noche» aplicado'), findsOneWidget);
      expect(t.takeException(), isNull);
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
