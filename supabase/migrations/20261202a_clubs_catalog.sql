-- =====================================================================================================================
-- Plobby · Catálogo de clubes y «club base» (2 dic 2026)
--   · clubs: slug, municipio, zona, área, CP, tipo, estado (verified/pending/rejected/merged), fusión, origen, autor,
--     contador de jugadores y estado de geocodificación. Nombre normalizado (columnas generadas) + índices trigram.
--   · club_aliases: otros nombres de cada club.
--   · normalize_club_name(text): minúsculas, sin tildes ni signos, padel/pádel/paddle unificados, sin palabras vacías.
--   · search_clubs(...): reconocimiento por nombre y alias (exacto, prefijo, todas las palabras, trigram) + cercanía y
--     popularidad. SECURITY INVOKER: respeta RLS (verificados + mis propuestas).
--   · propose_club(...): propuesta de club nuevo (pending) con aviso de duplicado probable. Límite: 5 al día.
--   · profiles.home_club_id / habitual_club_id: FK a clubs; el texto antiguo se mantiene sincronizado (apps viejas).
--   · Administración (solo cuentas con app_metadata.plobby_admin = true): aprobar, rechazar, fusionar, añadir alias.
--     Todo queda en audit_log.
-- No borra datos. Privilegios por defecto revocados (20261128a): todos los grant son explícitos.
-- =====================================================================================================================

create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- ───────────────────────────── Normalización ─────────────────────────────
create or replace function public.normalize_club_name(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select nullif(btrim(regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p, ''))), '[^a-z0-9]+', ' ', 'g'),
               '\m(paddle|padle|padel)\M', 'padel', 'g'),
             '\m(club|de|del|la|las|el|los|y|e|centro|deportivo|deportiva|sport|sports|cd|cde|cdm|real)\M', ' ', 'g'),
           '\s+', ' ', 'g')), '');
$$;
grant execute on function public.normalize_club_name(text) to authenticated;

create or replace function private.slugify(p text) returns text
language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p, ''))), '[^a-z0-9]+', '-', 'g'), '-');
$$;
revoke all on function private.slugify(text) from public, anon, authenticated;

-- ───────────────────────────── clubs ─────────────────────────────
alter table public.clubs
  add column if not exists slug text,
  add column if not exists municipality text check (municipality is null or char_length(municipality) <= 80),
  add column if not exists zone text check (zone in ('madrid_capital', 'norte', 'oeste', 'sur', 'este')),
  add column if not exists area text check (area is null or char_length(area) <= 80),
  add column if not exists postal_code text check (postal_code is null or postal_code ~ '^[0-9]{5}$'),
  add column if not exists type text not null default 'private_club'
    check (type in ('private_club', 'social_club', 'municipal', 'public_regional', 'federation', 'gym', 'university', 'school')),
  add column if not exists status text not null default 'pending' check (status in ('verified', 'pending', 'rejected', 'merged')),
  add column if not exists merged_into uuid references public.clubs (id) on delete set null,
  add column if not exists created_by uuid references public.profiles (id) on delete set null,
  add column if not exists source text not null default 'user' check (char_length(source) <= 40),
  add column if not exists players_count integer not null default 0,
  add column if not exists geocode_status text not null default 'pending' check (geocode_status in ('pending', 'ok', 'failed', 'manual')),
  add column if not exists updated_at timestamptz not null default now();
alter table public.clubs add column if not exists name_normalized text generated always as (public.normalize_club_name(name)) stored;
alter table public.clubs add column if not exists name_compact text generated always as (replace(coalesce(public.normalize_club_name(name), ''), ' ', '')) stored;
alter table public.clubs add column if not exists search_doc text
  generated always as (public.normalize_club_name(name || ' ' || coalesce(area, '') || ' ' || coalesce(municipality, ''))) stored;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clubs_name_len') then
    alter table public.clubs add constraint clubs_name_len check (char_length(btrim(name)) between 2 and 120);
    alter table public.clubs add constraint clubs_address_len check (address is null or char_length(address) <= 200);
    alter table public.clubs add constraint clubs_merged_target check ((status = 'merged') = (merged_into is not null) and merged_into is distinct from id);
  end if;
