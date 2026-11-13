-- Plobby · Gamificación (2/2): Head to Head, Friends Ranking, Plobby Wrapped, logros, XP y niveles.
--
-- PRINCIPIO: una sola fuente de datos deportivos. `player_match_stats` tiene UNA fila por jugador y partido CONFIRMADO
-- (clave primaria → imposible contar dos veces). La mantiene el servidor con triggers: cuando un partido pasa a
-- `confirmed` se crean sus filas; si deja de estarlo (o cambian sus sets) se recalculan o se borran. Head to Head,
-- rankings, Wrapped, logros y XP leen SIEMPRE de aquí, así que un resultado tiene el mismo efecto en todo.
-- Nada de esto se puede escribir desde la app: sin permisos de escritura, RLS de solo lectura y funciones SECURITY
-- DEFINER que no se exponen como RPC.

-- ═══════════════════════════ 1. Configuración ═══════════════════════════
create table if not exists public.gamification_config (
  id int primary key default 1 check (id = 1),
  timezone text not null default 'Europe/Madrid',                 -- semanas (lunes) y meses de las temporadas
  min_rate_matches jsonb not null default '{"week": 2, "month": 4, "year": 10, "all": 10}',  -- mínimo para el ranking de %
  daily_notification_limit int not null default 3                  -- avisos de ranking por persona y día
);
insert into public.gamification_config (id) values (1) on conflict do nothing;
alter table public.gamification_config enable row level security;
drop policy if exists gamification_config_read on public.gamification_config;
create policy gamification_config_read on public.gamification_config for select to authenticated using (true);
revoke all on public.gamification_config from anon;
revoke insert, update, delete on public.gamification_config from authenticated;

create or replace function public._g_tz() returns text language sql stable set search_path = public as
  $$ select coalesce((select timezone from public.gamification_config where id = 1), 'Europe/Madrid') $$;

-- ═══════════════════════════ 2. Estadísticas centrales ═══════════════════════════
create table if not exists public.player_match_stats (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  played_at timestamptz not null,
  team smallint not null,
  won boolean not null,
  sets_won smallint not null, sets_lost smallint not null,
  games_won smallint not null, games_lost smallint not null,
  partner_id uuid, rival1_id uuid, rival2_id uuid,
  is_league boolean not null default false,
  primary key (match_id, user_id)
);
create index if not exists pms_user_time_idx on public.player_match_stats (user_id, played_at desc);
create index if not exists pms_rival1_idx on public.player_match_stats (rival1_id);
create index if not exists pms_rival2_idx on public.player_match_stats (rival2_id);
create index if not exists pms_partner_idx on public.player_match_stats (partner_id);
create index if not exists pms_time_idx on public.player_match_stats (played_at);
alter table public.player_match_stats enable row level security;
drop policy if exists pms_read on public.player_match_stats;
create policy pms_read on public.player_match_stats for select to authenticated
  using (user_id = (select auth.uid()) or public.can_view_user(user_id));
revoke all on public.player_match_stats from anon;
revoke insert, update, delete, truncate on public.player_match_stats from authenticated;

