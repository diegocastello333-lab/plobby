-- Plobby · Mensajería: grupos + tarjetas de resultado de partido en cualquier chat.
-- NO EJECUTADO NI VALIDADO contra ninguna base de datos. Revisar antes de aplicar.
-- Depende de 20261112_home_social.sql (conversations, conversation_members, messages, friendships, notifications),
-- 20261115_match_lifecycle.sql y 20261116_match_recap.sql (get_match_recap).
--
-- Reglas que aplica el SERVIDOR (no solo la UI):
--  · grupos con id único (uuid) y persistencia; todos los miembros leen el mismo historial (RLS por membresía);
--  · solo administradores editan nombre/foto, añaden/quitan miembros y nombran admins; todo miembro puede abandonar;
--  · un grupo nunca se queda sin admin: si se va el último, se promueve al miembro más antiguo; sin miembros → se elimina;
--  · crear grupo / añadir: solo AMIGOS ACEPTADOS del que actúa (igual que el chat 1:1);
--  · la tarjeta de partido (send_match_card) solo existe si el partido está CONFIRMADO por los dos capitanes y quien
--    comparte JUEGA en él (reutiliza get_match_recap). El resultado sale de la BD, no del cliente, y se guarda como
--    snapshot en messages.payload: la tarjeta se conserva aunque el partido sea antiguo. `ref_id` enlaza al partido vivo.
--
-- ⚠ Notas de integración:
--  · `notifications.notification_type` puede tener un CHECK: añade 'group_message' y 'group_added' si es así.

alter type public.notification_type add value if not exists 'group_added';
alter type public.notification_type add value if not exists 'group_message';
--  · En grupos `messages.read_at` NO sirve (es un único flag): el no-leído se calcula con conversation_members.last_read_at.
--  · Corrige dos efectos laterales que habrían roto los grupos: get_or_create_conversation y on_friend_removed
--    operaban sobre CUALQUIER conversación compartida; ahora solo sobre las `direct`.

-- ============================================================ 1. Esquema
alter table public.conversations
  add column if not exists kind text not null default 'direct' check (kind in ('direct','group')),
  add column if not exists name text check (name is null or length(btrim(name)) between 1 and 60),
  add column if not exists avatar_url text,
  add column if not exists avatar_id text,                    -- imagen predeterminada (id de catálogo)
  add column if not exists created_by uuid references public.profiles(id) on delete set null;

alter table public.conversation_members
  add column if not exists role text not null default 'member' check (role in ('member','admin')),
  add column if not exists joined_at timestamptz not null default now();

alter table public.messages add column if not exists payload jsonb;           -- snapshot de la tarjeta de partido
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind in ('text','invite','match','league','profile','system'));
create index if not exists messages_conv_created_idx on public.messages (conversation_id, created_at);

-- ============================================================ 2. Helpers
create or replace function public.is_group_admin(conv uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_members m join public.conversations c on c.id = m.conversation_id
                  where m.conversation_id = conv and m.user_id = auth.uid() and m.role = 'admin' and c.kind = 'group');
$$;
create or replace function public._is_friend(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships where user_id = a and friend_id = b and status = 'accepted');
$$;
create or replace function public._system_msg(conv uuid, txt text) returns void language sql security definer set search_path = public as $$
  with m as (insert into public.messages (conversation_id, sender_id, kind, body) values (conv, auth.uid(), 'system', left(txt, 200)) returning created_at)
  update public.conversations set last_message_at = (select created_at from m) where id = conv;
$$;

