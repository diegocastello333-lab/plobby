-- =====================================================================================================================
-- Plobby · El club habitual viaja como id del catálogo:
--   · get_profile devuelve también habitual_club_id y el municipio del club (para enlazar a la página del club).
--   · save_onboarding_step(2) acepta 'club_id' (además del texto 'club', que sigue funcionando para apps antiguas).
-- Se parchean las funciones existentes (mismo patrón que 20261201a). No borra datos.
-- =====================================================================================================================
do $$
declare d text;
begin
  d := pg_get_functiondef('public.get_profile(uuid)'::regprocedure);
  if position('habitual_club_id' in d) = 0 then
    d := replace(d, $r$'habitual_club', p.habitual_club,$r$,
      $r$'habitual_club', p.habitual_club, 'habitual_club_id', p.habitual_club_id,
                                     'habitual_club_municipality', (select c.municipality from public.clubs c where c.id = p.habitual_club_id),$r$);
    if position('habitual_club_id' in d) = 0 then raise exception 'get_profile: patrón no encontrado'; end if;
    execute d;
  end if;

  d := pg_get_functiondef('public.save_onboarding_step(smallint, jsonb)'::regprocedure);
  if position('club_id' in d) = 0 then
    d := replace(d, $r$habitual_club = nullif(p_data->>'club',''),$r$,
      $r$habitual_club = nullif(p_data->>'club',''),
           habitual_club_id = case when coalesce(p_data->>'club_id', '') ~ '^[0-9a-f-]{36}$' then (p_data->>'club_id')::uuid else null end,$r$);
    if position('club_id' in d) = 0 then raise exception 'save_onboarding_step: patrón no encontrado'; end if;
    execute d;
  end if;
end $$;
revoke all on function public.get_profile(uuid), public.save_onboarding_step(smallint, jsonb) from public, anon;
grant execute on function public.get_profile(uuid), public.save_onboarding_step(smallint, jsonb) to authenticated;