-- Recalcula las filas de un partido desde las tablas de origen. Idempotente.
create or replace function public._g_sync_match(p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m public.matches; w1 int; w2 int; g1 int; g2 int;
begin
  delete from public.player_match_stats where match_id = p_match;
  select * into m from public.matches where id = p_match;
  if not found or m.status <> 'confirmed' then return; end if;
  select count(*) filter (where team1_games > team2_games), count(*) filter (where team2_games > team1_games),
         coalesce(sum(team1_games), 0), coalesce(sum(team2_games), 0)
    into w1, w2, g1, g2 from public.match_sets where match_id = p_match;
  if w1 = w2 then return; end if;                                   -- sin resultado válido: no suma
  insert into public.player_match_stats (match_id, user_id, played_at, team, won, sets_won, sets_lost, games_won, games_lost,
                                         partner_id, rival1_id, rival2_id, is_league)
  select p_match, mp.user_id, coalesce(m.played_at, m.ended_at, m.confirmed_at, m.created_at), mp.team,
         (mp.team = 1) = (w1 > w2),
         case when mp.team = 1 then w1 else w2 end, case when mp.team = 1 then w2 else w1 end,
         case when mp.team = 1 then g1 else g2 end, case when mp.team = 1 then g2 else g1 end,
         (select x.user_id from public.match_players x where x.match_id = p_match and x.team = mp.team and x.user_id <> mp.user_id limit 1),
         (select x.user_id from public.match_players x where x.match_id = p_match and x.team <> mp.team order by x.user_id limit 1),
         (select x.user_id from public.match_players x where x.match_id = p_match and x.team <> mp.team order by x.user_id offset 1 limit 1),
         m.match_type = 'league'
    from public.match_players mp where mp.match_id = p_match;
end $$;

-- ═══════════════════════════ 3. XP y niveles ═══════════════════════════
-- XP: 100 por partido confirmado, +50 por victoria, + la recompensa de cada logro. Libro de movimientos con clave
-- única (usuario, origen, id): cada recompensa se concede UNA vez. Si el origen desaparece, su fila se borra.
create table if not exists public.xp_events (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null check (source_type in ('match', 'win', 'achievement')),
  source_id text not null,
  xp int not null check (xp between 0 and 10000),
  created_at timestamptz not null default now(),
  unique (user_id, source_type, source_id)
);
create index if not exists xp_events_user_idx on public.xp_events (user_id, created_at desc);
alter table public.xp_events enable row level security;
drop policy if exists xp_events_read on public.xp_events;
create policy xp_events_read on public.xp_events for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.xp_events from anon;
revoke insert, update, delete, truncate on public.xp_events from authenticated;

create table if not exists public.player_progress (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  xp int not null default 0,
  level int not null default 1,
  updated_at timestamptz not null default now()
);
alter table public.player_progress enable row level security;
drop policy if exists player_progress_read on public.player_progress;
create policy player_progress_read on public.player_progress for select to authenticated
  using (user_id = (select auth.uid()) or public.can_view_user(user_id));
revoke all on public.player_progress from anon;
revoke insert, update, delete, truncate on public.player_progress from authenticated;

-- XP acumulada necesaria para llegar al nivel L: pasar de L a L+1 cuesta 300 + 100·L
-- (nivel 2: 400 XP, nivel 3: 900, nivel 4: 1.500…). Representa actividad, no habilidad.
create or replace function public.xp_for_level(p_level int) returns int language sql immutable as
  $$ select (300 * (greatest(p_level, 1) - 1) + 50 * (greatest(p_level, 1) - 1) * greatest(p_level, 1))::int $$;
create or replace function public.level_for_xp(p_xp int) returns int language plpgsql immutable as $$
declare l int := 1;
begin
  while l < 100 and public.xp_for_level(l + 1) <= coalesce(p_xp, 0) loop l := l + 1; end loop;
  return l;
end $$;

-- ═══════════════════════════ 4. Avisos: preferencias y límites ═══════════════════════════
create table if not exists public.notification_prefs (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  ranking boolean not null default true,
  achievements boolean not null default true,
  levels boolean not null default true,
  wrapped boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.notification_prefs enable row level security;
drop policy if exists notification_prefs_own on public.notification_prefs;
create policy notification_prefs_own on public.notification_prefs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.notification_prefs from anon;

create or replace function public._g_backfill() returns boolean language sql stable as
  $$ select coalesce(current_setting('plobby.backfill', true), '') = 'on' $$;

-- Crea un aviso si la persona lo quiere, no es una carga histórica y (para ranking) no supera el límite diario.
create or replace function public._g_notify(p_user uuid, p_kind text, p_type public.notification_type, p_title text, p_body text,
                                            p_key text, p_actor uuid default null, p_ref uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare pref public.notification_prefs; today int;
begin
  if public._g_backfill() then return; end if;
  select * into pref from public.notification_prefs where user_id = p_user;
  if found and ((p_kind = 'ranking' and not pref.ranking) or (p_kind = 'achievements' and not pref.achievements)
             or (p_kind = 'levels' and not pref.levels) or (p_kind = 'wrapped' and not pref.wrapped)) then return; end if;
  if p_kind = 'ranking' then
    select count(*) into today from public.notifications
     where recipient_user_id = p_user and notification_type = 'ranking' and created_at > now() - interval '1 day';
    if today >= (select daily_notification_limit from public.gamification_config where id = 1) then return; end if;
  end if;
  insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
  values (p_user, p_actor, p_type, p_ref, p_title, p_body, p_key) on conflict do nothing;
exception when others then null;   -- un aviso nunca impide confirmar un partido
end $$;

-- Recalcula XP y nivel; avisa al subir de nivel.
create or replace function public._g_refresh_progress(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare total int; lvl int; old_lvl int;
begin
  select coalesce(sum(xp), 0) into total from public.xp_events where user_id = p_user;
  lvl := public.level_for_xp(total);
  select level into old_lvl from public.player_progress where user_id = p_user;
  insert into public.player_progress (user_id, xp, level, updated_at) values (p_user, total, lvl, now())
    on conflict (user_id) do update set xp = excluded.xp, level = excluded.level, updated_at = now();
  if old_lvl is not null and lvl > old_lvl then
    perform public._g_notify(p_user, 'levels', 'level_up', 'Has subido al nivel ' || lvl, 'Sigue jugando para desbloquear más logros.',
                             'level:' || lvl);
  end if;
end $$;

-- ═══════════════════════════ 5. Logros ═══════════════════════════
create table if not exists public.achievement_catalog (
  id text primary key,
  category text not null check (category in ('activity', 'wins', 'streak', 'social', 'competition')),
  title text not null, description text not null, icon text not null,
  metric text not null check (metric in ('matches', 'wins', 'best_streak', 'partners', 'rivals', 'event')),
  goal int not null default 1, xp int not null default 100, sort int not null default 0
);
alter table public.achievement_catalog enable row level security;
drop policy if exists achievement_catalog_read on public.achievement_catalog;
create policy achievement_catalog_read on public.achievement_catalog for select to authenticated using (true);
revoke all on public.achievement_catalog from anon;
revoke insert, update, delete, truncate on public.achievement_catalog from authenticated;

insert into public.achievement_catalog (id, category, title, description, icon, metric, goal, xp, sort) values
  ('matches_1',   'activity', 'Primer partido',      'Juega tu primer partido confirmado.',          'ball',   'matches', 1,   50,  10),
  ('matches_10',  'activity', '10 partidos',         'Juega 10 partidos confirmados.',               'ball',   'matches', 10,  100, 11),
  ('matches_25',  'activity', '25 partidos',         'Juega 25 partidos confirmados.',               'ball',   'matches', 25,  200, 12),
  ('matches_50',  'activity', '50 partidos',         'Juega 50 partidos confirmados.',               'ball',   'matches', 50,  300, 13),
  ('matches_100', 'activity', '100 partidos',        'Juega 100 partidos confirmados.',              'ball',   'matches', 100, 500, 14),
  ('wins_1',      'wins',     'Primera victoria',    'Gana tu primer partido.',                      'trophy', 'wins', 1,      50,  20),
  ('wins_5',      'wins',     '5 victorias',         'Gana 5 partidos.',                             'trophy', 'wins', 5,      100, 21),
  ('wins_10',     'wins',     '10 victorias',        'Gana 10 partidos.',                            'trophy', 'wins', 10,     150, 22),
  ('wins_25',     'wins',     '25 victorias',        'Gana 25 partidos.',                            'trophy', 'wins', 25,     250, 23),
  ('wins_50',     'wins',     '50 victorias',        'Gana 50 partidos.',                            'trophy', 'wins', 50,     400, 24),
  ('streak_3',    'streak',   'En racha',            'Gana 3 partidos seguidos.',                    'flame',  'best_streak', 3,  100, 30),
  ('streak_5',    'streak',   'Imparable',           'Gana 5 partidos seguidos.',                    'flame',  'best_streak', 5,  200, 31),
  ('streak_10',   'streak',   'Leyenda',             'Gana 10 partidos seguidos.',                   'flame',  'best_streak', 10, 400, 32),
  ('partners_5',  'social',   'Buen compañero',      'Juega con 5 compañeros distintos.',            'users',  'partners', 5,  100, 40),
  ('partners_10', 'social',   'Jugador social',      'Juega con 10 compañeros distintos.',           'users',  'partners', 10, 200, 41),
  ('rivals_10',   'social',   'Sin miedo',           'Enfréntate a 10 rivales distintos.',           'users',  'rivals', 10,   150, 42),
  ('week_winner', 'competition', 'Campeón semanal',  'Gana el ranking semanal entre tus amigos.',    'star',   'event', 1,    200, 50),
  ('month_winner','competition', 'Campeón del mes',  'Gana el ranking mensual entre tus amigos.',    'star',   'event', 1,    400, 51),
  ('top3_friends','competition', 'Podio',            'Termina una temporada en el Top 3 de tus amigos.', 'star', 'event', 1,  150, 52),
  ('tournament_winner', 'competition', 'Campeón de torneo', 'Gana un torneo de Plobby.',             'trophy', 'event', 1,    500, 53)
on conflict (id) do update set category = excluded.category, title = excluded.title, description = excluded.description,
  icon = excluded.icon, metric = excluded.metric, goal = excluded.goal, xp = excluded.xp, sort = excluded.sort;

-- `seen_at`: la app muestra la celebración de los logros que aún no ha visto (los históricos se marcan como vistos).
alter table public.user_achievements add column if not exists seen_at timestamptz;
create index if not exists user_achievements_unseen_idx on public.user_achievements (user_id) where seen_at is null;

-- Métricas de un jugador (para logros y perfil), siempre desde player_match_stats.
create or replace function public._g_metrics(p_user uuid, p_from timestamptz default '-infinity', p_to timestamptz default 'infinity')
returns table (played int, wins int, losses int, best_streak int, partners int, rivals int, sets_won int, sets_lost int)
language sql stable security definer set search_path = public as $$
  with s as (
    select * from public.player_match_stats where user_id = p_user and played_at >= p_from and played_at < p_to
  ), runs as (   -- rachas de victorias: grupos consecutivos de «won» ordenados por fecha
    select won, row_number() over (order by played_at, match_id) - row_number() over (partition by won order by played_at, match_id) as grp from s
  )
  select (select count(*) from s)::int, (select count(*) filter (where won) from s)::int, (select count(*) filter (where not won) from s)::int,
         coalesce((select max(c) from (select count(*) c from runs where won group by grp) x), 0)::int,
         (select count(distinct partner_id) from s where partner_id is not null)::int,
         (select count(distinct r) from (select rival1_id r from s union all select rival2_id from s) y where r is not null)::int,
         coalesce((select sum(sets_won) from s), 0)::int, coalesce((select sum(sets_lost) from s), 0)::int
$$;

-- Concede o retira (si el dato ya no lo justifica) un logro y su XP.
create or replace function public._g_grant(p_user uuid, p_ach text) returns boolean
language plpgsql security definer set search_path = public as $$
declare c public.achievement_catalog; n int;
begin
  select * into c from public.achievement_catalog where id = p_ach;
  if not found then return false; end if;
  insert into public.user_achievements (user_id, achievement_id, unlocked_at, seen_at)
  values (p_user, p_ach, now(), case when public._g_backfill() then now() end) on conflict (user_id, achievement_id) do nothing;
  get diagnostics n = row_count;
  if n = 0 then return false; end if;
  insert into public.xp_events (user_id, source_type, source_id, xp) values (p_user, 'achievement', p_ach, c.xp) on conflict do nothing;
  perform public._g_notify(p_user, 'achievements', 'achievement', 'Logro desbloqueado: ' || c.title, c.description, 'ach:' || p_ach);
  return true;
end $$;

create or replace function public._g_revoke(p_user uuid, p_ach text) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.user_achievements where user_id = p_user and achievement_id = p_ach;
  delete from public.xp_events where user_id = p_user and source_type = 'achievement' and source_id = p_ach;
  delete from public.feed_posts where user_id = p_user and activity_type = 'achievement' and metadata->>'achievement_id' = p_ach;
end $$;

-- Evalúa los logros de estadística de un jugador: concede los alcanzados y retira los que ya no se cumplen (p. ej.
-- si un partido dejara de contar). Los de competición (eventos) solo los concede/retira su propio proceso.
create or replace function public._g_evaluate(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare mt record; c public.achievement_catalog; v int;
begin
  select * into mt from public._g_metrics(p_user);
  for c in select * from public.achievement_catalog where metric <> 'event' loop
    v := case c.metric when 'matches' then mt.played when 'wins' then mt.wins when 'best_streak' then mt.best_streak
                        when 'partners' then mt.partners when 'rivals' then mt.rivals end;
    if v >= c.goal then perform public._g_grant(p_user, c.id);
    elsif exists (select 1 from public.user_achievements where user_id = p_user and achievement_id = c.id) then perform public._g_revoke(p_user, c.id);
    end if;
  end loop;
end $$;

-- Publicación en el feed al desbloquear un logro: ahora con título y descripción del catálogo, y nunca en la carga
-- histórica (no inunda el feed con logros antiguos).
create or replace function public.on_achievement_unlocked() returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.achievement_catalog;
begin
  if public._g_backfill() then return new; end if;
  select * into c from public.achievement_catalog where id = new.achievement_id;
  perform public.emit_feed_event(new.user_id, 'achievement', 'ach:' || new.id, null, new.id,
    jsonb_build_object('achievement_id', new.achievement_id, 'title', c.title, 'description', c.description));
  return new;
end $$;

-- ═══════════════════════════ 6. Rankings y temporadas ═══════════════════════════
create table if not exists public.ranking_periods (
  kind text not null check (kind in ('week', 'month')),
  starts_on date not null,
  ends_on date not null,
  closed_at timestamptz not null default now(),
  primary key (kind, starts_on)
);
alter table public.ranking_periods enable row level security;
drop policy if exists ranking_periods_read on public.ranking_periods;
create policy ranking_periods_read on public.ranking_periods for select to authenticated using (true);
revoke all on public.ranking_periods from anon;
revoke insert, update, delete, truncate on public.ranking_periods from authenticated;

-- Clasificación final congelada de CADA jugador entre sus amigos (cada uno tiene su propio grupo de amigos).
create table if not exists public.ranking_snapshots (
  kind text not null, starts_on date not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rows jsonb not null,
  pos_wins int, pos_rate int, pos_activity int,
  active_players int not null default 0,
  primary key (kind, starts_on, user_id),
  foreign key (kind, starts_on) references public.ranking_periods(kind, starts_on) on delete cascade
);
create index if not exists ranking_snapshots_user_idx on public.ranking_snapshots (user_id, kind, starts_on desc);
alter table public.ranking_snapshots enable row level security;
drop policy if exists ranking_snapshots_own on public.ranking_snapshots;
create policy ranking_snapshots_own on public.ranking_snapshots for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.ranking_snapshots from anon;
revoke insert, update, delete, truncate on public.ranking_snapshots from authenticated;

-- Límites del periodo en la zona horaria de la app. offset 0 = actual, -1 = anterior…
create or replace function public._g_period(p_kind text, p_offset int default 0, out p_start date, out p_end date)
language plpgsql stable set search_path = public as $$
declare today date := (now() at time zone public._g_tz())::date;
begin
  case p_kind
    when 'week'  then p_start := date_trunc('week', today)::date + 7 * p_offset; p_end := p_start + 7;
    when 'month' then p_start := (date_trunc('month', today) + make_interval(months => p_offset))::date; p_end := (p_start + interval '1 month')::date;
    when 'year'  then p_start := (date_trunc('year', today) + make_interval(years => p_offset))::date; p_end := (p_start + interval '1 year')::date;
    when 'all'   then p_start := date '2000-01-01'; p_end := date '2100-01-01';
    else raise exception 'invalid_period';
  end case;
end $$;

create or replace function public._g_ts(p_day date) returns timestamptz language sql stable set search_path = public as
  $$ select (p_day::timestamp at time zone public._g_tz()) $$;

-- Filas del ranking de [p_viewer + sus amigos] en un intervalo. Reglas (docs/gamificacion.md):
--  · victorias: más victorias; empate → mejor % → más partidos (a igualdad de victorias y %, solo difieren con 0
--    victorias: quien ha jugado va por delante de quien no); si sigue el empate, comparten puesto;
--  · %: solo quien llega al mínimo de partidos; empate → más victorias;
--  · actividad: más partidos; empate → más victorias.
create or replace function public._g_ranking_rows(p_viewer uuid, p_from timestamptz, p_to timestamptz, p_min int)
returns table (user_id uuid, wins int, losses int, played int, win_rate int, pos_wins int, pos_rate int, pos_activity int)
language sql stable security definer set search_path = public as $$
  with grp as (
    select p_viewer as uid union select friend_id from public.friendships where user_id = p_viewer and status = 'accepted'
  ), agg as (
    select g.uid, count(s.match_id) filter (where s.won)::int w, count(s.match_id) filter (where not s.won)::int l, count(s.match_id)::int pl
      from grp g left join public.player_match_stats s on s.user_id = g.uid and s.played_at >= p_from and s.played_at < p_to
     group by g.uid
  ), r as (
    select uid, w, l, pl, case when pl > 0 then round(100.0 * w / pl)::int else 0 end rate,
           case when pl > 0 then w::numeric / pl else 0 end ratio from agg
  )
  select uid, w, l, pl, rate,
         rank() over (order by w desc, ratio desc, pl desc)::int,
         case when pl >= p_min then rank() over (partition by pl >= p_min order by ratio desc, w desc)::int end,
         rank() over (order by pl desc, w desc)::int
    from r
$$;

create or replace function public._g_rows_json(p_viewer uuid, p_from timestamptz, p_to timestamptz, p_min int) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', r.user_id, 'name', p.display_name, 'username', p.username, 'avatar_url', p.avatar_url,
           'wins', r.wins, 'losses', r.losses, 'played', r.played, 'win_rate', r.win_rate,
           'pos_wins', r.pos_wins, 'pos_rate', r.pos_rate, 'pos_activity', r.pos_activity,
           'level', coalesce(pp.level, 1)) order by r.pos_wins, p.display_name), '[]'::jsonb)
    from public._g_ranking_rows(p_viewer, p_from, p_to, p_min) r
    join public.profiles p on p.id = r.user_id
    left join public.player_progress pp on pp.user_id = r.user_id
$$;

-- Cierra las temporadas semanal y mensual que hayan terminado (idempotente; la primera llamada tras el cambio de
-- semana/mes la ejecuta). Congela la clasificación de cada jugador, concede insignias de ganador y Top 3, avisa del
-- resultado y del Wrapped mensual. Los partidos se asignan por la fecha en que se JUGARON; uno confirmado después del
-- cierre ya no altera una temporada cerrada.
create or replace function public._g_close_periods() returns void
language plpgsql security definer set search_path = public as $$
declare k text; ps date; pe date; minm int; u record; snap record; fromt timestamptz; tot timestamptz; label text;
begin
  foreach k in array array['week', 'month'] loop
    select p_start, p_end into ps, pe from public._g_period(k, -1);
    if exists (select 1 from public.ranking_periods where kind = k and starts_on = ps) then continue; end if;
    perform pg_advisory_xact_lock(hashtext('plobby_close_' || k || ps));
    if exists (select 1 from public.ranking_periods where kind = k and starts_on = ps) then continue; end if;
    insert into public.ranking_periods (kind, starts_on, ends_on) values (k, ps, pe);
    minm := ((select min_rate_matches from public.gamification_config where id = 1) ->> k)::int;
    fromt := public._g_ts(ps); tot := public._g_ts(pe);
    label := case k when 'week' then 'semanal' else 'mensual' end;
    -- jugadores con partidos en el periodo y sus amigos (los únicos cuyo grupo puede tener actividad)
    for u in
      select distinct x.uid from (
        select s.user_id uid from public.player_match_stats s where s.played_at >= fromt and s.played_at < tot
        union select f.friend_id from public.player_match_stats s join public.friendships f on f.user_id = s.user_id and f.status = 'accepted'
         where s.played_at >= fromt and s.played_at < tot) x
    loop
      select r.pos_wins, r.pos_rate, r.pos_activity, r.wins, r.played,
             (select count(*) from public._g_ranking_rows(u.uid, fromt, tot, minm) z where z.played > 0) act
        into snap from public._g_ranking_rows(u.uid, fromt, tot, minm) r where r.user_id = u.uid;
      insert into public.ranking_snapshots (kind, starts_on, user_id, rows, pos_wins, pos_rate, pos_activity, active_players)
      values (k, ps, u.uid, public._g_rows_json(u.uid, fromt, tot, minm), snap.pos_wins, snap.pos_rate, snap.pos_activity, snap.act)
      on conflict do nothing;
      continue when snap.played = 0;
      if snap.pos_wins = 1 and snap.wins > 0 and snap.act >= 2 then
        perform public._g_grant(u.uid, case k when 'week' then 'week_winner' else 'month_winner' end);
        perform public._g_notify(u.uid, 'ranking', 'ranking', '¡Has ganado la clasificación ' || label || '!',
                                 'Eres el número 1 entre tus amigos. Defiende el título en la nueva temporada.', 'season:' || k || ':' || ps);
      else
        perform public._g_notify(u.uid, 'ranking', 'ranking', 'Clasificación ' || label || ' cerrada',
                                 'Has terminado en el puesto ' || snap.pos_wins || ' de ' || snap.act || '. ¡Empieza una nueva temporada!',
                                 'season:' || k || ':' || ps);
      end if;
      if snap.pos_wins <= 3 and snap.act >= 4 then perform public._g_grant(u.uid, 'top3_friends'); end if;
      if k = 'month' then
        perform public._g_notify(u.uid, 'wrapped', 'wrapped', 'Tu Plobby Wrapped de ' || (array['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'])[extract(month from ps)::int] || ' está listo',
                                 'Descubre cómo ha sido tu mes en la pista.', 'wrapped:' || ps);
      end if;
    end loop;
  end loop;
end $$;

-- ═══════════════════════════ 7. Reacción a cambios de partido ═══════════════════════════
-- Avisos de ranking semanal tras un partido: a quien ganó y adelanta a amigos, y a los amigos adelantados.
create or replace function public._g_rank_notifications(p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s record; ps date; pe date; fromt timestamptz; tot timestamptz; before_pos int; after_pos int; f record; nm text;
begin
  select p_start, p_end into ps, pe from public._g_period('week', 0);
  fromt := public._g_ts(ps); tot := public._g_ts(pe);
  for s in select * from public.player_match_stats where match_id = p_match and won and played_at >= fromt and played_at < tot loop
    select display_name into nm from public.profiles where id = s.user_id;
    -- puesto antes (sin este partido) y después, por victorias
    select count(*) + 1 into after_pos from public._g_ranking_rows(s.user_id, fromt, tot, 0) r
      where r.user_id <> s.user_id and r.wins > (select wins from public._g_ranking_rows(s.user_id, fromt, tot, 0) q where q.user_id = s.user_id);
    select count(*) + 1 into before_pos from public._g_ranking_rows(s.user_id, fromt, tot, 0) r
      where r.user_id <> s.user_id and r.wins > (select wins - 1 from public._g_ranking_rows(s.user_id, fromt, tot, 0) q where q.user_id = s.user_id);
    if after_pos < before_pos then
      perform public._g_notify(s.user_id, 'ranking', 'ranking',
        case when after_pos <= 3 and before_pos > 3 then '¡Entras en el Top 3!' else 'Subes al puesto ' || after_pos end,
        'Clasificación semanal entre tus amigos.', 'rank_up:' || ps || ':' || after_pos);
      -- amigos a los que acaba de adelantar (tenían tantas victorias como él antes del partido)
      for f in select r.user_id from public._g_ranking_rows(s.user_id, fromt, tot, 0) r
                where r.user_id <> s.user_id and r.wins >= 1
                  and r.wins = (select wins - 1 from public._g_ranking_rows(s.user_id, fromt, tot, 0) q where q.user_id = s.user_id) loop
        perform public._g_notify(f.user_id, 'ranking', 'ranking', coalesce(nm, 'Un amigo') || ' te ha adelantado',
                                 'Clasificación semanal: juega un partido para recuperar tu puesto.', 'rank_over:' || ps || ':' || s.user_id, s.user_id);
      end loop;
    end if;
  end loop;
end $$;

-- Tras crear/borrar las filas de un partido: XP de partido y victoria, logros y avisos. Todo en la misma transacción.
create or replace function public._g_after_match(p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  for u in select distinct user_id from public.match_players where match_id = p_match loop
    delete from public.xp_events where user_id = u and source_type in ('match', 'win') and source_id = p_match::text
      and not exists (select 1 from public.player_match_stats s where s.match_id = p_match and s.user_id = u);
    insert into public.xp_events (user_id, source_type, source_id, xp)
      select s.user_id, 'match', p_match::text, 100 from public.player_match_stats s where s.match_id = p_match and s.user_id = u
      on conflict do nothing;
    delete from public.xp_events where user_id = u and source_type = 'win' and source_id = p_match::text
      and not exists (select 1 from public.player_match_stats s where s.match_id = p_match and s.user_id = u and s.won);
    insert into public.xp_events (user_id, source_type, source_id, xp)
      select s.user_id, 'win', p_match::text, 50 from public.player_match_stats s where s.match_id = p_match and s.user_id = u and s.won
      on conflict do nothing;
    perform public._g_evaluate(u);
    perform public._g_refresh_progress(u);
  end loop;
  if not public._g_backfill() then perform public._g_rank_notifications(p_match); end if;
end $$;

create or replace function public._g_on_match_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and (new.status = 'confirmed' or old.status = 'confirmed') then
    perform public._g_sync_match(new.id);
    perform public._g_after_match(new.id);
  end if;
  return new;
end $$;
drop trigger if exists matches_gamification on public.matches;
create trigger matches_gamification after update of status on public.matches for each row execute function public._g_on_match_change();

-- Si cambian los sets de un partido YA confirmado (corrección administrativa), se recalcula todo lo que depende de él.
create or replace function public._g_on_sets_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare mid uuid := coalesce(new.match_id, old.match_id);
begin
  if exists (select 1 from public.matches where id = mid and status = 'confirmed') then
    perform public._g_sync_match(mid);
    perform public._g_after_match(mid);
  end if;
  return null;
end $$;
drop trigger if exists match_sets_gamification on public.match_sets;
create trigger match_sets_gamification after insert or update or delete on public.match_sets for each row execute function public._g_on_sets_change();

-- Campeones de torneo → logro (y se retira si se corrige la final y el campeón ya no ha ganado ningún otro torneo).
create or replace function public._g_on_tournament() returns trigger
language plpgsql security definer set search_path = public as $$
declare t public.tournament_teams; u uuid;
begin
  if old.status = 'finished' and old.champion_team_id is not null
     and (new.status <> 'finished' or new.champion_team_id is distinct from old.champion_team_id) then
    select * into t from public.tournament_teams where id = old.champion_team_id;
    foreach u in array array[t.player1_id, t.player2_id] loop
      if not exists (select 1 from public.tournaments x join public.tournament_teams y on y.id = x.champion_team_id
                      where x.status = 'finished' and x.id <> new.id and u in (y.player1_id, y.player2_id)) then
        perform public._g_revoke(u, 'tournament_winner');
        perform public._g_refresh_progress(u);
      end if;
    end loop;
  end if;
  if new.status = 'finished' and new.champion_team_id is not null
     and (old.status <> 'finished' or new.champion_team_id is distinct from old.champion_team_id) then
    select * into t from public.tournament_teams where id = new.champion_team_id;
    foreach u in array array[t.player1_id, t.player2_id] loop
      perform public._g_grant(u, 'tournament_winner');
      perform public._g_refresh_progress(u);
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists tournaments_gamification on public.tournaments;
create trigger tournaments_gamification after update of status, champion_team_id on public.tournaments for each row execute function public._g_on_tournament();

-- ═══════════════════════════ 8. RPC para la app ═══════════════════════════
-- Resumen de un jugador (perfil, H2H): solo uno mismo o un amigo.
create or replace function public._g_player_card(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mt record; cur int := 0; last_won boolean; r record; form text := ''; series jsonb; p public.profiles;
begin
  select * into p from public.profiles where id = p_user;
  select * into mt from public._g_metrics(p_user);
  for r in select won from public.player_match_stats where user_id = p_user order by played_at desc, match_id desc loop
    if last_won is null then last_won := r.won; end if;
    exit when r.won <> last_won;
    cur := cur + 1;
  end loop;
  select string_agg(case when won then 'W' else 'L' end, '' order by played_at desc) into form
    from (select won, played_at from public.player_match_stats where user_id = p_user order by played_at desc limit 5) x;
  -- evolución: % de victorias de los últimos 6 meses (meses sin partidos → null)
  select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'played', coalesce(pl, 0),
           'win_rate', case when pl > 0 then round(100.0 * w / pl) end) order by m) into series
    from (select gs::date m from generate_series(date_trunc('month', now() at time zone public._g_tz()) - interval '5 months',
                                                 date_trunc('month', now() at time zone public._g_tz()), interval '1 month') gs) months
    left join lateral (select count(*) pl, count(*) filter (where won) w from public.player_match_stats
                        where user_id = p_user and played_at >= public._g_ts(months.m) and played_at < public._g_ts((months.m + interval '1 month')::date)) a on true;
  return jsonb_build_object('user_id', p_user, 'name', p.display_name, 'username', p.username, 'avatar_url', p.avatar_url,
    'elo', (select elo from public.player_ratings where user_id = p_user),
    'level', coalesce((select level from public.player_progress where user_id = p_user), 1),
    'played', mt.played, 'wins', mt.wins, 'losses', mt.losses,
    'win_rate', case when mt.played > 0 then round(100.0 * mt.wins / mt.played) else 0 end,
    'sets_won', mt.sets_won, 'sets_lost', mt.sets_lost, 'best_streak', mt.best_streak,
    'current_streak', case when last_won is null then 0 when last_won then cur else -cur end,
    'form', coalesce(form, ''), 'monthly', coalesce(series, '[]'::jsonb));
end $$;

create or replace function public.head_to_head(p_other uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); direct jsonb; together jsonb;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if p_other is null or p_other = me then raise exception 'invalid_player'; end if;
  if not public.can_view_user(p_other) then raise exception 'not_friends' using errcode = '42501'; end if;
  -- enfrentamientos directos: partidos confirmados en los que los dos jugaron en equipos CONTRARIOS
  select jsonb_build_object(
      'total', count(*), 'my_wins', count(*) filter (where a.won), 'their_wins', count(*) filter (where not a.won),
      'last_at', max(a.played_at),
      'matches', coalesce(jsonb_agg(jsonb_build_object('match_id', a.match_id, 'played_at', a.played_at, 'won', a.won,
                   'sets', (select jsonb_agg(jsonb_build_array(case when a.team = 1 then x.team1_games else x.team2_games end,
                                                               case when a.team = 1 then x.team2_games else x.team1_games end) order by x.set_no)
                            from public.match_sets x where x.match_id = a.match_id),
                   'my_partner', (select display_name from public.profiles where id = a.partner_id),
                   'their_partner', (select display_name from public.profiles where id = b.partner_id))
                 order by a.played_at desc, a.match_id desc), '[]'::jsonb))
    into direct
    from public.player_match_stats a join public.player_match_stats b on b.match_id = a.match_id and b.user_id = p_other and b.team <> a.team
   where a.user_id = me;
  select jsonb_build_object('total', count(*), 'wins', count(*) filter (where a.won)) into together
    from public.player_match_stats a where a.user_id = me and a.partner_id = p_other;
  return jsonb_build_object('me', public._g_player_card(me), 'other', public._g_player_card(p_other), 'direct', direct, 'together', together);
end $$;

-- Ranking entre amigos. p_period: week | month | year | all; p_offset 0 = actual, -1 = anterior… Las temporadas
-- semanales y mensuales ya cerradas se leen de su foto congelada.
create or replace function public.friends_ranking(p_period text, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); ps date; pe date; pps date; ppe date; minm int; rows jsonb; prev jsonb; snap public.ranking_snapshots; closed boolean := false;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if p_period not in ('week', 'month', 'year', 'all') or p_offset > 0 or p_offset < -60 then raise exception 'invalid_period'; end if;
  perform public._g_close_periods();
  select p_start, p_end into ps, pe from public._g_period(p_period, p_offset);
  minm := ((select min_rate_matches from public.gamification_config where id = 1) ->> p_period)::int;
  if p_period in ('week', 'month') then
    select * into snap from public.ranking_snapshots where kind = p_period and starts_on = ps and user_id = me;
    if found then rows := snap.rows; closed := true; end if;
    closed := closed or exists (select 1 from public.ranking_periods where kind = p_period and starts_on = ps);
  end if;
  if rows is null then rows := public._g_rows_json(me, public._g_ts(ps), public._g_ts(pe), minm); end if;
  if p_period <> 'all' then
    select p_start, p_end into pps, ppe from public._g_period(p_period, p_offset - 1);
    select s.rows into prev from public.ranking_snapshots s where s.kind = p_period and s.starts_on = pps and s.user_id = me;
    if prev is null then prev := public._g_rows_json(me, public._g_ts(pps), public._g_ts(ppe), minm); end if;
  end if;
  return jsonb_build_object('period', p_period, 'offset', p_offset, 'starts_on', ps, 'ends_on', pe, 'closed', closed,
    'min_matches', minm, 'rows', rows, 'previous', coalesce(prev, '[]'::jsonb), 'me', me);
end $$;

-- Temporadas ganadas por el usuario (insignias del perfil).
create or replace function public.my_season_titles() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'starts_on', starts_on) order by starts_on desc), '[]'::jsonb)
    from public.ranking_snapshots where user_id = auth.uid() and pos_wins = 1
     and (rows -> (0) ->> 'wins')::int > 0 and active_players >= 2
