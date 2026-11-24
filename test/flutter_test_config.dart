import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/router/app_router.dart' show deferredScreenLoaders;
import 'package:plobby/core/router/deferred_screen.dart';
import 'package:plobby/core/widgets/ambient_background.dart';
import 'package:plobby/core/theme/theme_pref.dart';

/// Carga Inter y Unbounded (las mismas fuentes empaquetadas que usa la app) antes de cada archivo de test.
/// Sin esto los tests pintan con la fuente «FlutterTest», donde cada letra es un cuadrado más ancho que Inter, y los
/// desbordamientos que detectan no se corresponden con los del dispositivo.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // El fondo vivo deriva en bucle infinito; en los tests se queda quieto para que `pumpAndSettle` termine.
  AmbientBackground.driftEnabled = false;
  // La app arranca en oscuro por defecto; los tests siguen al «sistema» (claro salvo que el test pida oscuro).
  ThemePrefs.notifier.value = ThemePref.system;
  const families = {
    'Inter': ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'],
    'Unbounded': ['SemiBold', 'Bold'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final w in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/${e.key}-$w.ttf'));
    }
    await loader.load();
  }
  // Pantallas en carga diferida: registradas antes de cada archivo, como hace la app en Android/iOS.
  await DeferredScreen.preload(deferredScreenLoaders);
  await testMain();
}
