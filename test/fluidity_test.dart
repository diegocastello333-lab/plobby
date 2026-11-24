import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/theme/design_tokens.dart';

/// Decisiones de fluidez (24 nov 2026, ver docs/rendimiento/fluidez.md). Si alguna cambia, que sea a propósito.
void main() {
  test('las barras no desenfocan en vivo por defecto (BackdropFilter recalculado en cada fotograma de scroll)', () {
    expect(AppMaterials.blur, isFalse);
    final direct = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('frosted_bar.dart')) continue;
      if (f.readAsStringSync().contains('BackdropFilter(')) direct.add(f.path);
    }
    expect(direct, isEmpty, reason: 'usa FrostedBar');
  });

  test('los bucles decorativos se limitan también en el móvil', () {
    // El valor por defecto (antes kIsWeb). Los tests pueden cambiarlo; aquí se lee el código fuente.
    expect(File('lib/core/motion/app_motion.dart').readAsStringSync(), contains('static bool limitLoops = true;'));
    expect(IdleMotion.cycles, lessThanOrEqualTo(3));
  });

  test('la web no fuerza el árbol de accesibilidad: se activa bajo demanda', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, isNot(contains('ensureSemantics')));
    expect(main, contains('installWebA11yToggle()'));
    expect(File('lib/core/a11y/web_a11y_web.dart').readAsStringSync(), contains('Activar lector de pantalla'));
  });

  test('la web está aislada (COOP + COEP credentialless): el motor pinta fuera del hilo principal', () {
    final d = jsonDecode(File('vercel.json').readAsStringSync()) as Map<String, dynamic>;
    final all = [for (final h in d['headers'] as List) if (h['source'] == '/(.*)') ...(h['headers'] as List)];
    String? v(String k) => all.cast<Map>().where((e) => e['key'] == k).map((e) => e['value'] as String).firstOrNull;
    expect(v('Cross-Origin-Opener-Policy'), 'same-origin');
    expect(v('Cross-Origin-Embedder-Policy'), 'credentialless');
  });

  test('las cabeceras fijas (Feed, Perfil, Liga) devuelven la misma instancia en cada fotograma', () {
    for (final f in ['lib/features/feed/presentation/feed_screen.dart', 'lib/features/profile/presentation/profile_screen.dart',
        'lib/features/leagues/presentation/league_detail_screen.dart']) {
      expect(File(f).readAsStringSync(), matches(RegExp(r'late final Widget _(w|list) = RepaintBoundary')), reason: f);
    }
  });
}
