import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/messaging/application/messaging_providers.dart';
import 'package:plobby/features/messaging/domain/messaging_models.dart';

void main() {
  test('enviar mensaje lo añade a la conversación y no admite vacíos', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(chatProvider('c_marcos').future);
    await c.read(chatProvider('c_marcos').notifier).send('   ');
    await c.read(chatProvider('c_marcos').notifier).send('Hola');
    final l = c.read(chatProvider('c_marcos')).value!;
    expect(l.last.body, 'Hola');
    expect(l.last.status, isNot(MessageStatus.failed));
    expect(l.where((m) => m.body.trim().isEmpty), isEmpty);
  });
  test('abrir el chat pone a cero los no leídos', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect((await c.read(conversationsProvider.future)).first.unread, 1);
    await c.read(chatProvider('c_marcos').future);
    expect((await c.refresh(conversationsProvider.future)).first.unread, 0);
  });
}
