import '../domain/feed_models.dart';

abstract class FeedRepository {
  FeedUser get me;
  Future<FeedPage> fetchPage({required FeedFilter filter, DateTime? before, int limit = 8});
  Future<void> setReaction(String postId, ReactionType? type); // null = quitar
  Future<List<(FeedUser, ReactionType)>> reactionsFor(String postId);
  Future<List<FeedComment>> comments(String postId);
  Future<FeedComment> addComment(String postId, String content);
  Future<void> deleteComment(String commentId);
  Future<void> reportComment(String commentId);
  Future<List<AppNotification>> notifications();
  Future<void> markRead(String? notificationId); // null = todas
  Future<void> respond(String notificationId, bool accept);
  /// Nueva actividad en tiempo real (Supabase Realtime sobre feed_posts).
  Stream<FeedPost> watchNew();
}
