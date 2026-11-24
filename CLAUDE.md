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
- Banner de Inicio: ver «Banners dinámicos» (la antigua `home_banner.jpg` se eliminó).

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
- (Banner personalizable de esta fase SUSTITUIDO el 13 nov por los banners dinámicos; ver abajo.)
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

## Banners dinámicos por hora local (13 nov 2026, v1.4.1)
- Solo 2 colecciones, visibles como **Seaside** y **Tropical** (ids internos `banner1`/`banner2`, sin cambiar) (`HomeBanner`, `home/domain/banner_schedule.dart`), 4 imágenes cada una en
  `assets/images/banners/<banner1|banner2>/<amanecer|dia|atardecer|noche>.jpg` (1376×768, del zip `Banners_Plobby.zip`).
- Franjas (hora LOCAL del dispositivo, `DateTime.now()`): 06–08:59 amanecer, 09–17:59 día, 18–19:59 atardecer, 20–05:59 noche.
  `nextPhaseChange` usa el constructor local de DateTime (cambios de hora correctos).
- `home/application/banner_clock.dart`: `bannerClockProvider` (autoDispose) = temporizador de un disparo al siguiente
  cambio + `resumed` del ciclo de vida + comprobación cada minuto (zona horaria/hora del sistema). `bannerNowProvider` para tests.
- Preferencia: `profiles.banner_id` ('banner1'/'banner2'; null o valor antiguo = Banner 1) vía RPC `set_home_banner`
  (sin cambios de esquema). `banner_url` queda en la BD sin uso (siempre NULL). Selector: `banner_picker.dart`.
- Eliminados: 8 SVG + foto clásica, subida/encuadre de foto propia (`banner_editor.dart`), `uploadBanner`/`deleteOldBanners`.
  En la BD no había banners guardados (0 perfiles, 0 ficheros `banner_*`).
- Tests: 261/261 (`test/home_banner_test.dart`, también con TZ=Europe/Madrid, America/New_York, Australia/Sydney).

## Actualización de calidad (13 nov 2026, v1.5.0)
- Banners: nombres Seaside/Tropical; el selector solo muestra dos tarjetas (imagen actual + nombre), sin horarios ni momentos.
- Migraciones aplicadas con autorización: `20261125a_feed_tournament_type`, `20261125b_security_performance`,
  `20261125c_feed_engagement`.
  - Seguridad: `avatar_url` solo de `avatars/<uid>/` (trigger `profiles_guard`, también recorta nombre 60 / ciudad 60 /
    club 80); reactions solo INSERT(post_id,user_id,reaction_type)/UPDATE(reaction_type); comments INSERT(post_id,user_id,content);
    `_rate_limit` (10 comentarios/min, 40 mensajes/min, 40 solicitudes/h, 20 denuncias/h → 'rate_limited');
    Storage `avatars_read_own` (antes cualquiera listaba todas las carpetas); anon sin permisos en torneos.
  - Rendimiento: 28 políticas con `(select auth.uid())` (el bucle es idempotente, regex con flag 'gi'); 16 índices.
  - Feed: `rating_history_feed` (rachas 3/5/10/15/20/25), `player_ratings_feed` (récord de ELO por cada múltiplo de 50),
    `tournaments_feed` (campeones; se retira si cambia el campeón). Tipo de publicación nuevo `tournament`.
- App: `collapseDuplicateMatches` (un partido = una publicación aunque lo publiquen 4 jugadores), reacciones en cola
  por publicación (orden garantizado, reversión solo de esa publicación), `TournamentPayload` + tarjeta `_Champion`,
  filtro «Competiciones» (ligas + torneos), comentarios con envío único y errores traducidos (`friendlyFeedError`),
  `cacheWidth` en todos los avatares de red.
- Pendiente: activar «Leaked password protection» en Supabase (panel); eliminación de cuenta NO existe (decidir diseño:
  hay FKs sin cascada en partidos/torneos); push con la app cerrada sigue sin Firebase.
- Tests: 267/267.

## iOS con Codemagic + TestFlight (13 nov 2026, v1.5.1)
- Guía completa para el usuario: `docs/ios_codemagic_testflight.md`. `codemagic.yaml` (workflow `ios-testflight`):
  Flutter 3.50.0, Xcode latest, integración ASC llamada «Plobby App Store Connect», grupo de variables `plobby_supabase`
  (SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY; rechaza sb_secret_/JWT service_role), analyze --no-fatal-infos, tests,
  `xcode-project use-profiles`, `flutter build ipa --build-number=$BUILD_NUMBER`, subida a TestFlight. Auto en push a `main`.
