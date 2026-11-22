-- Plobby · Pruebas de la Fase 4 (borrado/anonimización, exportación, códigos). Siempre termina en ROLLBACK (raise).
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); d uuid := gen_random_uuid();
  g uuid := gen_random_uuid(); m uuid := gen_random_uuid(); t uuid := gen_random_uuid(); tt uuid := gen_random_uuid(); lg uuid;
  res text[] := '{}'; n int; j jsonb; failed int; code text;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
    (a, 'lc_a@test.invalid', '{"full_name":"Ana Test"}', '{"provider":"google"}'),
    (b, 'lc_b@test.invalid', '{"full_name":"Beto Borrable","given_name":"Beto","family_name":"Borrable"}', '{"provider":"google"}'),
    (c, 'lc_c@test.invalid', '{"full_name":"Cris Test"}', '{"provider":"google"}'),
    (d, 'lc_d@test.invalid', '{"full_name":"Dani Test"}', '{"provider":"google"}');
  update public.profiles set username = 'beto_borrable', city = 'Madrid', bio = 'bio', birth_date = '1990-01-01', habitual_partner_id = a,
         avatar_url = 'https://x.supabase.co/storage/v1/object/public/avatars/' || b || '/avatar_1.jpg' where id = b;
  update public.profiles set habitual_partner_id = b where id = a;
  insert into public.friendships (user_id, friend_id, status) values (a, b, 'accepted'), (b, a, 'accepted'), (b, c, 'accepted'), (c, b, 'accepted');
  -- grupo donde B es el único admin
  insert into public.conversations (id, kind, name) values (g, 'group', 'Grupo LC');
  insert into public.conversation_members (conversation_id, user_id, role, joined_at) values (g, b, 'admin', now() - interval '2 day'), (g, a, 'member', now() - interval '1 day'), (g, c, 'member', now());
  insert into public.messages (conversation_id, sender_id, kind, body) values (g, b, 'text', 'mensaje de B'), (g, a, 'text', 'mensaje de A');
  -- partido de 4 confirmado con B
  insert into public.matches (id, created_by, match_type, status, started_by, ended_by, club) values (m, b, 'friendly', 'confirmed', b, b, 'Club');
  insert into public.match_players (match_id, user_id, team, is_captain) values (m, a, 1, true), (m, b, 1, false), (m, c, 2, true), (m, d, 2, false);
  insert into public.match_result_versions (match_id, version, proposed_by, sets, winner_team) values (m, 1, b, '[[6,3],[6,4]]', 1);
  -- torneo creado por B (dueño) con A como admin y un equipo con B
  insert into public.tournaments (id, name, starts_on, max_teams, format, groups_count, qualifiers_per_group, points_win, points_loss, status, created_by, cover_url)
    values (t, 'Torneo LC', current_date, 8, 'knockout', 1, 0, 3, 0, 'scheduled', b, 'https://x.supabase.co/storage/v1/object/public/avatars/' || b || '/tcover_1.jpg');
  insert into public.tournament_admins (tournament_id, user_id, role, created_at) values (t, b, 'owner', now() - interval '1 day'), (t, a, 'admin', now());
  insert into public.tournament_teams (id, tournament_id, seed, player1_id, player2_id) values (tt, t, 1, b, c);
  insert into public.tournament_players (tournament_id, user_id, team_id) values (t, b, tt), (t, c, tt);

  -- ---- borrado de B (lo que hace la Edge Function con auth.admin.deleteUser) ----
  begin delete from auth.users where id = b; res := res || text 'Borrar a B de Auth no falla (antes fallaba por los partidos): true';
  exception when others then res := res || format('Borrar a B de Auth no falla: false (%s %s)', sqlstate, sqlerrm); end;

  select count(*) into n from auth.users where id = b; res := res || format('B ya no existe en Auth: %s', n = 0);
  select count(*) into n from public.profiles where id = b and display_name = 'Jugador eliminado' and username is null and first_name is null
     and last_name is null and birth_date is null and avatar_url is null and city is null and bio is null and deleted_at is not null;
  res := res || format('Perfil de B anonimizado («Jugador eliminado», sin datos personales): %s', n = 1);
  select count(*) into n from public.match_players where match_id = m; res := res || format('El partido sigue con sus 4 jugadores: %s', n = 4);
  select count(*) into n from public.messages where sender_id = b; res := res || format('Mensajes de B borrados: %s', n = 0);
  select count(*) into n from public.messages where sender_id = a and conversation_id = g; res := res || format('Mensajes de A en el grupo intactos: %s', n = 1);
  select count(*) into n from public.conversation_members where conversation_id = g and role = 'admin'; res := res || format('El grupo tiene nuevo admin: %s', n = 1);
  select count(*) into n from public.friendships where user_id = b or friend_id = b; res := res || format('Amistades de B borradas: %s', n = 0);
  select count(*) into n from public.profiles where id = a and habitual_partner_id is null; res := res || format('La pareja habitual de A se limpia: %s', n = 1);
  select count(*) into n from public.tournament_admins where tournament_id = t and role = 'owner' and user_id = a; res := res || format('El torneo pasa a A como dueño: %s', n = 1);
  select count(*) into n from public.tournaments where id = t and cover_url is null; res := res || format('Portada del torneo (en carpeta de B) retirada: %s', n = 1);
  select count(*) into n from public.tournament_teams where id = tt and player1_id = b; res := res || format('El equipo del torneo sigue (B anónimo): %s', n = 1);
  select count(*) into n from public.audit_log where user_id = b and action = 'account_deleted'; res := res || format('audit_log registra el borrado: %s', n = 1);

  -- ---- A intenta interactuar con la cuenta borrada ----
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin perform public.send_friend_request(b); res := res || text 'No se puede pedir amistad a una cuenta eliminada: false';
  exception when others then res := res || format('No se puede pedir amistad a una cuenta eliminada: true (%s)', sqlerrm); end;
  select count(*) into n from public.search_players('Jugador'); res := res || format('La búsqueda no muestra cuentas eliminadas: %s', n = 0);
  j := public.export_my_data();
  res := res || format('Exportación: incluye perfil, partidos y amigos de A: %s',
           (j->'profile'->>'id') = a::text and jsonb_array_length(j->'matches') = 1 and j ? 'friends' and j ? 'messages_sent' and (j->'account'->>'email') = 'lc_a@test.invalid');
  res := res || format('Exportación: sin datos de otros (solo sus mensajes): %s', jsonb_array_length(j->'messages_sent') = 1);
  begin perform public.export_my_data(); res := res || text 'Exportación limitada a 1 cada 10 min: false';
  exception when others then res := res || format('Exportación limitada a 1 cada 10 min: true (%s)', sqlerrm); end;
  -- códigos de liga
  j := public.create_league('Liga Prueba LC', '', 'private', null, null, null, null, current_date, current_date + 30, 2, 8, 'individual', 10, 3, true, true, null);
  code := j->>'invite_code';
  res := res || format('Código de liga nuevo con 8 caracteres aleatorios (%s): %s', code, split_part(code, '-', 2) ~ '^[A-HJKMNP-Z2-9]{8}$');
  begin perform public.create_league('Liga Prueba LC2', '', 'private', null, null, null, null, current_date, current_date + 30, 2, 8, 'individual', 10, 3, true, true,
                                      (select array_agg(gen_random_uuid()) from generate_series(1, 65)));
        res := res || text 'Máx. 64 invitados por llamada: false';
  exception when others then res := res || format('Máx. 64 invitados por llamada: true (%s)', sqlerrm); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  execute 'set local role anon';
  begin perform public.export_my_data(); res := res || text 'anon no exporta: false';
  exception when others then res := res || format('anon no exporta: true (%s)', sqlstate); end;
  execute 'reset role';

  -- ---- un usuario nuevo con la misma cuenta de Google empieza de cero ----
  insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'lc_b@test.invalid', '{"full_name":"Beto Nuevo"}');
  select count(*) into n from public.profiles where display_name = 'Beto Nuevo' and deleted_at is null; res := res || format('Volver a registrarse crea un perfil nuevo y limpio: %s', n = 1);

  select count(*) into failed from unnest(res) r where r ~ ': (f|false)( |$)';
  raise exception E'RESULTADO: %/% OK\n%', array_length(res, 1) - failed, array_length(res, 1), array_to_string(res, E'\n');
end $$;
