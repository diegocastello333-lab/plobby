-- Plobby · Pruebas del catálogo de clubes (20261202a/b/c). Siempre termina en ROLLBACK (raise al final).
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); adm uuid := gen_random_uuid();
  res text[] := '{}'; n int; j jsonb; top text; names text[]; pid uuid; pid2 uuid; t0 timestamptz; ms numeric; worst numeric := 0;
  failed int; q text;
  got text;
begin
  -- ── Búsqueda (sección 3) ──
  for q, top in select * from (values
      ('ciudad raqueta', 'BamVolea Ciudad de la Raqueta'), ('ciudad de la raqueta', 'BamVolea Ciudad de la Raqueta'),
      ('bamvolea raqueta', 'BamVolea Ciudad de la Raqueta'), ('club de campo', 'Real Club de Campo Villa de Madrid'),
      ('ccvm', 'Real Club de Campo Villa de Madrid'), ('club campo villa madrid', 'Real Club de Campo Villa de Madrid'),
      ('mirasierra', 'Club Mirasierra'), ('get indoor getafe', 'BamVolea Get Indoor'), ('mas padel', 'Club Maspadel'),
      ('maspadel', 'Club Maspadel'), ('race', 'Complejo Deportivo RACE'), ('rivapadel', 'Rivapadel Sport Club'),
      ('riva padel', 'Rivapadel Sport Club'), ('padel spirit vicalvaro', 'PadelSpirit Club'), ('lili alvarez', 'CDE Innova Moratalaz - Lili Álvarez'),
      ('LILI ÁLVAREZ', 'CDE Innova Moratalaz - Lili Álvarez'), ('clipadel', 'Clipadel'), ('club leganes indoor paddle', 'Clipadel')) v(q, top)
  loop
    got := (select x.name from public.search_clubs(q) x limit 1);
    res := res || format('«%s» → %s: %s%s', q, top, coalesce(got, '(nada)') = top, case when coalesce(got, '') <> top then ' (salió ' || coalesce(got, 'nada') || ')' else '' end);
  end loop;
  select array_agg(name order by rn) into names from (select name, row_number() over () rn from public.search_clubs('mirasierra')) x;
  res := res || format('«mirasierra»: Club Mirasierra delante de BamVolea y La Masó: %s',
    names[1] = 'Club Mirasierra' and not ('BamVolea Ciudad de la Raqueta' = any (names[1:1])) and not ('La Masó Sport Club' = any (names[1:1])));
  select array_agg(name) into names from public.search_clubs('puerta de hierro');
  res := res || format('«puerta de hierro» devuelve los tres sin confundirlos (%s): %s', array_to_string(names, ' | '),
    names @> array['Real Club Puerta de Hierro', 'Parque Deportivo Puerta de Hierro', 'Club Deportivo Puerta de Hierro Guisando']
    and not (select confident from public.search_clubs('puerta de hierro') limit 1));
  select array_agg(name) into names from public.search_clubs('moraleja');
  res := res || format('«moraleja» devuelve los cuatro y no elige a ciegas (%s): %s', array_to_string(names, ' | '),
    names @> array['La Moraleja Club de Pádel', 'Real Club La Moraleja', 'Club de Tenis La Moraleja', 'Euroindoor Moraleja']
    and not (select confident from public.search_clubs('moraleja') limit 1));
  select count(*) into n from public.search_clubs('zzqx wolfram kepler');
  res := res || format('Texto sin coincidencias → lista vacía: %s', n = 0);
  select count(*) into n from public.search_clubs('a');
  res := res || format('Menos de 2 caracteres → nada: %s', n = 0);
  res := res || format('«ccvm» es una coincidencia clara (sugerir «¿Te refieres a…?»): %s', (select confident from public.search_clubs('ccvm') limit 1));
  res := res || format('«ccvm» dice qué alias coincidió: %s', (select matched_alias from public.search_clubs('ccvm') limit 1) = 'CCVM');
  select count(*) into n from public.search_clubs('padel', types => array['municipal']) where type <> 'municipal';
  res := res || format('Filtro por tipos: %s', n = 0 and exists (select 1 from public.search_clubs('lili alvarez', types => array['municipal'])));
  res := res || format('normalize_club_name: «Real Club de Pádel La Moraleja» → «padel moraleja»: %s',
    public.normalize_club_name('Real Club de Pádel La Moraleja') = 'padel moraleja');
  res := res || format('Carga: 245 clubes verificados y 79 alias: %s',
    (select count(*) from public.clubs where source = 'seed_2026_11' and status = 'verified') = 245
    and (select count(*) from public.club_aliases a join public.clubs c on c.id = a.club_id where c.source = 'seed_2026_11') = 79);
  res := res || format('CP con ceros a la izquierda como texto y celdas vacías a NULL: %s',
    (select postal_code from public.clubs where slug = 'bamvolea-ciudad-de-la-raqueta') = '28049'
    and (select address is null and postal_code is null from public.clubs where slug = 'padel-hangar'));

  -- ── Usuarios de prueba ──
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
    (a, 'cl_a@test.invalid', '{"full_name":"Ana Club"}', '{}'), (b, 'cl_b@test.invalid', '{"full_name":"Bea Club"}', '{}'),
    (adm, 'cl_adm@test.invalid', '{"full_name":"Admin Club"}', '{"plobby_admin":true}');

  -- A: elige club base verificado y propone uno nuevo
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'app_metadata', '{}'::json)::text, true);
  execute 'set local role authenticated';
  update public.profiles set home_club_id = (select id from public.clubs where slug = 'club-mirasierra') where id = a;
  execute 'reset role';
  res := res || format('Club base guardado como id y el texto se sincroniza: %s',
    (select home_club from public.profiles where id = a) = 'Club Mirasierra');
  execute 'set local role authenticated';
  j := public.propose_club('Club de Campo', 'Madrid');
  res := res || format('Proponer un club que ya existe avisa de duplicado: %s', j ->> 'status' = 'duplicates');
  j := public.propose_club('Pádel Los Almendros Test', 'Getafe', 'private_club', 'C/ Falsa, 1');
  pid := (j ->> 'id')::uuid;
  res := res || format('Propuesta nueva creada como pending: %s', j ->> 'status' = 'created'
    and (select status = 'pending' and created_by = a from public.clubs where id = pid));
  update public.profiles set home_club_id = pid where id = a;
  execute 'reset role';
  res := res || format('El autor puede usar su propuesta al momento: %s', (select home_club_id from public.profiles where id = a) = pid);
  execute 'set local role authenticated';
  res := res || format('El autor encuentra su propuesta en la búsqueda: %s', exists (select 1 from public.search_clubs('almendros test') where id = pid));
  begin insert into public.clubs (name, municipality, type, status) values ('Club Verificado Trampa', 'Madrid', 'private_club', 'verified');
        res := res || format('Insertar directamente como verified se convierte en pending: %s',
          (select status from public.clubs where name = 'Club Verificado Trampa') = 'pending');
  exception when others then res := res || format('Insertar directamente como verified se rechaza: true (%s)', sqlstate); end;
  begin update public.clubs set status = 'verified' where id = pid; get diagnostics n = row_count;
        res := res || format('El usuario no puede verificar su propuesta: %s', n = 0);
  exception when others then res := res || format('El usuario no puede verificar su propuesta: true (%s)', sqlstate); end;
  begin delete from public.clubs where slug = 'club-mirasierra'; get diagnostics n = row_count;
        res := res || format('El usuario no puede borrar clubes: %s', n = 0);
  exception when others then res := res || format('El usuario no puede borrar clubes: true (%s)', sqlstate); end;
  begin insert into public.club_aliases (club_id, alias) values (pid, 'Alias Trampa'); res := res || text 'El usuario no puede añadir alias: false';
  exception when others then res := res || format('El usuario no puede añadir alias: true (%s)', sqlstate); end;
  begin perform public.admin_review_club(pid, 'approve'); res := res || text 'Un usuario normal no puede aprobar: false';
  exception when others then res := res || format('Un usuario normal no puede aprobar: true (%s)', sqlstate); end;
  for n in 1..4 loop
    begin perform public.propose_club('Club Spam Prueba ' || n || ' ' || md5(random()::text), 'Getafe', 'private_club', null, true);
    exception when others then null; end;
  end loop;
  begin perform public.propose_club('Club Spam Seis ' || md5(random()::text), 'Getafe', 'private_club', null, true);
        res := res || text 'Límite de 5 propuestas al día: false';
  exception when others then res := res || format('Límite de 5 propuestas al día: true (%s)', sqlerrm); end;
  execute 'reset role';

  -- B: no ve las propuestas pending de A ni puede usarlas
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated', 'app_metadata', '{}'::json)::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.clubs where id = pid;
  res := res || format('Otro usuario no ve la propuesta pending: %s', n = 0 and not exists (select 1 from public.search_clubs('almendros test')));
  begin update public.profiles set home_club_id = pid where id = b; res := res || text 'Otro usuario no puede usar una propuesta ajena: false';
  exception when others then res := res || format('Otro usuario no puede usar una propuesta ajena: true (%s)', sqlerrm); end;
  j := public.club_page((select id from public.clubs where slug = 'club-mirasierra'));
  res := res || format('Página del club verificado: datos, alias, ranking y ligas: %s', j -> 'club' ->> 'name' = 'Club Mirasierra' and j ? 'ranking' and j ? 'leagues');
  res := res || format('Página de una propuesta ajena: nada: %s', public.club_page(pid) is null);
  execute 'reset role';

  -- Admin: ve la cola, aprueba, fusiona
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'app_metadata', '{"plobby_admin":true}'::json)::text, true);
  execute 'set local role authenticated';
  j := public.admin_pending_clubs();
  res := res || format('Admin ve la cola de propuestas: %s', exists (select 1 from jsonb_array_elements(j) e where (e ->> 'id')::uuid = pid));
  perform public.admin_add_club_alias((select id from public.clubs where slug = 'real-club-la-moraleja'), 'RCGLM');
  perform public.admin_review_club(pid, 'merge', (select id from public.clubs where slug = 'bamvolea-get-indoor'), 'prueba');
  execute 'reset role';
  res := res || format('Fusión: el perfil de Ana pasa al club definitivo: %s',
    (select home_club_id from public.profiles where id = a) = (select id from public.clubs where slug = 'bamvolea-get-indoor'));
  res := res || format('Fusión: el nombre del fusionado queda como alias: %s',
    exists (select 1 from public.club_aliases x join public.clubs c on c.id = x.club_id where c.slug = 'bamvolea-get-indoor' and x.alias = 'Pádel Los Almendros Test'));
  res := res || format('Fusión: estado merged + merged_into: %s',
    (select status = 'merged' and merged_into is not null from public.clubs where id = pid));
  res := res || format('Fusión: contador de jugadores recalculado: %s',
    (select players_count from public.clubs where slug = 'bamvolea-get-indoor') = 1 and (select players_count from public.clubs where id = pid) = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated', 'app_metadata', '{}'::json)::text, true);
  execute 'set local role authenticated';
  res := res || format('Tras la fusión, buscar el nombre viejo lleva al club definitivo: %s',
    (select name from public.search_clubs('almendros test') limit 1) = 'BamVolea Get Indoor');
  res := res || format('Alias añadido por admin funciona («RCGLM» → Real Club La Moraleja): %s',
    (select name from public.search_clubs('rcglm') limit 1) = 'Real Club La Moraleja');
  execute 'reset role';
  select count(*) into n from public.audit_log where actor_id = adm and action = 'admin_action' and details ->> 'op' in ('club_merge', 'club_alias_added');
  res := res || format('Acciones de admin en audit_log: %s', n = 2);

  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  execute 'set local role anon';
  begin perform count(*) from public.clubs; res := res || text 'anon no lee clubes: false';
  exception when others then res := res || format('anon no lee clubes: true (%s)', sqlstate); end;
  begin perform public.search_clubs('moraleja'); res := res || text 'anon no busca: false';
  exception when others then res := res || format('anon no busca: true (%s)', sqlstate); end;
  execute 'reset role';

  -- ── Rendimiento con 10.000 clubes ──
  insert into public.clubs (slug, name, municipality, zone, type, status, source)
  select 'perf-' || i, initcap((array['Padel','Club','Arena','Indoor','Sport','Raqueta','Center','Smash','Volea','Bandeja'])[1 + i % 10]) || ' '
         || substr(md5(i::text), 1, 6) || ' ' || (array['Norte','Sur','Este','Oeste','Centro','Parque','Valle','Sierra'])[1 + i % 8],
         (array['Madrid','Getafe','Alcobendas','Leganés','Móstoles','Alcalá de Henares'])[1 + i % 6], 'madrid_capital', 'private_club', 'verified', 'perf'
    from generate_series(1, 10000 - 245) i;
  analyze public.clubs; analyze public.club_aliases;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated', 'app_metadata', '{}'::json)::text, true);
  execute 'set local role authenticated';
  foreach q in array array['ccvm', 'moraleja', 'puerta de hierro', 'padel spirit vicalvaro', 'ciudad raqueta', 'padel', 'zzqx wolfram'] loop
    perform public.search_clubs(q);   -- calentar
    t0 := clock_timestamp(); perform public.search_clubs(q); ms := extract(epoch from clock_timestamp() - t0) * 1000;
    worst := greatest(worst, ms);
    res := res || format('Rendimiento con 10.000 clubes «%s»: %s ms (< 50: %s)', q, round(ms, 1), ms < 50);
  end loop;
  execute 'reset role';
  res := res || format('Peor tiempo: %s ms', round(worst, 1));

  -- informe de la migración de textos (20261202c), si se ha ejecutado en esta transacción
  if to_regclass('private.club_text_migration') is not null then
    for q in select format('INFORME %s «%s» → %s (%s) · 2.º %s (%s) · %s', entity, original_text, coalesce(best_club, 'sin coincidencia'),
                           coalesce(best_score::text, '-'), coalesce(second_club, '-'), coalesce(second_score::text, '-'),
                           case when assigned then 'ASIGNADO' else 'PARA REVISAR' end) from private.club_text_migration order by id loop
      res := res || q;
    end loop;
  end if;
  select count(*) into failed from unnest(res) r where r ~ ': (f|false)([ )]|$)';
  raise exception E'RESULTADO: %/% OK\n%', array_length(res, 1) - failed, array_length(res, 1), array_to_string(res, E'\n');
end $$;
