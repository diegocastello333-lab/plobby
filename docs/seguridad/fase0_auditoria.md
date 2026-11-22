# Plobby · Fase 0: auditoría de seguridad y privacidad

Fecha: 22 nov 2026 · Rama: `seguridad-legal` · Proyecto Supabase `niwognkvoifrvlizcdvb` (eu-west-3, Postgres 17).
Solo lectura: no se ha cambiado nada en la base de datos, la app ni la configuración.

## 1. Inventario

| Elemento | Cantidad | Notas |
|---|---|---|
| Tablas en `public` | 40 | **todas con RLS activado**; ninguna con `FORCE RLS` (no hace falta: solo el propietario la salta) |
| Vistas en `public` | 6 | todas con `security_invoker=true` |
| Funciones en `public` | 140 | 74 `SECURITY DEFINER` ejecutables por `authenticated`; **ninguna ejecutable por `anon`** |
| Buckets de Storage | 2 | `avatars` (público, 5 MB, jpeg/png/webp, 6 ficheros), `group-avatars` (privado, 0 ficheros) |
| Edge Functions | 0 | — |
| Tablas en Realtime | 12 | Realtime respeta RLS |
| Usuarios reales | 5 | todos con Google; 0 sin confirmar; 0 con MFA |
| Esquemas expuestos por la API | `public` (por defecto) | `auth`, `realtime`, `vault`… no se exponen por REST |

### Tablas, políticas y datos personales

Leyenda de políticas: S=SELECT, I=INSERT, U=UPDATE, D=DELETE. «Sin política» = denegado (solo escriben las RPC).

| Tabla | Políticas | Datos personales |
|---|---|---|
| profiles | S: todos los autenticados (solo columnas permitidas) · I/U: el propio (`id = auth.uid()`) · U por columna (9 columnas) | nombre visible, usuario, foto, ciudad, club, nivel, lado, mano, bio, pareja habitual; **nombre, apellidos y fecha de nacimiento** (no legibles por otros: sin permiso de columna) |
| player_ratings, player_progress, user_achievements, player_match_stats | S: el propio o `can_view_user` | ELO, XP, logros, estadísticas |
| rating_history, xp_events, ranking_snapshots | S: solo el propio | historial |
| friendships | S: solo las propias | grafo social |
| friend_requests | S: emisor o receptor | grafo social |
| conversations, conversation_members, messages | S: miembros (`is_member`) | **mensajes privados** |
| notifications | S/U(is_read): destinatario | actividad |
| notification_prefs | ALL: el propio | preferencias |
| feed_posts | S: `can_view_user` | actividad |
| comments, reactions | S: `can_view_post`; I/U/D: el propio (con `WITH CHECK`) | texto libre |
| comment_reports | I: el propio; sin lectura | denuncias |
| matches, match_players, match_sets, match_events, match_result_* | S: participantes o miembros de la liga | partidos, resultados |
| leagues, league_members, league_invites, league_join_requests | S: según visibilidad / gestor / el propio | mensaje de solicitud |
| tournaments, tournament_* (5) | S: `_t_can_view` | equipos, resultados |
| clubs, courts, achievement_catalog, rating_config, gamification_config, ranking_periods | S: todos los autenticados | ninguno (catálogos) |

Escrituras: salvo comentarios, reacciones, avisos leídos, preferencias y el propio perfil, **todo se escribe por RPC `SECURITY DEFINER`** que validan `auth.uid()`.

### Pruebas reales como `anon` (sin sesión, desde fuera de la app)
- `GET /rest/v1/{profiles, messages, notifications, player_ratings, matches, conversations, friendships, feed_posts, comments}` → **401 (42501)** en las 9.
- `POST /rest/v1/rpc/search_players` → **permiso denegado**.
- Listar el bucket `avatars` → `[]` (no se puede enumerar).
- `GET /auth/v1/settings` → proveedores activos: **google y email**; registro abierto; confirmación de email obligatoria (`mailer_autoconfirm=false`).

### Secretos en el código e historial
- 50 commits revisados en todas las ramas: **ninguna clave `service_role`, `sb_secret_`, JWT, clave de Google ni clave privada**. `env.json` nunca se ha subido; solo hay un ejemplo con `sb_publishable_xxxx`.
- `scripts/build_web.sh` y `codemagic.yaml` ya rechazan claves secretas.
- **Conclusión: no hace falta rotar ninguna clave por exposición en el repositorio.** (No puedo verificar si se pegó en otro sitio: chats, capturas, CI.)

