// Plobby · Acceso con Google REAL (Supabase Auth). Se activa en lib/core/supabase/supabase_bootstrap.dart cuando hay credenciales.
// SOLO se usa la clave anon (pública, protegida por RLS). NUNCA pongas la service_role key en la app.
//
// CONFIGURACIÓN EXTERNA PENDIENTE (no se puede hacer desde código):
//  1. Google Cloud Console → credenciales OAuth: tipo «Web» (el que usa Supabase) y, si usas login nativo, Android (SHA-1) e iOS.
//  2. Supabase → Authentication → Providers → Google: Client ID + Secret; activa «Skip nonce checks» solo si usas el login nativo en iOS.
//  3. Supabase → Authentication → URL Configuration: añade el redirect  io.plobby.app://login-callback/  (y el de web si aplica).
//  4. Android: en AndroidManifest.xml, dentro de <activity android:name=".MainActivity">:
//       <intent-filter><action android:name="android.intent.action.VIEW"/><category android:name="android.intent.category.DEFAULT"/>
//         <category android:name="android.intent.category.BROWSABLE"/><data android:scheme="io.plobby.app" android:host="login-callback"/></intent-filter>
//  5. iOS: en Info.plist, CFBundleURLTypes → CFBundleURLSchemes = [io.plobby.app]. Para Google nativo, además REVERSED_CLIENT_ID.
//  6. Supabase → Authentication → Settings: «Enable automatic linking» por email verificado (una cuenta Google = un usuario).

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../domain/auth_models.dart';
import 'auth_repository.dart';

const kAuthRedirect = 'io.plobby.app://login-callback/';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._c);
  final sb.SupabaseClient _c;

  AuthUser? _map(sb.User? u) => u == null ? null : AuthUser(id: u.id, email: u.email ?? '', displayName: u.userMetadata?['full_name'] as String?);

  @override
  AuthUser? get currentUser => _map(_c.auth.currentUser);          // sesión persistida por supabase_flutter (secure storage)

  @override
  Stream<AuthUser?> authChanges() => _c.auth.onAuthStateChange.map((e) => _map(e.session?.user));

  @override
  Future<void> signInWithGoogle() async {
    // Móvil: vuelve a la app por el esquema io.plobby.app. Web: vuelve a la misma URL de la app (redirect null).
    final ok = await _c.auth.signInWithOAuth(sb.OAuthProvider.google, redirectTo: kIsWeb ? null : kAuthRedirect,
        authScreenLaunchMode: kIsWeb ? sb.LaunchMode.platformDefault : sb.LaunchMode.externalApplication);
    if (!ok) throw AuthException('oauth_cancelled');
  }

  @override
  Future<void> signOut() => _c.auth.signOut();

  @override
  Future<OnboardingData> loadOnboarding() async {
    // get_my_profile (security definer): birth_date / first_name / last_name / onboarding_* ya no son legibles con select() sobre `profiles`.
    final r = await _c.rpc('get_my_profile') as Map<String, dynamic>?;
    if (r == null || r['id'] == null) return const OnboardingData();
    T? pick<T>(List<T> v, String? s, String Function(T) key) { for (final x in v) { if (key(x) == s) return x; } return null; }
    return OnboardingData(
      firstName: (r['first_name'] ?? '') as String, lastName: (r['last_name'] ?? '') as String, username: (r['username'] ?? '') as String, city: (r['city'] ?? '') as String,
      birthDate: r['birth_date'] == null ? null : DateTime.parse(r['birth_date'] as String),
      selfLevel: pick(SelfLevel.values, r['self_declared_level'] as String?, (x) => x.db),
      side: r['court_side'] == null ? null : (r['court_side'] == 'left' ? CourtSide.left : CourtSide.right),
      hand: r['dominant_hand'] == null ? null : (r['dominant_hand'] == 'left' ? Hand.left : Hand.right),
      habitualClub: r['habitual_club'] as String?, habitualPartnerId: r['habitual_partner_id'] as String?,
      avatarId: r['avatar_id'] as String?, avatarUrl: r['avatar_url'] as String?, completed: r['onboarding_completed_at'] != null);
  }

  @override
  Future<bool> isUsernameAvailable(String u) async => (await _c.rpc('is_username_available', params: {'p_username': u})) as bool;

  @override
  Future<void> saveStep(int step, OnboardingData d) async {
    final data = switch (step) {
      1 => {'first_name': d.firstName, 'last_name': d.lastName, 'username': d.username, 'city': d.city, 'birth_date': d.birthDate!.toIso8601String().substring(0, 10)},
      2 => {'level': d.selfLevel!.db, 'side': d.side == CourtSide.left ? 'left' : 'right', 'hand': d.hand == Hand.left ? 'left' : 'right', 'club': d.habitualClub ?? '', 'partner_id': d.habitualPartnerId ?? ''},
      3 => {'avatar_url': d.avatarUrl ?? '', 'avatar_id': d.avatarId ?? ''},
      _ => throw AuthException('invalid_step'),
    };
    try { await _c.rpc('save_onboarding_step', params: {'p_step': step, 'p_data': data}); }
    on sb.PostgrestException catch (e) { throw AuthException(e.message.contains('username_taken') ? 'username_taken' : 'server', e.message); }
    catch (_) { throw AuthException('network'); }
  }

  @override
  Future<String> uploadAvatar(List<int> bytes, String mime) async {
    final uid = _c.auth.currentUser!.id;
    final ext = mime == 'image/png' ? 'png' : mime == 'image/webp' ? 'webp' : 'jpg';
    final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';     // la política de Storage exige la carpeta <uid>/
    await _c.storage.from('avatars').uploadBinary(path, Uint8List.fromList(bytes), fileOptions: sb.FileOptions(contentType: mime, upsert: true));
    return _c.storage.from('avatars').getPublicUrl(path);
  }

  @override
  Future<void> deleteAvatarFiles({String? keepUrl}) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final bucket = _c.storage.from('avatars');
      final files = await bucket.list(path: uid);
      // Solo fotos de perfil (`avatar_*`): en la misma carpeta vive el banner de Inicio (`banner_*`).
      final stale = [for (final f in files) if (f.name.startsWith('avatar_') && bucket.getPublicUrl('$uid/${f.name}') != keepUrl) '$uid/${f.name}'];
      if (stale.isNotEmpty) await bucket.remove(stale);   // política de Storage: solo se puede borrar en la carpeta propia
    } catch (_) {/* limpieza best-effort: el registro del perfil ya no apunta a esos ficheros */}
  }

  @override
  Future<void> completeOnboarding() async {
    try { await _c.rpc('complete_onboarding'); } on sb.PostgrestException { throw AuthException('onboarding_incomplete'); }
  }
}
