import '../domain/auth_models.dart';

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
  Future<void> completeOnboarding();
}

class AuthException implements Exception {
  AuthException(this.code, [this.message]);
  final String code; final String? message;
  @override
  String toString() => 'AuthException($code)';
}
