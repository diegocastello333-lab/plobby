# Plobby — Perfil\n
Feature-first: `lib/features/profile` (domain / data / application / presentation) y `lib/features/share_stats`.
- Estado: Riverpod. Navegación: GoRouter (`lib/core/router/app_router.dart`: añade las rutas al router existente).
- Datos: `MockProfileRepository` (MOCK). Para Supabase implementa `ProfileRepository` (ver comentario al final de `mock_profile_repository.dart`) y cambia `profileRepositoryProvider`.
- Solo los partidos con `confirmed == true` afectan a ELO, estadísticas, logros y racha (`StatsCalculator`, con tests).
- Imagen compartible: `ShareCardPainter.toPng` usa `PictureRecorder` + `toImage` → PNG real 1080×1920 / 1080×1350.
- Fuente: Inter vía google_fonts; para la imagen exportada añade Inter como asset para que no dependa de la red.
- Instala: `flutter pub get`, luego `flutter analyze` y `flutter test`. Permisos: iOS `NSPhotoLibraryAddUsageDescription`; Android no necesita permiso extra con `gal` en API 29+.

## Feed (`lib/features/feed`)
- Dominio sellado (`FeedPayload`: partido, logro, racha, ELO, liga), repositorio abstracto + `MockFeedRepository` (MOCK) y un placeholder de Supabase documentado.
- `FeedController` (Riverpod AsyncNotifier): paginación por cursor, filtros, reacción optimista con rollback, actividad nueva en tiempo real sin duplicados y refresco al volver a la app.
- Reglas: solo partidos confirmados (el mock descarta uno sin confirmar), una reacción por usuario (`ReactionSummary.toggle`, con test), comentarios propios borrables y denuncia que oculta.
- Backend: `supabase/migrations/20261111_feed.sql` (tablas, índices, RLS, RPC `set_reaction`, triggers idempotentes con `dedupe_key`, notificaciones agrupadas, Realtime). No está aplicado ni validado, y asume tablas existentes (`profiles`, `friendships`, `matches`, `match_players`, `user_achievements`) que hay que contrastar con tu esquema real.
- Rutas a añadir al GoRouter existente: `/feed`, `/notifications`, `/player/:id` y las ya existentes `/match/:id` y `/friends`.

## Home funcional (amigos · ELO · racha · avisos · mensajes)
Nuevas features (feature-first, Riverpod, GoRouter): `social` (amigos, añadir amigos, solicitudes), `rating` (detalle ELO, solo lectura), `messaging` (conversaciones y chat), `home` (`streak_sheet.dart`, `home_wiring.dart`). El diseño del Home no se toca: solo se conectan sus botones y contadores reales (`homeCountersProvider`).
- Rutas añadidas: `/friends`, `/friends/add`, `/rating`, `/messages`, `/messages/with/:friendId`, `/messages/:conversationId`; `/notifications` ahora agrupa Hoy/Ayer/Anteriores y navega al destino según el tipo (`NotificationType.route`). `/match/:id` y `/leagues/:id` siguen siendo pantallas existentes del proyecto.
- **MOCK**: `MockSocialRepository`, `MockRatingRepository`, `MockMessagingRepository` (responde a los 2 s). **Sin conectar a Supabase**: las implementaciones reales están en `supabase/integration/*.dart.txt` (fuera de `lib/` porque requieren `supabase_flutter`; muévelas a `lib/.../data/*.dart`, descomenta la dependencia y cambia los providers `*RepositoryProvider`).
- ELO: el cliente nunca lo calcula ni lo escribe (`RatingRepository` solo tiene lectura). La barra usa umbrales de `rating_config`; el texto explicativo es informativo.
- Racha: solo partidos confirmados; háptico (`HapticFeedback`) y chispas; `EloBar` respeta `MediaQuery.disableAnimations`.
- Backend: `supabase/migrations/20261112_home_social.sql` (friend_requests, conversations, conversation_members, messages, rating_config, vistas/RPC, RLS, Realtime). NO ejecutado ni validado; los supuestos de esquema están al inicio del archivo (p. ej. `player_ratings`, `rating_history`, `v_my_friends.streak`/`last_match_label`, `v_my_rating_changes.score/opponents` quedan como TODO a adaptar). Ninguna service role key en la app.
- Pendiente de verificar: `flutter analyze` y `flutter test` no se han podido ejecutar (no hay SDK en este entorno).

