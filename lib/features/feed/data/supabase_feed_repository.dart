import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/feed_models.dart';
import 'feed_repository.dart';

/// Feed y notificaciones reales (Supabase). Solo clave publishable + sesión del usuario; la RLS de
/// `feed_posts`/`reactions`/`comments` ya limita a amigos (`can_view_user`). Los datos de partido de las tarjetas
/// (jugadores y sets) llegan por la RPC `feed_match_summaries`, porque `matches` solo es legible por sus participantes.
/// Tiempo real: INSERT en `feed_posts` (actividad nueva). El autor propio se expone con id `'me'` (convención de la UI).
class SupabaseFeedRepository implements FeedRepository {
  SupabaseFeedRepository(this._db);
  final SupabaseClient _db;
  String get _uid => _db.auth.currentUser!.id;

  @override
  FeedUser get me {
    final u = _db.auth.currentUser;
    final name = (u?.userMetadata?['full_name'] ?? u?.userMetadata?['name'] ?? u?.email ?? '') as String;
    return FeedUser(id: 'me', name: name, username: '');
  }

  static const _postCols = 'id, user_id, activity_type, related_match_id, metadata, created_at, '
      'author:profiles!feed_posts_user_id_fkey(id, display_name, username, avatar_url), '
      'reactions(user_id, reaction_type), comments(count)';

  FeedUser _user(Map<String, dynamic>? p) {
    final id = (p?['id'] ?? '') as String;
    return FeedUser(id: id == _uid ? 'me' : id, name: (p?['display_name'] ?? p?['name'] ?? '') as String, username: (p?['username'] ?? '') as String, avatarUrl: p?['avatar_url'] as String?);
  }

  ReactionType? _rt(String? s) => ReactionType.values.asNameMap()[s];

  Future<Map<String, Map<String, dynamic>>> _summaries(Iterable<String> matchIds) async {
    final ids = matchIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _db.rpc('feed_match_summaries', params: {'p_match_ids': ids}) as List;
    return {for (final r in rows.cast<Map<String, dynamic>>()) r['match_id'] as String: r};
  }

