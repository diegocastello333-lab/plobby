import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';

class StartResult { const StartResult({required this.started, required this.startedAt, required this.startedBy}); final bool started; final DateTime startedAt; final String startedBy; }
class LifecycleException implements Exception { LifecycleException(this.code); final String code; @override String toString() => 'LifecycleException($code)'; }

class EditMatch {
  const EditMatch({required this.scheduledAt, required this.club, this.court, required this.players});
  final DateTime scheduledAt; final String club; final String? court;
  final List<MatchPlayer> players;       // 4 jugadores con equipo y capitán
}

/// Ciclo de vida del partido. La implementación real (SupabaseLifecycleRepository) llama a las RPC atómicas
/// (start_match, finish_match, submit_result, respond_result, update_match, cancel_match) y escucha Realtime.
/// Ninguna de estas operaciones calcula ELO/estadísticas en el cliente: lo hace el servidor al confirmar.
abstract class LifecycleRepository {
  Future<DateTime> serverTime();
  Stream<List<LifecycleMatch>> watchUpcoming();                 // «Próximos partidos» (Home y perfil): UNA sola fuente
  Stream<LifecycleMatch?> watchMatch(String id);                // Realtime: los 4 jugadores ven los mismos cambios
  Future<StartResult> start(String id);
  Future<void> finish(String id);
  Future<int> submitResult(String id, List<SetScore> sets);     // devuelve la versión creada
  Future<MatchStatus> respond(String id, int version, {required bool accept, String? reason});
  Future<void> update(String id, EditMatch e);
  Future<void> cancel(String id);                               // «Eliminar partido»
  /// Partidos del usuario ya CONFIRMADOS (historial compartible, más recientes primero). Solo lectura.
  Future<List<LifecycleMatch>> confirmedMatches();
}
