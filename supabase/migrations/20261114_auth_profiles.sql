-- Plobby · Acceso con Google (Supabase Auth) + perfil / onboarding.
-- NO EJECUTADO NI VALIDADO contra ninguna base de datos. Revisar antes de aplicar.
--
-- Supuesto: existe public.profiles(id uuid pk → auth.users.id, display_name, username, avatar_url, city, ...)
-- (lo usan las migraciones anteriores). Aquí solo se AÑADE lo que falta; si alguna columna ya existe con otro
-- nombre, reutilízala y cambia el nombre en este archivo.
--
-- Una cuenta Google = un único usuario: Supabase Auth guarda una fila en auth.users por identidad/email
-- (con «automatic linking» por email verificado). profiles.id = auth.users.id, así que volver a entrar con
-- Google RECUPERA el mismo perfil y nunca crea uno duplicado (el trigger usa ON CONFLICT DO NOTHING).

alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists birth_date date,
  add column if not exists self_declared_level text,                 -- lo declara el jugador; NO es el ELO
  add column if not exists court_side text,                          -- 'right' (derecha) | 'left' (revés)
  add column if not exists dominant_hand text,                       -- 'right' | 'left'
  add column if not exists habitual_club text,
  add column if not exists habitual_partner_id uuid references public.profiles(id) on delete set null,
  add column if not exists avatar_id text,                           -- id de avatar predefinido (a1..a12) cuando no hay foto
  add column if not exists onboarding_step smallint not null default 1,
  add column if not exists onboarding_completed_at timestamptz;

alter table public.profiles drop constraint if exists profiles_level_chk;
alter table public.profiles add constraint profiles_level_chk
  check (self_declared_level is null or self_declared_level in ('beginner','intermediate','upper_intermediate','advanced'));
alter table public.profiles drop constraint if exists profiles_side_chk;
alter table public.profiles add constraint profiles_side_chk check (court_side is null or court_side in ('right','left'));
alter table public.profiles drop constraint if exists profiles_hand_chk;
alter table public.profiles add constraint profiles_hand_chk check (dominant_hand is null or dominant_hand in ('right','left'));
alter table public.profiles drop constraint if exists profiles_username_fmt_chk;
alter table public.profiles add constraint profiles_username_fmt_chk
  check (username is null or username ~ '^[a-z0-9._]{3,24}$') not valid;   -- `not valid`: no revisa filas antiguas
alter table public.profiles drop constraint if exists profiles_avatar_id_chk;
alter table public.profiles add constraint profiles_avatar_id_chk check (avatar_id is null or avatar_id ~ '^a([1-9]|1[0-2])$');

-- Nombre de usuario único sin distinguir mayúsculas.
create unique index if not exists profiles_username_ci_uq on public.profiles (lower(username)) where username is not null;

-- ---------------------------------------------------------------------------------------------
-- 1) Un perfil por usuario de Auth (se crea al primer acceso con Google; idempotente).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, first_name, last_name, display_name)
  values (new.id,
          nullif(new.raw_user_meta_data->>'given_name',''),
          nullif(new.raw_user_meta_data->>'family_name',''),
          coalesce(nullif(coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),''), split_part(coalesce(new.email,''),'@',1)))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------------------------
-- 2) Disponibilidad de username en tiempo real (no expone otros datos).
create or replace function public.is_username_available(p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_username ~ '^[a-z0-9._]{3,24}$'
     and not exists (select 1 from public.profiles where lower(username) = lower(p_username) and id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'));
$$;

-- 3) Pasos de onboarding PENDIENTES (usuarios existentes solo ven lo que les falta). Fuente de verdad: servidor.
create or replace function public.onboarding_pending_steps() returns smallint[]
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; s smallint[] := '{}';
begin
  select * into p from public.profiles where id = auth.uid();
  if not found then return array[1,2,3,4]::smallint[]; end if;
  if p.first_name is null or p.last_name is null or p.username is null or p.city is null or p.birth_date is null then s := s || 1::smallint; end if;
  if p.self_declared_level is null or p.court_side is null or p.dominant_hand is null then s := s || 2::smallint; end if;
  if p.avatar_url is null and p.avatar_id is null then s := s || 3::smallint; end if;
  if p.onboarding_completed_at is null then s := s || 4::smallint; end if;
  return s;
end $$;

-- 4) Guardado por pasos (reanudable). Valida en servidor; solo escribe la fila del propio usuario.
create or replace function public.save_onboarding_step(p_step smallint, p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_step = 1 then
    if coalesce(length(trim(p_data->>'first_name')),0) < 2 or coalesce(length(trim(p_data->>'last_name')),0) < 2 then raise exception 'invalid_name'; end if;
    if not public.is_username_available(lower(p_data->>'username')) then raise exception 'username_taken'; end if;
    if (p_data->>'birth_date')::date > (current_date - interval '14 years') then raise exception 'too_young'; end if;
    update public.profiles set first_name = trim(p_data->>'first_name'), last_name = trim(p_data->>'last_name'),
           username = lower(p_data->>'username'), city = trim(p_data->>'city'), birth_date = (p_data->>'birth_date')::date,
           display_name = trim(p_data->>'first_name') || ' ' || trim(p_data->>'last_name')
     where id = uid;
  elsif p_step = 2 then
    -- nivel DECLARADO: nunca toca player_ratings / ELO
    update public.profiles set self_declared_level = p_data->>'level', court_side = p_data->>'side', dominant_hand = p_data->>'hand',
           habitual_club = nullif(p_data->>'club',''), habitual_partner_id = nullif(p_data->>'partner_id','')::uuid
     where id = uid;
  elsif p_step = 3 then
    update public.profiles set avatar_url = nullif(p_data->>'avatar_url',''), avatar_id = nullif(p_data->>'avatar_id','') where id = uid;
  else raise exception 'invalid_step'; end if;
  update public.profiles set onboarding_step = greatest(onboarding_step, p_step + 1) where id = uid;
end $$;

create or replace function public.complete_onboarding() returns void
language plpgsql security definer set search_path = public as $$
begin
  if array_length(array(select unnest(public.onboarding_pending_steps()) except select 4), 1) is not null then raise exception 'onboarding_incomplete'; end if;
  update public.profiles set onboarding_completed_at = coalesce(onboarding_completed_at, now()) where id = auth.uid();
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5) RLS de perfiles: cada usuario solo modifica SU fila. (Si ya tienes políticas equivalentes, elimina estas.)
alter table public.profiles enable row level security;
drop policy if exists profiles_select_auth on public.profiles;
create policy profiles_select_auth on public.profiles for select to authenticated using (true);   -- perfiles visibles para usuarios con sesión
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles for insert to authenticated with check (id = auth.uid());

-- 6) Storage de avatares: bucket público de lectura; cada usuario escribe solo en su carpeta `<uid>/…`.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects for select using (bucket_id = 'avatars');
drop policy if exists avatars_write_own on storage.objects;
create policy avatars_write_own on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatars_update_own on storage.objects;
create policy avatars_update_own on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatars_delete_own on storage.objects;
create policy avatars_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

revoke all on function public.is_username_available(text), public.onboarding_pending_steps(), public.save_onboarding_step(smallint, jsonb), public.complete_onboarding() from public;
grant execute on function public.is_username_available(text), public.onboarding_pending_steps(), public.save_onboarding_step(smallint, jsonb), public.complete_onboarding() to authenticated;
