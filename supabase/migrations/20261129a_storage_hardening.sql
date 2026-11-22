-- =====================================================================================================================
-- Plobby · Seguridad Fase 2 (22 nov 2026): Storage. Ver docs/seguridad/fase2_storage.md.
--   · Escritura solo en la carpeta propia (<uid>/ en `avatars`; <conversation_id>/ y solo admins del grupo en
--     `group-avatars`), UN nivel de carpeta y extensión de imagen (jpg, jpeg, png, webp). UPDATE con WITH CHECK explícito.
--   · Límites por bucket: `group-avatars` 2 MB (la app sube 800 px, ~150 KB); `avatars` mantiene 5 MB (portadas de torneo).
--   · `group-avatars` sigue privado (URL firmada); los admins del grupo pueden borrar su imagen.
--   · `avatars` sigue PÚBLICO: ver decisión en el informe. No se puede listar (solo la carpeta propia).
-- No borra ficheros. Compatible con la app actual (las rutas que usa ya cumplen estas reglas).
-- =====================================================================================================================

update storage.buckets set file_size_limit = 2097152, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'], public = false
 where id = 'group-avatars';
update storage.buckets set file_size_limit = 5242880, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id = 'avatars';

-- ¿La ruta es «<carpeta>/<fichero>.<ext de imagen>» con exactamente un nivel de carpeta?
create or replace function private.storage_image_path_ok(p_name text, p_folder text) returns boolean
language sql immutable set search_path = '' as $$
  select p_name ~ '^[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,100}$'
     and split_part(p_name, '/', 1) = p_folder
     and lower(substring(p_name from '\.([A-Za-z0-9]+)$')) in ('jpg', 'jpeg', 'png', 'webp');
$$;
revoke all on function private.storage_image_path_ok(text, text) from public, anon;
grant execute on function private.storage_image_path_ok(text, text) to authenticated;

-- avatars: solo la carpeta propia
alter policy avatars_write_own on storage.objects
  with check (bucket_id = 'avatars' and private.storage_image_path_ok(name, (select auth.uid())::text));
alter policy avatars_update_own on storage.objects
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and private.storage_image_path_ok(name, (select auth.uid())::text));
alter policy avatars_delete_own on storage.objects
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- group-avatars: solo admins del grupo escriben/borran; miembros leen
alter policy ga_write on storage.objects
  with check (bucket_id = 'group-avatars' and private.storage_image_path_ok(name, split_part(name, '/', 1))
              and private.is_group_admin((split_part(name, '/', 1))::uuid));
alter policy ga_upd on storage.objects
  using (bucket_id = 'group-avatars' and private.is_group_admin((split_part(name, '/', 1))::uuid))
  with check (bucket_id = 'group-avatars' and private.storage_image_path_ok(name, split_part(name, '/', 1))
              and private.is_group_admin((split_part(name, '/', 1))::uuid));
do $$ begin
  create policy ga_delete on storage.objects for delete to authenticated
    using (bucket_id = 'group-avatars' and private.is_group_admin((split_part(name, '/', 1))::uuid));
exception when duplicate_object then null;
end $$;
