import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/format/names.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/design_tokens.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/wide_frame.dart';
import 'package:plobby/features/leagues/presentation/league_widgets.dart';
import 'package:plobby/features/matches/domain/match_defaults.dart';
import 'package:plobby/features/profile/domain/models.dart';
import 'package:plobby/features/profile/domain/stats_calculator.dart';
import 'package:plobby/features/splash/application/splash_boot.dart';

/// Fase 2: los nueve fallos de la auditoría que se pueden comprobar sin un navegador.
MatchResult _m(DateTime at, String partner, List<String> rivals) => MatchResult(
    id: '${at.millisecondsSinceEpoch}', playedAt: at, won: true, partner: PlayerRef(partner, partner),
    opponents: [for (final r in rivals) PlayerRef(r, r)], sets: const [(6, 3)], venue: 'Club', eloDelta: 10, side: PlaySide.right, confirmed: true);

void main() {
  group('Crear partido: hora por defecto (antes salía 02:26 de madrugada)', () {
    test('de madrugada → a las 19:00 de ese día', () => expect(defaultMatchTime(DateTime(2026, 11, 24, 0, 26)), DateTime(2026, 11, 24, 19)));
    test('por la tarde → la siguiente hora en punto con 1 h de margen', () => expect(defaultMatchTime(DateTime(2026, 11, 24, 17, 10)), DateTime(2026, 11, 24, 19)));
    test('a las 23:30 → mañana a las 19:00 (nunca de madrugada)', () => expect(defaultMatchTime(DateTime(2026, 11, 24, 23, 30)), DateTime(2026, 11, 25, 19)));
    test('nunca antes de las 8:00 ni después de las 23:00', () {
      for (var h = 0; h < 24; h++) {
        for (final min in [0, 29, 59]) {
          final t = defaultMatchTime(DateTime(2026, 11, 24, h, min));
          expect(t.hour, inInclusiveRange(8, 23), reason: '$h:$min → $t');
          expect(t.isAfter(DateTime(2026, 11, 24, h, min)), isTrue);
        }
      }
    });
    test('con hora habitual: la próxima vez que llega esa hora', () {
      expect(defaultMatchTime(DateTime(2026, 11, 24, 10), usualHour: 20), DateTime(2026, 11, 24, 20));
      expect(defaultMatchTime(DateTime(2026, 11, 24, 19, 30), usualHour: 20), DateTime(2026, 11, 25, 20));   // < 1 h: mañana
    });
    test('hora habitual = la más repetida (al menos 2 partidos)', () {
      expect(usualPlayHour([_m(DateTime(2026, 11, 1, 20), 'a', ['b'])]), isNull);
      expect(usualPlayHour([_m(DateTime(2026, 11, 1, 20), 'a', ['b']), _m(DateTime(2026, 11, 3, 20), 'a', ['c']), _m(DateTime(2026, 11, 5, 9), 'a', ['c'])]), 20);
    });
  });

  test('Sugeridos: primero la pareja habitual, luego con quién más juegas; solo amigos y sin uno mismo', () {
    final ms = [_m(DateTime(2026, 11, 1), 'ana', ['bea', 'carla']), _m(DateTime(2026, 11, 2), 'ana', ['bea', 'dani']), _m(DateTime(2026, 11, 3), 'eva', ['bea', 'carla'])];
    expect(suggestedPlayers(habitualPartnerId: 'eva', matches: ms, allowed: {'ana', 'bea', 'carla', 'dani', 'eva'}, meId: 'yo'), ['eva', 'ana', 'bea', 'carla', 'dani']);
    expect(suggestedPlayers(matches: ms, allowed: {'bea', 'dani'}), ['bea', 'dani']);   // no amigos → fuera
  });

  test('Nombres de pareja cortos: «Ana R. · Bea S.» en vez de cortarse a media palabra', () {
    expect(shortName('Ana Rodríguez Pérez'), 'Ana R.');
    expect(shortName('  lucía  álvarez '), 'lucía Á.');
    expect(shortName('Carla'), 'Carla');
    expect(shortName(''), '');
  });

  test('Perfil: un solo nivel en toda la app (el del ELO), con decimal y categoría', () {
    final c = StatsCalculator(now: DateTime(2026, 11, 24));
    expect(c.levelLabel(1210), '2,2 · Intermedio');
    expect(c.levelLabel(800), '1,0 · Principiante');
  });

  test('Portada «pista»: sus bordes quedan dentro del dibujo en cualquier proporción de tarjeta', () {
    for (final aspect in [390 / 120, 335 / 88, 600 / 88, 335 / 64, 390 / 260]) {
      final svg = leagueCoverSvg('court', aspect: aspect);
      final h = double.parse(RegExp(r'viewBox="0 0 390 ([\d.]+)"').firstMatch(svg)![1]!);
      final r = RegExp(r'<rect x="60" y="([\d.]+)" width="270" height="([\d.]+)"/>').firstMatch(svg)!;
      final top = double.parse(r[1]!), bottom = top + double.parse(r[2]!);
      expect(top, greaterThan(0), reason: '$aspect');
      expect(bottom, lessThan(h), reason: '$aspect');
      expect((top - (h - bottom)).abs(), lessThan(.2), reason: 'centrada ($aspect)');
    }
  });

  group('Barra inferior y escritorio', () {
    testWidgets('el margen inferior de las pestañas cubre la barra, la zona segura y el «+»', (t) async {
      late double clearance, bar;
      await t.pumpWidget(MediaQuery(data: const MediaQueryData(size: Size(390, 844), padding: EdgeInsets.only(bottom: 34)),
          child: Builder(builder: (c) { clearance = AppInsets.tabBarClearance(c); bar = AppInsets.tabBarHeight(c); return const SizedBox(); })));
      expect(bar, 66 + 34);
      expect(clearance, greaterThanOrEqualTo(bar + AppInsets.plusOverhang));
    });

    Future<void> pumpApp(WidgetTester t, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SplashBoot.pending = false;
      await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) => MaterialApp.router(theme: buildPlobbyTheme(),
          routerConfig: ref.watch(routerProvider), builder: (_, child) => WideFrame(child: child!)))));
      for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 200)); }
    }

    testWidgets('a 1440 px: columna centrada con barra lateral, sin barra inferior estirada', (t) async {
      await pumpApp(t, const Size(1440, 900));
      expect(t.takeException(), isNull);
      // Logotipo en la barra lateral + el del banner del Inicio (en móvil solo está el del banner).
      expect(find.text('plobby'), findsNWidgets(2));
      // Todo el contenido cabe en la columna de 736 px centrada.
      final scaffold = t.getRect(find.byType(Scaffold).first);
      expect(scaffold.width, WideLayout.frameWidth);
      expect(scaffold.center.dx, closeTo(720, 1));
      expect(find.text('Competiciones'), findsWidgets);
    });

    testWidgets('a 390 px: barra inferior de siempre, sin barra lateral', (t) async {
      await pumpApp(t, const Size(390, 844));
      expect(t.takeException(), isNull);
      expect(t.getRect(find.byType(Scaffold).first).width, 390);
      expect(find.text('plobby'), findsOneWidget);
    });
  });

  testWidgets('Tooltips con ratón: no aparecen al pasar de largo (antes tapaban «Nuevo mensaje»), sí tras 0,8 s quieto', (t) async {
    await t.pumpWidget(MaterialApp(theme: buildPlobbyTheme(), home: Scaffold(body: Center(child: IconButton(tooltip: 'Nuevo mensaje', onPressed: () {}, icon: const Icon(Icons.edit))))));
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    await g.moveTo(t.getCenter(find.byType(IconButton)));
    await t.pump(const Duration(milliseconds: 300));   // timing
    expect(find.text('Nuevo mensaje'), findsNothing);
    await t.pump(const Duration(milliseconds: 700));   // timing
    await t.pump();
    expect(find.text('Nuevo mensaje'), findsOneWidget);
    // debajo del botón, sin taparlo
    expect(t.getTopLeft(find.text('Nuevo mensaje')).dy, greaterThan(t.getBottomLeft(find.byType(IconButton)).dy - 1));
  });
}
