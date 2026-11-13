# Plobby — contexto para Claude (memoria del proyecto)

Resumen de las sesiones de integración (11–12 nov 2026). Léelo antes de tocar nada. Idioma de trabajo con el usuario: español.

## Qué es y dónde está todo
- App de pádel (amigos, feed, ELO/rachas, ligas, mensajes/grupos, ciclo de partido con confirmación de capitanes).
- **Flutter** (Riverpod 2 + GoRouter, feature-first `domain/data/application/presentation`) en la raíz del repo.
- **Supabase**: proyecto `plobby`, ref `niwognkvoifrvlizcdvb`, eu-west-3. Es el ÚNICO proyecto: no crear otro.
- **GitHub**: `diegocastello333-lab/plobby`, rama de trabajo `claude/keen-mendel-f7z962` (todo subido). `main` solo tiene el commit inicial; no se ha abierto PR (preguntar antes).
- Origen: ZIP `plobby_flutter` (base Flutter) + prototipo HTML `Plobby (4).html` (diseño de referencia: marfil `#F6F8F1`, tinta `#171C19`, lima `#D2F548`, Unbounded + Inter). No rehacer ni cambiar el diseño.
- El usuario a veces cree que trabajo sobre su ordenador: NO es así salvo que comparta carpeta por Remote Control (`list_computer_folders` ha salido vacío). Trabajo sobre el repo de GitHub y el Supabase real.

## Estado (verificado)
- `flutter analyze` 0 errores · `flutter test` 133/133 · `flutter build web` OK · `flutter build apk --release` OK (61,7 MB, firmado con clave debug).
- Credenciales: solo `env.json` local (en `.gitignore`), con `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`; se pasa con `--dart-define-from-file=env.json`. Nunca subir claves; nunca usar service_role en la app.
- `lib/core/supabase/supabase_bootstrap.dart`: inicializa un único cliente y sobrescribe todos los `*RepositoryProvider`; sin credenciales la app usa los mocks (los tests dependen de ellos). `SupabaseSessionScope` recrea el ProviderScope al cambiar de usuario.
- Repos reales en `lib/features/*/data/supabase_*`: auth, profile, feed, social, rating, matches/lifecycle, leagues, messaging. (Los antiguos `supabase/integration/*.dart.txt` ya se movieron e integraron; ya no existen.)
- Guardia de rutas: sin sesión → `/welcome`; sin onboarding → `/onboarding`; después `/home`.
- Base de datos: 11/11 migraciones de `supabase/migrations` aplicadas (la última, `20261120_leagues_profile`, aplicada con autorización del usuario). RLS en todas las tablas; buckets `avatars` (público) y `group-avatars`; 14 tablas en Realtime. BD vacía (0 usuarios, 0 clubes).
- Prueba E2E con las RPC reales en transacción con ROLLBACK: 26/26 (amistad, crear/empezar/finalizar partido, resultado, disputa, corrección, confirmación, ELO ±16, feed, historial, chat + tarjeta, RLS).
- **No uses `supabase db push`**: las versiones remotas (`20261111212251`…) no coinciden con los nombres locales. Migraciones nuevas: fichero en `supabase/migrations` + SQL Editor o `apply_migration`, validando antes en transacción con ROLLBACK y pidiendo autorización.

## Decisiones tomadas
- ELO solo en servidor (`apply_match_rating`, K=32, media por pareja, límites 800–2000). `EloCalculator` en Dart la replica solo para estimaciones/tests (golden values del SQL).
- Ligas: victoria 3, derrota 1, +1 bonus si gana sin ceder set; solo partidos confirmados. Visibilidad public/private(código o invitación)/club(solicitud). Ligas de club se crean desde el panel.
- `validateSets` / `_validate_sets`: el partido acaba al ganar 2 sets (bug corregido en ambos lados).
- **`super_clipboard` eliminado** (con autorización): su dependencia nativa no compila con Gradle 9, que exige Flutter 3.50. «COPY IMAGE» ahora avisa de que no está disponible; Guardar/Compartir siguen.
- Android: AGP 9.3 / Gradle 9.5 (plantilla de Flutter 3.50); `android/build.gradle.kts` sube a 36 el compileSdk de plugins antiguos. applicationId `io.plobby.plobby`. Deep link OAuth `io.plobby.app://login-callback/` en AndroidManifest e Info.plist. En web el OAuth vuelve a la propia URL.
- `assets/images/home_banner.jpg` extraída del prototipo HTML.