- iOS: bundle `io.plobby.plobby`, iOS 15, solo iPhone (TARGETED_DEVICE_FAMILY=1), solo vertical, CFBundleName Plobby,
  ITSAppUsesNonExemptEncryption=false, `ios/Podfile` (platform 15 + post_install sube pods a 15), `#include?` de Pods en xcconfig.
- Arreglos compartidos: iOS usa `CupertinoPageTransitionsBuilder` (gesto de volver); fontFamily Inter en los textStyle de
  botones del tema (antes fuente del sistema: SF en iOS, Roboto en Android). `test/ios_platform_test.dart`.
- NO verificado en iPhone real ni compilado para iOS (no hay macOS aquí): la primera build de Codemagic es la prueba real.

## Imágenes para compartir (13 nov 2026, v1.5.2)
- Causa de textos descentrados/solapados: coordenadas fijas, línea base adivinada (85 % vs 80 % real en Inter),
  anchos sin medir (nombres fuera de la imagen) o «…» prematuro, fila de etiquetas encogida entera, y símbolos sin
  glifo en las fuentes empaquetadas (▲ ▼ → ⏱).
- `lib/core/share/canvas_text.dart`: `ShareText` (mide, reduce hasta un mínimo antes de recortar, ancla a línea base o
  centro de mayúsculas con las métricas reales: cap Inter .7275, Unbounded .75), `ShareLayoutLog` (cajas para tests),
  `paintTriangle/paintArrow/paintClock`. Los dos pintores (`RecapPainter`, `ShareCardPainter`) lo usan; composición
  vertical por bloques medidos (`_flow`), etiquetas en hasta 2 filas, club/pareja y fecha/club en 2 líneas si no caben.
- Tests: `test/share_images_layout_test.dart` (48 combinaciones × casos de `test/support/share_fixtures.dart`: sin
  solapes, nada fuera de su caja/imagen, sin caracteres sin glifo (lee el cmap del TTF), «…» solo en textos libres del
  caso extremo, cifras nunca). Etiqueta «ELO ANTES Y DESPUÉS» (Inter no tiene «→»). Tests: 324/324.

## Gamificación: Head to Head, Friends Ranking, Wrapped, logros y niveles (13 nov 2026, v1.6.0)
- Diseño y reglas: `docs/gamificacion.md`. Migraciones `20261126a_gamification_notification_types` (enum ranking/level_up/
  wrapped) + `20261126b_gamification` — APLICADAS EN PRODUCCIÓN el 16 nov 2026 (con autorización; antes pendientes porque el conector dio 502 en esa
  sesión). Validadas en una réplica local: PostgreSQL 16 en /var/lib/postgresql/plobby_pg (puerto 5499) con
  `supabase/tests/local_supabase_stub.sql`; `supabase/tests/run_local.sh <socket> 5499` → 55/55.
- Fuente única `player_match_stats` (trigger al confirmar/desconfirmar y al cambiar sets) → RPC `head_to_head`,
  `friends_ranking` (+ cierre perezoso de temporadas `_g_close_periods` → `ranking_periods`/`ranking_snapshots`), `wrapped`,
  `wrapped_periods`, `my_achievements`, `mark_achievements_seen`, `my_season_titles`. XP en `xp_events` (único por origen),
  nivel en `player_progress` (300+100·L por nivel). Catálogo `achievement_catalog` (20); `user_achievements.seen_at`.
  Avisos con `notification_prefs` y límite diario. Desempate de victorias: % y luego MÁS partidos.
- App `lib/features/gamification/`: `GamificationEngine` (réplica Dart del SQL, usada por el mock y los tests), repos
  mock/Supabase, pantallas `/h2h/:id`, `/ranking`, `/wrapped`, `/wrapped/:kind/:yyyy-mm`, `/achievements`; imágenes con
  `ShareText` (`gamification_share.dart`, contenido centrado con doble pasada). Perfil propio → «Progreso»; perfil de amigo →
  Head to Head; Amigos → tarjeta de ranking; Inicio → logros del servidor. Eliminado el cálculo de logros en el móvil.
- Tests: 360/360 (motor, interfaz, imágenes y verificador de maquetación).

## Movimiento premium (15 nov 2026, v1.6.1)
- Referencia: shot de 60fps.design «Revolut Select Plan Tab Scroll Interaction» (selector segmentado paginado, color
  ambiente que se transforma con el desplazamiento, profundidad en tarjetas). El vídeo no se pudo descargar (permiso
  denegado); se usó la descripción oficial del shot. Red del entorno: añadidos 60fps.design y video.gumlet.io.