$$;

-- Logros con su estado y progreso, y el nivel.
create or replace function public.my_achievements() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); mt record; pp public.player_progress;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select * into mt from public._g_metrics(me);
  select * into pp from public.player_progress where user_id = me;
  return jsonb_build_object(
    'xp', coalesce(pp.xp, 0), 'level', coalesce(pp.level, 1),
    'level_floor', public.xp_for_level(coalesce(pp.level, 1)), 'level_ceiling', public.xp_for_level(coalesce(pp.level, 1) + 1),
    'achievements', (select jsonb_agg(jsonb_build_object('id', c.id, 'category', c.category, 'title', c.title, 'description', c.description,
        'icon', c.icon, 'goal', c.goal, 'xp', c.xp, 'unlocked_at', ua.unlocked_at, 'seen', ua.seen_at is not null,
        'progress', case c.metric when 'matches' then mt.played when 'wins' then mt.wins when 'best_streak' then mt.best_streak
                                  when 'partners' then mt.partners when 'rivals' then mt.rivals
                                  else case when ua.id is not null then 1 else 0 end end) order by c.sort)
      from public.achievement_catalog c left join public.user_achievements ua on ua.achievement_id = c.id and ua.user_id = me),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('type', e.source_type, 'source', e.source_id, 'xp', e.xp, 'at', e.created_at)
        order by e.created_at desc), '[]'::jsonb) from (select * from public.xp_events where user_id = me order by created_at desc limit 30) e));
