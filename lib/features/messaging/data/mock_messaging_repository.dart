import 'dart:async';
import 'dart:typed_data';
import '../../matches/domain/match_lifecycle.dart';
import '../../match_recap/domain/recap_data.dart';
import '../../social/domain/social_models.dart';
import '../domain/messaging_models.dart';
import 'messaging_repository.dart';

class _Conv {
  _Conv(this.id, this.kind, {this.name, this.avatarId, this.avatarBytes, this.direct});
  final String id; final ConversationKind kind;
  String? name, avatarId; Uint8List? avatarBytes;
  PlayerSummary? direct;
  final List<GroupMember> members = [];
}

/// DATOS MOCK: simula respuesta del amigo a los 2 s. Aplica las MISMAS reglas que las funciones SQL de
/// 20261117_messaging_groups.sql (para tests y desarrollo sin backend; la seguridad real está en RLS/RPC).
/// Sustituir por SupabaseMessagingRepository.
class MockMessagingRepository implements MessagingRepository {
  MockMessagingRepository({Set<String>? friends, Future<List<LifecycleMatch>> Function()? matches, DateTime Function()? now, Map<String, String>? names, this.autoReply = true})
      : friendIds = friends ?? {'marcos', 'lucia', 'alvaro', 'carla'}, _matches = matches, _now = now ?? DateTime.now,
        _names = {'me': 'Diego C.', 'marcos': 'Marcos R.', 'lucia': 'Lucía M.', 'alvaro': 'Álvaro T.', 'carla': 'Carla S.', ...?names} {
    final c = _Conv('c_marcos', ConversationKind.direct, direct: const PlayerSummary(id: 'marcos', name: 'Marcos R.', username: 'marcos.r', elo: 1455, level: 'Intermedio alto', online: true));
    _c[c.id] = c;
    _msgs[c.id] = [ChatMessage(id: '1', conversationId: c.id, senderId: 'marcos', body: '¿Jugamos el jueves a las 19:00?', createdAt: _now().subtract(const Duration(minutes: 12)))];
    _unread[c.id] = 1;
  }

  @override
  String get meId => 'me';
  final Set<String> friendIds;
  final bool autoReply;
  final DateTime Function() _now;
  final Future<List<LifecycleMatch>> Function()? _matches;
  final Map<String, String> _names;
  final _c = <String, _Conv>{};
  final _msgs = <String, List<ChatMessage>>{};
  final _unread = <String, int>{};
  final _ctl = StreamController<ChatMessage>.broadcast();
  final _grp = StreamController<String>.broadcast();
  int _seq = 0;

  _Conv _conv(String id) => _c[id] ?? (throw MessagingException('not_found'));
  _Conv _group(String id) { final c = _conv(id); if (c.kind != ConversationKind.group) throw MessagingException('not_a_group'); return c; }
  GroupPerms _perms(_Conv c) => GroupPerms(c.members, meId);
  _Conv _asMember(String id) { final c = _conv(id); if (c.kind == ConversationKind.group && !_perms(c).isMember) throw MessagingException('not_a_member'); return c; }
  GroupMember _mk(String id, GroupRole r) => GroupMember(id: id, name: _names[id] ?? id, username: id, role: r, joinedAt: _now().add(Duration(milliseconds: _seq++)));

  ChatMessage _post(String conv, String body, {MessageKind kind = MessageKind.text, String? ref, Map<String, dynamic>? payload, String? sender}) {
    final m = ChatMessage(id: 'm${_seq++}', conversationId: conv, senderId: sender ?? meId, kind: kind, body: body, refId: ref, payload: payload, createdAt: _now());
    (_msgs[conv] ??= []).add(m);
    return m;
  }

