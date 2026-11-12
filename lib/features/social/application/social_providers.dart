import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_social_repository.dart';
import '../data/social_repository.dart';
export '../data/social_repository.dart' show SocialChange;
import '../domain/social_models.dart';
import '../../feed/application/feed_providers.dart' show notificationsProvider;
import '../../messaging/application/messaging_providers.dart' show conversationsProvider;
import '../../profile/application/profile_providers.dart' show profileProvider;

final socialRepositoryProvider = Provider<SocialRepository>((ref) => MockSocialRepository());

class FriendsNotifier extends AsyncNotifier<List<Friend>> {
  @override
  Future<List<Friend>> build() => ref.read(socialRepositoryProvider).friends();
  Future<void> remove(String userId) async {
    await ref.read(socialRepositoryProvider).removeFriend(userId);
    _invalidateSocial(ref.invalidate);   // la conversación privada y la pareja habitual también desaparecen
    await future;
  }
}
final friendsProvider = AsyncNotifierProvider<FriendsNotifier, List<Friend>>(FriendsNotifier.new);

/// Contador real para la tarjeta "Amigos" del Home (nada de números fijos).
final friendCountProvider = Provider<int>((ref) => ref.watch(friendsProvider).valueOrNull?.length ?? 0);

final friendSearchQueryProvider = StateProvider<String>((ref) => '');
final friendFilterProvider = Provider<AsyncValue<List<Friend>>>((ref) {
  final q = ref.watch(friendSearchQueryProvider).trim().toLowerCase();
  return ref.watch(friendsProvider).whenData((l) => q.isEmpty
      ? l
      : l.where((f) => f.player.name.toLowerCase().contains(q) || f.player.username.toLowerCase().contains(q)).toList());
});

class RequestsNotifier extends AsyncNotifier<FriendRequests> {
  SocialRepository get _repo => ref.read(socialRepositoryProvider);
  @override
  Future<FriendRequests> build() => _repo.requests();
  Future<void> send(String id) async { await _repo.sendRequest(id); await _refresh(); }
  Future<void> cancel(String reqId) async { await _repo.cancelRequest(reqId); await _refresh(); }
  Future<void> respond(String reqId, bool accept) async {
    await _repo.respondRequest(reqId, accept: accept);
    ref.invalidate(friendsProvider);
    ref.invalidate(notificationsProvider);   // la RPC marca leída la notificación de la solicitud
    await _refresh();
  }
  Future<void> _refresh() async { ref.invalidateSelf(); ref.invalidate(addFriendsSearchProvider); ref.invalidate(suggestionsProvider); await future; }
}
final requestsProvider = AsyncNotifierProvider<RequestsNotifier, FriendRequests>(RequestsNotifier.new);

final addFriendsQueryProvider = StateProvider<String>((ref) => '');
final addFriendsSearchProvider = FutureProvider<List<SearchHit>>((ref) async {
  final q = ref.watch(addFriendsQueryProvider);
  if (q.trim().isEmpty) return <SearchHit>[];
  return ref.read(socialRepositoryProvider).search(q);
});
final suggestionsProvider = FutureProvider<List<SearchHit>>((ref) => ref.read(socialRepositoryProvider).suggestions());

/// Cambios en vivo de solicitudes/notificaciones (Supabase Realtime). Quien lo escucha (la barra inferior, siempre
/// montada) refresca amigos, solicitudes y notificaciones: así el otro usuario ve la solicitud o la amistad al momento.
final socialChangesProvider = StreamProvider<SocialChange>((ref) => ref.watch(socialRepositoryProvider).changes());

/// Relación con un jugador calculada SIEMPRE a partir de la misma fuente (amigos + solicitudes): perfil, buscador y
/// selectores no pueden discrepar. Se recalcula sola cuando cambian esas listas (Realtime o acciones propias).
final relationProvider = Provider.family<RelationState, String>((ref, userId) {
  if (ref.watch(friendsProvider).valueOrNull?.any((f) => f.player.id == userId) ?? false) return RelationState.friend;
  final r = ref.watch(requestsProvider).valueOrNull;
  if (r?.outgoing.any((x) => x.player.id == userId) ?? false) return RelationState.requestSent;
  if (r?.incoming.any((x) => x.player.id == userId) ?? false) return RelationState.requestReceived;
  return RelationState.none;
});

/// Solicitud pendiente con ese jugador (para aceptar o cancelar desde su perfil).
final requestWithProvider = Provider.family<FriendRequest?, String>((ref, userId) {
  final r = ref.watch(requestsProvider).valueOrNull;
  return [...?r?.incoming, ...?r?.outgoing].where((x) => x.player.id == userId).firstOrNull;
});

/// Número de amigos de un perfil. El propio sale de la lista de amigos (se actualiza al instante); el de otro jugador,
/// de la RPC `friend_count`, que se vuelve a pedir con cada cambio social.
final friendCountOfProvider = FutureProvider.family<int, String>((ref, userId) async {
  final repo = ref.watch(socialRepositoryProvider);
  if (userId == 'me' || userId == repo.meId) return ref.watch(friendCountProvider);
  ref.watch(friendsProvider);   // si cambia mi lista (p. ej. nos hacemos amigos), también cambia su contador
  return repo.friendCount(userId);
});

void _invalidateSocial(void Function(ProviderOrFamily) invalidate) {
  for (final p in <ProviderOrFamily>[friendsProvider, requestsProvider, suggestionsProvider, addFriendsSearchProvider,
      notificationsProvider, friendCountOfProvider, conversationsProvider, profileProvider('me')]) {
    invalidate(p);
  }
}

/// Refresca todo lo social tras un cambio hecho aquí o en el otro dispositivo: amigos, solicitudes, avisos, contadores,
/// conversaciones (al dejar de ser amigos se cierra el chat privado) y el perfil propio (pareja habitual).
void refreshSocial(WidgetRef ref) => _invalidateSocial(ref.invalidate);

/// Refresco proporcional a lo que cambió (Realtime). Un mensaje nuevo solo actualiza su aviso: antes cada aviso
/// recargaba amigos, solicitudes, contadores y el perfil completo.
void applySocialChange(WidgetRef ref, SocialChange c) {
  switch (c) {
    case SocialChange.notifications:
      ref.invalidate(notificationsProvider);
    case SocialChange.requests:
      for (final p in <ProviderOrFamily>[requestsProvider, notificationsProvider, addFriendsSearchProvider, suggestionsProvider]) { ref.invalidate(p); }
    case SocialChange.friendships || SocialChange.resync:
      refreshSocial(ref);
  }
}