end $$;

create or replace function public.mark_achievements_seen() returns void
language sql security definer set search_path = public as $$
  update public.user_achievements set seen_at = now() where user_id = auth.uid() and seen_at is null
$$;

-- Periodos con Wrapped disponible: meses y años con al menos un partido del usuario.
create or replace function public.wrapped_periods() returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); tz text := public._g_tz(); cur_month date; cur_year date;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  perform public._g_close_periods();
  cur_month := date_trunc('month', now() at time zone tz)::date; cur_year := date_trunc('year', now() at time zone tz)::date;
  return jsonb_build_object(
    'months', (select coalesce(jsonb_agg(jsonb_build_object('start', m, 'played', n, 'in_progress', m = cur_month) order by m desc), '[]'::jsonb)
                 from (select date_trunc('month', played_at at time zone tz)::date m, count(*) n from public.player_match_stats
                        where user_id = me group by 1) x),
    'years', (select coalesce(jsonb_agg(jsonb_build_object('start', y, 'played', n, 'in_progress', y = cur_year) order by y desc), '[]'::jsonb)
                from (select date_trunc('year', played_at at time zone tz)::date y, count(*) n from public.player_match_stats
                       where user_id = me group by 1) x));
end $$;

-- Plobby Wrapped del usuario para un mes o un año. Solo con datos reales: las secciones sin datos llegan vacías (null)
-- y la app no las muestra.
create or replace function public.wrapped(p_kind text, p_start date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); tz text := public._g_tz(); ps date; pe date; pps date; fromt timestamptz; tot timestamptz;
        mt record; prv record; res jsonb;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if p_kind not in ('month', 'year') then raise exception 'invalid_period'; end if;
  ps := date_trunc(p_kind, p_start)::date;
  pe := (ps + case p_kind when 'month' then interval '1 month' else interval '1 year' end)::date;
  pps := (ps - case p_kind when 'month' then interval '1 month' else interval '1 year' end)::date;
  fromt := public._g_ts(ps); tot := public._g_ts(pe);
  select * into mt from public._g_metrics(me, fromt, tot);
  select * into prv from public._g_metrics(me, public._g_ts(pps), fromt);
  with s as (select * from public.player_match_stats where user_id = me and played_at >= fromt and played_at < tot)
  select jsonb_build_object(
    'kind', p_kind, 'start', ps, 'end', pe,
    'in_progress', now() < tot,
    'played', mt.played, 'wins', mt.wins, 'losses', mt.losses,
    'win_rate', case when mt.played > 0 then round(100.0 * mt.wins / mt.played) end,
    'sets_played', mt.sets_won + mt.sets_lost, 'sets_won', mt.sets_won, 'best_streak', mt.best_streak,
    'previous', jsonb_build_object('played', prv.played, 'wins', prv.wins,
                                   'win_rate', case when prv.played > 0 then round(100.0 * prv.wins / prv.played) end),
    -- actividad por mes (año) o por semana (mes) y por día de la semana (1 = lunes)
    'buckets', (select coalesce(jsonb_agg(jsonb_build_object('start', b, 'played', n, 'wins', w) order by b), '[]'::jsonb)
                  from (select date_trunc(case p_kind when 'month' then 'week' else 'month' end, played_at at time zone tz)::date b,
                               count(*) n, count(*) filter (where won) w from s group by 1) x),
    'weekdays', (select coalesce(jsonb_agg(jsonb_build_object('dow', d, 'played', n) order by n desc, d), '[]'::jsonb)
                   from (select extract(isodow from played_at at time zone tz)::int d, count(*) n from s group by 1) x),
    'top_partner', (select jsonb_build_object('user_id', partner_id, 'name', p.display_name, 'avatar_url', p.avatar_url, 'played', n, 'wins', w)
                      from (select partner_id, count(*) n, count(*) filter (where won) w from s where partner_id is not null
                             group by 1 order by 2 desc, 3 desc limit 1) x join public.profiles p on p.id = x.partner_id),
    'top_rival', (select jsonb_build_object('user_id', r, 'name', p.display_name, 'avatar_url', p.avatar_url, 'played', n, 'wins', w)
                    from (select r, count(*) n, count(*) filter (where won) w
                            from (select rival1_id r, won from s union all select rival2_id, won from s) y where r is not null
                           group by 1 order by 2 desc, 3 desc limit 1) x join public.profiles p on p.id = x.r),
    'best_rival', (select jsonb_build_object('user_id', r, 'name', p.display_name, 'avatar_url', p.avatar_url, 'played', n, 'wins', w)
                     from (select r, count(*) n, count(*) filter (where won) w
                             from (select rival1_id r, won from s union all select rival2_id, won from s) y where r is not null
                            group by 1 having count(*) >= 2 order by (count(*) filter (where won))::numeric / count(*) desc, 2 desc limit 1) x
                     join public.profiles p on p.id = x.r),
    'top_friend', (select jsonb_build_object('user_id', u, 'name', p.display_name, 'avatar_url', p.avatar_url, 'played', n)
                     from (select u, count(distinct match_id) n
                             from (select match_id, partner_id u from s union all select match_id, rival1_id from s union all select match_id, rival2_id from s) y
                            where u is not null and exists (select 1 from public.friendships f where f.user_id = me and f.friend_id = y.u and f.status = 'accepted')
                            group by 1 order by 2 desc limit 1) x join public.profiles p on p.id = x.u),
    -- partido más memorable: victoria más disputada (3 sets y más juegos); si no hay, la de más juegos
    'memorable', (select jsonb_build_object('match_id', s.match_id, 'played_at', s.played_at, 'games', s.games_won + s.games_lost,
                    'sets', (select jsonb_agg(jsonb_build_array(case when s.team = 1 then x.team1_games else x.team2_games end,
                                                                case when s.team = 1 then x.team2_games else x.team1_games end) order by x.set_no)
                             from public.match_sets x where x.match_id = s.match_id),
                    'partner', (select display_name from public.profiles where id = s.partner_id),
                    'rivals', (select jsonb_agg(display_name) from public.profiles where id in (s.rival1_id, s.rival2_id)))
                    from s where s.won order by (s.sets_won + s.sets_lost) desc, (s.games_won + s.games_lost) desc, s.played_at desc limit 1),
    'record', (select jsonb_build_object('elo', mx, 'previous_best', prevbest, 'is_record', prevbest is null or mx > prevbest)
                 from (select max(rating_before + delta) mx from public.rating_history where user_id = me and created_at >= fromt and created_at < tot) a,
                      (select max(rating_before + delta) prevbest from public.rating_history where user_id = me and created_at < fromt) b
                where mx is not null),
    'achievements', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'title', c.title, 'icon', c.icon, 'at', ua.unlocked_at) order by ua.unlocked_at), '[]'::jsonb)
                       from public.user_achievements ua join public.achievement_catalog c on c.id = ua.achievement_id
                      where ua.user_id = me and ua.unlocked_at >= fromt and ua.unlocked_at < tot),
    'name', (select display_name from public.profiles where id = me))
  into res;
  return res;
