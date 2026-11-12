# Plobby

App social y competitiva de pádel: amigos, feed, ELO y rachas, ligas, mensajes y grupos, y el ciclo completo del
partido (programado → en juego con cronómetro → resultado → confirmación de los dos capitanes / disputa → resultado final).

- **Frontend:** Flutter (Riverpod + GoRouter, estructura *feature-first*: `domain / data / application / presentation`).
- **Backend:** Supabase (PostgreSQL + RLS, Auth con Google, Realtime y Storage). Proyecto `plobby` (`niwognkvoifrvlizcdvb`, eu-west-3).
- **Diseño:** marfil `#F6F8F1`, verde tinta `#171C19`, lima `#D2F548`; Unbounded para titulares e Inter para el resto
  (`lib/core/theme/design_tokens.dart`, `DESIGN.md`).

## Puesta en marcha

### 1. Requisitos

- Flutter estable 3.22 o superior (probado con 3.50; Dart ≥ 3.3).
- El repositorio no incluye las carpetas de plataforma. Genéralas una vez (no sobrescribe `lib/`):

  ```bash
  flutter create . --platforms=android,ios,web --org io.plobby --project-name plobby
  ```

### 2. Credenciales (nunca en el código)

La app lee la URL y la clave **publishable** (anon) de `--dart-define`. Copia la plantilla y rellénala con
Supabase → Project Settings → API:

```bash
cp env.example.json env.json
```

`env.json`, `.env*`, keystores y ficheros de Google están en `.gitignore`. **No pongas nunca la clave `secret` /
`service_role` en la app**: toda escritura sensible pasa por funciones `security definer` que validan permisos.

### 3. Ejecutar

```bash
flutter pub get
```

```bash
flutter run --dart-define-from-file=env.json
```

Sin `env.json` (o con las claves vacías) la app arranca en **modo demo** con los repositorios *mock* y datos de ejemplo:
útil para diseño y para las pruebas. Con credenciales, `lib/core/supabase/supabase_bootstrap.dart` inicializa el cliente
oficial `supabase_flutter` y sustituye todos los `*RepositoryProvider` por las implementaciones reales.

### 4. Base de datos

Las migraciones están en `supabase/migrations` y se aplican en orden de nombre:

| Migración | Contenido | Estado en el proyecto remoto |
|---|---|---|
| `20261110_core_schema` … `20261119_hardening` | perfiles, amistades, partidos, ciclo de vida, feed, notificaciones, mensajes y grupos, ELO, RLS, Storage | aplicadas |
| `20261120_leagues_profile` | ligas completas (roles, invitaciones, solicitudes, clasificación, descubrir), RLS de partidos de liga, historial de perfil, `bio`, `feed_match_summaries`, corrección de `_validate_sets` | aplicada (11 nov 2026) |

Todas están aplicadas en el proyecto remoto. La última se validó antes en una transacción con `ROLLBACK`
(13 comprobaciones de permisos y reglas) y se aplicó con `apply_migration`, que la registra en el historial.

> No uses `supabase db push` sin antes alinear el historial: las versiones remotas (`20261111212251`, …) no coinciden
> con los nombres locales (`20261110_…`) y la CLI intentaría reaplicar migraciones que ya existen. Para cambios
> nuevos, añade un fichero a `supabase/migrations` y aplícalo desde el SQL Editor o con `apply_migration`.

### 5. Configuración del panel de Supabase (no se puede hacer desde código)

1. **Authentication → Providers → Google:** Client ID y Secret de un cliente OAuth «Web» de Google Cloud.
2. **Authentication → URL Configuration:** añade el redirect `io.plobby.app://login-callback/`.
3. **Android** (`android/app/src/main/AndroidManifest.xml`, dentro de `<activity android:name=".MainActivity">`):

   ```xml
   <intent-filter>
     <action android:name="android.intent.action.VIEW"/>
     <category android:name="android.intent.category.DEFAULT"/>
     <category android:name="android.intent.category.BROWSABLE"/>
     <data android:scheme="io.plobby.app" android:host="login-callback"/>
   </intent-filter>
   ```

4. **iOS** (`ios/Runner/Info.plist`): `CFBundleURLTypes` → `CFBundleURLSchemes` = `io.plobby.app`; y
   `NSPhotoLibraryUsageDescription` / `NSPhotoLibraryAddUsageDescription` (foto de perfil y guardar imágenes).
5. **Datos iniciales:** `clubs` y `courts` (los clientes solo los leen).

## Estado verificado (12 nov 2026)

