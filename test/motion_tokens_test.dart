import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fase 0 (movimiento premium): todas las duraciones, curvas y vibraciones salen de `core/motion/app_motion.dart`.
/// Estas guardias fallan si alguien vuelve a escribir valores sueltos en la interfaz.

/// Ficheros de interfaz (presentación y widgets comunes). Datos, dominio y red quedan fuera: sus `Duration` son plazos.
List<File> _uiFiles() => Directory('lib').listSync(recursive: true).whereType<File>().where((f) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.dart')) return false;
      const skip = ['/data/', '/domain/', '/application/', 'core/net/', 'core/supabase/', 'core/motion/', 'core/share/',
        'core/config/', 'core/errors/'];
      return !skip.any(p.contains);
    }).toList();

List<String> _offending(RegExp pattern, {bool allowTimingComment = false}) {
  final out = <String>[];
  for (final f in _uiFiles()) {
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.trimLeft().startsWith('//')) continue;
      if (!pattern.hasMatch(l)) continue;
      if (allowTimingComment && l.contains('// timing')) continue;
      out.add('${f.path}:${i + 1}: ${l.trim()}');
    }
  }
  return out;
}

void main() {
  test('sin duraciones sueltas en la interfaz (usar Motion.* o marcar «// timing» si es un plazo)', () {
    expect(_offending(RegExp(r'\bDuration\((?!days:)'), allowTimingComment: true), isEmpty);
  });

  test('sin curvas sueltas en la interfaz (usar Motion.enter/exit/move/spring…)', () {
    expect(_offending(RegExp(r'\bCurves\.')), isEmpty);
  });

  test('nadie llama a HapticFeedback fuera de AppHaptics', () {
    final all = Directory('lib').listSync(recursive: true).whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.replaceAll('\\', '/').endsWith('core/motion/app_motion.dart'))
        .expand((f) => f.readAsLinesSync().asMap().entries
            .where((e) => e.value.contains('HapticFeedback.'))
            .map((e) => '${f.path}:${e.key + 1}'))
        .toList();
    expect(all, isEmpty);
  });

  test('tokens: escala de duraciones ordenada y «reducir movimiento» las anula', () {
    expect(Motion.fast < Motion.normal && Motion.normal < Motion.emphasis && Motion.emphasis < Motion.celebration, isTrue);
    expect(Motion.celebrationLong.inMilliseconds, lessThanOrEqualTo(1200));
  });

  testWidgets('Motion.reduced lee disableAnimations del sistema', (t) async {
    late bool reduced, normal;
    late Duration d;
    await t.pumpWidget(MediaQuery(data: const MediaQueryData(disableAnimations: true), child: Builder(builder: (c) {
      reduced = Motion.reduced(c);
      d = Motion.of(c, Motion.emphasis);
      return const SizedBox();
    })));
    await t.pumpWidget(MediaQuery(data: const MediaQueryData(), child: Builder(builder: (c) {
      normal = Motion.reduced(c);
      return const SizedBox();
    })));
    expect(reduced, isTrue);
    expect(d, Duration.zero);
    expect(normal, isFalse);
  });

  group('vibración', () {
    final calls = <String>[];
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppHaptics.log.clear();
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (m) async {
        if (m.method == 'HapticFeedback.vibrate') calls.add('${m.arguments}');
        return null;
      });
    });
    tearDown(() async {
      await AppHaptics.setEnabled(true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('una vibración por evento y nunca fuerte en errores', () async {
      await AppHaptics.setEnabled(true);
      AppHaptics.light();
      AppHaptics.medium();
      AppHaptics.success();
      AppHaptics.error();
      expect(AppHaptics.log, ['light', 'medium', 'success', 'error']);
      expect(calls.length, 4);
      expect(calls.last, 'HapticFeedbackType.selectionClick');
      expect(calls, isNot(contains('HapticFeedbackType.heavyImpact')));
    });

    test('el interruptor de Ajustes la desactiva y se recuerda al arrancar', () async {
      await AppHaptics.setEnabled(false);
      AppHaptics.success();
      AppHaptics.light();
      expect(calls, isEmpty);
      AppHaptics.enabled = true;     // simula un arranque nuevo…
      await AppHaptics.load();       // …que lee la preferencia guardada
      expect(AppHaptics.enabled, isFalse);
      await AppHaptics.setEnabled(true);
      AppHaptics.light();
      expect(calls.length, 1);
    });
  });
}
