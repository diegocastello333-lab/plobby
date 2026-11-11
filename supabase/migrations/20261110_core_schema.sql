-- Plobby · Esquema base. Las migraciones posteriores (feed, social, ciclo del partido…) se escribieron asumiendo estas
-- tablas; aquí se crean de verdad (clubes y pistas incluidos). Idempotente en lo posible; sin datos de ejemplo.
create extension if not exists pgcrypto;

-- ── Perfiles (1:1 con auth.users). 20261114_auth_profiles.sql añade columnas de onboarding.
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  username     text,
  avatar_url   text,
  city         text,
  home_club    text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index profiles_username_lower_idx on public.profiles (lower(username)) where username is not null;

-- ── Clubes y pistas
create table public.clubs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 2 and 120),
  city       text,
  address    text,
  lat        double precision,
  lng        double precision,
  created_at timestamptz not null default now(),
  unique (name, city)
);
create table public.courts (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs(id) on delete cascade,
  name       text not null,
  indoor     boolean not null default false,
  created_at timestamptz not null default now(),
  unique (club_id, name)
);

-- ── Amistades (relación simétrica: dos filas)
create table public.friendships (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  friend_id  uuid not null references public.profiles(id) on delete cascade,
  status     text not null default 'accepted' check (status in ('accepted','blocked')),
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);
create index friendships_friend_idx on public.friendships (friend_id);

-- ── Ligas
create table public.leagues (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 2 and 80),
  created_by uuid references public.profiles(id) on delete set null,
  club_id    uuid references public.clubs(id) on delete set null,
  created_at timestamptz not null default now()
);
create table public.league_members (
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);

-- ── Partidos. El estado/tipo/versionado se añaden en 20261113 y 20261115.
create table public.matches (
  id           uuid primary key default gen_random_uuid(),
  created_by   uuid references public.profiles(id) on delete set null,
  club         text,
  club_id      uuid references public.clubs(id) on delete set null,
  court_id     uuid references public.courts(id) on delete set null,
  court        text,
  played_at    timestamptz,
  confirmed_at timestamptz,
  created_at   timestamptz not null default now()
);
create index matches_played_idx on public.matches (played_at desc);
create table public.match_players (
  match_id  uuid not null references public.matches(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  team      smallint not null check (team in (1,2)),
  elo_delta int,
  primary key (match_id, user_id)
);
create index match_players_user_idx on public.match_players (user_id);
create table public.match_sets (
  match_id    uuid not null references public.matches(id) on delete cascade,
  set_no      smallint not null check (set_no between 1 and 5),
  team1_games smallint not null check (team1_games between 0 and 20),
  team2_games smallint not null check (team2_games between 0 and 20),
  primary key (match_id, set_no)
);

-- ── Valoración (ELO): solo la escribe el backend (funciones security definer); el cliente únicamente lee.
create table public.player_ratings (
  user_id  uuid primary key references public.profiles(id) on delete cascade,
  elo      int not null default 1200,
  best_elo int not null default 1200,
  updated_at timestamptz not null default now()
);
create table public.rating_history (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  match_id      uuid references public.matches(id) on delete set null,
  rating_before int not null,
  delta         int not null,
  created_at    timestamptz not null default now()
);
create index rating_history_user_idx on public.rating_history (user_id, created_at desc);

-- ── Logros
create table public.user_achievements (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  achievement_id text not null,
  unlocked_at    timestamptz not null default now(),
  unique (user_id, achievement_id)
);

-- RLS de las tablas base (las demás migraciones definen la suya para sus tablas)
alter table public.profiles enable row level security;
alter table public.clubs enable row level security;
alter table public.courts enable row level security;
alter table public.friendships enable row level security;
alter table public.leagues enable row level security;
alter table public.league_members enable row level security;
alter table public.matches enable row level security;
alter table public.match_players enable row level security;
alter table public.match_sets enable row level security;
alter table public.player_ratings enable row level security;
alter table public.rating_history enable row level security;
alter table public.user_achievements enable row level security;
