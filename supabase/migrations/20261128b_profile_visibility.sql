-- =====================================================================================================================
-- Plobby · Seguridad Fase 1b (22 nov 2026): visibilidad de perfiles (decisión del usuario: «Limitar»).
--
--   Cualquier usuario autenticado ve de otro: id, nombre visible, usuario, foto/avatar y nivel declarado.
--   Solo el propio usuario y sus amigos ven: ciudad, club, bio, lado, mano y pareja habitual (vía RPC get_profile).
--
-- ⚠️ ROMPE versiones de la app ANTERIORES a la que lee el perfil con `get_profile` (rama seguridad-legal): en esas, abrir
--    un perfil daría error de permisos. Aplicar SOLO cuando todos los móviles/web tengan la versión nueva.
-- Requiere 20261128a. No borra datos.
-- =====================================================================================================================

-- Ciudad visible solo para uno mismo y amigos (la usan las vistas de amigos/solicitudes y la búsqueda)
create or replace function private.visible_city(p_user uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when private.can_view_user(p_user) then (select p.city from public.profiles p where p.id = p_user) end;
$$;
revoke all on function private.visible_city(uuid) from public, anon;
grant execute on function private.visible_city(uuid) to authenticated;

-- Columnas legibles de profiles por la API: solo las públicas
revoke select on public.profiles from authenticated;
grant select (id, display_name, username, avatar_url, avatar_id, self_declared_level) on public.profiles to authenticated;

-- Vistas (security_invoker): la ciudad pasa por private.visible_city
create or replace view public.v_my_friends with (security_invoker = true) as
 select p.id as user_id, p.display_name, p.username, p.avatar_url, private.visible_city(p.id) as city, pr.elo,
    public.rating_level(pr.elo) as level,
    ((select count(*) from public.friendships a join public.friendships b on a.friend_id = b.friend_id
       where a.user_id = (select auth.uid()) and b.user_id = p.id))::integer as mutual_friends,
    null::text as last_match_label, 0 as streak
   from public.friendships f join public.profiles p on p.id = f.friend_id left join public.player_ratings pr on pr.user_id = p.id
  where f.user_id = (select auth.uid()) and f.status = 'accepted';

create or replace view public.v_my_friend_requests with (security_invoker = true) as
 select r.id as request_id, case when r.receiver_id = (select auth.uid()) then 'incoming' else 'outgoing' end as direction,
    r.created_at, p.id as user_id, p.display_name, p.username, p.avatar_url, private.visible_city(p.id) as city, pr.elo,
    public.rating_level(pr.elo) as level
   from public.friend_requests r
     join public.profiles p on p.id = case when r.receiver_id = (select auth.uid()) then r.sender_id else r.receiver_id end
     left join public.player_ratings pr on pr.user_id = p.id
  where r.status = 'pending' and (r.sender_id = (select auth.uid()) or r.receiver_id = (select auth.uid()));
revoke all on public.v_my_friends, public.v_my_friend_requests from anon, authenticated;
grant select on public.v_my_friends, public.v_my_friend_requests to authenticated;

-- Búsqueda y sugerencias: la ciudad solo de amigos (las sugerencias siguen pudiendo decir «Misma ciudad»)
create or replace function public.search_players(q text)
 returns table(user_id uuid, display_name text, username text, avatar_url text, city text, elo integer, level text, relation text)
 language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select p.id, p.display_name, p.username, p.avatar_url, private.visible_city(p.id), pr.elo, public.rating_level(pr.elo),
    case
      when exists (select 1 from friendships f where f.user_id = auth.uid() and f.friend_id = p.id and f.status = 'accepted') then 'friend'
      when exists (select 1 from friend_requests r where r.sender_id = auth.uid() and r.receiver_id = p.id and r.status = 'pending') then 'requestSent'
      when exists (select 1 from friend_requests r where r.receiver_id = auth.uid() and r.sender_id = p.id and r.status = 'pending') then 'requestReceived'
      else 'none' end
  from profiles p left join player_ratings pr on pr.user_id = p.id
  where p.id <> auth.uid() and length(trim(q)) >= 2
    and (p.display_name ilike '%' || trim(q) || '%' or p.username ilike '%' || trim(q) || '%')
  order by p.display_name limit 30;
$$;

create or replace function public.suggest_friends()
 returns table(user_id uuid, display_name text, username text, avatar_url text, city text, elo integer, level text, mutual_friends integer, reason text)
 language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  with me as (select p.city, p.home_club, coalesce(pr.elo, 1000) as elo from profiles p left join player_ratings pr on pr.user_id = p.id where p.id = auth.uid()),
  cand as (
    select p.id, p.display_name, p.username, p.avatar_url, pr.elo, public.rating_level(pr.elo) as lvl,
      (select count(*) from friendships a join friendships b on a.friend_id = b.friend_id where a.user_id = auth.uid() and b.user_id = p.id)::int as mutual,
      (p.city is not distinct from (select city from me)) as same_city,
      (p.home_club is not distinct from (select home_club from me) and p.home_club is not null) as same_club,
      abs(coalesce(pr.elo, 1000) - (select elo from me)) <= 60 as similar_elo
    from profiles p left join player_ratings pr on pr.user_id = p.id
    where p.id <> auth.uid()
      and not exists (select 1 from friendships f where f.user_id = auth.uid() and f.friend_id = p.id)
      and not exists (select 1 from friend_requests r where r.status = 'pending' and ((r.sender_id = auth.uid() and r.receiver_id = p.id) or (r.receiver_id = auth.uid() and r.sender_id = p.id))))
  select id, display_name, username, avatar_url, null::text, elo, lvl, mutual,
    concat_ws(' · ', case when mutual > 0 then mutual || ' amigos en común' end, case when same_club then 'Mismo club' end, case when same_city then 'Misma ciudad' end, case when similar_elo then 'ELO similar' end)
  from cand where mutual > 0 or same_club or same_city or similar_elo
  order by mutual desc, same_club desc, same_city desc limit 10;
$$;
revoke all on function public.search_players(text), public.suggest_friends() from public, anon;
grant execute on function public.search_players(text), public.suggest_friends() to authenticated;
