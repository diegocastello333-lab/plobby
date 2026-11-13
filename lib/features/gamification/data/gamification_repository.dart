import '../domain/gamification_models.dart';

/// Acceso a Head to Head, ranking entre amigos, Wrapped, logros/XP y preferencias de avisos.
/// En Supabase todo se calcula en el servidor (RPC sobre `player_match_stats`); la app solo lee.
abstract class GamificationRepository {
  String get meId;
  Future<H2HData> headToHead(String otherId);
  Future<RankingData> ranking(RankPeriod period, {int offset = 0});
  Future<List<WrappedPeriod>> wrappedPeriods();
  Future<WrappedData> wrapped(WrappedKind kind, DateTime start);
  Future<AchievementsData> achievements();
  Future<void> markAchievementsSeen();
  Future<NotificationPrefs> prefs();
  Future<void> savePrefs(NotificationPrefs p);
}

/// Error con código del servidor (no_friends, not_authenticated…) traducido a una frase.
class GamificationException implements Exception {
  GamificationException(this.code);
  final String code;
  String get message => switch (code) {
        'not_friends' => 'Solo puedes compararte con tus amigos.',
        'not_authenticated' => 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
        'network' => 'Sin conexión. Comprueba tu red e inténtalo de nuevo.',
        _ => 'No se pudo cargar. Inténtalo de nuevo.',
      };
  @override
  String toString() => 'GamificationException($code)';
}
