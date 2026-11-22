# Plobby · Fase 9: verificación final (22 nov 2026)

## Antes y después
| Aspecto | Antes (Fase 0) | Después |
|---|---|---|
| Tablas de `public` con RLS | 40/40 | **42/42** (+ `user_consents`, `legal_documents`) |
| Permisos de `anon` | ninguno en tablas | ninguno en tablas, vistas **ni funciones** (comprobado por catálogo y desde fuera) |
| TRUNCATE / REFERENCES / TRIGGER para `authenticated` | en 9 tablas | **en ninguna** |
| Escrituras de `authenticated` | INSERT/UPDATE/DELETE de sobra en 15 tablas (solo frenadas por RLS) | solo las columnas que usa la app, más RLS con `WITH CHECK` |
| Objetos nuevos | heredaban permisos para anon/authenticated | **sin permisos por defecto**: hay que concederlos expresamente |
| Funciones auxiliares de RLS invocables por RPC | 11 (sondeo de relaciones ajenas) | **0** (esquema `private`, no expuesto) |
| `search_path` en funciones | `public` (sin `pg_temp` al final) | fijo en todas: `''` en las nuevas y `pg_catalog, public, pg_temp` en las existentes |
| Validación en servidor | parcial | límites de longitud y tamaño en todas las tablas con texto libre; 3 restricciones validadas |
| Registro de auditoría | no existía | `audit_log`: alta, inicio de sesión, email, contraseña, borrado, consentimientos, exportación (12 meses) |
| Borrado de cuenta | **imposible** (fallaba por los partidos) | Edge Function + anonimización; probado (21/21) |
| Exportación de datos | no | `export_my_data()` (JSON, 1 cada 10 min) |
| Consentimientos | no | `user_consents` + aceptación obligatoria + re-aceptación por versión |
| Edad mínima | solo en el onboarding | también al aceptar los documentos (`too_young`) |
| Perfil visible para cualquiera | ciudad, club, bio, pareja… | `get_profile` por relación (la restricción de columnas, `20261128b`, se aplica cuando todos tengan la app nueva) |
| Códigos de invitación de liga | 4 hexadecimales (adivinables) | 8 caracteres aleatorios (~40 bits) |
| Storage | extensión libre, subcarpetas, UPDATE sin WITH CHECK; imagen de grupo con enlace de 1 año | solo jpg/jpeg/png/webp en la carpeta propia; grupo 2 MB, solo admins; enlace de 1 h |
| Proveedores de login | Google + **email abierto** | **solo Google** (email desactivado y comprobado) |
| Sesión en Android | SharedPreferences en texto plano | Keystore cifrado (migración automática) |
| APK | sin ofuscar, backup permitido, firma de debug | R8 + Dart ofuscado, sin backup, solo HTTPS; **firma propia pendiente** |
| Web | sin CSP ni HSTS | CSP estricta, HSTS, Permissions-Policy, COOP/CORP; 0 violaciones |
| Advisors de seguridad | 74 WARN (funciones) + contraseñas filtradas | 68 WARN, todas RPC de la app que validan `auth.uid()` (ninguna auxiliar); «contraseñas filtradas» sin efecto (no hay contraseñas); 1 INFO intencionado (`audit_log` sin políticas) |
| Avisos críticos (ERROR) | 0 | **0** |

## Pruebas en producción (todas con usuarios temporales y ROLLBACK)
- Aislamiento y flujos de la app (`supabase/tests/rls_isolation_test.sql`): **55/55**.
- Borrado y anonimización, exportación, códigos de liga (`account_lifecycle_test.sql`): **21/21**.
- Consentimientos (`legal_consents_test.sql`): **21/21** antes de aplicar, más **6/6** con la versión final aplicada.
- Storage (Fase 2): **15/15**.
- App: `flutter analyze` sin errores ni avisos; `flutter test` **404/404**.

## Ataques desde fuera (curl con la clave pública, sin sesión)
- Leer `profiles`, `messages`, `notifications`, `player_ratings`, `matches`, `conversations`, `friendships`, `feed_posts`,
  `comments`, `audit_log`, `user_consents`, `legal_documents`, `v_my_friends` → **401** en todas.
- Insertar un comentario / borrar perfiles → **401**.
- RPC `get_profile`, `search_players`, `export_my_data`, `legal_status`, `accept_legal`, `get_my_profile`, `is_member`
  → **permiso denegado**.
- Listar el bucket de fotos → vacío. Subir sin sesión → **403**.
- Registrarse con email → «Email signups are disabled». Borrar una cuenta sin sesión → **401**.

## Lo que tienes que hacer tú
**Para seguir usando la app con seguridad**
1. Instalar el APK nuevo (`dist/plobby-seguridad-f8.apk`) en todos los móviles, y desplegar la web desde la rama
   `seguridad-legal`. Después, avisar para aplicar **`20261128b`** (perfiles limitados para no amigos).
2. Comprobar en el móvil: que no hay que volver a entrar, la pantalla de aceptación, «Descargar mis datos» y, con una
   cuenta de prueba, «Eliminar mi cuenta».
3. Supabase → Database → Backups: comprobar que las copias diarias están activas (y PITR si el plan lo incluye).
4. Programar la purga de `audit_log` (12 meses): activar pg_cron en Supabase y programar `select private.purge_audit_log();`
   (o pedírmelo).

**Antes de publicar**
5. **Fase 7**: datos del titular (nombre o razón social, NIF, dirección, email, DPO) y redacción de los documentos; que los
   **revise un abogado**. Al publicarlos, subir la versión en `legal_documents` para que todos acepten el texto definitivo.
6. **Clave de firma propia** del APK (`docs/seguridad/fase5_android.md`) y guardarla en lugar seguro.
7. **Google Play**: rellenar «Seguridad de los datos» con el borrador de la Fase 5 y poner la URL de eliminación de cuenta
   (`https://TU-DOMINIO/legal/eliminar-cuenta.html`).
8. **Google Cloud**: pantalla de consentimiento en «Externo» → «En producción», con las URL de privacidad y términos.
9. **Dominio de la web**: cuando lo tengas, ponerlo en Supabase (Site URL y Redirect URLs) y en Edge Functions → Secrets →
   `ALLOWED_ORIGINS`.

**Opcional / más adelante**
10. Play Integrity cuando la app esté en Google Play.
11. Fotos de perfil privadas con URL firmadas (hoy públicas, decisión tuya).
12. Pasar las 129 funciones antiguas a `search_path = ''` reescribiéndolas (hoy ya es seguro con `pg_temp` al final).
13. No hace falta rotar ninguna clave: la `service_role` nunca estuvo en la app ni en el repositorio.
