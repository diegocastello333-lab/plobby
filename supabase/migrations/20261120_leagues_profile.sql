-- Plobby · Ligas completas, historial de perfil y corrección de la validación de sets.
--
-- Contexto (comprobado contra el proyecto remoto `plobby` antes de escribir esta migración):
--   · Ya existen y NO se recrean: profiles, friendships, matches, match_players, match_sets, player_ratings, rating_history,
--     notifications, feed_posts, conversations/messages (grupos), match_result_versions/acceptances, match_events.
--   · `leagues` solo tenía (id, name, created_by, club_id, created_at) y `league_members` (league_id, user_id, joined_at):
--     aquí se amplían con todo lo que usa el prototipo (descripción, visibilidad, temporada, reglas, roles, invitaciones,
--     solicitudes de acceso y clasificación).
--   · Mismo modelo de seguridad que el resto del esquema: el cliente solo LEE (RLS); toda escritura pasa por funciones
--     `security definer` que validan permisos. anon no tiene acceso a nada.
--
-- Supuestos (revisar antes de aplicar):
--   S1. Puntuación de liga (prototipo `pts = jugados + 2·ganados`): victoria = points_win (3 por defecto), derrota = points_loss (1),
--       +1 de bonus por ganar sin ceder set si bonus_enabled. Solo cuentan partidos de liga CONFIRMADOS por los dos capitanes.
--   S2. Visibilidad: 'public' (cualquiera se une), 'private' (con código o invitación) y 'club' (se solicita acceso y lo aprueba
--       el organizador/administrador). Las ligas de club no se crean desde la app (las da de alta el club desde el panel).
--   S3. Validación de resultados: se mantiene la del ciclo de vida existente (confirman los dos capitanes). No se añade la
--       opción «valida el organizador» del prototipo para no duplicar el flujo de disputa.
--   S4. Movimiento de puestos (+2 / −1) no se persiste: el prototipo lo muestra, pero requeriría instantáneas por jornada.
--
-- Idempotente en lo posible (if not exists / create or replace / drop policy if exists).

-- ════════════════════════════════════════════════════════════════════════════════════════
-- 1. PERFIL: bio editable y columnas que el propio usuario puede actualizar
-- ════════════════════════════════════════════════════════════════════════════════════════
alter table public.profiles add column if not exists bio text;
alter table public.profiles drop constraint if exists profiles_bio_len_chk;
alter table public.profiles add constraint profiles_bio_len_chk check (bio is null or char_length(bio) <= 280);
grant select (bio) on public.profiles to authenticated;   -- la concesión por columnas de 20261119_hardening no incluía columnas nuevas

-- Antes: UPDATE sobre TODAS las columnas (incluidas username, onboarding_completed_at…). Ahora solo los campos de «Editar perfil».
-- username, nivel, fecha de nacimiento y onboarding siguen cambiando solo vía save_onboarding_step / complete_onboarding.
revoke insert, update on public.profiles from authenticated;      -- el perfil lo crea el trigger handle_new_user
grant update (display_name, bio, city, avatar_url, avatar_id, court_side, dominant_hand, habitual_club, updated_at) on public.profiles to authenticated;

