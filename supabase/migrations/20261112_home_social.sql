-- Plobby · Home funcional: amistades, mensajes privados, notificaciones ampliadas y lectura de ELO.
-- NO EJECUTADO NI VALIDADO contra ninguna base de datos. Revisar antes de aplicar.
--
-- Reutiliza lo existente (no duplica tablas): profiles, friendships, notifications, matches, match_players.
-- Solo crea lo que falta: friend_requests, conversations, conversation_members, messages, rating_config
-- y vistas/RPC de lectura. SUPUESTOS a adaptar al esquema real:
--   public.profiles(id, display_name, username, avatar_url, city, home_club)
--   public.player_ratings(user_id pk, elo int, best_elo int)        -- escrito SOLO por el backend de rating
--   public.rating_history(id, user_id, match_id, rating_before int, delta int, created_at)  -- idem, solo lectura
--   public.friendships(user_id, friend_id, status)  -- 'accepted' = amigos, 2 filas simétricas
-- NUNCA se expone la service role key en la app: todo pasa por RLS + funciones SECURITY DEFINER.

-- ============================================================ 1. Notificaciones: más tipos
-- (ALTER TYPE ... ADD VALUE no puede usarse en la misma transacción que sus nuevos valores: aplicar en un paso previo)
alter type notification_type add value if not exists 'play_invite';
alter type notification_type add value if not exists 'match_confirmation_required';
alter type notification_type add value if not exists 'match_confirmed';
alter type notification_type add value if not exists 'match_disputed';
alter type notification_type add value if not exists 'streak';
alter type notification_type add value if not exists 'elo_milestone';
alter type notification_type add value if not exists 'rating_change';
alter type notification_type add value if not exists 'league_starting';
alter type notification_type add value if not exists 'league_position_change';

alter table public.notifications
  add column if not exists ref_id uuid,                 -- partido / liga / conversación relacionada
  add column if not exists title text,
  add column if not exists body text,
  add column if not exists dedupe_key text;             -- evita duplicados de un mismo evento
create unique index if not exists notifications_dedupe_idx on public.notifications (recipient_user_id, dedupe_key) where dedupe_key is not null;

-- ============================================================ 2. Solicitudes de amistad
create table if not exists public.friend_requests (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references public.profiles(id) on delete cascade,
  receiver_id  uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (sender_id <> receiver_id)
);
-- una sola solicitud pendiente por pareja, en cualquier dirección (evita duplicados)
create unique index if not exists friend_requests_pair_idx on public.friend_requests
  (least(sender_id, receiver_id), greatest(sender_id, receiver_id)) where status = 'pending';

alter table public.friend_requests enable row level security;
create policy fr_select on public.friend_requests for select to authenticated using (sender_id = auth.uid() or receiver_id = auth.uid());
-- sin policies de insert/update/delete: todo por RPC

create or replace function public.send_friend_request(target uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if target = auth.uid() then raise exception 'cannot add yourself'; end if;
  if exists (select 1 from public.friendships where user_id = auth.uid() and friend_id = target and status = 'accepted') then raise exception 'already friends'; end if;
  -- si el otro ya me envió una solicitud, la acepto directamente
  select id into rid from public.friend_requests where sender_id = target and receiver_id = auth.uid() and status = 'pending';
  if rid is not null then perform public.respond_friend_request(rid, true); return rid; end if;
  insert into public.friend_requests (sender_id, receiver_id) values (auth.uid(), target) returning id into rid;  -- el índice único evita duplicados
  insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, dedupe_key)
  values (target, auth.uid(), 'friend_request', rid, 'fr:' || rid) on conflict do nothing;
  return rid;
end $$;

create or replace function public.cancel_friend_request(req uuid) returns void
language sql security definer set search_path = public as $$
  update public.friend_requests set status = 'cancelled', responded_at = now() where id = req and sender_id = auth.uid() and status = 'pending';
$$;

