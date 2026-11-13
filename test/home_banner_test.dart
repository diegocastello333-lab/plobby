import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/plobby_components.dart';
import 'package:plobby/features/home/application/banner_clock.dart';
import 'package:plobby/features/home/domain/banner_schedule.dart';
import 'package:plobby/features/home/presentation/banner_catalog.dart';
import 'package:plobby/features/profile/application/profile_providers.dart';
import 'package:plobby/features/profile/data/mock_profile_repository.dart';

Finder _asset(String path) => find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == path);

DayPhase _expected(int h) => switch (h) { >= 6 && < 9 => DayPhase.amanecer, >= 9 && < 18 => DayPhase.dia, >= 18 && < 20 => DayPhase.atardecer, _ => DayPhase.noche };

void main() {
  group('Franjas horarias (hora local)', () {
    test('los 1440 minutos del día caen en la franja de la tabla', () {
      for (var m = 0; m < 1440; m++) {
        expect(dayPhaseAt(DateTime(2026, 11, 13, m ~/ 60, m % 60)), _expected(m ~/ 60), reason: '${m ~/ 60}:${m % 60}');
      }
    });

    test('cambia exactamente a las 06:00, 09:00, 18:00 y 20:00 (y los ejemplos pedidos)', () {
      DayPhase at(int h, int m, [int s = 0]) => dayPhaseAt(DateTime(2026, 11, 13, h, m, s));
      expect([at(5, 59, 59), at(6, 0)], [DayPhase.noche, DayPhase.amanecer]);
      expect([at(8, 59, 59), at(9, 0)], [DayPhase.amanecer, DayPhase.dia]);
      expect([at(17, 59, 59), at(18, 0)], [DayPhase.dia, DayPhase.atardecer]);
      expect([at(19, 59, 59), at(20, 0)], [DayPhase.atardecer, DayPhase.noche]);
      expect([at(7, 30), at(9, 0), at(15, 30), at(18, 0), at(20, 0), at(2, 0), at(6, 0)],
          [DayPhase.amanecer, DayPhase.dia, DayPhase.dia, DayPhase.atardecer, DayPhase.noche, DayPhase.noche, DayPhase.amanecer]);
    });

    test('la noche cruza la medianoche: 23:59 → 00:00 → 05:59 siguen siendo noche', () {
      expect(dayPhaseAt(DateTime(2026, 12, 31, 23, 59, 59)), DayPhase.noche);
      expect(dayPhaseAt(DateTime(2027, 1, 1)), DayPhase.noche);
      expect(dayPhaseAt(DateTime(2027, 1, 1, 5, 59)), DayPhase.noche);
      expect(nextPhaseChange(DateTime(2026, 12, 31, 21)), DateTime(2027, 1, 1, 6));            // cambio de año incluido
      expect(nextPhaseChange(DateTime(2026, 11, 13, 7, 30)), DateTime(2026, 11, 13, 9));
      expect(nextPhaseChange(DateTime(2026, 11, 13, 9)), DateTime(2026, 11, 13, 18));          // justo en el cambio → el siguiente
      expect(nextPhaseChange(DateTime(2026, 11, 13, 3)), DateTime(2026, 11, 13, 6));
    });

    test('dos usuarios en zonas distintas ven imágenes distintas en el MISMO instante', () {
      // 13 nov 2026, 19:30 UTC. Cada dispositivo convierte a su hora local con su desfase.
      final instant = DateTime.utc(2026, 11, 13, 19, 30);
      DayPhase local(Duration offset) => dayPhaseAt(instant.add(offset));
      expect(local(const Duration(hours: 1)), DayPhase.noche);       // Madrid (CET, invierno): 20:30
      expect(local(Duration.zero), DayPhase.atardecer);              // Londres (GMT): 19:30
      expect(local(const Duration(hours: -5)), DayPhase.dia);        // Nueva York (EST): 14:30
      expect(local(const Duration(hours: 11)), DayPhase.amanecer);   // Sídney (AEDT, verano austral): 06:30 del 14
    });

    test('usa la hora LOCAL del dispositivo (no UTC ni la del servidor)', () {
      final now = DateTime.now();
      expect(now.isUtc, isFalse);
      expect(dayPhaseAt(now), _expected(now.hour));
      // La misma hora UTC puede dar otra franja si el dispositivo no está en UTC: la app SIEMPRE pasa la local.
      expect(dayPhaseAt(now.toUtc().add(now.timeZoneOffset)), dayPhaseAt(now));
    });

    test('cambio de hora (verano/invierno): la espera real hasta el siguiente cambio lo tiene en cuenta', () {
      // Madrid: 29 mar 2026 a las 02:00 → 03:00 (se pierde una hora); 25 oct 2026 a las 03:00 → 02:00 (se gana).
      for (final (from, to) in [(DateTime(2026, 3, 29, 1, 30), DateTime(2026, 3, 29, 6)), (DateTime(2026, 10, 25, 1, 30), DateTime(2026, 10, 25, 6))]) {
        expect(nextPhaseChange(from), to);
        final shift = to.timeZoneOffset - from.timeZoneOffset;          // 0 en zonas sin cambio de hora (o UTC)
        expect(to.difference(from), const Duration(hours: 4, minutes: 30) - shift);
        expect(dayPhaseAt(to), DayPhase.amanecer);
      }
    });
  });

  group('Colecciones', () {
    test('solo existen Seaside y Tropical, con sus cuatro imágenes cada uno', () {
      expect(HomeBanner.values.map((b) => b.name), ['Seaside', 'Tropical']);
      final all = [for (final b in HomeBanner.values) ...b.assets];
      expect(all.toSet().length, 8);
      expect(HomeBanner.banner1.assets, [for (final p in ['amanecer', 'dia', 'atardecer', 'noche']) 'assets/images/banners/banner1/$p.jpg']);
      expect(HomeBanner.banner2.assets, [for (final p in ['amanecer', 'dia', 'atardecer', 'noche']) 'assets/images/banners/banner2/$p.jpg']);
    });

    test('preferencia: null o un banner antiguo → Seaside; «banner2» → Tropical', () {
      expect(HomeBanner.fromId(null), HomeBanner.banner1);
      for (final old in ['clasico', 'noche', 'lima', 'azul']) { expect(HomeBanner.fromId(old), HomeBanner.banner1); }
      expect(HomeBanner.fromId('banner2'), HomeBanner.banner2);
      for (final b in HomeBanner.values) { expect(RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(b.id), isTrue); }   // restricción de la columna
    });

    testWidgets('las 8 imágenes están empaquetadas, son JPEG válidos y todas con el mismo encuadre (1376×768)', (t) async {
      for (final b in HomeBanner.values) {
        for (final a in b.assets) {
          final bytes = (await t.runAsync(() => rootBundle.load(a)))!.buffer.asUint8List();
          final im = (await t.runAsync(() async => img.decodeJpg(bytes)))!;
          expect((im.width, im.height), (1376, 768), reason: a);
          expect(bytes.length, lessThan(400 * 1024), reason: a);
        }
      }
    });
  });

  group('Reloj del banner', () {
    late DateTime now;
    late ProviderContainer c;
    late List<DayPhase> seen;
    Future<void> advance(WidgetTester t, Duration d) async { now = now.add(d); await t.pump(d); }

    void start(DateTime at) {
      now = at;
      c = ProviderContainer(overrides: [bannerNowProvider.overrideWithValue(() => now)]);
      seen = [];
      c.listen(bannerClockProvider, (_, p) => seen.add(p), fireImmediately: true);
    }

    testWidgets('cambia solo a la hora exacta, con la app abierta, y emite 4 veces en 24 h', (t) async {
      start(DateTime(2026, 11, 13, 8, 59, 58));
      expect(c.read(bannerClockProvider), DayPhase.amanecer);
      await advance(t, const Duration(seconds: 1));
      expect(c.read(bannerClockProvider), DayPhase.amanecer);          // 08:59:59
      await advance(t, const Duration(seconds: 1, milliseconds: 300));
      expect(c.read(bannerClockProvider), DayPhase.dia);               // 09:00:00
      // Avanzamos un día entero, minuto a minuto (como pasa el tiempo real).
      for (var i = 0; i < 24 * 60; i++) { await advance(t, const Duration(minutes: 1)); }
      expect(seen, [DayPhase.amanecer, DayPhase.dia, DayPhase.atardecer, DayPhase.noche, DayPhase.amanecer, DayPhase.dia]);
      c.dispose();
    });

    testWidgets('al volver de segundo plano muestra la imagen correcta aunque los temporizadores no corrieran', (t) async {
      start(DateTime(2026, 11, 13, 7));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime(2026, 11, 13, 21, 15);          // 14 h en segundo plano: los temporizadores no han corrido
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(c.read(bannerClockProvider), DayPhase.noche);
      c.dispose();
    });

    testWidgets('si cambia la zona horaria (o la hora del sistema) con la app abierta, se corrige en ≤ 1 minuto', (t) async {
      start(DateTime(2026, 11, 13, 10));             // Madrid, 10:00 → Día
      expect(c.read(bannerClockProvider), DayPhase.dia);
      now = DateTime(2026, 11, 13, 4);               // vuela a Nueva York: allí son las 04:00
      await t.pump(BannerClock.watchInterval);
      expect(c.read(bannerClockProvider), DayPhase.noche);
      // Y el temporizador se reprogramó para las 06:00 de la NUEVA hora local.
      now = DateTime(2026, 11, 13, 5, 59, 59);
      await t.pump(const Duration(seconds: 1));
      now = DateTime(2026, 11, 13, 6, 0, 1);
      await t.pump(const Duration(seconds: 60));
      expect(c.read(bannerClockProvider), DayPhase.amanecer);
      c.dispose();
    });
  });

  group('Inicio y selector', () {
    late DateTime now;
    Future<void> settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }
    Future<void> app(WidgetTester t, MockProfileRepository repo) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(key: UniqueKey(), overrides: [profileRepositoryProvider.overrideWithValue(repo), bannerNowProvider.overrideWithValue(() => now)],
          child: Consumer(builder: (_, ref, __) => MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider)))));
      await settle(t);
    }

    testWidgets('Seaside por defecto; el selector solo ofrece Seaside y Tropical, sin textos técnicos; elegir Tropical se guarda y se aplica', (t) async {
      now = DateTime(2026, 11, 13, 15, 30);
      final repo = MockProfileRepository();
      await app(t, repo);
      expect(_asset('assets/images/banners/banner1/dia.jpg'), findsOneWidget);
      // Ocupa todo el banner (cover, sin deformar ni bandas).
      expect(t.getSize(_asset('assets/images/banners/banner1/dia.jpg')), Size(390, homeBannerHeight(t.element(find.byType(Scaffold).first))));

      await t.tap(find.bySemanticsLabel('Personalizar banner'));
      await settle(t);
      expect(find.text('Banner de Inicio'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^(Seaside|Tropical)(, seleccionado)?$')), findsNWidgets(2));
      expect(find.bySemanticsLabel('Seaside, seleccionado'), findsOneWidget);
      expect(find.text('Seaside'), findsOneWidget);
      expect(find.text('Tropical'), findsOneWidget);
      // Nada de banners antiguos ni de información técnica (momentos del día, horarios).
      for (final old in ['Clásico', 'Pista de noche', 'Subir una foto de la galería', 'Banner 1', 'Banner 2', 'Amanecer', 'Día', 'Atardecer', 'Noche']) {
        expect(find.text(old), findsNothing, reason: old);
      }
      final sheet = find.ancestor(of: find.byType(SheetHeader), matching: find.byType(Column)).first;
      expect(find.descendant(of: sheet, matching: find.textContaining(RegExp(r'\d\d:\d\d'))), findsNothing);
      // Cada tarjeta enseña la imagen de SU colección para la hora actual (15:30 → día).
      expect(_asset('assets/images/banners/banner2/dia.jpg'), findsOneWidget);

      await t.tap(find.bySemanticsLabel('Tropical'));
      await settle(t);
      expect((await t.runAsync(() => repo.load('me')))!.profile.bannerId, 'banner2');
      expect(find.text('Tropical aplicado'), findsOneWidget);
      await settle(t, 6);
      expect(_asset('assets/images/banners/banner2/dia.jpg'), findsOneWidget);
      expect(_asset('assets/images/banners/banner1/dia.jpg'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('con la app abierta en Inicio, a las 18:00 pasa sola a Atardecer con un fundido (sin hueco)', (t) async {
      now = DateTime(2026, 11, 13, 17, 59, 59);
      final repo = MockProfileRepository();
      await t.runAsync(() => repo.setBanner('banner2'));
      await app(t, repo);
      expect(_asset('assets/images/banners/banner2/dia.jpg'), findsOneWidget);
      now = DateTime(2026, 11, 13, 18, 0, 1);
      await t.pump(const Duration(seconds: 2));
      await t.pump(const Duration(milliseconds: 300));
      // A mitad del fundido conviven las dos: nunca hay un fotograma vacío.
      expect(_asset('assets/images/banners/banner2/dia.jpg'), findsOneWidget);
      expect(_asset('assets/images/banners/banner2/atardecer.jpg'), findsOneWidget);
      await settle(t, 6);
      expect(_asset('assets/images/banners/banner2/dia.jpg'), findsNothing);
      expect(_asset('assets/images/banners/banner2/atardecer.jpg'), findsOneWidget);
    });

    testWidgets('la preferencia se mantiene al cerrar y volver a abrir la app', (t) async {
      now = DateTime(2026, 11, 13, 22);
      final repo = MockProfileRepository();
      await t.runAsync(() => repo.setBanner('banner2'));
      await app(t, repo);
      expect(_asset('assets/images/banners/banner2/noche.jpg'), findsOneWidget);
      await t.pumpWidget(const SizedBox());           // «cierra» la app
      now = DateTime(2026, 11, 14, 7);
      await app(t, repo);                             // la vuelve a abrir al día siguiente
      expect(_asset('assets/images/banners/banner2/amanecer.jpg'), findsOneWidget);
    });
  });
}