## Logo + botón «+» (partido de liga / amistoso)
- **Logo:** `lib/core/widgets/plobby_logo.dart` (`PlobbyLogo`, `PlobbyMark`) (ACTUALIZADO) muestra SOLO el wordmark «plobby» en Unbounded 700 (-0.03em). Variante lima (fondos oscuros/foto) por defecto, `ink: true` para claro. Vectorial → nítido en Android/iOS. En el Home existente basta con sustituir el logo antiguo por `const PlobbyLogo(markHeight: 30)` en la esquina superior izquierda (no hay Home en este paquete).
- **Menú «+»:** `showNewMatchMenu(context)` (`HomeNav.newMatch`) abre dos tarjetas: «Crear partido de liga» / «Crear partido amistoso» (+ «Más opciones»: crear liga, descubrir ligas, que ya existían). Cada una navega a `/match/new?type=league|friendly`.
- **Formulario único:** `CreateMatchScreen` (liga: pide liga entre las ligas REALES del usuario y limita jugadores a sus miembros; amistoso: sin liga, jugadores = amigos). Validación pura `validateDraft` (con tests). Registrar resultado desde una liga reutiliza la misma pantalla: `/match/new?type=league&leagueId=…&result=1`.
- **Datos:** `MatchRepository` abstracto; `MockMatchRepository` (MOCK) y `supabase/integration/supabase_match_repository.dart.txt` (RPC `create_match`, sin verificar).
- **Supabase:** `supabase/migrations/20261113_match_type.sql` añade `matches.match_type` (enum) + `league_id` con constraint (liga ⇒ liga; amistoso ⇒ sin liga) solo si no existían — si ya tienes un campo equivalente, reutilízalo — y la RPC `create_match` (valida pertenencia a la liga / amistad, deja `confirmed_at` NULL). No toca ELO, estadísticas ni validación de resultados. Sin ejecutar.
- Rutas no existentes en este paquete que el menú usa: `/leagues/new`, `/leagues/discover` (pantallas de Ligas del proyecto).
- Pendiente: `flutter analyze`/`flutter test` no ejecutados (sin SDK aquí).


---
# Actualizaciones importantes (logo · Google · onboarding · próximos partidos · ciclo del partido)

## 1. Logo del Home
`PlobbyLogo` muestra ahora **solo el texto «plobby»** (Unbounded 700, −0.03em, lima / `ink: true` para claro). Se quitó el símbolo "P". `PlobbyMark` queda en el archivo pero ya no se usa. Nada más del header/Home cambia.

## 2. Acceso con Google (Supabase Auth) — `lib/features/auth`
- `WelcomeScreen` (logo, frase de comunidad, «Continuar con Google») → `AuthRepository.signInWithGoogle()`.
- **Implementación real**: `supabase/integration/supabase_auth_repository.dart.txt` (`signInWithOAuth(OAuthProvider.google, redirectTo: io.plobby.app://login-callback/)`, `onAuthStateChange`, sesión persistente de `supabase_flutter`, `signOut`). En `lib/` solo hay el **mock** (`MockAuthRepository`), que NO autentica con Google.
- Una cuenta Google = un usuario: `profiles.id = auth.users.id`; el trigger `handle_new_user` usa `ON CONFLICT DO NOTHING`, así que volver a entrar recupera el perfil y nunca lo duplica.
- Guardia de rutas pura `authRedirect(...)` (en `app_router.dart`, con test): sin sesión → `/welcome`; sesión sin perfil completo → `/onboarding`.
- **Onboarding** (`OnboardingScreen`, `OnboardingController`): 4 pasos, **reanudable** (`loadOnboarding`) y **solo pasos pendientes** (`pendingSteps`, mismo criterio que la RPC `onboarding_pending_steps`). 1 nombre/apellidos/usuario único con comprobación en tiempo real (debounce, `is_username_available`)/ciudad/fecha de nacimiento; 2 nivel **declarado** (separado del ELO, nunca asignado a mano) + posición (derecha/revés) + mano + club/pareja opcionales; 3 foto de galería (Storage `avatars/<uid>/…`) **o** avatar deportivo (12 diseños propios, `avatar_catalog.dart`) — se puede terminar solo con avatar; 4 bienvenida «Entrar en Plobby». Cada paso se guarda en servidor (`save_onboarding_step`, valida allí).
- Foto/avatar editables luego desde Editar perfil con el mismo `AvatarPicker`.
- Estados de carga y error en todos los pasos. RLS: cada usuario solo modifica su fila; Storage restringido a su carpeta.
- **Configuración externa pendiente (no se puede hacer desde código)**: cliente OAuth «Web» (y Android SHA-1 / iOS) en Google Cloud; activar el proveedor Google en Supabase (Client ID/Secret); añadir el redirect `io.plobby.app://login-callback/` en Supabase → URL Configuration; intent-filter en `AndroidManifest.xml`; `CFBundleURLTypes` en `Info.plist`. Los detalles están en la cabecera de `supabase_auth_repository.dart.txt`.
- Dependencia añadida: `image_picker`. Descomentar `supabase_flutter` para conectar.

