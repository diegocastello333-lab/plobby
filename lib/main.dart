import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/errors/app_errors.dart';
import 'core/live/live_sync.dart';
import 'core/motion/app_motion.dart';
import 'core/router/app_router.dart';
import 'core/router/deferred_screen.dart';
import 'features/splash/application/splash_boot.dart';
import 'features/home/application/home_snapshot.dart' show HomeSnapshotStore;
import 'core/supabase/supabase_bootstrap.dart';
import 'core/theme/plobby_theme.dart';

/// Con `--dart-define-from-file=env.json` (SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY) la app usa Supabase;
/// sin credenciales arranca en modo demo con datos de ejemplo (repositorios mock).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrors.install();
  await Future.wait([
    AppHaptics.load(),   // preferencia «Vibración» de Ajustes, antes del primer toque
    GateCache.load(),
    HomeSnapshotStore.load(),   // cabecera del Inicio al instante (stale-while-revalidate)
    ThumbsHealed.load(),
  ]);
  final client = await SupabaseBootstrap.init();
  if (kIsWeb) {
    // Web: el código de las pantallas secundarias se descarga en segundo plano cuando la app ya está a la vista.
    WidgetsBinding.instance.addPostFrameCallback((_) => Timer(const Duration(seconds: 4), () => unawaited(DeferredScreen.preload(deferredScreenLoaders))));  // timing
  } else {
    await DeferredScreen.preload(deferredScreenLoaders);   // móvil: sin descarga, solo se registran
  }
  // Pantalla de carga solo cuando hace falta esperar algo: sin sesión, o con una sesión que aún no ha pasado la guardia
  // en este dispositivo. Con sesión ya validada se entra directo al Inicio (la guardia se comprueba en segundo plano).
  SplashBoot.pending = client == null || !GateCache.okFor(client.auth.currentUser?.id);
  runApp(client == null
      ? const ProviderScope(child: PlobbyApp())
      : SupabaseSessionScope(client: client, child: const PlobbyApp()));
}

class PlobbyApp extends ConsumerWidget {
  const PlobbyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
      title: 'Plobby', theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider), debugShowCheckedModeBanner: false,
      // Sincronización en vivo y avisos emergentes en cualquier pantalla (no solo en las pestañas).
      builder: (_, child) => LiveSync(child: child ?? const SizedBox.shrink()));
}
