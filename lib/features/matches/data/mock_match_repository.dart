import '../domain/match_models.dart';
import 'match_repository.dart';

/// DATOS MOCK (desarrollo/tests). La app real usa SupabaseMatchRepository (ver supabase/integration).
class MockMatchRepository implements MatchRepository {
  final created = <MatchDraft>[];
  @override
  Future<List<LeagueOption>> myLeagues() async => const [LeagueOption('bunker', 'BÜNKER PADEL LEAGUE'), LeagueOption('madrid', 'MADRID SOCIAL PADEL')];
  @override
  Future<List<PlayerOption>> leagueMembers(String id) async => const [PlayerOption('marcos', 'Marcos R.'), PlayerOption('carlos', 'Carlos M.'), PlayerOption('laura', 'Laura G.')];
  @override
  Future<List<PlayerOption>> friends() async => const [PlayerOption('marcos', 'Marcos R.'), PlayerOption('lucia', 'Lucía M.'), PlayerOption('alvaro', 'Álvaro P.'), PlayerOption('carla', 'Carla N.')];
  @override
  Future<List<String>> clubs() async => const ['Club La Moraleja', 'Padel Chamberí', 'Club Alameda'];
  @override
  Future<String> create(MatchDraft d) async { created.add(d); return 'm${created.length}'; }
}
