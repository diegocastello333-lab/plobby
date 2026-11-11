import 'package:supabase_flutter/supabase_flutter.dart';
import 'match_repository.dart';
import '../domain/match_models.dart';

/// Integración Supabase (SIN verificar contra una base real). Mover a lib/features/matches/data/.
class SupabaseMatchRepository implements MatchRepository {
  SupabaseMatchRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<List<LeagueOption>> myLeagues() async {
    // Ligas reales del usuario: RLS de league_members/leagues (ADAPTAR nombres de tabla/columna al esquema real).
    final rows = await _db.from('league_members').select('league:leagues(id,name)').eq('user_id', _db.auth.currentUser!.id);
    return [for (final r in rows as List) LeagueOption(r['league']['id'], r['league']['name'])];
  }

  @override
  Future<List<PlayerOption>> leagueMembers(String leagueId) async {
    final rows = await _db.from('league_members').select('user:profiles(id,display_name)').eq('league_id', leagueId).neq('user_id', _db.auth.currentUser!.id);
    return [for (final r in rows as List) PlayerOption(r['user']['id'], r['user']['display_name'])];
  }

  @override
  Future<List<PlayerOption>> friends() async {
    final rows = await _db.from('v_my_friends').select('user_id,display_name');
    return [for (final r in rows as List) PlayerOption(r['user_id'], r['display_name'])];
  }

  @override
  Future<List<String>> clubs() async => [for (final r in await _db.from('clubs').select('name').order('name') as List) r['name'] as String];

  @override
  Future<String> create(MatchDraft d) async {
    final id = await _db.rpc('create_match', params: {
      'p_type': d.type.name,                 // 'league' | 'friendly'
      'p_league_id': d.leagueId,             // null en amistosos
      'p_partner': d.partnerId, 'p_rival1': d.rival1Id, 'p_rival2': d.rival2Id,
      'p_when': d.when.toUtc().toIso8601String(), 'p_club': d.club,
      'p_sets': [for (final s in d.sets) [s.a, s.b]],
    });
    return id as String;
  }
}
