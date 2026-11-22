-- =====================================================================================================================
-- Plobby · Seguridad Fase 4 (22 nov 2026): lógica sensible en servidor. Ver docs/seguridad/fase4_servidor.md.
--
--  1. BORRADO DE CUENTA (decisión del usuario: anonimizar lo compartido).
--     · La Edge Function `delete-account` (única con service_role) borra los ficheros de Storage y el usuario de Auth.
--     · Al borrarse de auth.users, el trigger `plobby_anonymize_before_delete` ejecuta private.anonymize_user(uid):
--       borra todo lo personal y deja el perfil como «Jugador eliminado» (sin nombre, usuario, foto, fecha de nacimiento…)
--       para que los partidos, torneos, ELO y rankings de los DEMÁS no se rompan.
--     · Por eso `profiles.id` deja de tener FK a auth.users (antes ON DELETE CASCADE): el perfil anonimizado sobrevive.
--       También funciona si el usuario se borra desde el panel de Supabase.
--  2. EXPORTACIÓN: RPC export_my_data() (RGPD art. 15 y 20): todos los datos del usuario en JSON. Máx. 1 cada 10 min.
--  3. Códigos de invitación de liga: 8 caracteres aleatorios (40 bits) en vez de 4 hexadecimales (16 bits, adivinables).
--     Los 2 códigos existentes siguen valiendo (no se cambian para no romper invitaciones ya enviadas).
--  4. Límites de entrada: máx. 64 invitados por llamada en create_league / invite_to_league.
--  5. No se puede enviar solicitud de amistad a una cuenta eliminada; la búsqueda y las sugerencias las ocultan.
-- No borra datos existentes.
-- =====================================================================================================================

alter table public.profiles add column if not exists deleted_at timestamptz;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Anonimización
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function private.anonymize_user(p_uid uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  if p_uid is null or not exists (select 1 from public.profiles where id = p_uid) then return; end if;

  -- grupos: si era el único admin, pasa a serlo el miembro más antiguo
  for r in select cm.conversation_id from public.conversation_members cm join public.conversations c on c.id = cm.conversation_id
            where cm.user_id = p_uid and c.kind = 'group' and cm.role = 'admin'
              and not exists (select 1 from public.conversation_members o where o.conversation_id = cm.conversation_id and o.role = 'admin' and o.user_id <> p_uid)
  loop
    update public.conversation_members set role = 'admin'
     where conversation_id = r.conversation_id and user_id = (select user_id from public.conversation_members
           where conversation_id = r.conversation_id and user_id <> p_uid order by joined_at limit 1);
  end loop;
  -- ligas: si era el organizador, lo pasa a ser un admin o el miembro más antiguo
  for r in select league_id from public.league_members where user_id = p_uid and role = 'organizer' loop
    update public.league_members set role = 'organizer'
     where league_id = r.league_id and user_id = (select user_id from public.league_members where league_id = r.league_id and user_id <> p_uid
           order by (role = 'admin') desc, joined_at limit 1);
  end loop;
  -- torneos: si era el dueño, pasa a serlo otro admin (si lo hay)
  for r in select tournament_id from public.tournament_admins where user_id = p_uid and role = 'owner' loop
    update public.tournament_admins set role = 'owner'
     where tournament_id = r.tournament_id and user_id = (select user_id from public.tournament_admins where tournament_id = r.tournament_id
           and user_id <> p_uid order by created_at limit 1);
  end loop;
  -- portadas de torneo guardadas en su carpeta (la Edge Function borra el fichero)
  update public.tournaments set cover_url = null where cover_url like '%/avatars/' || p_uid::text || '/%';

  -- datos personales y actividad propia
  delete from public.messages where sender_id = p_uid;
  delete from public.conversation_members where user_id = p_uid;
  delete from public.comments where user_id = p_uid;
  delete from public.reactions where user_id = p_uid;
  delete from public.comment_reports where reporter_id = p_uid;
  delete from public.feed_posts where user_id = p_uid;
  delete from public.notifications where recipient_user_id = p_uid;
  delete from public.notification_prefs where user_id = p_uid;
  delete from public.friend_requests where sender_id = p_uid or receiver_id = p_uid;
  delete from public.friendships where user_id = p_uid or friend_id = p_uid;
  delete from public.league_invites where user_id = p_uid;
  delete from public.league_join_requests where user_id = p_uid;
  delete from public.league_members where user_id = p_uid;
  delete from public.tournament_admins where user_id = p_uid;
  delete from public.user_achievements where user_id = p_uid;
  delete from public.xp_events where user_id = p_uid;
  delete from public.player_progress where user_id = p_uid;
  delete from public.ranking_snapshots where user_id = p_uid;
  delete from public.rating_history where user_id = p_uid;
  delete from public.player_match_stats where user_id = p_uid;
  delete from public.player_ratings where user_id = p_uid;
  update public.profiles set habitual_partner_id = null where habitual_partner_id = p_uid;

  -- perfil → «Jugador eliminado» (se conserva el id para los partidos/torneos de los demás)
  update public.profiles set
    display_name = 'Jugador eliminado', username = null, first_name = null, last_name = null, birth_date = null,
    avatar_url = null, avatar_id = null, banner_id = null, banner_url = null, city = null, home_club = null,
    habitual_club = null, bio = null, self_declared_level = null, court_side = null, dominant_hand = null,
    habitual_partner_id = null, deleted_at = now(), updated_at = now()
  where id = p_uid;
end $$;
revoke all on function private.anonymize_user(uuid) from public, anon, authenticated;

create or replace function private.anonymize_before_auth_delete() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.anonymize_user(old.id);
  return old;
end $$;
revoke all on function private.anonymize_before_auth_delete() from public, anon, authenticated;

drop trigger if exists plobby_anonymize_before_delete on auth.users;
create trigger plobby_anonymize_before_delete before delete on auth.users
  for each row execute function private.anonymize_before_auth_delete();

-- El perfil anonimizado sobrevive al usuario de Auth (antes: ON DELETE CASCADE lo borraba y fallaba por los partidos)
alter table public.profiles drop constraint if exists profiles_id_fkey;

-- Nadie puede pedir amistad a una cuenta eliminada
create or replace function private.block_deleted_target() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.profiles where id = new.receiver_id and deleted_at is not null) then
    raise exception 'user_deleted' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function private.block_deleted_target() from public, anon, authenticated;
