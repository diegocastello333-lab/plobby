import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plobby/features/profile/data/supabase_profile_repository.dart';
import 'package:plobby/features/profile/domain/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repositorio REAL de perfil contra un servidor PostgREST simulado (sin red). Regresión del 16 nov 2026: la pareja
/// habitual se pedía embebida con la pista ambigua `profiles!habitual_partner_id`; si llegaba como lista, el perfil
/// fallaba entero y la app mostraba «no hay conexión» aunque Supabase respondía 200.
const me = '48eee197-dc9e-4f4f-bddd-b45f8b88c3a0', partner = '11111111-2222-3333-4444-555555555555';

Map<String, dynamic> _profile(String id, String name, {String? partnerId}) => {
      'id': id, 'display_name': name, 'username': name.toLowerCase(), 'avatar_url': null, 'avatar_id': null, 'banner_id': null,
      'city': 'Madrid', 'bio': '', 'self_declared_level': 'advanced', 'court_side': 'right', 'dominant_hand': 'right',
      'habitual_club': null, 'habitual_partner_id': partnerId,
    };

void main() {
  late List<Uri> requests;

  SupabaseProfileRepository repo(http.Response Function(http.Request) handler) {
    requests = [];
    final client = MockClient((r) async {
      requests.add(r.url);
      final res = handler(r);
      return http.Response.bytes(res.bodyBytes, res.statusCode, headers: res.headers, request: r);   // el cliente lee res.request
    });
    return SupabaseProfileRepository(SupabaseClient('https://example.supabase.co', 'sb_publishable_test', httpClient: client,
        authOptions: const AuthClientOptions(autoRefreshToken: false)));
  }

  http.Response json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  http.Response server(http.Request r) {
    final p = r.url.path, id = (r.url.queryParameters['id'] ?? '').replaceFirst('eq.', '');
    if (p.endsWith('/profiles')) {
      if ((r.url.queryParameters['select'] ?? '').contains('partner:')) {
        // Lo que podía devolver la consulta embebida ambigua: una LISTA.
        return json({..._profile(me, 'Diego', partnerId: partner), 'partner': [_profile(partner, 'Anto', partnerId: me)]});
      }
      return json(id == me ? _profile(me, 'Diego', partnerId: partner) : _profile(partner, 'Anto', partnerId: me));
    }
    if (p.endsWith('/player_ratings')) return json({'elo': 1482});
    if (p.endsWith('/league_members')) return json([]);
    if (p.endsWith('/rpc/get_player_history')) return json([]);
    return http.Response('{}', 404);
  }

  test('perfil con pareja habitual mutua: carga y la pareja aparece aceptada', () async {
    final d = await repo(server).load(me);
    expect(d.profile.fullName, 'Diego');
    expect(d.currentElo, 1482);
    expect(d.profile.partner?.name, 'Anto');
    expect(d.profile.partner?.status, PartnerStatus.accepted);
  });

  test('la consulta de perfil NO embebe la relación ambigua de profiles consigo misma', () async {
    await repo(server).load(me);
    final selects = [for (final u in requests) if (u.path.endsWith('/profiles')) u.queryParameters['select'] ?? ''];
    expect(selects, isNotEmpty);
    expect(selects.where((s) => s.contains('partner:')), isEmpty);
  });

  test('perfil sin pareja: una sola consulta de perfil', () async {
    final d = await repo((r) {
      if (r.url.path.endsWith('/profiles')) return json(_profile(me, 'Diego'));
      return server(r);
    }).load(me);
    expect(d.profile.partner, isNull);
    expect(requests.where((u) => u.path.endsWith('/profiles')).length, 1);
  });
}
