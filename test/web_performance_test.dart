import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/async/single_flight.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/widgets/ambient_background.dart';
import 'package:plobby/features/home/domain/banner_schedule.dart';
import 'package:plobby/features/home/presentation/banner_catalog.dart';

/// Optimización de la versión web (16 nov 2026): en reposo la app no debe pintar ningún fotograma.
void main() {
  tearDown(() => IdleMotion.limitLoops = false);

  testWidgets('web: un bucle decorativo se detiene tras unos ciclos y vuelve a su pose de reposo', (t) async {
    IdleMotion.limitLoops = true;
    final c = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 100));
    addTearDown(c.dispose);
    IdleMotion.loop(c, reverse: true, rest: 0);
    await t.pump();
    expect(c.isAnimating, isTrue);
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(c.isAnimating, isFalse, reason: 'tras ${IdleMotion.cycles} ciclos queda quieta: 0 fotogramas en reposo');
    expect(c.value, 0);
  });

  testWidgets('nativo (Android/iOS): el bucle sigue como siempre', (t) async {
    IdleMotion.limitLoops = false;
    final c = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 100));
    addTearDown(c.dispose);
    IdleMotion.loop(c, reverse: true, rest: 0);
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(c.isAnimating, isTrue);
    c.stop();
  });

  testWidgets('web: el fondo vivo no deriva (sin fotogramas en reposo) pero sigue cambiando de color', (t) async {
    IdleMotion.limitLoops = true;
    final prev = AmbientBackground.driftEnabled;
    AmbientBackground.driftEnabled = true;   // aunque la deriva esté permitida, en la web no se activa
    addTearDown(() => AmbientBackground.driftEnabled = prev);
    Widget app(double pos) => MaterialApp(home: AmbientBackground(palettes: const [AmbientPalette.home, AmbientPalette.feed], position: pos));
    await t.pumpWidget(app(0));
    await t.pumpAndSettle();                         // terminaría por tiempo si hubiera una animación infinita
    expect(t.binding.hasScheduledFrame, isFalse);
    await t.pumpWidget(app(1));                      // cambio de pestaña: el color sí se anima…
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();                         // …y termina
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  test('Inicio solo precarga la franja actual; la siguiente, solo si el cambio está cerca (antes, las cuatro)', () {
    expect(bannerPhasesToPrecache(DayPhase.dia, untilNext: const Duration(hours: 3)), [DayPhase.dia]);
    expect(bannerPhasesToPrecache(DayPhase.dia, untilNext: const Duration(minutes: 10)), [DayPhase.dia, DayPhase.atardecer]);
    expect(bannerPhasesToPrecache(DayPhase.noche), [DayPhase.noche, DayPhase.amanecer]);
  });

  test('doble toque: una acción de partido solo se envía una vez mientras la primera está en curso', () async {
    var calls = 0;
    Future<void> action() async { calls++; await Future<void>.delayed(const Duration(milliseconds: 20)); }
    await Future.wait([SingleFlight.run(('match-action', 'm1'), action), SingleFlight.run(('match-action', 'm1'), action)]);
    expect(calls, 1);
    await SingleFlight.run(('match-action', 'm1'), action);   // terminada la primera, se puede volver a ejecutar
    expect(calls, 2);
    await Future.wait([SingleFlight.run(('match-action', 'm1'), action), SingleFlight.run(('match-action', 'm2'), action)]);
    expect(calls, 4, reason: 'partidos distintos no se bloquean entre sí');
  });
}