-- Pareja habitual: solo un amigo aceptado (o null para quitarla).
create or replace function public.set_habitual_partner(p_partner uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_partner is not null and (p_partner = auth.uid() or not public._is_friend(auth.uid(), p_partner)) then
    raise exception 'partner_must_be_friend';
  end if;
  update public.profiles set habitual_partner_id = p_partner, updated_at = now() where id = auth.uid();
end $$;

-- Historial de un jugador para el perfil (propio o de un amigo). Los ajenos solo ven partidos CONFIRMADOS.
-- Sets en orden [equipo1, equipo2]; el cliente los orienta con `team`. Para partidos pendientes se usa la versión vigente.
create or replace function public.get_player_history(p_user uuid, p_limit int default 200) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.r order by x.at desc), '[]'::jsonb) from (
    select coalesce(m.played_at, m.ended_at, m.scheduled_at, m.created_at) as at,
      jsonb_build_object(
        'match_id', m.id,
        'played_at', coalesce(m.played_at, m.ended_at, m.scheduled_at, m.created_at),
        'status', m.status,
        'confirmed', m.status = 'confirmed',
        'is_league', m.match_type = 'league',
        'league_name', l.name,
        'venue', coalesce(m.club, ''),
        'team', me.team,
        'elo_delta', coalesce(me.elo_delta, 0),
        'sets', case when m.status = 'confirmed'
                  then (select coalesce(jsonb_agg(jsonb_build_array(s.team1_games, s.team2_games) order by s.set_no), '[]'::jsonb) from public.match_sets s where s.match_id = m.id)
                  else coalesce((select v.sets from public.match_result_versions v where v.match_id = m.id and v.version = m.result_version), '[]'::jsonb) end,
        'players', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name, 'avatar_url', p.avatar_url, 'team', mp.team)), '[]'::jsonb)
                      from public.match_players mp join public.profiles p on p.id = mp.user_id where mp.match_id = m.id)
      ) as r
    from public.matches m
    join public.match_players me on me.match_id = m.id and me.user_id = p_user
    left join public.leagues l on l.id = m.league_id
    where (p_user = auth.uid() or public.can_view_user(p_user))
      and (m.status = 'confirmed' or (p_user = auth.uid() and m.status in ('pending_confirmation', 'disputed')))
    order by 1 desc
    limit greatest(1, least(coalesce(p_limit, 200), 500))
  ) x;
$$;

-- ════════════════════════════════════════════════════════════════════════════════════════
-- 2. CORRECCIÓN: _validate_sets aceptaba un set después de 2-0 cuando el tercero lo ganaba el perdedor (6-4 6-3 3-6).
--    Misma regla que validateSets() en Flutter: el partido termina cuando una pareja gana 2 sets.
-- ════════════════════════════════════════════════════════════════════════════════════════
create or replace function public._validate_sets(p_sets jsonb) returns smallint
language plpgsql immutable set search_path = public as $$
declare n int; a int := 0; b int := 0; i int; x int; y int; hi int; lo int;
begin
  if p_sets is null or jsonb_typeof(p_sets) <> 'array' then raise exception 'invalid_sets'; end if;
  n := jsonb_array_length(p_sets);
  if n < 2 or n > 3 then raise exception 'invalid_sets'; end if;
  for i in 0 .. n - 1 loop
    if a = 2 or b = 2 then raise exception 'match_already_decided'; end if;
    x := (p_sets->i->>0)::int; y := (p_sets->i->>1)::int;
    if x is null or y is null then raise exception 'invalid_set_%', i + 1; end if;
    hi := greatest(x, y); lo := least(x, y);
    if not ((hi = 6 and lo <= 4) or (hi = 7 and lo in (5, 6))) then raise exception 'invalid_set_%', i + 1; end if;
    if x > y then a := a + 1; else b := b + 1; end if;
  end loop;
  if a < 2 and b < 2 then raise exception 'third_set_required'; end if;
  return case when a > b then 1 else 2 end;
end $$;

-- ════════════════════════════════════════════════════════════════════════════════════════
-- 3. LIGAS
-- ════════════════════════════════════════════════════════════════════════════════════════
alter table public.leagues
  add column if not exists description text not null default '',
  add column if not exists visibility text not null default 'private',
  add column if not exists invite_code text,
  add column if not exists cover text not null default 'lines',
  add column if not exists location text not null default '',
  add column if not exists level_min text not null default 'Iniciación',
  add column if not exists level_max text not null default 'Avanzado',
  add column if not exists season text not null default '01',
  add column if not exists starts_on date,
  add column if not exists ends_on date,
  add column if not exists min_players int not null default 2,
  add column if not exists max_players int not null default 16,
  add column if not exists format text not null default 'individual',
  add column if not exists matches_per_player int not null default 10,
  add column if not exists points_win int not null default 3,
  add column if not exists points_loss int not null default 1,
  add column if not exists bonus_enabled boolean not null default true,
  add column if not exists challenges_enabled boolean not null default true,
  add column if not exists ended_at timestamptz;

alter table public.leagues drop constraint if exists leagues_rules_chk;
alter table public.leagues add constraint leagues_rules_chk check (
  visibility in ('public', 'private', 'club')
  and format in ('individual', 'pairs')
  and char_length(description) <= 180
  and min_players between 2 and 64 and max_players between 2 and 64 and min_players <= max_players
  and matches_per_player between 1 and 50
  and points_win between 1 and 5 and points_loss between 0 and 2
  and (starts_on is null or ends_on is null or ends_on > starts_on));
