-- Plobby · 13 nov 2026: publicaciones automáticas con sentido deportivo (sin saturar el feed).
--  · «tournament»: campeones de un torneo (una por jugador campeón). Si se corrige la final y cambia el campeón, la
--    publicación anterior se retira.
--  · «streak»: rachas de victorias en hitos (3, 5, 10, 15, 20, 25), no en cada victoria.
--  · «elo»: nuevo récord personal de ELO al superar un múltiplo de 50 (1050, 1100…), una sola vez por hito.
-- Todo pasa por `emit_feed_event` (clave de deduplicación): nunca se publica dos veces lo mismo.

-- Racha actual de victorias confirmadas de un jugador (según los sets de cada partido, más reciente primero).
create or replace function public._win_streak(p_user uuid) returns int language plpgsql stable security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select (sum(case when s.team1_games > s.team2_games then 1 else 0 end) > sum(case when s.team2_games > s.team1_games then 1 else 0 end)) = (mp.team = 1) as won
      from public.rating_history rh
      join public.match_players mp on mp.match_id = rh.match_id and mp.user_id = rh.user_id
      join public.match_sets s on s.match_id = rh.match_id
     where rh.user_id = p_user
     group by rh.match_id, mp.team, rh.created_at
     order by rh.created_at desc
     limit 30
  loop
    exit when not r.won;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function public._win_streak(uuid) from public, anon, authenticated;

create or replace function public._feed_on_rating() returns trigger language plpgsql security definer set search_path = public as $$
declare n int;
begin
  n := public._win_streak(new.user_id);
  if n in (3, 5, 10, 15, 20, 25) then
    perform public.emit_feed_event(new.user_id, 'streak', 'streak:' || new.user_id || ':' || new.match_id, new.match_id, null, jsonb_build_object('count', n));
  end if;
  return new;
end $$;
revoke execute on function public._feed_on_rating() from public, anon, authenticated;
drop trigger if exists rating_history_feed on public.rating_history;
create trigger rating_history_feed after insert on public.rating_history for each row execute function public._feed_on_rating();

create or replace function public._feed_on_best_elo() returns trigger language plpgsql security definer set search_path = public as $$
declare step int := (new.best_elo / 50)::int * 50;
begin
  if new.best_elo > old.best_elo and (new.best_elo / 50)::int > (old.best_elo / 50)::int then
    perform public.emit_feed_event(new.user_id, 'elo', 'elo:' || new.user_id || ':' || step, null, null,
      jsonb_build_object('from', old.best_elo, 'to', new.best_elo, 'headline', 'Nuevo récord personal'));
  end if;
  return new;
end $$;
revoke execute on function public._feed_on_best_elo() from public, anon, authenticated;
drop trigger if exists player_ratings_feed on public.player_ratings;
create trigger player_ratings_feed after update of best_elo on public.player_ratings for each row execute function public._feed_on_best_elo();

create or replace function public._feed_on_tournament() returns trigger language plpgsql security definer set search_path = public as $$
declare t public.tournament_teams; n int;
begin
  -- Campeón retirado (final corregida o torneo reabierto): fuera su publicación.
  if old.status = 'finished' and old.champion_team_id is not null
     and (new.status <> 'finished' or new.champion_team_id is distinct from old.champion_team_id) then
    delete from public.feed_posts where dedupe_key like 'tchamp:' || old.id || ':%';
  end if;
  if new.status = 'finished' and new.champion_team_id is not null
     and (old.status <> 'finished' or new.champion_team_id is distinct from old.champion_team_id) then
    select * into t from public.tournament_teams where id = new.champion_team_id;
    if found then
      select count(*) into n from public.tournament_teams where tournament_id = new.id;
      perform public.emit_feed_event(t.player1_id, 'tournament', 'tchamp:' || new.id || ':' || t.player1_id, null, null,
        jsonb_build_object('tournament_id', new.id, 'name', new.name, 'partner_id', t.player2_id,
                           'partner_name', (select display_name from public.profiles where id = t.player2_id), 'teams', n));
      perform public.emit_feed_event(t.player2_id, 'tournament', 'tchamp:' || new.id || ':' || t.player2_id, null, null,
        jsonb_build_object('tournament_id', new.id, 'name', new.name, 'partner_id', t.player1_id,
                           'partner_name', (select display_name from public.profiles where id = t.player1_id), 'teams', n));
    end if;
  end if;
  return new;
end $$;
revoke execute on function public._feed_on_tournament() from public, anon, authenticated;
drop trigger if exists tournaments_feed on public.tournaments;
create trigger tournaments_feed after update of status, champion_team_id on public.tournaments for each row execute function public._feed_on_tournament();
