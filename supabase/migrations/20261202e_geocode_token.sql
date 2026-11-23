-- =====================================================================================================================
-- Plobby · Tokens de servicio de un solo propósito (geocodificación de clubes). Solo se guarda el HASH (sha-256);
-- el token vive fuera del repositorio. La comprobación solo la puede ejecutar service_role (la Edge Function).
-- =====================================================================================================================
create table if not exists private.service_tokens (
  name text primary key,
  token_hash text not null check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
revoke all on private.service_tokens from public, anon, authenticated;

create or replace function public.geocode_token_ok(p text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.service_tokens t
                  where t.name = 'geocode' and t.expires_at > now()
                    and t.token_hash = encode(extensions.digest(coalesce(p, ''), 'sha256'), 'hex'));
$$;
revoke all on function public.geocode_token_ok(text) from public, anon, authenticated;
grant execute on function public.geocode_token_ok(text) to service_role;
