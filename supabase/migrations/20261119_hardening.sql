-- Plobby · Endurecimiento de seguridad (aplicado tras los avisos del linter de Supabase).
-- · anon/public sin EXECUTE en ninguna función de `public`; funciones internas/trigger tampoco para authenticated.
-- · search_path fijo en funciones que no lo tenían.
-- · Índices en claves foráneas; se elimina un índice duplicado.
-- · Sin TRUNCATE/REFERENCES/TRIGGER para clientes; anon sin acceso a tablas.
-- · profiles: columnas personales (birth_date, first_name, last_name, onboarding_*) NO legibles por otros usuarios;
--   el propio usuario las lee con rpc('get_my_profile').
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f' loop
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f'
              and p.proname in ('_init_rating','_is_friend','_post_message','_system_msg','emit_feed_event','notify','handle_new_user',
                                'on_achievement_unlocked','on_comment','on_friend_removed','on_match_confirmed','on_reaction','on_report',
                                '_default_scheduled','_validate_sets','_guard_match_lifecycle','apply_match_rating') loop
    execute format('revoke execute on function %s from authenticated', f.sig);
  end loop;
end $$;

alter function public._default_scheduled() set search_path = public;
alter function public._validate_sets(jsonb) set search_path = public;
alter function public._guard_match_lifecycle() set search_path = public;
alter function public.server_time() set search_path = public;

drop index if exists public.profiles_username_lower_idx;
create index if not exists friend_requests_receiver_idx on public.friend_requests (receiver_id);
create index if not exists friend_requests_sender_idx on public.friend_requests (sender_id);
create index if not exists league_members_user_idx on public.league_members (user_id);
create index if not exists matches_created_by_idx on public.matches (created_by);
create index if not exists messages_sender_idx on public.messages (sender_id);
create index if not exists notifications_actor_idx on public.notifications (actor_user_id);
create index if not exists conversations_created_by_idx on public.conversations (created_by);
create index if not exists comments_user_idx on public.comments (user_id);
create index if not exists reactions_user_idx on public.reactions (user_id);
create index if not exists mra_user_idx on public.match_result_acceptances (user_id);
create index if not exists rating_history_match_idx on public.rating_history (match_id);
create index if not exists leagues_club_idx on public.leagues (club_id);

revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
revoke all on all tables in schema public from anon;

revoke select on public.profiles from authenticated;
do $$ declare cols text; begin
  select string_agg(quote_ident(column_name), ', ') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles'
     and column_name not in ('birth_date','first_name','last_name','onboarding_step','onboarding_completed_at');
  execute 'grant select (' || cols || ') on public.profiles to authenticated';
end $$;

create or replace function public.get_my_profile() returns public.profiles
language sql stable security definer set search_path = public as $$
  select * from public.profiles where id = auth.uid();
$$;
revoke execute on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;