- `core/widgets/ambient_background.dart`: `AmbientBackground` (3 degradados radiales de la paleta, deriva 24 s, color
  por `position` + `offset` en vivo, RepaintBoundary, quieto con «reducir movimiento»). En `AppShell` detrás de las 4
  pestañas (sus Scaffold son transparentes; el perfil de otro jugador no). Paletas: home, feed, leagues, tournaments,
  profile. Tests: `AmbientBackground.driftEnabled = false` en `test/flutter_test_config.dart`.
- `ScrollLinkedTabs` (motion_widgets): píldora ligada a `PageController.page` (se estira ≤10 % a mitad).
  Competiciones = PageView deslizable (keep-alive, `_DepthPage` escala 94 % sin solapes), `CompetitionsScreen.page`
  alimenta el fondo; `competitionsTabProvider` sigue siendo la fuente (cambios externos se animan).
- `AppShell`: `_BranchFade` (fundido 240 ms al cambiar de pestaña, estructura fija para no perder estado), icono con
  «pop» al activarse, color animado, «+» con `Pressable(scale: .9)`. `Pressable` vuelve con easeOutBack 320 ms.
  Hojas: entrada 380 ms easeOutCubic / salida 240 ms. Chips del feed: transparentes salvo fijos sobre contenido.
- REGLA: un envoltorio animado debe devolver SIEMPRE la misma estructura (no `return child` a veces): si no, se
  reconstruye la sección y pierde scroll/estado. Tests: 366/366 (`test/motion_premium_test.dart`).

## Calidad Apple (skill apple-design, 15 nov 2026, v1.7.0)
- Guía única: `docs/sistema_de_diseno.md` (tokens con contraste medido, tipografía, movimiento, hápticos, estados).
- Auditoría (HIG): 28 textos <11 pt → todos ≥11 (`eb`/`key` 10,5→11); desbordes con Dynamic Type en Perfil, Feed, Inicio,
  Mi rating, Ranking, Wrapped, ligas, torneos → alturas mínimas / `textScalerOf` / FittedBox / botones apilados ≥130 %;
  Perfil roto a 320 pt arreglado. `test/accessibility_scaling_test.dart`: 22 pantallas × (320/390 pt, 100/135/200 %),
  mínimo 11 pt y muelles. OJO: restaurar `FlutterError.onError` ANTES de `expect` o el test se bloquea.
- `AppSprings` (smooth/snappy/bouncy, `SpringCurve` de SpringSimulation) y `AppHaptics` (selection/tap/success/error):
  prohibido `HapticFeedback` directo; los botones secundarios no vibran.
- Estados rediseñados (`state_views.dart`): EmptyStateCard/ErrorStateCard con PlobbyButton, LoadingBlock = SkeletonBox,
  `showPlobbySnack` = cápsula tinta con icono + háptico. Perfil y torneo cargan con esqueleto.
- Feed: sin logotipo repetido (título grande + acciones). Pestañas de torneo en lima (antes tinta). Barra inferior sin
  escalado de texto (como iOS). `supabase_rating_repository`: 3 consultas en paralelo.
- Pendiente: modo oscuro (tokens existen, falta aplicarlos), probar en móvil real. El «+» de la barra es una acción
  (HIG lo desaconseja): se mantiene por identidad.

## Versión web / PWA (16 nov 2026, rama `web-version`)
- Guía: `docs/web_pwa.md` (Vercel, variables, Redirect URLs de Supabase, añadir a pantalla de inicio, privacidad).
- `scripts/build_web.sh` (descarga Flutter 3.50.0 si falta; rechaza claves secretas; `--no-web-resources-cdn`; inyecta
  BUILD_ID en sw.js) + `vercel.json` (rewrites SPA, no-cache para index/sw/main.dart.js, noindex, cabeceras seguras).
- `web/`: index.html (viewport-fit=cover → Flutter 3.50 lee env(safe-area-inset-*), splash lima, aviso de versión
  nueva), manifest (Plobby, lima/marfil, iconos del logo), `sw.js` PROPIO (solo la app en caché por despliegue; nada de
  Supabase), `flutter_bootstrap.js` sin el SW de Flutter (es un stub que se da de baja y borraría el nuestro).
- `lib/core/share/image_io*.dart`: export condicional (nativo: gal + archivo temporal; web: Web Share con File,
  Clipboard API, descarga). `image_actions.dart`: si Safari da NotAllowedError (sin gesto reciente) → hoja «Tu imagen
  está lista» con botón. «Copiar» solo se muestra donde funciona (web). `core/net/image_fetch.dart` (http en vez de
  HttpClient de dart:io). Repos: `on http.ClientException` = error de red. OAuth web: redirectTo = origen actual.
- Verificado en Chromium con emulación de iPhone: build real → bienvenida, authorize de Supabase con PKCE y
  redirect_to correcto, SW activo sin datos de Supabase en caché; build demo → 16 pantallas, descarga PNG, Web Share
  simulado con NotAllowedError → hoja de reintento → compartido. NO verificado en Safari real ni con sesión real.

