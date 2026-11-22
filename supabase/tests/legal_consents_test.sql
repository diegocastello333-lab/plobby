-- Plobby · Pruebas de la Fase 8 (consentimientos). Siempre termina en ROLLBACK (raise).
do $$
declare a uuid := gen_random_uuid(); c uuid := gen_random_uuid(); k uuid := gen_random_uuid();
  res text[] := '{}'; n int; j jsonb; failed int;
begin
  insert into auth.users (id, email, raw_user_meta_data) values (a, 'lg_a@test.invalid', '{"full_name":"Ana Legal"}'),
    (c, 'lg_c@test.invalid', '{"full_name":"Cris Legal"}'), (k, 'lg_k@test.invalid', '{"full_name":"Kid Legal"}');
  update public.profiles set birth_date = current_date - interval '10 years' where id = k;

  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.7, 10.0.0.1"}', true);
  execute 'set local role authenticated';
  j := public.legal_status();
  res := res || format('Usuario nuevo: faltan Términos, Privacidad y edad: %s', not (j->>'required_ok')::boolean and jsonb_array_length(j->'pending') = 3);
  begin perform public.save_onboarding_step(1::smallint, '{"first_name":"Ana","last_name":"Legal","username":"ana_legal","city":"Madrid","birth_date":"1990-01-01"}');
        res := res || text 'Sin consentimiento no se guarda el perfil: false';
  exception when others then res := res || format('Sin consentimiento no se guarda el perfil: true (%s)', sqlerrm); end;
  begin perform public.complete_onboarding(); res := res || text 'Sin consentimiento no se completa el onboarding: false';
  exception when others then res := res || format('Sin consentimiento no se completa el onboarding: true (%s)', sqlerrm); end;
  begin perform public.accept_legal(true, true, false, false, 'android'); res := res || text 'Sin confirmar la edad no se acepta: false';
  exception when others then res := res || format('Sin confirmar la edad no se acepta: true (%s)', sqlerrm); end;
  begin perform public.accept_legal(true, false, true, false, 'android'); res := res || text 'Sin Privacidad no se acepta: false';
  exception when others then res := res || format('Sin Privacidad no se acepta: true (%s)', sqlerrm); end;
  j := public.accept_legal(true, true, true, false, 'android');
  res := res || format('Aceptar Términos + Privacidad + edad → completo: %s', (j->>'required_ok')::boolean and not (j->>'marketing')::boolean);
  select count(*) into n from public.user_consents where user_id = a and platform = 'android' and ip = '203.0.113.7' and revoked_at is null;
  res := res || format('Se registran 3 consentimientos con plataforma e IP: %s', n = 3);
  begin perform public.save_onboarding_step(1::smallint, '{"first_name":"Ana","last_name":"Legal","username":"ana_legal","city":"Madrid","birth_date":"1990-01-01"}');
        res := res || text 'Con consentimiento ya se guarda el perfil: true';
  exception when others then res := res || format('Con consentimiento ya se guarda el perfil: false (%s)', sqlerrm); end;
  perform public.set_marketing_consent(true, 'android');
  res := res || format('Marketing activado aparte: %s', (public.legal_status()->>'marketing')::boolean);
  perform public.set_marketing_consent(false, 'android');
  select count(*) into n from public.user_consents where user_id = a and doc_type = 'marketing' and revoked_at is not null;
  res := res || format('Retirar marketing lo marca como revocado (queda constancia): %s', n = 1 and not (public.legal_status()->>'marketing')::boolean);
  begin insert into public.user_consents (user_id, doc_type, version) values (a, 'terms', 1); res := res || text 'No se puede insertar consentimientos a mano: false';
  exception when others then res := res || format('No se puede insertar consentimientos a mano: true (%s)', sqlstate); end;
  begin update public.user_consents set accepted_at = now() - interval '1 year' where user_id = a; get diagnostics n = row_count;
        res := res || format('No se puede falsear la fecha: %s', n = 0);
  exception when others then res := res || format('No se puede falsear la fecha: true (%s)', sqlstate); end;
  begin update public.legal_documents set version = 9 where doc_type = 'terms'; get diagnostics n = row_count;
        res := res || format('El usuario no puede cambiar versiones: %s', n = 0);
  exception when others then res := res || format('El usuario no puede cambiar versiones: true (%s)', sqlstate); end;
  j := public.export_my_data();
  res := res || format('La exportación incluye los consentimientos: %s', jsonb_array_length(j->'consents') = 4);
  execute 'reset role';

  -- C no ve los consentimientos de A
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.user_consents where user_id = a; res := res || format('C no ve los consentimientos de A: %s', n = 0);
  execute 'reset role';

  -- menor de 14: no puede aceptar
  perform set_config('request.jwt.claims', json_build_object('sub', k, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin perform public.accept_legal(true, true, true, false, 'web'); res := res || text 'Menor de 14 años no puede aceptar: false';
  exception when others then res := res || format('Menor de 14 años no puede aceptar: true (%s)', sqlerrm); end;
  execute 'reset role';

  -- nueva versión de los Términos → hay que aceptarla otra vez
  update public.legal_documents set version = 2 where doc_type = 'terms';
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  j := public.legal_status();
  res := res || format('Nueva versión de Términos → pendiente de nuevo (y se sabe que ya aceptó antes): %s',
     not (j->>'required_ok')::boolean and jsonb_array_length(j->'pending') = 1 and (j->'pending'->0->>'doc_type') = 'terms' and (j->'pending'->0->>'previously_accepted')::boolean);
  j := public.accept_legal(true, true, true, false, 'ios');
  res := res || format('Al aceptar la v2 vuelve a estar completo: %s', (j->>'required_ok')::boolean);
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  execute 'set local role anon';
  begin perform public.legal_status(); res := res || text 'anon no consulta: false';
  exception when others then res := res || format('anon no consulta: true (%s)', sqlstate); end;
  begin perform count(*) from public.user_consents; res := res || text 'anon no lee consentimientos: false';
  exception when others then res := res || format('anon no lee consentimientos: true (%s)', sqlstate); end;
  execute 'reset role';
  select count(*) into n from public.audit_log where user_id = a and action in ('consent_given', 'consent_revoked'); res := res || format('audit_log registra aceptar y retirar: %s', n >= 3);

  select count(*) into failed from unnest(res) r where r ~ ': (f|false)( |$)';
  raise exception E'RESULTADO: %/% OK\n%', array_length(res, 1) - failed, array_length(res, 1), array_to_string(res, E'\n');
end $$;
