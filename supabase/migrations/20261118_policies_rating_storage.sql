-- Plobby · Políticas RLS de las tablas base, ELO en servidor y almacenamiento de fotos de grupo.
-- Principio: el cliente SOLO lee (y solo lo que le corresponde); toda escritura sensible pasa por funciones security definer.

-- ── helpers (security definer para evitar recursión de RLS)
create or replace function public.is_league_member(p_league uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.league_members where league_id = p_league and user_id = auth.uid())
      or exists (select 1 from public.leagues where id = p_league and created_by = auth.uid());
$$;
grant execute on function public.is_league_member(uuid) to authenticated;

-- ── clubes y pistas: lectura para usuarios con sesión; altas solo desde el servidor (service role / panel)
create policy clubs_read  on public.clubs  for select to authenticated using (true);
create policy courts_read on public.courts for select to authenticated using (true);

-- ── amistades: cada usuario ve las suyas; se crean/borran solo vía RPC (send/respond/remove_friend)
create policy friendships_read_own on public.friendships for select to authenticated using (user_id = auth.uid());

-- ── ligas
create policy leagues_read on public.leagues for select to authenticated using (public.is_league_member(id));
create policy league_members_read on public.league_members for select to authenticated using (public.is_league_member(league_id));

-- ── partidos: solo sus participantes los ven; NINGUNA política de escritura (create_match, start_match,
--    submit_result, respond_result… son las únicas vías y validan el ciclo de vida en servidor)
create policy matches_read_participants on public.matches for select to authenticated using (public._is_participant(id, auth.uid()));
create policy match_players_read on public.match_players for select to authenticated using (public._is_participant(match_id, auth.uid()));
create policy match_sets_read on public.match_sets for select to authenticated using (public._is_participant(match_id, auth.uid()));

-- ── logros: los propios y los de amigos
create policy user_achievements_read on public.user_achievements for select to authenticated using (user_id = auth.uid() or public.can_view_user(user_id));

-- ── ELO (servidor): equipo contra equipo, K=32, límites de rating_config. Idempotente por partido.
create or replace function public.apply_match_rating(p_match_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t1 numeric; t2 numeric; g1 int; g2 int; w smallint; e1 numeric; k constant numeric := 32; mn int; mx int; r record; d int;
begin
  if exists (select 1 from public.rating_history where match_id = p_match_id) then return; end if;
  select min_rating, max_rating into mn, mx from public.rating_config where id = 1;
  insert into public.player_ratings (user_id) select user_id from public.match_players where match_id = p_match_id on conflict do nothing;
  select sum(case when s.team1_games > s.team2_games then 1 else 0 end), sum(case when s.team2_games > s.team1_games then 1 else 0 end)
    into g1, g2 from public.match_sets s where s.match_id = p_match_id;
  if coalesce(g1,0) = coalesce(g2,0) then return; end if;                    -- sin ganador claro: no se toca el ELO
  w := case when g1 > g2 then 1 else 2 end;
  select avg(pr.elo) filter (where mp.team = 1), avg(pr.elo) filter (where mp.team = 2) into t1, t2
    from public.match_players mp join public.player_ratings pr on pr.user_id = mp.user_id where mp.match_id = p_match_id;
  e1 := 1 / (1 + power(10, (t2 - t1) / 400));
  for r in select mp.user_id, mp.team, pr.elo from public.match_players mp join public.player_ratings pr on pr.user_id = mp.user_id where mp.match_id = p_match_id loop
    d := round(k * ((case when r.team = w then 1 else 0 end) - (case when r.team = 1 then e1 else 1 - e1 end)));
    d := greatest(mn, least(mx, r.elo + d)) - r.elo;
    insert into public.rating_history (user_id, match_id, rating_before, delta) values (r.user_id, p_match_id, r.elo, d);
    update public.player_ratings set elo = elo + d, best_elo = greatest(best_elo, elo + d), updated_at = now() where user_id = r.user_id;
    update public.match_players set elo_delta = d where match_id = p_match_id and user_id = r.user_id;
    update public.feed_posts set metadata = metadata || jsonb_build_object('elo_delta', d) where dedupe_key = 'match:' || p_match_id || ':' || r.user_id;
  end loop;
end $$;
revoke all on function public.apply_match_rating(uuid) from public, authenticated, anon;

-- ── nuevo perfil → fila de rating inicial
create or replace function public._init_rating() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.player_ratings (user_id) values (new.id) on conflict do nothing; return new; end $$;
drop trigger if exists profiles_init_rating on public.profiles;
create trigger profiles_init_rating after insert on public.profiles for each row execute function public._init_rating();
insert into public.player_ratings (user_id) select id from public.profiles on conflict do nothing;

-- ── fotos de grupo: bucket privado `group-avatars`, ruta `<conversation_id>/avatar.jpg`; miembros leen, admins escriben
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('group-avatars', 'group-avatars', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy ga_read  on storage.objects for select to authenticated using (bucket_id = 'group-avatars' and public.is_member((split_part(name, '/', 1))::uuid));
create policy ga_write on storage.objects for insert to authenticated with check (bucket_id = 'group-avatars' and public.is_group_admin((split_part(name, '/', 1))::uuid));
create policy ga_upd   on storage.objects for update to authenticated using (bucket_id = 'group-avatars' and public.is_group_admin((split_part(name, '/', 1))::uuid));