## Optimización web (16 nov 2026, rama `web-optimizacion`; estable anterior en `backup/web-v1-estable`)
- BD (con autorización): aplicadas `20261126a/b` (gamificación: los logs mostraban 404 reales en head_to_head,
  my_achievements, friends_ranking, wrapped_periods), `20261127_fk_indexes` (7 índices de FK) y
  `20261127b_gamification_search_path`. Validación en BD real: transacción + `raise exception` final (deshace todo y
  devuelve los resultados en el mensaje).
- Postgres no es el cuello de botella (notifications 1,5 ms, get_my_profile 5,5 ms en pg_stat_statements); en el móvil
  cuesta el viaje de red (~300 ms): optimizar NÚMERO de peticiones en serie. Perfil: pareja embebida
  (`partner:profiles!habitual_partner_id(...)`); LiveSync: recarga social al volver solo tras ≥10 s oculta.
- Web en reposo: `IdleMotion.loop` (app_motion) limita bucles decorativos a 3 ciclos en web; `AmbientBackground` sin
  deriva en web. Medido (Playwright, rAF/s en reposo): Inicio/Feed/Competiciones 5–9 → 0, Perfil 11 → 0, Mi rating 17 → 0.
- `image` (≈230 KB, 7,7 % del JS) en carga diferida (`tournament_cover_image.dart`, `deferred as cover`); en web la foto
  se reduce a 1200 px al elegirla. main.dart.js 5,04 → 4,66 MB. Banners: se precargan franja actual + siguiente (antes 4).
- `core/async/single_flight.dart`: acciones de partido (empezar, finalizar, aceptar/rechazar, eliminar) una sola vez por
  doble toque. Tests: `test/web_performance_test.dart`. Total 377/377.

## Falsos «sin conexión» en el iPhone (16 nov 2026, rama `fix-conectividad`; anterior en `backup/web-v2-optimizacion`)
- Causa 1 (perfil): el 15 nov el perfil pedía la pareja embebida con `profiles!habitual_partner_id`; en una relación de
  `profiles` consigo misma la pista es ambigua y la respuesta llegaba como LISTA → `as Map` lanzaba → perfil roto con
  Supabase respondiendo 200 (logs). Revertido a consulta aparte. `test/profile_repository_test.dart` usa el repositorio
  REAL con un PostgREST simulado (MockClient; ojo: la respuesta debe llevar `request:`).
- Causa 2 (mensaje): `ErrorStateCard` decía «Parece que no hay conexión» ante CUALQUIER error, y ~12 avisos decían
  «Revisa tu conexión» igual. No había detección de conectividad alguna.
- Ahora: `core/errors/failure.dart` (`FailureKind`: offline, noInternet, serviceUnavailable, timeout, auth, permission,
  server, data; `classifyError`, `diagnose` con sonda, `actionErrorText` para acciones, `refreshSessionIfPossible`;
  interfaz `CodedFailure` en las excepciones de cada funcionalidad). `core/net/network_status*.dart` (web:
  navigator.onLine solo para «sin red», eventos online/offline para reintentar; sonda = `version.json` del propio dominio
  sin caché, solo tras un fallo). `ErrorStateCard(error: e)` en las 41 pantallas: causa real, reintento automático al
  volver la red (solo lecturas, una vez), renueva sesión si es `auth`. LiveSync: cápsula «Sin conexión» (también sin
  sesión) y al volver la red renueva token caducado + refreshSocial. Las acciones nunca se reintentan solas.
- Tests: `test/connectivity_errors_test.dart`. Total 384/384.

## Seguridad y legal (22 nov 2026, rama `seguridad-legal`)
- Informes: `docs/seguridad/fase0_auditoria.md`, `docs/seguridad/fase1_base_de_datos.md`. Decisiones del usuario: solo
  Google (desactivar email/contraseña), sin rol admin por ahora, borrado de cuenta = anonimizar partidos/torneos ajenos,
  perfiles limitados para no amigos (nombre, usuario, foto, nivel).
- `20261128a_security_hardening` APLICADA (con autorización). Esquema `private` (auxiliares de RLS, no expuesto);
  auxiliares de `public` ya no invocables; permisos mínimos y **privilegios por defecto revocados: toda migración nueva
  debe hacer sus `grant` explícitos**; `audit_log` (triggers en auth.users); RPC `get_profile`.
- `20261128b_profile_visibility` PENDIENTE: rompe la pantalla de perfil de APK/web anteriores a esta rama. Aplicar cuando
  todos tengan la app nueva (que ya lee con `get_profile`).
