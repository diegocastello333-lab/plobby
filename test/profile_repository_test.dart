import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plobby/features/profile/data/supabase_profile_repository.dart';
import 'package:plobby/features/profile/domain/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repositorio REAL de perfil contra un servidor PostgREST simulado (sin red).
/// - Regresión del 16 nov 2026: la pareja embebida con la pista ambigua `profiles!habitual_partner_id` podía llegar como
///   LISTA y el perfil fallaba entero («no hay conexión» con Supabase respondiendo 200).
/// - Seguridad 22 nov 2026: el perfil se lee con la RPC `get_profile`, que decide en el servidor qué datos ve cada uno
///   (desconocidos: solo nombre, usuario, foto y nivel). La app ya no pide columnas privadas a la tabla `profiles`.
const me = '48eee197-dc9e-4f4f-bddd-b45f8b88c3a0', partner = '11111111-2222-3333-4444-555555555555', stranger = '99999999-2222-3333-4444-555555555555';

Map<String, dynamic> _full(String id, String name, {Map<String, dynamic>? partnerJson}) => {
      'id': id, 'display_name': name, 'username': name.toLowerCase(), 'avatar_url': null, 'avatar_id': null, 'banner_id': null,
      'self_declared_level': 'advanced', 'is_self': id == me, 'full': true,
      'city': 'Madrid', 'bio': 'Juego por las tardes', 'court_side': 'left', 'dominant_hand': 'left', 'habitual_club': null,
      if (partnerJson != null) 'partner': partnerJson,
    };

void main() {
  late List<http.Request> requests;

  SupabaseProfileRepository repo(http.Response Function(http.Request) handler) {
    requests = [];
    final client = MockClient((r) async {
      requests.add(r);
      final res = handler(r);
      return http.Response.bytes(res.bodyBytes, res.statusCode, headers: res.headers, request: r);   // el cliente lee res.request
    });
    return SupabaseProfileRepository(SupabaseClient('https://example.supabase.co', 'sb_publishable_test', httpClient: client,
        authOptions: const AuthClientOptions(autoRefreshToken: false)));
  }

  http.Response json(Object? body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  http.Response server(http.Request r) {
    final p = r.url.path;
    if (p.endsWith('/rpc/get_profile')) {
      final id = (jsonDecode(r.body) as Map)['p_user'];
      if (id == me) return json(_full(me, 'Diego', partnerJson: {'id': partner, 'display_name': 'Anto', 'username': 'anto', 'avatar_url': null, 'mutual': true}));
      if (id == stranger) {
        return json({'id': stranger, 'display_name': 'Lucía', 'username': 'lucia', 'avatar_url': null, 'avatar_id': 'a3',
            'self_declared_level': 'intermediate', 'is_self': false, 'full': false});
      }
      return json(null);
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
    expect(d.profile.location, 'Madrid');
    expect(d.profile.limited, isFalse);
    expect(d.profile.partner?.name, 'Anto');
    expect(d.profile.partner?.status, PartnerStatus.accepted);
  });

  test('la app no pide columnas a la tabla profiles: todo llega por get_profile (una sola llamada)', () async {
    await repo(server).load(me);
    expect(requests.where((r) => r.url.path.endsWith('/profiles')), isEmpty);
    expect(requests.where((r) => r.url.path.endsWith('/rpc/get_profile')).length, 1);
  });

  test('perfil de un desconocido: limitado, sin ciudad, bio ni pareja', () async {
    final d = await repo(server).load(stranger);
    expect(d.profile.fullName, 'Lucía');
    expect(d.profile.limited, isTrue);
    expect(d.profile.location, isEmpty);
    expect(d.profile.bio, isEmpty);
    expect(d.profile.partner, isNull);
    expect(d.profile.club, isNull);
  });

  test('perfil inexistente: error claro (no un perfil vacío)', () async {
    expect(() => repo(server).load('00000000-0000-0000-0000-000000000000'), throwsA(isA<PostgrestException>()));
  });
}