## Pendiente (a 12 nov 2026)
1. **Login con Google**: Google está activado en Supabase y el cliente OAuth es válido, pero el usuario obtuvo `Error 403: org_internal` → la pantalla de consentimiento está en «Interno». Debe pasarla a **Externo**, estado «Prueba» y añadir `diegocastello333@gmail.com` como usuario de prueba (o crear el cliente en un proyecto fuera de su organización Workspace). Comprobar también que `io.plobby.app://login-callback/` está en Authentication → URL Configuration.
2. Tras el login: verificar en BD que se crea el perfil (`profiles`, `player_ratings`) y que el onboarding guarda los datos.
3. Cargar datos de `clubs` y `courts`.
4. Clave de firma propia para publicar el APK; decidir si abrir PR de la rama a `main`.

## Rediseño fiel al HTML (en curso, desde 12 nov 2026)
- Referencia visual: el prototipo HTML (Plobby (4).html = Plobby (3).html, idénticos). Medir con getComputedStyle en
  Playwright, no a ojo. Comparar cada pantalla con capturas 390×844 lado a lado antes de darla por terminada.
- Puntos de restauración en GitHub (ramas, el proxy no deja subir tags): `backup/v0-original-antes-rediseno`,
  `backup/v1-sistema-de-diseno`, `backup/v2-inicio`, `backup/v3-navegacion`, `backup/v4-perfil`, `backup/v5-partidos`, `backup/v6-ligas`, `backup/v7-feed`, `backup/v8-mensajes-amigos`, `backup/v9-elo-compartir-acceso`. Crear `backup/vN-…` tras cada fase estable (MCP create_branch).
- Hecho: P0 (perfil en blanco; fuentes Inter/Unbounded empaquetadas en assets/fonts, sin google_fonts),
  V1 sistema de diseño (`PlobbyText`, `PlobbyIcon` con los 50 iconos del HTML vía flutter_svg, `plobby_components.dart`,
  `SilhouetteAvatar`), V2 Inicio, V3 navegación, V4 perfil (+ Editar perfil), V5 partidos (menú «+», crear, detalle,
  resultado, final, editar; hojas con `showPlobbySheet`/`SheetHeader`/`SheetListItem`, `PlobbyHeaderBar`, `MatchCtaButton`),
  V6 ligas (lista, detalle con pestañas fijas, crear, descubrir, gestión; portadas = SVG del HTML vía `leagueCoverSvg`,
  ids de BD intactos: waves→arcs, diagonal→diag), V7 feed (cabecera, burbujas, filtros fijos, tarjetas, reacciones,
  comentarios). `showPlobbySheet` usa el navegador raíz: las hojas tapan la barra inferior como en el HTML.
  V8 mensajes (lista, chat, nuevo grupo, info del grupo, selector de partidos), notificaciones, amigos y añadir
  amigos (`PersonRow`, `PlayerAvatar` con paleta del HTML; imágenes de grupo p1–p8 = `GPRE` del HTML),
  V9 Mi rating, Compartir mis stats, Share Match, Bienvenida y Onboarding. Rediseño completo (V0–V9).
- Reglas: letterSpacing SIEMPRE explícito (si es null, Material añade +0.5 px); usar PlobbyText/componentes, no
  TextStyle/colores sueltos; los tests cargan las fuentes reales (test/flutter_test_config.dart).
- Tests: 235/235. `flutter analyze`: 0 errores, 0 avisos (solo infos de deprecaciones). (Los emojis salen como cuadros solo en los tests: no hay fuente de emojis.) Botones con `Semantics(container: true)` para que el lector no los fusione con el texto vecino.
- Pendiente: probar en móvil real con Supabase; build web/APK tras el rediseño. Mocks de amigos y mensajes no
  comparten la lista de amigos (solo demo). Diferencias pendientes: estado «VIVO»/panel en directo de
  amigos (el feed solo trae partidos confirmados), fecha de logros (el modelo no la guarda).

## Cierre de sesión y creación de partidos (12 nov 2026)
- Perfil propio → «Cerrar sesión» al final (`profile/presentation/widgets/logout_button.dart`): diálogo de confirmación y
  `AuthRepository.signOut()` (= `supabase.auth.signOut()`, scope local: borra la sesión del dispositivo, no la cuenta).
  `SupabaseSessionScope` recrea el ProviderScope y la guardia lleva a /welcome con `go` (sin pila → «atrás» no vuelve).
- Pantalla negra al crear partido: `clubs.first` sobre la lista vacía de la tabla `clubs` (0 filas) → StateError en build.
  Ahora: lista si hay clubes, campo de texto si no; se envía el club visible; errores de `create_match` traducidos
  (`MatchCreateException`). Verificado contra la BD real en transacción con ROLLBACK.

