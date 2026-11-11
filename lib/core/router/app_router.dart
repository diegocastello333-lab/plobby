import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/feed/presentation/feed_screen.dart';
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
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/rating/presentation/elo_detail_screen.dart';
import '../../features/share_stats/presentation/share_stats_screen.dart';
import '../../features/social/presentation/add_friends_screen.dart';
import '../../features/social/presentation/friends_screen.dart';

/// Si el proyecto ya tiene un GoRouter, añade solo estas rutas (no sustituyas el existente).
final appRouter = GoRouter(initialLocation: '/feed', routes: [
  GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
  GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
  GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen(),
      routes: [GoRoute(path: 'share', builder: (_, __) => const ShareStatsScreen())]),
  GoRoute(path: '/player/:id', builder: (_, s) => ProfileScreen(playerId: s.pathParameters['id']!)),
  GoRoute(path: '/friends', builder: (_, __) => const FriendsScreen(), routes: [
    GoRoute(path: 'add', builder: (_, __) => const AddFriendsScreen()),
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
  GoRoute(path: '/onboarding', builder: (c, __) => OnboardingScreen(onDone: () => GoRouter.of(c).go('/feed'))),
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
  // '/leagues/:id': pantalla existente del proyecto; conecta aquí su ruta.
]);

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
  final onAuth = location == '/welcome', onOnb = location == '/onboarding';
  if (!signedIn) return onAuth ? null : '/welcome';
  if (!onboardingDone) return onOnb ? null : '/onboarding';
  if (onAuth || onOnb) return '/feed';
  return null;
}
