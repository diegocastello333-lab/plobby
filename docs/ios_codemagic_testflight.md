# Plobby en iPhone: Codemagic + TestFlight (sin Mac)

Flujo: **escribes código en Windows → subes a GitHub → Codemagic compila en un Mac en la nube → TestFlight → tu iPhone.**

Lo que ya está hecho en el repositorio y lo que tienes que hacer tú con tus cuentas está separado abajo. Nadie
(ni Claude ni el repositorio) tiene tus credenciales de Apple: las introduces tú, solo en Apple y en Codemagic.

---

## A. Ya preparado en el código (no tienes que hacer nada)

| Elemento | Valor |
|---|---|
| Bundle ID | `io.plobby.plobby` (el mismo id que Android, `applicationId`) |
| Nombre en el iPhone | Plobby |
| Versión / compilación | versión de `pubspec.yaml` (ahora 1.5.1); el número de compilación lo pone Codemagic y siempre crece |
| iOS mínimo | 15.0 (iPhone 6s/SE de 1.ª generación en adelante) |
| Dispositivos | solo iPhone (iPad desactivado: el diseño es de móvil), orientación vertical |
| Icono y pantalla de carga | los de Plobby (icono 1024 px sin transparencia, como exige Apple) |
| Permisos | Fotos (elegir foto de perfil/grupo), guardar en Fotos (compartir resultados), Cámara |
| Inicio de sesión con Google | vuelve a la app por `io.plobby.app://login-callback/` (ya registrado en iOS) |
| Cifrado | `ITSAppUsesNonExemptEncryption = NO` (solo HTTPS): TestFlight no te preguntará en cada versión |
| Entitlements | ninguno (no hay notificaciones push todavía) |
| Codemagic | `codemagic.yaml` en la raíz: comprueba, ejecuta los tests, firma, genera el IPA y lo sube a TestFlight |
| Secretos | ninguno en GitHub. La URL y la clave publishable de Supabase se guardan en Codemagic |

Arreglos hechos específicamente para iPhone:
- **Gesto de volver** deslizando desde el borde izquierdo (antes no funcionaba: iOS usaba la transición de Android).
- **Fuente de los botones**: salían en la fuente del sistema (San Francisco) en lugar de Inter.
- Comprobado con la geometría de iPhone SE, 15 Pro y 15 Pro Max: nada queda bajo la Dynamic Island ni bajo el
  indicador de inicio, y no hay desbordes en las pantallas principales.

---

## B. Lo que tienes que hacer tú (una sola vez)

### 1. Apple Developer (developer.apple.com)
1. Inscríbete en el **Apple Developer Program** (99 USD/año) en <https://developer.apple.com/programs/enroll/>.
   Sin él no hay TestFlight. La aprobación puede tardar de horas a un par de días.
2. **Registra el Bundle ID**: *Certificates, Identifiers & Profiles → Identifiers → (+) → App IDs → App*.
   - Description: `Plobby`
   - Bundle ID: **Explicit** → `io.plobby.plobby`
   - Capabilities: no marques nada (de momento no hace falta ninguna).

### 2. App Store Connect (appstoreconnect.apple.com)
1. **Mis apps → (+) → Nueva app**:
   - Plataforma: iOS · Nombre: `Plobby` (si estuviera cogido en la App Store, pon p. ej. `Plobby Pádel`: es solo el
     nombre de la ficha; en el iPhone seguirá apareciendo «Plobby») · Idioma: Español (España)
   - ID de paquete: `io.plobby.plobby` · SKU: `plobby-ios` · Acceso: completo.
2. **Clave de API para Codemagic**: *Usuarios y acceso → Integraciones → App Store Connect API → Claves de equipo → (+)*.
   - Nombre: `Codemagic` · Acceso: **App Manager**.
   - Descarga el archivo `.p8` (**solo se puede descargar una vez**; guárdalo en un sitio seguro, nunca en GitHub).
   - Apunta el **Issuer ID** (arriba de la lista) y el **Key ID** de la clave.

### 3. Codemagic (codemagic.io)
1. Entra con tu cuenta de **GitHub** y autoriza la app de Codemagic para el repositorio `diegocastello333-lab/plobby`.
2. **Add application → GitHub → plobby → Flutter App**. Codemagic detecta `codemagic.yaml` automáticamente.
3. **Conectar Apple** (*Team settings → Team integrations → Developer Portal → Connect*):
   - App Store Connect API key name: **`Plobby App Store Connect`** (exactamente así: lo usa `codemagic.yaml`).
   - Issuer ID, Key ID y el archivo `.p8` del paso 2.2.
4. **Certificado de distribución** (*Team settings → codemagic.yaml settings → Code signing identities → iOS certificates*):
   - *Generate certificate* → tipo **Apple Distribution** → usa la integración anterior. Codemagic lo crea en tu cuenta
     de Apple y guarda la clave privada cifrada (nunca pasa por GitHub ni por tu PC).