| Comprobación | Resultado |
|---|---|
| `flutter pub get` / `flutter analyze` | OK · 0 errores (solo avisos informativos) |
| `flutter test` | 133/133 |
| `flutter build web --dart-define-from-file=env.json` | OK · arranca contra el proyecto real, sin sesión redirige a `/welcome` |
| `flutter build apk --release` | OK · 61,7 MB, firmado con la clave de depuración (para publicar hace falta tu propia clave) |
| Flujo real en la base de datos (transacción revertida) | 26/26: perfiles por trigger, amistades, crear/empezar/finalizar partido, resultado, disputa, corrección, confirmación de capitanes, ELO ±16, feed, historial, chat + tarjeta de partido, RLS |
| Migraciones | 11/11 aplicadas; RLS activa en todas las tablas; buckets `avatars` y `group-avatars`; 14 tablas en Realtime |
| Copiar imagen (Match Recap) | Desactivado: `super_clipboard` no compila con Gradle 9; el botón avisa y Guardar/Compartir siguen |
| Login con Google | **No activado** en Supabase (solo email): ver «Configuración del panel» |

## Cómo está conectado

| Feature | Repositorio real | Lecturas | Escrituras (RPC `security definer`) | Tiempo real |
|---|---|---|---|---|
| Auth / onboarding | `SupabaseAuthRepository` | `get_my_profile` | `save_onboarding_step`, `complete_onboarding`, Storage `avatars/<uid>/` | sesión (`onAuthStateChange`) |
| Perfil | `SupabaseProfileRepository` | `profiles`, `player_ratings`, `get_player_history` | `update` de columnas editables, `set_habitual_partner` | — |
| Amigos | `SupabaseSocialRepository` | `v_my_friends`, `v_my_friend_requests`, `search_players` | `send/respond/cancel_friend_request`, `remove_friend` | — |
| ELO | `SupabaseRatingRepository` | `v_my_rating_detail`, `v_my_rating_changes` | ninguna (lo calcula `apply_match_rating`) | — |
| Feed y avisos | `SupabaseFeedRepository` | `feed_posts`, `feed_match_summaries`, `notifications` | `set_reaction`, comentarios, `respond_friend_request`, `join_league` | `feed_posts` |
| Partidos | `SupabaseMatchRepository` + `SupabaseLifecycleRepository` | `matches` (+ jugadores, versiones, aceptaciones) | `create_match`, `start_match`, `finish_match`, `submit_result`, `respond_result`, `update_match`, `cancel_match` | `matches`, versiones y aceptaciones |
| Ligas | `SupabaseLeagueRepository` | `my_leagues`, `discover_leagues`, `league_standings`, `leagues` | `create_league`, `join_league(_by_code)`, `respond_join_request`, `invite_to_league`, `update_league`, `leave_league`, `remove_league_member` | miembros, solicitudes y partidos de la liga |
| Mensajes y grupos | `SupabaseMessagingRepository` | `v_my_conversations`, `messages`, `v_group_members` | `send_message`, `create_group`, `send_match_card`… | `messages`, `conversations` |

- **Sesión:** la guardia de rutas (`authRedirect`) envía a `/welcome` sin sesión y a `/onboarding` si el perfil está
  incompleto. Al cambiar de usuario se recrea el `ProviderScope` para no mostrar datos en caché de otra cuenta.
- **RLS:** cada usuario solo lee lo suyo y lo de sus amigos; los partidos, solo sus participantes y (si son de liga)
  los miembros de la liga; las ligas privadas, solo miembros e invitados. Ninguna tabla tiene escritura directa salvo
  los campos editables del propio perfil, comentarios/reacciones propios y marcar avisos como leídos.
- **ELO:** solo cuentan partidos confirmados por los dos capitanes. El servidor lo aplica una vez (idempotente);
  `EloCalculator` replica la fórmula en Dart solo para mostrar una estimación antes de confirmar.

## Pruebas

```bash
flutter analyze
```

```bash
flutter test
```

- `test/elo_calculator_test.dart`: fórmula de ELO con valores obtenidos ejecutando `apply_match_rating` en Supabase.
- `test/match_lifecycle_test.dart` y `test/match_lifecycle_flow_test.dart`: reglas y ciclo completo del partido
  (inicio atómico, cronómetro por hora de servidor, versiones, disputa, confirmación, ELO aplicado una vez).
- `test/leagues_test.dart`: clasificación (misma fórmula que `league_standings`), asistente y reglas de unión.
- `test/supabase_mapping_test.dart`: conversión de filas de Supabase a modelos de la UI.
- Resto: feed, mensajería, grupos, onboarding, estadísticas, Match Recap y sistema de movimiento.

## Estructura

```
lib/
  core/        config (Env), router (GoRouter + barra inferior), supabase (bootstrap), theme, motion, widgets
  features/
    home/      Inicio
    leagues/   Ligas (lista, detalle, crear, descubrir, gestión)
    matches/   crear partido, detalle, resultado, confirmación, resultado final
    feed/  social/  profile/  rating/  messaging/  match_recap/  share_stats/  auth/
supabase/migrations/   esquema versionado
assets/images/         banner del Inicio (extraído del prototipo HTML)
docs/HISTORIAL.md      notas de desarrollo anteriores a esta integración
```
