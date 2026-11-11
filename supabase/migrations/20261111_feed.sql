-- Plobby · Feed social: tablas, índices, RLS y generación de eventos.
-- NO EJECUTADO NI VALIDADO contra ninguna base de datos. Revisar antes de aplicar.
-- Supuestos sobre el esquema existente (ADAPTAR; no se ha podido inspeccionar el proyecto):
--   public.profiles(id uuid pk -> auth.users)
--   public.friendships(user_id uuid, friend_id uuid, status text)  -- 'accepted' = amigos (relación simétrica con 2 filas)
--   public.matches(id, confirmed_at timestamptz null)               -- null = sin confirmar
--   public.match_players(match_id, user_id, team smallint, elo_delta int)
--   public.user_achievements(id, user_id, achievement_id)
-- Si ya existen tablas equivalentes (p. ej. notifications), reutilízalas en lugar de duplicarlas.

create type feed_activity_type as enum ('match','achievement','streak','elo','league');
create type reaction_type      as enum ('fire','heart','clap','strong','laugh');
create type notification_type  as enum ('reaction','comment','friend_request','friend_accepted','league_invite','match_event','achievement');

create table public.feed_posts (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references public.profiles(id) on delete cascade,
  activity_type           feed_activity_type not null,
  related_match_id        uuid references public.matches(id) on delete cascade,
  related_achievement_id  uuid references public.user_achievements(id) on delete cascade,
  metadata                jsonb not null default '{}'::jsonb,
  dedupe_key              text not null,                       -- evita posts duplicados por reprocesar un evento
  created_at              timestamptz not null default now(),
  constraint feed_posts_dedupe unique (dedupe_key)
);
create index feed_posts_created_idx on public.feed_posts (created_at desc, id);
create index feed_posts_user_idx    on public.feed_posts (user_id, created_at desc);
create index feed_posts_match_idx   on public.feed_posts (related_match_id) where related_match_id is not null;