### Advisors de Supabase
- Seguridad (WARN): 74× `authenticated_security_definer_function_executable` (las RPC de la app: esperado, pero hay ~12 auxiliares que no deberían ser llamables); 1× `auth_leaked_password_protection` desactivada.
- Rendimiento: 41× índice sin usar (INFO; la BD es nueva y casi vacía, no es significativo); 3× varias políticas permisivas en `matches`, `match_players`, `match_sets` (WARN).
- No hay avisos ERROR (ni tablas sin RLS, ni vistas `security definer`, ni funciones con `search_path` mutable).

## 2. Riesgos por gravedad

### Crítico
Ninguno encontrado: no hay tablas sin RLS, `anon` no lee nada, no hay secretos expuestos y la app no usa `service_role`.

### Alto
1. **No existe borrado de cuenta ni exportación de datos.** Lo exigen el RGPD (arts. 15, 17 y 20) y Google Play (URL pública de borrado). Además, 9 claves foráneas a `profiles` son `NO ACTION` (`matches.started_by/ended_by`, `match_result_versions.proposed_by`, `match_result_acceptances.user_id`, `tournaments.created_by`, `tournament_teams.player1/2`, `tournament_players.user_id`, `tournament_matches.updated_by`): **hoy, borrar un usuario desde el panel falla** si ha jugado partidos o torneos.
2. **No hay documentos legales, registro de consentimientos ni control de edad.** El onboarding pide la fecha de nacimiento pero no impide el registro de menores de 14 años.
3. **El proveedor Email/contraseña está activo y el registro abierto, aunque la app solo usa Google.** Cualquiera puede crear cuentas llamando directamente a `/auth/v1/signup`. Así se salta la app (y el futuro consentimiento), y no hay CAPTCHA ni comprobación de contraseñas filtradas.
4. **APK release firmado con la clave de debug, sin R8/minify ni ofuscación.** `android:allowBackup` no está declarado, así que vale `true` por defecto. La sesión (refresh token) se guarda en SharedPreferences en texto plano, que es lo que hace `supabase_flutter` por defecto, y puede salir en copias de seguridad.

### Medio
5. Las 74 funciones `SECURITY DEFINER` tienen `search_path=public`, no `''`. Hoy no es explotable (los usuarios no pueden crear objetos en `public`), pero no cumple la regla pedida.
6. Hay ~12 funciones auxiliares invocables por RPC: `_is_participant(match, user)`, `_t_is_admin`, `_t_can_view`, `_can_view_league_match`, `can_view_user`, `can_view_post`, `is_member`, `is_group_admin`, `is_league_member`, `is_league_manager`, `league_role`. Permiten sondear relaciones de terceros (p. ej. si X jugó el partido Y).
7. **Cualquier usuario autenticado lee el perfil básico de todos** (ciudad, club, bio, nivel, pareja habitual), y cualquiera puede registrarse. Es casi un directorio público; hay que revisarlo por minimización de datos.
8. `authenticated` tiene permisos de tabla INSERT/UPDATE/DELETE de sobra en 15 tablas (`clubs`, `courts`, `messages`, `matches`, `feed_posts`, `friendships`, `conversations`…). Hoy los bloquea RLS porque no hay política, pero es una sola barrera: falta defensa en profundidad.
9. Web sin `Content-Security-Policy` ni `Strict-Transport-Security` explícito, y `Permissions-Policy` incompleta.
10. No hay `audit_log`.
11. No puedo verificar copias de seguridad ni PITR con las herramientas disponibles (dependen del plan, en el panel).
12. Protección de contraseñas filtradas desactivada (advisor). Solo importa si se mantiene el email.

### Bajo
13. El bucket `avatars` es público. Las fotos de perfil son accesibles por URL sin sesión, aunque no se pueden listar y la ruta incluye un id aleatorio.
14. `debugPrint` de errores también sale en release (`core/errors/app_errors.dart`); puede incluir ids o mensajes del servidor.
15. Rendimiento: 3 tablas con dos políticas SELECT permisivas (se pueden fusionar). Los 41 índices sin usar no se tocan aún: la BD tiene poco uso.

## 3. Lo que ya está bien
RLS en las 40 tablas; `anon` sin permisos en tablas y funciones; vistas `security_invoker`; escrituras por RPC que validan `auth.uid()`; permisos por columna en `profiles`, `comments`, `reactions` y `notifications`; trigger `profiles_guard` (la URL de la foto solo puede apuntar a la carpeta propia y se limita la longitud de los textos); límites de frecuencia (`_rate_limit`); Storage limitado a la carpeta propia, con tamaño máximo y tipos MIME; canales Realtime privados por usuario; sin secretos en el repositorio.

## 4. Decisiones que necesito antes de la Fase 1
Ver el resumen en el chat.
