import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'core/a11y/web_a11y.dart';
import 'core/theme/theme_pref.dart';
import 'core/widgets/net_image.dart';
import 'core/widgets/loading_bar.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/errors/app_errors.dart';
import 'core/live/live_sync.dart';
import 'core/motion/app_motion.dart';
import 'core/router/app_router.dart';
import 'core/router/deferred_screen.dart';
import 'core/widgets/wide_frame.dart';
import 'features/splash/application/splash_boot.dart';
import 'features/home/application/home_snapshot.dart' show HomeSnapshotStore;
import 'core/supabase/supabase_bootstrap.dart';
import 'core/theme/design_tokens.dart';
import 'core/theme/plobby_theme.dart';

/// Con `--dart-define-from-file=env.json` (SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY) la app usa Supabase;
/// sin credenciales arranca en modo demo con datos de ejemplo (repositorios mock).
/// Mantiene activa la semántica en la web mientras viva la app.
// ignore: unused_element

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrors.install();
  await Future.wait([
    AppHaptics.load(),   // preferencia «Vibración» de Ajustes, antes del primer toque
    ThemePrefs.load(),
    NetImage.loadMissing(),   // miniaturas que no existen: no volver a pedirlas en cada apertura   // apariencia (oscuro por defecto) antes del primer fotograma: sin destello claro
    GateCache.load(),
    HomeSnapshotStore.load(),   // cabecera del Inicio al instante (stale-while-revalidate)
    ThumbsHealed.load(),
  ]);
  final client = await SupabaseBootstrap.init();
  // Web: accesibilidad bajo demanda (botón «Activar lector de pantalla», recordado). Siempre activa costaba ~40 % de
  // cada fotograma al desplazar. Ver core/a11y/web_a11y.dart.
  if (kIsWeb) installWebA11yToggle();
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

class PlobbyApp extends ConsumerStatefulWidget {
  const PlobbyApp({super.key});
  @override
  ConsumerState<PlobbyApp> createState() => _PlobbyAppState();
}

/// Modo claro/oscuro según la preferencia del usuario ([ThemePrefs]: oscuro por defecto; «Como el sistema» sigue al
/// sistema). Los colores de Plobby son getters que leen [AppColors.isDark], así que al
/// cambiar de modo se fija el valor y se reconstruye TODA la app (clave distinta): ningún widget se queda con el color
/// anterior. La ruta actual no se pierde (el router vive en Riverpod).
class _PlobbyAppState extends ConsumerState<PlobbyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemePrefs.notifier.addListener(_onPref);
    _sync();
  }

  void _onPref() { if (_sync()) setState(() {}); }

  @override
  void dispose() { ThemePrefs.notifier.removeListener(_onPref); WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  void didChangePlatformBrightness() { if (_sync()) setState(() {}); }

  /// Devuelve true si el modo ha cambiado.
  bool _sync() {
    final dark = ThemePrefs.isDark(WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    if (dark == AppColors.isDark) return false;
    AppColors.isDark = dark;
    return true;
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: ValueKey(AppColors.isDark), child: MaterialApp.router(
      title: 'Plobby', theme: buildPlobbyTheme(), routerConfig: ref.watch(routerProvider), debugShowCheckedModeBanner: false,
      // Sincronización en vivo y avisos emergentes en cualquier pantalla (no solo en las pestañas).
      builder: (_, child) => LoadingBar(child: WideFrame(child: LiveSync(child: child ?? const SizedBox.shrink())))));
}
