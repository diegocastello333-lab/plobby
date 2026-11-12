import '../domain/models.dart';

/// Contrato del perfil. La UI solo conoce esta interfaz.
abstract class ProfileRepository {
  Future<ProfileData> load(String playerId);
  Future<void> setSide(PlaySide side);
  Future<void> setClub(ClubRef? club);
  /// Crea la solicitud de pareja (queda `pending` hasta que el otro usuario acepte).
  Future<PartnerLink?> requestPartner(String userId);
  Future<void> removePartner();
  Future<List<ClubRef>> searchClubs(String query);
  /// Bio del propio perfil (máx. 160 caracteres en la app; la columna admite 280).
  Future<void> setBio(String bio);
}
