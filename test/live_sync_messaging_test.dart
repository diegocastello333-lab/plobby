import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/live/live_sync.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/auth/application/auth_providers.dart';
import 'package:plobby/features/auth/data/mock_auth_repository.dart';
import 'package:plobby/features/messaging/application/messaging_providers.dart';
import 'package:plobby/features/messaging/data/mock_messaging_repository.dart';
import 'package:plobby/features/messaging/domain/messaging_models.dart';
import 'package:plobby/features/profile/domain/models.dart';
import 'package:plobby/features/profile/presentation/widgets/profile_header.dart';
import 'package:plobby/features/social/application/social_providers.dart';
import 'package:plobby/features/social/domain/social_models.dart';

/// Doble de mensajería: historial controlable, envíos que fallan a demanda y Realtime manual.
class _Repo extends MockMessagingRepository {
  _Repo() : super(autoReply: false);
  final live = StreamController<ChatMessage>.broadcast();
  Completer<List<ChatMessage>>? historyGate;
  int failSends = 0, sends = 0, reads = 0;
  ChatMessage? deliverBeforeReturn;   // simula que Realtime trae la fila antes de que vuelva la RPC

  ChatMessage msg(String id, {String from = 'ana', String c = 'c1', String body = 'hola', int sec = 0}) =>
      ChatMessage(id: id, conversationId: c, senderId: from, body: body, createdAt: DateTime(2026, 11, 12, 10, 0, sec));

  @override
  Future<List<ChatMessage>> history(String c, {DateTime? before, int limit = 40}) => historyGate?.future ?? Future.value([msg('h1')]);
  @override
  Stream<ChatMessage> watch(String c) => live.stream.where((m) => m.conversationId == c);
  @override
  Stream<ChatMessage> watchIncoming() => live.stream.where((m) => m.senderId != meId);
  @override
  Future<void> markRead(String c) async => reads++;
  @override
  Future<Conversation?> conversation(String id) async => null;
  @override
  Future<ChatMessage> send(String c, String body, {MessageKind kind = MessageKind.text, String? refId}) async {
    sends++;
    if (failSends > 0) { failSends--; throw MessagingException('network'); }
    final saved = msg('s$sends', from: meId, c: c, body: body, sec: 30);
    if (deliverBeforeReturn != null) { live.add(saved); await Future<void>.delayed(Duration.zero); }
    return saved;
  }
}

