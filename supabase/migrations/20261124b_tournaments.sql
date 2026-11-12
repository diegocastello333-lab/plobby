-- Plobby · Torneos (diseño: docs/torneos.md). Sistema INDEPENDIENTE de Ligas: no toca ninguna tabla ni función de ligas.

-- ════════════════════════════ Tablas ════════════════════════════
create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 3 and 60),
  description text check (description is null or length(description) <= 500),
  starts_on date not null,
  ends_on date,
  time_slot text check (time_slot is null or length(time_slot) <= 60),
  location text check (location is null or length(location) <= 120),
  cover_url text check (cover_url is null or length(cover_url) <= 500),
  max_teams int not null check (max_teams between 2 and 64),
  format text not null check (format in ('knockout', 'groups_knockout', 'round_robin')),
  groups_count int not null default 1 check (groups_count between 1 and 8),
  qualifiers_per_group int not null default 0 check (qualifiers_per_group between 0 and 4),
  points_win int not null default 3 check (points_win between 1 and 5),
  points_loss int not null default 0 check (points_loss between 0 and 2),
  status text not null default 'scheduled' check (status in ('scheduled', 'in_progress', 'finished')),
  champion_team_id uuid,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint tournaments_dates_chk check (ends_on is null or ends_on >= starts_on)
);

create table if not exists public.tournament_admins (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'admin' check (role in ('owner', 'admin')),
  created_at timestamptz not null default now(),
  primary key (tournament_id, user_id)
);

create table if not exists public.tournament_teams (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  seed int not null check (seed >= 1),
  player1_id uuid not null references public.profiles(id),
  player2_id uuid not null references public.profiles(id),
  group_label text check (group_label is null or group_label ~ '^[A-H]$'),
  created_at timestamptz not null default now(),
  unique (tournament_id, seed),
  check (player1_id <> player2_id)
);

alter table public.tournaments drop constraint if exists tournaments_champion_fk;
alter table public.tournaments add constraint tournaments_champion_fk foreign key (champion_team_id) references public.tournament_teams(id) on delete set null;

-- Un jugador solo puede estar en UNA pareja de cada torneo (la PK lo garantiza).
create table if not exists public.tournament_players (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  team_id uuid not null references public.tournament_teams(id) on delete cascade,
  primary key (tournament_id, user_id)
);
create index if not exists tournament_players_user_idx on public.tournament_players (user_id);

create table if not exists public.tournament_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  stage text not null check (stage in ('group', 'knockout')),
  group_label text check (group_label is null or group_label ~ '^[A-H]$'),
  round int not null check (round >= 1),
  position int not null check (position >= 0),
  team1_id uuid references public.tournament_teams(id) on delete set null,
  team2_id uuid references public.tournament_teams(id) on delete set null,
  slot1_source text,   -- p. ej. 'A1' (1.º del grupo A) en los cruces que salen de grupos
  slot2_source text,
  next_match_id uuid references public.tournament_matches(id) on delete set null,
  next_slot smallint check (next_slot in (1, 2)),
  status text not null default 'pending' check (status in ('pending', 'live', 'finished', 'bye')),
  sets jsonb,
  winner_team_id uuid references public.tournament_teams(id) on delete set null,
  version int not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  check (team1_id is null or team2_id is null or team1_id <> team2_id),
  check (stage = 'knockout' or group_label is not null)
);
create unique index if not exists tournament_matches_slot_uq on public.tournament_matches (tournament_id, stage, coalesce(group_label, '-'), round, position);
create index if not exists tournament_matches_t_idx on public.tournament_matches (tournament_id);
create index if not exists tournament_teams_t_idx on public.tournament_teams (tournament_id);

