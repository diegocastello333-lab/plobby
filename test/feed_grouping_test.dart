import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/feed/domain/feed_grouping.dart';
import 'package:plobby/features/feed/domain/feed_models.dart';

FeedPost _p(String id, String who, FeedPayload pl) => FeedPost(id: id, author: FeedUser(id: who, name: '$who Apellido', username: who), createdAt: DateTime(2026, 11, 24), payload: pl);
const _ach = AchievementPayload(achievementId: 'fire', title: 'En llamas', description: '5 victorias');

void main() {
  test('logros seguidos se agrupan; partidos y rachas no; un logro suelto queda suelto', () {
    final items = groupFeed([
      _p('1', 'jacobo', _ach), _p('2', 'ana', _ach), _p('3', 'luis', _ach),
      _p('4', 'ana', const StreakPayload(5)),
      _p('5', 'eva', _ach),
    ]);
    expect(items.map((i) => i.runtimeType.toString()), ['AchievementGroup', 'SinglePost', 'SinglePost']);
    final g = items.first as AchievementGroup;
    expect(g.posts.length, 3);
    expect(achievementGroupTitle(g), 'jacobo y 2 amigos más han desbloqueado logros');
  });

  test('títulos del grupo según cuántas personas', () {
    expect(achievementGroupTitle(AchievementGroup([_p('1', 'Ana', _ach), _p('2', 'Ana', _ach)])), 'Ana ha desbloqueado 2 logros');
    expect(achievementGroupTitle(AchievementGroup([_p('1', 'Ana', _ach), _p('2', 'Bea', _ach)])), 'Ana y Bea han desbloqueado logros');
  });
}