## Entorno de nube
- Entorno personal «plobby» (red limitada): `niwognkvoifrvlizcdvb.supabase.co`, `dl.google.com`, `services.gradle.org`, `plugins.gradle.org`, `storage.googleapis.com` + gestores de paquetes.
- El SDK de Flutter y el de Android se instalaron a mano en el scratchpad (no persisten entre contenedores); `flutter create` ya no hace falta (plataformas en el repo).

## Amigos, jugadores, pareja y avatares (12 nov 2026)
- Causa del fallo de solicitudes: `v_my_friend_requests` devuelve `elo` null para quien aún no es amigo (RLS de
  `player_ratings`) y `(j['elo'] as num)` lanzaba → la lista entera fallaba en silencio. Ahora `playerSummaryFromRow`
  es null-safe; Amigos muestra «Solicitudes pendientes» (Aceptar/Rechazar), «Enviadas» (Cancelar) y tarjeta de error.
- Sincronización: `SocialRepository.changes()` (Realtime de `friend_requests` y `notifications` filtrado por usuario)
  → `socialChangesProvider`, escuchado en `AppShell` (`refreshSocial`). Aceptar desde notificaciones refresca amigos.
- Selector de amigos: ruta `/friends/pick` con `FriendPick` (`pickFriends(context, pick)` devuelve `List<PlayerOption>`).
  Crear partido: «Añadir jugadores» (hasta 3, el orden reparte huecos) o hueco a hueco, sin duplicados.
  Pareja habitual: elegir/cambiar desde Amigos y quitar con «×» (RPC `set_habitual_partner`, exige amistad).
  `IdentityCard` usa `profileProvider('me')` para el propio perfil (con UUID no se refrescaba).
- Foto/avatar (Editar perfil → hoja `AvatarGallerySheet`): subir foto, elegir avatar (PNG renderizado con
  `renderAvatarPng` y subido, `avatar_id` guarda cuál) o eliminar (url e id a NULL). Tras cada cambio
  `AuthRepository.deleteAvatarFiles(keepUrl:)` borra las imágenes anteriores de `avatars/<uid>/`.
- Sin cambios de esquema ni de RLS. Verificado entre diego.c y antocuesta con RPC reales en transacción con ROLLBACK.

## Auditoría social y tiempo real (12 nov 2026)
- Migraciones `20261121a_direct_message_type` + `20261121b_social_sync` (aplicadas con autorización): avisos de
  mensaje privado (`direct_message`), avisos de privado/grupo que se reactivan (upsert por `dm:`/`gm:` + actor_count),
  `mark_conversation_read` los marca leídos, `cancel_friend_request` retira el aviso, `remove_friend` quita la pareja,
  `save_onboarding_step(2)` solo admite pareja amiga, `friend_count(uuid)`, trigger `friendships_broadcast` →
  Broadcast privado `user:<uid>` (política `plobby_user_topic_read` en realtime.messages), índice duplicado eliminado.
- Causa de «los mensajes no siempre llegan»: varios canales Realtime con el MISMO nombre (`groups:<uid>`, `chat:<id>`);
  el servidor cierra el anterior. Ahora `core/supabase/shared_realtime.dart` (un canal por tema, sufijo único, resyncs).
- `core/live/live_sync.dart` (MaterialApp.builder): Realtime social con refresco proporcional (`applySocialChange`),
  recarga al volver a primer plano y banner en la app (`activeConversation` evita avisar del chat abierto).
- Fuente única: `relationProvider`, `requestWithProvider`, `friendCountOfProvider`; perfil ajeno con botón según relación.
- Push con la app cerrada: NO implementado (requiere proyecto Firebase/APNs del usuario).
- Prueba de 14 pasos entre diego.c y antocuesta (+2 usuarios temporales) con ROLLBACK: todo correcto.

## Fase 3: sincronización global y estabilidad (12 nov 2026)
- Pareja habitual «no se deja»: los logs mostraban `invalid input syntax for type uuid: "lucia"` → un móvil con APK
  antiguo. Versión visible al final del perfil (`--dart-define=PLOBBY_BUILD=…`, `core/config/build_info.dart`).
- Migración `20261122_phase3_sync` (aplicada con autorización): triggers `profiles_broadcast` (foto/avatar/nombre →
  amigos y compañeros de grupo/liga), `conversation_members_broadcast`/`conversations_broadcast` (→ miembros);
  `conversations`/`conversation_members` fuera de la publicación; políticas Presence `plobby_presence_read/write`
  (`presence:<uid>`, solo amigos); `profiles.banner_id/banner_url` + RPC `set_home_banner`.
