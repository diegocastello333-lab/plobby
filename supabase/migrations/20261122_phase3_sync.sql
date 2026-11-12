-- Plobby · Fase 3 (12 nov 2026): perfiles y grupos en tiempo real, presencia en el chat y banner de Inicio.
-- Todo el «tiempo real» nuevo usa Broadcast desde la base de datos a canales privados por usuario (`user:<uid>`, ya
-- autorizado por la política plobby_user_topic_read): llega solo a quien debe y no expone datos de otros.

-- ── 1) Foto, avatar o nombre de un jugador → aviso a quien lo muestra en pantalla ────────────────────────────────
-- Destinatarios: él mismo (sus otros dispositivos), sus amigos, quien comparte con él una conversación (grupos) y
-- quien comparte con él una liga (clasificaciones y partidos de liga).
create or replace function public._broadcast_profile() returns trigger
language plpgsql security definer set search_path = public as $$
declare r uuid; payload jsonb;
begin
  payload := jsonb_build_object('user_id', new.id, 'avatar_url', new.avatar_url, 'avatar_id', new.avatar_id,
                                'display_name', new.display_name, 'username', new.username);
  for r in
    select new.id
    union select f.friend_id from public.friendships f where f.user_id = new.id
    union select b.user_id from public.conversation_members a join public.conversation_members b on b.conversation_id = a.conversation_id where a.user_id = new.id
    union select b.user_id from public.league_members a join public.league_members b on b.league_id = a.league_id where a.user_id = new.id
  loop
    begin
      perform realtime.send(payload, 'profile', 'user:' || r, true);
    exception when others then null;   -- el aviso en vivo nunca debe impedir guardar el perfil
    end;
  end loop;
  return null;
end $$;
drop trigger if exists profiles_broadcast on public.profiles;
create trigger profiles_broadcast after update of avatar_url, avatar_id, display_name, username on public.profiles
  for each row when (old.avatar_url is distinct from new.avatar_url or old.avatar_id is distinct from new.avatar_id
                  or old.display_name is distinct from new.display_name or old.username is distinct from new.username)
  execute function public._broadcast_profile();

-- ── 2) Grupos: altas, bajas, roles y cambios de nombre/foto → aviso a TODOS los miembros (y a quien sale) ──────────
-- Antes se dependía de los DELETE de postgres_changes, que no pasan por RLS: llegaban a todos los clientes (con los
-- ids de conversación y usuario) o no llegaban según el estado del canal.
create or replace function public._broadcast_group() returns trigger
language plpgsql security definer set search_path = public as $$
declare conv uuid; affected uuid; r uuid;
begin
  if tg_table_name = 'conversations' then
    conv := new.id; affected := null;
  elsif tg_op = 'DELETE' then
    conv := old.conversation_id; affected := old.user_id;
  else
    conv := new.conversation_id; affected := new.user_id;
  end if;
  for r in select user_id from public.conversation_members where conversation_id = conv
           union select affected where affected is not null loop
    begin
      perform realtime.send(jsonb_build_object('conversation_id', conv, 'op', lower(tg_op), 'user_id', affected), 'group', 'user:' || r, true);
    exception when others then null;
    end;
  end loop;
  return null;
end $$;
drop trigger if exists conversation_members_broadcast on public.conversation_members;
create trigger conversation_members_broadcast after insert or delete or update on public.conversation_members
  for each row execute function public._broadcast_group();
drop trigger if exists conversations_broadcast on public.conversations;
create trigger conversations_broadcast after update of name, avatar_url, avatar_id on public.conversations
  for each row execute function public._broadcast_group();

-- La app ya no escucha estas tablas por postgres_changes (sus DELETE se emitían a todos los suscriptores).
do $$ begin
  if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'conversation_members') then
    alter publication supabase_realtime drop table public.conversation_members;
  end if;
  if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'conversations') then
    alter publication supabase_realtime drop table public.conversations;
  end if;
end $$;

-- ── 3) Presencia («En línea» / «Desconectado») con Realtime Presence ──────────────────────────────────────────────
-- Cada usuario publica su presencia SOLO en su canal `presence:<uid>`; sus amigos pueden escucharlo. El servidor la
-- retira sola al cortarse la conexión (heartbeat del socket), así que nadie se queda «en línea» por una sesión mal cerrada.
drop policy if exists plobby_presence_read on realtime.messages;
create policy plobby_presence_read on realtime.messages for select to authenticated
  using (realtime.messages.extension = 'presence' and (
    realtime.topic() = 'presence:' || auth.uid()::text
    or exists (select 1 from public.friendships f
                where f.user_id = auth.uid() and f.status = 'accepted' and realtime.topic() = 'presence:' || f.friend_id::text)));
drop policy if exists plobby_presence_write on realtime.messages;
create policy plobby_presence_write on realtime.messages for insert to authenticated
  with check (realtime.messages.extension = 'presence' and realtime.topic() = 'presence:' || auth.uid()::text);

-- ── 4) Banner de Inicio personalizable (persistente entre dispositivos) ───────────────────────────────────────────
alter table public.profiles add column if not exists banner_id text, add column if not exists banner_url text;
alter table public.profiles drop constraint if exists profiles_banner_id_chk;
alter table public.profiles add constraint profiles_banner_id_chk check (banner_id is null or banner_id ~ '^[a-z0-9_-]{1,32}$');
grant select (banner_id, banner_url) on public.profiles to authenticated;

-- Fija el banner: un predeterminado (id) o una foto propia subida a `avatars/<uid>/banner_*.jpg`. Ambos nulos = el
-- banner por defecto de Plobby.
create or replace function public.set_home_banner(p_banner_id text, p_banner_url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_banner_url is not null and p_banner_url not like '%/storage/v1/object/public/avatars/' || auth.uid()::text || '/banner\_%' then
    raise exception 'invalid_banner_url';
  end if;
  if p_banner_id is not null and p_banner_id !~ '^[a-z0-9_-]{1,32}$' then raise exception 'invalid_banner_id'; end if;
  update public.profiles set banner_id = case when p_banner_url is null then p_banner_id end,
                             banner_url = p_banner_url, updated_at = now()
   where id = auth.uid();
end $$;
revoke execute on function public.set_home_banner(text, text) from public, anon;
grant execute on function public.set_home_banner(text, text) to authenticated;

-- Las funciones de trigger no deben poder llamarse por RPC.
revoke execute on function public._broadcast_profile() from public, anon, authenticated;
revoke execute on function public._broadcast_group() from public, anon, authenticated;
