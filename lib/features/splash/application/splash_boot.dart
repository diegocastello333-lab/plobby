import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    if (gate.signedIn && gate.onboarded) {
      await ref.read(profileProvider('me').future).timeout(const Duration(seconds: 3));
    }
  }
}
