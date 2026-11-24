import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/theme/design_tokens.dart';
import 'package:plobby/features/splash/application/splash_boot.dart';
import 'package:plobby/main.dart' show PlobbyApp;

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// Contraste WCAG entre dos colores opacos.
double contrast(Color a, Color b) { final la = _lum(a), lb = _lum(b); final hi = la > lb ? la : lb, lo = la > lb ? lb : la; return (hi + 0.05) / (lo + 0.05); }

void main() {
  tearDown(() => AppColors.isDark = false);

  test('modo oscuro: los pares de texto principales cumplen AA (4,5:1)', () {
    AppColors.isDark = true;
    for (final (name, fg, bg) in [
      ('texto / fondo', AppColors.text, AppColors.bg), ('texto / superficie', AppColors.text, AppColors.surface),
      ('secundario / fondo', AppColors.textMuted, AppColors.bg), ('secundario / superficie', AppColors.textMuted, AppColors.surface),
      ('marfil / bloque destacado', AppColors.ink50, AppColors.inverse), ('lima / bloque destacado', AppColors.lime300, AppColors.inverse),
      ('tinta / lima', AppColors.brandInk, AppColors.brand),
    ]) {
      expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
    }
  });

  test('los colores semánticos cambian con el modo; las primitivas y el lima, no', () {
    final light = (AppColors.bg, AppColors.text, AppColors.surface);
    AppColors.isDark = true;
    expect((AppColors.bg, AppColors.text, AppColors.surface), isNot(light));
    expect(AppColors.brand, AppColors.lime300);
    // Las imágenes para compartir se pintan siempre en claro.
    expect(AppColors.light(() => AppColors.bg), AppColors.ink50);
    expect(AppColors.isDark, isTrue);
  });

  testWidgets('la app sigue el modo del sistema y se reconstruye al cambiarlo', (t) async {
    SplashBoot.pending = false;
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.pumpWidget(const ProviderScope(child: PlobbyApp()));
    for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 200)); }
    expect(AppColors.isDark, isTrue);
    expect(Theme.of(t.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
    expect(t.takeException(), isNull);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    for (var i = 0; i < 4; i++) { await t.pump(const Duration(milliseconds: 200)); }
    expect(AppColors.isDark, isFalse);
    expect(Theme.of(t.element(find.byType(Scaffold).first)).brightness, Brightness.light);
  });

  testWidgets('pantallas principales en oscuro sin errores de dibujo', (t) async {
    SplashBoot.pending = false;
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.pumpWidget(const ProviderScope(child: PlobbyApp()));
    for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 200)); }
    for (final tab in ['Feed', 'Competiciones', 'Perfil', 'Inicio']) {
      await t.tap(find.bySemanticsLabel(tab).last);
      for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 200)); }
      expect(t.takeException(), isNull, reason: tab);
    }
  });
}
