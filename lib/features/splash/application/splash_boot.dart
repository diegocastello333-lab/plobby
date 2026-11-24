import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/router/app_router.dart' show sessionGateProvider;
import '../../profile/application/profile_providers.dart' show profileProvider;

/// La pantalla de carga se muestra UNA vez por arranque de la app. `main()` activa [pending]; el router lo consume
/// al crearse. Al iniciar o cerrar sesión el ProviderScope (y el router) se recrean, pero ya no vuelve a salir.
class SplashBoot {
  SplashBoot._();
  static bool pending = false;
  static bool consume() { final p = pending; pending = false; return p; }

  /// Trabajo crítico que la carga espera (con límite de tiempo; nunca bloquea la entrada):
  ///  1. Sesión y onboarding (la guardia decide Inicio / Bienvenida / Onboarding sin «saltos» de pantalla).
  ///  2. Con sesión completa, el perfil propio: el Inicio aparece ya con nombre, foto, ELO y banner.
  /// Lo secundario (amigos, partidos, feed…) lo carga cada sección después, con sus propios estados de carga.
  static Future<void> criticalWork(WidgetRef ref) async {
    final gate = await ref.read(sessionGateProvider.future).timeout(const Duration(seconds: 6));
    if (gate.signedIn && gate.onboarded && gate.consentsOk) {
      await ref.read(profileProvider('me').future).timeout(const Duration(seconds: 3));
    }
  }
}

/// Recuerda, por usuario, que su último arranque pasó la guardia (sesión + consentimientos + onboarding). Con eso, si al
/// abrir la app ya hay sesión guardada se entra DIRECTAMENTE al Inicio, sin pantalla de carga: la guardia vuelve a
/// comprobarlo en segundo plano y, si algo cambió (p. ej. hay una versión nueva de los Términos), redirige igual.
class GateCache {
  GateCache._();
  static SharedPreferences? _prefs;
  static String _key(String uid) => 'plobby.gate_ok.$uid';

  static Future<void> load() async {
    try { _prefs = await SharedPreferences.getInstance(); } catch (_) {/* sin almacenamiento: se muestra la carga */}
  }

  static bool okFor(String? uid) => uid != null && (_prefs?.getBool(_key(uid)) ?? false);

  static void remember(String uid, bool ok) {
    try { _prefs?.setBool(_key(uid), ok); } catch (_) {/* no crítico */}
  }
}
