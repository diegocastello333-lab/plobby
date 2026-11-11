-- Plobby · Tipo de partido (liga / amistoso) y creación unificada.
-- NO EJECUTADO NI VALIDADO contra ninguna base de datos. Revisar antes de aplicar.
--
-- No se ha podido inspeccionar el esquema real: si `matches` YA tiene un campo de tipo o de liga, REUTILÍZALO
-- (cambia los nombres de columna en este archivo y en create_match) en lugar de añadir los de abajo.
-- Supuestos: public.matches(id, confirmed_at, ...), public.match_players(match_id, user_id, team smallint),
--            public.match_sets(match_id, set_no, team1_games, team2_games), public.league_members(league_id, user_id),
--            public.leagues(id), public.friendships(user_id, friend_id, status).
-- NO toca ELO, estadísticas ni la validación de resultados: esas funciones/triggers existentes se siguen
-- ejecutando al confirmarse el partido (confirmed_at), igual que antes.

do $$ begin
  create type public.match_type as enum ('league', 'friendly');
exception when duplicate_object then null; end $$;

alter table public.matches
  add column if not exists match_type public.match_type not null default 'friendly',
  add column if not exists league_id uuid references public.leagues(id) on delete set null,
  add column if not exists played_at timestamptz,
  add column if not exists club text,
  add column if not exists created_by uuid references public.profiles(id);

-- Coherencia: liga ⇒ league_id obligatorio; amistoso ⇒ sin liga (los amistosos nunca aparecen en una liga).
alter table public.matches drop constraint if exists matches_type_league_chk;
alter table public.matches add constraint matches_type_league_chk
  check ((match_type = 'league' and league_id is not null) or (match_type = 'friendly' and league_id is null)) not valid;
-- `not valid`: no revisa filas antiguas. Backfill sugerido antes de `validate constraint`:
--   update public.matches set match_type = 'league' where league_id is not null;  -- y friendly para el resto
create index if not exists matches_league_idx on public.matches (league_id, played_at desc) where league_id is not null;

-- RLS: un usuario crea partidos solo mediante create_match(); no hay insert directo desde el cliente.
alter table public.matches enable row level security;
-- (Las policies de SELECT existentes se mantienen. Un amistoso es visible solo para sus jugadores y sus amigos.)

alter table public.match_players add column if not exists is_captain boolean not null default false;   -- (la restricción de un capitán por equipo se añade en 20261115)

create or replace function public.create_match(
  p_type text, p_league_id uuid, p_partner uuid, p_rival1 uuid, p_rival2 uuid,
  p_when timestamptz, p_club text, p_sets int[][] default '{}'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); mid uuid; pl uuid[]; u uuid; i int; n int;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if p_type not in ('league', 'friendly') then raise exception 'invalid match type'; end if;
  pl := array[p_partner, p_rival1, p_rival2];
  if p_partner is null or p_rival1 is null or p_rival2 is null or cardinality(array(select distinct x from unnest(pl) x)) < 3 or me = any(pl) then
    raise exception 'three different players required';
  end if;

  if p_type = 'league' then
    if p_league_id is null then raise exception 'league required'; end if;
    -- el creador y los otros tres deben ser miembros de la liga
    foreach u in array array[me, p_partner, p_rival1, p_rival2] loop
      if not exists (select 1 from public.league_members where league_id = p_league_id and user_id = u) then
        raise exception 'player % is not a member of the league', u;
      end if;
    end loop;
  else
    if p_league_id is not null then raise exception 'friendly matches cannot have a league'; end if;
    -- amistoso: solo con amigos aceptados
    foreach u in array pl loop
      if not exists (select 1 from public.friendships where user_id = me and friend_id = u and status = 'accepted') then
        raise exception 'player % is not your friend', u;
      end if;
    end loop;
  end if;

  insert into public.matches (match_type, league_id, played_at, club, created_by)
  values (p_type::public.match_type, p_league_id, p_when, p_club, me) returning id into mid;
  -- capitanes: el creador (equipo 1) y el primer rival (equipo 2). Los confirman/disputan el resultado (20261115).
  insert into public.match_players (match_id, user_id, team, is_captain) values (mid, me, 1, true), (mid, p_partner, 1, false), (mid, p_rival1, 2, true), (mid, p_rival2, 2, false);

  n := coalesce(array_length(p_sets, 1), 0);
  for i in 1..n loop
    -- mismas reglas de set que el flujo existente (6-0..6-4, 7-5, 7-6); la validación definitiva sigue siendo la existente
    if not ((greatest(p_sets[i][1], p_sets[i][2]) = 6 and least(p_sets[i][1], p_sets[i][2]) <= 4)
         or (greatest(p_sets[i][1], p_sets[i][2]) = 7 and least(p_sets[i][1], p_sets[i][2]) in (5, 6))) then
      raise exception 'invalid set %', i;
    end if;
    insert into public.match_sets (match_id, set_no, team1_games, team2_games) values (mid, i, p_sets[i][1], p_sets[i][2]);
  end loop;
  if n = 1 then raise exception 'at least two sets required'; end if;

  -- confirmed_at queda NULL: el partido no cuenta para ELO/estadísticas/racha hasta que lo confirmen los rivales
  -- (sistema de confirmación existente). Avisamos a los otros jugadores.
  foreach u in array pl loop
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, dedupe_key, title)
    values (u, me, case when n > 0 and u in (p_rival1, p_rival2) then 'match_confirmation_required' else 'play_invite' end::notification_type,
            mid, 'mc:' || mid || ':' || u, case when n > 0 then 'Confirma el resultado' else 'Te invita a jugar' end)
    on conflict do nothing;
  end loop;
  return mid;
end $$;
revoke all on function public.create_match(text, uuid, uuid, uuid, uuid, timestamptz, text, int[][]) from public, anon;
grant execute on function public.create_match(text, uuid, uuid, uuid, uuid, timestamptz, text, int[][]) to authenticated;

-- Las pantallas de liga deben filtrar por tipo: `where match_type = 'league' and league_id = :id`;
-- el feed/perfil de amistosos usa `match_type = 'friendly'`.
