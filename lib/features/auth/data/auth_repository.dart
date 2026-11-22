import '../domain/auth_models.dart';
import '../domain/legal.dart';
import '../../../core/errors/failure.dart';

/// Acceso con Google (Supabase Auth). Una cuenta Google ↔ un único usuario: la implementación real usa
/// `signInWithOAuth(OAuthProvider.google)` y el perfil se crea/recupera con el trigger `handle_new_user`.
abstract class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthUser?> authChanges();                     // sesión persistente: emite el usuario al arrancar si hay sesión guardada
  Future<void> signInWithGoogle();                     // lanza OAuth; la sesión llega por [authChanges] tras el redirect
  Future<void> signOut();

  Future<OnboardingData> loadOnboarding();             // lo ya guardado (para reanudar y saltar pasos completos)
  Future<bool> isUsernameAvailable(String username);   // RPC is_username_available
  Future<void> saveStep(int step, OnboardingData data);// RPC save_onboarding_step (valida en servidor)
  Future<String> uploadAvatar(List<int> bytes, String mime); // Storage `avatars/<uid>/…`; devuelve la URL pública
  /// Borra de Storage las imágenes de `avatars/<uid>/` salvo la de [keepUrl] (la vigente). Se llama tras cambiar o
  /// quitar la foto para no dejar ficheros huérfanos. Nunca lanza: si falla, el perfil ya está guardado.
  Future<void> deleteAvatarFiles({String? keepUrl});
  Future<void> completeOnboarding();

  // ── Legal y privacidad (Seguridad Fase 8) ──
  /// Qué documentos obligatorios faltan por aceptar (o cambiaron de versión) y si tiene activas las comunicaciones comerciales.
  Future<LegalStatus> legalStatus();
  /// Acepta Términos + Privacidad + edad mínima (versión vigente, la fija el servidor) y guarda la casilla opcional de marketing.
  Future<LegalStatus> acceptLegal({required bool marketing});
  /// Activa o retira el consentimiento para comunicaciones comerciales.
  Future<void> setMarketing(bool accept);
  /// Todos los datos del usuario en JSON (RPC export_my_data; máximo 1 cada 10 minutos).
  Future<String> exportMyData();
  /// Borra la cuenta (Edge Function `delete-account`): fotos, datos personales y usuario; lo compartido queda anónimo.
  Future<void> deleteAccount();
  /// Cierra la sesión en todos los dispositivos (revoca todos los tokens de refresco).
  Future<void> signOutEverywhere();
}

class AuthException implements Exception, CodedFailure {
  AuthException(this.code, [this.message]);
  final String code; final String? message;
  @override
  String toString() => 'AuthException($code)';
}
