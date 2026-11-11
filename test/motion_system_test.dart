import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/widgets/motion_widgets.dart';

Widget host(Widget w, {bool reduce = false}) => MaterialApp(
    home: MediaQuery(data: MediaQueryData(disableAnimations: reduce), child: Scaffold(body: Center(child: w))));

void main() {
  setUp(AppearRegistry.reset);

  test('retraso escalonado con tope y valores dentro de rango', () {
    expect(AppAnimations.staggerDelay(0), Duration.zero);
    expect(AppAnimations.staggerDelay(2), const Duration(milliseconds: 80));
    expect(AppAnimations.staggerDelay(99), AppAnimations.appearMaxDelay);
    expect(AppAnimations.pressScale, closeTo(.97, 1e-9));
    expect(AppAnimations.appear.inMilliseconds, inInclusiveRange(200, 300));
    expect(AppAnimations.press.inMilliseconds, inInclusiveRange(100, 180));
    expect(AppAnimations.appearOffset, inInclusiveRange(8, 12));
  });

  test('registro de aparición: una sola vez por clave', () {
    expect(AppearRegistry.hasSeen('a'), isFalse);
    AppearRegistry.markSeen('a');
    expect(AppearRegistry.hasSeen('a'), isTrue);
  });

  testWidgets('AppearOnce anima la primera vez y NO la repite al volver a montar', (t) async {
    await t.pumpWidget(host(const AppearOnce(animationKey: 'k1', child: Text('x'))));
    expect(t.widget<Opacity>(find.byType(Opacity).first).opacity, lessThan(1));
    await t.pumpAndSettle();
    expect(t.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(const AppearOnce(animationKey: 'k1', child: Text('x'))));
    expect(t.widget<Opacity>(find.byType(Opacity).first).opacity, 1); // ya vista: sin animación
  });

  testWidgets('reducir movimiento: la tarjeta aparece sin animación', (t) async {
    await t.pumpWidget(host(const AppearOnce(animationKey: 'k2', child: Text('x')), reduce: true));
    await t.pump();
    expect(t.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
  });

  testWidgets('SectionHeader: título y acción comparten eje vertical y altura 44', (t) async {
    await t.pumpWidget(host(SizedBox(width: 358, child: SectionHeader(title: 'Últimas partidas de amigos', actionLabel: 'Ver todos', onAction: () {}))));
    final title = t.getCenter(find.text('Últimas partidas de amigos')).dy;
    final link = t.getCenter(find.text('Ver todos')).dy;
    expect((title - link).abs(), lessThan(1.0));
    expect(t.getSize(find.byType(SectionHeader)).height, AppLayout.headerHeight);
    expect(t.getSize(find.byType(SectionLink)).height, greaterThanOrEqualTo(AppLayout.minTap));
  });

  testWidgets('SectionHeader no desborda con título largo y pantalla estrecha', (t) async {
    await t.pumpWidget(host(SizedBox(width: 280, child: SectionHeader(title: 'Últimas partidas de amigos con título larguísimo', actionLabel: 'Ver todos', onAction: () {}))));
    expect(t.takeException(), isNull);
    expect(find.text('Ver todos'), findsOneWidget);
  });

  testWidgets('SectionLink conserva su acción (onTap)', (t) async {
    var n = 0;
    await t.pumpWidget(host(SectionLink(label: 'Ver todos', onTap: () => n++)));
    await t.tap(find.text('Ver todos'));
    expect(n, 1);
  });

  testWidgets('CountUpText: sin animate muestra el valor real; con animate termina en el valor real', (t) async {
    await t.pumpWidget(host(const CountUpText(from: 1400, to: 1482)));
    expect(find.text('1482'), findsOneWidget);
    await t.pumpWidget(host(const CountUpText(from: 1400, to: 1482, animate: true)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('1482'), findsNothing); // valor intermedio
    await t.pumpAndSettle();
    expect(find.text('1482'), findsOneWidget);
  });

  testWidgets('DeltaChip muestra signo correcto', (t) async {
    await t.pumpWidget(host(const DeltaChip(delta: 18)));
    expect(find.text('+18'), findsOneWidget);
    await t.pumpWidget(host(const DeltaChip(delta: -12)));
    expect(find.text('-12'), findsOneWidget);
  });

  testWidgets('SlidingTabs cambia de pestaña vía onChanged', (t) async {
    var i = 0;
    await t.pumpWidget(host(StatefulBuilder(builder: (c, set) => SizedBox(width: 300, child: SlidingTabs(labels: const ['A', 'B', 'C'], index: i, onChanged: (v) => set(() => i = v))))));
    await t.tap(find.text('C'));
    await t.pumpAndSettle();
    expect(i, 2);
  });

  testWidgets('Skeleton respeta altura final y se detiene con reducir movimiento', (t) async {
    await t.pumpWidget(host(const SizedBox(width: 300, child: MatchCardSkeleton()), reduce: true));
    expect(t.getSize(find.byType(MatchCardSkeleton)).height, MatchCardSkeleton.height);
    await t.pumpAndSettle(); // no hay animación infinita
  });

  testWidgets('BellBadge oculta el contador a 0 y no anima de forma continua', (t) async {
    await t.pumpWidget(host(const BellBadge(count: 0, icon: Icon(Icons.notifications))));
    await t.pumpAndSettle();
    await t.pumpWidget(host(const BellBadge(count: 3, icon: Icon(Icons.notifications))));
    await t.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
  });
}
