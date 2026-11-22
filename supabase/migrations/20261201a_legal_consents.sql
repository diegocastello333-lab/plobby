-- =====================================================================================================================
-- Plobby · Seguridad Fase 8 (22 nov 2026): aceptación de documentos legales y consentimientos.
--
--   · legal_documents: versión vigente de cada documento. Al publicar un texto nuevo se sube su `version` y la app pide
--     aceptarlo de nuevo antes de continuar (solo los `required`). Hoy todos están en v1 con texto PROVISIONAL (Fase 7).
--   · user_consents: registro de cada aceptación (usuario, documento, versión, fecha, plataforma, IP, revocación).
--     RLS: cada usuario solo LEE lo suyo. Solo se escribe con las RPC (que fijan la versión vigente y la hora del
--     servidor: no se puede «aceptar» una versión antigua ni falsear la fecha). Se conserva tras borrar la cuenta como
--     prueba del consentimiento (id seudónimo, sin otros datos).
--   · El servidor exige el consentimiento para CREAR el perfil: sin aceptar Términos + Privacidad + edad mínima no se
--     puede guardar el onboarding ni completarlo ('consent_required'). Editar un perfil ya creado no se bloquea, para no
--     romper la edición en versiones antiguas de la app; la app nueva pide aceptar antes de entrar.
-- Requiere 20261128a (audit_log, private.audit) y 20261130a (export_my_data). No borra datos.
-- =====================================================================================================================

create table if not exists public.legal_documents (
  doc_type text primary key check (doc_type in ('terms', 'privacy', 'cookies', 'community', 'legal_notice', 'deletion', 'age', 'marketing')),
  version integer not null check (version >= 1),
  title text not null check (char_length(title) <= 120),
  required boolean not null default false,      -- hay que aceptarlo para usar la app
  published_on date not null default current_date,
  updated_at timestamptz not null default now()
);
alter table public.legal_documents enable row level security;
drop policy if exists legal_documents_read on public.legal_documents;
create policy legal_documents_read on public.legal_documents for select to authenticated using (true);
revoke all on public.legal_documents from anon, authenticated;
grant select on public.legal_documents to authenticated;

insert into public.legal_documents (doc_type, version, title, required) values
  ('terms', 1, 'Términos y Condiciones de Uso', true),
  ('privacy', 1, 'Política de Privacidad', true),
  ('age', 1, 'Confirmación de edad mínima (14 años)', true),
  ('community', 1, 'Normas de la comunidad', false),
  ('cookies', 1, 'Política de Cookies', false),
  ('legal_notice', 1, 'Aviso Legal', false),
  ('deletion', 1, 'Eliminación de cuenta y datos', false),
  ('marketing', 1, 'Comunicaciones comerciales', false)
on conflict (doc_type) do nothing;

create table if not exists public.user_consents (
  id bigint generated always as identity primary key,
  user_id uuid not null,                 -- sin FK: el registro de consentimiento sobrevive al borrado de la cuenta
  doc_type text not null references public.legal_documents (doc_type),
  version integer not null,
  accepted_at timestamptz not null default now(),
  platform text not null default 'other' check (platform in ('android', 'ios', 'web', 'other')),
  ip text check (ip is null or char_length(ip) <= 64),
  revoked_at timestamptz
);
create index if not exists user_consents_user_idx on public.user_consents (user_id, doc_type, version);
alter table public.user_consents enable row level security;
drop policy if exists user_consents_read_own on public.user_consents;
create policy user_consents_read_own on public.user_consents for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.user_consents from anon, authenticated;
grant select on public.user_consents to authenticated;

