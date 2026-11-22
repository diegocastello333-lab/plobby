import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Guarda la sesión de Supabase (token de acceso y de refresco) cifrada en el dispositivo.
///
/// Por defecto `supabase_flutter` la deja en SharedPreferences, que en Android es un XML en texto plano dentro de la
/// carpeta de la app (legible con root o en una copia de seguridad). Aquí se usa `flutter_secure_storage`:
/// Android Keystore (EncryptedSharedPreferences) y Keychain en iOS.
///
/// Migración: la primera vez que arranca esta versión, si había una sesión en SharedPreferences (versiones
/// anteriores de Plobby) se copia al almacén cifrado y se borra del antiguo. El usuario NO tiene que volver a entrar.
///
/// En web no se usa: el navegador no ofrece un almacén más seguro que localStorage para un SPA (la clave de cifrado
/// tendría que vivir también en el navegador), así que se mantiene el almacenamiento por defecto.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey, FlutterSecureStorage? storage}) : _storage = storage ?? secureStorage;

  final String persistSessionKey;
  final FlutterSecureStorage _storage;

  /// Opciones únicas para toda la app. `resetOnError`: si el Keystore se corrompe (pasa en algunos móviles tras
  /// restaurar el sistema), se borra el almacén en vez de bloquear la app; el usuario solo tendría que volver a entrar.
  static const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true, resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  /// Clave que usa `supabase_flutter` por defecto: `sb-<ref del proyecto>-auth-token`.
  static String defaultKey(String supabaseUrl) => 'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy != null) {
        if (await _storage.read(key: persistSessionKey) == null) await _storage.write(key: persistSessionKey, value: legacy);
        await prefs.remove(persistSessionKey);
      }
    } catch (e) {
      // Sin migración posible: la app sigue funcionando; como mucho, el usuario vuelve a iniciar sesión.
      debugPrint('secure_session_migration_failed: ${e.runtimeType}');
    }
  }

  @override
  Future<bool> hasAccessToken() async => (await _read()) != null;

  @override
  Future<String?> accessToken() => _read();

  @override
  Future<void> removePersistedSession() async {
    try { await _storage.delete(key: persistSessionKey); } catch (_) {}
  }

  @override
  Future<void> persistSession(String persistSessionString) => _storage.write(key: persistSessionKey, value: persistSessionString);

  Future<String?> _read() async {
    try { return await _storage.read(key: persistSessionKey); } catch (_) { return null; }
  }
}

/// El verificador PKCE del inicio de sesión con Google (vive unos segundos, entre abrir Google y volver a la app).
/// También cifrado, por coherencia: por defecto iría a SharedPreferences.
class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage({FlutterSecureStorage? storage}) : _storage = storage ?? SecureSessionStorage.secureStorage;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem({required String key}) async {
    try { return await _storage.read(key: key); } catch (_) { return null; }
  }

  @override
  Future<void> setItem({required String key, required String value}) => _storage.write(key: key, value: value);

  @override
  Future<void> removeItem({required String key}) async {
    try { await _storage.delete(key: key); } catch (_) {}
  }
}

/// Opciones de Auth para [Supabase.initialize]: almacén cifrado en Android/iOS; por defecto en web.
FlutterAuthClientOptions plobbyAuthOptions(String supabaseUrl) => kIsWeb
    ? const FlutterAuthClientOptions()
    : FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(persistSessionKey: SecureSessionStorage.defaultKey(supabaseUrl)),
        pkceAsyncStorage: SecurePkceStorage(),
      );