-- ════════════════════════════ Permisos (RLS) ════════════════════════════
create or replace function public._t_is_admin(p_t uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.tournament_admins where tournament_id = p_t and user_id = auth.uid());
$$;
create or replace function public._t_can_view(p_t uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public._t_is_admin(p_t) or exists (select 1 from public.tournament_players where tournament_id = p_t and user_id = auth.uid());
$$;

alter table public.tournaments enable row level security;
alter table public.tournament_admins enable row level security;
alter table public.tournament_teams enable row level security;
alter table public.tournament_players enable row level security;
alter table public.tournament_matches enable row level security;
drop policy if exists t_select on public.tournaments;
create policy t_select on public.tournaments for select to authenticated using (public._t_can_view(id));
drop policy if exists ta_select on public.tournament_admins;
create policy ta_select on public.tournament_admins for select to authenticated using (public._t_can_view(tournament_id));
drop policy if exists tt_select on public.tournament_teams;
create policy tt_select on public.tournament_teams for select to authenticated using (public._t_can_view(tournament_id));
drop policy if exists tp_select on public.tournament_players;
create policy tp_select on public.tournament_players for select to authenticated using (public._t_can_view(tournament_id));
drop policy if exists tm_select on public.tournament_matches;
create policy tm_select on public.tournament_matches for select to authenticated using (public._t_can_view(tournament_id));
-- Sin políticas de escritura: solo las funciones de abajo (security definer) modifican torneos.
revoke insert, update, delete on public.tournaments, public.tournament_admins, public.tournament_teams, public.tournament_players, public.tournament_matches from anon, authenticated;
grant select on public.tournaments, public.tournament_admins, public.tournament_teams, public.tournament_players, public.tournament_matches to authenticated;

-- ════════════════════════════ Lógica de competición ════════════════════════════

-- Sets al mejor de 3 (6-0…6-4, 7-5, 7-6; se acaba al ganar 2). Devuelve 1 o 2 (pareja ganadora). Propia de torneos.
create or replace function public._t_validate_sets(p_sets jsonb) returns smallint
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

-- Orden de siembra estándar de un cuadro de p huecos: [1, p, p/2+1, …] (1 vs p, 2 vs p-1…).
create or replace function public._t_seed_order(p int) returns int[]
language plpgsql immutable as $$
declare o int[] := array[1]; r int[]; s int; n int;
begin
  while cardinality(o) < p loop
    n := cardinality(o) * 2; r := '{}';
    foreach s in array o loop r := r || s || (n + 1 - s); end loop;
    o := r;
  end loop;
  return o;
end $$;

-- Clasificación de los grupos (solo partidos de grupo terminados). Sin comprobación de permisos: uso interno.
create or replace function public._t_standings(p_t uuid)
returns table (group_label text, team_id uuid, seed int, played int, won int, lost int, sets_for int, sets_against int,
               games_for int, games_against int, points int, pos int)
language sql stable security definer set search_path = public as $$
  with t as (select points_win, points_loss from public.tournaments where id = p_t),
  rows as (
    select m.group_label, side.team_id, side.won,
           (select count(*) from jsonb_array_elements(m.sets) s where (case when side.n = 1 then (s->>0)::int > (s->>1)::int else (s->>1)::int > (s->>0)::int end))::int sf,
           (select count(*) from jsonb_array_elements(m.sets) s where (case when side.n = 1 then (s->>0)::int < (s->>1)::int else (s->>1)::int < (s->>0)::int end))::int sa,
           (select coalesce(sum(case when side.n = 1 then (s->>0)::int else (s->>1)::int end), 0) from jsonb_array_elements(m.sets) s)::int gf,
           (select coalesce(sum(case when side.n = 1 then (s->>1)::int else (s->>0)::int end), 0) from jsonb_array_elements(m.sets) s)::int ga
      from public.tournament_matches m
      cross join lateral (values (1, m.team1_id, m.winner_team_id = m.team1_id), (2, m.team2_id, m.winner_team_id = m.team2_id)) side(n, team_id, won)
     where m.tournament_id = p_t and m.stage = 'group' and m.status = 'finished'
  ),
  agg as (
    select tt.group_label, tt.id team_id, tt.seed,
           count(r.team_id)::int played, count(*) filter (where r.won)::int won, count(*) filter (where r.won = false)::int lost,
           coalesce(sum(r.sf), 0)::int sets_for, coalesce(sum(r.sa), 0)::int sets_against,
           coalesce(sum(r.gf), 0)::int games_for, coalesce(sum(r.ga), 0)::int games_against
      from public.tournament_teams tt left join rows r on r.team_id = tt.id
     where tt.tournament_id = p_t and tt.group_label is not null
     group by tt.group_label, tt.id, tt.seed
  )
  select a.group_label, a.team_id, a.seed, a.played, a.won, a.lost, a.sets_for, a.sets_against, a.games_for, a.games_against,
         (a.won * t.points_win + a.lost * t.points_loss)::int points,
         row_number() over (partition by a.group_label order by (a.won * t.points_win + a.lost * t.points_loss) desc,
                            (a.sets_for - a.sets_against) desc, (a.games_for - a.games_against) desc, a.won desc, a.seed)::int pos
    from agg a cross join t;
$$;

-- Vacía un partido (resultado y, si se indica, parejas) y anula en cascada los siguientes que dependían de su ganador.
create or replace function public._t_reset_match(p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m public.tournament_matches;
begin
  select * into m from public.tournament_matches where id = p_match;
  if m.status in ('finished', 'live') or m.winner_team_id is not null then
    update public.tournament_matches set sets = null, winner_team_id = null, status = 'pending', version = version + 1, updated_at = now() where id = p_match;
    if m.next_match_id is not null then perform public._t_set_slot(m.next_match_id, m.next_slot, null); end if;
  end if;
end $$;

-- Coloca una pareja (o nada) en un hueco. Si el partido cambia de pareja y ya tenía resultado, se anula en cascada.
create or replace function public._t_set_slot(p_match uuid, p_slot smallint, p_team uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m public.tournament_matches; cur uuid;
begin
  select * into m from public.tournament_matches where id = p_match;
  cur := case when p_slot = 1 then m.team1_id else m.team2_id end;
  if cur is not distinct from p_team then return; end if;
  if m.status in ('finished', 'live') then perform public._t_reset_match(p_match); end if;
  if p_slot = 1 then update public.tournament_matches set team1_id = p_team, version = version + 1, updated_at = now() where id = p_match;
  else update public.tournament_matches set team2_id = p_team, version = version + 1, updated_at = now() where id = p_match; end if;
end $$;

-- Un BYE (un solo hueco ocupado) se resuelve solo: esa pareja avanza.
create or replace function public._t_resolve_bye(p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m public.tournament_matches; w uuid;
begin
  select * into m from public.tournament_matches where id = p_match;
  if m.status <> 'bye' then return; end if;
  w := coalesce(m.team1_id, m.team2_id);
  if m.winner_team_id is not distinct from w then return; end if;
  update public.tournament_matches set winner_team_id = w, version = version + 1, updated_at = now() where id = p_match;
  if m.next_match_id is not null then perform public._t_set_slot(m.next_match_id, m.next_slot, w); end if;
end $$;

-- Crea las rondas de eliminatoria para k participantes. p_entrants: ids de pareja (p_sources = false) o etiquetas
-- de grupo como 'A1' (p_sources = true), en orden de siembra.
create or replace function public._t_build_knockout(p_t uuid, p_entrants text[], p_sources boolean) returns void
language plpgsql security definer set search_path = public as $$
declare k int := cardinality(p_entrants); p int := 2; rounds int := 1; r int; pos int; nid uuid; ord int[]; a int; b int; mid uuid;
begin
  if k < 2 then raise exception 'not_enough_teams'; end if;
  while p < k loop p := p * 2; rounds := rounds + 1; end loop;
  -- De la final hacia atrás, para conocer el partido siguiente de cada uno.
  for r in reverse rounds .. 1 loop
    for pos in 0 .. (p / (2 ^ r))::int - 1 loop
      select id into nid from public.tournament_matches
       where tournament_id = p_t and stage = 'knockout' and round = r + 1 and position = pos / 2;
      insert into public.tournament_matches (tournament_id, stage, round, position, next_match_id, next_slot)
      values (p_t, 'knockout', r, pos, nid, case when nid is null then null else (pos % 2) + 1 end);
    end loop;
  end loop;
  ord := public._t_seed_order(p);
  for pos in 0 .. p / 2 - 1 loop
    a := ord[2 * pos + 1]; b := ord[2 * pos + 2];
    select id into mid from public.tournament_matches where tournament_id = p_t and stage = 'knockout' and round = 1 and position = pos;
    if p_sources then
      update public.tournament_matches set slot1_source = p_entrants[a], slot2_source = case when b <= k then p_entrants[b] end,
             status = case when b > k then 'bye' else 'pending' end where id = mid;
    else
      update public.tournament_matches set team1_id = p_entrants[a]::uuid, team2_id = case when b <= k then p_entrants[b]::uuid end,
             status = case when b > k then 'bye' else 'pending' end where id = mid;
      perform public._t_resolve_bye(mid);
    end if;
  end loop;
end $$;

-- Todos contra todos dentro de un grupo (método del círculo: cada jornada, cada pareja juega como mucho una vez).
create or replace function public._t_build_round_robin(p_t uuid, p_group text) returns void
language plpgsql security definer set search_path = public as $$
declare ids uuid[]; n int; r int; i int; a uuid; b uuid; pos int; rot uuid[];
begin
  select array_agg(id order by seed) into ids from public.tournament_teams where tournament_id = p_t and group_label = p_group;
  n := coalesce(cardinality(ids), 0);
  if n < 2 then raise exception 'group_too_small'; end if;
  if n % 2 = 1 then ids := ids || null::uuid; n := n + 1; end if;
  for r in 1 .. n - 1 loop
    pos := 0;
    for i in 1 .. n / 2 loop
      a := ids[i]; b := ids[n + 1 - i];
      if a is not null and b is not null then
        insert into public.tournament_matches (tournament_id, stage, group_label, round, position, team1_id, team2_id)
        values (p_t, 'group', p_group, r, pos, a, b);
        pos := pos + 1;
      end if;
    end loop;
    rot := array[ids[1]] || ids[n] || ids[2 : n - 1];   -- rota todos menos el primero
    ids := rot;
  end loop;
end $$;

-- Genera toda la estructura del torneo a partir de sus parejas (ya insertadas con semilla).
create or replace function public._t_generate(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t public.tournaments; n int; g int; i int; labels text[] := array['A','B','C','D','E','F','G','H'];
        ent text[] := '{}'; q int; gi int;
begin
  select * into t from public.tournaments where id = p_t;
  select count(*) into n from public.tournament_teams where tournament_id = p_t;
  delete from public.tournament_matches where tournament_id = p_t;
  update public.tournament_teams set group_label = null where tournament_id = p_t;
  if t.format = 'knockout' then
    if n < 2 then raise exception 'not_enough_teams'; end if;
    select array_agg(id::text order by seed) into ent from public.tournament_teams where tournament_id = p_t;
    perform public._t_build_knockout(p_t, ent, false);
  elsif t.format = 'round_robin' then
    if n < 3 then raise exception 'not_enough_teams'; end if;
    update public.tournament_teams set group_label = 'A' where tournament_id = p_t;
    perform public._t_build_round_robin(p_t, 'A');
  else
    g := t.groups_count; q := t.qualifiers_per_group;
    if g < 1 or n < 2 * g then raise exception 'not_enough_teams'; end if;
    if q < 1 or q > n / g or g * q < 2 then raise exception 'invalid_qualifiers'; end if;
    -- Reparto en serpiente por semilla: A B C D D C B A …
    update public.tournament_teams tt set group_label = labels[
      (case when ((x.rn - 1) / g) % 2 = 0 then ((x.rn - 1) % g) + 1 else g - ((x.rn - 1) % g) end)::int]
      from (select id, (row_number() over (order by seed))::int rn from public.tournament_teams where tournament_id = p_t) x
     where tt.id = x.id;
    for gi in 1 .. g loop perform public._t_build_round_robin(p_t, labels[gi]); end loop;
    -- Cruces: 1.º de cada grupo, luego 2.º… (siembra A1, B1, …, A2, B2, …)
    for i in 1 .. q loop for gi in 1 .. g loop ent := ent || (labels[gi] || i); end loop; end loop;
    perform public._t_build_knockout(p_t, ent, true);
  end if;
end $$;

-- Cuando todos los partidos de grupo han terminado, coloca a los clasificados en los cruces (y re-siembra si una
-- corrección cambia la clasificación: solo se anulan los cruces que cambian de pareja).
create or replace function public._t_seed_from_groups(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m record; t1 uuid; t2 uuid; done boolean;
begin
  select not exists (select 1 from public.tournament_matches where tournament_id = p_t and stage = 'group' and status <> 'finished') into done;
  for m in select * from public.tournament_matches where tournament_id = p_t and stage = 'knockout' and round = 1 and slot1_source is not null order by position loop
    if done then
      select s.team_id into t1 from public._t_standings(p_t) s where s.group_label || s.pos = m.slot1_source;
      select s.team_id into t2 from public._t_standings(p_t) s where m.slot2_source is not null and s.group_label || s.pos = m.slot2_source;
    else
      t1 := null; t2 := null;
    end if;
    if m.slot2_source is null then t2 := null; end if;
    perform public._t_set_slot(m.id, 1::smallint, t1);
    perform public._t_set_slot(m.id, 2::smallint, t2);
    if m.status = 'bye' then
      if t1 is not null then perform public._t_resolve_bye(m.id);
      elsif m.winner_team_id is not null then
        update public.tournament_matches set winner_team_id = null, version = version + 1 where id = m.id;
        if m.next_match_id is not null then perform public._t_set_slot(m.next_match_id, m.next_slot, null); end if;
      end if;
    end if;
  end loop;
end $$;

-- Estado y campeón coherentes con los resultados actuales.
create or replace function public._t_refresh(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t public.tournaments; champ uuid; any_done boolean;
begin
  select * into t from public.tournaments where id = p_t;
  if t.format = 'round_robin' then
    if not exists (select 1 from public.tournament_matches where tournament_id = p_t and status <> 'finished') then
      select team_id into champ from public._t_standings(p_t) where pos = 1 limit 1;
    end if;
  else
    select winner_team_id into champ from public.tournament_matches
     where tournament_id = p_t and stage = 'knockout' and next_match_id is null and status in ('finished', 'bye');
  end if;
  select exists (select 1 from public.tournament_matches where tournament_id = p_t and status in ('finished', 'live')) into any_done;
  update public.tournaments set champion_team_id = champ,
         status = case when champ is not null then 'finished' when any_done then 'in_progress' else 'scheduled' end,
         finished_at = case when champ is not null then coalesce(finished_at, now()) end,
         updated_at = now()
   where id = p_t;
end $$;

-- Inserta parejas y jugadores validando duplicados y que cada jugador exista.
create or replace function public._t_insert_teams(p_t uuid, p_teams jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare i int; a uuid; b uuid; tid uuid; n int := coalesce(jsonb_array_length(p_teams), 0);
begin
  if p_teams is null or jsonb_typeof(p_teams) <> 'array' then raise exception 'invalid_teams'; end if;
  for i in 0 .. n - 1 loop
    a := (p_teams->i->>0)::uuid; b := (p_teams->i->>1)::uuid;
    if a is null or b is null then raise exception 'invalid_team'; end if;
    if a = b then raise exception 'duplicate_player'; end if;
    if not exists (select 1 from public.profiles where id = a) or not exists (select 1 from public.profiles where id = b) then raise exception 'unknown_player'; end if;
    if exists (select 1 from public.tournament_players where tournament_id = p_t and user_id in (a, b)) then raise exception 'duplicate_player'; end if;
    insert into public.tournament_teams (tournament_id, seed, player1_id, player2_id) values (p_t, i + 1, a, b) returning id into tid;
    insert into public.tournament_players (tournament_id, user_id, team_id) values (p_t, a, tid), (p_t, b, tid);
  end loop;
  return n;
end $$;

-- Aviso «te han inscrito» a cada jugador (salvo a quien organiza). Nunca impide crear el torneo.
create or replace function public._t_notify_players(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid; nm text;
begin
  select name into nm from public.tournaments where id = p_t;
  for u in select user_id from public.tournament_players where tournament_id = p_t and user_id <> auth.uid() loop
    begin
      insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
      values (u, auth.uid(), 'tournament_added', p_t, 'Te han inscrito en un torneo', nm, 'ta:' || p_t || ':' || u) on conflict do nothing;
    exception when others then null;
    end;
  end loop;
end $$;

-- ════════════════════════════ RPC públicas ════════════════════════════
create or replace function public.create_tournament(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); tid uuid; n int;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  insert into public.tournaments (name, description, starts_on, ends_on, time_slot, location, cover_url, max_teams, format,
                                  groups_count, qualifiers_per_group, points_win, points_loss, created_by)
  values (btrim(p->>'name'), nullif(btrim(p->>'description'), ''), (p->>'starts_on')::date, nullif(p->>'ends_on', '')::date,
          nullif(btrim(p->>'time_slot'), ''), nullif(btrim(p->>'location'), ''), nullif(p->>'cover_url', ''),
          coalesce((p->>'max_teams')::int, 16), p->>'format',
          coalesce((p->>'groups_count')::int, 1), coalesce((p->>'qualifiers_per_group')::int, 0),
          coalesce((p->>'points_win')::int, 3), coalesce((p->>'points_loss')::int, 0), me)
  returning id into tid;
  insert into public.tournament_admins (tournament_id, user_id, role) values (tid, me, 'owner');
  n := public._t_insert_teams(tid, p->'teams');
  if n > (select max_teams from public.tournaments where id = tid) then raise exception 'too_many_teams'; end if;
  perform public._t_generate(tid);
  perform public._t_notify_players(tid);
  return tid;
end $$;

-- Cambiar parejas o formato solo antes de que haya resultados (después rompería clasificaciones y cuadro).
create or replace function public.replace_tournament_teams(p_t uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._t_is_admin(p_t) then raise exception 'not_tournament_admin'; end if;
  perform 1 from public.tournaments where id = p_t for update;
  if exists (select 1 from public.tournament_matches where tournament_id = p_t and status in ('finished', 'live')) then raise exception 'tournament_started'; end if;
  update public.tournaments set format = coalesce(p->>'format', format), groups_count = coalesce((p->>'groups_count')::int, groups_count),
         qualifiers_per_group = coalesce((p->>'qualifiers_per_group')::int, qualifiers_per_group), updated_at = now() where id = p_t;
  delete from public.tournament_matches where tournament_id = p_t;
  delete from public.tournament_players where tournament_id = p_t;
  delete from public.tournament_teams where tournament_id = p_t;
  n := public._t_insert_teams(p_t, p->'teams');
  if n > (select max_teams from public.tournaments where id = p_t) then raise exception 'too_many_teams'; end if;
  perform public._t_generate(p_t);
  perform public._t_refresh(p_t);
  perform public._t_notify_players(p_t);
end $$;

create or replace function public.update_tournament_info(p_t uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._t_is_admin(p_t) then raise exception 'not_tournament_admin'; end if;
  update public.tournaments set
    name = coalesce(btrim(p->>'name'), name),
    description = case when p ? 'description' then nullif(btrim(p->>'description'), '') else description end,
    starts_on = coalesce((p->>'starts_on')::date, starts_on),
    ends_on = case when p ? 'ends_on' then nullif(p->>'ends_on', '')::date else ends_on end,
    time_slot = case when p ? 'time_slot' then nullif(btrim(p->>'time_slot'), '') else time_slot end,
    location = case when p ? 'location' then nullif(btrim(p->>'location'), '') else location end,
    cover_url = case when p ? 'cover_url' then nullif(p->>'cover_url', '') else cover_url end,
    max_teams = coalesce((p->>'max_teams')::int, max_teams),
    updated_at = now()
  where id = p_t;
  if (select max_teams from public.tournaments where id = p_t) < (select count(*) from public.tournament_teams where tournament_id = p_t) then
    raise exception 'too_many_teams';
  end if;
end $$;

-- Registrar o corregir un resultado. Bloquea el torneo y exige la versión del partido que vio el cliente: dos
-- organizadores no pueden pisarse (el segundo recibe result_conflict y ve el resultado actual).
create or replace function public.record_tournament_result(p_match uuid, p_sets jsonb, p_version int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.tournament_matches; w smallint; winner uuid;
begin
  select * into m from public.tournament_matches where id = p_match;
  if m.id is null then raise exception 'match_not_found'; end if;
  if not public._t_is_admin(m.tournament_id) then raise exception 'not_tournament_admin'; end if;
  perform 1 from public.tournaments where id = m.tournament_id for update;
  select * into m from public.tournament_matches where id = p_match for update;
  if m.version <> p_version then raise exception 'result_conflict'; end if;
  if m.status = 'bye' or m.team1_id is null or m.team2_id is null then raise exception 'match_not_ready'; end if;
  w := public._t_validate_sets(p_sets);
  winner := case when w = 1 then m.team1_id else m.team2_id end;
  update public.tournament_matches set sets = p_sets, winner_team_id = winner, status = 'finished', version = version + 1,
         updated_at = now(), updated_by = auth.uid() where id = p_match;
  if m.stage = 'knockout' and m.next_match_id is not null then
    perform public._t_set_slot(m.next_match_id, m.next_slot, winner);   -- avanza; si cambió, anula en cascada
  elsif m.stage = 'group' then
    perform public._t_seed_from_groups(m.tournament_id);
  end if;
  perform public._t_refresh(m.tournament_id);
  return jsonb_build_object('match_id', p_match, 'winner_team_id', winner, 'version', m.version + 1);
end $$;

create or replace function public.clear_tournament_result(p_match uuid, p_version int) returns void
language plpgsql security definer set search_path = public as $$
declare m public.tournament_matches;
begin
  select * into m from public.tournament_matches where id = p_match;
  if m.id is null then raise exception 'match_not_found'; end if;
  if not public._t_is_admin(m.tournament_id) then raise exception 'not_tournament_admin'; end if;
  perform 1 from public.tournaments where id = m.tournament_id for update;
  select * into m from public.tournament_matches where id = p_match for update;
  if m.version <> p_version then raise exception 'result_conflict'; end if;
  if m.status = 'bye' then raise exception 'match_not_ready'; end if;
  perform public._t_reset_match(p_match);
  if m.stage = 'group' then perform public._t_seed_from_groups(m.tournament_id); end if;
  perform public._t_refresh(m.tournament_id);
end $$;

create or replace function public.set_tournament_match_live(p_match uuid, p_live boolean) returns void
language plpgsql security definer set search_path = public as $$
declare m public.tournament_matches;
begin
  select * into m from public.tournament_matches where id = p_match;
  if m.id is null then raise exception 'match_not_found'; end if;
  if not public._t_is_admin(m.tournament_id) then raise exception 'not_tournament_admin'; end if;
  if m.status = 'finished' or m.status = 'bye' or m.team1_id is null or m.team2_id is null then raise exception 'match_not_ready'; end if;
  update public.tournament_matches set status = case when p_live then 'live' else 'pending' end, version = version + 1, updated_at = now() where id = p_match;
  perform public._t_refresh(m.tournament_id);
end $$;

create or replace function public.finish_tournament(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._t_is_admin(p_t) then raise exception 'not_tournament_admin'; end if;
  perform public._t_refresh(p_t);
  if (select champion_team_id from public.tournaments where id = p_t) is null then raise exception 'tournament_not_decided'; end if;
end $$;

create or replace function public.tournament_standings(p_t uuid)
returns table (group_label text, team_id uuid, seed int, played int, won int, lost int, sets_for int, sets_against int,
               games_for int, games_against int, points int, pos int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._t_can_view(p_t) then raise exception 'not_allowed'; end if;
  return query select * from public._t_standings(p_t) order by 1, 12;
end $$;

-- Mis torneos con lo necesario para la lista (la fase y el próximo partido se calculan en la app a partir de esto).
create or replace function public.my_tournaments()
returns table (id uuid, name text, cover_url text, starts_on date, ends_on date, time_slot text, location text, status text,
               format text, teams_count int, max_teams int, is_admin boolean, knockout_rounds int, current_round int,
               group_pending int, champion_team_id uuid, my_team_id uuid, next_match jsonb)
language sql stable security definer set search_path = public as $$
  select t.id, t.name, t.cover_url, t.starts_on, t.ends_on, t.time_slot, t.location, t.status, t.format,
         (select count(*) from public.tournament_teams x where x.tournament_id = t.id)::int,
         t.max_teams, public._t_is_admin(t.id),
         (select max(round) from public.tournament_matches x where x.tournament_id = t.id and x.stage = 'knockout')::int,
         (select min(round) from public.tournament_matches x where x.tournament_id = t.id and x.stage = 'knockout' and x.status in ('pending', 'live'))::int,
         (select count(*) from public.tournament_matches x where x.tournament_id = t.id and x.stage = 'group' and x.status <> 'finished')::int,
         t.champion_team_id,
         (select team_id from public.tournament_players p where p.tournament_id = t.id and p.user_id = auth.uid()),
         (select jsonb_build_object('match_id', m.id, 'stage', m.stage, 'group_label', m.group_label, 'round', m.round, 'status', m.status,
                 'opponent', (select jsonb_build_object('p1', a.display_name, 'p2', b.display_name)
                                from public.tournament_teams o join public.profiles a on a.id = o.player1_id join public.profiles b on b.id = o.player2_id
                               where o.id = case when m.team1_id = mp.team_id then m.team2_id else m.team1_id end))
            from public.tournament_matches m join public.tournament_players mp on mp.tournament_id = t.id and mp.user_id = auth.uid()
           where m.tournament_id = t.id and m.status in ('pending', 'live') and mp.team_id in (m.team1_id, m.team2_id)
           order by m.stage desc, m.round, m.position limit 1)
    from public.tournaments t
   where public._t_can_view(t.id)
   order by (t.status = 'finished'), t.starts_on;
$$;

-- ════════════════════════════ Tiempo real ════════════════════════════
-- Cualquier cambio en un torneo avisa (Broadcast privado `user:<uid>`, evento 'tournament') a sus organizadores y
-- jugadores. Por sentencia: registrar un resultado que mueve varias filas manda UN aviso por usuario.
create or replace function public._t_broadcast(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r uuid; sent text := coalesce(current_setting('plobby.t_broadcast', true), '');
begin
  -- UN aviso por torneo y transacción: una operación (p. ej. un resultado que avanza rondas) actualiza muchas filas,
  -- pero los clientes solo necesitan saber que el torneo cambió (lo recargan entero tras el commit).
  if position(p_t::text in sent) > 0 then return; end if;
  perform set_config('plobby.t_broadcast', sent || p_t::text || ',', true);
  for r in select user_id from public.tournament_admins where tournament_id = p_t
           union select user_id from public.tournament_players where tournament_id = p_t loop
    begin
      perform realtime.send(jsonb_build_object('tournament_id', p_t), 'tournament', 'user:' || r, true);
    exception when others then null;
    end;
  end loop;
end $$;

create or replace function public._t_broadcast_rows() returns trigger
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  if tg_op = 'DELETE' then
    for t in select distinct tournament_id from old_rows loop perform public._t_broadcast(t); end loop;
  else
    for t in select distinct tournament_id from new_rows loop perform public._t_broadcast(t); end loop;
  end if;
  return null;
end $$;

create or replace function public._t_broadcast_tournament() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public._t_broadcast(new.id);
  return null;
end $$;

drop trigger if exists tournament_matches_bi on public.tournament_matches;
drop trigger if exists tournament_matches_bu on public.tournament_matches;
create trigger tournament_matches_bi after insert on public.tournament_matches referencing new table as new_rows for each statement execute function public._t_broadcast_rows();
create trigger tournament_matches_bu after update on public.tournament_matches referencing new table as new_rows for each statement execute function public._t_broadcast_rows();
drop trigger if exists tournaments_bu on public.tournaments;
create trigger tournaments_bu after update on public.tournaments for each row execute function public._t_broadcast_tournament();

-- Las funciones internas no se exponen por RPC.
-- (_t_is_admin y _t_can_view siguen ejecutables: las usan las políticas RLS, que corren con el rol del usuario.)
revoke execute on function public._t_validate_sets(jsonb), public._t_seed_order(int),
  public._t_standings(uuid), public._t_reset_match(uuid), public._t_set_slot(uuid, smallint, uuid), public._t_resolve_bye(uuid),
  public._t_build_knockout(uuid, text[], boolean), public._t_build_round_robin(uuid, text), public._t_generate(uuid),
  public._t_seed_from_groups(uuid), public._t_refresh(uuid), public._t_insert_teams(uuid, jsonb), public._t_broadcast(uuid), public._t_notify_players(uuid),
  public._t_broadcast_rows(), public._t_broadcast_tournament() from public, anon, authenticated;
revoke execute on function public.create_tournament(jsonb), public.replace_tournament_teams(uuid, jsonb), public.update_tournament_info(uuid, jsonb),
  public.record_tournament_result(uuid, jsonb, int), public.clear_tournament_result(uuid, int), public.set_tournament_match_live(uuid, boolean),
  public.finish_tournament(uuid), public.tournament_standings(uuid), public.my_tournaments() from public, anon;
grant execute on function public.create_tournament(jsonb), public.replace_tournament_teams(uuid, jsonb), public.update_tournament_info(uuid, jsonb),
  public.record_tournament_result(uuid, jsonb, int), public.clear_tournament_result(uuid, int), public.set_tournament_match_live(uuid, boolean),
  public.finish_tournament(uuid), public.tournament_standings(uuid), public.my_tournaments() to authenticated;
