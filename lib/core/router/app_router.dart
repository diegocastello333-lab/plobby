import '../../features/gamification/presentation/wrapped_screens.dart';
import '../../features/gamification/presentation/head_to_head_screen.dart';
import '../../features/gamification/presentation/friends_ranking_screen.dart';
import '../../features/gamification/presentation/achievements_screen.dart';
import '../../features/gamification/domain/gamification_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/leagues/presentation/create_league_screen.dart';
import '../../features/leagues/presentation/discover_leagues_screen.dart';
import '../../features/leagues/presentation/league_detail_screen.dart';
import '../../features/leagues/presentation/leagues_screen.dart';
import '../../features/tournaments/presentation/competitions_screen.dart';
import '../../features/tournaments/presentation/create_tournament_screen.dart';
import '../../features/tournaments/presentation/tournament_detail_screen.dart';
import '../../features/leagues/presentation/manage_league_screen.dart';
import 'app_shell.dart';
import '../../features/feed/presentation/notifications_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/matches/domain/match_models.dart';
import '../../features/matches/presentation/final_result_screen.dart';
import '../../features/match_recap/presentation/share_match_screen.dart';
import '../../features/matches/presentation/match_detail_screen.dart';
import '../../features/matches/presentation/result_entry_screen.dart';
import '../../features/matches/presentation/create_match_screen.dart';
import '../../features/messaging/application/messaging_providers.dart';
import '../../features/messaging/presentation/chat_screen.dart';
import '../../features/messaging/presentation/conversations_screen.dart';
import '../../features/messaging/presentation/group_info_screen.dart';
import '../../features/messaging/presentation/new_group_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/rating/presentation/elo_detail_screen.dart';
import '../../features/share_stats/presentation/share_stats_screen.dart';
import '../../features/social/presentation/add_friends_screen.dart';
import '../../features/social/presentation/friends_screen.dart';
import '../../features/splash/application/splash_boot.dart';
import '../../features/splash/presentation/splash_screen.dart';

/// true cuando la app usa Supabase (lo activa `SupabaseBootstrap.overrides`): sin sesión → /welcome, sin onboarding → /onboarding.
/// En modo demo (mocks) se entra directamente al Inicio.
final authGuardEnabledProvider = Provider<bool>((ref) => false);

/// Estado de acceso para la guardia: sesión + onboarding completado (RPC get_my_profile vía AuthRepository.loadOnboarding).
final sessionGateProvider = FutureProvider<({bool signedIn, bool onboarded})>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return (signedIn: false, onboarded: false);
  final d = await ref.read(authRepositoryProvider).loadOnboarding();
  return (signedIn: true, onboarded: d.completed);
});

/// Router único. Las 4 pestañas (Inicio, Feed, Competiciones, Perfil) viven en un `StatefulShellRoute` con la barra inferior;
/// el resto de pantallas se abren a pantalla completa por encima.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionGateProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    // Primer arranque: pantalla de carga. Si el router se recrea (inicio/cierre de sesión), directamente al Inicio.
    initialLocation: SplashBoot.consume() ? '/splash' : '/home',
    refreshListenable: refresh,
    redirect: (_, state) {
      if (!ref.read(authGuardEnabledProvider)) return null;
      final gate = ref.read(sessionGateProvider);
      if (!gate.hasValue) {
        // Mientras se lee el perfil: sin sesión guardada se va directo a /welcome (sin pedir datos protegidos);
        // con sesión se espera al valor y la guardia se re-evalúa.
        final signedIn = ref.read(authRepositoryProvider).currentUser != null;
        return signedIn ? null : authRedirect(signedIn: false, onboardingDone: false, location: state.matchedLocation);
      }
      return authRedirect(signedIn: gate.value!.signedIn, onboardingDone: gate.value!.onboarded, location: state.matchedLocation);
    },
    routes: appRoutes,
  );
});

