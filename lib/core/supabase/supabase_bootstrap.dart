import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';
import '../router/app_router.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/data/supabase_auth_repository.dart';
import '../../features/feed/application/feed_providers.dart';
import '../../features/feed/data/supabase_feed_repository.dart';
import '../../features/leagues/application/league_providers.dart';
import '../../features/leagues/data/supabase_league_repository.dart';
import '../../features/matches/application/lifecycle_providers.dart';
import '../../features/matches/application/match_providers.dart';
import '../../features/matches/data/supabase_lifecycle_repository.dart';
import '../../features/matches/data/supabase_match_repository.dart';
import '../../features/messaging/application/messaging_providers.dart';
import '../../features/messaging/data/supabase_messaging_repository.dart';
import '../../features/profile/application/profile_providers.dart';
import '../../features/profile/data/supabase_profile_repository.dart';
import '../../features/rating/application/rating_providers.dart';
import '../../features/rating/data/supabase_rating_repository.dart';
import '../../features/social/application/social_providers.dart';
import '../../features/social/data/supabase_social_repository.dart';

/// Punto único de conexión con Supabase.
///
/// · Credenciales: SOLO `--dart-define` / `--dart-define-from-file=env.json` (ver [Env]); `env.json` está en .gitignore.
/// · Sin credenciales la app arranca en modo demo con los repositorios MOCK (útil para diseño y tests).
/// · Con credenciales: cliente oficial `supabase_flutter`, sesión persistente y todos los repositorios reales.
class SupabaseBootstrap {
  SupabaseBootstrap._();

  /// Inicializa el cliente si hay credenciales. Devuelve null en modo demo.
  static Future<SupabaseClient?> init() async {
    if (!Env.hasSupabase) return null;
    await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabasePublishableKey);
    return Supabase.instance.client;
  }

  /// Sustituye cada `*RepositoryProvider` mock por su implementación real. La UI no cambia.
  static List<Override> overrides(SupabaseClient c) => [
        authGuardEnabledProvider.overrideWithValue(true),
        currentUserIdProvider.overrideWithValue(c.auth.currentUser?.id ?? ''),
        authRepositoryProvider.overrideWithValue(SupabaseAuthRepository(c)),
        profileRepositoryProvider.overrideWithValue(SupabaseProfileRepository(c)),
        feedRepositoryProvider.overrideWithValue(SupabaseFeedRepository(c)),
        socialRepositoryProvider.overrideWithValue(SupabaseSocialRepository(c)),
        ratingRepositoryProvider.overrideWithValue(SupabaseRatingRepository(c)),
        matchRepositoryProvider.overrideWithValue(SupabaseMatchRepository(c)),
        lifecycleRepositoryProvider.overrideWithValue(SupabaseLifecycleRepository(c)),
        leagueRepositoryProvider.overrideWithValue(SupabaseLeagueRepository(c)),
        messagingRepositoryProvider.overrideWith((ref) => SupabaseMessagingRepository(c, confirmed: () => ref.read(lifecycleRepositoryProvider).confirmedMatches())),
      ];
}

/// Raíz con Supabase: recrea el [ProviderScope] cuando cambia el usuario de la sesión (login, logout, cambio de cuenta),
/// así ningún dato en caché de un usuario se muestra a otro.
class SupabaseSessionScope extends StatefulWidget {
  const SupabaseSessionScope({super.key, required this.client, required this.child});
  final SupabaseClient client;
  final Widget child;
  @override
  State<SupabaseSessionScope> createState() => _SupabaseSessionScopeState();
}

class _SupabaseSessionScopeState extends State<SupabaseSessionScope> {
  late String? _uid = widget.client.auth.currentUser?.id;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.client.auth.onAuthStateChange.listen((s) {
      final uid = s.session?.user.id;
      if (uid != _uid && mounted) setState(() => _uid = uid);
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) =>
      ProviderScope(key: ValueKey(_uid ?? 'signed-out'), overrides: SupabaseBootstrap.overrides(widget.client), child: widget.child);
}
