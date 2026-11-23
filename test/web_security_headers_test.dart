import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Seguridad Fase 6: cabeceras de la web (vercel.json) y página sin scripts en línea (la CSP los prohíbe).
void main() {
  final cfg = jsonDecode(File('vercel.json').readAsStringSync()) as Map<String, dynamic>;
  final global = {for (final h in ((cfg['headers'] as List).first as Map)['headers'] as List) (h as Map)['key'] as String: h['value'] as String};

  test('cabeceras de seguridad presentes', () {
    for (final k in ['Content-Security-Policy', 'Strict-Transport-Security', 'X-Frame-Options', 'X-Content-Type-Options', 'Referrer-Policy', 'Permissions-Policy']) {
      expect(global.containsKey(k), isTrue, reason: k);
    }
    expect(global['X-Content-Type-Options'], 'nosniff');
    expect(global['X-Frame-Options'], 'DENY');
    expect(global['Strict-Transport-Security'], contains('max-age=63072000'));
  });

  test('CSP estricta: sin eval ni scripts en línea, sin marcos, Supabase como único destino externo', () {
    final csp = global['Content-Security-Policy']!;
    final script = RegExp(r"script-src ([^;]+)").firstMatch(csp)!.group(1)!;
    expect(script, isNot(contains("'unsafe-inline'")));
    expect(script, isNot(contains("'unsafe-eval'")));
    expect(csp, contains("frame-ancestors 'none'"));
    expect(csp, contains("object-src 'none'"));
    final hosts = RegExp(r'(?:https|wss)://[^\s;]+').allMatches(csp).map((m) => Uri.parse(m.group(0)!).host).toSet();
    expect(hosts, {'niwognkvoifrvlizcdvb.supabase.co'});
  });

  test('index.html no tiene scripts en línea ni recursos de terceros', () {
    final html = File('web/index.html').readAsStringSync();
    for (final m in RegExp(r'<script([^>]*)>').allMatches(html)) {
      expect(m.group(1), contains('src='), reason: 'script en línea: ${m.group(0)}');
    }
    expect(RegExp(r'''(src|href)="https?://''').hasMatch(html), isFalse, reason: 'recurso externo en index.html');
  });

  test('CSP: se pueden leer las fotos elegidas de la galería (blob:/data: en connect-src)', () {
    // image_picker entrega la foto como URL blob: y la app la lee con una petición; sin blob: no se puede subir
    // (onboarding, Editar perfil, portada de torneo, imagen de grupo). Son datos locales: no abre terceros.
    final connect = global['Content-Security-Policy']!.split(';').map((d) => d.trim()).firstWhere((d) => d.startsWith('connect-src'));
    expect(connect.split(' '), containsAll(['blob:', 'data:']));
    expect(connect.split(' ').where((x) => x.startsWith('http') || x.startsWith('wss')).every((x) => x.contains('niwognkvoifrvlizcdvb.supabase.co')), isTrue);
  });
}
