import '../domain/match_models.dart';

/// Creación de partidos. Una sola ruta para liga y amistoso; el tipo viaja en [MatchDraft.type].
/// La implementación real llama a la RPC `create_match` (ver migración 20261113_match_type.sql), que valida
/// membresía/amistad con RLS y deja las notificaciones de confirmación. NO calcula ELO ni estadísticas.
abstract class MatchRepository {
  Future<List<LeagueOption>> myLeagues();                           // ligas REALES del usuario
  Future<List<PlayerOption>> leagueMembers(String leagueId);         // sin el propio usuario
  Future<List<PlayerOption>> friends();                              // para amistosos
  Future<List<String>> clubs();
  Future<String> create(MatchDraft draft);                           // devuelve el id del partido
}
