import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/design_tokens.dart';
import 'package:plobby/features/splash/application/splash_boot.dart';
import 'package:plobby/main.dart' show PlobbyApp;

/// Auditoría de contraste en MODO OSCURO: renderiza las pantallas principales, recorre cada texto e icono y compara su
/// color con el fondo REAL que tiene debajo (cajas de color, Material, tarjetas; se componen las capas translúcidas).
/// Mínimos WCAG AA: 4,5:1 texto normal, 3:1 texto grande (≥18 pt o ≥14 pt negrita) e iconos.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}
double contrast(Color a, Color b) { final x = _lum(a), y = _lum(b); return (math.max(x, y) + .05) / (math.min(x, y) + .05); }
Color _over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

Color? _fill(RenderObject r) {
  if (r is RenderDecoratedBox) { final d = r.decoration; if (d is BoxDecoration && d.color != null && d.gradient == null && d.image == null) return d.color; if (d is ShapeDecoration && d.color != null) return d.color; }
  if (r is RenderPhysicalModel) return r.color;
  if (r is RenderPhysicalShape) return r.color;
  if (r.runtimeType.toString() == '_RenderColoredBox') return (r as dynamic).color as Color;
  return null;
}

/// Fondo bajo [r]: capas de color de los ancestros compuestas hasta una opaca (o el fondo de la app).
Color? backgroundOf(RenderObject r) {
  final layers = <Color>[];
  RenderObject? p = r.parent;
  while (p != null) {
    if (p is RenderOffstage && p.offstage) return null;          // no visible
    if (p is RenderOpacity && p.opacity < .5) return null;
    if (p is RenderAnimatedOpacity && p.opacity.value < .5) return null;
    if (p is RenderDecoratedBox && p.decoration is BoxDecoration && ((p.decoration as BoxDecoration).gradient != null || (p.decoration as BoxDecoration).image != null)) return null; // degradado/imagen: no medible
    if (p.runtimeType.toString().contains('Image')) return null;
    final c = _fill(p);
    if (c != null && c.a > 0) { layers.add(c); if (c.a >= .99) break; }
    p = p.parent;
  }
  var bg = AppColors.bg;
  for (final c in layers.reversed) { bg = _over(c, bg); }
  return bg;
}

class Finding { Finding(this.route, this.text, this.fg, this.bg, this.ratio, this.min); final String route, text; final Color fg, bg; final double ratio, min;
  @override String toString() => '$route · «$text» ${fg.toARGB32().toRadixString(16)} sobre ${bg.toARGB32().toRadixString(16)} = ${ratio.toStringAsFixed(2)} (mín ${min.toStringAsFixed(1)})'; }

List<Finding> audit(WidgetTester t, String route) {
  final out = <Finding>[];
  void visit(RenderObject r) {
    if (r is RenderParagraph && r.hasSize && r.size.width > 1) {
      final bg = backgroundOf(r);
      if (bg != null) {
        r.text.visitChildren((span) {
          if (span is TextSpan && (span.text ?? '').trim().isNotEmpty) {
            final st = span.style;
            final fg = st?.color ?? (r.text.style?.color);
            // Tinta de marca (brandInk) solo se usa sobre lima (regla del sistema de diseño, ver dark_mode_test): las píldoras
            // lima de pestañas y la llama van en una capa hermana, no antecesora, y este detector no las ve.
            if (fg != null && fg.a > .05 && fg != AppColors.brandInk) {
              final size = st?.fontSize ?? r.text.style?.fontSize ?? 14, w = st?.fontWeight ?? r.text.style?.fontWeight ?? FontWeight.w400;
              final large = size >= 18 || (size >= 14 && w.value >= 700);
              final ratio = contrast(_over(fg, bg), bg), min = large ? 3.0 : 4.5;
              if (ratio < min) out.add(Finding(route, span.text!.trim().replaceAll('\n', ' '), fg, bg, ratio, min));
            }
          }
          return true;
        });
      }
    }
    r.visitChildren(visit);
  }
  visit(t.binding.renderViews.first);
  return out;
}

void main() {
  testWidgets('auditoría de contraste en modo oscuro', (t) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SplashBoot.pending = false;
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: const PlobbyApp()));
    for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 200)); }
    final routes = ['/home', '/feed', '/leagues', '/profile', '/match/new?type=friendly', '/messages', '/notifications', '/friends',
      '/rating', '/leagues/bunker', '/settings/privacy', '/achievements', '/ranking', '/profile/share',
      '/profile/edit', '/friends/add', '/leagues/new', '/leagues/discover', '/leagues/bunker/manage', '/tournaments/new', '/h2h/marcos',
      '/player/marcos', '/messages/c_marcos?name=Marcos', '/messages/group/new', '/wrapped', '/match/new?type=league'];
    final all = <Finding>[];
    for (final r in routes) {
      container.read(routerProvider).go(r);
      for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 200)); }
      all.addAll(audit(t, r));
    }
    // Hoja «+» (crear partido amistoso / de liga)
    container.read(routerProvider).go('/home');
    for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 200)); }
    await t.tap(find.bySemanticsLabel('Nuevo partido').last);
    for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 200)); }
    all.addAll(audit(t, 'hoja +'));
    final seen = <String>{};
    final uniq = [for (final f in all) if (seen.add('${f.route}|${f.text}')) f];
    // ignore: avoid_print
    for (final f in uniq) { print('CONTRASTE $f'); }
    expect(uniq, isEmpty, reason: '${uniq.length} textos con poco contraste en oscuro');
  });
}