create table public.reactions (
  id            uuid primary key default gen_random_uuid(),
  post_id       uuid not null references public.feed_posts(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  reaction_type reaction_type not null,
  created_at    timestamptz not null default now(),
  constraint reactions_one_per_user unique (post_id, user_id)   -- máximo una reacción activa por usuario y post
);
create index reactions_post_idx on public.reactions (post_id, reaction_type);

create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.feed_posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  content    text not null check (char_length(btrim(content)) between 1 and 140),
  hidden     boolean not null default false,                   -- moderación básica (denuncias)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index comments_post_idx on public.comments (post_id, created_at);

create table public.comment_reports (
  comment_id  uuid not null references public.comments(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (comment_id, reporter_id)
);

create table public.notifications (
  id                uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references public.profiles(id) on delete cascade,
  actor_user_id     uuid references public.profiles(id) on delete set null,
  notification_type notification_type not null,
  related_post_id   uuid references public.feed_posts(id) on delete cascade,
  actor_count       int not null default 1,                    -- agrupa "Marcos y 3 más…" para no saturar
  is_read           boolean not null default false,
  created_at        timestamptz not null default now()
);
create index notifications_recipient_idx on public.notifications (recipient_user_id, is_read, created_at desc);
-- una sola notificación SIN LEER por destinatario+tipo+post: las siguientes acciones se agrupan
create unique index notifications_group_idx on public.notifications (recipient_user_id, notification_type, related_post_id) where is_read = false and related_post_id is not null;

-- ---------- visibilidad ----------
create or replace function public.can_view_user(target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select target = auth.uid()
      or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = target and f.status = 'accepted');
$$;
create or replace function public.can_view_post(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.feed_posts p where p.id = pid and public.can_view_user(p.user_id));
$$;

-- ---------- RLS ----------
alter table public.feed_posts      enable row level security;
alter table public.reactions       enable row level security;
alter table public.comments        enable row level security;
alter table public.comment_reports enable row level security;
alter table public.notifications   enable row level security;

-- feed_posts: solo lectura desde el cliente; la escritura ocurre en triggers/funciones (security definer)
create policy feed_posts_select on public.feed_posts for select to authenticated using (public.can_view_user(user_id));

create policy reactions_select on public.reactions for select to authenticated using (public.can_view_post(post_id));
create policy reactions_insert on public.reactions for insert to authenticated with check (user_id = auth.uid() and public.can_view_post(post_id));
create policy reactions_update on public.reactions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy reactions_delete on public.reactions for delete to authenticated using (user_id = auth.uid());

create policy comments_select on public.comments for select to authenticated using (public.can_view_post(post_id) and (not hidden or user_id = auth.uid()));
create policy comments_insert on public.comments for insert to authenticated with check (user_id = auth.uid() and public.can_view_post(post_id));
create policy comments_update on public.comments for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy comments_delete on public.comments for delete to authenticated using (user_id = auth.uid());
revoke update on public.comments from authenticated;  grant update (content, updated_at) on public.comments to authenticated;

create policy reports_insert on public.comment_reports for insert to authenticated with check (reporter_id = auth.uid());

create policy notifications_select on public.notifications for select to authenticated using (recipient_user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated using (recipient_user_id = auth.uid()) with check (recipient_user_id = auth.uid());
revoke update on public.notifications from authenticated;  grant update (is_read) on public.notifications to authenticated;
-- sin políticas de INSERT/DELETE para notifications y feed_posts: solo las crean funciones del servidor.

-- ---------- RPC: reacción atómica (null = quitar) ----------
create or replace function public.set_reaction(p_post_id uuid, p_type reaction_type) returns void
language plpgsql security invoker set search_path = public as $$
begin
  if p_type is null then
    delete from public.reactions where post_id = p_post_id and user_id = auth.uid();
  else
    insert into public.reactions (post_id, user_id, reaction_type) values (p_post_id, auth.uid(), p_type)
    on conflict (post_id, user_id) do update set reaction_type = excluded.reaction_type;
  end if;
end $$;

-- ---------- generación de eventos (idempotente) ----------
create or replace function public.emit_feed_event(p_user uuid, p_type feed_activity_type, p_key text, p_match uuid, p_ach uuid, p_meta jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.feed_posts (user_id, activity_type, related_match_id, related_achievement_id, metadata, dedupe_key)
  values (p_user, p_type, p_match, p_ach, coalesce(p_meta, '{}'), p_key)
  on conflict (dedupe_key) do nothing;               -- reprocesar el mismo evento NO crea otro post
$$;

-- Partido: solo cuando pasa de no confirmado a confirmado.
create or replace function public.on_match_confirmed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.confirmed_at is null and new.confirmed_at is not null then
    insert into public.feed_posts (user_id, activity_type, related_match_id, metadata, dedupe_key, created_at)
    select mp.user_id, 'match', new.id,
           jsonb_build_object('team', mp.team, 'elo_delta', mp.elo_delta),   -- completar con marcador, rivales y sede
           'match:' || new.id || ':' || mp.user_id, new.confirmed_at
    from public.match_players mp where mp.match_id = new.id
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end $$;
create trigger matches_confirmed after update of confirmed_at on public.matches
  for each row execute function public.on_match_confirmed();

create or replace function public.on_achievement_unlocked() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.emit_feed_event(new.user_id, 'achievement', 'ach:' || new.id, null, new.id, jsonb_build_object('achievement_id', new.achievement_id));
  return new;
end $$;
create trigger achievements_feed after insert on public.user_achievements
  for each row execute function public.on_achievement_unlocked();
-- Rachas, hitos de ELO y actividad de ligas: llamar a emit_feed_event(...) desde la función que ya recalcula
-- el ELO / racha tras confirmar un partido, con claves como 'streak:<user>:<n>' o 'elo:<user>:<hito>'.

-- ---------- notificaciones (agrupadas, sin ruido) ----------
create or replace function public.notify(p_recipient uuid, p_actor uuid, p_type notification_type, p_post uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_recipient = p_actor then return; end if;                      -- no te avisas a ti mismo
  insert into public.notifications (recipient_user_id, actor_user_id, notification_type, related_post_id)
  values (p_recipient, p_actor, p_type, p_post)
  on conflict (recipient_user_id, notification_type, related_post_id) where is_read = false and related_post_id is not null
  do update set actor_count = public.notifications.actor_count + 1, actor_user_id = excluded.actor_user_id, created_at = now();
end $$;

create or replace function public.on_reaction() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notify((select user_id from public.feed_posts where id = new.post_id), new.user_id, 'reaction', new.post_id);
  return new;
end $$;
create trigger reactions_notify after insert on public.reactions for each row execute function public.on_reaction();

create or replace function public.on_comment() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notify((select user_id from public.feed_posts where id = new.post_id), new.user_id, 'comment', new.post_id);
  return new;
end $$;
create trigger comments_notify after insert on public.comments for each row execute function public.on_comment();

-- Denuncias: a partir de 3 reportes distintos el comentario se oculta automáticamente.
create or replace function public.on_report() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.comments set hidden = true where id = new.comment_id
    and (select count(*) from public.comment_reports where comment_id = new.comment_id) >= 3;
  return new;
end $$;
create trigger reports_moderate after insert on public.comment_reports for each row execute function public.on_report();

-- ---------- Realtime ----------
alter publication supabase_realtime add table public.feed_posts, public.reactions, public.comments, public.notifications;
