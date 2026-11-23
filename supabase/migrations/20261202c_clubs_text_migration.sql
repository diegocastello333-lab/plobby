-- =====================================================================================================================
-- Plobby · Migración del club escrito a mano (texto) al club del catálogo (id). Requiere 20261202a y 20261202b.
--   · profiles.home_club / habitual_club → home_club_id / habitual_club_id
--   · matches.club → matches.club_id
-- Se asigna SOLO si la mejor coincidencia de search_clubs es clara (confident: ≥ 0,9 y ≥ 0,2 por delante de la segunda).
-- Todo lo demás queda sin asignar y aparece en private.club_text_migration para revisarlo a mano.
-- Las columnas de texto NO se borran. Se puede repetir: solo toca filas aún sin id.
-- =====================================================================================================================
create table if not exists private.club_text_migration (
  id bigint generated always as identity primary key,
  entity text not null,            -- 'profile.home_club' | 'profile.habitual_club' | 'match.club'
  entity_id uuid not null,
  original_text text not null,
  best_club_id uuid, best_club text, best_score real,
  second_club text, second_score real,
  assigned boolean not null,
  created_at timestamptz not null default now()
);
revoke all on private.club_text_migration from public, anon, authenticated;

do $$
declare r record; b record; s record; ok boolean;
begin
  for r in
    select 'profile.home_club' e, id, home_club t from public.profiles where home_club_id is null and nullif(btrim(home_club), '') is not null
    union all
    select 'profile.habitual_club', id, habitual_club from public.profiles where habitual_club_id is null and nullif(btrim(habitual_club), '') is not null
    union all
    select 'match.club', id, club from public.matches where club_id is null and nullif(btrim(club), '') is not null
  loop
    select * into b from public.search_clubs(r.t, null, null, null, 2) limit 1;
    select * into s from public.search_clubs(r.t, null, null, null, 2) offset 1 limit 1;
    ok := coalesce(b.confident, false);
    if ok then
      if r.e = 'profile.home_club' then update public.profiles set home_club_id = b.id where id = r.id;
      elsif r.e = 'profile.habitual_club' then update public.profiles set habitual_club_id = b.id where id = r.id;
      else update public.matches set club_id = b.id where id = r.id; end if;
    end if;
    insert into private.club_text_migration (entity, entity_id, original_text, best_club_id, best_club, best_score, second_club, second_score, assigned)
      values (r.e, r.id, r.t, b.id, b.name, b.score, s.name, s.score, ok);
  end loop;
end $$;
