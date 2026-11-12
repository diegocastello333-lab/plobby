import 'package:flutter/foundation.dart';

enum ReactionType {
  fire('🔥'), heart('❤️'), clap('👏'), strong('💪'), laugh('😂');
  const ReactionType(this.emoji);
  final String emoji;
}

enum FeedFilter { all, friends, matches, achievements, leagues }

@immutable
class FeedUser {
  const FeedUser({required this.id, required this.name, required this.username, this.avatarUrl});
  final String id, name, username;
  final String? avatarUrl;
}

/// Contenido específico de cada tipo de actividad (sellado: `switch` exhaustivo en la UI).
sealed class FeedPayload { const FeedPayload(); }

class MatchPayload extends FeedPayload {
  const MatchPayload({required this.matchId, required this.teamA, required this.teamB, required this.sets, required this.won, required this.eloDelta, this.venue, this.leagueName});
  final String matchId;
  final List<FeedUser> teamA, teamB; // teamA = equipo del autor
  final List<(int, int)> sets;       // (equipo A, equipo B)
  final bool won;
  final int eloDelta;
  final String? venue, leagueName;
  String get score => sets.map((s) => '${s.$1}-${s.$2}').join(' / ');
}

class AchievementPayload extends FeedPayload {
  const AchievementPayload({required this.achievementId, required this.title, required this.description, this.milestone});
  final String achievementId, title, description;
  final String? milestone; // p. ej. "+104 ELO" o "CLUB LA MORALEJA · #1"
}

class StreakPayload extends FeedPayload { const StreakPayload(this.count); final int count; }

class EloPayload extends FeedPayload {
  const EloPayload({required this.from, required this.to, required this.headline});
  final int from, to; final String headline;
  int get delta => to - from;
}

class LeaguePayload extends FeedPayload {
  const LeaguePayload({required this.leagueName, required this.headline, required this.subtitle});
  final String leagueName, headline, subtitle;
}

@immutable
class ReactionSummary {
  const ReactionSummary({this.counts = const {}, this.mine, this.recent = const []});
  final Map<ReactionType, int> counts;   // contadores por emoji
  final ReactionType? mine;              // máximo una reacción activa por usuario y actividad
  final List<FeedUser> recent;           // previsualización de quién ha reaccionado
  int get total => counts.values.fold(0, (a, b) => a + b);

  /// Regla de una sola reacción: quitar, cambiar o añadir. Devuelve el nuevo resumen (optimista).
  ReactionSummary toggle(ReactionType t, FeedUser me) {
    final c = Map<ReactionType, int>.from(counts);
    if (mine != null) c[mine!] = (c[mine!] ?? 1) - 1;
    final removing = mine == t;
    if (!removing) c[t] = (c[t] ?? 0) + 1;
    c.removeWhere((_, v) => v <= 0);
    final r = recent.where((u) => u.id != me.id).toList();
    if (!removing) r.insert(0, me);
    return ReactionSummary(counts: c, mine: removing ? null : t, recent: r.take(3).toList());
  }
}

@immutable
class FeedPost {
  const FeedPost({required this.id, required this.author, required this.createdAt, required this.payload, this.reactions = const ReactionSummary(), this.commentCount = 0, this.previewComments = const []});
  final String id;                 // identificador único (clave de deduplicación en backend)
  final FeedUser author;
  final DateTime createdAt;
  final FeedPayload payload;
  final ReactionSummary reactions;
  final int commentCount;
  final List<FeedComment> previewComments;
  FeedPost copyWith({ReactionSummary? reactions, int? commentCount, List<FeedComment>? previewComments}) => FeedPost(
      id: id, author: author, createdAt: createdAt, payload: payload, reactions: reactions ?? this.reactions,
      commentCount: commentCount ?? this.commentCount, previewComments: previewComments ?? this.previewComments);
}

@immutable
class FeedComment {
  const FeedComment({required this.id, required this.postId, required this.author, required this.content, required this.createdAt});
  final String id, postId, content;
  final FeedUser author;
  final DateTime createdAt;
}

enum NotificationType {
  // social
  reaction, comment, friendRequest, friendAccepted,
  // partidos
  playInvite, matchConfirmationRequired, matchConfirmed, matchDisputed, matchEvent,
  // progresión
  achievement, streak, eloMilestone, ratingChange,
  // ligas
  leagueInvite, leagueStarting, leaguePositionChange,
  // mensajes (refId = id de la conversación)
  directMessage, groupMessage, groupAdded,
}

/// Destino al pulsar una notificación (se resuelve en la UI con GoRouter).
extension NotificationDestination on NotificationType {
  String route(AppNotification n) => switch (this) {
        NotificationType.reaction || NotificationType.comment => '/feed',
        NotificationType.friendRequest => '/friends',   // «Solicitudes pendientes» con Aceptar / Rechazar
        NotificationType.friendAccepted => '/player/${n.actors.first.id}',
        NotificationType.playInvite => '/messages/with/${n.actors.first.id}',
        NotificationType.matchConfirmationRequired || NotificationType.matchConfirmed || NotificationType.matchDisputed || NotificationType.matchEvent => '/match/${n.refId ?? ''}',
        NotificationType.achievement || NotificationType.streak => '/profile',
        NotificationType.eloMilestone || NotificationType.ratingChange => '/rating',
        NotificationType.leagueInvite || NotificationType.leagueStarting || NotificationType.leaguePositionChange => '/leagues/${n.refId ?? ''}',
        NotificationType.directMessage || NotificationType.groupMessage || NotificationType.groupAdded =>
            n.refId == null ? '/messages' : '/messages/${n.refId}',
      };
}

@immutable
class AppNotification {
  const AppNotification({required this.id, required this.type, required this.actors, required this.text, required this.createdAt, this.postId, this.refId, this.isRead = false, this.actionable = false});
  final String id, text;
  final String? refId; // id de partido/liga relacionado
  final NotificationType type;
  final List<FeedUser> actors;  // agrupadas para evitar ruido ("Marcos y 3 más…")
  final DateTime createdAt;
  final String? postId;
  final bool isRead, actionable;
  AppNotification copyWith({bool? isRead, bool? actionable}) => AppNotification(id: id, type: type, actors: actors, text: text, createdAt: createdAt, postId: postId, refId: refId, isRead: isRead ?? this.isRead, actionable: actionable ?? this.actionable);
}

@immutable
class FeedPage {
  const FeedPage(this.posts, this.nextCursor);
  final List<FeedPost> posts;
  final DateTime? nextCursor; // paginación por cursor (created_at), null = no hay más
}
