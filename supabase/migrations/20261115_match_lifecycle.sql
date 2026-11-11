-- Plobby · Ciclo de vida del partido: programado → en juego → resultado → confirmación de capitanes.
-- NO EJECUTADO NI VALIDADO contra ninguna base de datos. Revisar antes de aplicar.
--
-- Supuestos (los mismos que 20261113_match_type.sql):
--   public.matches(id, match_type, league_id, played_at, club, created_by, confirmed_at, …)
--   public.match_players(match_id, user_id, team smallint, elo_delta int)
--   public.match_sets(match_id, set_no, team1_games, team2_games)
--   public.league_members(league_id, user_id), public.leagues(id), public.notifications(...)
-- Si `matches` YA tiene una columna de estado, REUTILÍZALA (mapea los valores) en vez de añadir `status`.
--
-- ELO / estadísticas / clasificación / rachas / feed: NO se reimplementan aquí. `finalize_match` marca el
-- partido como confirmado UNA sola vez (guarda rating_applied_at) y llama al sistema existente
-- (public.apply_match_rating(uuid) si existe; o bien los triggers existentes sobre `confirmed_at`).
-- ⚠ Asegúrate de que solo UNA de esas dos vías esté activa, para no aplicar el ELO dos veces.

do $$ begin
  create type public.match_status as enum ('scheduled','live','pending_result','pending_confirmation','disputed','confirmed','cancelled');
exception when duplicate_object then null; end $$;

alter table public.matches
  add column if not exists status public.match_status not null default 'scheduled',
  add column if not exists scheduled_at timestamptz,
  add column if not exists court text,
  add column if not exists started_at timestamptz,
  add column if not exists started_by uuid references public.profiles(id),
  add column if not exists ended_at timestamptz,
  add column if not exists ended_by uuid references public.profiles(id),
  add column if not exists duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  add column if not exists result_version integer not null default 0,
  add column if not exists rating_applied_at timestamptz;

create index if not exists matches_status_sched_idx on public.matches (status, scheduled_at);

-- create_match (20261113) guarda la fecha en played_at; el ciclo de vida usa scheduled_at: se mantienen sincronizadas.
update public.matches set scheduled_at = played_at where scheduled_at is null and played_at is not null;
create or replace function public._default_scheduled() returns trigger language plpgsql as $$
begin new.scheduled_at := coalesce(new.scheduled_at, new.played_at); return new; end $$;
drop trigger if exists matches_default_scheduled on public.matches;
create trigger matches_default_scheduled before insert on public.matches for each row execute function public._default_scheduled();

-- Capitán por equipo. Por defecto: el primer jugador del equipo 1 es quien crea el partido; el del equipo 2, el primero que se añade.
alter table public.match_players add column if not exists is_captain boolean not null default false;
create unique index if not exists match_players_one_captain_uq on public.match_players (match_id, team) where is_captain;

