import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga Inter y Unbounded (las mismas fuentes empaquetadas que usa la app) antes de cada archivo de test.
/// Sin esto los tests pintan con la fuente «FlutterTest», donde cada letra es un cuadrado más ancho que Inter, y los
/// desbordamientos que detectan no se corresponden con los del dispositivo.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const families = {
    'Inter': ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'],
    'Unbounded': ['Medium', 'SemiBold', 'Bold'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final w in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/${e.key}-$w.ttf'));
    }
    await loader.load();
  }
  await testMain();
}