- `core/supabase/user_channel.dart`: UN canal privado `user:<uid>` (amistades, perfiles, grupos) compartido por los
  repos (creado en `SupabaseBootstrap.overrides`). `core/live/presence.dart`: Presence, activo solo en primer plano.
- `core/net/timeout_client.dart` (20 s / 60 s subidas) y `core/errors/app_errors.dart` (errores globales; en release
  un widget que falla no deja pantalla gris).
- Banner: `home/presentation/banner_catalog.dart` (9: clásico + 8 SVG) y `banner_editor.dart` (encuadre 6:5,
  JPEG 1200 px q82 con `package:image` en isolate, `avatars/<uid>/banner_*.jpg`). `deleteAvatarFiles` solo borra `avatar_*`.
- Crear partido exige 3 amigos distintos (regla del servidor): con 2 cuentas no se puede por diseño.
- Push con la app cerrada: sigue sin implementar (requiere Firebase del usuario).

## Splash, banner y presencia (12 nov 2026, v1.3.1)
- Pareja habitual / presencia «fallan»: los logs (x-client-info) muestran que el Samsung S942B de antocuesta sigue con
  un APK anterior al arreglo (envía «lucia» a las 22:17). El S928B de diego.c tiene la versión nueva. El usuario
  rechazó crear la tabla `app_config` (versión mínima): no se hizo.
- Banner con bandas: el Stack interno de `AnimatedSwitcher` daba restricciones sueltas → `cover` no llenaba. Ahora
  `layoutBuilder` con StackFit.expand + `SizedBox.expand` en `BannerImage`; encuadre con la proporción REAL del banner
  (`homeBannerAspect`, medida en Inicio antes de abrir la hoja).
- Presencia: heartbeat 30 s (re-track) y caducidad 75 s medida con el reloj del receptor (`presenceHeartbeat/Expiry`).
- Splash: paquete `plobby_icono_y_splash.zip` integrado (icono Android/iOS, splash nativo lima, `features/splash/`).
  Fuentes empaquetadas en vez de google_fonts. `SplashBoot.pending` (main) → solo una vez por arranque;
  `criticalWork` espera sesión/onboarding (6 s) y perfil propio (3 s); `authRedirect` deja pasar `/splash`.


## Competiciones: Ligas + Torneos (13 nov 2026, v1.4.0)
- La pestaña «Ligas» es ahora «Competiciones» (`tournaments/presentation/competitions_screen.dart`): Ligas (intacto,
  `LeaguesScreen(embedded: true)` solo quita Scaffold y título) | Torneos. Rutas `/tournaments/new` y `/tournaments/:id`.
- Migraciones `20261124a_tournament_notification` + `20261124b_tournaments` (aplicadas con autorización): tablas
  `tournaments`, `tournament_admins` (owner/admin → coadmins futuros), `tournament_teams`, `tournament_players` (PK evita
  duplicados), `tournament_matches` (cuadro persistido: next_match_id/next_slot, slot*_source 'A1', version).
  RLS solo lectura (`_t_can_view`); toda escritura por RPC (`create_tournament`, `replace_tournament_teams`,
  `update_tournament_info`, `record_tournament_result` con versión → `result_conflict`, `clear_tournament_result`,
  `set_tournament_match_live`, `finish_tournament`, `tournament_standings`, `my_tournaments`). Broadcast `tournament`
  por `user:<uid>` (deduplicado por transacción). Aviso `tournament_added`. Diseño en `docs/torneos.md`.
- Formatos: eliminatoria (potencia de 2, byes a las mejores semillas, pase automático), grupos + eliminatoria (reparto
  en serpiente, cruces A1vB2…), todos contra todos (método del círculo). Corregir un resultado anula en cascada.
- `TournamentEngine` (Dart) replica el SQL: lo usan el mock y los tests (mismos valores que la validación SQL).
- Validado en BD real con ROLLBACK (diego.c, antocuesta + 12 temporales): 5 parejas/3 byes, duplicados, pocas parejas,
  set inválido, empate, conflicto de versión, avance, cambio tras empezar, participante sin permisos, UPDATE directo
  denegado (42501), extraño ve 0, campeón, corrección en cascada, 7 parejas en grupos 3/4, RR de 3, ligas intactas.
- Tests: 254/254. Pendiente: probarlo en móvil con varias cuentas reales; portada se sube al bucket `avatars`.
