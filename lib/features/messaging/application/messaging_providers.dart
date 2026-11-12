import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../feed/application/feed_providers.dart' show notificationsProvider;
import '../../matches/application/lifecycle_providers.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../data/messaging_repository.dart';
import '../data/mock_messaging_repository.dart';
import '../domain/messaging_models.dart';

/// El mock obtiene los partidos confirmados de la MISMA fuente que el resto de la app (LifecycleRepository): sin duplicar datos.
final messagingRepositoryProvider = Provider<MessagingRepository>((ref) => MockMessagingRepository(matches: () => ref.read(lifecycleRepositoryProvider).confirmedMatches()));

/// Conversación abierta en pantalla (la fija ChatScreen). Sirve para no avisar de un mensaje que ya se está viendo.
/// ValueNotifier y no provider: se actualiza desde initState/dispose, donde Riverpod no deja modificar estado.
final activeConversation = ValueNotifier<String?>(null);

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() {
    final repo = ref.read(messagingRepositoryProvider);
    // Recarga con un pequeño margen: varios mensajes seguidos generan una sola consulta.
    Timer? debounce;
    void reload() { debounce?.cancel(); debounce = Timer(const Duration(milliseconds: 250), ref.invalidateSelf); }
    final subs = [
      repo.watchIncoming().listen((_) => reload()),
      repo.watchGroupChanges().listen((_) => reload()),   // nombre/foto/miembros en tiempo real
      repo.resyncs().listen((_) => reload()),             // vuelta de la conexión: recuperar lo perdido
    ];
    ref.onDispose(() { debounce?.cancel(); for (final s in subs) { s.cancel(); } });
    return repo.conversations();
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

  /// Une mensajes sin duplicar (el mismo mensaje puede llegar por la respuesta del envío y por Realtime) y en orden.
  static List<ChatMessage> _merge(List<ChatMessage> a, Iterable<ChatMessage> b) {
    final byId = {for (final m in a) m.id: m};
    for (final m in b) { byId[m.id] = m; }
    return byId.values.toList()..sort((x, y) => x.createdAt.compareTo(y.createdAt));
  }

  @override
  Future<List<ChatMessage>> build(String conversationId) async {
    // Lo que llegue mientras se carga el historial se guarda y se une después (antes podía perderse).
    final early = <ChatMessage>[];
    var loaded = false;
    final subs = [
      _repo.watch(conversationId).listen((m) {
        if (!loaded) { early.add(m); return; }
        final cur = state.valueOrNull ?? const <ChatMessage>[];
        if (cur.any((x) => x.id == m.id)) return;
        state = AsyncData(_merge(cur, [m]));
        if (m.senderId != _repo.meId) _read();
      }),
      _repo.resyncs().listen((_) => _reload()),
    ];
    ref.onDispose(() { for (final s in subs) { s.cancel(); } });
    final h = await _repo.history(conversationId);
    loaded = true;
    unawaited(_read());
    return _merge(h, early);
  }

  /// Marca la conversación como leída (servidor: last_read_at + avisos) y refresca lista y notificaciones.
  Future<void> _read() async {
    try { await _repo.markRead(arg); } catch (_) {/* sin conexión: se marcará al volver */}
    ref.invalidate(conversationsProvider);
    ref.invalidate(notificationsProvider);   // sus avisos de mensaje quedan leídos en el servidor
  }

  /// Recarga tras recuperar la conexión, conservando los mensajes locales pendientes o fallidos.
  Future<void> _reload() async {
    try {
      final h = await _repo.history(arg);
      final local = (state.valueOrNull ?? const <ChatMessage>[]).where((m) => m.status == MessageStatus.sending || m.status == MessageStatus.failed);
      state = AsyncData(_merge(h, local));
      unawaited(_read());
    } catch (_) {/* se reintentará en la siguiente reconexión */}
  }

  /// Envía la tarjeta de un partido. El resultado lo construye el servidor a partir del partido original: aquí solo viaja su id.
  /// Lanza MessagingException(recap_not_confirmed | recap_not_participant | …) si el servidor lo rechaza.
  Future<void> sendMatchCard(String matchId) async {
    try {
      final saved = await _repo.sendMatchCard(arg, matchId);
      state = AsyncData(_merge(state.valueOrNull ?? const [], [saved]));
    } finally {
      ref.invalidate(conversationsProvider);
    }
  }

  /// Envío optimista: el mensaje aparece como "enviando" y se reconcilia con la fila del servidor.
  Future<void> send(String body, {MessageKind kind = MessageKind.text, String? refId}) async {
    final text = body.trim();
    if (text.isEmpty && kind == MessageKind.text) return;
    final tmp = ChatMessage(id: 'tmp${DateTime.now().microsecondsSinceEpoch}', conversationId: arg, senderId: _repo.meId, kind: kind, body: text, refId: refId, createdAt: DateTime.now(), status: MessageStatus.sending);
    state = AsyncData([...state.valueOrNull ?? const <ChatMessage>[], tmp]);
    await _deliver(tmp);
  }

  /// Reintenta un mensaje fallido: el MISMO mensaje pasa a «enviando» (antes se creaba otro y quedaba el fallido).
  Future<void> retry(String tmpId) async {
    final m = state.valueOrNull?.where((x) => x.id == tmpId).firstOrNull;
    if (m == null || m.status != MessageStatus.failed) return;
    _replace(tmpId, m.copyWith(status: MessageStatus.sending));
    await _deliver(m);
  }

  Future<void> _deliver(ChatMessage tmp) async {
    try {
      final saved = await _repo.send(arg, tmp.body, kind: tmp.kind, refId: tmp.refId);
      final cur = state.valueOrNull ?? const <ChatMessage>[];
      // Si Realtime ya trajo la fila guardada, se quita el provisional; si no, se sustituye.
      state = AsyncData(cur.any((m) => m.id == saved.id) ? cur.where((m) => m.id != tmp.id).toList() : [for (final m in cur) m.id == tmp.id ? saved : m]);
    } catch (_) {
      _replace(tmp.id, tmp.copyWith(status: MessageStatus.failed));
    }
    ref.invalidate(conversationsProvider);
  }

  void _replace(String id, ChatMessage m) => state = AsyncData([for (final x in state.valueOrNull ?? const <ChatMessage>[]) x.id == id ? m : x]);
}

final chatProvider = AsyncNotifierProvider.family<ChatNotifier, List<ChatMessage>, String>(ChatNotifier.new);

final conversationSearchProvider = StateProvider<String>((ref) => '');