alter table public.leagues drop constraint if exists leagues_name_len_chk;
alter table public.leagues add constraint leagues_name_len_chk check (char_length(btrim(name)) between 3 and 40) not valid;
create unique index if not exists leagues_invite_code_uq on public.leagues (invite_code) where invite_code is not null;
create index if not exists leagues_created_by_idx on public.leagues (created_by);
create index if not exists leagues_visibility_idx on public.leagues (visibility) where ended_at is null;

alter table public.league_members add column if not exists role text not null default 'player';
alter table public.league_members drop constraint if exists league_members_role_chk;
alter table public.league_members add constraint league_members_role_chk check (role in ('organizer', 'admin', 'player'));
update public.league_members lm set role = 'organizer' from public.leagues l
 where l.id = lm.league_id and l.created_by = lm.user_id and lm.role = 'player';

-- Invitaciones directas (amigos invitados por un gestor): permiten unirse a una liga privada sin código.
create table if not exists public.league_invites (
  league_id  uuid not null references public.leagues(id) on delete cascade,
  user_id    uuid not null constraint league_invites_user_fk references public.profiles(id) on delete cascade,
  invited_by uuid constraint league_invites_inviter_fk references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
create index if not exists league_invites_user_idx on public.league_invites (user_id);
create index if not exists league_invites_inviter_idx on public.league_invites (invited_by);

-- Solicitudes de acceso (ligas de club). Una pendiente como máximo por usuario y liga.
create table if not exists public.league_join_requests (
  id           uuid primary key default gen_random_uuid(),
  league_id    uuid not null references public.leagues(id) on delete cascade,
  user_id      uuid not null constraint league_join_requests_user_fk references public.profiles(id) on delete cascade,
  message      text not null default '' check (char_length(message) <= 140),
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  responded_by uuid constraint league_join_requests_responder_fk references public.profiles(id) on delete set null
);
create unique index if not exists league_join_requests_pending_uq on public.league_join_requests (league_id, user_id) where status = 'pending';
create index if not exists league_join_requests_user_idx on public.league_join_requests (user_id);
create index if not exists league_join_requests_responder_idx on public.league_join_requests (responded_by);

alter table public.league_invites enable row level security;
alter table public.league_join_requests enable row level security;

-- ── helpers (security definer → sin recursión de RLS)
create or replace function public.league_role(p_league uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.league_members where league_id = p_league and user_id = auth.uid();
$$;
create or replace function public.is_league_manager(p_league uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.league_role(p_league) in ('organizer', 'admin'), false);
$$;
-- Ver una liga: miembros, invitados y cualquiera si es pública o de club (para descubrirla y solicitar acceso).
create or replace function public.can_view_league(p_league uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_league_member(p_league)
      or exists (select 1 from public.leagues l where l.id = p_league and l.visibility in ('public', 'club'))
      or exists (select 1 from public.league_invites i where i.league_id = p_league and i.user_id = auth.uid());
$$;
-- Un partido de liga lo ven también los miembros de esa liga (clasificación, pestaña «Partidos», disputas).
create or replace function public._can_view_league_match(p_match uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.matches m where m.id = p_match and m.match_type = 'league' and m.league_id is not null and public.is_league_member(m.league_id));
$$;
create or replace function public.league_status(p_ended timestamptz, p_starts date) returns text
language sql immutable set search_path = public as $$
  select case when p_ended is not null then 'ended' when p_starts is not null and p_starts > current_date then 'open' else 'running' end;
$$;

-- ── RLS
drop policy if exists leagues_read on public.leagues;
create policy leagues_read on public.leagues for select to authenticated using (public.can_view_league(id));
drop policy if exists league_members_read on public.league_members;
create policy league_members_read on public.league_members for select to authenticated using (public.can_view_league(league_id));
drop policy if exists league_invites_read on public.league_invites;
create policy league_invites_read on public.league_invites for select to authenticated using (user_id = auth.uid() or public.is_league_manager(league_id));
drop policy if exists league_join_requests_read on public.league_join_requests;
create policy league_join_requests_read on public.league_join_requests for select to authenticated using (user_id = auth.uid() or public.is_league_manager(league_id));

drop policy if exists matches_read_league on public.matches;
create policy matches_read_league on public.matches for select to authenticated using (match_type = 'league' and league_id is not null and public.is_league_member(league_id));
drop policy if exists match_players_read_league on public.match_players;
create policy match_players_read_league on public.match_players for select to authenticated using (public._can_view_league_match(match_id));
drop policy if exists match_sets_read_league on public.match_sets;
create policy match_sets_read_league on public.match_sets for select to authenticated using (public._can_view_league_match(match_id));

-- Sin escritura directa: ni políticas de INSERT/UPDATE/DELETE ni privilegios. El código de invitación no es legible con select().
revoke insert, update, delete on public.leagues, public.league_members, public.league_invites, public.league_join_requests from authenticated, anon;
revoke all on public.league_invites, public.league_join_requests from anon;
grant select on public.league_invites, public.league_join_requests to authenticated;
revoke select on public.leagues from authenticated;
do $$ declare cols text; begin
  select string_agg(quote_ident(column_name), ', ') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'leagues' and column_name <> 'invite_code';
  execute 'grant select (' || cols || ') on public.leagues to authenticated';
end $$;

-- ── notificaciones internas de liga (reutiliza el tipo existente league_invite; el título distingue el caso)
create or replace function public._league_notify(p_to uuid, p_league uuid, p_title text, p_body text, p_key text) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
  values (p_to, auth.uid(), 'league_invite', p_league, p_title, p_body, p_key)
  on conflict do nothing;
$$;

-- ── RPC: crear liga. El creador queda como organizador; los invitados (solo amigos) reciben invitación.
create or replace function public.create_league(
  p_name text, p_description text, p_visibility text, p_cover text, p_location text,
  p_level_min text, p_level_max text, p_starts_on date, p_ends_on date,
  p_min_players int, p_max_players int, p_format text, p_matches_per_player int,
  p_points_win int, p_bonus boolean, p_challenges boolean, p_invited uuid[] default '{}'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); lid uuid; nm text := upper(btrim(coalesce(p_name, ''))); code text; u uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if char_length(nm) < 3 or char_length(nm) > 40 then raise exception 'invalid_league_name'; end if;
  if p_starts_on is null or p_ends_on is null or p_ends_on <= p_starts_on then raise exception 'invalid_league_dates'; end if;
  if coalesce(p_min_players, 2) > coalesce(p_max_players, 16) then raise exception 'invalid_league_players'; end if;
  if p_visibility not in ('public', 'private') then raise exception 'invalid_league_visibility'; end if;  -- S2: 'club' solo desde el panel
  code := coalesce(nullif(left(regexp_replace(nm, '[^A-Z0-9]+', '', 'g'), 8), ''), 'LIGA') || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 4));
  insert into public.leagues (name, description, visibility, invite_code, cover, location, level_min, level_max, starts_on, ends_on,
                              min_players, max_players, format, matches_per_player, points_win, bonus_enabled, challenges_enabled, created_by)
  values (nm, btrim(coalesce(p_description, '')), p_visibility, code, coalesce(p_cover, 'lines'), btrim(coalesce(p_location, '')),
          coalesce(p_level_min, 'Iniciación'), coalesce(p_level_max, 'Avanzado'), p_starts_on, p_ends_on,
          coalesce(p_min_players, 2), coalesce(p_max_players, 16), coalesce(p_format, 'individual'), coalesce(p_matches_per_player, 10),
          coalesce(p_points_win, 3), coalesce(p_bonus, true), coalesce(p_challenges, true), me)
  returning id into lid;
  insert into public.league_members (league_id, user_id, role) values (lid, me, 'organizer');
  foreach u in array coalesce(p_invited, '{}'::uuid[]) loop
    if u <> me and public._is_friend(me, u) then
      insert into public.league_invites (league_id, user_id, invited_by) values (lid, u, me) on conflict do nothing;
      perform public._league_notify(u, lid, 'Invitación a liga', 'Te han invitado a ' || nm, 'league_invite:' || lid);
    end if;
  end loop;
  perform public.emit_feed_event(me, 'league', 'league_created:' || lid, null, null,
    jsonb_build_object('league_id', lid, 'league_name', nm, 'headline', 'Creó una liga', 'subtitle', 'Temporada 01'));
  return jsonb_build_object('id', lid, 'invite_code', code);
end $$;

-- ── RPC: invitar amigos (gestores)
create or replace function public.invite_to_league(p_league uuid, p_user_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare u uuid; n int := 0; nm text;
begin
  if not public.is_league_manager(p_league) then raise exception 'not_league_manager'; end if;
  select name into nm from public.leagues where id = p_league;
  foreach u in array coalesce(p_user_ids, '{}'::uuid[]) loop
    continue when u = auth.uid() or not public._is_friend(auth.uid(), u)
      or exists (select 1 from public.league_members where league_id = p_league and user_id = u);
    insert into public.league_invites (league_id, user_id, invited_by) values (p_league, u, auth.uid()) on conflict do nothing;
    perform public._league_notify(u, p_league, 'Invitación a liga', 'Te han invitado a ' || nm, 'league_invite:' || p_league);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ── RPC: unirse. Devuelve 'joined' | 'requested' | 'already_member'.
--    pública → entra; privada → código o invitación; club → solicitud que aprueba un gestor.
create or replace function public.join_league(p_league uuid, p_code text default null, p_message text default null) returns text
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); l public.leagues; n int; m uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select * into l from public.leagues where id = p_league for update;
  if not found then raise exception 'league_not_found'; end if;
  if exists (select 1 from public.league_members where league_id = p_league and user_id = me) then return 'already_member'; end if;
  if l.ended_at is not null then raise exception 'league_ended'; end if;
  select count(*) into n from public.league_members where league_id = p_league;
  if n >= l.max_players then raise exception 'league_full'; end if;

  if l.visibility = 'public'
     or exists (select 1 from public.league_invites where league_id = p_league and user_id = me)
     or (p_code is not null and upper(btrim(p_code)) = l.invite_code) then
    insert into public.league_members (league_id, user_id, role) values (p_league, me, 'player');
    delete from public.league_invites where league_id = p_league and user_id = me;
    update public.league_join_requests set status = 'approved', responded_at = now() where league_id = p_league and user_id = me and status = 'pending';
    perform public.emit_feed_event(me, 'league', 'league_join:' || p_league || ':' || me, null, null,
      jsonb_build_object('league_id', p_league, 'league_name', l.name, 'headline', 'Se unió a la liga', 'subtitle', 'Temporada ' || l.season));
    return 'joined';
  end if;

  if l.visibility = 'private' then raise exception 'invite_code_required'; end if;
  insert into public.league_join_requests (league_id, user_id, message) values (p_league, me, left(btrim(coalesce(p_message, '')), 140))
    on conflict do nothing;
  for m in select user_id from public.league_members where league_id = p_league and role in ('organizer', 'admin') loop
    perform public._league_notify(m, p_league, 'Solicitud de acceso', 'Nueva solicitud para unirse a ' || l.name, 'league_req:' || p_league || ':' || me);
  end loop;
  return 'requested';
end $$;

create or replace function public.join_league_by_code(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare lid uuid;
begin
  select id into lid from public.leagues where invite_code = upper(btrim(coalesce(p_code, '')));
  if lid is null then raise exception 'invalid_invite_code'; end if;
  perform public.join_league(lid, p_code, null);
  return lid;
end $$;

-- Código de invitación: solo miembros (y en ligas de club, solo gestores, para no saltarse la aprobación).
create or replace function public.league_invite_code(p_league uuid) returns text
language sql stable security definer set search_path = public as $$
  select l.invite_code from public.leagues l
   where l.id = p_league and public.is_league_member(p_league) and (l.visibility <> 'club' or public.is_league_manager(p_league));
$$;

create or replace function public.respond_join_request(p_request uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare r public.league_join_requests; l public.leagues; n int;
begin
  select * into r from public.league_join_requests where id = p_request for update;
  if not found or r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  if not public.is_league_manager(r.league_id) then raise exception 'not_league_manager'; end if;
  select * into l from public.leagues where id = r.league_id for update;
  if p_accept then
    select count(*) into n from public.league_members where league_id = r.league_id;
    if n >= l.max_players then raise exception 'league_full'; end if;
    insert into public.league_members (league_id, user_id, role) values (r.league_id, r.user_id, 'player') on conflict do nothing;
  end if;
  update public.league_join_requests set status = case when p_accept then 'approved' else 'rejected' end, responded_at = now(), responded_by = auth.uid() where id = p_request;
  perform public._league_notify(r.user_id, r.league_id, case when p_accept then 'Solicitud aprobada' else 'Solicitud rechazada' end,
    case when p_accept then 'Ya formas parte de ' else 'No se aprobó tu solicitud para ' end || l.name, 'league_resp:' || p_request);
end $$;

-- Salir de la liga. El organizador no puede salir mientras haya otros miembros (si está solo, la liga se elimina).
create or replace function public.leave_league(p_league uuid) returns void
language plpgsql security definer set search_path = public as $$
declare rl text := public.league_role(p_league);
begin
  if rl is null then raise exception 'not_a_member'; end if;
  if rl = 'organizer' then
    if exists (select 1 from public.league_members where league_id = p_league and user_id <> auth.uid()) then raise exception 'organizer_cannot_leave'; end if;
    delete from public.leagues where id = p_league;
    return;
  end if;
  delete from public.league_members where league_id = p_league and user_id = auth.uid();
end $$;

create or replace function public.remove_league_member(p_league uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_league_manager(p_league) then raise exception 'not_league_manager'; end if;
  if p_user = auth.uid() then raise exception 'use_leave_league'; end if;
  if (select role from public.league_members where league_id = p_league and user_id = p_user) = 'organizer' then raise exception 'cannot_remove_organizer'; end if;
  delete from public.league_members where league_id = p_league and user_id = p_user;
end $$;

-- Editar liga (gestores). Claves admitidas: name, description, cover, location, starts_on, ends_on, max_players,
-- points_win, bonus_enabled, challenges_enabled, visibility ('club' solo un admin de club), ended (true = cerrar temporada).
create or replace function public.update_league(p_league uuid, p_patch jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare l public.leagues; v text;
begin
  if not public.is_league_manager(p_league) then raise exception 'not_league_manager'; end if;
  select * into l from public.leagues where id = p_league for update;
  v := coalesce(p_patch->>'visibility', l.visibility);
  if v = 'club' and l.visibility <> 'club' and public.league_role(p_league) <> 'admin' then raise exception 'club_visibility_requires_admin'; end if;
  if p_patch ? 'name' and char_length(btrim(p_patch->>'name')) not between 3 and 40 then raise exception 'invalid_league_name'; end if;
  update public.leagues set
    name = coalesce(upper(btrim(p_patch->>'name')), name),
    description = coalesce(btrim(p_patch->>'description'), description),
    cover = coalesce(p_patch->>'cover', cover),
    location = coalesce(p_patch->>'location', location),
    starts_on = coalesce((p_patch->>'starts_on')::date, starts_on),
    ends_on = coalesce((p_patch->>'ends_on')::date, ends_on),
    max_players = coalesce((p_patch->>'max_players')::int, max_players),
    points_win = coalesce((p_patch->>'points_win')::int, points_win),
    bonus_enabled = coalesce((p_patch->>'bonus_enabled')::boolean, bonus_enabled),
    challenges_enabled = coalesce((p_patch->>'challenges_enabled')::boolean, challenges_enabled),
    visibility = v,
    ended_at = case when (p_patch->>'ended')::boolean is true then coalesce(ended_at, now()) else ended_at end
  where id = p_league;
  if (select count(*) from public.league_members where league_id = p_league) > (select max_players from public.leagues where id = p_league) then
    raise exception 'max_below_members';
  end if;
end $$;

-- ── Clasificación (S1). Solo partidos de liga confirmados. Visible para quien puede ver la liga.
create or replace function public.league_standings(p_league uuid)
returns table (user_id uuid, display_name text, username text, avatar_url text, avatar_id text, elo int, role text,
               played int, wins int, losses int, bonus int, points int, win_pct int, rank int)
language sql stable security definer set search_path = public as $$
  with lg as (select * from public.leagues where id = p_league and public.can_view_league(p_league)),
  res as (
    select mp.user_id, (mp.team = case when g.t1 > g.t2 then 1 else 2 end) as won, least(g.t1, g.t2) = 0 as clean
    from public.matches m
    join public.match_players mp on mp.match_id = m.id
    cross join lateral (select count(*) filter (where s.team1_games > s.team2_games) t1, count(*) filter (where s.team2_games > s.team1_games) t2
                          from public.match_sets s where s.match_id = m.id) g
    where m.league_id = p_league and m.match_type = 'league' and m.status = 'confirmed' and g.t1 <> g.t2
  ),
  agg as (select r.user_id, count(*)::int played, (count(*) filter (where r.won))::int wins, (count(*) filter (where r.won and r.clean))::int bonus from res r group by r.user_id),
  t as (
    select lm.user_id, p.display_name, p.username, p.avatar_url, p.avatar_id, coalesce(pr.elo, 1200) as elo, lm.role,
           coalesce(a.played, 0) played, coalesce(a.wins, 0) wins, coalesce(a.played, 0) - coalesce(a.wins, 0) losses,
           case when lg.bonus_enabled then coalesce(a.bonus, 0) else 0 end bonus,
           coalesce(a.wins, 0) * lg.points_win + (coalesce(a.played, 0) - coalesce(a.wins, 0)) * lg.points_loss
             + case when lg.bonus_enabled then coalesce(a.bonus, 0) else 0 end as points
    from lg join public.league_members lm on lm.league_id = lg.id
    join public.profiles p on p.id = lm.user_id
    left join public.player_ratings pr on pr.user_id = lm.user_id
    left join agg a on a.user_id = lm.user_id
  )
  select t.user_id, t.display_name, t.username, t.avatar_url, t.avatar_id, t.elo, t.role, t.played, t.wins, t.losses, t.bonus, t.points,
         case when t.played > 0 then round(100.0 * t.wins / t.played)::int else 0 end,
         (rank() over (order by t.points desc, t.wins desc, t.elo desc))::int
  from t order by 14, t.display_name;
$$;

-- ── Mis ligas (pantalla «Ligas»): una fila por liga con mi posición y el progreso de la temporada.
create or replace function public.my_leagues()
returns table (league_id uuid, name text, visibility text, cover text, location text, season text, starts_on date, ends_on date,
               status text, role text, members int, my_rank int, my_points int, my_played int, my_wins int,
               matches_done int, matches_total int, organizer_name text)
language sql stable security definer set search_path = public as $$
  select l.id, l.name, l.visibility, l.cover, l.location, l.season, l.starts_on, l.ends_on,
         public.league_status(l.ended_at, l.starts_on), me.role,
         (select count(*)::int from public.league_members x where x.league_id = l.id),
         s.rank, s.points, s.played, s.wins,
         (select count(*)::int from public.matches m where m.league_id = l.id and m.status = 'confirmed'),
         ceil((select count(*) from public.league_members x where x.league_id = l.id) * l.matches_per_player / 4.0)::int,
         (select p.display_name from public.profiles p where p.id = l.created_by)
  from public.league_members me
  join public.leagues l on l.id = me.league_id
  left join lateral (select st.rank, st.points, st.played, st.wins from public.league_standings(l.id) st where st.user_id = auth.uid()) s on true
  where me.user_id = auth.uid()
  order by (l.ended_at is not null), l.starts_on desc nulls last, l.created_at desc;
$$;

-- ── Descubrir ligas: públicas y de club abiertas (más las que me han invitado), con amigos dentro.
create or replace function public.discover_leagues(p_query text default '')
returns table (league_id uuid, name text, visibility text, cover text, location text, level_min text, level_max text, season text,
               starts_on date, ends_on date, status text, organizer_name text, members int, max_players int,
               friends_in int, friend_ids uuid[], invited boolean, request_pending boolean)
language sql stable security definer set search_path = public as $$
  select l.id, l.name, l.visibility, l.cover, l.location, l.level_min, l.level_max, l.season, l.starts_on, l.ends_on,
         public.league_status(l.ended_at, l.starts_on),
         (select p.display_name from public.profiles p where p.id = l.created_by),
         (select count(*)::int from public.league_members x where x.league_id = l.id), l.max_players,
         (select count(*)::int from public.league_members x join public.friendships f on f.friend_id = x.user_id and f.user_id = auth.uid() and f.status = 'accepted' where x.league_id = l.id),
         (select coalesce(array_agg(x.user_id), '{}') from (select x.user_id from public.league_members x join public.friendships f on f.friend_id = x.user_id and f.user_id = auth.uid() and f.status = 'accepted' where x.league_id = l.id limit 3) x),
         exists (select 1 from public.league_invites i where i.league_id = l.id and i.user_id = auth.uid()),
         exists (select 1 from public.league_join_requests r where r.league_id = l.id and r.user_id = auth.uid() and r.status = 'pending')
  from public.leagues l
  where l.ended_at is null
    and not exists (select 1 from public.league_members x where x.league_id = l.id and x.user_id = auth.uid())
    and (l.visibility in ('public', 'club') or exists (select 1 from public.league_invites i where i.league_id = l.id and i.user_id = auth.uid()))
    and (coalesce(btrim(p_query), '') = '' or (l.name || ' ' || l.location || ' ' || coalesce((select p.display_name from public.profiles p where p.id = l.created_by), '')) ilike '%' || btrim(p_query) || '%')
  order by 15 desc, l.starts_on nulls last
  limit 50;
$$;

-- ── Feed: jugadores y sets de los partidos que aparecen en MI feed. `matches` solo es legible por sus participantes,
--    así que una tarjeta de partido de un amigo no podría mostrar rivales ni marcador sin esta función.
--    Solo devuelve partidos CONFIRMADOS que tengan una publicación visible para quien llama (can_view_user del autor).
create or replace function public.feed_match_summaries(p_match_ids uuid[])
returns table (match_id uuid, league_name text, venue text, players jsonb, sets jsonb)
language sql stable security definer set search_path = public as $$
  select m.id, l.name, coalesce(m.club, ''),
         (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name, 'username', p.username, 'avatar_url', p.avatar_url, 'team', mp.team, 'elo_delta', mp.elo_delta)), '[]'::jsonb)
            from public.match_players mp join public.profiles p on p.id = mp.user_id where mp.match_id = m.id),
         (select coalesce(jsonb_agg(jsonb_build_array(s.team1_games, s.team2_games) order by s.set_no), '[]'::jsonb) from public.match_sets s where s.match_id = m.id)
  from public.matches m
  left join public.leagues l on l.id = m.league_id
  where m.id = any (coalesce(p_match_ids, '{}'::uuid[])) and m.status = 'confirmed'
    and exists (select 1 from public.feed_posts fp where fp.related_match_id = m.id and public.can_view_user(fp.user_id))
  limit 100;
$$;

-- ── Permisos de ejecución (misma política que 20261119_hardening)
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('set_habitual_partner','get_player_history','league_role','is_league_manager','can_view_league',
              '_can_view_league_match','league_status','_league_notify','create_league','invite_to_league','join_league','join_league_by_code',
              'league_invite_code','respond_join_request','leave_league','remove_league_member','update_league','league_standings','my_leagues','discover_leagues','_validate_sets',
              'feed_match_summaries') loop
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
end $$;
revoke execute on function public._league_notify(uuid, uuid, text, text, text) from authenticated;
revoke execute on function public._validate_sets(jsonb) from authenticated;
grant execute on function public.set_habitual_partner(uuid), public.get_player_history(uuid, int), public.league_role(uuid), public.is_league_manager(uuid),
  public.can_view_league(uuid), public._can_view_league_match(uuid), public.league_status(timestamptz, date),
  public.create_league(text, text, text, text, text, text, text, date, date, int, int, text, int, int, boolean, boolean, uuid[]),
  public.invite_to_league(uuid, uuid[]), public.join_league(uuid, text, text), public.join_league_by_code(text), public.league_invite_code(uuid),
  public.respond_join_request(uuid, boolean), public.leave_league(uuid), public.remove_league_member(uuid, uuid), public.update_league(uuid, jsonb),
  public.league_standings(uuid), public.my_leagues(), public.discover_leagues(text), public.feed_match_summaries(uuid[]) to authenticated;

-- ── Realtime: la clasificación y las solicitudes se refrescan en vivo (RLS se aplica también al canal).
do $$ declare t text; begin
  foreach t in array array['league_members', 'league_join_requests', 'match_sets'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
