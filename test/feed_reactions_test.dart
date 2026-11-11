import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/feed/domain/feed_models.dart';

void main() {
  const me = FeedUser(id: 'me', name: 'Diego', username: 'diego.c');
  test('una reacción activa por usuario: añadir, cambiar y quitar', () {
    var r = const ReactionSummary(counts: {ReactionType.fire: 2});
    r = r.toggle(ReactionType.fire, me);
    expect(r.mine, ReactionType.fire);
    expect(r.counts[ReactionType.fire], 3);
    r = r.toggle(ReactionType.heart, me); // cambiar
    expect(r.mine, ReactionType.heart);
    expect(r.counts[ReactionType.fire], 2);
    expect(r.counts[ReactionType.heart], 1);
    expect(r.total, 3);
    r = r.toggle(ReactionType.heart, me); // quitar
    expect(r.mine, isNull);
    expect(r.counts.containsKey(ReactionType.heart), isFalse);
  });
}
