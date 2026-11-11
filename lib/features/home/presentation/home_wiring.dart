import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../feed/application/feed_providers.dart';
import '../../messaging/application/messaging_providers.dart';
import '../../profile/application/profile_providers.dart';
import '../../rating/application/rating_providers.dart';
import '../../social/application/social_providers.dart';
import '../../matches/presentation/new_match_menu.dart';
import 'streak_sheet.dart';

/// Valores REALES que alimentan el Home (ninguno está fijado en el widget):
///  amigos → friendsProvider, ELO/delta → myRatingProvider (backend), racha → profileViewProvider('me'),
///  avisos → notificationsProvider, mensajes → conversationsProvider.
class HomeCounters {
  const HomeCounters({this.friends = 0, this.elo, this.delta30, this.streak = 0, this.bestStreak = 0, this.unreadNotifications = 0, this.unreadMessages = 0});
  final int friends, streak, bestStreak, unreadNotifications, unreadMessages;
  final int? elo, delta30;
}

final homeCountersProvider = Provider<HomeCounters>((ref) {
  final r = ref.watch(myRatingProvider).valueOrNull;
  final s = ref.watch(profileViewProvider('me')).valueOrNull?.streak;
  return HomeCounters(
    friends: ref.watch(friendCountProvider),
    elo: r?.elo, delta30: r?.delta30,
    streak: s?.current ?? 0, bestStreak: s?.best ?? 0,
    unreadNotifications: ref.watch(unreadCountProvider),
    unreadMessages: ref.watch(unreadMessagesProvider),
  );
});

/// Úsalos SIN cambiar el diseño del Home: solo sustituye los `onTap` y los textos fijos.
/// Ejemplo de integración en el Home existente:
///
///   final c = ref.watch(homeCountersProvider);
///   _FriendsCard(count: c.friends, onTap: () => context.push('/friends'))
///   _EloCard(elo: c.elo, delta: c.delta30, onTap: () => context.push('/rating'))
///   _StreakCard(streak: c.streak, onTap: () => showStreakSheet(context, current: c.streak, best: c.bestStreak))
///   // cabecera: reemplaza el logo anterior por `const PlobbyLogo(markHeight: 30)` (lib/core/widgets/plobby_logo.dart)
///   // botón «+»: onPressed: () => HomeNav.newMatch(context)
///   HomeIconButton(icon: Icons.person_add_alt_1, label: 'Añadir amigos', onTap: () => context.push('/friends/add'))
///   HomeIconButton(icon: Icons.notifications_none, label: 'Notificaciones', badge: c.unreadNotifications, onTap: () => context.push('/notifications'))
///   HomeIconButton(icon: Icons.send_outlined, label: 'Mensajes', badge: c.unreadMessages, onTap: () => context.push('/messages'))
class HomeIconButton extends StatelessWidget {
  const HomeIconButton({super.key, required this.icon, required this.label, required this.onTap, this.badge = 0});
  final IconData icon; final String label; final VoidCallback onTap; final int badge;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: badge > 0 ? '$label, $badge sin leer' : label,
        child: IconButton(
          onPressed: onTap,
          icon: Badge(isLabelVisible: badge > 0, label: Text(badge > 99 ? '99+' : '$badge'), child: Icon(icon)),
        ),
      );
}

/// Atajos de navegación del Home (auditoría de botones): todos llevan a una pantalla real.
class HomeNav {
  static void newMatch(BuildContext c) => showNewMatchMenu(c); // botón «+»: menú liga / amistoso
  static void friends(BuildContext c) => c.push('/friends');
  static void addFriends(BuildContext c) => c.push('/friends/add');
  static void elo(BuildContext c) => c.push('/rating');
  static void notifications(BuildContext c) => c.push('/notifications');
  static void messages(BuildContext c) => c.push('/messages');
  static void profile(BuildContext c) => c.go('/profile');
  static void match(BuildContext c, String id) => c.push('/match/$id');
  static void seeAllFriendMatches(BuildContext c) => c.go('/feed'); // filtro "Partidos"
  static void seeAllMyMatches(BuildContext c) => c.go('/profile'); // pestaña Partidos
  static void seeAllAchievements(BuildContext c) => c.go('/profile'); // pestaña Estadísticas/Logros
  static void streak(BuildContext c, HomeCounters h) => showStreakSheet(c, current: h.streak, best: h.bestStreak);
}
