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

  /// Banner de Inicio: un predeterminado ([presetId]) o una foto propia ya subida ([url]); ambos nulos = el de Plobby.
  /// RPC `set_home_banner` (valida que la URL sea de la carpeta del usuario).
  Future<void> setBanner({String? presetId, String? url});
  /// Sube el JPEG ya recortado y optimizado a `avatars/<uid>/banner_<ts>.jpg` y devuelve su URL pública (única por
  /// subida, así la caché de imágenes nunca muestra la anterior).
  Future<String> uploadBanner(List<int> jpeg);
  /// Borra los banners antiguos del usuario salvo [keepUrl]. Nunca lanza.
  Future<void> deleteOldBanners({String? keepUrl});
}