end $$;
update public.clubs set slug = private.slugify(name) || '-' || left(id::text, 6) where slug is null;   -- (la tabla estaba vacía)
alter table public.clubs alter column slug set not null;
create unique index if not exists clubs_slug_key on public.clubs (slug);
create index if not exists clubs_name_trgm on public.clubs using gin (name_normalized extensions.gin_trgm_ops);
create index if not exists clubs_doc_trgm on public.clubs using gin (search_doc extensions.gin_trgm_ops);
create index if not exists clubs_compact_idx on public.clubs (name_compact text_pattern_ops);
create index if not exists clubs_name_prefix_idx on public.clubs (name_normalized text_pattern_ops);
create index if not exists clubs_status_idx on public.clubs (status, type);
create index if not exists clubs_created_by_idx on public.clubs (created_by) where created_by is not null;
create index if not exists clubs_merged_into_idx on public.clubs (merged_into) where merged_into is not null;

-- ───────────────────────────── club_aliases ─────────────────────────────
create table if not exists public.club_aliases (
  id bigint generated always as identity primary key,
  club_id uuid not null references public.clubs (id) on delete cascade,
  alias text not null check (char_length(btrim(alias)) between 2 and 120),
  alias_normalized text generated always as (public.normalize_club_name(alias)) stored,
  alias_compact text generated always as (replace(coalesce(public.normalize_club_name(alias), ''), ' ', '')) stored,
  source text not null default 'seed' check (char_length(source) <= 40),
  created_at timestamptz not null default now()
);
create unique index if not exists club_aliases_unique on public.club_aliases (club_id, alias_normalized);
create index if not exists club_aliases_trgm on public.club_aliases using gin (alias_normalized extensions.gin_trgm_ops);
create index if not exists club_aliases_compact_idx on public.club_aliases (alias_compact text_pattern_ops);
create index if not exists club_aliases_prefix_idx on public.club_aliases (alias_normalized text_pattern_ops);

-- ───────────────────────────── RLS ─────────────────────────────
alter table public.clubs enable row level security;
alter table public.club_aliases enable row level security;
drop policy if exists clubs_read on public.clubs;
drop policy if exists clubs_read_visible on public.clubs;
create policy clubs_read_visible on public.clubs for select to authenticated
  using (status = 'verified' or (status = 'pending' and created_by = (select auth.uid())));
drop policy if exists clubs_propose on public.clubs;
create policy clubs_propose on public.clubs for insert to authenticated
  with check (status = 'pending' and created_by = (select auth.uid()) and source = 'user' and merged_into is null);
-- sin políticas de UPDATE/DELETE: solo funciones del servidor (administración)
drop policy if exists club_aliases_read on public.club_aliases;
create policy club_aliases_read on public.club_aliases for select to authenticated
  using (exists (select 1 from public.clubs c where c.id = club_id));   -- la RLS de clubs se aplica dentro

revoke all on public.clubs from anon, authenticated;
revoke all on public.club_aliases from anon, authenticated;
grant select on public.clubs to authenticated;
grant insert (name, municipality, zone, area, address, postal_code, type) on public.clubs to authenticated;
grant select on public.club_aliases to authenticated;