  @override
  Future<List<Conversation>> conversations() async {
    final l = <Conversation>[];
    for (final c in _c.values) {
      if (c.kind == ConversationKind.group && !_perms(c).isMember) continue;
      final last = (_msgs[c.id] ?? const []).isEmpty ? null : _msgs[c.id]!.last;
      l.add(Conversation(id: c.id, kind: c.kind, other: c.direct, groupName: c.name, groupAvatarId: c.avatarId, groupAvatarBytes: c.avatarBytes, memberCount: c.members.length,
          last: last, lastSenderName: last == null ? null : (last.senderId == meId ? 'Tú' : (_names[last.senderId] ?? '').split(' ').first), unread: _unread[c.id] ?? 0));
    }
    l.sort((a, b) => (b.last?.createdAt ?? DateTime(0)).compareTo(a.last?.createdAt ?? DateTime(0)));
    return l;
  }
  @override
  Future<Conversation?> conversation(String id) async { for (final c in await conversations()) { if (c.id == id) return c; } return null; }
  @override
  Future<String> openWith(String friendId) async {
    if (!friendIds.contains(friendId)) throw MessagingException('only_friends');
    final id = 'c_$friendId';
    _c.putIfAbsent(id, () => _Conv(id, ConversationKind.direct, direct: PlayerSummary(id: friendId, name: _names[friendId] ?? friendId, username: friendId, elo: 1400, level: 'Avanzado')));
    _msgs.putIfAbsent(id, () => []);
    return id;
  }
  @override
  Future<List<ChatMessage>> history(String c, {DateTime? before, int limit = 40}) async { _asMember(c); return List.of(_msgs[c] ?? const []); }
  @override
  Future<ChatMessage> send(String c, String body, {MessageKind kind = MessageKind.text, String? refId}) async {
    final conv = _asMember(c);
    if (kind == MessageKind.match || kind == MessageKind.system) throw MessagingException('use_dedicated_function'); // el cliente no fabrica tarjetas
    final m = _post(c, body.length > 500 ? body.substring(0, 500) : body, kind: kind, ref: refId);
    if (autoReply) {
      Timer(const Duration(seconds: 2), () {
        final from = conv.kind == ConversationKind.direct ? conv.direct!.id : conv.members.firstWhere((x) => x.id != meId, orElse: () => conv.members.first).id;
        final r = _post(c, '¡Genial! 🎾', sender: from);
        _unread[c] = (_unread[c] ?? 0);
        _ctl.add(r);
      });
    }
    return m;
  }
  @override
  Future<void> markRead(String c) async => _unread[c] = 0;
  @override
  Stream<ChatMessage> watch(String c) => _ctl.stream.where((m) => m.conversationId == c);
  @override
  Stream<ChatMessage> watchIncoming() => _ctl.stream.where((m) => m.senderId != meId);
  @override
  Stream<void> resyncs() => const Stream.empty();

