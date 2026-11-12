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
  `backup/v1-sistema-de-diseno`, `backup/v2-inicio`. Crear `backup/vN-…` tras cada fase estable (MCP create_branch).
- Hecho: P0 (perfil en blanco; fuentes Inter/Unbounded empaquetadas en assets/fonts, sin google_fonts),
  V1 sistema de diseño (`PlobbyText`, `PlobbyIcon` con los 50 iconos del HTML vía flutter_svg, `plobby_components.dart`,
  `SilhouetteAvatar`), V2 Inicio.
- Reglas: letterSpacing SIEMPRE explícito (si es null, Material añade +0.5 px); usar PlobbyText/componentes, no
  TextStyle/colores sueltos; los tests cargan las fuentes reales (test/flutter_test_config.dart).
- Siguiente: V3 navegación (barra inferior: activa en negrita sin punto, iconos del HTML), V4 perfil, V5 partidos,
  V6 ligas («torneos» en la app = ligas), feed, mensajes. Diferencias pendientes: estado «VIVO»/panel en directo de
  amigos (el feed solo trae partidos confirmados), fecha de logros (el modelo no la guarda).

## Entorno de nube
- Entorno personal «plobby» (red limitada): `niwognkvoifrvlizcdvb.supabase.co`, `dl.google.com`, `services.gradle.org`, `plugins.gradle.org`, `storage.googleapis.com` + gestores de paquetes.
- El SDK de Flutter y el de Android se instalaron a mano en el scratchpad (no persisten entre contenedores); `flutter create` ya no hace falta (plataformas en el repo).