-- Al insertar: slug único, campos controlados por el servidor y límite de propuestas (5 cada 24 h por usuario).
create or replace function private.clubs_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); base text; n int := 1;
begin
  new.name := btrim(regexp_replace(new.name, '\s+', ' ', 'g'));
  new.municipality := nullif(btrim(new.municipality), '');
  new.address := nullif(btrim(new.address), '');
  if me is not null then   -- propuesta de un usuario (las cargas y la administración van sin sesión o por funciones)
    if (select count(*) from public.clubs where created_by = me and created_at > now() - interval '1 day') >= 5 then
      raise exception 'rate_limited';
    end if;
    new.status := 'pending'; new.created_by := me; new.source := 'user'; new.merged_into := null;
    new.players_count := 0; new.geocode_status := 'pending'; new.lat := null; new.lng := null;
    new.slug := null;
  end if;
  if new.slug is null then
    base := private.slugify(new.name || coalesce('-' || new.municipality, ''));
    new.slug := base;
    while exists (select 1 from public.clubs where slug = new.slug) loop n := n + 1; new.slug := base || '-' || n; end loop;
  end if;
  new.city := coalesce(new.city, new.municipality);
  new.updated_at := now();
  return new;
end $$;
revoke all on function private.clubs_before_insert() from public, anon, authenticated;
drop trigger if exists clubs_before_insert on public.clubs;
create trigger clubs_before_insert before insert on public.clubs for each row execute function private.clubs_before_insert();

-- ───────────────────────────── profiles: club base ─────────────────────────────
alter table public.profiles
  add column if not exists home_club_id uuid references public.clubs (id) on delete set null,
  add column if not exists habitual_club_id uuid references public.clubs (id) on delete set null;
create index if not exists profiles_home_club_idx on public.profiles (home_club_id) where home_club_id is not null;
create index if not exists profiles_habitual_club_idx on public.profiles (habitual_club_id) where habitual_club_id is not null;
grant update (home_club_id, habitual_club_id) on public.profiles to authenticated;

-- Solo clubes que el usuario puede usar (verificados o su propia propuesta); un club fusionado se sustituye por el
-- definitivo; el texto antiguo (home_club / habitual_club) se rellena con el nombre para versiones antiguas de la app.
create or replace function private.profiles_club_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); c record;
begin
  if new.home_club_id is not null and (tg_op = 'INSERT' or new.home_club_id is distinct from old.home_club_id) then
    select id, name, status, merged_into, created_by into c from public.clubs where id = new.home_club_id;
    if c.status = 'merged' then select id, name, status, merged_into, created_by into c from public.clubs where id = c.merged_into; end if;
    if c.id is null or not (c.status = 'verified' or (c.status = 'pending' and (me is null or c.created_by = me)) or me is null) then
      raise exception 'club_not_available';
    end if;
    new.home_club_id := c.id; new.home_club := c.name;
  end if;
  if new.habitual_club_id is not null and (tg_op = 'INSERT' or new.habitual_club_id is distinct from old.habitual_club_id) then
    select id, name, status, merged_into, created_by into c from public.clubs where id = new.habitual_club_id;
    if c.status = 'merged' then select id, name, status, merged_into, created_by into c from public.clubs where id = c.merged_into; end if;
    if c.id is null or not (c.status = 'verified' or (c.status = 'pending' and (me is null or c.created_by = me)) or me is null) then
      raise exception 'club_not_available';
    end if;
    new.habitual_club_id := c.id; new.habitual_club := c.name;
  end if;
  return new;
end $$;
revoke all on function private.profiles_club_guard() from public, anon, authenticated;
drop trigger if exists profiles_club_guard on public.profiles;
create trigger profiles_club_guard before insert or update of home_club_id, habitual_club_id on public.profiles
  for each row execute function private.profiles_club_guard();

-- Popularidad: nº de jugadores con ese club base (se usa en la búsqueda y en la página del club)
create or replace function private.profiles_club_count() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and old.home_club_id is not null and (tg_op = 'DELETE' or old.home_club_id is distinct from new.home_club_id) then
    update public.clubs set players_count = greatest(players_count - 1, 0) where id = old.home_club_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.home_club_id is not null and (tg_op = 'INSERT' or old.home_club_id is distinct from new.home_club_id) then
    update public.clubs set players_count = players_count + 1 where id = new.home_club_id;
  end if;
  return null;