drop trigger if exists friend_requests_not_deleted on public.friend_requests;
create trigger friend_requests_not_deleted before insert on public.friend_requests
  for each row execute function private.block_deleted_target();

-- Búsqueda y sugerencias sin cuentas eliminadas (misma salida que antes)
do $$
declare d text;
begin
  d := pg_get_functiondef('public.search_players(text)'::regprocedure);
  if position('p.deleted_at is null' in d) = 0 then
    d := replace(d, 'where p.id <> auth.uid() and length(trim(q)) >= 2', 'where p.id <> auth.uid() and p.deleted_at is null and length(trim(q)) >= 2');
    if position('p.deleted_at is null' in d) = 0 then raise exception 'search_players: patrón no encontrado'; end if;
    execute d;
  end if;
  d := pg_get_functiondef('public.suggest_friends()'::regprocedure);
  if position('p.deleted_at is null' in d) = 0 then
    d := replace(d, E'where p.id <> auth.uid()\n', E'where p.id <> auth.uid() and p.deleted_at is null\n');
    if position('p.deleted_at is null' in d) = 0 then raise exception 'suggest_friends: patrón no encontrado'; end if;
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Exportación de datos (portabilidad / derecho de acceso)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.export_my_data() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); res jsonb;
begin
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if exists (select 1 from public.audit_log where user_id = me and action = 'data_exported' and created_at > now() - interval '10 minutes') then
    raise exception 'rate_limited';
  end if;
  res := jsonb_build_object(
    'format', 'plobby-export', 'version', 1, 'exported_at', now(), 'user_id', me,
    'account', (select jsonb_build_object('email', u.email, 'provider', u.raw_app_meta_data->>'provider', 'created_at', u.created_at,
                                          'last_sign_in_at', u.last_sign_in_at) from auth.users u where u.id = me),
    'profile', (select to_jsonb(p) - 'banner_url' from public.profiles p where p.id = me),
    'rating', (select to_jsonb(r) from public.player_ratings r where r.user_id = me),
    'rating_history', coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at) from public.rating_history h where h.user_id = me), '[]'),
    'progress', (select to_jsonb(x) from public.player_progress x where x.user_id = me),
    'xp_events', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.xp_events x where x.user_id = me), '[]'),
    'achievements', coalesce((select jsonb_agg(to_jsonb(a) order by a.unlocked_at) from public.user_achievements a where a.user_id = me), '[]'),
    'matches', coalesce((select jsonb_agg(jsonb_build_object('match_id', m.id, 'status', m.status, 'type', m.match_type, 'league_id', m.league_id,
                          'club', m.club, 'court', m.court, 'scheduled_at', m.scheduled_at, 'played_at', m.played_at, 'team', mp.team,
                          'elo_delta', mp.elo_delta,
                          'sets', (select coalesce(jsonb_agg(jsonb_build_array(s.team1_games, s.team2_games) order by s.set_no), '[]') from public.match_sets s where s.match_id = m.id))
                          order by m.created_at)
                        from public.match_players mp join public.matches m on m.id = mp.match_id where mp.user_id = me), '[]'),
    'friends', coalesce((select jsonb_agg(jsonb_build_object('user_id', f.friend_id, 'display_name', p.display_name, 'since', f.created_at))
                        from public.friendships f join public.profiles p on p.id = f.friend_id where f.user_id = me), '[]'),
    'friend_requests', coalesce((select jsonb_agg(to_jsonb(r)) from public.friend_requests r where r.sender_id = me or r.receiver_id = me), '[]'),
    'messages_sent', coalesce((select jsonb_agg(jsonb_build_object('conversation_id', m.conversation_id, 'kind', m.kind, 'body', m.body, 'created_at', m.created_at) order by m.created_at)
                        from public.messages m where m.sender_id = me), '[]'),
    'groups', coalesce((select jsonb_agg(jsonb_build_object('conversation_id', c.id, 'name', c.name, 'role', cm.role, 'joined_at', cm.joined_at))
                        from public.conversation_members cm join public.conversations c on c.id = cm.conversation_id where cm.user_id = me and c.kind = 'group'), '[]'),
    'feed_posts', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'type', f.activity_type, 'metadata', f.metadata, 'created_at', f.created_at) order by f.created_at)
                        from public.feed_posts f where f.user_id = me), '[]'),
    'comments', coalesce((select jsonb_agg(jsonb_build_object('post_id', c.post_id, 'content', c.content, 'created_at', c.created_at) order by c.created_at)
                        from public.comments c where c.user_id = me), '[]'),
    'reactions', coalesce((select jsonb_agg(jsonb_build_object('post_id', r.post_id, 'type', r.reaction_type, 'created_at', r.created_at)) from public.reactions r where r.user_id = me), '[]'),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('type', n.notification_type, 'title', n.title, 'body', n.body, 'read', n.is_read, 'created_at', n.created_at) order by n.created_at desc)
                        from public.notifications n where n.recipient_user_id = me), '[]'),
    'notification_prefs', (select to_jsonb(x) from public.notification_prefs x where x.user_id = me),
    'leagues', coalesce((select jsonb_agg(jsonb_build_object('league_id', l.id, 'name', l.name, 'role', lm.role, 'joined_at', lm.joined_at))
                        from public.league_members lm join public.leagues l on l.id = lm.league_id where lm.user_id = me), '[]'),
    'tournaments', coalesce((select jsonb_agg(jsonb_build_object('tournament_id', t.id, 'name', t.name))
                        from public.tournaments t where exists (select 1 from public.tournament_players tp where tp.tournament_id = t.id and tp.user_id = me)
                           or exists (select 1 from public.tournament_admins ta where ta.tournament_id = t.id and ta.user_id = me)), '[]'),
    'security_log', coalesce((select jsonb_agg(jsonb_build_object('action', a.action, 'created_at', a.created_at) order by a.created_at desc)
                        from public.audit_log a where a.user_id = me), '[]')
  );
  perform private.audit(me, 'data_exported', '{}'::jsonb);
  return res;
