-- Pruebas de la gamificación sobre la réplica local, con las RPC reales del ciclo de partido. Todo se deshace.
begin;
create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
create or replace function pg_temp.as_admin() returns void language plpgsql as $$ begin execute 'reset role'; end $$;

-- Partido completo: crea (creador + pareja vs rivales), empieza (con fecha `at`), termina, resultado y lo aceptan los 2 capitanes.
create or replace function pg_temp.play(creator uuid, partner uuid, r1 uuid, r2 uuid, sets jsonb, at timestamptz default clock_timestamp()) returns uuid language plpgsql as $$
declare m uuid; v int;
begin
  perform pg_temp.as_user(creator);
  m := (public.create_match('friendly', null, partner, r1, r2, at, 'Club Test', null))::text::uuid;
  perform public.start_match(m);
  perform pg_temp.as_admin();
  perform set_config('plobby.rpc', 'on', true);
  update public.matches set started_at = at where id = m;
  perform set_config('plobby.rpc', 'off', true);
  perform pg_temp.as_user(creator);
  perform public.finish_match(m);
  v := public.submit_result(m, sets);
  perform public.respond_result(m, v, true, null);
  perform pg_temp.as_user((select user_id from public.match_players where match_id = m and team = 2 and is_captain));
  perform public.respond_result(m, v, true, null);
  perform pg_temp.as_admin();
  if (select status from public.matches where id = m) <> 'confirmed' then raise exception 'partido no confirmado'; end if;
  return m;
end $$;

create temp table r(n serial, ok boolean, what text);
grant all on r to authenticated, anon; grant all on sequence r_n_seq to authenticated, anon;
create or replace function pg_temp.check(ok boolean, what text) returns void language sql as $$ insert into r(ok, what) values (coalesce(ok, false), what) $$;

