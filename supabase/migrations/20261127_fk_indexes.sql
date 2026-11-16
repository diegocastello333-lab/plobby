-- Plobby · Índices en claves foráneas sin índice (asesor de rendimiento de Supabase, 16 nov 2026).
-- Solo añade índices: no cambia datos, permisos ni políticas. Aceleran los JOIN por estas columnas y los borrados en
-- cascada de clubes, pistas y perfiles cuando las tablas crezcan.
create index if not exists comment_reports_reporter_idx on public.comment_reports (reporter_id);
create index if not exists feed_posts_related_achievement_idx on public.feed_posts (related_achievement_id);
create index if not exists matches_club_idx on public.matches (club_id);
create index if not exists matches_court_idx on public.matches (court_id);
create index if not exists matches_started_by_idx on public.matches (started_by);
create index if not exists matches_ended_by_idx on public.matches (ended_by);
create index if not exists tournament_matches_updated_by_idx on public.tournament_matches (updated_by);
