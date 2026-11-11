import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../matches/application/lifecycle_providers.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../data/messaging_repository.dart';
import '../data/mock_messaging_repository.dart';
import '../domain/messaging_models.dart';

/// El mock obtiene los partidos confirmados de la MISMA fuente que el resto de la app (LifecycleRepository): sin duplicar datos.
final messagingRepositoryProvider = Provider<MessagingRepository>((ref) => MockMessagingRepository(matches: () => ref.read(lifecycleRepositoryProvider).confirmedMatches()));

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() {
    final repo = ref.read(messagingRepositoryProvider);
    final sub = repo.watchIncoming().listen((_) => ref.invalidateSelf());
    final sub2 = repo.watchGroupChanges().listen((_) => ref.invalidateSelf());   // nombre/foto/miembros en tiempo real
    ref.onDispose(() { sub.cancel(); sub2.cancel(); });
    return ref.read(messagingRepositoryProvider).conversations();
  }
}
final conversationsProvider = AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(ConversationsNotifier.new);

final conversationProvider = FutureProvider.family<Conversation?, String>((ref, id) async {
  final sub = ref.read(messagingRepositoryProvider).watchGroupChanges().where((g) => g == id).listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return ref.read(messagingRepositoryProvider).conversation(id);
});

/// Miembros de un grupo (con rol), en tiempo real ante cambios del grupo.
final groupMembersProvider = FutureProvider.family<List<GroupMember>, String>((ref, id) async {
  final sub = ref.read(messagingRepositoryProvider).watchGroupChanges().where((g) => g == id).listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return ref.read(messagingRepositoryProvider).members(id);
});

/// Partidos finalizados y confirmados que el usuario puede compartir (se recargan cada vez que se abre el selector).
final shareableMatchesProvider = FutureProvider.autoDispose<List<LifecycleMatch>>((ref) => ref.read(messagingRepositoryProvider).shareableMatches());

/// Contador del icono de mensajes del Home: suma real de no leídos.
final unreadMessagesProvider = Provider<int>((ref) => ref.watch(conversationsProvider).valueOrNull?.fold<int>(0, (a, c) => a + c.unread) ?? 0);

class ChatNotifier extends FamilyAsyncNotifier<List<ChatMessage>, String> {
  MessagingRepository get _repo => ref.read(messagingRepositoryProvider);
  @override
  Future<List<ChatMessage>> build(String conversationId) async {
    final sub = _repo.watch(conversationId).listen((m) {
      final cur = state.valueOrNull ?? [];
      if (cur.any((x) => x.id == m.id)) return;
      state = AsyncData([...cur, m]);
      _repo.markRead(conversationId);
    });
    ref.onDispose(sub.cancel);
    final h = await _repo.history(conversationId);
    await _repo.markRead(conversationId);
    ref.invalidate(conversationsProvider);
    return h;
  }

  /// Envía la tarjeta de un partido. El resultado lo construye el servidor a partir del partido original: aquí solo viaja su id.
  /// Lanza MessagingException(recap_not_confirmed | recap_not_participant | …) si el servidor lo rechaza.
  Future<void> sendMatchCard(String matchId) async {
    try {
      final saved = await _repo.sendMatchCard(arg, matchId);
      if (!(state.valueOrNull ?? []).any((m) => m.id == saved.id)) state = AsyncData([...state.value ?? [], saved]);
    } finally {
      ref.invalidate(conversationsProvider);
    }
  }

  /// Envío optimista: el mensaje aparece como "enviando" y se reconcilia con la fila del servidor.
  Future<void> send(String body, {MessageKind kind = MessageKind.text, String? refId}) async {
    final text = body.trim();
    if (text.isEmpty && kind == MessageKind.text) return;
    final tmp = ChatMessage(id: 'tmp${DateTime.now().microsecondsSinceEpoch}', conversationId: arg, senderId: _repo.meId, kind: kind, body: text, refId: refId, createdAt: DateTime.now(), status: MessageStatus.sending);
    state = AsyncData([...state.value ?? [], tmp]);
    try {
      final saved = await _repo.send(arg, text, kind: kind, refId: refId);
      state = AsyncData([for (final m in state.value!) m.id == tmp.id ? saved : m]);
    } catch (_) {
      state = AsyncData([for (final m in state.value!) m.id == tmp.id ? m.copyWith(status: MessageStatus.failed) : m]);
    }
    ref.invalidate(conversationsProvider);
  }
}
final chatProvider = AsyncNotifierProvider.family<ChatNotifier, List<ChatMessage>, String>(ChatNotifier.new);

final conversationSearchProvider = StateProvider<String>((ref) => '');
