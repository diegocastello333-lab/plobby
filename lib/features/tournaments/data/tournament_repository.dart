import '../domain/tournament_models.dart';

/// Contrato de Torneos (independiente de Ligas). Implementación real: [SupabaseTournamentRepository] (RPC de la
/// migración `20261124b_tournaments.sql`); demo y tests: [MockTournamentRepository] (con [TournamentEngine]).
abstract class TournamentRepository {
  String get meId;
  Future<List<TournamentSummary>> myTournaments();
  Future<TournamentDetail> detail(String id);
  /// Sube la portada (JPEG ya optimizado) y devuelve su URL pública.
  Future<String> uploadCover(List<int> jpeg);
  /// Crea el torneo con sus parejas y genera la estructura (grupos, partidos y cuadro) en una sola operación.
  Future<String> create(TournamentDraft d, {String? coverUrl});
  Future<void> updateInfo(String id, Map<String, dynamic> patch);
  /// Cambia parejas (y formato) antes de que haya resultados; regenera la estructura.
  Future<void> replaceTeams(String id, List<(TPlayer, TPlayer)> teams, {TournamentFormat? format, int? groupsCount, int? qualifiersPerGroup});
  /// Registra o corrige un resultado; [version] es la que vio el usuario (si otro lo cambió antes → `result_conflict`).
  Future<void> recordResult(String matchId, List<(int, int)> sets, int version);
  Future<void> clearResult(String matchId, int version);
  Future<void> setLive(String matchId, bool live);
  /// Torneos que han cambiado (Realtime). Emite el id del torneo.
  Stream<String> changes();
}
