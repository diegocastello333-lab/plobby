-- =====================================================================================================================
-- Plobby · Pruebas de aislamiento (RLS, permisos, RPC, Storage). Demuestran que el usuario C (desconocido) NO puede
-- leer, editar ni borrar datos de A y B, que `anon` no ve nada, y que A (amigo de B) sí ve lo que le corresponde.
--
-- Uso: ejecutar el fichero entero en el SQL Editor / execute_sql. Crea 3 usuarios temporales y SIEMPRE termina con
-- `raise exception` para deshacerlo todo: el mensaje de error ES el informe («RESULTADO: n/n OK» + una línea por prueba).
-- Requiere la migración 20261128a (y, si está aplicada, comprueba también la 20261128b).
-- =====================================================================================================================
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  conv uuid := gen_random_uuid(); post uuid := gen_random_uuid(); cmt uuid := gen_random_uuid();
  res text[] := '{}'; n int; j jsonb; failed int := 0; phase_b boolean;
begin
  -- ---------- preparación (como postgres) ----------
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
    (a, 'rls_a@test.invalid', '{"full_name":"Ana Test"}', '{"provider":"google"}'),
    (b, 'rls_b@test.invalid', '{"full_name":"Beto Test"}', '{"provider":"google"}'),
    (c, 'rls_c@test.invalid', '{"full_name":"Cris Test"}', '{"provider":"google"}');
  update public.profiles set city = 'Madrid', bio = 'bio privada de B', birth_date = '1990-05-05', habitual_club = 'Club B' where id = b;
  insert into public.friendships (user_id, friend_id, status) values (a, b, 'accepted'), (b, a, 'accepted');
  insert into public.conversations (id, kind) values (conv, 'direct');
  insert into public.conversation_members (conversation_id, user_id) values (conv, a), (conv, b);
  insert into public.messages (conversation_id, sender_id, kind, body) values (conv, a, 'text', 'mensaje privado A→B');
  insert into public.notifications (recipient_user_id, actor_user_id, notification_type, title, body)
    values (b, a, (select enum_range(null::public.notification_type))[1], 'aviso', 'aviso privado de B');
  insert into public.feed_posts (id, user_id, activity_type, metadata, dedupe_key) values (post, b, (select enum_range(null::public.feed_activity_type))[1], '{}', 'rls-test-' || post);
  insert into public.comments (id, post_id, user_id, content) values (cmt, post, b, 'comentario de B');
  insert into public.xp_events (user_id, source_type, source_id, xp) values (b, 'match', 'rls-test', 10);
  phase_b := not has_column_privilege('authenticated', 'public.profiles', 'city', 'SELECT');

  -- ---------- como C: usuario autenticado sin relación ----------
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.messages where conversation_id = conv;            res := res || format('C no lee mensajes ajenos: %s', n = 0);
  select count(*) into n from public.conversations where id = conv;                    res := res || format('C no ve la conversación: %s', n = 0);
  select count(*) into n from public.conversation_members where conversation_id = conv; res := res || format('C no ve miembros: %s', n = 0);
  select count(*) into n from public.notifications where recipient_user_id = b;        res := res || format('C no lee avisos de B: %s', n = 0);
  select count(*) into n from public.friendships where user_id = b;                    res := res || format('C no ve amistades de B: %s', n = 0);
  select count(*) into n from public.feed_posts where user_id = b;                     res := res || format('C no ve publicaciones de B: %s', n = 0);
  select count(*) into n from public.comments where post_id = post;                    res := res || format('C no ve comentarios de B: %s', n = 0);
  select count(*) into n from public.player_ratings where user_id = b;                 res := res || format('C no ve el ELO de B: %s', n = 0);
  select count(*) into n from public.xp_events where user_id = b;                      res := res || format('C no ve la XP de B: %s', n = 0);
  select count(*) into n from public.rating_history where user_id = b;                 res := res || format('C no ve historial de B: %s', n = 0);

  update public.profiles set bio = 'hackeado' where id = b; get diagnostics n = row_count;
  res := res || format('C no edita el perfil de B: %s', n = 0);
  update public.notifications set is_read = true where recipient_user_id = b; get diagnostics n = row_count;
  res := res || format('C no marca avisos de B: %s', n = 0);
  delete from public.comments where id = cmt; get diagnostics n = row_count;
  res := res || format('C no borra comentarios de B: %s', n = 0);

  begin insert into public.comments (post_id, user_id, content) values (post, b, 'suplantando a B'); res := res || text 'C no comenta en nombre de B: false';
  exception when others then res := res || format('C no comenta en nombre de B: true (%s)', sqlstate); end;
  begin insert into public.comments (post_id, user_id, content) values (post, c, 'colado'); res := res || text 'C no comenta en post que no ve: false';
  exception when others then res := res || format('C no comenta en post que no ve: true (%s)', sqlstate); end;
  begin update public.profiles set id = b where id = c; res := res || text 'C no cambia su id: false';
  exception when others then res := res || format('C no cambia su id: true (%s)', sqlstate); end;
  begin perform birth_date from public.profiles where id = b; res := res || text 'C no lee fecha de nacimiento: false';
  exception when others then res := res || format('C no lee fecha de nacimiento: true (%s)', sqlstate); end;
  begin perform first_name from public.profiles where id = b; res := res || text 'C no lee nombre real: false';
  exception when others then res := res || format('C no lee nombre real: true (%s)', sqlstate); end;
  begin insert into public.messages (conversation_id, sender_id, kind, body) values (conv, c, 'text', 'x'); res := res || text 'C no inserta mensajes directos: false';
  exception when others then res := res || format('C no inserta mensajes directos: true (%s)', sqlstate); end;
  begin perform public.send_message(conv, 'intruso', 'text', null); res := res || text 'C no escribe en chat ajeno (RPC): false';
  exception when others then res := res || format('C no escribe en chat ajeno (RPC): true (%s)', sqlstate); end;
  begin execute 'truncate public.notifications'; res := res || text 'C no puede TRUNCATE: false';
  exception when others then res := res || format('C no puede TRUNCATE: true (%s)', sqlstate); end;
  begin perform public.is_member(conv); res := res || text 'Auxiliar is_member no invocable: false';
  exception when others then res := res || format('Auxiliar is_member no invocable: true (%s)', sqlstate); end;
  begin perform public._is_participant(gen_random_uuid(), b); res := res || text 'Auxiliar _is_participant no invocable: false';
  exception when others then res := res || format('Auxiliar _is_participant no invocable: true (%s)', sqlstate); end;
  begin perform count(*) from public.audit_log; res := res || text 'C no lee audit_log: false';
  exception when others then res := res || format('C no lee audit_log: true (%s)', sqlstate); end;
  begin insert into storage.objects (bucket_id, name, owner) values ('avatars', b::text || '/x.png', c); res := res || text 'C no sube a la carpeta de B: false';
  exception when others then res := res || format('C no sube a la carpeta de B: true (%s)', sqlstate); end;

  j := public.get_profile(b);
  res := res || format('get_profile: C ve nombre de B: %s', j->>'display_name' = 'Beto Test');
  res := res || format('get_profile: C NO ve ciudad/bio/club de B: %s', not (j ? 'city') and not (j ? 'bio') and not (j ? 'habitual_club'));
  if phase_b then
    begin perform city from public.profiles where id = b; res := res || text '[1b] C no lee ciudad por REST: false';
    exception when others then res := res || format('[1b] C no lee ciudad por REST: true (%s)', sqlstate); end;
    select count(*) into n from public.search_players('Beto') where city is not null; res := res || format('[1b] búsqueda sin ciudad de desconocidos: %s', n = 0);
  end if;

  update public.profiles set bio = 'mi bio' where id = c; get diagnostics n = row_count;
  res := res || format('Control: C sí edita su perfil: %s', n = 1);
  execute 'reset role';

  -- ---------- como A: amigo de B ----------
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.messages where conversation_id = conv;   res := res || format('Control: A lee su chat con B: %s', n = 1);
  select count(*) into n from public.feed_posts where user_id = b;            res := res || format('Control: A ve publicaciones de su amigo B: %s', n = 1);
  select count(*) into n from public.notifications where recipient_user_id = b; res := res || format('A (amigo) tampoco lee avisos de B: %s', n = 0);
  select count(*) into n from public.xp_events where user_id = b;             res := res || format('A (amigo) no ve la XP de B: %s', n = 0);
  j := public.get_profile(b);
  res := res || format('Control: get_profile da a A la ciudad de B: %s', j->>'city' = 'Madrid');
  -- flujos reales de la app que escriben directamente en tablas (no deben romperse)
  begin perform public.set_reaction(post, (select enum_range(null::public.reaction_type))[1]);
    select count(*) into n from public.reactions where post_id = post and user_id = a; res := res || format('App: A reacciona (set_reaction): %s', n = 1);
  exception when others then res := res || format('App: A reacciona (set_reaction): false (%s %s)', sqlstate, sqlerrm); end;
  begin insert into public.comments (post_id, user_id, content) values (post, a, 'buen partido') returning to_jsonb(id) into j;
    res := res || text 'App: A comenta en post de su amigo: true';
  exception when others then res := res || format('App: A comenta en post de su amigo: false (%s %s)', sqlstate, sqlerrm); end;
  begin insert into public.notification_prefs (user_id, ranking, achievements, levels, wrapped) values (a, true, false, true, true)
          on conflict (user_id) do update set user_id = excluded.user_id, ranking = excluded.ranking, achievements = excluded.achievements;
    res := res || text 'App: A guarda preferencias (upsert): true';
  exception when others then res := res || format('App: A guarda preferencias (upsert): false (%s %s)', sqlstate, sqlerrm); end;
  begin update public.notifications set is_read = true where recipient_user_id = a; res := res || text 'App: A marca sus avisos: true';
  exception when others then res := res || format('App: A marca sus avisos: false (%s %s)', sqlstate, sqlerrm); end;
  begin update public.profiles set court_side = 'left', habitual_club = 'Club A', updated_at = now() where id = a; get diagnostics n = row_count;
    res := res || format('App: A edita su perfil: %s', n = 1);
  exception when others then res := res || format('App: A edita su perfil: false (%s %s)', sqlstate, sqlerrm); end;
  begin perform count(*) from public.v_my_friends; perform count(*) from public.v_my_friend_requests; perform count(*) from public.v_my_conversations;
        perform count(*) from public.v_group_members; perform count(*) from public.v_my_rating_detail; perform count(*) from public.v_my_rating_changes;
    select count(*) into n from public.v_my_friends; res := res || format('App: A lee las 6 vistas (1 amigo): %s', n = 1);
  exception when others then res := res || format('App: A lee las 6 vistas: false (%s %s)', sqlstate, sqlerrm); end;
  begin select count(*) into n from public.comments x join public.profiles pf on pf.id = x.user_id where x.post_id = post;
    res := res || format('App: A lee comentarios con autor: %s', n >= 1);
  exception when others then res := res || format('App: A lee comentarios con autor: false (%s %s)', sqlstate, sqlerrm); end;
  begin perform public.send_message(conv, 'hola B', 'text', null); res := res || text 'App: A envía mensaje (RPC): true';
  exception when others then res := res || format('App: A envía mensaje (RPC): false (%s %s)', sqlstate, sqlerrm); end;
  execute 'reset role';

  -- ---------- como anon (sin sesión) ----------
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  execute 'set local role anon';
  begin perform count(*) from public.profiles; res := res || text 'anon no lee perfiles: false';
  exception when others then res := res || format('anon no lee perfiles: true (%s)', sqlstate); end;
  begin perform count(*) from public.messages; res := res || text 'anon no lee mensajes: false';
  exception when others then res := res || format('anon no lee mensajes: true (%s)', sqlstate); end;
  begin perform count(*) from public.v_my_friends; res := res || text 'anon no lee vistas: false';
  exception when others then res := res || format('anon no lee vistas: true (%s)', sqlstate); end;
  begin perform public.get_profile(b); res := res || text 'anon no llama get_profile: false';
  exception when others then res := res || format('anon no llama get_profile: true (%s)', sqlstate); end;
  begin perform * from public.search_players('Beto'); res := res || text 'anon no llama search_players: false';
  exception when others then res := res || format('anon no llama search_players: true (%s)', sqlstate); end;
  begin insert into public.comments (post_id, user_id, content) values (post, b, 'anon'); res := res || text 'anon no escribe: false';
  exception when others then res := res || format('anon no escribe: true (%s)', sqlstate); end;
  execute 'reset role';

  -- ---------- auditoría ----------
  select count(*) into n from public.audit_log where user_id in (a, b, c) and action = 'signup';
  res := res || format('audit_log registra las 3 altas: %s', n = 3);

  select count(*) into n from pg_proc fp join pg_namespace s on s.oid = fp.pronamespace
   where s.nspname in ('public', 'private') and fp.prokind = 'f' and not exists (select 1 from unnest(coalesce(fp.proconfig, '{}')) x where x like 'search_path=%');
  res := res || format('Todas las funciones con search_path fijo: %s', n = 0);
  select count(*) into n from pg_class t join pg_namespace s on s.oid = t.relnamespace where s.nspname = 'public' and t.relkind = 'r' and not t.relrowsecurity;
  res := res || format('Ninguna tabla de public sin RLS: %s', n = 0);
  select count(*) into n from pg_class t join pg_namespace s on s.oid = t.relnamespace where s.nspname = 'public' and t.relkind in ('r', 'v')
     and (has_table_privilege('anon', t.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') or has_table_privilege('authenticated', t.oid, 'TRUNCATE,REFERENCES,TRIGGER'));
  res := res || format('anon sin permisos y nadie con TRUNCATE/REFERENCES/TRIGGER: %s', n = 0);
  select count(*) into failed from unnest(res) r where r ~ ': (f|false)( |$)';
  raise exception E'RESULTADO: %/% OK\n%', array_length(res, 1) - failed, array_length(res, 1), array_to_string(res, E'\n');
end $$;