end $$;

-- ═══════════════════════════ 9. Permisos de las funciones ═══════════════════════════
do $$
declare f text;
begin
  foreach f in array array['_g_tz()', '_g_sync_match(uuid)', 'xp_for_level(int)', 'level_for_xp(int)', '_g_backfill()',
    '_g_notify(uuid,text,public.notification_type,text,text,text,uuid,uuid)', '_g_refresh_progress(uuid)',
    '_g_metrics(uuid,timestamptz,timestamptz)', '_g_grant(uuid,text)', '_g_revoke(uuid,text)', '_g_evaluate(uuid)',
    '_g_period(text,int)', '_g_ts(date)', '_g_ranking_rows(uuid,timestamptz,timestamptz,int)', '_g_rows_json(uuid,timestamptz,timestamptz,int)',
    '_g_close_periods()', '_g_rank_notifications(uuid)', '_g_after_match(uuid)', '_g_on_match_change()', '_g_on_sets_change()',
    '_g_on_tournament()', '_g_player_card(uuid)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['head_to_head(uuid)', 'friends_ranking(text,int)', 'my_season_titles()', 'my_achievements()',
    'mark_achievements_seen()', 'wrapped_periods()', 'wrapped(text,date)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
-- Las funciones internas que usa la RLS deben poder ejecutarse con el rol del usuario.
grant execute on function public.xp_for_level(int), public.level_for_xp(int) to authenticated;

-- ═══════════════════════════ 10. Carga histórica (sin avisos ni publicaciones) ═══════════════════════════
do $$
declare m uuid; t record;
begin
  perform set_config('plobby.backfill', 'on', true);
  for m in select id from public.matches where status = 'confirmed' loop
    perform public._g_sync_match(m);
    perform public._g_after_match(m);
  end loop;
  for t in select x.id, y.player1_id, y.player2_id from public.tournaments x join public.tournament_teams y on y.id = x.champion_team_id
            where x.status = 'finished' loop
    perform public._g_grant(t.player1_id, 'tournament_winner'); perform public._g_refresh_progress(t.player1_id);
    perform public._g_grant(t.player2_id, 'tournament_winner'); perform public._g_refresh_progress(t.player2_id);
  end loop;
  perform set_config('plobby.backfill', 'off', true);
end $$;
