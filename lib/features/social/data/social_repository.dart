import '../domain/social_models.dart';

/// Contrato de datos sociales. Implementación real: [SupabaseSocialRepository] (RPCs de la migración
/// `20261112_home_social.sql`). Todas las mutaciones pasan por RPC `security definer`; el cliente
/// jamás escribe en `friendships` ni en tablas de rating.
/// Qué ha cambiado: solicitudes, notificaciones, amistades (alta/baja) o todo (tras recuperar la conexión).
enum SocialChange { requests, notifications, friendships, resync }

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
  /// Avisa de cambios sociales en el servidor (Supabase Realtime), con su tipo para refrescar solo lo afectado.
  Stream<SocialChange> changes();
  /// Número de amigos de cualquier jugador (RPC `friend_count`; la RLS de friendships solo deja leer las propias).
  Future<int> friendCount(String userId);
}