  // ───────────── grupos ─────────────
  @override
  Future<String> createGroup({required String name, required List<String> memberIds, String? avatarId, Uint8List? avatarBytes}) async {
    final ids = memberIds.toSet()..remove(meId);
    final err = validateGroupDraft(name: name, selected: ids.length);
    if (err != null) throw MessagingException(name.trim().isEmpty || name.trim().length > maxGroupName ? 'invalid_group_name' : ids.isEmpty ? 'group_needs_members' : 'group_too_large');
    if (ids.any((u) => !friendIds.contains(u))) throw MessagingException('only_friends_allowed');
    final c = _Conv('g${_seq++}', ConversationKind.group, name: name.trim(), avatarId: avatarId, avatarBytes: avatarBytes);
    c.members..add(_mk(meId, GroupRole.admin))..addAll([for (final u in ids) _mk(u, GroupRole.member)]);
    _c[c.id] = c; _msgs[c.id] = [];
    _post(c.id, 'creó el grupo «${c.name}»', kind: MessageKind.system);
    _grp.add(c.id);
    return c.id;
  }
  @override
  Future<List<GroupMember>> members(String id) async { final c = _asMember(id); return List.of(c.members); }
  @override
  Future<void> updateGroup(String id, {String? name, String? avatarId, Uint8List? avatarBytes}) async {
    final c = _group(id);
    if (!_perms(c).canEdit) throw MessagingException('not_group_admin');
    if (name != null) {
      if (name.trim().isEmpty || name.trim().length > maxGroupName) throw MessagingException('invalid_group_name');
      c.name = name.trim(); _post(id, 'cambió el nombre a «${c.name}»', kind: MessageKind.system);
    }
    if (avatarId != null || avatarBytes != null) { c.avatarId = avatarId ?? c.avatarId; c.avatarBytes = avatarBytes ?? c.avatarBytes; if (avatarBytes != null) c.avatarId = null; _post(id, 'cambió la foto del grupo', kind: MessageKind.system); }
    _grp.add(id);
  }
  @override
  Future<void> addMembers(String id, List<String> ids) async {
    final c = _group(id);
    if (!_perms(c).canAdd) throw MessagingException('not_group_admin');
    if (c.members.length + ids.length > maxGroupMembers) throw MessagingException('group_too_large');
    for (final u in ids) {
      if (!friendIds.contains(u)) throw MessagingException('only_friends_allowed');
      if (c.members.every((m) => m.id != u)) c.members.add(_mk(u, GroupRole.member));
    }
    _post(id, 'añadió participantes', kind: MessageKind.system); _grp.add(id);
  }
  @override
  Future<void> removeMember(String id, String userId) async {
    final c = _group(id), p = _perms(c);
    if (!p.isAdmin) throw MessagingException('not_group_admin');
    if (userId == meId) throw MessagingException('use_leave_group');
    final t = c.members.firstWhere((m) => m.id == userId, orElse: () => throw MessagingException('not_a_member'));
    if (t.isAdmin) throw MessagingException('demote_admin_first');
    c.members.remove(t); _post(id, 'quitó a un participante', kind: MessageKind.system); _grp.add(id);
  }
  @override
  Future<void> setAdmin(String id, String userId, bool admin) async {
    final c = _group(id), p = _perms(c);
    if (!p.isAdmin) throw MessagingException('not_group_admin');
    final i = c.members.indexWhere((m) => m.id == userId);
    if (i < 0) throw MessagingException('not_a_member');
    if (!admin && c.members[i].isAdmin && p.adminCount <= 1) throw MessagingException('last_admin');
    c.members[i] = c.members[i].withRole(admin ? GroupRole.admin : GroupRole.member); _grp.add(id);
  }
  @override
  Future<void> leaveGroup(String id) async {
    final c = _group(id), p = _perms(c);
    if (!p.isMember) throw MessagingException('not a member');
    final wasAdmin = p.isAdmin;
    _post(id, 'abandonó el grupo', kind: MessageKind.system);
    c.members.removeWhere((m) => m.id == meId);
    if (c.members.isEmpty) { _c.remove(id); _msgs.remove(id); }
    else if (wasAdmin && !c.members.any((m) => m.isAdmin)) {
      final sorted = [...c.members]..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      final i = c.members.indexWhere((m) => m.id == sorted.first.id);
      c.members[i] = c.members[i].withRole(GroupRole.admin);                // el miembro más antiguo pasa a admin
    }
    _grp.add(id);
  }
  @override
  Stream<String> watchGroupChanges() => _grp.stream;

  // ───────────── tarjetas de partido ─────────────
  @override
  Future<List<LifecycleMatch>> shareableMatches() async {
    final all = await (_matches?.call() ?? Future.value(const <LifecycleMatch>[]));
    return [for (final m in all) if (RecapData.canShare(m, meId)) m];    // confirmados por los dos capitanes y donde participa
  }
  @override
  Future<ChatMessage> sendMatchCard(String conversationId, String matchId) async {
    _asMember(conversationId);
    final m = (await (_matches?.call() ?? Future.value(const <LifecycleMatch>[]))).where((x) => x.id == matchId).firstOrNull;
    if (m == null) throw MessagingException('match_not_found');
    if (m.player(meId) == null) throw MessagingException('recap_not_participant');
    if (!RecapData.canShare(m, meId)) throw MessagingException('recap_not_confirmed');    // ← la misma barrera que get_match_recap
    final payload = matchServerJson(m);                                                     // datos del partido, NO del cliente
    final sets = m.sets.map((s) => '${s.a}-${s.b}').join(' ');
    return _post(conversationId, sets, kind: MessageKind.match, ref: m.id, payload: payload);
  }
}
