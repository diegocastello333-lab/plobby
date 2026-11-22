# Plobby · Fase 5: app Android

## Cambios
| Punto | Antes | Ahora |
|---|---|---|
| Sesión (tokens) | SharedPreferences en texto plano (opción por defecto de `supabase_flutter`) | `flutter_secure_storage`: Android Keystore + EncryptedSharedPreferences; Keychain en iOS (`lib/core/supabase/secure_session_storage.dart`). El verificador PKCE del login con Google también va cifrado. En web no cambia (el navegador no ofrece un almacén mejor) |
| Usuarios que ya tenían la app | — | **No tienen que volver a entrar**: al abrir la versión nueva, la sesión se copia al almacén cifrado y se borra la copia en texto plano (5 tests) |
| Copias de seguridad | `allowBackup` sin declarar (= sí) | `allowBackup="false"`, `fullBackupContent="false"` y `dataExtractionRules` que excluyen todo (Android 12+) |
| Tráfico | por defecto | `usesCleartextTraffic="false"` + `network_security_config.xml`: solo HTTPS y solo CA del sistema |
| Ofuscación | ninguna | R8 (`isMinifyEnabled` + `isShrinkResources`) y Dart ofuscado con `--obfuscate --split-debug-info` |
| Firma | clave de debug | `signingConfigs.release` desde `android/key.properties` (no se sube). Sin ese fichero se firma con debug (solo para pruebas; Google Play lo rechaza) |
| Registros (logcat) | mensaje completo del error | en release solo el tipo de error, sin textos del servidor ni datos de usuarios |

### Compilar la versión de publicación
```
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env.json --dart-define=PLOBBY_BUILD=1.8.0
```
Guarda la carpeta `build/symbols` de cada versión publicada (fuera del repositorio): sin ella no se pueden leer los
informes de errores ofuscados.

### Crear tu clave de firma (una vez; guárdala bien, si la pierdes no podrás actualizar la app)
```
keytool -genkey -v -keystore ~/plobby-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias plobby
```
y crea `android/key.properties` (no se sube a GitHub):
```
storePassword=…
keyPassword=…
keyAlias=plobby
storeFile=/ruta/a/plobby-upload.jks
```
En Google Play activa «Firma de apps de Google Play»: esta clave pasa a ser solo la de subida.

## Permisos
Ver el resultado de la compilación más abajo (manifiesto fusionado).

## Play Integrity
**No se activa ahora.** Necesita la app publicada en Google Play Console y una verificación en el servidor (Edge
Function que valide el token de integridad en cada acción sensible). Hoy toda la seguridad está en el servidor (RLS +
RPC): un cliente modificado no puede leer ni escribir nada que la app original no pueda. Cuando la app esté en
Play, se puede añadir para frenar bots o trampas en el ELO.

## Borrador del formulario «Seguridad de los datos» de Google Play
Debe coincidir con la Política de Privacidad (Fase 7). Respuestas propuestas:

- **¿Recoge o comparte datos de usuario?** Sí, los recoge. **¿Comparte con terceros?** No. Supabase (base de datos y
  autenticación), Google (inicio de sesión) y el hosting web son encargados del tratamiento que actúan en nombre de
  Plobby, y Google no los cuenta como «compartir».
- **¿Datos cifrados en tránsito?** Sí (solo HTTPS).
- **¿Los usuarios pueden pedir que se eliminen?** Sí: desde la app (Ajustes → Eliminar cuenta) y desde una URL pública
  (Fase 7).

| Categoría (Google Play) | Dato | ¿Obligatorio? | Finalidad |
|---|---|---|---|
| Información personal → Nombre | nombre visible; nombre y apellidos de Google | Sí | Funcionalidad, gestión de la cuenta |
| Información personal → Dirección de correo electrónico | email de la cuenta de Google | Sí | Gestión de la cuenta |
| Información personal → ID de usuario | id interno y nombre de usuario | Sí | Funcionalidad, gestión de la cuenta |
| Información personal → Otra información | fecha de nacimiento, ciudad, club, nivel, lado, mano, bio | Fecha de nacimiento: sí; el resto opcional | Funcionalidad (y control de edad mínima) |
| Fotos y vídeos → Fotos | foto de perfil, imagen de grupo, portada de torneo | No | Funcionalidad |
| Mensajes → Otros mensajes en la app | chats privados y de grupo | No | Funcionalidad |
| Actividad en la app → Otro contenido generado por el usuario | partidos, resultados, comentarios, reacciones, ligas, torneos | No | Funcionalidad |
| Actividad en la app → Interacciones en la app | amistades, solicitudes, avisos leídos, logros | No | Funcionalidad |

**No se recogen:** ubicación del dispositivo, contactos, datos financieros, de salud, audio, archivos, calendario,
identificadores de publicidad, analítica ni informes de fallos de terceros. (Si más adelante se añaden analítica,
Firebase o notificaciones push, habrá que actualizar este formulario y la política.)
Los servidores de Supabase registran la IP en sus logs técnicos de seguridad; Google no la considera un tipo de dato
del formulario, pero se menciona en la Política de Privacidad.
