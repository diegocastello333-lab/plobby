import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_social_repository.dart';
import '../data/social_repository.dart';
import '../domain/social_models.dart';
import '../../feed/application/feed_providers.dart' show notificationsProvider;

final socialRepositoryProvider = Provider<SocialRepository>((ref) => MockSocialRepository());

class FriendsNotifier extends AsyncNotifier<List<Friend>> {
  @override
  Future<List<Friend>> build() => ref.read(socialRepositoryProvider).friends();
  Future<void> remove(String userId) async {
    await ref.read(socialRepositoryProvider).removeFriend(userId);
    ref.invalidateSelf();
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
final socialChangesProvider = StreamProvider<void>((ref) => ref.watch(socialRepositoryProvider).changes());

/// Refresca todo lo social tras un cambio hecho aquí o en el otro dispositivo.
void refreshSocial(WidgetRef ref) {
  ref.invalidate(friendsProvider);
  ref.invalidate(requestsProvider);
  ref.invalidate(suggestionsProvider);
  ref.invalidate(addFriendsSearchProvider);
  ref.invalidate(notificationsProvider);
}
