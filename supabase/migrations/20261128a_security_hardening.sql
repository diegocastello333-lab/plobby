-- =====================================================================================================================
-- Plobby · Seguridad Fase 1a (22 nov 2026). Endurecimiento SIN romper versiones anteriores de la app.
-- Ver docs/seguridad/fase0_auditoria.md y docs/seguridad/fase1_base_de_datos.md.
--
--  1. Esquema `private` (NO expuesto por la API REST): funciones auxiliares de RLS con search_path = '' y nombres
--     totalmente cualificados. Las políticas pasan a usarlas. Las versiones de `public` quedan como envoltorios que
--     solo puede ejecutar el propietario (las RPC SECURITY DEFINER las siguen llamando), así nadie puede usarlas por
--     /rest/v1/rpc para sondear relaciones de otros usuarios.
--  2. search_path fijo y con pg_temp al final en TODAS las funciones de `public` (ver nota en el informe sobre '').
--  3. Permisos mínimos: se revoca todo a anon/authenticated (incluido TRUNCATE, REFERENCES, TRIGGER) y se concede
--     solo lo que la app usa. Por defecto, los objetos nuevos NO dan permisos a anon/authenticated.
--  4. Políticas SELECT duplicadas fusionadas (matches, match_players, match_sets).
--  5. Restricciones de servidor (longitudes) y validación de las que estaban NOT VALID.
--  6. Tabla `audit_log` + triggers en auth.users (alta, inicio de sesión, cambio de email/contraseña, borrado).
--  7. RPC `get_profile(uuid)`: perfil ajeno según relación (base para la Fase 1b, que limita columnas).
-- Idempotente en lo posible. No borra datos.
-- =====================================================================================================================

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Esquema privado y auxiliares de RLS
-- ---------------------------------------------------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;   -- necesario para evaluar políticas; el esquema no está expuesto

create or replace function private.is_member(conv uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.conversation_members where conversation_id = conv and user_id = (select auth.uid()));
$$;

create or replace function private.is_group_admin(conv uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.conversation_members m join public.conversations c on c.id = m.conversation_id
                  where m.conversation_id = conv and m.user_id = (select auth.uid()) and m.role = 'admin' and c.kind = 'group');
$$;