end $$;
revoke all on function private.profiles_club_count() from public, anon, authenticated;
drop trigger if exists profiles_club_count on public.profiles;
create trigger profiles_club_count after insert or delete or update of home_club_id on public.profiles
  for each row execute function private.profiles_club_count();

-- ───────────────────────────── Búsqueda ─────────────────────────────
-- Candidatos usando los índices trigram/prefijo. Va aparte (SECURITY DEFINER, esquema private no expuesto) porque con
-- RLS Postgres no puede usar esos índices antes de aplicar la política (los operadores de pg_trgm no son «leakproof») y
-- recorría la tabla entera (≈ 60 ms con 10.000 clubes). Solo devuelve ids: search_clubs (SECURITY INVOKER) lee después
-- los clubes con la RLS del usuario, así que nadie ve un club que no debería.
create or replace function private.club_candidates(nq text, cq text) returns table (club_id uuid, alias_id bigint)
language plpgsql stable security definer
set search_path = pg_catalog, extensions, public
set enable_seqscan = off      -- solo en esta función: siempre por índice (el planificador dudaba y recorría la tabla)
set pg_trgm.similarity_threshold = 0.3
set pg_trgm.word_similarity_threshold = 0.5
as $$
begin
  -- SQL dinámico con los valores literales: así el planificador sabe que «like 'texto%'» es un prefijo y usa el índice
  return query execute format($q$
    select x.id, null::bigint from public.clubs x where x.name_normalized %% %1$L
    union select x.id, null from public.clubs x where x.search_doc %%> %1$L
    union select x.id, null from public.clubs x where x.name_normalized like %3$L
    union select x.id, null from public.clubs x where x.name_compact like %4$L
    union select x.club_id, x.id from public.club_aliases x where x.alias_normalized %% %1$L
    union select x.club_id, x.id from public.club_aliases x where x.alias_normalized %%> %1$L
    union select x.club_id, x.id from public.club_aliases x where x.alias_normalized like %3$L
    union select x.club_id, x.id from public.club_aliases x where x.alias_compact like %4$L
    limit 2000 $q$, nq, cq, replace(replace(nq, '%', ''), '_', '') || '%', replace(replace(cq, '%', ''), '_', '') || '%');
end $$;
revoke all on function private.club_candidates(text, text) from public, anon;
grant execute on function private.club_candidates(text, text) to authenticated;

-- Puntuación léxica: exacto 1,0 · prefijo 0,85 · todas las palabras (nombre, alias, barrio o municipio) 0,75 ·
-- parecido trigram hasta 0,7. Bonus: cercanía (hasta +0,15, si llegan lat/lng y el club está geocodificado) y
-- popularidad (hasta +0,1). confident = el primero es claro (≥ 0,9 y le saca ≥ 0,2 al segundo): la app solo sugiere
-- «¿Te refieres a…?» en ese caso.
create or replace function public.search_clubs(q text, lat double precision default null, lng double precision default null,
                                               types text[] default null, "limit" integer default 8)
