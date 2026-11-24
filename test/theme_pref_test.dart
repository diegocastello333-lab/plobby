import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/theme/design_tokens.dart';
import 'package:plobby/core/theme/theme_pref.dart';
import 'package:plobby/features/splash/application/splash_boot.dart';
import 'package:plobby/main.dart' show PlobbyApp;
import 'package:shared_preferences/shared_preferences.dart';

/// Oscuro por defecto para TODOS (también cuentas existentes, que no tienen preferencia guardada).
void main() {
  tearDown(() { ThemePrefs.notifier.value = ThemePref.system; AppColors.isDark = false; });

  test('sin preferencia guardada (usuarios existentes) se carga OSCURO', () async {
    SharedPreferences.setMockInitialValues({});
    ThemePrefs.notifier.value = ThemePref.system;
    await ThemePrefs.load();
    expect(ThemePrefs.value, ThemePref.dark);
    expect(ThemePrefs.isDark(false), isTrue, reason: 'aunque el móvil esté en claro');
  });

  test('la elección se guarda y se respeta', () async {
    SharedPreferences.setMockInitialValues({});
    await ThemePrefs.set(ThemePref.light);
    ThemePrefs.notifier.value = ThemePref.dark;
    await ThemePrefs.load();
    expect(ThemePrefs.value, ThemePref.light);
    expect(ThemePrefs.isDark(true), isFalse);
    await ThemePrefs.set(ThemePref.system);
    expect(ThemePrefs.isDark(true), isTrue);
    expect(ThemePrefs.isDark(false), isFalse);
  });

  testWidgets('la app arranca en oscuro con el sistema en claro y cambia al instante al elegir otro tema', (t) async {
    SplashBoot.pending = false;
    ThemePrefs.notifier.value = ThemePref.dark;
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.pumpWidget(const ProviderScope(child: PlobbyApp()));
    for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 200)); }
    expect(AppColors.isDark, isTrue);
    expect(Theme.of(t.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
    ThemePrefs.notifier.value = ThemePref.light;
    for (var i = 0; i < 4; i++) { await t.pump(const Duration(milliseconds: 200)); }
    expect(AppColors.isDark, isFalse);
    expect(t.takeException(), isNull);
  });
}
