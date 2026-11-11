-- Plobby · MATCH RECAP: lectura autorizada de un partido para generar la imagen.
-- NO EJECUTADO NI VALIDADO contra ninguna base de datos. Revisar antes de aplicar.
-- Depende de 20261115_match_lifecycle.sql. Solo LEE: no toca ELO, resultados, confirmaciones ni estadísticas.
--
-- Garantía en el SERVIDOR (no solo en la UI): devuelve datos únicamente si
--   · el partido está `confirmed`,
--   · los DOS capitanes han aceptado la versión de resultado VIGENTE (`matches.result_version`; si un procedimiento
--     administrativo la corrige, el recap refleja siempre la vigente),
--   · quien llama participa en el partido.
-- En otro caso lanza `recap_not_confirmed` / `recap_not_participant`, y la app no puede generar el Match Recap.

create or replace function public.get_match_recap(p_match_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.matches; v public.match_result_versions; caps int; res jsonb;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into m from public.matches where id = p_match_id;
  if not found then raise exception 'match_not_found'; end if;
  if not public._is_participant(p_match_id, auth.uid()) then raise exception 'recap_not_participant'; end if;
  if m.status <> 'confirmed' then raise exception 'recap_not_confirmed'; end if;

  select * into v from public.match_result_versions where match_id = p_match_id and version = m.result_version;
  if not found then raise exception 'recap_not_confirmed'; end if;

  select count(distinct a.team) into caps
    from public.match_result_acceptances a
    join public.match_players mp on mp.match_id = a.match_id and mp.user_id = a.user_id and mp.is_captain
   where a.match_id = p_match_id and a.version = m.result_version and a.decision = 'accepted';
  if caps < 2 then raise exception 'recap_not_confirmed'; end if;

  select jsonb_build_object(
    'match_id', m.id, 'status', m.status, 'result_version', m.result_version,
    'sets', v.sets, 'winner_team', v.winner_team,
    'club', m.club, 'court', m.court, 'played_at', coalesce(m.ended_at, m.scheduled_at, m.played_at),
    'duration_seconds', m.duration_seconds,
    'type', m.match_type, 'league_id', m.league_id,
    'league_name', (select l.name from public.leagues l where l.id = m.league_id),
    'players', (select jsonb_agg(jsonb_build_object(
        'user_id', mp.user_id, 'team', mp.team, 'is_captain', mp.is_captain, 'elo_delta', mp.elo_delta,
        'name', p.display_name, 'avatar_url', p.avatar_url, 'avatar_id', p.avatar_id) order by mp.team, mp.is_captain desc)
      from public.match_players mp join public.profiles p on p.id = mp.user_id where mp.match_id = m.id)
  ) into res;
  return res;
end $$;

revoke all on function public.get_match_recap(uuid) from public;
grant execute on function public.get_match_recap(uuid) to authenticated;
