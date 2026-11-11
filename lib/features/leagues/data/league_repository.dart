import '../../matches/domain/match_lifecycle.dart';
import '../domain/league_models.dart';

/// Ligas. Implementación real: [SupabaseLeagueRepository] (RPC de `20261120_leagues_profile.sql`): el cliente solo lee
/// con RLS y TODA escritura pasa por funciones `security definer` que comprueban rol y visibilidad en el servidor.
/// La clasificación también la calcula el servidor (`league_standings`); el cliente no suma puntos.
abstract class LeagueRepository {
  Future<List<LeagueSummary>> myLeagues();
  Future<List<DiscoverLeague>> discover(String query);
  Future<LeagueDetail> league(String id);
  Future<List<StandingRow>> standings(String id);
  /// Partidos de la liga (programados, en juego, pendientes y confirmados), más recientes primero.
  Future<List<LifecycleMatch>> matches(String id);
  Future<List<JoinRequest>> joinRequests(String id);          // solo gestores (RLS)
  Future<String?> inviteCode(String id);                      // null si no tienes permiso
  Future<({String id, String code})> create(LeagueDraft draft);
  Future<JoinOutcome> join(String id, {String? code, String? message});
  Future<String> joinByCode(String code);                     // devuelve el id de la liga
  Future<void> respondRequest(String requestId, {required bool accept});
  Future<void> leave(String id);
  Future<void> removeMember(String id, String userId);
  Future<int> invite(String id, List<String> userIds);
  /// Claves: name, description, cover, location, max_players, points_win, bonus_enabled, challenges_enabled, visibility, ended.
  Future<void> update(String id, Map<String, Object?> patch);
  /// Cambios en tiempo real (miembros, solicitudes, partidos) de una liga. Emite cuando hay que recargar.
  Stream<void> watch(String id);
}