returns table (id uuid, name text, municipality text, zone text, type text, status text, matched_alias text, score real, confident boolean)
language plpgsql stable security invoker
set search_path = pg_catalog, extensions, public
set pg_trgm.similarity_threshold = 0.3
set pg_trgm.word_similarity_threshold = 0.5
as $$
declare nq text := public.normalize_club_name(left(q, 120)); cq text; lim int := least(greatest(coalesce("limit", 8), 1), 30);
begin
  if nq is null or char_length(nq) < 2 then return; end if;
  cq := replace(nq, ' ', '');
  return query
  with words as (select array_agg(w) ws from unnest(string_to_array(nq, ' ')) w),
  -- candidatos por índice (función auxiliar, solo devuelve ids); la RLS del usuario se aplica después, al leer los clubes
  cc as materialized (select * from private.club_candidates(nq, cq)),
  cand as (select x.club_id id from cc x where x.alias_id is null),
  acand as (select x.alias_id id from cc x where x.alias_id is not null),
  hits as (
    select c.id cid, null::text alias, c.name_normalized n, c.name_compact k, c.search_doc d
      from cand join public.clubs c on c.id = cand.id
     where c.status in ('verified', 'pending') and (types is null or c.type = any (types))
    union all
    select a.club_id, a.alias, a.alias_normalized, a.alias_compact, a.alias_normalized || ' ' || coalesce(c.search_doc, '')
      from acand join public.club_aliases a on a.id = acand.id join public.clubs c on c.id = a.club_id
     where c.status in ('verified', 'pending') and (types is null or c.type = any (types))
  ),
  scored as (
    select h.cid, h.alias,
           greatest(
             case when h.n = nq or h.k = cq then 1.0
                  when h.n like nq || '%' or h.k like cq || '%' then 0.85
                  when (select bool_and(position(' ' || w || ' ' in ' ' || h.d || ' ') > 0) from words, unnest(words.ws) w) then 0.75
                  else 0 end,
             0.7 * greatest(similarity(h.n, nq), word_similarity(nq, h.d))
           )::real s
      from hits h
  ),
  best as (
    select distinct on (s.cid) s.cid, s.alias, s.s from scored s order by s.cid, s.s desc, (s.alias is null) desc
  ),
  ranked as (
    select c.id, c.name, c.municipality, c.zone, c.type, c.status, b.alias,
           (b.s
            + least(0.1, ln(1 + c.players_count) / 50)
            + case when search_clubs.lat is not null and search_clubs.lng is not null and c.lat is not null and c.lng is not null
                   then 0.15 * exp(-(2 * 6371 * asin(sqrt(power(sin(radians(c.lat - search_clubs.lat) / 2), 2)
                        + cos(radians(search_clubs.lat)) * cos(radians(c.lat)) * power(sin(radians(c.lng - search_clubs.lng) / 2), 2)))) / 10)
                   else 0 end)::real total,
           b.s lex, c.players_count
      from best b join public.clubs c on c.id = b.cid
     where b.s >= 0.3
  ),
  ordered as (
    select r.*, row_number() over (order by r.total desc, r.players_count desc, r.name) rn,
           lead(r.total) over (order by r.total desc, r.players_count desc, r.name) next_total
      from ranked r
  )
  select o.id, o.name, o.municipality, o.zone, o.type, o.status, o.alias, round(o.total::numeric, 3)::real,
         (o.rn = 1 and o.lex >= 0.9 and (o.next_total is null or o.total - o.next_total >= 0.2))
    from ordered o
   where o.rn <= lim
   order by o.rn;
end $$;
revoke all on function public.search_clubs(text, double precision, double precision, text[], integer) from public, anon;
grant execute on function public.search_clubs(text, double precision, double precision, text[], integer) to authenticated;

-- Clubes cerca de una posición (sección «Clubes cerca de ti»): solo los geocodificados.
create or replace function public.nearby_clubs(lat double precision, lng double precision, "limit" integer default 8)
returns table (id uuid, name text, municipality text, zone text, type text, distance_km real)
language sql stable security invoker set search_path = pg_catalog, public as $$
  select c.id, c.name, c.municipality, c.zone, c.type,
         round((2 * 6371 * asin(sqrt(power(sin(radians(c.lat - nearby_clubs.lat) / 2), 2)
              + cos(radians(nearby_clubs.lat)) * cos(radians(c.lat)) * power(sin(radians(c.lng - nearby_clubs.lng) / 2), 2))))::numeric, 1)::real d
    from public.clubs c
   where c.status = 'verified' and c.lat is not null and c.lng is not null
     and c.lat between nearby_clubs.lat - 0.5 and nearby_clubs.lat + 0.5 and c.lng between nearby_clubs.lng - 0.7 and nearby_clubs.lng + 0.7
   order by d, c.players_count desc
   limit least(greatest(coalesce("limit", 8), 1), 30);
$$;
revoke all on function public.nearby_clubs(double precision, double precision, integer) from public, anon;
grant execute on function public.nearby_clubs(double precision, double precision, integer) to authenticated;

