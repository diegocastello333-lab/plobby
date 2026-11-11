import '../domain/social_models.dart';

/// Contrato de datos sociales. Implementación real: [SupabaseSocialRepository] (RPCs de la migración
/// `20261112_home_social.sql`). Todas las mutaciones pasan por RPC `security definer`; el cliente
/// jamás escribe en `friendships` ni en tablas de rating.
abstract class SocialRepository {
  String get meId;
  Future<List<Friend>> friends();
  Future<FriendRequests> requests();
  Future<List<SearchHit>> search(String query);        // excluye al propio usuario
  Future<List<SearchHit>> suggestions();                // amigos en común / ciudad / club / ELO similar
  Future<void> sendRequest(String userId);              // RPC send_friend_request (evita duplicados)
  Future<void> cancelRequest(String requestId);
  Future<void> respondRequest(String requestId, {required bool accept}); // RPC respond_friend_request
  Future<void> removeFriend(String userId);             // RPC remove_friend
}