-- ============================================================ 3. Grupos
create or replace function public.create_group(p_name text, p_member_ids uuid[], p_avatar_id text default null, p_avatar_url text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; u uuid; ids uuid[]; nm text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if length(nm) < 1 or length(nm) > 60 then raise exception 'invalid_group_name'; end if;
  select coalesce(array_agg(distinct x), '{}') into ids from unnest(coalesce(p_member_ids, '{}')) x where x <> auth.uid();
  if coalesce(array_length(ids, 1), 0) < 1 then raise exception 'group_needs_members'; end if;
  if array_length(ids, 1) > 49 then raise exception 'group_too_large'; end if;
  foreach u in array ids loop
    if not public._is_friend(auth.uid(), u) then raise exception 'only_friends_allowed'; end if;
  end loop;
  insert into public.conversations (kind, name, avatar_id, avatar_url, created_by) values ('group', nm, p_avatar_id, p_avatar_url, auth.uid()) returning id into cid;
  insert into public.conversation_members (conversation_id, user_id, role) values (cid, auth.uid(), 'admin');
  insert into public.conversation_members (conversation_id, user_id) select cid, x from unnest(ids) x;
  perform public._system_msg(cid, 'creó el grupo «' || nm || '»');
  insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
    select x, auth.uid(), 'group_added', cid, 'Te han añadido a un grupo', nm, 'ga:' || cid || ':' || x from unnest(ids) x on conflict do nothing;
  return cid;
end $$;

-- p_patch: {"name": "...", "avatar_id": "...", "avatar_url": "..."}; solo se tocan las claves presentes.
create or replace function public.update_group(conv uuid, p_patch jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if not public.is_group_admin(conv) then raise exception 'not_group_admin'; end if;
  if p_patch ? 'name' then
    nm := btrim(coalesce(p_patch->>'name', ''));
    if length(nm) < 1 or length(nm) > 60 then raise exception 'invalid_group_name'; end if;
    update public.conversations set name = nm where id = conv;
    perform public._system_msg(conv, 'cambió el nombre a «' || nm || '»');
  end if;
  if p_patch ? 'avatar_id' or p_patch ? 'avatar_url' then
    update public.conversations set avatar_id = case when p_patch ? 'avatar_id' then p_patch->>'avatar_id' else avatar_id end,
                                   avatar_url = case when p_patch ? 'avatar_url' then p_patch->>'avatar_url' else avatar_url end where id = conv;
    perform public._system_msg(conv, 'cambió la foto del grupo');
  end if;
end $$;

create or replace function public.add_group_members(conv uuid, p_member_ids uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid; n int; gname text;
begin
  if not public.is_group_admin(conv) then raise exception 'not_group_admin'; end if;
  select count(*) into n from public.conversation_members where conversation_id = conv;
  if n + coalesce(array_length(p_member_ids, 1), 0) > 50 then raise exception 'group_too_large'; end if;
  select name into gname from public.conversations where id = conv;
  foreach u in array coalesce(p_member_ids, '{}') loop
    if not public._is_friend(auth.uid(), u) then raise exception 'only_friends_allowed'; end if;
    insert into public.conversation_members (conversation_id, user_id) values (conv, u) on conflict do nothing;
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
      values (u, auth.uid(), 'group_added', conv, 'Te han añadido a un grupo', gname, 'ga:' || conv || ':' || u) on conflict do nothing;
  end loop;
  perform public._system_msg(conv, 'añadió participantes');
end $$;

create or replace function public.remove_group_member(conv uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(conv) then raise exception 'not_group_admin'; end if;
  if p_user = auth.uid() then raise exception 'use_leave_group'; end if;
  if exists (select 1 from public.conversation_members where conversation_id = conv and user_id = p_user and role = 'admin') then
    raise exception 'demote_admin_first';            -- un admin no puede expulsar a otro admin sin degradarlo antes
  end if;
  delete from public.conversation_members where conversation_id = conv and user_id = p_user;
  perform public._system_msg(conv, 'quitó a un participante');
end $$;

create or replace function public.set_group_admin(conv uuid, p_user uuid, p_admin boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(conv) then raise exception 'not_group_admin'; end if;
  if not p_admin and (select count(*) from public.conversation_members where conversation_id = conv and role = 'admin') <= 1 then
    raise exception 'last_admin';                    -- siempre debe quedar un admin
  end if;
  update public.conversation_members set role = case when p_admin then 'admin' else 'member' end where conversation_id = conv and user_id = p_user;
  if not found then raise exception 'not_a_member'; end if;
end $$;

create or replace function public.leave_group(conv uuid) returns void
language plpgsql security definer set search_path = public as $$
declare was_admin boolean; next_admin uuid;
begin
  if not exists (select 1 from public.conversations where id = conv and kind = 'group') then raise exception 'not_a_group'; end if;
  select role = 'admin' into was_admin from public.conversation_members where conversation_id = conv and user_id = auth.uid();
  if was_admin is null then raise exception 'not a member'; end if;
  perform public._system_msg(conv, 'abandonó el grupo');
  delete from public.conversation_members where conversation_id = conv and user_id = auth.uid();
  if not exists (select 1 from public.conversation_members where conversation_id = conv) then
    delete from public.conversations where id = conv;                      -- sin miembros: se elimina (cascade a mensajes)
  elsif was_admin and not exists (select 1 from public.conversation_members where conversation_id = conv and role = 'admin') then
    select user_id into next_admin from public.conversation_members where conversation_id = conv order by joined_at, user_id limit 1;
    update public.conversation_members set role = 'admin' where conversation_id = conv and user_id = next_admin;
  end if;
end $$;

-- ============================================================ 4. Envío (directo y grupo)
create or replace function public._post_message(conv uuid, p_kind text, p_body text, p_ref text, p_payload jsonb) returns public.messages
language plpgsql security definer set search_path = public as $$
declare m public.messages; c public.conversations; other uuid;
begin
  if not public.is_member(conv) then raise exception 'not a member'; end if;
  select * into c from public.conversations where id = conv;
  if c.kind = 'direct' then
    select user_id into other from public.conversation_members where conversation_id = conv and user_id <> auth.uid();
    if not public._is_friend(auth.uid(), other) then raise exception 'not friends'; end if;
  end if;
  insert into public.messages (conversation_id, sender_id, kind, body, ref_id, payload)
    values (conv, auth.uid(), p_kind, left(coalesce(p_body, ''), 500), p_ref, p_payload) returning * into m;
  update public.conversations set last_message_at = m.created_at where id = conv;
  if c.kind = 'direct' and p_kind = 'invite' then
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
    values (other, auth.uid(), 'play_invite', conv, 'Te invita a jugar', left(p_body, 120), 'pi:' || m.id) on conflict do nothing;
  elsif c.kind = 'group' then
    -- una sola notificación pendiente por grupo y persona (se borra al leer) → sin spam
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
      select cm.user_id, auth.uid(), 'group_message', conv, c.name, left(case when p_kind = 'match' then 'Compartió un resultado' else p_body end, 120), 'gm:' || conv || ':' || cm.user_id
        from public.conversation_members cm where cm.conversation_id = conv and cm.user_id <> auth.uid() on conflict do nothing;
  end if;
  return m;
end $$;

create or replace function public.send_message(conv uuid, body_in text, kind_in text default 'text', ref_in text default null) returns public.messages
language plpgsql security definer set search_path = public as $$
begin
  if kind_in in ('match', 'system') then raise exception 'use_dedicated_function'; end if;   -- el cliente no fabrica tarjetas ni mensajes de sistema
  return public._post_message(conv, kind_in, body_in, ref_in, null);
end $$;

create or replace function public.send_match_card(conv uuid, p_match_id uuid) returns public.messages
language plpgsql security definer set search_path = public as $$
declare r jsonb; sets jsonb; body text;
begin
  r := public.get_match_recap(p_match_id);                    -- lanza recap_not_confirmed / recap_not_participant
  select string_agg((s->>0) || '-' || (s->>1), ' ' order by o) into body from jsonb_array_elements(r->'sets') with ordinality as t(s, o);
  return public._post_message(conv, 'match', coalesce(body, ''), p_match_id::text, r);
end $$;

create or replace function public.mark_conversation_read(conv uuid) returns void
language sql security definer set search_path = public as $$
  with u as (update public.conversation_members set last_read_at = now() where conversation_id = conv and user_id = auth.uid() returning 1),
       n as (delete from public.notifications where recipient_user_id = auth.uid() and dedupe_key = 'gm:' || conv || ':' || auth.uid() returning 1)
  update public.messages set read_at = now() where conversation_id = conv and sender_id <> auth.uid() and read_at is null and public.is_member(conv)
     and exists (select 1 from public.conversations c where c.id = conv and c.kind = 'direct');
$$;

-- ============================================================ 5. Correcciones de efectos laterales sobre 1:1
create or replace function public.get_or_create_conversation(friend uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if not public._is_friend(auth.uid(), friend) then raise exception 'only accepted friends can chat'; end if;
  select a.conversation_id into cid from public.conversation_members a
    join public.conversation_members b on a.conversation_id = b.conversation_id
    join public.conversations c on c.id = a.conversation_id and c.kind = 'direct'
   where a.user_id = auth.uid() and b.user_id = friend limit 1;
  if cid is null then
    insert into public.conversations (kind) values ('direct') returning id into cid;
    insert into public.conversation_members (conversation_id, user_id) values (cid, auth.uid()), (cid, friend);
  end if;
  return cid;
end $$;

create or replace function public.on_friend_removed() returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- solo se cierra la conversación PRIVADA; dejar de ser amigos no expulsa de grupos compartidos
  delete from public.conversation_members cm
   where cm.user_id in (old.user_id, old.friend_id)
     and cm.conversation_id in (select a.conversation_id from public.conversation_members a
        join public.conversation_members b on a.conversation_id = b.conversation_id
        join public.conversations c on c.id = a.conversation_id and c.kind = 'direct'
       where a.user_id = old.user_id and b.user_id = old.friend_id);
  return old;
end $$;

-- ============================================================ 6. Vistas
drop view if exists public.v_my_conversations;
create view public.v_my_conversations with (security_invoker = true) as
select c.id as conversation_id, c.kind, c.last_message_at,
       c.name as group_name, c.avatar_url as group_avatar_url, c.avatar_id as group_avatar_id,
       (select count(*) from public.conversation_members x where x.conversation_id = c.id)::int as member_count,
       o.user_id as other_id, p.display_name as other_name, p.username as other_username, p.avatar_url as other_avatar,
       pr.elo as other_elo, public.rating_level(pr.elo) as other_level,
       lm.body as last_body, lm.kind as last_kind, lm.sender_id as last_sender, lp.display_name as last_sender_name,
       (select count(*) from public.messages x where x.conversation_id = c.id and x.sender_id <> auth.uid() and x.kind <> 'system'
           and x.created_at > me.last_read_at)::int as unread
from public.conversations c
join public.conversation_members me on me.conversation_id = c.id and me.user_id = auth.uid()
left join public.conversation_members o on o.conversation_id = c.id and o.user_id <> auth.uid() and c.kind = 'direct'
left join public.profiles p on p.id = o.user_id
left join public.player_ratings pr on pr.user_id = o.user_id
left join lateral (select body, kind, sender_id from public.messages where conversation_id = c.id order by created_at desc limit 1) lm on true
left join public.profiles lp on lp.id = lm.sender_id;

create or replace view public.v_group_members with (security_invoker = true) as
select m.conversation_id, m.user_id, m.role, m.joined_at, p.display_name, p.username, p.avatar_url, p.avatar_id
from public.conversation_members m join public.profiles p on p.id = m.user_id;

-- ============================================================ 7. Permisos y realtime
revoke all on function public.create_group(text, uuid[], text, text), public.update_group(uuid, jsonb), public.add_group_members(uuid, uuid[]),
  public.remove_group_member(uuid, uuid), public.set_group_admin(uuid, uuid, boolean), public.leave_group(uuid), public.send_match_card(uuid, uuid),
  public._post_message(uuid, text, text, text, jsonb), public._system_msg(uuid, text), public._is_friend(uuid, uuid) from public;
grant execute on function public.create_group(text, uuid[], text, text), public.update_group(uuid, jsonb), public.add_group_members(uuid, uuid[]),
  public.remove_group_member(uuid, uuid), public.set_group_admin(uuid, uuid, boolean), public.leave_group(uuid), public.send_match_card(uuid, uuid) to authenticated;

do $$ begin alter publication supabase_realtime add table public.conversations; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.conversation_members; exception when duplicate_object then null; end $$;

-- Foto de grupo subida desde la galería: bucket `group-avatars`, ruta `<conversation_id>/avatar.jpg`. Solo admins escriben; miembros leen.
-- (ejecutar con el rol adecuado en Supabase Storage; ajusta el nombre del bucket si ya existe uno)
-- insert into storage.buckets (id, name, public) values ('group-avatars', 'group-avatars', false) on conflict do nothing;
-- create policy ga_read  on storage.objects for select to authenticated using (bucket_id = 'group-avatars' and public.is_member((split_part(name, '/', 1))::uuid));
-- create policy ga_write on storage.objects for insert to authenticated with check (bucket_id = 'group-avatars' and public.is_group_admin((split_part(name, '/', 1))::uuid));
-- create policy ga_upd   on storage.objects for update to authenticated using (bucket_id = 'group-avatars' and public.is_group_admin((split_part(name, '/', 1))::uuid));