-- ───────────────────────────── Propuestas ─────────────────────────────
-- Sin p_force: si hay un club muy parecido devuelve {status:'duplicates', candidates:[…]} para que la app avise.
create or replace function public.propose_club(p_name text, p_municipality text, p_type text default 'private_club',
                                               p_address text default null, p_force boolean default false)
returns jsonb language plpgsql security invoker set search_path = pg_catalog, public as $$
declare d jsonb; new_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_name, ''))) < 3 or char_length(btrim(coalesce(p_municipality, ''))) < 2 then raise exception 'invalid_club'; end if;
  if not coalesce(p_force, false) then
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'municipality', s.municipality, 'type', s.type, 'score', s.score))
      into d from public.search_clubs(p_name || ' ' || p_municipality, null, null, null, 5) s where s.score >= 0.7;
    if d is null then
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'municipality', s.municipality, 'type', s.type, 'score', s.score))
        into d from public.search_clubs(p_name, null, null, null, 5) s where s.score >= 0.85;
    end if;
    if d is not null then return jsonb_build_object('status', 'duplicates', 'candidates', d); end if;
  end if;
  insert into public.clubs (name, municipality, type, address)
    values (p_name, p_municipality, coalesce(nullif(p_type, ''), 'private_club'), p_address)
    returning clubs.id into new_id;
  return jsonb_build_object('status', 'created', 'id', new_id);
end $$;
revoke all on function public.propose_club(text, text, text, text, boolean) from public, anon;
grant execute on function public.propose_club(text, text, text, text, boolean) to authenticated;

-- ───────────────────────────── Administración ─────────────────────────────
-- Administrador = cuenta con raw_app_meta_data.plobby_admin = true (solo se puede poner con la service_role / SQL).
create or replace function private.is_platform_admin() returns boolean
language sql stable set search_path = '' as $$
  select coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'plobby_admin')::boolean, false);
$$;
revoke all on function private.is_platform_admin() from public, anon;
grant execute on function private.is_platform_admin() to authenticated;

create or replace function public.admin_pending_clubs() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_platform_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'municipality', c.municipality, 'type', c.type,
           'address', c.address, 'created_at', c.created_at, 'created_by', c.created_by,
           'creator', (select p.display_name from public.profiles p where p.id = c.created_by),
           'players', (select count(*) from public.profiles p where p.home_club_id = c.id or p.habitual_club_id = c.id),
           'similar', (select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'municipality', o.municipality))
                         from (select o.id, o.name, o.municipality from public.clubs o
                                where o.status = 'verified' and extensions.similarity(o.name_normalized, c.name_normalized) >= 0.4
                                order by extensions.similarity(o.name_normalized, c.name_normalized) desc limit 3) o))
           order by c.created_at) from public.clubs c where c.status = 'pending'), '[]'::jsonb);
end $$;
revoke all on function public.admin_pending_clubs() from public, anon;
grant execute on function public.admin_pending_clubs() to authenticated;