  FeedPost? _post(Map<String, dynamic> r, Map<String, Map<String, dynamic>> matches) {
    final author = _user(r['author'] as Map<String, dynamic>?);
    final meta = (r['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payload = feedPayloadFrom(type: r['activity_type'] as String, meta: meta, authorUid: r['user_id'] as String, myUid: _uid,
        match: r['related_match_id'] == null ? null : matches[r['related_match_id']]);
    if (payload == null) return null;
    final rx = (r['reactions'] as List? ?? const []).cast<Map<String, dynamic>>();
    final counts = <ReactionType, int>{};
    ReactionType? mine;
    for (final x in rx) {
      final t = _rt(x['reaction_type'] as String?);
      if (t == null) continue;
      counts[t] = (counts[t] ?? 0) + 1;
      if (x['user_id'] == _uid) mine = t;
    }
    final cc = (r['comments'] as List? ?? const []);
    return FeedPost(
      id: r['id'] as String, author: author, createdAt: DateTime.parse(r['created_at'] as String).toLocal(), payload: payload,
      reactions: ReactionSummary(counts: counts, mine: mine), commentCount: cc.isEmpty ? 0 : ((cc.first as Map)['count'] as num).toInt(),
    );
  }

  Future<List<FeedPost>> _map(List rows) async {
    final list = rows.cast<Map<String, dynamic>>();
    final matches = await _summaries([for (final r in list) if (r['related_match_id'] != null) r['related_match_id'] as String]);
    return list.map((r) => _post(r, matches)).whereType<FeedPost>().toList();
  }

  @override
  Future<FeedPage> fetchPage({required FeedFilter filter, DateTime? before, int limit = 8}) async {
    var q = _db.from('feed_posts').select(_postCols);
    switch (filter) {
      case FeedFilter.all: break;
      case FeedFilter.friends: q = q.neq('user_id', _uid);
      case FeedFilter.matches: q = q.eq('activity_type', 'match');
      case FeedFilter.achievements: q = q.inFilter('activity_type', ['achievement', 'streak', 'elo']);
      case FeedFilter.leagues: q = q.eq('activity_type', 'league');
    }
    if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
    final rows = await q.order('created_at', ascending: false).limit(limit);
    final posts = await _map(rows);
    return FeedPage(posts, rows.length < limit ? null : DateTime.parse(rows.last['created_at'] as String));
  }

  @override
  Future<void> setReaction(String postId, ReactionType? type) => _db.rpc('set_reaction', params: {'p_post_id': postId, 'p_type': type?.name});

  @override
  Future<List<(FeedUser, ReactionType)>> reactionsFor(String postId) async {
    final rows = await _db.from('reactions').select('reaction_type, user:profiles!reactions_user_id_fkey(id, display_name, username, avatar_url)').eq('post_id', postId).order('created_at', ascending: false);
    return [for (final r in rows) if (_rt(r['reaction_type'] as String?) != null) (_user(r['user'] as Map<String, dynamic>?), _rt(r['reaction_type'] as String?)!)];
  }

  FeedComment _comment(Map<String, dynamic> r) => FeedComment(id: r['id'] as String, postId: r['post_id'] as String, author: _user(r['user'] as Map<String, dynamic>?),
      content: r['content'] as String, createdAt: DateTime.parse(r['created_at'] as String).toLocal());
  static const _commentCols = 'id, post_id, content, created_at, user:profiles!comments_user_id_fkey(id, display_name, username, avatar_url)';

  @override
  Future<List<FeedComment>> comments(String postId) async =>
      [for (final r in await _db.from('comments').select(_commentCols).eq('post_id', postId).eq('hidden', false).order('created_at')) _comment(r)];

  @override
  Future<FeedComment> addComment(String postId, String content) async =>
      _comment(await _db.from('comments').insert({'post_id': postId, 'user_id': _uid, 'content': content.trim()}).select(_commentCols).single());

  @override
  Future<void> deleteComment(String commentId) => _db.from('comments').delete().eq('id', commentId);

  @override
  Future<void> reportComment(String commentId) => _db.from('comment_reports').insert({'comment_id': commentId, 'reporter_id': _uid});

  @override
  Future<List<AppNotification>> notifications() async {
    final rows = await _db.from('notifications')
        .select('id, notification_type, ref_id, related_post_id, actor_count, is_read, created_at, title, body, actor:profiles!notifications_actor_user_id_fkey(id, display_name, username, avatar_url)')
        .eq('recipient_user_id', _uid).order('created_at', ascending: false).limit(100);
    return [for (final r in rows) notificationFrom(r, _user(r['actor'] as Map<String, dynamic>?))].whereType<AppNotification>().toList();
  }

  @override
  Future<void> markRead(String? id) async {
    var q = _db.from('notifications').update({'is_read': true}).eq('recipient_user_id', _uid).eq('is_read', false);
    if (id != null) q = q.eq('id', id);
    await q;
  }

  /// Acciones de las notificaciones con botones: solicitud de amistad (ref_id = id de la solicitud) e invitación a liga.
  @override
  Future<void> respond(String id, bool accept) async {
    final n = await _db.from('notifications').select('notification_type, ref_id').eq('id', id).single();
    final ref = n['ref_id'] as String?;
    if (ref != null) {
      if (n['notification_type'] == 'friend_request') await _db.rpc('respond_friend_request', params: {'req': ref, 'accept': accept});
      if (n['notification_type'] == 'league_invite' && accept) await _db.rpc('join_league', params: {'p_league': ref});
    }
    await markRead(id);
  }

  @override
  Stream<FeedPost> watchNew() {
    late final RealtimeChannel ch;
    final ctl = StreamController<FeedPost>(onCancel: () => _db.removeChannel(ch));
    ch = _db.channel('feed:$_uid').onPostgresChanges(
      event: PostgresChangeEvent.insert, schema: 'public', table: 'feed_posts',
      callback: (p) async {
        try {
          final row = await _db.from('feed_posts').select(_postCols).eq('id', p.newRecord['id'] as String).maybeSingle();
          if (row == null) return;            // la RLS no la deja ver (no es de un amigo)
          final posts = await _map([row]);
          if (posts.isNotEmpty && !ctl.isClosed) ctl.add(posts.first);
        } catch (_) {/* sin red: la actividad aparecerá al refrescar */}
      },
    )..subscribe();
    return ctl.stream;
  }
}

/// Mapea `feed_posts.metadata` (+ resumen del partido) al payload de la UI. Puro, para poder probarlo.
FeedPayload? feedPayloadFrom({required String type, required Map<String, dynamic> meta, required String authorUid, required String myUid, Map<String, dynamic>? match}) {
  FeedUser u(Map<String, dynamic> p) {
    final id = p['id'] as String;
    return FeedUser(id: id == myUid ? 'me' : id, name: (p['name'] ?? '') as String, username: (p['username'] ?? '') as String, avatarUrl: p['avatar_url'] as String?);
  }
  switch (type) {
    case 'match':
      if (match == null) return null;                       // partido no confirmado o no visible: no se publica
      final players = (match['players'] as List? ?? const []).cast<Map<String, dynamic>>();
      final myTeam = (meta['team'] as num?)?.toInt() ?? (players.where((p) => p['id'] == authorUid).map((p) => (p['team'] as num).toInt()).firstOrNull ?? 1);
      final sets = <(int, int)>[for (final s in (match['sets'] as List? ?? const []).cast<List>()) myTeam == 1 ? ((s[0] as num).toInt(), (s[1] as num).toInt()) : ((s[1] as num).toInt(), (s[0] as num).toInt())];
      if (sets.isEmpty) return null;
      final won = sets.where((s) => s.$1 > s.$2).length * 2 > sets.length;
      final mine = players.where((p) => p['id'] == authorUid).firstOrNull;
      return MatchPayload(
        matchId: match['match_id'] as String,
        teamA: [for (final p in players) if (p['team'] == myTeam) u(p)], teamB: [for (final p in players) if (p['team'] != myTeam) u(p)],
        sets: sets, won: won, eloDelta: ((meta['elo_delta'] ?? mine?['elo_delta'] ?? 0) as num).toInt(),
        venue: (match['venue'] as String?)?.isEmpty == true ? null : match['venue'] as String?, leagueName: match['league_name'] as String?);
    case 'achievement':
      return AchievementPayload(achievementId: (meta['achievement_id'] ?? '') as String, title: (meta['title'] ?? 'Logro desbloqueado') as String,
          description: (meta['description'] ?? '') as String, milestone: meta['milestone'] as String?);
    case 'streak':
      return StreakPayload(((meta['count'] ?? meta['streak'] ?? 0) as num).toInt());
    case 'elo':
      final from = ((meta['from'] ?? 0) as num).toInt(), to = ((meta['to'] ?? 0) as num).toInt();
      return EloPayload(from: from, to: to, headline: (meta['headline'] ?? 'Nuevo ELO') as String);
    case 'league':
      return LeaguePayload(leagueName: (meta['league_name'] ?? '') as String, headline: (meta['headline'] ?? '') as String, subtitle: (meta['subtitle'] ?? '') as String);
  }
  return null;
}

const _types = {
  'reaction': NotificationType.reaction, 'comment': NotificationType.comment, 'friend_request': NotificationType.friendRequest,
  'friend_accepted': NotificationType.friendAccepted, 'play_invite': NotificationType.playInvite,
  'match_confirmation_required': NotificationType.matchConfirmationRequired, 'match_confirmed': NotificationType.matchConfirmed,
  'match_disputed': NotificationType.matchDisputed, 'match_event': NotificationType.matchEvent, 'achievement': NotificationType.achievement,
  'streak': NotificationType.streak, 'elo_milestone': NotificationType.eloMilestone, 'rating_change': NotificationType.ratingChange,
  'league_invite': NotificationType.leagueInvite, 'league_starting': NotificationType.leagueStarting, 'league_position_change': NotificationType.leaguePositionChange,
  'direct_message': NotificationType.directMessage, 'group_message': NotificationType.groupMessage, 'group_added': NotificationType.groupAdded,
};

/// Fila de `notifications` → [AppNotification]. Los tipos desconocidos se omiten. Puro, para poder probarlo.
/// Mensajes: un aviso por conversación que el servidor actualiza con el último mensaje (`actor_count` = sin leer).
AppNotification? notificationFrom(Map<String, dynamic> r, FeedUser actor) {
  final t = _types[r['notification_type']];
  if (t == null) return null;
  final who = actor.name.isEmpty ? 'Alguien' : actor.name;
  final more = ((r['actor_count'] ?? 1) as num).toInt() - 1;
  final whoAll = more > 0 ? '$who y $more más' : who;
  final title = r['title'] as String?, body = r['body'] as String?;
  final n = more + 1;
  final text = switch (t) {
    NotificationType.directMessage => n > 1 ? '$who te ha enviado $n mensajes · ${body ?? ''}' : '$who: ${body ?? ''}',
    NotificationType.groupMessage => '$who en «${title ?? 'el grupo'}»: ${body ?? ''}${n > 1 ? ' (+${n - 1})' : ''}',
    NotificationType.groupAdded => '$who te añadió al grupo «${body ?? ''}»',
    _ => null,
  } ?? (body?.isNotEmpty == true ? (title?.isNotEmpty == true ? '$title: $body' : body!) : switch (t) {
    NotificationType.reaction => '$whoAll reaccionó a tu actividad',
    NotificationType.comment => '$whoAll comentó tu actividad',
    NotificationType.friendRequest => '$who quiere ser tu amigo',
    NotificationType.friendAccepted => '$who aceptó tu solicitud de amistad',
    NotificationType.leagueInvite => '$who te invitó a una liga',
    _ => title ?? 'Tienes una novedad',
  });
  final read = r['is_read'] == true;
  return AppNotification(
    id: r['id'] as String, type: t, actors: [if (actor.id.isNotEmpty) actor], text: text, createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    postId: r['related_post_id'] as String?, refId: r['ref_id'] as String?, isRead: read,
    actionable: !read && (t == NotificationType.friendRequest || (t == NotificationType.leagueInvite && title == 'Invitación a liga')),
  );
}