final appRoutes = <RouteBase>[
  // Pantalla de carga (solo al abrir la app). Al terminar sustituye la ruta por /home y la guardia decide el destino.
  GoRoute(path: '/splash', pageBuilder: (_, s) => NoTransitionPage(key: s.pageKey, child: const _SplashRoute())),
  StatefulShellRoute.indexedStack(
    builder: (_, __, shell) => AppShell(shell: shell),
    branches: [
      StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
      StatefulShellBranch(routes: [GoRoute(path: '/feed', builder: (_, __) => const FeedScreen())]),
      // Pestaña «Competiciones» (Ligas | Torneos). Misma ruta /leagues que antes: los enlaces de ligas siguen valiendo.
      StatefulShellBranch(routes: [GoRoute(path: '/leagues', builder: (_, __) => const CompetitionsScreen())]),
      StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen(),
          routes: [GoRoute(path: 'share', builder: (_, __) => const ShareStatsScreen())])]),
    ],
  ),
  // Editar perfil a pantalla completa (fuera de la barra inferior). '/profile' (pestaña) no tiene hijo 'edit', así que
  // GoRouter sigue buscando y encuentra esta ruta.
  GoRoute(path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
  // Gamificación: Head to Head, ranking entre amigos, Wrapped y logros (fuera de la barra inferior).
  GoRoute(path: '/h2h/:id', builder: (_, s) => HeadToHeadScreen(otherId: s.pathParameters['id']!)),
  GoRoute(path: '/ranking', builder: (_, __) => const FriendsRankingScreen()),
  GoRoute(path: '/achievements', builder: (_, __) => const AchievementsScreen()),
  GoRoute(path: '/wrapped', builder: (_, __) => const WrappedListScreen(), routes: [
    GoRoute(path: ':kind/:start', pageBuilder: (_, s) => MaterialPage(fullscreenDialog: true, key: s.pageKey, child: WrappedStoryScreen(
        kind: WrappedKind.values.byName(s.pathParameters['kind']!), start: DateTime.parse('${s.pathParameters['start']}-01')))),
  ]),
  GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
  GoRoute(path: '/player/:id', builder: (_, s) => ProfileScreen(playerId: s.pathParameters['id']!)),
  GoRoute(path: '/friends', builder: (_, __) => const FriendsScreen(), routes: [
    GoRoute(path: 'add', builder: (_, __) => const AddFriendsScreen()),
    // Amigos como selector (jugadores de un partido, pareja habitual). Devuelve List<PlayerOption> con `pop`.
    GoRoute(path: 'pick', builder: (_, s) => FriendsScreen(pick: s.extra is FriendPick ? s.extra as FriendPick : const FriendPick(title: 'Elige amigos'))),
  ]),
  // Formulario único de partido: /match/new?type=league|friendly (+ leagueId&result=1 desde una liga). Declarar antes de '/match/:id'.
  GoRoute(path: '/match/new', builder: (_, s) => CreateMatchScreen(
      type: s.uri.queryParameters['type'] == 'friendly' ? MatchType.friendly : MatchType.league,
      leagueId: s.uri.queryParameters['leagueId'], resultRequired: s.uri.queryParameters['result'] == '1')),
  // Ciclo del partido (detalle → resultado → confirmación → resultado final). '/match/new' va ANTES de '/match/:id'.
  GoRoute(path: '/match/:id', builder: (_, s) => MatchDetailScreen(matchId: s.pathParameters['id']!), routes: [
    GoRoute(path: 'result', builder: (_, s) => ResultEntryScreen(matchId: s.pathParameters['id']!)),
    GoRoute(path: 'final', builder: (_, s) => FinalResultScreen(matchId: s.pathParameters['id']!)),
    GoRoute(path: 'share', builder: (_, s) => ShareMatchScreen(matchId: s.pathParameters['id']!)),
  ]),
  GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
  GoRoute(path: '/onboarding', builder: (c, __) => OnboardingScreen(onDone: () {
    ProviderScope.containerOf(c, listen: false).invalidate(sessionGateProvider);   // la guardia vuelve a leer el perfil ya completo
    GoRouter.of(c).go('/home');
  })),
  GoRoute(path: '/rating', builder: (_, __) => const EloDetailScreen()),
  GoRoute(path: '/messages', builder: (_, __) => const ConversationsScreen(), routes: [
    // abre (o crea) la conversación con un amigo; el backend rechaza si no sois amigos aceptados
    GoRoute(path: 'with/:friendId', builder: (_, s) => _OpenChat(friendId: s.pathParameters['friendId']!, invite: s.uri.queryParameters['invite'] == '1')),
    // literales ANTES que ':conversationId'
    GoRoute(path: 'group/new', builder: (_, __) => const NewGroupScreen()),
    GoRoute(path: ':conversationId', builder: (_, s) => ChatScreen(conversationId: s.pathParameters['conversationId']!, title: s.uri.queryParameters['name'] ?? 'Chat'), routes: [
      GoRoute(path: 'info', builder: (_, s) => GroupInfoScreen(conversationId: s.pathParameters['conversationId']!)),
    ]),
  ]),
  // Torneos (sistema independiente de Ligas). '/tournaments/new' ANTES que ':id'.
  GoRoute(path: '/tournaments/new', builder: (_, __) => const CreateTournamentScreen()),
  GoRoute(path: '/tournaments/:id', builder: (_, s) => TournamentDetailScreen(tournamentId: s.pathParameters['id']!)),
  // Ligas (literales ANTES que ':id')
  GoRoute(path: '/leagues/new', builder: (_, __) => const CreateLeagueScreen()),
  GoRoute(path: '/leagues/discover', builder: (_, __) => const DiscoverLeaguesScreen()),
  GoRoute(path: '/leagues/join', builder: (c, s) => _JoinByCodeRoute(code: s.uri.queryParameters['code'])),
  GoRoute(path: '/leagues/:id', builder: (_, s) => LeagueDetailScreen(leagueId: s.pathParameters['id']!,
      initialTab: LeagueTab.values.asNameMap()[s.uri.queryParameters['tab']] ?? LeagueTab.rank), routes: [
    GoRoute(path: 'created', builder: (_, s) => LeagueCreatedScreen(leagueId: s.pathParameters['id']!, code: s.uri.queryParameters['code'])),
    GoRoute(path: 'manage', builder: (_, s) => ManageLeagueScreen(leagueId: s.pathParameters['id']!)),
  ]),
];

