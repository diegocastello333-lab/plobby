import 'dart:async';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../../social/domain/social_models.dart';
import '../domain/messaging_models.dart';
import 'messaging_repository.dart';

/// Integración Supabase (SIN verificar contra una base real). Realtime: los canales respetan RLS, así que solo llegan
/// mensajes/cambios de conversaciones en las que el usuario es miembro. Requiere la migración 20261117_messaging_groups.sql.
class SupabaseMessagingRepository implements MessagingRepository {
  SupabaseMessagingRepository(this._db, {required this.confirmed});
  final SupabaseClient _db;
  /// `lifecycleRepository.confirmedMatches` — misma fuente que el resto de la app.
  final Future<List<LifecycleMatch>> Function() confirmed;
  @override
  String get meId => _db.auth.currentUser!.id;

  MessageKind _kind(String? k) => MessageKind.values.asNameMap()[k] ?? MessageKind.text;

  ChatMessage _msg(Map<String, dynamic> j) => ChatMessage(
        id: j['id'], conversationId: j['conversation_id'], senderId: j['sender_id'] ?? '',
        kind: _kind(j['kind']), body: j['body'] ?? '', refId: j['ref_id'], payload: (j['payload'] as Map?)?.cast<String, dynamic>(),
        createdAt: DateTime.parse(j['created_at']).toLocal(),
        status: j['read_at'] != null ? MessageStatus.read : MessageStatus.sent,
      );

  MessagingException _map(Object e) {
    if (e is PostgrestException) {
      for (final k in ['recap_not_confirmed', 'recap_not_participant', 'not_group_admin', 'last_admin', 'demote_admin_first', 'only_friends_allowed', 'not_a_member', 'invalid_group_name', 'too_many_members']) {
        if (e.message.contains(k)) return MessagingException(k);
      }
      return MessagingException('server');
    }
    return MessagingException('network');
  }

  Conversation _conv(Map<String, dynamic> r) {
    final group = r['kind'] == 'group';
    return Conversation(
      id: r['conversation_id'], kind: group ? ConversationKind.group : ConversationKind.direct,
      other: group ? null : PlayerSummary(id: r['other_id'], name: r['other_name'] ?? '', username: r['other_username'] ?? '', avatarUrl: r['other_avatar'], elo: r['other_elo'], level: r['other_level']),
      groupName: r['group_name'], groupAvatarUrl: r['group_avatar_url'], groupAvatarId: r['group_avatar_id'], memberCount: r['member_count'] ?? 2,
      last: r['last_body'] == null ? null : ChatMessage(id: 'last', conversationId: r['conversation_id'], senderId: r['last_sender'] ?? '', body: r['last_body'], kind: _kind(r['last_kind']), createdAt: DateTime.parse(r['last_message_at']).toLocal()),
      lastSenderName: r['last_sender_name'], unread: r['unread'] ?? 0,
    );
  }

  @override
  Future<List<Conversation>> conversations() async {
    final rows = await _db.from('v_my_conversations').select().order('last_message_at', ascending: false);
    return [for (final r in rows as List) _conv(r as Map<String, dynamic>)];
  }

  @override
  Future<Conversation?> conversation(String id) async {
    final r = await _db.from('v_my_conversations').select().eq('conversation_id', id).maybeSingle();
    return r == null ? null : _conv(r);
  }

  @override
  Future<String> openWith(String friendId) async => (await _db.rpc('get_or_create_conversation', params: {'friend': friendId})) as String;

  @override
  Future<List<ChatMessage>> history(String c, {DateTime? before, int limit = 40}) async {
    var q = _db.from('messages').select().eq('conversation_id', c);
    if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return (rows as List).map((r) => _msg(r as Map<String, dynamic>)).toList().reversed.toList();
  }

  @override
  Future<ChatMessage> send(String c, String body, {MessageKind kind = MessageKind.text, String? refId}) async {
    try {
      final r = await _db.rpc('send_message', params: {'conv': c, 'body_in': body, 'kind_in': kind.name, 'ref_in': refId});
      return _msg(r as Map<String, dynamic>);
    } catch (e) { throw _map(e); }
  }

  @override
  Future<void> markRead(String c) => _db.rpc('mark_conversation_read', params: {'conv': c});

