# Plobby · Fase 4: lógica sensible en servidor

## Revisión de las 64 funciones que la app puede llamar
- Todas son `SECURITY DEFINER` con `search_path` fijo (Fase 1) y comprueban quién llama: 48 con `auth.uid()` directamente,
  16 a través de auxiliares que también lo usan (`is_group_admin`, `_t_is_admin`, `is_league_manager`, `can_view_league`,
  `get_match_recap`, `_post_message`…). Ninguna acepta un `user_id` del cliente para actuar en su nombre.
- No hay pagos, moderación con roles, cambios de rol global ni envío de emails en Plobby. Los roles de grupo, liga y
  torneo solo se cambian con RPC que comprueban que quien llama es admin.
- Entradas: longitudes por restricciones (Fase 1) y validación en cada RPC (sets, fechas, visibilidad, nombres).
- **Arreglos de esta fase** (`supabase/migrations/20261130a_account_lifecycle.sql`):
  - Códigos de invitación de liga: antes `NOMBRE-XXXX` con 4 hexadecimales (65.536 combinaciones; el prefijo sale del
    nombre de la liga). Ahora 8 caracteres aleatorios de un alfabeto de 31 (~40 bits). Los 2 códigos existentes no se
    cambian para no romper invitaciones ya enviadas.
  - Máximo 64 invitados por llamada (`create_league`, `invite_to_league`).
- `service_role`: no está en la app, ni en el repositorio, ni en su historial (Fase 0). Solo la usa la Edge Function de
  borrado, como variable que inyecta Supabase. **No hace falta rotarla.**

## Borrado de cuenta (decisión: anonimizar lo compartido)
- Edge Function `supabase/functions/delete-account/index.ts`: verifica el JWT (y la pasarela, `verify_jwt`), exige el
  cuerpo `{"confirm":"ELIMINAR"}`, CORS solo para `ALLOWED_ORIGINS`, borra `avatars/<uid>/…` y borra el usuario de Auth.
- Trigger `plobby_anonymize_before_delete` en `auth.users` → `private.anonymize_user`. Sirve también si se borra desde
  el panel de Supabase.
  - **Se borra:** mensajes enviados, comentarios, reacciones, publicaciones, avisos, amistades, solicitudes, grupos,
    ligas, invitaciones, logros, XP, progreso, ELO, historial, estadísticas, preferencias y fotos.
  - **Se anonimiza:** el perfil queda como «Jugador eliminado» (sin usuario, nombre, apellidos, fecha de nacimiento,
    foto, ciudad, club, bio), para que los partidos, torneos y rankings de los demás no se rompan.
  - **Se traspasa:** admin de grupo, organizador de liga y dueño de torneo al siguiente miembro.
  - **Queda en `audit_log`:** el evento `account_deleted` con el id seudónimo (12 meses).
- `profiles.id` deja de tener FK a `auth.users` (antes `ON DELETE CASCADE`, y el borrado fallaba por los partidos).
- Volver a entrar con la misma cuenta de Google crea un perfil nuevo y vacío.

## Exportación de datos
RPC `export_my_data()`: un JSON con la cuenta, el perfil completo, el ELO y su historial, los partidos, los amigos, las
solicitudes, los mensajes enviados, los grupos, las publicaciones, los comentarios, las reacciones, los avisos, las
preferencias, los logros, la XP, las ligas, los torneos y el registro de seguridad. Solo los datos propios. Máximo 1 cada
10 minutos; queda registrada en `audit_log`.

## Validación (BD real, transacción deshecha): 22/22
Borrar a B (con partido de 4, grupo donde era el único admin, torneo del que era dueño con portada, pareja habitual)
funciona ✔ · perfil anonimizado ✔ · el partido conserva sus 4 jugadores ✔ · mensajes de B borrados y los de A intactos ✔ ·
nuevo admin del grupo ✔ · amistades borradas ✔ · la pareja de A se limpia ✔ · el torneo pasa a A ✔ · portada retirada ✔ ·
el equipo sigue ✔ · `audit_log` ✔ · no se puede pedir amistad a una cuenta eliminada ✔ · la búsqueda no la muestra ✔ ·
exportación completa y solo propia ✔ · límite de exportación ✔ · código de liga de 8 caracteres ✔ · máx. 64 invitados ✔ ·
anon no exporta ✔ · volver a registrarse da un perfil limpio ✔.
(El borrado de ficheros de Storage solo se puede probar desde la Edge Function desplegada.)
