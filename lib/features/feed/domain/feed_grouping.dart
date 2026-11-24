import 'feed_models.dart';

/// Elemento del feed: una publicación o un grupo de logros seguidos.
sealed class FeedItem { const FeedItem(); }
class SinglePost extends FeedItem { const SinglePost(this.post); final FeedPost post; }
class AchievementGroup extends FeedItem {
  const AchievementGroup(this.posts);
  final List<FeedPost> posts;
  /// Personas distintas, en orden de aparición.
  List<FeedUser> get people {
    final seen = <String>{};
    return [for (final p in posts) if (seen.add(p.author.id)) p.author];
  }
  String get key => 'grp:${posts.first.id}';
}

/// Agrupa los logros CONSECUTIVOS (2 o más) en una sola tarjeta: «Jacobo y 2 amigos más han desbloqueado logros».
/// Partidos, rachas, récords de ELO y campeones nunca se agrupan.
List<FeedItem> groupFeed(List<FeedPost> posts, {int minGroup = 2}) {
  final out = <FeedItem>[];
  var run = <FeedPost>[];
  void flush() {
    if (run.length >= minGroup) { out.add(AchievementGroup(run)); } else { out.addAll(run.map(SinglePost.new)); }
    run = [];
  }
  for (final p in posts) {
    if (p.payload is AchievementPayload) { run.add(p); continue; }
    flush();
    out.add(SinglePost(p));
  }
  flush();
  return out;
}

/// «Jacobo ha desbloqueado 2 logros» · «Jacobo y Ana han…» · «Jacobo y 2 amigos más han desbloqueado logros».
String achievementGroupTitle(AchievementGroup g) {
  final people = g.people;
  final first = people.first.name.split(' ').first;
  if (people.length == 1) return '$first ha desbloqueado ${g.posts.length} logros';
  if (people.length == 2) return '$first y ${people[1].name.split(' ').first} han desbloqueado logros';
  return '$first y ${people.length - 1} amigos más han desbloqueado logros';
}
