-- Plobby · 13 nov 2026: endurecimiento de seguridad y rendimiento de RLS. Sin cambios de datos ni de funcionalidad.

-- 1) Torneos: el rol anónimo no necesita nada (la RLS ya devolvía 0 filas, ahora ni siquiera hay permiso).
revoke all on public.tournaments, public.tournament_admins, public.tournament_teams, public.tournament_players, public.tournament_matches from anon;
revoke execute on function public._t_can_view(uuid), public._t_is_admin(uuid) from anon, public;
alter function public._t_seed_order(int) set search_path = public;

-- 2) Perfiles: la foto solo puede apuntar a la carpeta propia del bucket `avatars` (antes se podía poner cualquier URL
--    externa con un UPDATE directo: imágenes ajenas o un «píxel espía» que revelaría la IP de quien ve el perfil).
--    Textos libres acotados (se recortan, nunca bloquean un registro: el nombre viene de Google en el alta).
create or replace function public._profiles_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.avatar_url is distinct from old.avatar_url and new.avatar_url is not null
     and new.avatar_url not like '%/storage/v1/object/public/avatars/' || new.id::text || '/%' then
    raise exception 'invalid_avatar_url';
  end if;
  new.display_name := left(btrim(new.display_name), 60);
  new.city := nullif(left(btrim(new.city), 60), '');
  new.habitual_club := nullif(left(btrim(new.habitual_club), 80), '');
  return new;
end $$;
revoke execute on function public._profiles_guard() from public, anon, authenticated;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before insert or update on public.profiles for each row execute function public._profiles_guard();

-- 3) Reacciones y comentarios: solo las columnas necesarias (antes se podía mover una reacción a otra publicación o
--    falsear la fecha / el estado «oculto» de un comentario).
revoke insert, update on public.reactions from authenticated;
grant insert (post_id, user_id, reaction_type) on public.reactions to authenticated;
grant update (reaction_type) on public.reactions to authenticated;
revoke insert on public.comments from authenticated;
grant insert (post_id, user_id, content) on public.comments to authenticated;

-- 4) Límite de frecuencia en el servidor (abuso automatizado / spam). Holgado para un uso normal.
create or replace function public._rate_limit() returns trigger language plpgsql security definer set search_path = public as $$
declare n int; who uuid := auth.uid();
begin
  if who is null then return new; end if;   -- procesos internos (triggers del sistema) no se limitan
  case tg_table_name
    when 'comments' then select count(*) into n from public.comments where user_id = who and created_at > now() - interval '1 minute';
      if n >= 10 then raise exception 'rate_limited'; end if;
    when 'messages' then select count(*) into n from public.messages where sender_id = who and created_at > now() - interval '1 minute';
      if n >= 40 then raise exception 'rate_limited'; end if;
    when 'friend_requests' then select count(*) into n from public.friend_requests where sender_id = who and created_at > now() - interval '1 hour';
      if n >= 40 then raise exception 'rate_limited'; end if;
    when 'comment_reports' then select count(*) into n from public.comment_reports where reporter_id = who and created_at > now() - interval '1 hour';
      if n >= 20 then raise exception 'rate_limited'; end if;
    else null;
  end case;
  return new;
end $$;
revoke execute on function public._rate_limit() from public, anon, authenticated;
drop trigger if exists comments_rate_limit on public.comments;
create trigger comments_rate_limit before insert on public.comments for each row execute function public._rate_limit();
drop trigger if exists messages_rate_limit on public.messages;
create trigger messages_rate_limit before insert on public.messages for each row execute function public._rate_limit();
drop trigger if exists friend_requests_rate_limit on public.friend_requests;
create trigger friend_requests_rate_limit before insert on public.friend_requests for each row execute function public._rate_limit();
drop trigger if exists comment_reports_rate_limit on public.comment_reports;
create trigger comment_reports_rate_limit before insert on public.comment_reports for each row execute function public._rate_limit();
create index if not exists messages_sender_created_idx on public.messages (sender_id, created_at desc);
create index if not exists comments_user_created_idx on public.comments (user_id, created_at desc);

-- 5) Storage: el bucket `avatars` es público para VER las imágenes por su URL (no necesita política), pero la política
--    `avatars_read` permitía además LISTAR las carpetas de todos los usuarios (enumerar ids). Ahora cada usuario solo
--    lista su carpeta (lo necesita la app para borrar sus fotos antiguas).
drop policy if exists avatars_read on storage.objects;
create policy avatars_read_own on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- 6) Rendimiento RLS: `auth.uid()` se evaluaba en CADA fila; envuelto en (select …) se evalúa una vez por consulta.
--    Misma condición, mismo resultado.
do $$
declare p record; q text; w text; s text;
begin
  for p in select schemaname, tablename, policyname, qual, with_check from pg_policies
           where schemaname in ('public', 'realtime')
             and (coalesce(qual, '') ~ 'auth\.uid\(\)' or coalesce(with_check, '') ~ 'auth\.uid\(\)') loop
    q := regexp_replace(p.qual, '(?<!select )auth\.uid\(\)', '(select auth.uid())', 'gi');
    w := regexp_replace(p.with_check, '(?<!select )auth\.uid\(\)', '(select auth.uid())', 'gi');
    s := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    if q is not null then s := s || format(' using (%s)', q); end if;
    if w is not null then s := s || format(' with check (%s)', w); end if;
    execute s;
  end loop;
end $$;

-- 7) Índices de claves ajenas que se usan en uniones y borrados en cascada.
create index if not exists tournament_admins_user_idx on public.tournament_admins (user_id);
create index if not exists tournament_matches_next_idx on public.tournament_matches (next_match_id);
create index if not exists tournament_matches_team1_idx on public.tournament_matches (team1_id);
create index if not exists tournament_matches_team2_idx on public.tournament_matches (team2_id);
create index if not exists tournament_matches_winner_idx on public.tournament_matches (winner_team_id);
create index if not exists tournament_players_team_idx on public.tournament_players (team_id);
create index if not exists tournament_teams_p1_idx on public.tournament_teams (player1_id);
create index if not exists tournament_teams_p2_idx on public.tournament_teams (player2_id);
create index if not exists tournaments_created_by_idx on public.tournaments (created_by);
create index if not exists tournaments_champion_idx on public.tournaments (champion_team_id);
create index if not exists profiles_habitual_partner_idx on public.profiles (habitual_partner_id);
create index if not exists notifications_related_post_idx on public.notifications (related_post_id);
create index if not exists feed_posts_related_match_idx on public.feed_posts (related_match_id);
create index if not exists match_result_versions_proposed_by_idx on public.match_result_versions (proposed_by);
