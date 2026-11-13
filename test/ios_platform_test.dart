import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/feed/presentation/notifications_screen.dart';
import 'package:plobby/features/home/presentation/home_screen.dart';

/// iPhone 15 Pro: 393×852 pt, @3x, Dynamic Island (59 pt arriba) e indicador de inicio (34 pt abajo).
Future<GoRouter> _iphone(WidgetTester t, {double width = 393, double height = 852}) async {
  t.view.physicalSize = Size(width * 3, height * 3);
  t.view.devicePixelRatio = 3;
  t.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  t.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);
  late GoRouter r;
  await t.pumpWidget(ProviderScope(child: Consumer(builder: (_, ref, __) {
    r = ref.watch(routerProvider);
    return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r);
  })));
  for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 250)); }
  return r;
}

Future<void> _settle(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

void main() {
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  test('iOS usa la transición nativa (con gesto de volver); Android conserva la de Plobby', () {
    expect(AppTransitions.theme.builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
    expect(AppTransitions.theme.builders[TargetPlatform.android], isA<AppPageTransitionsBuilder>());
  });

  testWidgets('en iPhone, deslizar desde el borde izquierdo vuelve a la pantalla anterior', (t) async {
    final r = await _iphone(t);
    expect(find.byType(HomeScreen), findsOneWidget);
    r.push('/notifications');
    await _settle(t);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    // Gesto de borde (como el pulgar en un iPhone).
    final g = await t.startGesture(const Offset(4, 420));
    for (var i = 0; i < 12; i++) { await g.moveBy(const Offset(28, 0)); await t.pump(const Duration(milliseconds: 16)); }
    await g.up();
    await _settle(t);
    expect(find.byType(NotificationsScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  }, variant: ios);

  for (final (name, w, h) in [('iPhone 15 Pro', 393.0, 852.0), ('iPhone SE', 375.0, 667.0), ('iPhone 15 Pro Max', 430.0, 932.0)]) {
    testWidgets('$name: pantallas principales sin desbordes y la barra inferior respeta el indicador de inicio', (t) async {
      final r = await _iphone(t, width: w, height: h);
      for (final route in ['/home', '/feed', '/leagues', '/profile', '/messages', '/friends', '/rating', '/notifications']) {
        r.go(route);
        await _settle(t);
        expect(t.takeException(), isNull, reason: route);
      }
      r.go('/home');
      await _settle(t);
      // Ningún destino de la barra inferior queda dentro de la zona del indicador de inicio (últimos 34 pt).
      final home = t.getRect(find.text('Inicio').last);
      expect(home.bottom, lessThanOrEqualTo(h - 34 + 0.5));
    }, variant: ios);
  }

  testWidgets('en iPhone y Android todo el texto usa las fuentes de Plobby (Inter / Unbounded), nunca la del sistema', (t) async {
    final r = await _iphone(t);
    final bad = <String>{};
    void scan(String route) {
      for (final rt in t.widgetList<RichText>(find.byType(RichText))) {
        void visit(InlineSpan span, String? family) {
          final f = span.style?.fontFamily ?? family;
          if (span is TextSpan) {
            final txt = (span.text ?? '').trim();
            if (txt.isNotEmpty && f != 'Inter' && f != 'Unbounded' && f != 'MaterialIcons') bad.add('$route: «$txt» ($f)');
            for (final c in span.children ?? const <InlineSpan>[]) { visit(c, f); }
          }
        }
        visit(rt.text, null);
      }
    }
    for (final route in ['/home', '/feed', '/leagues', '/profile', '/messages', '/friends', '/rating', '/notifications', '/tournaments/new']) {
      r.go(route);
      await _settle(t);
      scan(route);
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
}