void main() {
  group('Chat (ChatNotifier)', () {
    test('un mensaje que llega por Realtime mientras se carga el historial no se pierde', () async {
      final repo = _Repo()..historyGate = Completer();
      final c = ProviderContainer(overrides: [messagingRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      final sub = c.listen(chatProvider('c1'), (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      repo.live.add(repo.msg('rt1', sec: 5));             // llega antes de que termine la carga
      await Future<void>.delayed(Duration.zero);
      repo.historyGate!.complete([repo.msg('h1')]);
      final l = await c.read(chatProvider('c1').future);
      expect(l.map((m) => m.id), ['h1', 'rt1']);
      expect(repo.reads, greaterThan(0));                  // al abrir se marca como leída
    });

    test('el mismo mensaje por la respuesta del envío y por Realtime aparece una sola vez', () async {
      final repo = _Repo();
      final c = ProviderContainer(overrides: [messagingRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      final sub = c.listen(chatProvider('c1'), (_, __) {});
      addTearDown(sub.close);
      await c.read(chatProvider('c1').future);
      repo.deliverBeforeReturn = repo.msg('x');
      await c.read(chatProvider('c1').notifier).send('¿Jugamos?');
      final l = c.read(chatProvider('c1')).value!;
      expect(l.where((m) => m.body == '¿Jugamos?').length, 1);
      expect(l.last.status, MessageStatus.sent);
    });

    test('un envío fallido se reintenta sin duplicarse', () async {
      final repo = _Repo()..failSends = 1;
      final c = ProviderContainer(overrides: [messagingRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      final sub = c.listen(chatProvider('c1'), (_, __) {});
      addTearDown(sub.close);
      await c.read(chatProvider('c1').future);
      final n = c.read(chatProvider('c1').notifier);
      await n.send('Hola');
      final failed = c.read(chatProvider('c1')).value!.last;
      expect(failed.status, MessageStatus.failed);
      await n.retry(failed.id);
      final l = c.read(chatProvider('c1')).value!;
      expect(l.where((m) => m.body == 'Hola').length, 1);
      expect(l.last.status, MessageStatus.sent);
    });
  });

  group('Relación de amistad (fuente única)', () {
    test('amigo, solicitud recibida y tras aceptar pasa a amigo', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(friendsProvider.future);
      await c.read(requestsProvider.future);
      expect(c.read(relationProvider('laura')), RelationState.friend);
      expect(c.read(relationProvider('raul')), RelationState.requestReceived);
      expect(c.read(relationProvider('nadie')), RelationState.none);
      await c.read(requestsProvider.notifier).respond('r1', true);
      await c.read(friendsProvider.future);
      expect(c.read(relationProvider('raul')), RelationState.friend);
      expect(c.read(friendCountProvider), 3);
    });
  });

  group('Perfil de otro jugador', () {
    const raul = PlayerProfile(id: 'raul', fullName: 'Raúl D.', username: 'ra.l.d', location: '', declaredLevel: 'Intermedio',
        declaredLevelValue: 3, side: PlaySide.right, dominantHand: 'Derecha');
    testWidgets('el botón refleja la relación real: «Aceptar solicitud» → «Amigos» + contador', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(child: MaterialApp(theme: buildPlobbyTheme(),
          home: const Scaffold(body: SingleChildScrollView(child: ProfileHeader(profile: raul, isOwner: false))))));
      for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 200)); }
      expect(find.text('Aceptar solicitud'), findsOneWidget);
      expect(find.text('Compartir perfil'), findsOneWidget);
      expect(find.bySemanticsLabel('12 amigos'), findsOneWidget);
      await t.tap(find.text('Aceptar solicitud'));
      for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 200)); }
      expect(find.text('Amigos'), findsOneWidget);
      expect(find.text('Enviar mensaje'), findsOneWidget);   // ya pueden hablar
      expect(find.text('Ahora sois amigos'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('Avisos en la app (LiveSync)', () {
    Future<_Repo> app(WidgetTester t) async {
      final repo = _Repo();
      final auth = MockAuthRepository();
      await auth.signInWithGoogle();
      await t.pumpWidget(ProviderScope(
        overrides: [messagingRepositoryProvider.overrideWithValue(repo), authRepositoryProvider.overrideWithValue(auth)],
        child: MaterialApp(theme: buildPlobbyTheme(), builder: (_, child) => LiveSync(child: child!), home: const Scaffold(body: Text('Inicio'))),
      ));
      await t.pump();
      return repo;
    }

    testWidgets('mensaje nuevo fuera de su chat → banner con el texto; desaparece solo', (t) async {
      final repo = await app(t);
      repo.live.add(repo.msg('n1', body: '¿Partido el jueves?'));
      for (var i = 0; i < 4; i++) { await t.pump(const Duration(milliseconds: 100)); }
      expect(find.text('¿Partido el jueves?'), findsOneWidget);
      expect(find.text('Nuevo mensaje'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('¿Partido el jueves?'), findsNothing);
    });

    testWidgets('si esa conversación está abierta no se muestra banner', (t) async {
      final repo = await app(t);
      activeConversation.value = 'c1';
      addTearDown(() => activeConversation.value = null);
      repo.live.add(repo.msg('n2', body: 'Ya lo estás viendo'));
      for (var i = 0; i < 4; i++) { await t.pump(const Duration(milliseconds: 100)); }
      expect(find.text('Ya lo estás viendo'), findsNothing);
    });
  });
}
