import 'dart:typed_data';
import '../../social/domain/social_models.dart';

enum MessageKind { text, invite, match, league, profile, system }
enum MessageStatus { sending, sent, read, failed }
enum ConversationKind { direct, group }
enum GroupRole { member, admin }

class ChatMessage {
  final String id, conversationId, senderId;
  final MessageKind kind;
  final String body;               // texto o descripción de la tarjeta
  final String? refId;             // id de partido / liga / perfil compartido
  /// Snapshot de la tarjeta de partido tal como lo devuelve el servidor (`get_match_recap`). Se conserva en el
  /// historial aunque el partido sea antiguo; `refId` enlaza al partido vivo para abrir el detalle.
  final Map<String, dynamic>? payload;
  final DateTime createdAt;
  final MessageStatus status;
  const ChatMessage({required this.id, required this.conversationId, required this.senderId, this.kind = MessageKind.text, required this.body, this.refId, this.payload, required this.createdAt, this.status = MessageStatus.sent});
  ChatMessage copyWith({MessageStatus? status}) => ChatMessage(id: id, conversationId: conversationId, senderId: senderId, kind: kind, body: body, refId: refId, payload: payload, createdAt: createdAt, status: status ?? this.status);
}

class GroupMember {
  const GroupMember({required this.id, required this.name, this.username = '', this.avatarUrl, this.avatarId, this.role = GroupRole.member, required this.joinedAt});
  final String id, name, username;
  final String? avatarUrl, avatarId;
  final GroupRole role;
  final DateTime joinedAt;
  bool get isAdmin => role == GroupRole.admin;
  String get initials => name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join().toUpperCase();
  GroupMember withRole(GroupRole r) => GroupMember(id: id, name: name, username: username, avatarUrl: avatarUrl, avatarId: avatarId, role: r, joinedAt: joinedAt);
}

class Conversation {
  final String id;
  final ConversationKind kind;
  final PlayerSummary? other;               // solo en chats directos
  final String? groupName, groupAvatarUrl, groupAvatarId;
  final Uint8List? groupAvatarBytes;        // solo el mock (en Supabase la foto vive en Storage → groupAvatarUrl)
  final int memberCount;
  final ChatMessage? last;
  final String? lastSenderName;
  final int unread;
  const Conversation({required this.id, this.kind = ConversationKind.direct, this.other, this.groupName, this.groupAvatarUrl, this.groupAvatarId, this.groupAvatarBytes, this.memberCount = 2, this.last, this.lastSenderName, this.unread = 0});
  bool get isGroup => kind == ConversationKind.group;
  String get title => isGroup ? (groupName ?? 'Grupo') : (other?.name ?? 'Chat');
  /// Texto de la lista de conversaciones: en grupos antepone quién escribió el último mensaje.
  String get preview {
    final m = last;
    if (m == null) return 'Sin mensajes';
    final txt = switch (m.kind) {
      MessageKind.match => '🏆 Resultado de partido',
      MessageKind.invite => '🎾 Invitación a jugar',
      MessageKind.league => '🏅 Liga compartida',
      MessageKind.profile => '👤 Perfil compartido',
      _ => m.body,
    };
    return isGroup && m.kind != MessageKind.system && lastSenderName != null ? '$lastSenderName: $txt' : txt;
  }
}

class MessagingException implements Exception {
  MessagingException(this.code);
  final String code;
  @override
  String toString() => 'MessagingException($code)';
}

/// Reglas de grupo. ESPEJO de las funciones SQL (20261117_messaging_groups.sql): sirven para mostrar/ocultar acciones y
/// para el mock; la autoridad real es el servidor.
class GroupPerms {
  const GroupPerms(this.members, this.me);
  final List<GroupMember> members; final String me;
  GroupMember? get self { for (final m in members) { if (m.id == me) return m; } return null; }
  bool get isMember => self != null;
  bool get isAdmin => self?.isAdmin ?? false;
  int get adminCount => members.where((m) => m.isAdmin).length;
  bool get canEdit => isAdmin;                    // nombre y foto
  bool get canAdd => isAdmin;
  bool canRemove(GroupMember t) => isAdmin && t.id != me && !t.isAdmin;       // un admin no expulsa a otro admin sin degradarlo antes
  bool canPromote(GroupMember t) => isAdmin && !t.isAdmin;
  bool canDemote(GroupMember t) => isAdmin && t.isAdmin && adminCount > 1;    // siempre queda un admin
  bool get canLeave => isMember;
}

const maxGroupName = 60, maxGroupMembers = 50;

/// Validación del formulario «Nuevo grupo» (misma que `create_group`). null = válido.
String? validateGroupDraft({required String name, required int selected}) {
  final n = name.trim();
  if (n.isEmpty) return 'Ponle un nombre al grupo';
  if (n.length > maxGroupName) return 'El nombre admite hasta $maxGroupName caracteres';
  if (selected < 1) return 'Elige al menos un amigo';
  if (selected + 1 > maxGroupMembers) return 'Un grupo admite hasta $maxGroupMembers participantes';
  return null;
}