-- p_action: 'approve' | 'reject' | 'merge' (con p_target). Al fusionar se reasignan perfiles, partidos, ligas y pistas,
-- los alias pasan al club definitivo (y el nombre del fusionado queda como alias) y se recuentan los jugadores.
create or replace function public.admin_review_club(p_club uuid, p_action text, p_target uuid default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.clubs; t public.clubs;
begin
  if not private.is_platform_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into c from public.clubs where id = p_club for update;
  if not found then raise exception 'not_found'; end if;
  if p_action = 'approve' then
    update public.clubs set status = 'verified', updated_at = now() where id = p_club;
  elsif p_action = 'reject' then
    update public.clubs set status = 'rejected', updated_at = now() where id = p_club;
    update public.profiles set home_club_id = null where home_club_id = p_club;          -- el texto se conserva
    update public.profiles set habitual_club_id = null where habitual_club_id = p_club;
  elsif p_action = 'merge' then
    select * into t from public.clubs where id = p_target for update;
    if not found or t.id = c.id or t.status <> 'verified' then raise exception 'invalid_target'; end if;
    update public.profiles set home_club_id = t.id where home_club_id = c.id;
    update public.profiles set habitual_club_id = t.id where habitual_club_id = c.id;
    update public.matches set club_id = t.id where club_id = c.id;
    update public.leagues set club_id = t.id where club_id = c.id;
    update public.courts set club_id = t.id where club_id = c.id;
    insert into public.club_aliases (club_id, alias, source) select t.id, a.alias, 'merge' from public.club_aliases a where a.club_id = c.id
      on conflict (club_id, alias_normalized) do nothing;
    delete from public.club_aliases where club_id = c.id;
    if c.name_normalized is distinct from t.name_normalized then
      insert into public.club_aliases (club_id, alias, source) values (t.id, c.name, 'merge') on conflict (club_id, alias_normalized) do nothing;
    end if;
    update public.clubs set status = 'merged', merged_into = t.id, updated_at = now() where id = c.id;
    update public.clubs x set players_count = (select count(*) from public.profiles p where p.home_club_id = x.id) where x.id in (c.id, t.id);
  else raise exception 'invalid_action';
  end if;
  perform private.audit((select auth.uid()), 'admin_action',
    jsonb_build_object('op', 'club_' || p_action, 'club_id', c.id, 'club', c.name, 'target_id', p_target, 'note', left(p_note, 300)));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_review_club(uuid, text, uuid, text) from public, anon;
grant execute on function public.admin_review_club(uuid, text, uuid, text) to authenticated;

create or replace function public.admin_add_club_alias(p_club uuid, p_alias text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_platform_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  insert into public.club_aliases (club_id, alias, source) values (p_club, btrim(p_alias), 'admin') on conflict (club_id, alias_normalized) do nothing;
  perform private.audit((select auth.uid()), 'admin_action', jsonb_build_object('op', 'club_alias_added', 'club_id', p_club, 'alias', left(p_alias, 120)));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_add_club_alias(uuid, text) from public, anon;
grant execute on function public.admin_add_club_alias(uuid, text) to authenticated;

-- ───────────────────────────── Página del club ─────────────────────────────
-- Jugadores con ese club base (solo los datos públicos mínimos: nombre, usuario, foto, nivel y ELO), ligas visibles
-- del club y ranking por ELO entre esos jugadores. Solo para clubes que el usuario puede ver.
create or replace function public.club_page(p_club uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); c public.clubs;
begin
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into c from public.clubs where id = p_club;
  if c.status = 'merged' then select * into c from public.clubs where id = c.merged_into; end if;
  if c.id is null or not (c.status = 'verified' or (c.status = 'pending' and c.created_by = me)) then return null; end if;
  return jsonb_build_object(
    'club', jsonb_build_object('id', c.id, 'name', c.name, 'municipality', c.municipality, 'zone', c.zone, 'area', c.area,
                               'address', c.address, 'postal_code', c.postal_code, 'type', c.type, 'status', c.status,
                               'players_count', c.players_count, 'lat', c.lat, 'lng', c.lng,
                               'aliases', (select coalesce(jsonb_agg(a.alias order by a.alias), '[]') from public.club_aliases a where a.club_id = c.id)),
    'ranking', (select coalesce(jsonb_agg(x order by x.elo desc nulls last, x.name), '[]') from (
        select p.id, p.display_name as name, p.username, p.avatar_url, p.self_declared_level as level, r.elo
          from public.profiles p left join public.player_ratings r on r.user_id = p.id
         where p.home_club_id = c.id and p.deleted_at is null and p.onboarding_completed_at is not null
         order by r.elo desc nulls last limit 50) x),
    'leagues', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name)), '[]')
                  from public.leagues l where l.club_id = c.id and private.can_view_league(l.id)));
end $$;
revoke all on function public.club_page(uuid) from public, anon;
grant execute on function public.club_page(uuid) to authenticated;
