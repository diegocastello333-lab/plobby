import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/home/presentation/home_screen.dart';
import 'package:plobby/features/splash/application/splash_boot.dart';
import 'package:plobby/features/splash/presentation/splash_screen.dart';

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
}