-- Versiones de resultado, aceptaciones y auditoría (solo escribe el servidor; ver RLS abajo).
create table if not exists public.match_result_versions (
  id bigserial primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  version integer not null,
  proposed_by uuid not null references public.profiles(id),
  sets jsonb not null,                       -- [[6,4],[3,6],[7,5]]  (equipo1, equipo2)
  winner_team smallint not null check (winner_team in (1,2)),
  created_at timestamptz not null default now(),
  unique (match_id, version)
);
create table if not exists public.match_result_acceptances (
  id bigserial primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  version integer not null,
  user_id uuid not null references public.profiles(id),
  team smallint not null check (team in (1,2)),
  decision text not null check (decision in ('accepted','rejected')),
  reason text,
  created_at timestamptz not null default now(),
  unique (match_id, version, user_id),                                   -- sin dobles confirmaciones
  foreign key (match_id, version) references public.match_result_versions(match_id, version) on delete cascade
);
create table if not exists public.match_events (
  id bigserial primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  actor_id uuid,                              -- null = sistema
  kind text not null,
  payload jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists match_events_match_idx on public.match_events (match_id, created_at desc);

-- ---------------------------------------------------------------------------------------------
-- Helpers
create or replace function public._is_participant(p_match uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.match_players where match_id = p_match and user_id = p_user);
$$;
create or replace function public._log(p_match uuid, p_kind text, p_payload jsonb default '{}') returns void
language sql security definer set search_path = public as $$
  insert into public.match_events(match_id, actor_id, kind, payload) values (p_match, auth.uid(), p_kind, p_payload);
$$;
create or replace function public._notify_players(p_match uuid, p_title text, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
  select mp.user_id, auth.uid(), 'match_event', p_match, p_title, p_body,
         'match:' || p_match || ':' || mp.user_id || ':' || md5(p_title || p_body || clock_timestamp()::text)
    from public.match_players mp where mp.match_id = p_match and mp.user_id is distinct from auth.uid()
  on conflict do nothing;
end $$;
-- Valida marcador al mejor de 3 sets (mismas reglas de set que la app: 6-0..6-4, 7-5, 7-6). Devuelve el equipo ganador.
create or replace function public._validate_sets(p_sets jsonb) returns smallint
language plpgsql immutable as $$
declare n int := jsonb_array_length(p_sets); a int := 0; b int := 0; i int; x int; y int; hi int; lo int;
begin
  if n < 2 or n > 3 then raise exception 'invalid_sets'; end if;
  for i in 0 .. n - 1 loop
    x := (p_sets->i->>0)::int; y := (p_sets->i->>1)::int; hi := greatest(x,y); lo := least(x,y);
    if not ((hi = 6 and lo <= 4) or (hi = 7 and lo in (5,6))) then raise exception 'invalid_set_%', i + 1; end if;
    if x > y then a := a + 1; else b := b + 1; end if;
  end loop;
  if (a = 2 and b = 0) or (a = 0 and b = 2) then if n <> 2 then raise exception 'match_already_decided'; end if;
  elsif a = 1 and b = 1 then if n <> 3 then raise exception 'third_set_required'; end if;
  elsif not (a = 2 and b = 1) and not (a = 1 and b = 2) then raise exception 'invalid_sets'; end if;
  return case when a > b then 1 else 2 end;
end $$;

-- Solo las funciones de este archivo pueden cambiar columnas de ciclo de vida (ver trigger de guarda).
create or replace function public._guard_match_lifecycle() returns trigger
language plpgsql as $$
begin
  if coalesce(current_setting('plobby.rpc', true), '') <> 'on' and (
       new.status is distinct from old.status or new.started_at is distinct from old.started_at or new.ended_at is distinct from old.ended_at
    or new.duration_seconds is distinct from old.duration_seconds or new.result_version is distinct from old.result_version
    or new.rating_applied_at is distinct from old.rating_applied_at or new.confirmed_at is distinct from old.confirmed_at
    or new.started_by is distinct from old.started_by or new.ended_by is distinct from old.ended_by) then
    raise exception 'lifecycle_columns_are_server_managed' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists matches_guard_lifecycle on public.matches;
create trigger matches_guard_lifecycle before update on public.matches for each row execute function public._guard_match_lifecycle();

-- ---------------------------------------------------------------------------------------------
-- Hora oficial del servidor (el cliente calcula su desfase y muestra now() - started_at).
create or replace function public.server_time() returns timestamptz language sql stable as $$ select now(); $$;

-- EMPEZAR PARTIDO — atómico: dos pulsaciones simultáneas ⇒ una sola hora de inicio (gana el primer UPDATE).
create or replace function public.start_match(p_match_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.matches;
begin
  if not public._is_participant(p_match_id, auth.uid()) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  perform set_config('plobby.rpc', 'on', true);
  update public.matches set status = 'live', started_at = now(), started_by = auth.uid()
   where id = p_match_id and status = 'scheduled'
   returning * into v;
  if found then
    perform public._log(p_match_id, 'start', jsonb_build_object('started_at', v.started_at));
    perform public._notify_players(p_match_id, 'Partido en juego', 'El partido ha empezado');
    return jsonb_build_object('started', true, 'started_at', v.started_at, 'started_by', v.started_by);
  end if;
  select * into v from public.matches where id = p_match_id;                  -- ya estaba iniciado: se devuelve la hora oficial existente
  return jsonb_build_object('started', false, 'status', v.status, 'started_at', v.started_at, 'started_by', v.started_by);
end $$;

-- FINALIZAR PARTIDO — hora de fin del servidor, duración total permanente, pasa a «pendiente de resultado».
create or replace function public.finish_match(p_match_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.matches;
begin
  if not public._is_participant(p_match_id, auth.uid()) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  perform set_config('plobby.rpc', 'on', true);
  update public.matches set status = 'pending_result', ended_at = now(), ended_by = auth.uid(),
         duration_seconds = greatest(0, extract(epoch from (now() - started_at))::int)
   where id = p_match_id and status = 'live' returning * into v;
  if not found then raise exception 'match_not_live'; end if;
  perform public._log(p_match_id, 'finish', jsonb_build_object('ended_at', v.ended_at, 'duration_seconds', v.duration_seconds));
  perform public._notify_players(p_match_id, 'Partido finalizado', 'Introducid el resultado para confirmarlo');
  return jsonb_build_object('ended_at', v.ended_at, 'duration_seconds', v.duration_seconds);
end $$;

-- Introducir o corregir el resultado: crea una versión NUEVA; las aceptaciones de versiones anteriores dejan de valer.
create or replace function public.submit_result(p_match_id uuid, p_sets jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare m public.matches; w smallint; nv integer;
begin
  if not public._is_participant(p_match_id, auth.uid()) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  select * into m from public.matches where id = p_match_id for update;
  if m.status not in ('pending_result','pending_confirmation','disputed') then raise exception 'invalid_state_%', m.status; end if;
  w := public._validate_sets(p_sets);
  nv := m.result_version + 1;
  perform set_config('plobby.rpc', 'on', true);
  insert into public.match_result_versions(match_id, version, proposed_by, sets, winner_team) values (p_match_id, nv, auth.uid(), p_sets, w);
  update public.matches set result_version = nv, status = 'pending_confirmation' where id = p_match_id;
  perform public._log(p_match_id, case when m.result_version = 0 then 'result_submitted' else 'result_edited' end,
                      jsonb_build_object('version', nv, 'sets', p_sets, 'invalidated_previous', m.result_version > 0));
  perform public._notify_players(p_match_id, 'Resultado pendiente de confirmar', 'Los capitanes deben aceptar el resultado');
  return nv;
end $$;

-- Aceptar / rechazar una versión concreta. Solo capitanes. La versión se compara EN SERVIDOR (aceptación obsoleta ⇒ error).
create or replace function public.respond_result(p_match_id uuid, p_version integer, p_accept boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.matches; mp public.match_players; c1 boolean; c2 boolean;
begin
  select * into m from public.matches where id = p_match_id for update;           -- serializa respuestas concurrentes
  select * into mp from public.match_players where match_id = p_match_id and user_id = auth.uid();
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if not mp.is_captain then raise exception 'only_captains_can_confirm' using errcode = '42501'; end if;
  if m.status <> 'pending_confirmation' then raise exception 'invalid_state_%', m.status; end if;
  if p_version is distinct from m.result_version then raise exception 'stale_version'; end if;
  perform set_config('plobby.rpc', 'on', true);
  if not p_accept then
    insert into public.match_result_acceptances(match_id, version, user_id, team, decision, reason)
    values (p_match_id, p_version, auth.uid(), mp.team, 'rejected', nullif(trim(p_reason), ''))
    on conflict (match_id, version, user_id) do nothing;
    update public.matches set status = 'disputed' where id = p_match_id;
    perform public._log(p_match_id, 'result_rejected', jsonb_build_object('version', p_version, 'reason', p_reason));
    perform public._notify_players(p_match_id, 'Resultado en disputa', coalesce('Motivo: ' || nullif(trim(p_reason), ''), 'Un capitán no está de acuerdo con el resultado'));
    return jsonb_build_object('status', 'disputed');
  end if;
  insert into public.match_result_acceptances(match_id, version, user_id, team, decision)
  values (p_match_id, p_version, auth.uid(), mp.team, 'accepted')
  on conflict (match_id, version, user_id) do nothing;                              -- reintento idempotente
  perform public._log(p_match_id, 'result_accepted', jsonb_build_object('version', p_version));
  select bool_or(a.team = 1), bool_or(a.team = 2) into c1, c2
    from public.match_result_acceptances a join public.match_players x on x.match_id = a.match_id and x.user_id = a.user_id and x.is_captain
   where a.match_id = p_match_id and a.version = m.result_version and a.decision = 'accepted';
  if coalesce(c1, false) and coalesce(c2, false) then
    perform public._finalize_match(p_match_id);
    return jsonb_build_object('status', 'confirmed');
  end if;
  return jsonb_build_object('status', 'pending_confirmation');
end $$;

-- Cierre del partido: ATÓMICO e IDEMPOTENTE (rating_applied_at + FOR UPDATE). No se llama desde el cliente.
create or replace function public._finalize_match(p_match_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m public.matches; r public.match_result_versions;
begin
  select * into m from public.matches where id = p_match_id for update;
  if m.rating_applied_at is not null or m.status = 'confirmed' then return; end if;      -- ya aplicado: no se repite el ELO
  select * into r from public.match_result_versions where match_id = p_match_id and version = m.result_version;
  perform set_config('plobby.rpc', 'on', true);
  delete from public.match_sets where match_id = p_match_id;
  insert into public.match_sets(match_id, set_no, team1_games, team2_games)
    select p_match_id, s.ord::int, (s.val->>0)::int, (s.val->>1)::int from jsonb_array_elements(r.sets) with ordinality as s(val, ord);
  update public.matches set status = 'confirmed', confirmed_at = now(), rating_applied_at = now(), played_at = coalesce(started_at, scheduled_at) where id = p_match_id;
  -- Sistema ELO / estadísticas / clasificación / rachas EXISTENTE (solo ahora que el resultado está confirmado).
  if to_regprocedure('public.apply_match_rating(uuid)') is not null then
    execute 'select public.apply_match_rating($1)' using p_match_id;
  end if;
  perform public._log(p_match_id, 'confirmed', jsonb_build_object('version', m.result_version));
  perform public._notify_players(p_match_id, 'Partido confirmado', 'Resultado confirmado por los dos capitanes');
end $$;

-- Editar (solo quien creó el partido, solo si sigue programado). Reglas de liga comprobadas aquí.
-- p_players: [{"user_id":…, "team":1|2, "captain":true|false}, …] (exactamente 4, un capitán por equipo)
create or replace function public.update_match(p_match_id uuid, p_scheduled_at timestamptz, p_club text, p_court text, p_players jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare m public.matches; e jsonb; n int; changed boolean;
begin
  select * into m from public.matches where id = p_match_id for update;
  if m.created_by is distinct from auth.uid() then raise exception 'only_creator_can_edit' using errcode = '42501'; end if;
  if m.status <> 'scheduled' then raise exception 'match_not_editable'; end if;
  if p_scheduled_at <= now() then raise exception 'date_must_be_future'; end if;
  if jsonb_array_length(p_players) <> 4 then raise exception 'need_four_players'; end if;
  if (select count(distinct x->>'user_id') from jsonb_array_elements(p_players) x) <> 4 then raise exception 'players_must_be_distinct'; end if;
  if (select count(*) from jsonb_array_elements(p_players) x where (x->>'captain')::boolean and (x->>'team')::int = 1) <> 1
     or (select count(*) from jsonb_array_elements(p_players) x where (x->>'captain')::boolean and (x->>'team')::int = 2) <> 1 then raise exception 'one_captain_per_team'; end if;
  if not exists (select 1 from jsonb_array_elements(p_players) x where (x->>'user_id')::uuid = auth.uid()) then raise exception 'creator_must_play'; end if;
  if m.match_type = 'league' then
    -- regla de liga: solo miembros de la liga …
    if exists (select 1 from jsonb_array_elements(p_players) x where not exists (select 1 from public.league_members lm where lm.league_id = m.league_id and lm.user_id = (x->>'user_id')::uuid)) then raise exception 'players_must_be_league_members'; end if;
    -- … y no se cambian jugadores a menos de 2 h del inicio (ajusta/lee esta regla de la configuración de la liga si existe).
    select exists (select 1 from jsonb_array_elements(p_players) x where not exists (select 1 from public.match_players mp where mp.match_id = p_match_id and mp.user_id = (x->>'user_id')::uuid)) into changed;
    if changed and m.scheduled_at - now() < interval '2 hours' then raise exception 'league_rule_players_locked'; end if;
  end if;
  perform set_config('plobby.rpc', 'on', true);
  update public.matches set scheduled_at = p_scheduled_at, club = p_club, court = nullif(trim(p_court), '') where id = p_match_id;
  delete from public.match_players where match_id = p_match_id;
  for e in select * from jsonb_array_elements(p_players) loop
    insert into public.match_players(match_id, user_id, team, is_captain) values (p_match_id, (e->>'user_id')::uuid, (e->>'team')::smallint, (e->>'captain')::boolean);
  end loop;
  perform public._log(p_match_id, 'edited', jsonb_build_object('scheduled_at', p_scheduled_at, 'club', p_club, 'court', p_court));
  perform public._notify_players(p_match_id, 'Partido modificado', 'Han cambiado los datos del partido');
end $$;

-- Eliminar = cancelar (se conserva el rastro de auditoría). Mismas reglas de permiso y de liga.
create or replace function public.cancel_match(p_match_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m public.matches;
begin
  select * into m from public.matches where id = p_match_id for update;
  if m.created_by is distinct from auth.uid() then raise exception 'only_creator_can_delete' using errcode = '42501'; end if;
  if m.status <> 'scheduled' then raise exception 'match_not_deletable'; end if;
  if m.match_type = 'league' and m.scheduled_at - now() < interval '2 hours' then raise exception 'league_rule_delete_locked'; end if;
  perform set_config('plobby.rpc', 'on', true);
  update public.matches set status = 'cancelled' where id = p_match_id;
  perform public._log(p_match_id, 'cancelled');
  perform public._notify_players(p_match_id, 'Partido cancelado', 'El organizador ha cancelado el partido');
end $$;

-- ---------------------------------------------------------------------------------------------
-- RLS: solo participantes leen; NINGÚN cliente escribe en estas tablas (solo las funciones de arriba).
alter table public.match_result_versions enable row level security;
alter table public.match_result_acceptances enable row level security;
alter table public.match_events enable row level security;
drop policy if exists mrv_read on public.match_result_versions;
create policy mrv_read on public.match_result_versions for select to authenticated using (public._is_participant(match_id, auth.uid()));
drop policy if exists mra_read on public.match_result_acceptances;
create policy mra_read on public.match_result_acceptances for select to authenticated using (public._is_participant(match_id, auth.uid()));
drop policy if exists mev_read on public.match_events;
create policy mev_read on public.match_events for select to authenticated using (public._is_participant(match_id, auth.uid()));
revoke insert, update, delete on public.match_result_versions, public.match_result_acceptances, public.match_events from authenticated, anon;

revoke all on function public.start_match(uuid), public.finish_match(uuid), public.submit_result(uuid, jsonb), public.respond_result(uuid, integer, boolean, text),
  public.update_match(uuid, timestamptz, text, text, jsonb), public.cancel_match(uuid), public.server_time() from public;
grant execute on function public.start_match(uuid), public.finish_match(uuid), public.submit_result(uuid, jsonb), public.respond_result(uuid, integer, boolean, text),
  public.update_match(uuid, timestamptz, text, text, jsonb), public.cancel_match(uuid), public.server_time() to authenticated;
revoke all on function public._finalize_match(uuid), public._log(uuid, text, jsonb), public._notify_players(uuid, text, text) from public, authenticated, anon;

-- Realtime: el reloj, los estados y las aceptaciones llegan a los cuatro jugadores sin recargar.
do $$ begin
  begin alter publication supabase_realtime add table public.matches; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.match_result_versions; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.match_result_acceptances; exception when duplicate_object then null; end;
exception when undefined_object then null; end $$;
