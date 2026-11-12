import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/home/presentation/banner_catalog.dart';
import 'package:plobby/features/home/presentation/banner_editor.dart';
import 'package:plobby/features/home/presentation/home_screen.dart';
import 'package:plobby/features/splash/application/splash_boot.dart';
import 'package:plobby/features/splash/presentation/splash_screen.dart';

Uint8List _jpeg(int w, int h) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

void main() {
  group('Pantalla de carga', () {
    Future<void> app(WidgetTester t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) => MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider)))));
    }

    testWidgets('aparece al abrir la app, anima y entra en Inicio (sin volver a ella)', (t) async {
      SplashBoot.pending = true;
      await app(t);
      await t.pump();
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      // Animación de entrada (2,1 s) + salida (0,26 s) + transición al Inicio.
      for (var i = 0; i < 16; i++) { await t.pump(const Duration(milliseconds: 200)); }
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('si el router se recrea (inicio/cierre de sesión) no se repite', (t) async {
      SplashBoot.pending = false;
      await app(t);
      await t.pump();
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 300)); }   // datos de demo
    });

    testWidgets('con «reducir movimiento» muestra el estado final y continúa', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var done = 0;
      await t.pumpWidget(MaterialApp(theme: buildPlobbyTheme(), home: MediaQuery(data: const MediaQueryData(disableAnimations: true),
          child: SplashScreen(onFinished: () => done++))));
      expect(find.text('plobby'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 800));
      expect(done, 1);
    });
  });

  group('Banner: ocupa siempre todo el espacio', () {
    // Restricciones sueltas como las del Stack interno de AnimatedSwitcher (la causa del fallo).
    Widget host(Widget child) => MaterialApp(home: Center(child: SizedBox(width: 390, height: 340, child: Stack(children: [child]))));

    testWidgets('predeterminado y foto clásica rellenan el banner aunque el padre dé restricciones sueltas', (t) async {
      await t.pumpWidget(host(const BannerImage(presetId: 'noche')));
      expect(t.getSize(find.byType(SvgPicture)), const Size(390, 340));
      await t.pumpWidget(host(const BannerImage()));
      expect(t.getSize(find.byType(Image)), const Size(390, 340));
    });

    for (final (name, w, h) in [('vertical', 900, 1600), ('horizontal', 1600, 900), ('cuadrada', 1200, 1200)]) {
      testWidgets('foto $name: el encuadre tiene la proporción exacta del banner y no deforma', (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        const aspect = 390 / 340;
        Rect? result;
        final src = BannerSource(_jpeg(w, h), w, h);
        await t.pumpWidget(MaterialApp(theme: buildPlobbyTheme(), home: Builder(builder: (c) {
          Future<void> open() async {
            result = await Navigator.of(c).push<Rect>(MaterialPageRoute(builder: (_) => BannerCropScreen(source: src, aspect: aspect)));
          }
          return Scaffold(body: Center(child: TextButton(onPressed: open, child: const Text('abrir'))));
        })));
        await t.tap(find.text('abrir'));
        await t.pumpAndSettle();
        await t.tap(find.text('Guardar banner'));
        await t.pumpAndSettle();
        final r = result!;
        expect(r.width / r.height, closeTo(aspect, .01));            // misma proporción que el banner
        expect(r.left >= -0.5 && r.top >= -0.5 && r.right <= w + .5 && r.bottom <= h + .5, isTrue, reason: '$r');   // dentro de la foto: sin bandas
        // Recorte centrado y lo más grande posible (la foto llena el marco).
        expect(r.width >= w - 1 || r.height >= h - 1, isTrue);
        final out = img.decodeJpg(cropBannerJpeg(BannerCropJob(_jpeg(w, h), r)))!;
        expect(out.width / out.height, closeTo(aspect, .01));
        expect(out.width, lessThanOrEqualTo(1200));                   // optimizada, nunca ampliada
      });
    }
  });
}