## 3-7. Próximos partidos y ciclo del partido — `lib/features/matches`
- **Estados** (`MatchStatus` ↔ enum SQL `match_status`): scheduled, live, pending_result, pending_confirmation, disputed, confirmed, cancelled. Completan los existentes sin duplicarlos.
- **Próximos partidos**: `UpcomingMatchesSection` — en el Home va **justo encima de «Últimas partidas de amigos»** (`UpcomingMatchesSection()`), y en el perfil ya está insertado antes del historial. Ambos leen `upcomingMatchesProvider` (una fuente): editar/eliminar/empezar se refleja en los dos sin duplicar. Orden cronológico; estado vacío «Todavía no tienes partidos programados. ¡Es hora de organizar uno!».
- **Detalle** (`/match/:id`): fecha/hora, club, pista, tipo, liga, estado, EQUIPO 1/2 con avatar, nombre, nivel/ELO y capitán; «Editar partido» y «Eliminar partido» (solo el creador, solo si está programado; confirmación; reglas de liga: solo miembros y bloqueo a <2 h del inicio — valor por defecto, ajustable por liga).
- **EMPEZAR PARTIDO**: RPC atómica `start_match` (`UPDATE … WHERE status='scheduled'` con `now()` del servidor): dos pulsaciones simultáneas ⇒ una sola hora oficial. **Cronómetro** (`MatchStopwatch`): `serverNow − startedAt` (`ServerClock` mide el desfase con `server_time()`), nunca un contador local; sigue si se cierra la app, igual para los 4; Realtime sincroniza el estado. **FINALIZAR PARTIDO**: `finish_match` guarda fin y duración total, estado `pending_result` y abre la pantalla de resultado.
- **Resultado** (`/match/:id/result`): sets validados (al mejor de 3, mismas reglas de set de la app), ganador automático; cualquiera de los 4 propone; cada envío/corrección crea una **versión nueva**.
- **Confirmación de los dos capitanes** (obligatoria): capitán por equipo (por defecto el primero de cada equipo; visible en pantalla). `respond_result` solo deja a capitanes, compara la versión **en servidor** (aceptación obsoleta ⇒ `stale_version`), registra `(usuario, partido, versión)` único y confirma solo cuando ambos capitanes aceptaron la versión vigente. Editar tras aceptar invalida las aceptaciones; rechazar ⇒ `disputed` con motivo y aviso a los cuatro; se corrige y se vuelve a pedir. Historial de cambios en `match_events`.
- **ELO/estadísticas/clasificación/racha/feed**: ningún resultado sin confirmar los toca. `_finalize_match` (idempotente: `rating_applied_at` + `FOR UPDATE`) cierra el partido y llama al sistema existente (`apply_match_rating(uuid)` si existe, o los triggers actuales sobre `confirmed_at`). ⚠ Que solo una de las dos vías esté activa.
- **Resultado final** (`/match/:id/final`): resultado destacado, ganador, 4 jugadores con cambio de ELO, fecha, club/pista, duración total, inicio/fin, liga; accesible desde el historial.
- **Seguridad**: las tablas nuevas no tienen escritura directa para clientes; las columnas de ciclo de vida de `matches` solo cambian dentro de las RPC (trigger `_guard_match_lifecycle` + `set_config('plobby.rpc')`); RLS de lectura solo para participantes; sin service-role key en la app.
- **MOCK vs real**: `MockLifecycleRepository` (mismas reglas, en memoria, para tests) vs `supabase/integration/supabase_lifecycle_repository.dart.txt` (RPC + Realtime). La app usa el mock hasta que lo sustituyas en `lifecycleRepositoryProvider`.
- Migraciones nuevas: `20261114_auth_profiles.sql`, `20261115_match_lifecycle.sql` (**no ejecutadas ni validadas**; asumen las tablas de migraciones previas — contrasta nombres/columnas con tu esquema real).
- Tests nuevos: `test/auth_onboarding_test.dart`, `test/match_lifecycle_test.dart` (**escritos pero no ejecutados**: no hay Flutter SDK aquí; ejecuta `flutter analyze && flutter test`).


