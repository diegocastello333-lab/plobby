# Plobby · Fase 1: base de datos

Rama `seguridad-legal`. Migraciones versionadas:

| Fichero | Qué hace | ¿Rompe algo? |
|---|---|---|
| `supabase/migrations/20261128a_security_hardening.sql` | Endurecimiento general (abajo) | **No.** Validado en la BD real con usuarios temporales y ROLLBACK, incluidos los flujos de la app que escriben directamente en tablas |
| `supabase/migrations/20261128b_profile_visibility.sql` | Perfiles: los desconocidos solo ven nombre, usuario, foto y nivel | **Sí, en versiones antiguas de la app**: su pantalla de perfil pide columnas que dejarán de ser legibles. Se aplica cuando todos tengan la versión nueva |
| `supabase/tests/rls_isolation_test.sql` | 51 pruebas (aislamiento A/B/C, `anon`, flujos de la app, comprobaciones estructurales) | — (siempre se deshace) |

## 20261128a, punto por punto

1. **Auxiliares de RLS en un esquema `private`** (no expuesto por la API).
   - Las 11 funciones que usan las políticas (`is_member`, `can_view_user`, `_t_can_view`…) tienen ahora una versión en `private` con `search_path = ''` y nombres totalmente cualificados.
   - Las 34 políticas (tablas y Storage) pasan a usarlas, con la misma lógica.
   - Las versiones de `public` quedan como envoltorios que **ya no se pueden invocar por `/rest/v1/rpc`**. Antes permitían sondear, por ejemplo, si un usuario X había jugado el partido Y.
   - `_is_participant(match, user)` deja de aceptar un usuario arbitrario en las políticas: `private.is_participant(match)` usa siempre el de la sesión.
2. **`search_path` fijo en las 140 funciones**, con `pg_temp` al final.
   - Las 11 auxiliares nuevas y `get_profile` usan `''`.
   - Las 129 existentes usan `pg_catalog, public, pg_temp`. Pasarlas a `''` exige reescribir el cuerpo de cada una cualificando cada tabla y función, con mucho riesgo de romper la lógica de partidos, ELO, ligas y torneos.
   - Según la documentación de PostgreSQL ("Writing SECURITY DEFINER Functions Safely"), un `search_path` fijo con `pg_temp` al final ya impide la suplantación. Además, ningún rol de la API puede crear objetos en `public`.
3. **Permisos mínimos.**
   - Se revoca todo a `anon` y `authenticated` en tablas, vistas y secuencias. Eso incluye **TRUNCATE (que se salta RLS), REFERENCES y TRIGGER**, que `authenticated` tenía en 9 tablas.
   - Después se concede solo lo que usa la app: SELECT (lo filtra RLS) y escrituras por columna en `profiles` (9 columnas), `comments`, `reactions`, `notifications.is_read`, `notification_prefs` y `comment_reports`.
   - Privilegios por defecto: lo que se cree a partir de ahora **no da permisos a nadie** si no se conceden explícitamente. Las migraciones futuras deben incluir sus `grant`.
4. **Una política SELECT por tabla** en `matches`, `match_players` y `match_sets`. Antes había dos permisivas, y el advisor de rendimiento lo marcaba.
5. **Validación en servidor.**
   - Se validan 3 restricciones que estaban `NOT VALID`.
   - Se añaden límites de longitud y tamaño en perfiles, partidos, avisos, clubes, pistas, motivos de rechazo, metadatos del feed y mensajes, y una fecha de nacimiento ≥ 1900.
   - El trigger `profiles_guard` recorta también nombre, apellidos y club.
   - Los datos actuales cumplen todas las restricciones (comprobado antes).
6. **`audit_log`.**
   - Registra alta, inicio de sesión, cambio de email o contraseña y borrado de cuenta mediante triggers en `auth.users`. Las acciones `consent_given`, `consent_revoked`, `data_exported` y `admin_action` quedan preparadas para las fases 8 y 9.
   - Sin acceso desde la app: se consulta en el panel.
   - Sin FK a perfiles: el registro sobrevive al borrado de la cuenta como seudónimo.
   - Conservación: 12 meses con `private.purge_audit_log()`, que se programará.
   - Un fallo de auditoría nunca bloquea un inicio de sesión.
7. **RPC `get_profile(uuid)`**: devuelve el perfil según la relación (propio o amigo: todo; desconocido: nombre, usuario, foto y nivel), con la pareja incluida.

## 20261128b
- `profiles` solo deja leer por la API `id`, `display_name`, `username`, `avatar_url`, `avatar_id` y `self_declared_level`.
- Las vistas de amigos y solicitudes y la búsqueda devuelven la ciudad solo de los amigos. Las sugerencias no la devuelven.
- **Requiere la app nueva**: la pantalla de perfil lee con `get_profile` y muestra «—» en lado y mano de los desconocidos.

## Resultado de la validación (BD real, transacción deshecha)
- 47 de 51 pruebas OK en la primera pasada completa.
- Las 4 restantes fallaron por un error del propio test: guardaba el texto del resultado como literal sin tipo y PostgreSQL lo interpretaba como array. Las 4 operaciones (comentar, guardar preferencias, marcar avisos, enviar mensaje) **habían terminado bien** antes de esa línea. El test ya está corregido y se volverá a ejecutar completo tras aplicar la migración.

## Copias de seguridad
No puedo verlas con las herramientas disponibles. Hay que revisarlas en el panel: Database → Backups (las diarias están en todos los planes de pago; PITR es un complemento).