5. **Perfil de aprovisionamiento**:
   - En developer.apple.com: *Profiles → (+) → App Store Connect* (Distribution) → App ID `io.plobby.plobby` →
     el certificado del paso anterior → nombre `Plobby App Store`.
   - En Codemagic: *Code signing identities → iOS provisioning profiles → Fetch profiles* → selecciona `Plobby App Store`.
6. **Variables de Supabase** (*tu app en Codemagic → Environment variables*), grupo **`plobby_supabase`**, ambas
   marcadas como **Secret**:
   - `SUPABASE_URL` = la URL del proyecto (la misma que tienes en `env.json`).
   - `SUPABASE_PUBLISHABLE_KEY` = la clave **publishable** (`sb_publishable_…`) de *Supabase → Project Settings → API Keys*.
   - **Nunca** la `service_role` ni una `sb_secret_…`: la compilación se detiene sola si las detecta.

### 4. TestFlight y tu iPhone
1. En App Store Connect → tu app → **TestFlight → Pruebas internas → (+)** → grupo `Equipo` → añádete
   (tu Apple ID tiene que ser usuario de App Store Connect; como titular de la cuenta ya lo eres).
   Activa **distribución automática** para que cada nueva compilación te llegue sola.
2. En el iPhone instala **TestFlight** desde la App Store e inicia sesión con el mismo Apple ID.

### 5. Supabase (si aún no está)
- *Authentication → URL Configuration → Redirect URLs*: debe incluir `io.plobby.app://login-callback/` (es el mismo que
  usa Android, probablemente ya esté).
- El inicio de sesión con Google sigue dependiendo de que la pantalla de consentimiento de Google esté en «Externo»
  (pendiente que ya conocías: `Error 403: org_internal`). No es algo de iOS.

---

## C. Generar una versión y subirla a TestFlight

**Primera vez / ramas que no son `main`** (`codemagic.yaml` está ahora en la rama `claude/keen-mendel-f7z962`):
1. Codemagic → tu app → **Start new build** → rama `claude/keen-mendel-f7z962` → workflow **Plobby iOS → TestFlight**.
2. Unos 20-30 min: dependencias → análisis → tests → firma → IPA → subida a App Store Connect.
   El IPA queda también en *Artifacts* de la compilación.
3. Apple procesa la compilación (5-30 min). Te llega un correo y aparece en TestFlight.
4. En el iPhone: abre TestFlight → Plobby → **Instalar**. Comprueba al final del perfil la versión
   (`1.5.1-ios.N`), así sabes qué compilación tienes.

**Después**: cuando la rama esté fusionada en `main`, cada `push` a `main` compila y sube sola una versión nueva.
También puedes lanzar cualquier rama a mano. Para cambiar la versión visible, sube `version:` en `pubspec.yaml`.

Si una compilación falla, el registro de Codemagic dice en qué paso. Los más habituales al principio: nombre de la
integración distinto de `Plobby App Store Connect`, falta el perfil de aprovisionamiento o las variables de Supabase.

---

## D. Qué probar en el iPhone (no está verificado hasta que lo pruebes tú)

Nada de esto se ha podido ejecutar en un iPhone real todavía (no hay Mac ni iPhone en el entorno de desarrollo): la
primera compilación de Codemagic es la primera prueba real de que compila en iOS.

1. Abrir la app (pantalla lima de carga) e iniciar sesión con Google; cerrar y reabrir → la sesión se mantiene.
2. Volver atrás deslizando desde el borde izquierdo en varias pantallas.
3. Perfil: cambiar la foto desde la galería (iOS pedirá permiso a Fotos la primera vez).
4. Amigos y solicitudes; chat con otra cuenta (los mensajes llegan en tiempo real); grupos.
5. Crear y consultar partidos, ligas y torneos; feed (reacciones, comentarios); ELO.
6. Banner de Inicio (Seaside/Tropical) según la hora.
7. Compartir un resultado: guardar en Fotos y compartir.
8. Poner la app en segundo plano y volver: los datos se actualizan.

Diferencias conocidas con Android:
- Sin **notificaciones push** con la app cerrada (tampoco en Android): requiere configurar APNs/Firebase.
- La copia de imagen al portapapeles («COPY IMAGE») no está disponible en ninguna plataforma.
- Para publicar en la **App Store** (no para TestFlight interno) Apple exige «Iniciar sesión con Apple» si se ofrece
  Google, además de política de privacidad y la opción de eliminar la cuenta desde la app.

## E. Entornos

Plobby usa **un único proyecto de Supabase**: la versión de TestFlight y el APK de Android usan los mismos datos
reales. Para pruebas, usa cuentas de prueba. No hay ningún secreto en la app: solo la clave publishable, y la
seguridad la garantizan las políticas RLS y las funciones del servidor.