end $$;
revoke all on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3 y 4. Códigos de invitación robustos y límites de entrada
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function private.random_code(p_len int) returns text
language sql volatile set search_path = '' as $$
  -- alfabeto sin caracteres confundibles (0/O, 1/I/L): 31 símbolos → 8 caracteres ≈ 40 bits
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + (get_byte(b, i) % 31), 1), '')
  from (select extensions.gen_random_bytes(p_len) as b) x, generate_series(0, p_len - 1) as i;
$$;
revoke all on function private.random_code(int) from public, anon, authenticated;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.create_league'::regproc);
  if position('private.random_code' in d) = 0 then
    d := replace(d, 'upper(substr(md5(gen_random_uuid()::text), 1, 4))', 'private.random_code(8)');
    d := replace(d, E'begin\n  if me is null then raise exception ''not_authenticated''; end if;',
                    E'begin\n  if me is null then raise exception ''not_authenticated''; end if;\n  if cardinality(p_invited) > 64 then raise exception ''too_many_invites''; end if;');
    if position('private.random_code' in d) = 0 or position('too_many_invites' in d) = 0 then raise exception 'create_league: patrón no encontrado'; end if;
    execute d;
  end if;
  d := pg_get_functiondef('public.invite_to_league'::regproc);
  if position('too_many_invites' in d) = 0 then
    d := replace(d, E'begin\n  if not public.is_league_manager(p_league) then raise exception ''not_league_manager''; end if;',
                    E'begin\n  if not public.is_league_manager(p_league) then raise exception ''not_league_manager''; end if;\n  if cardinality(p_user_ids) > 64 then raise exception ''too_many_invites''; end if;');
    if position('too_many_invites' in d) = 0 then raise exception 'invite_to_league: patrón no encontrado'; end if;
    execute d;
  end if;
end $$;
-- pg_get_functiondef conserva propietario, SECURITY DEFINER y search_path; se reafirman los permisos
revoke all on function public.create_league(text, text, text, text, text, text, text, date, date, integer, integer, text, integer, integer, boolean, boolean, uuid[]) from public, anon;
grant execute on function public.create_league(text, text, text, text, text, text, text, date, date, integer, integer, text, integer, integer, boolean, boolean, uuid[]) to authenticated;
revoke all on function public.invite_to_league(uuid, uuid[]) from public, anon;
grant execute on function public.invite_to_league(uuid, uuid[]) to authenticated;
revoke all on function public.search_players(text), public.suggest_friends() from public, anon;
grant execute on function public.search_players(text), public.suggest_friends() to authenticated;
