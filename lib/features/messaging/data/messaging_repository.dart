import 'dart:typed_data';
import '../../matches/domain/match_lifecycle.dart';
import '../domain/messaging_models.dart';

/// Reglas (aplicadas en backend por RLS/RPC, no solo en UI):
///  - solo usuarios autenticados; solo miembros leen/envían; chat 1:1 solo entre amigos aceptados;
///  - grupos: create_group / update_group / add_group_members / remove_group_member / set_group_admin / leave_group (solo admins editan);
///  - tarjeta de partido: send_match_card (partido CONFIRMADO por los dos capitanes y el que comparte juega en él).
abstract class MessagingRepository {
  String get meId;
  Future<List<Conversation>> conversations();                       // orden: último mensaje desc.
  Future<Conversation?> conversation(String id);
  Future<String> openWith(String friendId);                         // RPC get_or_create_conversation
  Future<List<ChatMessage>> history(String conversationId, {DateTime? before, int limit = 40});
  Future<ChatMessage> send(String conversationId, String body, {MessageKind kind = MessageKind.text, String? refId});
  Future<void> markRead(String conversationId);
  /// Realtime (Supabase Realtime sobre `messages`, filtrado por conversación; RLS aplica también al canal).
  Stream<ChatMessage> watch(String conversationId);
  /// Mensajes entrantes de cualquier conversación (para el contador del Home).
  Stream<ChatMessage> watchIncoming();

  // ── grupos ──
  Future<String> createGroup({required String name, required List<String> memberIds, String? avatarId, Uint8List? avatarBytes});
  Future<List<GroupMember>> members(String conversationId);          // v_group_members
  Future<void> updateGroup(String conversationId, {String? name, String? avatarId, Uint8List? avatarBytes});
  Future<void> addMembers(String conversationId, List<String> userIds);
  Future<void> removeMember(String conversationId, String userId);
  Future<void> setAdmin(String conversationId, String userId, bool admin);
  Future<void> leaveGroup(String conversationId);
  /// Cambios de grupo (nombre, foto, miembros) en tiempo real.
  Stream<String> watchGroupChanges();

  // ── tarjetas de partido ──
  /// Partidos del usuario FINALIZADOS Y CONFIRMADOS (los únicos compartibles), más recientes primero.
  Future<List<LifecycleMatch>> shareableMatches();
  /// RPC send_match_card: el servidor valida estado/participación y construye el snapshot; el cliente solo pasa el id.
  Future<ChatMessage> sendMatchCard(String conversationId, String matchId);
}
