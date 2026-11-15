import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/tournaments/application/tournament_providers.dart';

/// Auditoría Apple Design convertida en pruebas permanentes:
/// - HIG › Typography / Accessibility: el texto escala con el sistema (Dynamic Type) y las pantallas no se rompen,
///   también en el iPhone más estrecho (320 pt).
/// - Tamaño mínimo de texto: 11 pt.
/// - Los muelles de movimiento terminan exactamente en su destino.
Future<void> _settle(WidgetTester t, [int n = 10]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

const _routes = ['/home', '/feed', '/leagues', '/profile', '/notifications', '/friends', '/friends/add', '/messages', '/match/new', '/rating',
  '/leagues/bunker', '/leagues/discover', '/leagues/new', '/tournaments/new', '/player/laura', '/profile/edit', '/h2h/laura', '/ranking',
  '/achievements', '/wrapped', '/profile/share', 'torneo'];

void main() {
  for (final (scale, width) in [(1.0, 320.0), (1.35, 390.0), (2.0, 390.0), (2.0, 320.0)]) {
    testWidgets('22 pantallas sin desbordes con texto al ${(scale * 100).round()} % y ${width.toInt()} pt de ancho', (t) async {
      t.view.physicalSize = Size(width * 2, 844 * 2); t.view.devicePixelRatio = 2; addTearDown(t.view.reset);
      final problems = <String>[];
      var cur = '';
      final old = FlutterError.onError;
      FlutterError.onError = (d) => problems.add('${cur.isEmpty ? 'arranque' : cur}: ${d.exceptionAsString().split('\n').first} '
          '(${RegExp(r'lib/[^:]+:\d+').firstMatch(d.toString())?.group(0) ?? '?'})');
      late GoRouter r; late ProviderContainer c;
      await t.pumpWidget(ProviderScope(child: Consumer(builder: (ctx, ref, __) {
        r = ref.watch(routerProvider); c = ProviderScope.containerOf(ctx);
        return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r,
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!));
      })));
      await _settle(t);
      for (var route in _routes) {
        if (route == 'torneo') route = '/tournaments/${(await c.read(myTournamentsProvider.future)).first.id}';
        cur = route;
        r.go(route);
        await _settle(t);
      }
      FlutterError.onError = old;   // restaurar ANTES de expect (si no, el framework de tests se bloquea)
      expect(problems, isEmpty, reason: problems.toSet().join('\n'));
    });
  }

  test('ningún texto de la interfaz por debajo de 11 pt (HIG: mínimo 11 pt en iOS)', () {
    final small = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)\b');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.contains('painter') || f.path.contains('gamification_share')) continue;   // imágenes compartidas: píxeles de imagen
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in small.allMatches(lines[i])) {
          if (double.parse(m.group(1)!) < 11) bad.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('los muelles empiezan en 0, terminan en 1 y solo «bouncy» rebota de forma visible', () {
    for (final s in [AppSprings.smooth, AppSprings.snappy, AppSprings.bouncy]) {
      expect(s.transform(0), 0);
      expect(s.transform(1), 1);
    }
    double peak(SpringCurve c) => [for (var i = 0; i <= 100; i++) c.transform(i / 100)].reduce((a, b) => a > b ? a : b);
    expect(peak(AppSprings.smooth), lessThan(1.01));
    expect(peak(AppSprings.snappy), lessThan(1.04));
    expect(peak(AppSprings.bouncy), greaterThan(1.04));
    expect(peak(AppSprings.bouncy), lessThan(1.2));
  });
}
