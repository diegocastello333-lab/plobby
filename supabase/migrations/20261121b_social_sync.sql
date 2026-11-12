-- Plobby · auditoría social (12 nov 2026): notificaciones de mensajes, avisos que se reactivan, sincronización de
-- amistades en tiempo real, contador de amigos y coherencia de la pareja habitual.

-- 1) Mensajes: aviso al destinatario de un mensaje privado (antes no se generaba ninguno) y avisos de grupo que se
--    reactivan. Antes los de grupo usaban `on conflict do nothing`: si el aviso ya existía (aunque estuviera leído)
--    los mensajes siguientes no avisaban nunca. Ahora un aviso por conversación y destinatario, que se actualiza con
--    el último mensaje, vuelve a «sin leer» y cuenta los mensajes pendientes (actor_count).
create or replace function public._post_message(conv uuid, p_kind text, p_body text, p_ref text, p_payload jsonb)
returns public.messages language plpgsql security definer set search_path = public as $$
declare m public.messages; c public.conversations; other uuid; preview text;
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
  preview := left(case p_kind when 'match' then 'Compartió un resultado' when 'profile' then 'Compartió un perfil'
                              when 'league' then 'Compartió una liga' when 'invite' then 'Te invita a jugar: ' || coalesce(p_body, '')
                              else coalesce(p_body, '') end, 120);
  if c.kind = 'direct' and p_kind = 'invite' then
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
    values (other, auth.uid(), 'play_invite', conv, 'Te invita a jugar', left(p_body, 120), 'pi:' || m.id) on conflict do nothing;
  elsif c.kind = 'direct' then
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
    values (other, auth.uid(), 'direct_message', conv, null, preview, 'dm:' || conv || ':' || other)
    on conflict (recipient_user_id, dedupe_key) where dedupe_key is not null do update
      set actor_user_id = excluded.actor_user_id, body = excluded.body, created_at = now(),
          actor_count = case when public.notifications.is_read then 1 else public.notifications.actor_count + 1 end, is_read = false;
  elsif c.kind = 'group' then
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
      select cm.user_id, auth.uid(), 'group_message', conv, c.name, preview, 'gm:' || conv || ':' || cm.user_id
        from public.conversation_members cm where cm.conversation_id = conv and cm.user_id <> auth.uid()
    on conflict (recipient_user_id, dedupe_key) where dedupe_key is not null do update
      set actor_user_id = excluded.actor_user_id, title = excluded.title, body = excluded.body, created_at = now(),
          actor_count = case when public.notifications.is_read then 1 else public.notifications.actor_count + 1 end, is_read = false;
  end if;
  return m;
end $$;

-- 2) Abrir una conversación marca como leídos sus avisos (privado y grupo) en lugar de borrarlos.
create or replace function public.mark_conversation_read(conv uuid)
returns void language sql security definer set search_path = public as $$
  with u as (update public.conversation_members set last_read_at = now() where conversation_id = conv and user_id = auth.uid() returning 1),
       n as (update public.notifications set is_read = true
              where recipient_user_id = auth.uid() and is_read = false
                and dedupe_key in ('gm:' || conv || ':' || auth.uid(), 'dm:' || conv || ':' || auth.uid()) returning 1)
  update public.messages set read_at = now() where conversation_id = conv and sender_id <> auth.uid() and read_at is null and public.is_member(conv)
     and exists (select 1 from public.conversations c where c.id = conv and c.kind = 'direct');
$$;

-- 3) Cancelar una solicitud retira también el aviso del destinatario (antes quedaba con «Aceptar» y fallaba).
create or replace function public.cancel_friend_request(req uuid)
returns void language sql security definer set search_path = public as $$
  with r as (update public.friend_requests set status = 'cancelled', responded_at = now()
              where id = req and sender_id = auth.uid() and status = 'pending' returning id, receiver_id)
  delete from public.notifications n using r
   where n.recipient_user_id = r.receiver_id and n.ref_id = r.id and n.notification_type = 'friend_request';
$$;

-- 4) Eliminar un amigo quita también la pareja habitual entre ambos (antes quedaba una pareja que ya no es amiga).
create or replace function public.remove_friend(target uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.friendships where (user_id = auth.uid() and friend_id = target) or (user_id = target and friend_id = auth.uid());
  update public.profiles set habitual_partner_id = null, updated_at = now()
   where (id = auth.uid() and habitual_partner_id = target) or (id = target and habitual_partner_id = auth.uid());
$$;

-- 5) Editar perfil (paso 2) ya no puede fijar como pareja a alguien que no es amigo (set_habitual_partner sí lo exigía).
create or replace function public.save_onboarding_step(p_step smallint, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); partner uuid;
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
    partner := nullif(p_data->>'partner_id','')::uuid;
    if partner is not null and not public._is_friend(uid, partner) then partner := null; end if;
    update public.profiles set self_declared_level = p_data->>'level', court_side = p_data->>'side', dominant_hand = p_data->>'hand',
           habitual_club = nullif(p_data->>'club',''), habitual_partner_id = partner
     where id = uid;
  elsif p_step = 3 then
    update public.profiles set avatar_url = nullif(p_data->>'avatar_url',''), avatar_id = nullif(p_data->>'avatar_id','') where id = uid;
  else raise exception 'invalid_step'; end if;
  update public.profiles set onboarding_step = greatest(onboarding_step, p_step + 1) where id = uid;
end $$;

-- 6) Contador de amigos de cualquier perfil (la RLS de friendships solo deja leer las filas propias).
create or replace function public.friend_count(p_user uuid)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from public.friendships where user_id = p_user and status = 'accepted';
$$;
revoke execute on function public.friend_count(uuid) from public, anon;
grant execute on function public.friend_count(uuid) to authenticated;

-- 7) Amistades en tiempo real para los DOS usuarios (alta y baja). Se usa Broadcast desde la base de datos en un canal
--    privado por usuario (`user:<uid>`): los eventos DELETE de postgres_changes no se pueden filtrar ni pasan por RLS,
--    así que suscribirse a ellos enviaría a todos los clientes quién deja de ser amigo de quién.
create or replace function public._broadcast_friendship() returns trigger
language plpgsql security definer set search_path = public as $$
declare uid uuid := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
        fid uuid := case when tg_op = 'DELETE' then old.friend_id else new.friend_id end;
begin
  begin
    perform realtime.send(jsonb_build_object('op', lower(tg_op), 'friend_id', fid), 'friends', 'user:' || uid, true);
  exception when others then null;   -- el aviso en vivo nunca debe impedir el cambio de amistad
  end;
  return null;
end $$;
drop trigger if exists friendships_broadcast on public.friendships;
create trigger friendships_broadcast after insert or delete on public.friendships
  for each row execute function public._broadcast_friendship();

drop policy if exists plobby_user_topic_read on realtime.messages;
create policy plobby_user_topic_read on realtime.messages for select to authenticated
  using (realtime.topic() = 'user:' || auth.uid()::text);

-- 8) Rendimiento: índice duplicado (messages_conv_idx ya cubre conversation_id, created_at en ambos sentidos).
drop index if exists public.messages_conv_created_idx;

-- 9) La función del trigger no debe poder llamarse por RPC (aviso del linter de Supabase).
revoke execute on function public._broadcast_friendship() from public, anon, authenticated;