- Pruebas: `supabase/tests/rls_isolation_test.sql` (51/51 en producción, siempre termina en ROLLBACK).
- `20261129a_storage_hardening` APLICADA (con autorización): `avatars` sigue público (decisión del usuario), solo
  `<uid>/<fichero>.jpg|jpeg|png|webp`; `group-avatars` privado 2 MB, solo admins escriben/borran, la app re-firma la URL
  (1 h) al leer (`_refreshGroupAvatars`). Informe `docs/seguridad/fase2_storage.md` (15/15).
- Fase 3 (panel, hecha por el usuario): proveedor Email DESACTIVADO (verificado: signup/login/otp/recover → email_provider_disabled).
  Solo Google. Guía `docs/seguridad/fase3_autenticacion.md`.
- `20261130a_account_lifecycle` APLICADA + Edge Function `delete-account` DESPLEGADA (verify_jwt, CORS `ALLOWED_ORIGINS`,
  por defecto https://plobby.vercel.app; cambiar el secreto cuando la web tenga dominio). Borrar de auth.users dispara
  `private.anonymize_user` (perfil «Jugador eliminado», `profiles.deleted_at`; `profiles.id` YA NO tiene FK a auth.users).
  RPC `export_my_data()` (1 cada 10 min). Códigos de liga de 8 caracteres. Informe `docs/seguridad/fase4_servidor.md` (22/22).
- Fase 5 (Android, en la rama; APK de prueba `dist/plobby-seguridad-f5.apk`, firmado con debug): sesión en
  `flutter_secure_storage` (`core/supabase/secure_session_storage.dart`, migra sola desde SharedPreferences), sin
  backups, solo HTTPS (`res/xml/network_security_config.xml`), R8 + `--obfuscate --split-debug-info`, firma desde
  `android/key.properties` si existe, logs de release solo con el tipo de error. Informe `docs/seguridad/fase5_android.md`.
  Si Maven Central da 429 al compilar, reintentar tras 1 min. SDK Android en scratchpad/android-sdk; Flutter en scratchpad/sdk/flutter.
- Fase 6 (web, en la rama): CSP estricta (sin scripts en línea: `web/app_boot.js`), HSTS, Permissions-Policy, COOP/CORP en
  vercel.json; 0 violaciones en Chromium; sin cookies ni terceros → sin banner (AEPD). `test/web_security_headers_test.dart`.
- Fase 7 (documentos legales) APLAZADA por el usuario: textos provisionales con [PENDIENTE] en `assets/legal/` y `web/legal/`.
- Fase 8 (migración `20261201a_legal_consents` APLICADA con autorización; crear perfil exige consentimiento, editarlo no): `/consent` (guardia: sin sesión →
  /welcome; sin consentimiento → /consent; sin onboarding → /onboarding), `/legal/:slug`, `/settings/privacy` (Perfil →
  Privacidad y datos). AuthRepository: legalStatus/acceptLegal/setMarketing/exportMyData/deleteAccount/signOutEverywhere.
- Fase 9: informe final `docs/seguridad/fase9_verificacion_final.md` (antes/después, 55+21+21 pruebas, ataques con curl,
  lista de tareas manuales). APK con todo: `dist/plobby-seguridad-f8.apk` (firma debug).


## Animaciones y acabado premium (22–23 nov 2026, rama `gamificacion-premium`)
- Informe: `docs/animaciones_informe.md`. Fases 0, 1, 2 y 4 aprobadas; Fase 3 (mecánicas nuevas) RECHAZADA. Sin cambios en BD.
- `core/motion/app_motion.dart`: `Motion` (fast/normal/emphasis/celebration…, curvas enter/exit/move/spring/springBounce,
  `Motion.reduced/of/fadeOr`, `forceReduced` para tests) y `AppHaptics` (light/medium/success/error; nunca fuerte; una por
  evento; interruptor «Vibración» en Perfil → Ajustes y privacidad, guardado en SharedPreferences y cargado en main).
- REGLA (test/motion_tokens_test.dart): en la interfaz nada de `Duration(` sin `// timing`, ni `Curves.`, ni `HapticFeedback.`.
- Post-partido `/match/:id/summary` (`post_match_screen.dart`, `PostMatchSummary` con datos de rating_history/xp_events/logros):
  secuencia saltable, `_Stage` = cada bloque se reconstruye solo en su tramo. Se abre al confirmar y 1 vez por partido.
- `core/widgets/celebration.dart`: confeti en código, `showCelebration` 1 vez por evento (`CelebrationLog`).
- Banco de rendimiento `tool/motion_lab/` (no se incluye en la app): `flutter build web -t tool/motion_lab/main.dart` + scripts
  Playwright en `tool/motion_lab/perf/`. El entorno no tiene GPU: el 74 % del tiempo es presentación del navegador; NO
  equivale a un móvil. Pendiente: medir en Android real con `flutter run --profile`.
- Tests: 433/433.

## Catálogo de clubes (23 nov 2026, rama `clubes`; publicada en `gamificacion-premium`, anterior en `backup/web-v3-antes-de-clubes`)
- Plan e informes: `docs/clubes/plan_y_informes.md`. APLICADAS (con autorización): `20261202a_clubs_catalog` (esquema, RLS,
  `normalize_club_name`, `club_aliases`, `search_clubs` INVOKER + `private.club_candidates` DEFINER con índices, `propose_club`,
  `club_page`, `nearby_clubs`, admin `admin_pending_clubs/admin_review_club/admin_add_club_alias` → audit `admin_action`),
  `20261202b_clubs_seed` (245 clubes + 79 alias, generado por `supabase/seed/build_clubs_seed.py` desde el CSV),
  `20261202c_clubs_text_migration` (informe en `private.club_text_migration`), `20261202d_clubs_single_field`
  («Club habitual» = club base: habitual_club_id ↔ home_club_id sincronizados), `20261202e_geocode_token`.
- Admin = `raw_app_meta_data.plobby_admin = true` (puesto a la cuenta del dueño). Alias extra: RCGLM → Real Club La Moraleja.
- Pruebas: `supabase/tests/clubs_test.sql` (62/62 en réplica local; 41/41 funcionales en producción). Búsqueda 6–10 ms con
  245 clubes; con 10.000 simulados 38–106 ms en el servidor de Supabase.
- Réplica local: PostgreSQL 16 en /var/lib/postgresql/plobby_pg (puerto 5499, socket /tmp, log /tmp/pg5499.log);
  `supabase/tests/run_local.sh` (stub con auth.jwt, pgcrypto, columnas de auth.users y USAGE de extensions).
- Geocodificación: Edge Function `geocode-clubs` (desplegada, verify_jwt=false con autorización propia: token de un solo uso
  cuyo hash está en `private.service_tokens` o admin). **Nominatim y Photon devuelven 403 desde Supabase** (bloquean IPs de nube):
  pendiente de que el usuario elija otro proveedor. 0 clubes geocodificados.
- App (`lib/features/clubs/`): buscador `pickClub` (hoja con debounce, «¿Te refieres a…?», alias, «Proponer nuevo club»
  con aviso de duplicados), página `/club/:id`, moderación `/admin/clubs` (entrada en Ajustes y privacidad solo para admin).
  Conectado en Perfil (club habitual), Onboarding (paso 2 envía `club_id`, migración `20261202f`) y Crear partido
  (buscador con el club habitual por defecto + «escribir el nombre»; `create_match` sigue recibiendo texto).
  Ligas: sin campo de club (las ligas de club se crean desde el panel). Tests `test/clubs_test.dart`. Total 451/451.
- Pendiente: decisión del usuario sobre 7 posibles duplicados del CSV; geocodificación (proveedor) y «Clubes cerca de ti».

## Sello de verificado (23 nov 2026, rama `verificado`)
- `core/widgets/verified_badge.dart`: `VerifiedBadge` (roseta lima de 9 lóbulos, reflejo holográfico que gira + franja de
  luz, check en tinta; quieto con «reducir movimiento», `IdleMotion.loop` en web). Solo en la cabecera del perfil.
- Quién: `profile/domain/verified_users.dart` (`verifiedUserIds`, por UUID; hoy solo la cuenta del dueño). Sin cambios en BD;
  si hay más verificados, pasar a columna del servidor. Tests `test/verified_badge_test.dart`. Total 454/454.

## Rendimiento + premium (24 nov 2026, en curso; fases en ramas `perf`, `fixes`, `premium`)
- Encargo en 4 fases (rendimiento, 9 fallos, diseño premium tipo Apple, verificación). Decisiones del usuario: miniaturas al
  subir (Supabase no tiene transformaciones de imagen en este plan: 403), modo oscuro en fase propia al final, publicar tras
  cada fase con su OK.
- F1 (rama `perf`, informe `docs/rendimiento/fase1.md`): web `--wasm --enable-wasm-deferred-loading` (requirió
  flutter_secure_storage 10, migra la sesión en Android), `DeferredScreen` + `deferredScreenLoaders` (precarga: móvil al
  arrancar, web 4 s tras el primer fotograma, tests en flutter_test_config), Roboto → alias de Inter, sin Unbounded Medium,
  splash ≤0,9 s y `GateCache` (con sesión validada no hay splash), `myRatingSummaryProvider` (20 filas), lectura compartida
  de get_my_profile, `HomeSnapshot` (cabecera al instante), `NetImage`/`AvatarThumbs` (_t96/_t256), banners WebP,
  caché `plobby-engine-<motor>` en sw.js, presencia con dispose. NO precargar main.dart.wasm desde HTML (doble descarga).
- Medición: `tool/perf/*.js` (Playwright, 4G lento + CPU 4×) y `test/home_requests_test.dart` (peticiones del Inicio).
- F2 (rama `fixes`, informe `docs/rendimiento/fase2.md`): `AppMaterials` (barra translúcida), `AppInsets.tabBarClearance`
  (margen inferior de pestañas), `WideLayout`/`WideFrame` (≥840 px: columna 736 = barra lateral 96 + contenido 640),
  nivel único `StatsCalculator.levelLabel` («Nivel con el que empezaste» secundario), `leagueCoverSvg(aspect:)`,
  `match_defaults.dart` (hora por defecto, hora habitual, sugeridos), `shortName`, semántica web por defecto, tema de tooltips.
  NO poner LayoutBuilder dentro de IntrinsicHeight (Inicio). `find.byTooltip` necesita la semántica del tooltip.
- F3 (rama `premium`, informe `docs/rendimiento/fase3.md`): «+» = pestaña central `PlusSquare` (cuadrado lima 44, sin
  etiqueta; elección del usuario: opción A sin «Nuevo»); `PlobbyText` escala iOS (Unbounded solo títulos grandes y cifras;
  `sec`/`t2` en Inter); `AppRadius` 12/16/24 + `AppShapes` (RoundedSuperellipseBorder); una sombra; márgenes 20; barra
  translúcida `AppMaterials.tabBar` (90 %: AA); iconos rellenos en pestaña activa (`PlobbyIcon(filled:)`); transición tipo
  iOS en todo + atrás predictivo Android; `Motion.press` 100 ms y `Motion.skeletonDelay` 300 ms; Hero solo del ELO
  ('elo-me'; avatares/partidos se repiten en pantalla); perfil con cabecera clara; feed con `groupFeed` (logros) y
  reacciones discretas; crear partido con botón fijo; Competiciones con la liga activa primero.

## Modo oscuro (24 nov 2026, rama `dark`, informe `docs/rendimiento/fase3b_oscuro.md`)
- Sigue el sistema (`PlobbyApp` observa `platformBrightness`; `KeyedSubtree(ValueKey(isDark))`). `AppColors.isDark` + getters
  semánticos; paleta en `AppColorsDark`. REGLAS: sobre lima siempre `brandInk`; texto de cuerpo = `AppColors.textBody`
  (nunca `ink700` fijo, lo vigila `test/dark_mode_test.dart`); bloques oscuros por diseño usan `ink50`/`ink900` fijos;
  los colores semánticos NO pueden ir en `const` ni en `static final` (capturarían el modo): getters.
  Pintores de imágenes para compartir dentro de `AppColors.light(...)`. `AppColors.inkA(alpha)` = tinta/blanco con alfa.
- `CollapsingTitleScaffold` (título grande que se encoge) en Competiciones.
- Herramienta: `scratchpad/tools/fix_const.py <salida de dart analyze --format=machine>` quita `const` inválidos.

## Verificación final (24 nov 2026, rama `verificacion`, informe `docs/rendimiento/fase4_verificacion.md`)
- Capturas claro/oscuro × móvil/tableta/escritorio en `docs/rendimiento/capturas/f4/`; scripts en scratchpad/perf
  (`shots_f4.js`, `a11y_f4.js` = árbol de accesibilidad con `ariaSnapshot`).
- REGLAS a11y: un Tooltip junto a una etiqueta semántica igual lleva `excludeFromSemantics: true`; los encabezados van con
  `Semantics(header: true, container: true, …)` (sin container se fusionan con sus vecinos).
- APK 1.9.0+17: `dist/plobby-1.9.0-arm64.apk` (25,3 MB) y `-armv7` (23,4 MB), ofuscados, firma debug.

## Fluidez (24 nov 2026, rama `fluidez`, PUBLICADA en `gamificacion-premium`; anterior en `backup/web-v8-antes-de-fluidez`; APK 1.9.1)
- Medir con build `--profile` + perfil de CPU (scratchpad/perf/cpu_profile.js) y trazas (trace_cost.js), comparando con
  `backup/web-v4-antes-de-rendimiento`. Los fps de este entorno no sirven (GPU por software).
- REGLAS: nada de `ensureSemantics()` global (accesibilidad web bajo demanda, `core/a11y/web_a11y*.dart`); nada de
  `BackdropFilter` directo (usar `FrostedBar`; `AppMaterials.blur` = false → barras opacas); cabeceras de
  `SliverPersistentHeader` devuelven una instancia guardada; bucles decorativos con `IdleMotion.loop` (limitados en todas
  partes); `vercel.json` con COOP same-origin + COEP credentialless (motor en hilo aparte). Vigilado por test/fluidity_test.dart.

## Pulido (24 nov 2026, rama `pulido`, APK 1.9.2)
- Icono relleno de pestaña activa: `holeColor: AppMaterials.tabBar` (antes blanco fijo → bloque blanco en oscuro).
- «+» de la barra: `PlusSquare(size: PlusSquare.tabSize)` = 42 px alineado arriba con el bloque icono + etiqueta.
- Racha del Inicio: número en `brandInk` sobre la llama lima (y llama apagada oscura en modo oscuro).
- Reacciones: las cinco siempre visibles (sin pulsación larga); etiqueta «Reaccionar con 🔥, 3».
- `LoadingBar` (MaterialApp.builder) + `NetActivity`: barra lima de 2,5 px si una petición a Supabase (TimeoutHttpClient)
  o la descarga de una pantalla diferida tarda >400 ms.
- `ref.cacheFor(2 min)` (core/state/cache_for.dart) en detalle de liga/clasificación/partidos, Head to Head, Wrapped y club.

## Oscuro legible + fotos en las imágenes (24 nov 2026, rama `compartir-oscuro`, APK 1.9.3)
- `test/dark_contrast_audit_test.dart`: renderiza 33 pantallas + hoja «+» en oscuro y mide el contraste REAL de cada texto con
  el fondo compuesto de sus ancestros (AA 4,5/3). Excluye `brandInk` (solo va sobre lima, capa hermana no detectable).
- Tokens nuevos: `AppColors.onInverseText` (texto sobre bloque de tinta) y `AppColors.scrim(alpha)` (velo SIEMPRE oscuro;
  `inkA` se aclara en oscuro → no usarlo para barreras de diálogo, cristal ni velos sobre fotos).
- Arreglados: hoja «+» (texto = color de fondo), flecha del ELO del Inicio (SVG con tinta fija), «% de victorias» de Mi
  rating, velos/cristal/diálogos, círculos `#EEF1EA` fijos, avatar gris de la paleta (ink400), subtítulo del ranking.
- Fotos: `NetImage.missing` recuerda miniaturas inexistentes (los registros mostraban 400 en bucle de `_t96/_t256` de otros
  jugadores). «Compartir mis stats» ahora descarga y dibuja la foto (antes nunca se pasaba) y, sin foto, avatar de Plobby o
  iniciales. Share Match / Head to Head / ranking / stats esperan a las fotos antes de generar el PNG.

## Oscuro por defecto para todos (24 nov 2026, rama `oscuro-por-defecto`, APK 1.9.4)
- `core/theme/theme_pref.dart`: `ThemePrefs` (dark | light | system; por defecto DARK, en SharedPreferences `plobby.theme`).
  Las cuentas existentes no tienen preferencia guardada → arrancan en oscuro. `PlobbyApp._sync` usa `ThemePrefs.isDark(...)`
  y escucha `ThemePrefs.notifier`. Selector «Apariencia» en Perfil → Ajustes y privacidad (también en la web).
- Web: `index.html` oscuro por defecto (#0D110F, un solo theme-color); `app_boot.js` lee `flutter.plobby.theme` y pone
  `html.light` + theme-color claro si toca. Tests: `flutter_test_config` fija `ThemePref.system`; `test/theme_pref_test.dart`.

## Share Match en iPhone + sello en imágenes (24 nov 2026, rama `share-verificado`, PUBLICADA; anterior en `backup/web-v12-antes-de-share-verificado`; APK 1.9.5)
- Vista previa de Share Match en blanco en Safari (iPhone): pintaba solo el fondo. El pintor funciona en Chromium con los dos
  motores (lab `tool/recap_lab/main.dart`), así que se atribuye a las fotos decodificadas por el navegador en Safari. En la web
  `fetchUiImage` decodifica en Dart (`core/net/pixel_decode.dart`, `image` diferido) → `decodeImageFromPixels`. NO verificado en Safari real.
- Sello de verificado en todas las imágenes para compartir: `core/share/verified_mark.dart` (roseta en la esquina de la foto)
  en RecapPainter, gamification_share y ShareCardPainter (`verified`).
- `NetImage.loadMissing()` en main: miniaturas inexistentes recordadas 24 h entre aperturas (seguían ~300 peticiones 400/6 h).
- Duración < 60 s → «<1 min». Humo web: `scratchpad/perf/smoke.js` (23 rutas, 0 errores de consola).
