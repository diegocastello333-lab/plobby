import '../../../core/errors/failure.dart';
import '../domain/club_models.dart';

/// Catálogo de clubes. En Supabase: `search_clubs`, `propose_club`, `club_page`, `nearby_clubs` y las funciones de
/// administración (solo para cuentas con `app_metadata.plobby_admin`). El club del jugador es `habitual_club_id`
/// (= club base; el servidor mantiene `home_club_id` igual).
abstract class ClubRepository {
  Future<List<ClubHit>> search(String query, {double? lat, double? lng, List<ClubType>? types, int limit = 8});
  Future<List<ClubHit>> nearby(double lat, double lng, {int limit = 8});
  Future<ProposeOutcome> propose({required String name, required String municipality, ClubType type = ClubType.privateClub,
      String? address, bool force = false});
  Future<ClubPage?> page(String clubId);
  /// Guarda el club habitual del usuario (null = quitarlo).
  Future<void> setMyClub(String? clubId);
  bool get isAdmin;
  Future<List<PendingClub>> pending();
  Future<void> review(String clubId, String action, {String? targetId, String? note});
  Future<void> addAlias(String clubId, String alias);
}

class ClubException implements Exception, CodedFailure {
  ClubException(this.code);
  @override
  final String code;
  String get message => switch (code) {
        'rate_limited' => 'Has propuesto muchos clubes hoy. Inténtalo mañana.',
        'invalid_club' => 'Escribe el nombre del club y el municipio.',
        'club_not_available' => 'Ese club ya no está disponible. Elige otro.',
        'forbidden' => 'No tienes permiso para hacer esto.',
        'invalid_target' => 'Elige un club verificado para fusionar.',
        'network' => 'Sin conexión. Comprueba tu red e inténtalo de nuevo.',
        _ => 'No se pudo completar. Inténtalo de nuevo.',
      };
  @override
  String toString() => 'ClubException($code)';
}
