import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Web: los emojis (reacciones 🔥 ❤️ 👏 💪 😂, logros, chat) y símbolos (✓ ← →) no están en Inter/Unbounded. Flutter Web
/// descarga fuentes Noto de respaldo; por defecto desde fonts.gstatic.com, que la CSP (font-src/connect-src 'self')
/// bloquea → «no glyph». Se sirven desde la propia web: web/fonts/fallback + fontFallbackBaseUrl en flutter_bootstrap.js.
/// Si se actualiza Flutter y cambian los nombres de fichero, este test lo detecta.
void main() {
  test('flutter_bootstrap.js usa las fuentes de respaldo propias', () {
    expect(File('web/flutter_bootstrap.js').readAsStringSync(), contains("fontFallbackBaseUrl: '/fonts/fallback/'"));
  });

  test('están todos los ficheros de emoji y símbolos que pide esta versión de Flutter', () {
    final root = Platform.environment['FLUTTER_ROOT'];
    final data = File('$root/bin/cache/flutter_web_sdk/lib/_engine/engine/font_fallback_data.dart');
    if (root == null || !data.existsSync()) {
      markTestSkipped('No se encuentra el SDK web de Flutter');
      return;
    }
    final wanted = RegExp(r"'(noto(?:coloremoji|sanssymbols2?|sansmath)/[^']+\.woff2)'")
        .allMatches(data.readAsStringSync()).map((m) => m.group(1)!).toSet();
    expect(wanted, isNotEmpty);
    final missing = wanted.where((f) => !File('web/fonts/fallback/$f').existsSync()).toList();
    expect(missing, isEmpty, reason: 'Descarga de https://fonts.gstatic.com/s/<fichero> a web/fonts/fallback/: ${missing.join(', ')}');
  });

  test('la CSP sigue sin permitir fuentes de terceros', () {
    final v = File('vercel.json').readAsStringSync();
    expect(v, contains("font-src 'self' data:"));
    expect(v, isNot(contains('fonts.gstatic.com')));
  });
}
