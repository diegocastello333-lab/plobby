# Plobby · Fase 8: aceptación en el registro y Ajustes de privacidad

## Flujo
1. «Continuar con Google» → **pantalla de aceptación** (`/consent`), antes del onboarding:
   - ☐ «He leído y acepto los **Términos y Condiciones** y la **Política de Privacidad**» (obligatoria, desmarcada, con enlaces).
   - ☐ «Confirmo que tengo **14 años o más**» (obligatoria, desmarcada).
   - ☐ «Quiero recibir novedades y comunicaciones comerciales» (**opcional e independiente**, desmarcada).
   - «Continuar» desactivado hasta marcar las dos obligatorias. «No acepto · Cerrar sesión» para salir.
2. Si cambia la versión de un documento obligatorio, al abrir la app se muestra la misma pantalla con «Hemos actualizado
   nuestras condiciones» y no se puede seguir sin aceptar.
3. **Perfil → Privacidad y datos** (`/settings/privacy`): documentos, interruptor de comunicaciones comerciales,
   «Descargar mis datos» (JSON; en el móvil, hoja de compartir/guardar; en la web, descarga), «Cerrar sesión en todos los
   dispositivos» y «Eliminar mi cuenta» (hay que escribir ELIMINAR; llama a la Edge Function `delete-account`).

Los **5 usuarios actuales** verán la pantalla de aceptación la próxima vez que abran la versión nueva (no tienen
consentimientos registrados). Las versiones antiguas de la app no la muestran, pero siguen funcionando (editar perfil no
se bloquea); un usuario NUEVO con un APK antiguo no podría completar el registro (el servidor exige el consentimiento).

## Servidor (`supabase/migrations/20261201a_legal_consents.sql`)
- `legal_documents`: versión vigente de cada documento (`terms`, `privacy`, `age` obligatorios; `community`, `cookies`,
  `legal_notice`, `deletion`, `marketing` informativos u opcionales). Hoy todos en v1 con texto **provisional**.
  Para publicar un texto nuevo: actualizar `assets/legal/*.md` + `web/legal/*.html` y subir `version` en esta tabla.
- `user_consents` (usuario, documento, versión, fecha, plataforma, IP, revocación). RLS: cada usuario **solo lee lo
  suyo**. Solo se escribe con las RPC `accept_legal` / `set_marketing_consent`, que fijan la versión vigente y la hora del
  servidor (no se puede aceptar una versión vieja ni falsear la fecha). Se conserva tras borrar la cuenta como prueba.
- `legal_status()` para la app; `export_my_data()` incluye los consentimientos; `audit_log` registra aceptar y retirar.
- Validación en servidor: sin consentimiento no se puede **crear** el perfil (`save_onboarding_step` con el onboarding sin
  completar, `complete_onboarding`); `accept_legal` rechaza a menores de 14 años según su fecha de nacimiento.

## Documentos (provisionales hasta la Fase 7)
`assets/legal/*.md` (dentro de la app, sin conexión ni sesión) y `web/legal/*.html` (URL pública, sin JavaScript, compatible
con la CSP): términos, privacidad, cookies, aviso legal, normas de la comunidad y **eliminar cuenta** (cómo pedir el borrado
sin la app, para Google Play). Todos llevan versión y huecos `[PENDIENTE: …]`.

## Pruebas
- SQL (BD real, ROLLBACK): `supabase/tests/legal_consents_test.sql` → 21/21.
- App: `test/legal_consent_test.dart` (guardia, re-aceptación, casillas desmarcadas, botón desactivado, marketing
  independiente, documentos en app y web, borrado protegido con ELIMINAR). Total 404/404.
