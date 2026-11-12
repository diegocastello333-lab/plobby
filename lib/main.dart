import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/errors/app_errors.dart';
import 'core/live/live_sync.dart';
import 'core/router/app_router.dart';
import 'features/splash/application/splash_boot.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'core/theme/plobby_theme.dart';

/// Con `--dart-define-from-file=env.json` (SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY) la app usa Supabase;
/// sin credenciales arranca en modo demo con datos de ejemplo (repositorios mock).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrors.install();
  SplashBoot.pending = true;   // pantalla de carga en este arranque (una sola vez)   // errores no controlados: registrados y sin pantallas grises/negras en la APK
  final client = await SupabaseBootstrap.init();
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