## Pulido visual y microanimaciones (UI polish)
Solo presentación; no cambia lógica, rutas, datos ni acciones.
- `lib/core/motion/app_motion.dart`: `AppAnimations` (duraciones, curvas, press 0.97, retraso escalonado con tope, reduce-motion),
  `AppLayout` (alturas 44/48, gaps), `AppCardStyles`, `AppTransitions` (PageTransitionsTheme: fundido + 4 % de desplazamiento; GoRouter intacto),
  `AppearRegistry` (una aparición por clave). `AppSpacing/AppRadius/AppTypography/AppButtonStyles` siguen en `core/theme`.
- `lib/core/widgets/motion_widgets.dart`: `Pressable`, `SectionHeader`/`SectionLink` (eje común, 44 dp), `AppearOnce`, `SkeletonBox`/`MatchCardSkeleton`,
  `CountUpText`, `DeltaChip`, `PopOnEvent`, `BellBadge`, `SlidingTabs`.
- Aplicado en: perfil (`_section` y «Ver todos los partidos»), Próximos partidos (skeleton + aparición única + botón centrado), campana del feed.
- Pendiente de cablear por pantalla (componentes listos): `SlidingTabs` en las pestañas del perfil/feed/estadísticas, `CountUpText`+`DeltaChip` en la tarjeta ELO
  alimentados por el evento «resultado confirmado», `PopOnEvent` en logros/racha, `Pressable` en el resto de tarjetas.
- Tests: `test/motion_system_test.dart`. **No ejecutados** (no hay SDK de Flutter en este entorno): corre `flutter analyze && flutter test`.

## PLOBBY MATCH RECAP (compartir resultado)
`lib/features/match_recap/`
- `domain/recap_data.dart`: `RecapData.fromMatch` (puro). **Lanza `RecapException`** si el partido no está `confirmed` con los dos capitanes, no hay sets o el usuario no juega. Ganadores primero; ELO/duración/stats `null` si no existen (no se dibujan).
- `application/recap_painter.dart`: **un único `CustomPainter`** (3 plantillas × 3 formatos con layouts propios, no recortes). `RecapPainter.toPng` graba el mismo painter en `PictureRecorder` → `toImage(1080×H)` → PNG real (sin UI). La previsualización usa el mismo painter.
- `application/recap_service.dart`: `RecapImageLoader` (fotos de red, fallo → avatar/iniciales), guardar (`gal`), menú nativo (`share_plus`), copiar imagen (`super_clipboard`, devuelve `copyUnsupported` si la plataforma no lo permite).
- `presentation/share_match_screen.dart`: ruta **`/match/:id/share`** (subruta añadida; las demás intactas).
- Entradas «COMPARTIR RESULTADO»: detalle del partido (confirmado), resultado final, hoja del historial del perfil.
- Notas: «INSTAGRAM STORY» abre el menú nativo con PNG 9:16 (no hay deep-link directo a Stories). `MatchPlayer.elo` se interpreta como ELO previo al partido (confirmar con el backend). Tests: `test/match_recap_test.dart`. **No ejecutados** (sin SDK Flutter): `flutter pub get && flutter analyze && flutter test`. Añade `super_clipboard` a pubspec (ya incluido) y permisos de galería en Info.plist/AndroidManifest para `gal`.

### Match Recap · integración (21 nov)
- Botón/icono «COMPARTIR RESULTADO»: detalle del partido (confirmado), resultado final, tarjetas del historial del perfil (`MatchCard.onShare`, icono discreto 44 dp, solo `confirmed` y propio perfil) y hoja de detalle del historial. Un único generador y una única pantalla (`/match/:id/share`) para amistosos y ligas.
- Candado en servidor: `supabase/migrations/20261116_match_recap.sql` → `get_match_recap(uuid)` solo devuelve datos si `status='confirmed'`, ambos capitanes aceptaron la `result_version` vigente y quien llama participa. Para usarlo en producción, sustituye el origen de `recapDataProvider` por esa RPC (hoy usa `matchProvider`, que en Supabase ya está protegido por RLS). Sin ejecutar.

