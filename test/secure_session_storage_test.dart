import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/supabase/secure_session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seguridad Fase 5: la sesión de Supabase se guarda cifrada (Keystore/Keychain), no en SharedPreferences.
void main() {
  const key = 'sb-niwognkvoifrvlizcdvb-auth-token';
  const session = '{"access_token":"a","refresh_token":"r"}';

  test('la clave es la misma que usa supabase_flutter por defecto', () {
    expect(SecureSessionStorage.defaultKey('https://niwognkvoifrvlizcdvb.supabase.co'), key);
  });

  test('migra la sesión de SharedPreferences al almacén cifrado y la borra del antiguo (no hay que volver a entrar)', () async {
    SharedPreferences.setMockInitialValues({key: session});
    FlutterSecureStorage.setMockInitialValues({});
    final s = SecureSessionStorage(persistSessionKey: key);
    await s.initialize();
    expect(await s.accessToken(), session);
    expect(await s.hasAccessToken(), isTrue);
    expect((await SharedPreferences.getInstance()).getString(key), isNull, reason: 'no debe quedar copia en texto plano');
  });

  test('guarda, lee y borra (cerrar sesión) solo en el almacén cifrado', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final s = SecureSessionStorage(persistSessionKey: key);
    await s.initialize();
    expect(await s.hasAccessToken(), isFalse);
    await s.persistSession(session);
    expect(await s.accessToken(), session);
    expect((await SharedPreferences.getInstance()).getString(key), isNull);
    await s.removePersistedSession();
    expect(await s.hasAccessToken(), isFalse);
  });

  test('si ya hay sesión cifrada, la migración no la pisa con una antigua', () async {
    SharedPreferences.setMockInitialValues({key: 'vieja'});
    FlutterSecureStorage.setMockInitialValues({key: session});
    final s = SecureSessionStorage(persistSessionKey: key);
    await s.initialize();
    expect(await s.accessToken(), session);
    expect((await SharedPreferences.getInstance()).getString(key), isNull);
  });

  test('el verificador PKCE del login con Google también va cifrado', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final p = SecurePkceStorage();
    await p.setItem(key: 'pkce', value: 'v');
    expect(await p.getItem(key: 'pkce'), 'v');
    await p.removeItem(key: 'pkce');
    expect(await p.getItem(key: 'pkce'), isNull);
  });
}
