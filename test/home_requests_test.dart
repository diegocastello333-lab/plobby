import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plobby/core/supabase/supabase_bootstrap.dart';
import 'package:plobby/main.dart' show PlobbyApp;
import 'package:plobby/features/home/presentation/home_screen.dart';
import 'package:plobby/features/splash/application/splash_boot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cuenta las peticiones HTTP que hace el Inicio al abrir la app con sesión, usando los repositorios REALES de Supabase
/// contra un servidor simulado (sin red). Es la métrica «peticiones del inicio» del informe de rendimiento, y evita que
/// vuelvan a aparecer lecturas duplicadas o de 500 filas.
const _uid = '48eee197-dc9e-4f4f-bddd-b45f8b88c3a0';

String _b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _session() {
  final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;   // timing: sesión de prueba válida
  final jwt = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.${_b64({'sub': _uid, 'exp': exp, 'role': 'authenticated'})}.firma';
  return jsonEncode({
    'access_token': jwt, 'token_type': 'bearer', 'expires_in': 3600 * 24 * 30, 'expires_at': exp, 'refresh_token': 'r',
    'user': {'id': _uid, 'aud': 'authenticated', 'role': 'authenticated', 'email': 'demo@plobby.test', 'app_metadata': {}, 'user_metadata': {},
      'created_at': '2026-11-01T00:00:00Z'},
  });
}

http.Response _json(Object? body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

/// Respuestas mínimas y coherentes: el perfil está completo y con consentimientos; el resto, vacío.
http.Response _server(http.Request r) {
  final p = r.url.path;
  if (p.endsWith('/rpc/get_my_profile')) {
    return _json({'id': _uid, 'first_name': 'Diego', 'last_name': 'C', 'username': 'diego', 'city': 'Madrid', 'birth_date': '1990-01-01',
      'self_declared_level': 'intermediate', 'court_side': 'right', 'dominant_hand': 'right', 'avatar_url': null, 'avatar_id': null,
      'onboarding_completed_at': '2026-11-01T00:00:00Z'});
  }
  if (p.endsWith('/rpc/legal_status')) return _json({'required_ok': true, 'documents': [], 'marketing': false});
  if (p.endsWith('/rpc/get_profile')) {
    return _json({'id': _uid, 'display_name': 'Diego C', 'username': 'diego', 'self_declared_level': 'intermediate', 'is_self': true, 'full': true});
  }
  if (p.contains('/rpc/')) return _json([]);
  if (r.headers['accept']?.contains('vnd.pgrst.object') ?? false) return http.Response('{"code":"PGRST116","message":"0 rows"}', 406);
  return _json([]);
}

void main() {
  testWidgets('peticiones del Inicio al abrir la app con sesión', (t) async {
    final requests = <String>[];
    final client = SupabaseClient('https://example.supabase.co', 'sb_publishable_test',
        httpClient: MockClient((r) async {
          requests.add('${r.method} ${r.url.path.replaceFirst('/rest/v1', '')}${r.url.queryParameters.containsKey('limit') ? '?limit=${r.url.queryParameters['limit']}' : ''}');
          final res = _server(r);
          return http.Response.bytes(res.bodyBytes, res.statusCode, headers: res.headers, request: r);
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    await client.auth.setInitialSession(_session());
    SplashBoot.pending = false;
    await t.binding.setSurfaceSize(const Size(390, 844));
    // La app completa (con LiveSync, que también lee datos al arrancar), igual que en main.dart.
    await t.pumpWidget(ProviderScope(overrides: SupabaseBootstrap.overrides(client), child: const PlobbyApp()));
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }   // timing
    expect(find.byType(HomeScreen), findsOneWidget);
    final counts = <String, int>{};
    for (final r in requests.where((r) => !r.contains('/realtime/'))) { counts[r] = (counts[r] ?? 0) + 1; }
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    // ignore: avoid_print
    print('PETICIONES DEL INICIO: $total\n${(counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '  ${e.value}× ${e.key}').join('\n')}');
    expect(requests.where((r) => r.contains('limit=500')), isEmpty, reason: 'el Inicio no debe pedir el histórico completo');
    expect(counts['POST /rpc/get_my_profile'] ?? 0, lessThanOrEqualTo(1), reason: 'get_my_profile solo una vez');
    await t.pumpWidget(const SizedBox());
    // Sin red de verdad: los canales en tiempo real no llegan a conectar. Se cierran sin esperar respuesta del servidor.
    await t.runAsync(() async {
      try { await client.removeAllChannels().timeout(const Duration(seconds: 1)); } catch (_) {}   // timing
      try { await client.realtime.disconnect().timeout(const Duration(seconds: 1)); } catch (_) {}   // timing
    });
    unawaited(client.dispose());
    for (var i = 0; i < 4; i++) { await t.pump(const Duration(seconds: 30)); }   // timing: vencen límites de tiempo y reintentos pendientes
  });
}
