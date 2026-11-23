-- =====================================================================================================================
-- Plobby · «Club habitual» y «club base» son el MISMO dato (decisión del usuario, 23 nov 2026). La app usa solo
-- «Club habitual» (habitual_club_id); home_club_id se mantiene idéntico para la popularidad, la búsqueda y la página
-- del club. Si alguien guarda uno de los dos, el otro se copia (también desde versiones antiguas de la app).
-- Se ejecuta antes que profiles_club_guard (los triggers BEFORE van por orden alfabético). No borra datos.
-- =====================================================================================================================
create or replace function private.profiles_club_sync() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.home_club_id := coalesce(new.habitual_club_id, new.home_club_id);
    new.habitual_club_id := new.home_club_id;
  elsif new.habitual_club_id is distinct from old.habitual_club_id then
    new.home_club_id := new.habitual_club_id;
  elsif new.home_club_id is distinct from old.home_club_id then
    new.habitual_club_id := new.home_club_id;
  end if;
  return new;
end $$;
revoke all on function private.profiles_club_sync() from public, anon, authenticated;
drop trigger if exists profiles_club_a_sync on public.profiles;
create trigger profiles_club_a_sync before insert or update of home_club_id, habitual_club_id on public.profiles
  for each row execute function private.profiles_club_sync();

-- datos existentes: igualar las dos columnas
update public.profiles set home_club_id = habitual_club_id where habitual_club_id is not null and home_club_id is distinct from habitual_club_id;
update public.profiles set habitual_club_id = home_club_id where home_club_id is not null and habitual_club_id is null;
update public.clubs c set players_count = (select count(*) from public.profiles p where p.home_club_id = c.id);

-- el contador de jugadores también debe saltar cuando la app guarda solo habitual_club_id (home_club_id lo rellena el
-- trigger anterior, y un trigger «UPDATE OF columna» solo mira las columnas escritas en la sentencia)
drop trigger if exists profiles_club_count on public.profiles;
create trigger profiles_club_count after insert or delete or update of home_club_id, habitual_club_id on public.profiles
  for each row execute function private.profiles_club_count();