  // ── grupos ──
  /// Sube la foto al bucket `group-avatars` (ruta `<conversation_id>/avatar.jpg`) y devuelve su URL firmada de larga duración.
  Future<String> _upload(String convId, Uint8List bytes) async {
    final path = '$convId/avatar.jpg';
    await _db.storage.from('group-avatars').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
    // versionada para que el caché de imagen se refresque al cambiar la foto
    return '${await _db.storage.from('group-avatars').createSignedUrl(path, 60 * 60 * 24 * 365)}&v=${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<String> createGroup({required String name, required List<String> memberIds, String? avatarId, Uint8List? avatarBytes}) async {
    try {
      final id = (await _db.rpc('create_group', params: {'p_name': name, 'p_member_ids': memberIds, 'p_avatar_id': avatarBytes == null ? avatarId : null})) as String;
      if (avatarBytes != null) await _db.rpc('update_group', params: {'conv': id, 'p_patch': {'avatar_url': await _upload(id, avatarBytes)}});
      return id;
    } catch (e) { throw _map(e); }
  }

  @override
  Future<List<GroupMember>> members(String c) async {
    final rows = await _db.from('v_group_members').select().eq('conversation_id', c).order('joined_at');
    return [
      for (final r in rows as List)
        GroupMember(id: r['user_id'], name: r['display_name'] ?? '', username: r['username'] ?? '', avatarUrl: r['avatar_url'], avatarId: r['avatar_id'],
            role: r['role'] == 'admin' ? GroupRole.admin : GroupRole.member, joinedAt: DateTime.parse(r['joined_at']).toLocal()),
    ];
  }

  @override
  Future<void> updateGroup(String c, {String? name, String? avatarId, Uint8List? avatarBytes}) async {
    try {
      final patch = <String, dynamic>{if (name != null) 'name': name};
      if (avatarBytes != null) { patch['avatar_url'] = await _upload(c, avatarBytes); }
      else if (avatarId != null) { patch['avatar_id'] = avatarId; patch['avatar_url'] = null; }
      await _db.rpc('update_group', params: {'conv': c, 'p_patch': patch});
    } catch (e) { throw _map(e); }
  }

  @override
  Future<void> addMembers(String c, List<String> ids) async { try { await _db.rpc('add_group_members', params: {'conv': c, 'p_member_ids': ids}); } catch (e) { throw _map(e); } }
  @override
  Future<void> removeMember(String c, String u) async { try { await _db.rpc('remove_group_member', params: {'conv': c, 'p_user': u}); } catch (e) { throw _map(e); } }
  @override
  Future<void> setAdmin(String c, String u, bool admin) async { try { await _db.rpc('set_group_admin', params: {'conv': c, 'p_user': u, 'p_admin': admin}); } catch (e) { throw _map(e); } }
  @override
  Future<void> leaveGroup(String c) async { try { await _db.rpc('leave_group', params: {'conv': c}); } catch (e) { throw _map(e); } }

  // ── tarjetas de partido ──
  @override
  Future<List<LifecycleMatch>> shareableMatches() => confirmed();

  @override
  Future<ChatMessage> sendMatchCard(String c, String matchId) async {
    try {
      return _msg((await _db.rpc('send_match_card', params: {'conv': c, 'p_match_id': matchId})) as Map<String, dynamic>);
    } catch (e) { throw _map(e); }
  }

  // ── realtime ──
  @override
  Stream<ChatMessage> watch(String c) {
    final ctl = StreamController<ChatMessage>();
    final ch = _db.channel('chat:$c').onPostgresChanges(
      event: PostgresChangeEvent.insert, schema: 'public', table: 'messages',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: c),
      callback: (p) => ctl.add(_msg(p.newRecord)),
    )..subscribe();
    ctl.onCancel = () { _db.removeChannel(ch); ctl.close(); };
    return ctl.stream;
  }

  /// Mensajes entrantes de TODAS mis conversaciones (lista, badge, notificaciones locales). Se excluyen los míos y los de sistema.
  @override
  Stream<ChatMessage> watchIncoming() {
    final ctl = StreamController<ChatMessage>();
    final ch = _db.channel('inbox:$meId').onPostgresChanges(
      event: PostgresChangeEvent.insert, schema: 'public', table: 'messages',
      callback: (p) { final m = _msg(p.newRecord); if (m.senderId != meId && m.kind != MessageKind.system) ctl.add(m); },
    )..subscribe();
    ctl.onCancel = () { _db.removeChannel(ch); ctl.close(); };
    return ctl.stream;
  }

  /// Cambios de grupo: nombre/foto (conversations) y altas/bajas/roles (conversation_members). Emite el id de la conversación.
  @override
  Stream<String> watchGroupChanges() {
    final ctl = StreamController<String>();
    final ch = _db.channel('groups:$meId')
      ..onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'conversations', callback: (p) => ctl.add(p.newRecord['id'] as String))
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'conversation_members', callback: (p) {
        final r = p.eventType == PostgresChangeEvent.delete ? p.oldRecord : p.newRecord;
        final id = r['conversation_id'] as String?; if (id != null) ctl.add(id);
      })
      ..subscribe();
    ctl.onCancel = () { _db.removeChannel(ch); ctl.close(); };
    return ctl.stream;
  }
}
