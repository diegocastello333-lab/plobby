import 'feed_repository.dart';

/// Punto de integración con Supabase (NO implementado en este paquete).
///
/// Implementación prevista (cliente `supabase_flutter`, solo clave anon; nunca la service role):
///  - fetchPage: `from('feed_posts').select('*, author:profiles(*), reactions(count), comments(count)')`
///      `.lt('created_at', cursor).order('created_at', ascending: false).limit(n)`; la RLS ya limita a amigos.
///  - setReaction: `rpc('set_reaction', {p_post_id, p_type})` (upsert/delete atómico, una por usuario y post).
///  - watchNew: `channel('feed').onPostgresChanges(INSERT, table: 'feed_posts')`; actualizar contadores con
///    `onPostgresChanges(table: 'reactions')` sin recargar la lista.
///  - notifications: `from('notifications').select().eq('recipient_user_id', uid)`; markRead con update.
/// Ver supabase/migrations/20261111_feed.sql (tablas, índices, RLS, generación de eventos).
abstract class SupabaseFeedRepositoryPlaceholder implements FeedRepository {}
