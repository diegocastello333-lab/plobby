import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/celebration.dart';
import 'package:plobby/core/widgets/plobby_icon.dart';
import 'package:plobby/features/feed/application/feed_providers.dart';
import 'package:plobby/features/feed/domain/feed_models.dart';
import 'package:plobby/features/feed/presentation/widgets/reaction_bar.dart';
import 'package:plobby/features/gamification/domain/gamification_models.dart';
import 'package:plobby/features/gamification/presentation/gamification_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GP2 · Animaciones por pantalla: decoran el estado (no lo sustituyen), se ven una vez por evento y respetan
/// «reducir movimiento».
Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }   // timing

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppHaptics.log.clear();
    AppearRegistry.reset();
  });

  test('confeti: dibujado en código, determinista y vacío fuera de la ráfaga', () {
    for (final t in [0.0, .3, .8, 1.0]) {
      ConfettiPainter(t).paint(Canvas(ui.PictureRecorder()), const Size(390, 844));   // no lanza
    }
    expect(ConfettiPainter(.5).shouldRepaint(ConfettiPainter(.5)), isFalse);
    expect(ConfettiPainter(.5).shouldRepaint(ConfettiPainter(.6)), isTrue);
  });

  test('cada celebración se muestra UNA vez por evento', () async {
    expect(await CelebrationLog.claim('level:3'), isTrue);
    expect(await CelebrationLog.claim('level:3'), isFalse);
    expect(await CelebrationLog.claim('level:4'), isTrue);
  });

  testWidgets('celebración: se cierra sola y vibra una vez', (t) async {
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => TextButton(
        onPressed: () => showCelebration(c, const Celebration(eventKey: 'level:5', title: '¡Nivel 5!', text: 'Has subido al nivel 5.')),
        child: const Text('abrir')))));
    await t.tap(find.text('abrir'));
    await t.pump(); await t.pump(); await t.pump(const Duration(milliseconds: 300));   // timing
    expect(find.text('¡Nivel 5!'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ConfettiPainter), findsOneWidget);
    expect(AppHaptics.log, ['success']);
    await _settle(t, 12);
    expect(find.text('¡Nivel 5!'), findsNothing);
    // otra vez el mismo evento: nada
    await t.tap(find.text('abrir'));
    await _settle(t, 2);
    expect(find.text('¡Nivel 5!'), findsNothing);
    expect(AppHaptics.log, ['success']);
  });

  testWidgets('insignia: bloqueada con candado (no solo color) y destello una sola vez al conseguirla', (t) async {
    const locked = AchievementItem(id: 'a', category: 'wins', title: 'X', description: 'Y', icon: 'trophy', goal: 10, xp: 50, progress: 4);
    final got = AchievementItem(id: 'b', category: 'wins', title: 'X', description: 'Y', icon: 'trophy', goal: 1, xp: 50, unlockedAt: DateTime(2026));
    await t.pumpWidget(MaterialApp(home: Row(children: [const AchievementBadge(locked), AchievementBadge(got)])));
    expect(find.byWidgetPredicate((w) => w is PlobbyIcon && w.icon == PlobbyIcons.lock), findsOneWidget);
    await t.pump(const Duration(milliseconds: 300));   // timing
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_Shine'), findsOneWidget);
    await _settle(t, 6);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_Shine'), findsNothing);
    // volver a montarla en la misma sesión: sin destello
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(MaterialApp(home: AchievementBadge(got)));
    await t.pump(const Duration(milliseconds: 300));   // timing
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_Shine'), findsNothing);
  });

  testWidgets('contador que rueda: muestra el valor nuevo', (t) async {
    Widget host(int v) => MaterialApp(home: Center(child: RollingCount(value: v, style: const TextStyle(fontSize: 12))));
    await t.pumpWidget(host(3));
    await t.pumpWidget(host(4));
    await _settle(t, 2);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('feed: doble toque = 🔥 (solo añade; un segundo doble toque no la quita)', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late WidgetRef ref;
    await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, r, __) { ref = r; return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r.watch(routerProvider)); })));
    await _settle(t, 4);
    await t.tap(find.bySemanticsLabel('Feed').last);
    await _settle(t, 8);
    final area = find.byType(DoubleTapFire).first;
    final post = t.widget<DoubleTapFire>(area).post;
    Future<void> doubleTap() async {
      final c = t.getCenter(area);
      await t.tapAt(c); await t.pump(const Duration(milliseconds: 60)); await t.tapAt(c);   // timing
      await _settle(t, 4);
    }
    FeedPost now() => ref.read(feedControllerProvider).value!.posts.firstWhere((p) => p.id == post.id);
    await doubleTap();
    expect(now().reactions.mine, ReactionType.fire);
    final count = now().reactions.counts[ReactionType.fire];
    await doubleTap();
    expect(now().reactions.mine, ReactionType.fire);
    expect(now().reactions.counts[ReactionType.fire], count);
  });
}