create or replace function public.respond_friend_request(req uuid, accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare r public.friend_requests;
begin
  select * into r from public.friend_requests where id = req and receiver_id = auth.uid() and status = 'pending' for update;
  if not found then raise exception 'request not found'; end if;
  update public.friend_requests set status = case when accept then 'accepted' else 'declined' end, responded_at = now() where id = req;
  update public.notifications set is_read = true where recipient_user_id = auth.uid() and ref_id = req and notification_type = 'friend_request';
  if accept then
    insert into public.friendships (user_id, friend_id, status) values (r.sender_id, r.receiver_id, 'accepted'), (r.receiver_id, r.sender_id, 'accepted') on conflict do nothing;
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, dedupe_key)
    values (r.sender_id, auth.uid(), 'friend_accepted', req, 'fa:' || req) on conflict do nothing;
  end if;
end $$;

create or replace function public.remove_friend(target uuid) returns void
language sql security definer set search_path = public as $$
  delete from public.friendships where (user_id = auth.uid() and friend_id = target) or (user_id = target and friend_id = auth.uid());
$$;

-- ============================================================ 4. ELO: configuración y lectura (SOLO LECTURA)
create table if not exists public.rating_config (
  id int primary key default 1 check (id = 1),
  min_rating int not null default 800, max_rating int not null default 2000,
  tiers jsonb not null default '[{"name":"Principiante","from":800},{"name":"Intermedio","from":1200},{"name":"Avanzado","from":1400},{"name":"Experto","from":1600}]'
);
insert into public.rating_config (id) values (1) on conflict do nothing;
alter table public.rating_config enable row level security;
create policy rating_config_read on public.rating_config for select to authenticated using (true);

create or replace function public.rating_level(elo int) returns text language sql stable set search_path = public as $$
  select t->>'name' from public.rating_config c, jsonb_array_elements(c.tiers) t
  where (t->>'from')::int <= coalesce(elo, c.min_rating) order by (t->>'from')::int desc limit 1;
$$;

-- ============================================================ 3. Vistas y búsqueda (lectura)
create or replace view public.v_my_friends with (security_invoker = true) as
select p.id as user_id, p.display_name, p.username, p.avatar_url, p.city, pr.elo,
       public.rating_level(pr.elo) as level,
       (select count(*) from public.friendships a join public.friendships b on a.friend_id = b.friend_id
         where a.user_id = auth.uid() and b.user_id = p.id)::int as mutual_friends,
       null::text as last_match_label, 0 as streak   -- TODO: derivar del último partido confirmado / racha vigente
from public.friendships f
join public.profiles p on p.id = f.friend_id
left join public.player_ratings pr on pr.user_id = p.id
where f.user_id = auth.uid() and f.status = 'accepted';

create or replace view public.v_my_friend_requests with (security_invoker = true) as
select r.id as request_id, case when r.receiver_id = auth.uid() then 'incoming' else 'outgoing' end as direction, r.created_at,
       p.id as user_id, p.display_name, p.username, p.avatar_url, p.city, pr.elo, public.rating_level(pr.elo) as level
from public.friend_requests r
join public.profiles p on p.id = case when r.receiver_id = auth.uid() then r.sender_id else r.receiver_id end
left join public.player_ratings pr on pr.user_id = p.id
where r.status = 'pending' and (r.sender_id = auth.uid() or r.receiver_id = auth.uid());