/// Enlace de invitación `/leagues/join?code=XXXX`: abre Ligas con la hoja «Unirme con código» rellena.
class _JoinByCodeRoute extends StatefulWidget {
  const _JoinByCodeRoute({this.code});
  final String? code;
  @override
  State<_JoinByCodeRoute> createState() => _JoinByCodeRouteState();
}
class _JoinByCodeRouteState extends State<_JoinByCodeRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async { await showJoinByCodeSheet(context, initial: widget.code); if (mounted) context.pop(); });
  }
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

class _OpenChat extends ConsumerWidget {
  const _OpenChat({required this.friendId, required this.invite});
  final String friendId; final bool invite;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<String>(
        future: ref.read(messagingRepositoryProvider).openWith(friendId),
        builder: (_, s) => s.hasError
            ? const Scaffold(body: Center(child: Text('Solo puedes escribir a tus amigos')))
            : !s.hasData
                ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                : ChatScreen(conversationId: s.data!, title: friendId, otherId: friendId, startWithInvite: invite),
      );
}

/// Guardia de acceso para `GoRouter(redirect: …, refreshListenable: …)`. Pura y testeable:
/// sin sesión → /welcome; con sesión pero perfil sin completar → /onboarding; con todo listo no se vuelve a ver ninguna de las dos.
String? authRedirect({required bool signedIn, required bool onboardingDone, required String location}) {
  if (location == '/splash') return null; // la pantalla de carga se muestra siempre; navega ella al terminar
  final onAuth = location == '/welcome', onOnb = location == '/onboarding';
  if (!signedIn) return onAuth ? null : '/welcome';
  if (!onboardingDone) return onOnb ? null : '/onboarding';
  if (onAuth || onOnb) return '/home';
  return null;
}

/// Ruta de la pantalla de carga: lanza el trabajo crítico una sola vez y, al terminar la animación y ese trabajo
/// (o su límite de tiempo, o un error de red: la app sigue y cada pantalla muestra su estado), funde la marca y entra.
class _SplashRoute extends ConsumerStatefulWidget {
  const _SplashRoute();
  @override
  ConsumerState<_SplashRoute> createState() => _SplashRouteState();
}

class _SplashRouteState extends ConsumerState<_SplashRoute> {
  late final Future<void> _ready = SplashBoot.criticalWork(ref);
  bool _leaving = false;

  void _finish() {
    if (_leaving) return;
    setState(() => _leaving = true);
    // Salida: la marca se funde y crece ligeramente (260 ms) y se entra al Inicio sin pila (atrás no vuelve aquí).
    Future<void>.delayed(const Duration(milliseconds: 260), () { if (mounted) GoRouter.of(context).go('/home'); });
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFFD2F548),
        child: AnimatedOpacity(
          opacity: _leaving ? 0 : 1, duration: const Duration(milliseconds: 260), curve: Curves.easeIn,
          child: AnimatedScale(scale: _leaving ? 1.04 : 1, duration: const Duration(milliseconds: 260), curve: Curves.easeIn,
              child: SplashScreen(ready: _ready, onFinished: _finish)),
        ),
      );
}