create or replace function private.can_view_user(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select target = (select auth.uid())
      or exists (select 1 from public.friendships f where f.user_id = (select auth.uid()) and f.friend_id = target and f.status = 'accepted');
$$;

create or replace function private.can_view_post(pid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.feed_posts p where p.id = pid and private.can_view_user(p.user_id));
$$;

create or replace function private.is_league_member(p_league uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.league_members where league_id = p_league and user_id = (select auth.uid()))
      or exists (select 1 from public.leagues where id = p_league and created_by = (select auth.uid()));
$$;

create or replace function private.is_league_manager(p_league uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.league_members where league_id = p_league and user_id = (select auth.uid())
                  and role in ('organizer', 'admin'));
$$;

create or replace function private.can_view_league(p_league uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_league_member(p_league)
      or exists (select 1 from public.leagues l where l.id = p_league and l.visibility in ('public', 'club'))
      or exists (select 1 from public.league_invites i where i.league_id = p_league and i.user_id = (select auth.uid()));
$$;

create or replace function private.can_view_league_match(p_match uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.matches m where m.id = p_match and m.match_type = 'league'
                  and m.league_id is not null and private.is_league_member(m.league_id));
$$;

-- solo para el usuario de la sesión (la versión pública aceptaba cualquier usuario como 2º parámetro)
create or replace function private.is_participant(p_match uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.match_players where match_id = p_match and user_id = (select auth.uid()));
$$;

create or replace function private.t_is_admin(p_t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.tournament_admins where tournament_id = p_t and user_id = (select auth.uid()));
$$;

create or replace function private.t_can_view(p_t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.t_is_admin(p_t)
      or exists (select 1 from public.tournament_players where tournament_id = p_t and user_id = (select auth.uid()));
$$;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- Políticas → auxiliares privados (misma lógica)
alter policy conv_select on public.conversations using (private.is_member(id));
alter policy cm_select on public.conversation_members using (private.is_member(conversation_id));
alter policy msg_select on public.messages using (private.is_member(conversation_id));
alter policy feed_posts_select on public.feed_posts using (private.can_view_user(user_id));
alter policy reactions_select on public.reactions using (private.can_view_post(post_id));
alter policy reactions_insert on public.reactions with check ((user_id = (select auth.uid())) and private.can_view_post(post_id));
alter policy comments_select on public.comments using (private.can_view_post(post_id) and ((not hidden) or (user_id = (select auth.uid()))));
alter policy comments_insert on public.comments with check ((user_id = (select auth.uid())) and private.can_view_post(post_id));
alter policy leagues_read on public.leagues using (private.can_view_league(id));
alter policy league_members_read on public.league_members using (private.can_view_league(league_id));
alter policy league_invites_read on public.league_invites using ((user_id = (select auth.uid())) or private.is_league_manager(league_id));
alter policy league_join_requests_read on public.league_join_requests using ((user_id = (select auth.uid())) or private.is_league_manager(league_id));
alter policy t_select on public.tournaments using (private.t_can_view(id));
alter policy ta_select on public.tournament_admins using (private.t_can_view(tournament_id));
alter policy tt_select on public.tournament_teams using (private.t_can_view(tournament_id));
alter policy tp_select on public.tournament_players using (private.t_can_view(tournament_id));
alter policy tm_select on public.tournament_matches using (private.t_can_view(tournament_id));
alter policy pr_read on public.player_ratings using ((user_id = (select auth.uid())) or private.can_view_user(user_id));
alter policy user_achievements_read on public.user_achievements using ((user_id = (select auth.uid())) or private.can_view_user(user_id));
alter policy pms_read on public.player_match_stats using ((user_id = (select auth.uid())) or private.can_view_user(user_id));
alter policy player_progress_read on public.player_progress using ((user_id = (select auth.uid())) or private.can_view_user(user_id));
alter policy mrv_read on public.match_result_versions using (private.is_participant(match_id));
alter policy mra_read on public.match_result_acceptances using (private.is_participant(match_id));
alter policy mev_read on public.match_events using (private.is_participant(match_id));

-- 4. Una sola política SELECT por tabla (antes dos permisivas: participantes + liga)
drop policy if exists matches_read_league on public.matches;
drop policy if exists match_players_read_league on public.match_players;
drop policy if exists match_sets_read_league on public.match_sets;
alter policy matches_read_participants on public.matches
  using (private.is_participant(id) or (match_type = 'league' and league_id is not null and private.is_league_member(league_id)));
alter policy match_players_read on public.match_players using (private.is_participant(match_id) or private.can_view_league_match(match_id));
alter policy match_sets_read on public.match_sets using (private.is_participant(match_id) or private.can_view_league_match(match_id));

-- Storage: avatares de grupo
alter policy ga_read on storage.objects using ((bucket_id = 'group-avatars') and private.is_member((split_part(name, '/', 1))::uuid));
alter policy ga_write on storage.objects with check ((bucket_id = 'group-avatars') and private.is_group_admin((split_part(name, '/', 1))::uuid));
alter policy ga_upd on storage.objects using ((bucket_id = 'group-avatars') and private.is_group_admin((split_part(name, '/', 1))::uuid));

-- Las auxiliares públicas pasan a ser envoltorios de las privadas (una sola lógica) y dejan de ser invocables por RPC.
create or replace function public.is_member(conv uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.is_member(conv) $$;
create or replace function public.is_group_admin(conv uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.is_group_admin(conv) $$;
create or replace function public.can_view_user(target uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.can_view_user(target) $$;
create or replace function public.can_view_post(pid uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.can_view_post(pid) $$;
create or replace function public.is_league_member(p_league uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.is_league_member(p_league) $$;
create or replace function public.is_league_manager(p_league uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.is_league_manager(p_league) $$;
create or replace function public.can_view_league(p_league uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.can_view_league(p_league) $$;
create or replace function public._can_view_league_match(p_match uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.can_view_league_match(p_match) $$;
create or replace function public._t_is_admin(p_t uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.t_is_admin(p_t) $$;
create or replace function public._t_can_view(p_t uuid) returns boolean language sql stable security definer set search_path = '' as $$ select private.t_can_view(p_t) $$;
-- _is_participant(match, user) se usa en RPC internas con usuarios concretos: se mantiene, pero no invocable.
revoke execute on function public.is_member(uuid), public.is_group_admin(uuid), public.can_view_user(uuid), public.can_view_post(uuid),
  public.is_league_member(uuid), public.is_league_manager(uuid), public.can_view_league(uuid), public._can_view_league_match(uuid),
  public._t_is_admin(uuid), public._t_can_view(uuid), public._is_participant(uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. search_path fijo en todas las funciones de public (pg_temp al final: no se puede suplantar con objetos temporales).
--    Las que ya tienen '' (las de arriba) se respetan.
-- ---------------------------------------------------------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind in ('f', 'p')
      and not coalesce('search_path=""' = any(p.proconfig), false)
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('alter function %s set search_path = pg_catalog, public, pg_temp', f.sig);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Permisos mínimos
-- ---------------------------------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select c.oid::regclass as t, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p')
  loop
    execute format('revoke all on table %s from anon, authenticated', r.t);
    if r.relname not in ('profiles', 'audit_log') then
      execute format('grant select on table %s to authenticated', r.t);
    end if;
  end loop;
end $$;
revoke all on all sequences in schema public from anon, authenticated;

-- Lectura de perfiles: mismas columnas que antes (nombre, apellidos y fecha de nacimiento NO). Fase 1b las reduce.
grant select (id, display_name, username, avatar_url, avatar_id, self_declared_level, city, home_club, habitual_club, bio,
              court_side, dominant_hand, habitual_partner_id, banner_id, banner_url, created_at, updated_at)
  on public.profiles to authenticated;
-- Escrituras directas que usa la app (todas protegidas además por RLS con WITH CHECK)
grant update (display_name, avatar_url, avatar_id, bio, city, court_side, dominant_hand, habitual_club, updated_at) on public.profiles to authenticated;
grant insert (post_id, user_id, content), update (content, updated_at), delete on public.comments to authenticated;
grant insert (post_id, user_id, reaction_type), update (reaction_type), delete on public.reactions to authenticated;
grant update (is_read) on public.notifications to authenticated;
grant insert (user_id, ranking, achievements, levels, wrapped, updated_at),
      update (user_id, ranking, achievements, levels, wrapped, updated_at) on public.notification_prefs to authenticated;
grant insert (comment_id, reporter_id) on public.comment_reports to authenticated;

-- Funciones: nada para anon; authenticated conserva solo lo que ya tenía (las RPC de la app).
revoke execute on all functions in schema public from public, anon;

-- Por defecto, lo que se cree a partir de ahora (por este rol) NO da permisos a nadie: hay que concederlos explícitamente.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema private revoke execute on functions from public, anon;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Validación en servidor
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.leagues validate constraint leagues_name_len_chk;
alter table public.matches validate constraint matches_type_league_chk;
alter table public.profiles validate constraint profiles_username_fmt_chk;

create or replace function public._profiles_guard() returns trigger
language plpgsql set search_path = pg_catalog, public, pg_temp as $$
begin
  if tg_op = 'UPDATE' and new.avatar_url is distinct from old.avatar_url and new.avatar_url is not null
     and new.avatar_url not like '%/storage/v1/object/public/avatars/' || new.id::text || '/%' then
    raise exception 'invalid_avatar_url';
  end if;
  new.display_name := left(btrim(new.display_name), 60);
  new.first_name := nullif(left(btrim(new.first_name), 60), '');
  new.last_name := nullif(left(btrim(new.last_name), 60), '');
  new.city := nullif(left(btrim(new.city), 60), '');
  new.home_club := nullif(left(btrim(new.home_club), 80), '');
  new.habitual_club := nullif(left(btrim(new.habitual_club), 80), '');
  return new;
end $$;

do $$ begin
  alter table public.profiles add constraint profiles_text_len_chk check (
    char_length(display_name) <= 60 and coalesce(char_length(first_name), 0) <= 60 and coalesce(char_length(last_name), 0) <= 60
    and coalesce(char_length(city), 0) <= 60 and coalesce(char_length(home_club), 0) <= 80 and coalesce(char_length(habitual_club), 0) <= 80
    and coalesce(char_length(avatar_url), 0) <= 500 and coalesce(char_length(banner_url), 0) <= 500);
  alter table public.profiles add constraint profiles_birth_date_chk check (birth_date is null or birth_date >= date '1900-01-01');
  alter table public.matches add constraint matches_text_len_chk check (coalesce(char_length(club), 0) <= 120 and coalesce(char_length(court), 0) <= 60);
  alter table public.notifications add constraint notifications_text_len_chk check (coalesce(char_length(title), 0) <= 120 and coalesce(char_length(body), 0) <= 500);
  alter table public.clubs add constraint clubs_text_len_chk check (coalesce(char_length(city), 0) <= 120 and coalesce(char_length(address), 0) <= 200);
  alter table public.courts add constraint courts_name_len_chk check (char_length(btrim(name)) between 1 and 60);
  alter table public.match_result_acceptances add constraint mra_reason_len_chk check (coalesce(char_length(reason), 0) <= 280);
  alter table public.conversations add constraint conversations_avatar_url_len_chk check (coalesce(char_length(avatar_url), 0) <= 500);
  alter table public.feed_posts add constraint feed_posts_metadata_size_chk check (pg_column_size(metadata) <= 8192);
  alter table public.messages add constraint messages_payload_size_chk check (payload is null or pg_column_size(payload) <= 8192);
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Registro de auditoría (sin acceso desde la app: solo el servidor escribe; se consulta desde el panel)
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  user_id uuid,                       -- sin FK: el registro sobrevive al borrado de la cuenta (seudónimo)
  actor_id uuid,
  action text not null check (action in ('signup', 'login', 'email_changed', 'password_changed', 'account_deleted',
                                         'consent_given', 'consent_revoked', 'data_exported', 'admin_action')),
  details jsonb not null default '{}'::jsonb check (pg_column_size(details) <= 4096),
  created_at timestamptz not null default now()
);
create index if not exists audit_log_user_idx on public.audit_log (user_id, created_at desc);
alter table public.audit_log enable row level security;
revoke all on public.audit_log from anon, authenticated;

create or replace function private.audit(p_user uuid, p_action text, p_details jsonb default '{}'::jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into public.audit_log (user_id, actor_id, action, details) values (p_user, (select auth.uid()), p_action, coalesce(p_details, '{}'::jsonb));
$$;
revoke all on function private.audit(uuid, text, jsonb) from public, anon, authenticated;

-- Conservación: 12 meses (se programa en la Fase 9 o desde el panel con pg_cron).
create or replace function private.purge_audit_log() returns integer
language sql security definer set search_path = '' as $$
  with d as (delete from public.audit_log where created_at < now() - interval '12 months' returning 1) select count(*)::int from d;
$$;
revoke all on function private.purge_audit_log() from public, anon, authenticated;

create or replace function private.audit_auth_users() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin  -- la auditoría nunca debe impedir un alta o un inicio de sesión
    if tg_op = 'INSERT' then
      perform private.audit(new.id, 'signup', jsonb_build_object('provider', new.raw_app_meta_data->>'provider'));
    elsif tg_op = 'DELETE' then
      perform private.audit(old.id, 'account_deleted', '{}'::jsonb);
    else
      if new.last_sign_in_at is distinct from old.last_sign_in_at and new.last_sign_in_at is not null then
        perform private.audit(new.id, 'login', jsonb_build_object('provider', new.raw_app_meta_data->>'provider'));
      end if;
      if new.email is distinct from old.email then perform private.audit(new.id, 'email_changed', '{}'::jsonb); end if;
      if new.encrypted_password is distinct from old.encrypted_password then perform private.audit(new.id, 'password_changed', '{}'::jsonb); end if;
    end if;
  exception when others then null;
  end;
  return null;
end $$;
revoke all on function private.audit_auth_users() from public, anon, authenticated;

drop trigger if exists plobby_audit_auth_users on auth.users;
create trigger plobby_audit_auth_users after insert or update of last_sign_in_at, email, encrypted_password or delete on auth.users
  for each row execute function private.audit_auth_users();

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Perfil de otro jugador según la relación (lo usa la app nueva; la Fase 1b retira las columnas privadas del SELECT)
--    Públicos para cualquier usuario: id, nombre visible, usuario, foto/avatar y nivel declarado.
--    Solo el propio usuario y sus amigos: ciudad, club, bio, lado, mano, pareja habitual.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.get_profile(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); p public.profiles; q public.profiles; full_access boolean; res jsonb;
begin
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into p from public.profiles where id = p_user;
  if not found then return null; end if;
  full_access := private.can_view_user(p_user);
  res := jsonb_build_object('id', p.id, 'display_name', p.display_name, 'username', p.username, 'avatar_url', p.avatar_url,
                            'avatar_id', p.avatar_id, 'self_declared_level', p.self_declared_level,
                            'is_self', p.id = me, 'full', full_access);
  if full_access then
    res := res || jsonb_build_object('city', p.city, 'bio', p.bio, 'court_side', p.court_side, 'dominant_hand', p.dominant_hand,
                                     'habitual_club', p.habitual_club, 'habitual_partner_id', p.habitual_partner_id);
    if p.id = me then res := res || jsonb_build_object('banner_id', p.banner_id); end if;
    if p.habitual_partner_id is not null then
      select * into q from public.profiles where id = p.habitual_partner_id;
      if found then
        res := res || jsonb_build_object('partner', jsonb_build_object('id', q.id, 'display_name', q.display_name, 'username', q.username,
                                         'avatar_url', q.avatar_url, 'mutual', q.habitual_partner_id = p.id));
      end if;
    end if;
  end if;
  return res;
end $$;
revoke all on function public.get_profile(uuid) from public, anon;
grant execute on function public.get_profile(uuid) to authenticated;
