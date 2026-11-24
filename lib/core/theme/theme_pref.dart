import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apariencia elegida por el usuario. Por defecto OSCURO para todos (decisión del 24 nov 2026), también para quien ya
/// tenía cuenta: la preferencia se guarda en el dispositivo y nadie la tenía guardada, así que todos empiezan en oscuro.
/// Se puede cambiar en Perfil → Ajustes y privacidad → Apariencia.
enum ThemePref { dark, light, system }

class ThemePrefs {
  ThemePrefs._();
  static const _key = 'plobby.theme';
  static const fallback = ThemePref.dark;
  /// Valor vigente; `PlobbyApp` lo escucha y se redibuja al cambiarlo.
  static final notifier = ValueNotifier<ThemePref>(fallback);
  static ThemePref get value => notifier.value;

  static Future<void> load() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(_key);
      notifier.value = ThemePref.values.firstWhere((p) => p.name == s, orElse: () => fallback);
    } catch (_) {}
  }

  static Future<void> set(ThemePref p) async {
    notifier.value = p;
    try { await (await SharedPreferences.getInstance()).setString(_key, p.name); } catch (_) {}
  }

  /// ¿Oscuro? con la preferencia y el modo del sistema.
  static bool isDark(bool systemDark) => switch (value) { ThemePref.dark => true, ThemePref.light => false, ThemePref.system => systemDark };
}