create or replace function public.search_players(q text)
returns table (user_id uuid, display_name text, username text, avatar_url text, city text, elo int, level text, relation text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.username, p.avatar_url, p.city, pr.elo, public.rating_level(pr.elo),
    case
      when exists (select 1 from friendships f where f.user_id = auth.uid() and f.friend_id = p.id and f.status = 'accepted') then 'friend'
      when exists (select 1 from friend_requests r where r.sender_id = auth.uid() and r.receiver_id = p.id and r.status = 'pending') then 'requestSent'
      when exists (select 1 from friend_requests r where r.receiver_id = auth.uid() and r.sender_id = p.id and r.status = 'pending') then 'requestReceived'
      else 'none' end
  from profiles p left join player_ratings pr on pr.user_id = p.id
  where p.id <> auth.uid() and length(trim(q)) >= 2
    and (p.display_name ilike '%' || trim(q) || '%' or p.username ilike '%' || trim(q) || '%')
  order by p.display_name limit 30;
$$;

create or replace function public.suggest_friends()
returns table (user_id uuid, display_name text, username text, avatar_url text, city text, elo int, level text, mutual_friends int, reason text)
language sql stable security definer set search_path = public as $$
  with me as (select p.city, p.home_club, coalesce(pr.elo, 1000) as elo from profiles p left join player_ratings pr on pr.user_id = p.id where p.id = auth.uid()),
  cand as (
    select p.id, p.display_name, p.username, p.avatar_url, p.city, pr.elo, public.rating_level(pr.elo) as lvl,
      (select count(*) from friendships a join friendships b on a.friend_id = b.friend_id where a.user_id = auth.uid() and b.user_id = p.id)::int as mutual,
      (p.city is not distinct from (select city from me)) as same_city,
      (p.home_club is not distinct from (select home_club from me) and p.home_club is not null) as same_club,
      abs(coalesce(pr.elo, 1000) - (select elo from me)) <= 60 as similar_elo
    from profiles p left join player_ratings pr on pr.user_id = p.id
    where p.id <> auth.uid()
      and not exists (select 1 from friendships f where f.user_id = auth.uid() and f.friend_id = p.id)
      and not exists (select 1 from friend_requests r where r.status = 'pending' and ((r.sender_id = auth.uid() and r.receiver_id = p.id) or (r.receiver_id = auth.uid() and r.sender_id = p.id))))
  select id, display_name, username, avatar_url, city, elo, lvl, mutual,
    concat_ws(' · ', case when mutual > 0 then mutual || ' amigos en común' end, case when same_club then 'Mismo club' end, case when same_city then 'Misma ciudad' end, case when similar_elo then 'ELO similar' end)
  from cand where mutual > 0 or same_club or same_city or similar_elo
  order by mutual desc, same_club desc, same_city desc limit 10;
$$;


-- Nadie edita ELO desde el cliente: sin policies de escritura en player_ratings / rating_history.
alter table public.player_ratings enable row level security;
alter table public.rating_history enable row level security;
create policy pr_read on public.player_ratings for select to authenticated using (user_id = auth.uid() or public.can_view_user(user_id));
create policy rh_read_own on public.rating_history for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.player_ratings, public.rating_history from authenticated, anon;
-- El ELO lo actualiza la función de rating existente (p. ej. apply_match_rating) disparada al confirmarse un partido; no se reimplementa aquí.

create or replace view public.v_my_rating_detail with (security_invoker = true) as
select p.display_name, p.username, p.avatar_url, pr.elo, greatest(pr.best_elo, pr.elo) as best_elo,
  coalesce((select sum(delta) from public.rating_history h where h.user_id = auth.uid() and h.created_at > now() - interval '30 days'), 0)::int as delta_30d,
  (select count(*) from public.match_players mp join public.matches m on m.id = mp.match_id where mp.user_id = auth.uid() and m.confirmed_at is not null)::int as confirmed_matches,
  (select count(*) from public.rating_history h where h.user_id = auth.uid() and h.delta > 0)::int as wins,   -- ADAPTAR: usar resultado real del partido
  (select count(*) from public.rating_history h where h.user_id = auth.uid() and h.delta <= 0)::int as losses
from public.profiles p join public.player_ratings pr on pr.user_id = p.id where p.id = auth.uid();

-- ADAPTAR: score/opponents/won se derivan de matches + match_players según vuestro esquema.
create or replace view public.v_my_rating_changes with (security_invoker = true) as
select h.match_id, h.created_at, h.rating_before, h.delta, (h.delta > 0) as won,
       ''::text as score, ''::text as opponents
from public.rating_history h where h.user_id = auth.uid();

-- ============================================================ 5. Mensajería privada
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  last_message_at timestamptz
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index if not exists cm_user_idx on public.conversation_members (user_id);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'text' check (kind in ('text','invite','match','league','profile')),
  body text not null default '' check (length(body) <= 500),
  ref_id text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists messages_conv_idx on public.messages (conversation_id, created_at desc);

create or replace function public.is_member(conv uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_members where conversation_id = conv and user_id = auth.uid());
$$;

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
create policy conv_select on public.conversations for select to authenticated using (public.is_member(id));
create policy cm_select on public.conversation_members for select to authenticated using (public.is_member(conversation_id));
create policy msg_select on public.messages for select to authenticated using (public.is_member(conversation_id));
-- sin policy de insert en messages: se envía con send_message() para validar membresía y amistad

create or replace function public.get_or_create_conversation(friend uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if not exists (select 1 from public.friendships where user_id = auth.uid() and friend_id = friend and status = 'accepted') then
    raise exception 'only accepted friends can chat';
  end if;
  select a.conversation_id into cid from public.conversation_members a join public.conversation_members b on a.conversation_id = b.conversation_id
   where a.user_id = auth.uid() and b.user_id = friend limit 1;
  if cid is null then
    insert into public.conversations default values returning id into cid;
    insert into public.conversation_members (conversation_id, user_id) values (cid, auth.uid()), (cid, friend);
  end if;
  return cid;
end $$;

create or replace function public.send_message(conv uuid, body_in text, kind_in text default 'text', ref_in text default null) returns public.messages
language plpgsql security definer set search_path = public as $$
declare m public.messages; other uuid;
begin
  if not public.is_member(conv) then raise exception 'not a member'; end if;
  select user_id into other from public.conversation_members where conversation_id = conv and user_id <> auth.uid();
  if not exists (select 1 from public.friendships where user_id = auth.uid() and friend_id = other and status = 'accepted') then raise exception 'not friends'; end if;
  insert into public.messages (conversation_id, sender_id, kind, body, ref_id) values (conv, auth.uid(), kind_in, left(body_in, 500), ref_in) returning * into m;
  update public.conversations set last_message_at = m.created_at where id = conv;
  if kind_in = 'invite' then
    insert into public.notifications (recipient_user_id, actor_user_id, notification_type, ref_id, title, body, dedupe_key)
    values (other, auth.uid(), 'play_invite', conv, 'Te invita a jugar', left(body_in, 120), 'pi:' || m.id) on conflict do nothing;
  end if;
  return m;
end $$;

create or replace function public.mark_conversation_read(conv uuid) returns void
language sql security definer set search_path = public as $$
  with u as (update public.conversation_members set last_read_at = now() where conversation_id = conv and user_id = auth.uid() returning 1)
  update public.messages set read_at = now() where conversation_id = conv and sender_id <> auth.uid() and read_at is null and public.is_member(conv);
$$;

create or replace view public.v_my_conversations with (security_invoker = true) as
select c.id as conversation_id, c.last_message_at, o.user_id as other_id, p.display_name as other_name, p.username as other_username,
       p.avatar_url as other_avatar, pr.elo as other_elo, public.rating_level(pr.elo) as other_level,
       lm.body as last_body, lm.kind as last_kind, lm.sender_id as last_sender,
       (select count(*) from public.messages x where x.conversation_id = c.id and x.sender_id <> auth.uid() and x.read_at is null)::int as unread
from public.conversations c
join public.conversation_members me on me.conversation_id = c.id and me.user_id = auth.uid()
join public.conversation_members o on o.conversation_id = c.id and o.user_id <> auth.uid()
join public.profiles p on p.id = o.user_id
left join public.player_ratings pr on pr.user_id = o.user_id
left join lateral (select body, kind, sender_id from public.messages where conversation_id = c.id order by created_at desc limit 1) lm on true;

-- Al eliminar la amistad se retiran las membresías para cerrar la conversación privada
create or replace function public.on_friend_removed() returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.conversation_members cm where cm.user_id in (old.user_id, old.friend_id)
    and cm.conversation_id in (select a.conversation_id from public.conversation_members a join public.conversation_members b on a.conversation_id = b.conversation_id where a.user_id = old.user_id and b.user_id = old.friend_id);
  return old;
end $$;
drop trigger if exists friendships_removed on public.friendships;
create trigger friendships_removed after delete on public.friendships for each row execute function public.on_friend_removed();

-- ============================================================ 6. Realtime
do $$ begin alter publication supabase_realtime add table public.messages; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.friend_requests; exception when duplicate_object then null; end $$;