## Mensajería: grupos + resultados de partido en cualquier chat (`lib/features/messaging`)
Todo vive dentro de **Mensajes** (mismo listado, mismo chat, mismo compositor): no hay una app aparte. El 1:1 no cambia.
- **Migración** `supabase/migrations/20261117_messaging_groups.sql`: `conversations.kind/name/avatar_*`, `conversation_members.role`, `messages.payload` y tipo `system`; RPC `create_group`, `update_group`, `add_group_members`, `remove_group_member`, `set_group_admin`, `leave_group`, `send_match_card`; vistas `v_my_conversations` y `v_group_members`; realtime. Invariantes: solo amigos, solo admins gestionan, nunca sin admin (el miembro más antiguo hereda), grupo vacío se borra. `get_or_create_conversation` y `on_friend_removed` solo afectan a chats directos.
- **Tarjeta de resultado**: el cliente solo envía el id del partido; `send_match_card` llama a `get_match_recap` (solo CONFIRMADO por los dos capitanes y con el usuario como participante) y guarda un **snapshot** en `messages.payload`: persiste en el historial aunque el partido cambie y no se puede editar desde el chat. `send_message` rechaza `match`/`system`.
- **UI**: `conversations_screen` (grupos con foto, remitente, hora, no leídos; botón «Nuevo grupo»), `new_group_screen`, `group_info_screen` (insignia ADMIN, editar nombre/foto, añadir, ascender/degradar/quitar, abandonar), `chat_screen` (cabecera de grupo, remitente+foto, mensajes de sistema, icono 🏆 en el compositor de TODOS los chats), `match_picker_sheet` (solo partidos confirmados, con búsqueda), `match_result_card`. Rutas: `/messages/group/new` (antes de `:conversationId`) y `/messages/:conversationId/info`.
- **Integración**: `supabase/integration/supabase_messaging_repository.dart.txt` (RPCs, storage `group-avatars`, realtime de mensajes y de cambios de grupo) y `confirmedMatches()` en el repositorio de ciclo de partido. Dependencia: `image_picker`.
- **Tests**: `test/messaging_groups_test.dart` (mock con las mismas reglas que el SQL). Sin ejecutar aquí (no hay SDK de Flutter).
- **Límites conocidos**: un miembro que no jugó el partido no puede abrir `/match/:id/final` por RLS → ve el detalle desde el snapshot; `read_at` es un único flag, así que no hay «leído por» por miembro en grupos; las notificaciones push de mensajes requieren un trigger/Edge Function (no incluido).

## Integración con Supabase y GitHub

**Frontend de producción: Flutter (este proyecto).** El archivo HTML («artefacto») es el *prototipo clicable* con datos en memoria:
sirve para validar diseño y flujos, **no se conecta a Supabase ni se mezcla con Flutter**. Ambos comparten el mismo diseño, textos y
reglas de negocio; el backend real (Supabase) solo lo consume Flutter.

**Backend:** proyecto Supabase `niwognkvoifrvlizcdvb` (eu-west-3). URL y clave *publishable* se inyectan en compilación, no se guardan en el repo:

```bash
cp env.example.json env.json        # rellena SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY (Supabase → Project Settings → API)
flutter pub get
flutter run --dart-define-from-file=env.json
```
`lib/core/config/env.dart` expone `Env.hasSupabase`. **Nunca** pongas la clave `secret` / `service_role` en la app.

**Migraciones** (`supabase/migrations`, orden por nombre; todas aplicadas en remoto): core_schema → feed → home_social → match_type →
auth_profiles → match_lifecycle → match_recap → messaging_groups → policies_rating_storage → hardening.
Modelo: el cliente solo hace `select` (RLS); toda escritura pasa por funciones `security definer` (create_match, submit_result,
respond_result, send_message, create_group…). El ELO se calcula en servidor (`apply_match_rating`). Fotos: buckets `avatars` (público lectura,
escritura en `<uid>/`) y `group-avatars` (privado, solo miembros).

**Activar los repositorios reales** (pendiente; no compilado): copiar `supabase/integration/*.dart.txt` a su carpeta `data/` como `.dart`,
inicializar `Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabasePublishableKey)` en `main.dart` si `Env.hasSupabase` y
sobrescribir los `*RepositoryProvider` en el `ProviderScope`. Sin credenciales la app sigue usando los mocks.

**Configuración manual en el panel de Supabase:** Authentication → Providers → Google (Client ID/Secret) y URL Configuration
(`io.plobby.app://login-callback/`); datos iniciales de `clubs` y `courts` (los clientes solo los leen).