-- ¿Tiene aceptada (y no revocada) la versión vigente de todos los documentos obligatorios?
create or replace function private.has_required_consents(p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (
    select 1 from public.legal_documents d
     where d.required
       and not exists (select 1 from public.user_consents c where c.user_id = p_uid and c.doc_type = d.doc_type
                        and c.version = d.version and c.revoked_at is null));
$$;
revoke all on function private.has_required_consents(uuid) from public, anon, authenticated;

create or replace function private.request_ip() returns text
language sql stable set search_path = '' as $$
  select left(nullif(btrim(split_part(coalesce((nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for'), ''), ',', 1)), ''), 64);
$$;
revoke all on function private.request_ip() from public, anon, authenticated;

-- Estado para la app: qué falta por aceptar y si tiene activas las comunicaciones comerciales
create or replace function public.legal_status() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when (select auth.uid()) is null then null else jsonb_build_object(
    'required_ok', private.has_required_consents((select auth.uid())),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('doc_type', d.doc_type, 'version', d.version, 'title', d.title,
                          'previously_accepted', exists (select 1 from public.user_consents c where c.user_id = (select auth.uid()) and c.doc_type = d.doc_type)))
                        from public.legal_documents d
                        where d.required and not exists (select 1 from public.user_consents c where c.user_id = (select auth.uid())
                              and c.doc_type = d.doc_type and c.version = d.version and c.revoked_at is null)), '[]'::jsonb),
    'marketing', exists (select 1 from public.user_consents c where c.user_id = (select auth.uid()) and c.doc_type = 'marketing' and c.revoked_at is null),
    'documents', (select jsonb_agg(jsonb_build_object('doc_type', d.doc_type, 'version', d.version, 'title', d.title, 'required', d.required,
                                                      'published_on', d.published_on) order by d.doc_type) from public.legal_documents d)
  ) end;
$$;
revoke all on function public.legal_status() from public, anon;
grant execute on function public.legal_status() to authenticated;

-- Aceptación: todos los obligatorios a la vez (Términos + Privacidad + edad) y, por separado, el marketing opcional.
create or replace function public.accept_legal(p_terms boolean, p_privacy boolean, p_age_confirmed boolean, p_marketing boolean, p_platform text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); plat text := case when p_platform in ('android', 'ios', 'web') then p_platform else 'other' end;
        ip text := private.request_ip(); d record;
begin
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not coalesce(p_terms, false) or not coalesce(p_privacy, false) then raise exception 'consent_required'; end if;
  if not coalesce(p_age_confirmed, false) then raise exception 'age_confirmation_required'; end if;
  if exists (select 1 from public.profiles where id = me and birth_date is not null and birth_date > current_date - interval '14 years') then
    raise exception 'too_young';
  end if;
  for d in select doc_type, version from public.legal_documents where required loop
    if not exists (select 1 from public.user_consents where user_id = me and doc_type = d.doc_type and version = d.version and revoked_at is null) then
      insert into public.user_consents (user_id, doc_type, version, platform, ip) values (me, d.doc_type, d.version, plat, ip);
    end if;
  end loop;
  perform public.set_marketing_consent(coalesce(p_marketing, false), plat);
  perform private.audit(me, 'consent_given', jsonb_build_object('platform', plat, 'marketing', coalesce(p_marketing, false)));
  return public.legal_status();
end $$;
revoke all on function public.accept_legal(boolean, boolean, boolean, boolean, text) from public, anon;
grant execute on function public.accept_legal(boolean, boolean, boolean, boolean, text) to authenticated;

-- Comunicaciones comerciales: casilla independiente; se puede retirar en cualquier momento (Ajustes)
create or replace function public.set_marketing_consent(p_accept boolean, p_platform text default 'other') returns boolean
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); v int; active boolean;
begin
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select version into v from public.legal_documents where doc_type = 'marketing';
  active := exists (select 1 from public.user_consents where user_id = me and doc_type = 'marketing' and revoked_at is null);
  if p_accept and not active then
    insert into public.user_consents (user_id, doc_type, version, platform, ip)
      values (me, 'marketing', v, case when p_platform in ('android', 'ios', 'web') then p_platform else 'other' end, private.request_ip());
  elsif not p_accept and active then
    update public.user_consents set revoked_at = now() where user_id = me and doc_type = 'marketing' and revoked_at is null;
    perform private.audit(me, 'consent_revoked', jsonb_build_object('doc_type', 'marketing'));
  end if;
  return p_accept;
end $$;
revoke all on function public.set_marketing_consent(boolean, text) from public, anon;
grant execute on function public.set_marketing_consent(boolean, text) to authenticated;

-- El servidor exige el consentimiento para crear/completar el perfil
do $$
declare d text;
begin
  d := pg_get_functiondef('public.save_onboarding_step(smallint, jsonb)'::regprocedure);
  if position('consent_required' in d) = 0 then
    d := replace(d, E'if uid is null then raise exception ''not_authenticated'' using errcode = ''28000''; end if;',
                    E'if uid is null then raise exception ''not_authenticated'' using errcode = ''28000''; end if;\n  -- crear el perfil (onboarding sin completar) exige el consentimiento; editarlo después no (la app pide la nueva versión)\n  if not private.has_required_consents(uid) and exists (select 1 from public.profiles where id = uid and onboarding_completed_at is null) then raise exception ''consent_required''; end if;');
    if position('consent_required' in d) = 0 then raise exception 'save_onboarding_step: patrón no encontrado'; end if;
    execute d;
  end if;
  d := pg_get_functiondef('public.complete_onboarding()'::regprocedure);
  if position('consent_required' in d) = 0 then
    d := replace(d, E'begin\n  if array_length(', E'begin\n  if not private.has_required_consents(auth.uid()) then raise exception ''consent_required''; end if;\n  if array_length(');
    if position('consent_required' in d) = 0 then raise exception 'complete_onboarding: patrón no encontrado'; end if;
    execute d;
  end if;
  -- la exportación incluye los consentimientos
  d := pg_get_functiondef('public.export_my_data()'::regprocedure);
  if position('''consents''' in d) = 0 then
    d := replace(d, E'    ''security_log'', coalesce(',
                    E'    ''consents'', coalesce((select jsonb_agg(jsonb_build_object(''doc_type'', c.doc_type, ''version'', c.version, ''accepted_at'', c.accepted_at, ''platform'', c.platform, ''revoked_at'', c.revoked_at) order by c.accepted_at)\n                        from public.user_consents c where c.user_id = me), ''[]''),\n    ''security_log'', coalesce(');
    if position('''consents''' in d) = 0 then raise exception 'export_my_data: patrón no encontrado'; end if;
    execute d;
  end if;
end $$;
revoke all on function public.save_onboarding_step(smallint, jsonb), public.complete_onboarding(), public.export_my_data() from public, anon;
grant execute on function public.save_onboarding_step(smallint, jsonb), public.complete_onboarding(), public.export_my_data() to authenticated;