do $t$
declare a uuid; b uuid; c uuid; d uuid; e uuid; u uuid[] := '{}'; i int; m1 uuid; m uuid; j jsonb; x int; y int; tid uuid; f record;
begin
  for i in 1..6 loop
    u := u || gen_random_uuid();
    insert into auth.users (id, email, raw_user_meta_data) values (u[i], 'u' || i || '@test.invalid', jsonb_build_object('full_name', (array['Ana','Bea','Carla','Dani','Eva','Fer'])[i] || ' Test'));
  end loop;
  a := u[1]; b := u[2]; c := u[3]; d := u[4]; e := u[5];   -- e no es amiga de nadie
  insert into public.friendships (user_id, friend_id, status)
    select x1, x2, 'accepted' from unnest(array[a,b,c,d,u[6]]) x1, unnest(array[a,b,c,d,u[6]]) x2 where x1 <> x2 on conflict do nothing;

  -- 1) Partido: A+B ganan a C+D. Filas, XP, logros.
  m1 := pg_temp.play(a, b, c, d, '[[6,3],[6,4]]');
  perform pg_temp.check((select count(*) from public.player_match_stats where match_id = m1) = 4, '1 partido = 4 filas de estadística');
  perform pg_temp.check((select won from public.player_match_stats where match_id = m1 and user_id = a) and not (select won from public.player_match_stats where match_id = m1 and user_id = c), 'ganadores y perdedores correctos');
  perform pg_temp.check((select (sets_won, sets_lost, games_won, games_lost) = (2::smallint, 0::smallint, 12::smallint, 7::smallint) from public.player_match_stats where match_id = m1 and user_id = a), 'sets y juegos desde el punto de vista del jugador');
  perform pg_temp.check((select partner_id = b and least(rival1_id, rival2_id) = least(c, d) from public.player_match_stats where match_id = m1 and user_id = a), 'pareja y rivales');
  perform pg_temp.check((select xp from public.player_progress where user_id = a) = 100 + 50 + 50 + 50, 'XP A = partido 100 + victoria 50 + logros primer partido 50 y primera victoria 50');
  perform pg_temp.check((select xp from public.player_progress where user_id = c) = 100 + 50, 'XP C = partido 100 + logro primer partido 50 (sin victoria)');
  perform pg_temp.check(exists (select 1 from public.feed_posts where user_id = a and activity_type = 'achievement' and metadata->>'title' = 'Primera victoria'), 'publicación de logro con título');
  perform pg_temp.check(exists (select 1 from public.notifications where recipient_user_id = a and notification_type = 'achievement'), 'aviso de logro');

  -- 2) Idempotencia: recalcular no duplica nada
  perform public._g_sync_match(m1); perform public._g_after_match(m1); perform public._g_after_match(m1);
  perform pg_temp.check((select count(*) from public.player_match_stats where match_id = m1) = 4 and (select xp from public.player_progress where user_id = a) = 250, 'recalcular dos veces no duplica filas ni XP');

  -- 3) Racha de 3 → logro; nivel 2 (400 XP) con aviso
  m := pg_temp.play(a, b, c, d, '[[6,1],[6,1]]');
  m := pg_temp.play(a, b, c, d, '[[3,6],[6,4],[7,5]]');
  perform pg_temp.check(exists (select 1 from public.user_achievements where user_id = a and achievement_id = 'streak_3'), 'logro racha de 3');
  perform pg_temp.check((select level from public.player_progress where user_id = a) >= 2, 'sube de nivel');
  perform pg_temp.check(exists (select 1 from public.notifications where recipient_user_id = a and notification_type = 'level_up'), 'aviso de subida de nivel');

  -- 4) Head to Head
  perform pg_temp.as_user(a);
  j := public.head_to_head(c);
  perform pg_temp.check((j->'direct'->>'total')::int = 3 and (j->'direct'->>'my_wins')::int = 3 and (j->'direct'->>'their_wins')::int = 0, 'H2H directo A vs C: 3 partidos, 3-0');
  perform pg_temp.check((j->'together'->>'total')::int = 0, 'H2H: A y C nunca juntos');
  perform pg_temp.check((j->'me'->>'played')::int = 3 and (j->'me'->>'current_streak')::int = 3 and (j->'other'->>'current_streak')::int = -3, 'H2H: tarjetas generales (rachas +3 / -3)');
  perform pg_temp.check(jsonb_array_length(j->'direct'->'matches') = 3 and exists (select 1 from jsonb_array_elements(j->'direct'->'matches') mm where mm->'sets' = '[[3,6],[6,4],[7,5]]'::jsonb), 'H2H: resultados con sets desde mi punto de vista');
  j := public.head_to_head(b);
  perform pg_temp.check((j->'direct'->>'total')::int = 0 and (j->'together'->>'total')::int = 3 and (j->'together'->>'wins')::int = 3, 'H2H con mi compañero: 0 enfrentamientos, 3 juntos');
  begin perform public.head_to_head(e); perform pg_temp.check(false, 'H2H con alguien que no es amigo debe fallar');
  exception when insufficient_privilege then perform pg_temp.check(true, 'H2H con un desconocido: denegado'); end;
  perform pg_temp.as_admin();

  -- 5) Ranking semanal y avisos de adelantamiento
  perform pg_temp.as_user(a);
  j := public.friends_ranking('week');
  perform pg_temp.check((select (rw->>'pos_wins')::int from jsonb_array_elements(j->'rows') rw where rw->>'user_id' = a::text) = 1, 'A lidera el ranking de victorias');
  perform pg_temp.check((select (rw->>'pos_wins')::int from jsonb_array_elements(j->'rows') rw where rw->>'user_id' = b::text) = 1, 'empate: B (mismas victorias, mismo %) comparte el puesto 1');
  perform pg_temp.check((select rw->>'pos_rate' from jsonb_array_elements(j->'rows') rw where rw->>'user_id' = u[6]::text) is null, 'sin partidos: fuera del ranking de % (mínimo de partidos)');
  perform pg_temp.check(jsonb_array_length(j->'rows') = 5, 'el grupo es A + sus 4 amigos');
  perform pg_temp.as_admin();
  -- C y D ganan ahora a Fer+A? (A pierde) → C pasa de 0 a 1 victoria
  m := pg_temp.play(c, d, a, u[6], '[[6,2],[6,2]]');
  perform pg_temp.check((select count(*) from public.notifications where recipient_user_id = c and notification_type = 'ranking') >= 1, 'C recibe «subes de puesto»');
  perform pg_temp.check(not exists (select 1 from public.user_achievements where user_id = a and achievement_id = 'streak_3') = false, 'la racha histórica (mejor racha 3) se conserva aunque se pierda');
  -- límite diario y preferencias
  update public.notification_prefs set ranking = false where user_id = b;
  insert into public.notification_prefs (user_id, ranking) values (b, false) on conflict (user_id) do update set ranking = false;
  x := (select count(*) from public.notifications where recipient_user_id = b and notification_type = 'ranking');
  m := pg_temp.play(c, d, b, u[6], '[[6,2],[6,2]]');
  perform pg_temp.check((select count(*) from public.notifications where recipient_user_id = b and notification_type = 'ranking') = x, 'preferencia ranking desactivada: B no recibe avisos de ranking');
  for i in 1..5 loop m := pg_temp.play(c, d, u[6], a, '[[6,2],[6,2]]'); end loop;
  perform pg_temp.check((select count(*) from public.notifications where recipient_user_id = c and notification_type = 'ranking') <= 3, 'límite diario de avisos de ranking (3)');

  -- 6) Seguridad: nada se escribe desde la app
  perform pg_temp.as_user(a);
  begin insert into public.xp_events (user_id, source_type, source_id, xp) values (a, 'match', 'fake', 10000); perform pg_temp.check(false, 'insertar XP desde la app');
  exception when insufficient_privilege then perform pg_temp.check(true, 'XP: escritura directa denegada'); end;
  begin update public.player_progress set xp = 999999 where user_id = a; perform pg_temp.check(false, 'cambiar progreso desde la app');
  exception when insufficient_privilege then perform pg_temp.check(true, 'nivel/XP: actualización directa denegada'); end;
  begin insert into public.player_match_stats (match_id, user_id, played_at, team, won, sets_won, sets_lost, games_won, games_lost) values (m1, a, now(), 1, true, 2, 0, 12, 0);
        perform pg_temp.check(false, 'insertar estadísticas desde la app');
  exception when insufficient_privilege then perform pg_temp.check(true, 'estadísticas: escritura directa denegada'); end;
  begin insert into public.user_achievements (user_id, achievement_id) values (a, 'matches_100'); perform pg_temp.check(false, 'insertar logro desde la app');
  exception when insufficient_privilege then perform pg_temp.check(true, 'logros: escritura directa denegada'); end;
  begin perform public._g_grant(a, 'matches_100'); perform pg_temp.check(false, 'llamar a la función interna de logros');
  exception when insufficient_privilege then perform pg_temp.check(true, 'funciones internas no ejecutables por la app'); end;
  update public.notification_prefs set ranking = true where user_id = b;   -- RLS: no afecta a la fila de B
  perform pg_temp.as_admin();
  perform pg_temp.check((select ranking from public.notification_prefs where user_id = b) = false, 'no se pueden cambiar las preferencias de otro');
  perform pg_temp.as_user(a);
  perform pg_temp.as_admin();
  perform pg_temp.as_user(e);
  perform pg_temp.check((select count(*) from public.player_match_stats) = 0 and (select count(*) from public.xp_events) = 0, 'un desconocido no ve estadísticas ni XP de nadie');
  perform pg_temp.as_admin();

  -- 7) Invalidación: si un partido deja de estar confirmado, se retiran sus filas, su XP y los logros que ya no se cumplen
  x := (select xp from public.player_progress where user_id = b);
  perform set_config('plobby.rpc', 'on', true);
  update public.matches set status = 'disputed' where id = m1;
  perform set_config('plobby.rpc', 'off', true);
  perform pg_temp.check(not exists (select 1 from public.player_match_stats where match_id = m1), 'partido invalidado: filas retiradas');
  perform pg_temp.check(not exists (select 1 from public.xp_events where source_id = m1::text), 'partido invalidado: XP retirada');
  perform pg_temp.check((select xp from public.player_progress where user_id = b) < x, 'partido invalidado: el total de XP baja');
  perform set_config('plobby.rpc', 'on', true);
  update public.matches set status = 'confirmed' where id = m1;
  perform set_config('plobby.rpc', 'off', true);
  perform pg_temp.check((select xp from public.player_progress where user_id = b) = x, 'al volver a confirmarse, la XP vuelve exactamente');
  -- corrección de sets de un partido ya confirmado → el ganador cambia en todo el sistema
  update public.match_sets set team1_games = 2, team2_games = 6 where match_id = m1;
  perform pg_temp.check(not (select won from public.player_match_stats where match_id = m1 and user_id = a), 'corrección de sets: A pasa a haber perdido m1');
  perform pg_temp.check(not exists (select 1 from public.xp_events where source_type = 'win' and source_id = m1::text and user_id = a)
                        and exists (select 1 from public.xp_events where source_type = 'win' and source_id = m1::text and user_id = c), 'corrección: la XP de victoria cambia de lado');

  -- 8) Temporadas. La semana anterior ya se cerró (vacía) al consultar el ranking arriba: un partido de esa semana
  --    confirmado TARDE no la altera.
  m := pg_temp.play(a, b, c, d, '[[6,0],[6,0]]', now() - interval '7 days');
  perform pg_temp.check(not exists (select 1 from public.ranking_snapshots where kind = 'week'), 'un partido confirmado tarde no altera una temporada ya cerrada');
  m := pg_temp.play(a, b, c, d, '[[6,0],[6,0]]', now() - interval '7 days');
  -- Para probar el cierre con datos se reabre esa semana (como si nadie hubiera consultado aún).
  delete from public.ranking_periods where kind = 'week';
  perform pg_temp.as_user(c);
  j := public.friends_ranking('week');
  perform pg_temp.as_admin();
  perform pg_temp.check(exists (select 1 from public.ranking_periods where kind = 'week' and starts_on = (select p_start from public._g_period('week', -1))), 'semana anterior cerrada automáticamente');
  perform pg_temp.check((select count(*) from public.ranking_snapshots where kind = 'week') >= 5, 'foto final guardada para cada jugador');
  perform pg_temp.check(exists (select 1 from public.user_achievements where user_id = a and achievement_id = 'week_winner'), 'insignia de campeón semanal');
  perform pg_temp.check(exists (select 1 from public.notifications where recipient_user_id = c and notification_type = 'ranking' and dedupe_key like 'season:week:%')
                        or exists (select 1 from public.notifications where recipient_user_id = a and dedupe_key like 'season:week:%'), 'aviso de cierre de temporada');
  x := (select count(*) from public.ranking_snapshots);
  perform pg_temp.as_user(a);
  j := public.friends_ranking('week', -1);
  perform pg_temp.as_admin();
  perform pg_temp.check((select count(*) from public.ranking_snapshots) = x, 'cerrar es idempotente');
  perform pg_temp.check((j->>'closed')::boolean and (select (rw->>'pos_wins')::int from jsonb_array_elements(j->'rows') rw where rw->>'user_id' = a::text) = 1, 'la temporada cerrada se lee de la foto congelada');

  -- 9) Wrapped: mes, año, cambio de año (zona horaria de Madrid)
  m := pg_temp.play(a, b, c, d, '[[6,4],[6,4]]', timestamptz '2026-12-31 22:30:00+00');   -- 31 dic 23:30 en Madrid
  perform pg_temp.as_user(a);
  j := public.wrapped('month', date '2026-12-01');
  perform pg_temp.check((j->>'played')::int = 1, 'Wrapped de diciembre incluye el partido de las 23:30 del 31');
  j := public.wrapped('month', date '2027-01-01');
  perform pg_temp.check((j->>'played')::int = 0, 'y no cuenta en enero (cambio de año)');
  j := public.wrapped('year', date '2026-01-01');
  perform pg_temp.check((j->>'played')::int = (select count(*) from public.player_match_stats where user_id = a) and j->'top_partner'->>'user_id' = b::text, 'Wrapped anual: total y compañero más habitual');
  perform pg_temp.check(j->'memorable' is not null and (j->>'best_streak')::int between 2 and (j->>'wins')::int and jsonb_array_length(j->'buckets') >= 1, 'Wrapped: partido memorable, mejor racha (refleja la corrección) y evolución');
  j := public.wrapped_periods();
  perform pg_temp.check(jsonb_array_length(j->'months') >= 2 and jsonb_array_length(j->'years') >= 1, 'periodos de Wrapped disponibles');
  perform pg_temp.as_admin();

  -- 10) Torneo ganado → logro; se retira al corregir la final
  perform pg_temp.as_user(a);
  tid := public.create_tournament(jsonb_build_object('name','Copa','starts_on','2026-11-20','max_teams',4,'format','knockout',
     'teams', jsonb_build_array(jsonb_build_array(a,b), jsonb_build_array(c,d))));
  select * into f from public.tournament_matches where tournament_id = tid;
  perform public.record_tournament_result(f.id, '[[6,2],[6,3]]', f.version);
  perform pg_temp.as_admin();
  perform pg_temp.check(exists (select 1 from public.user_achievements where user_id = a and achievement_id = 'tournament_winner'), 'logro de campeón de torneo');
  perform pg_temp.as_user(a);
  select * into f from public.tournament_matches where tournament_id = tid;
  perform public.record_tournament_result(f.id, '[[2,6],[3,6]]', f.version);
  perform pg_temp.as_admin();
  perform pg_temp.check(not exists (select 1 from public.user_achievements where user_id = a and achievement_id = 'tournament_winner')
                        and exists (select 1 from public.user_achievements where user_id = c and achievement_id = 'tournament_winner'), 'final corregida: el logro cambia de dueño');

  -- 11) Logros y nivel para la app
  perform pg_temp.as_user(a);
  j := public.my_achievements();
  perform pg_temp.check(jsonb_array_length(j->'achievements') = 20 and (j->>'xp')::int = (select xp from public.player_progress where user_id = a)
                        and (j->>'level_ceiling')::int > (j->>'level_floor')::int, 'my_achievements: catálogo, XP y tramo de nivel');
  perform public.mark_achievements_seen();
  perform pg_temp.check(not exists (select 1 from public.user_achievements where user_id = a and seen_at is null), 'logros marcados como vistos');
  perform pg_temp.as_admin();
end $t$;

select n, case when ok then 'OK ' else 'FALLO' end, what from r order by n;
select count(*) filter (where ok) || '/' || count(*) as resumen from r;
rollback;
