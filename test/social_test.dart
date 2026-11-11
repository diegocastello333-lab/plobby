import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/social/data/mock_social_repository.dart';
import 'package:plobby/features/social/domain/social_models.dart';

void main() {
  test('no se puede enviar solicitud dos veces ni a uno mismo', () async {
    final r = MockSocialRepository();
    await r.sendRequest('paula');
    await r.sendRequest('paula');
    await r.sendRequest('me');
    expect((await r.requests()).outgoing.length, 1);
  });
  test('aceptar una solicitud crea la amistad y la quita de pendientes', () async {
    final r = MockSocialRepository();
    final before = (await r.friends()).length;
    final req = (await r.requests()).incoming.first;
    await r.respondRequest(req.id, accept: true);
    expect((await r.friends()).length, before + 1);
    expect((await r.requests()).incoming, isEmpty);
  });
  test('la búsqueda excluye al usuario y refleja la relación', () async {
    final r = MockSocialRepository();
    await r.sendRequest('paula');
    final hits = await r.search('paula');
    expect(hits.single.relation, RelationState.requestSent);
    expect((await r.search('me')).any((h) => h.player.id == 'me'), isFalse);
  });
}
