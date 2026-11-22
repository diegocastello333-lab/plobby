# Plobby · Fase 3: autenticación

Plobby solo permite entrar con **Google** (decisión del usuario). Casi todo se configura en el panel de Supabase; no hay
herramienta para cambiarlo desde aquí. Panel: <https://supabase.com/dashboard/project/niwognkvoifrvlizcdvb>.

## Estado actual (leído de `/auth/v1/settings`, sin sesión)
- Proveedores activos: **google: sí · email: SÍ (no se usa en la app)** · teléfono, Apple, etc.: no · anónimos: no.
- Registro abierto (`disable_signup: false`): es necesario para que entren usuarios nuevos con Google.
- Confirmación de email obligatoria (`mailer_autoconfirm: false`).

## Pasos que debes hacer tú en el panel (≈5 minutos)

1. **Desactivar email/contraseña.** Authentication → Sign In / Providers → **Email** → desactivar «Enable Email provider».
   Con esto nadie puede crear cuentas con email y contraseña llamando a la API (hoy se puede). Desaparece también el aviso
   «Leaked password protection» y dejan de aplicar la contraseña de 10 caracteres y el CAPTCHA, que solo sirven para el
   acceso con email/contraseña u OTP (Supabase no aplica CAPTCHA al inicio de sesión con Google). Los 5 usuarios actuales
   son de Google: no les afecta.
2. **URLs de redirección.** Authentication → URL Configuration:
   - *Site URL*: la URL de la web de producción (p. ej. `https://plobby.vercel.app`).
   - *Redirect URLs*: deja **solo**
     ```
     io.plobby.app://login-callback/
     https://plobby.vercel.app/**
     ```
     (cambia `plobby.vercel.app` por tu dominio real). **Quita** cualquier `http://localhost…` y el comodín de vistas
     previas `https://*-…vercel.app/**` salvo que pruebes ramas en Vercel con inicio de sesión real: cualquier vista
     previa de tu cuenta podría recibir la sesión.
3. **Sesiones.** Authentication → Sessions (algunas opciones requieren plan Pro):
   - «Detect and revoke potentially compromised refresh tokens» (rotación con detección de reutilización): **activado**.
   - Refresh token reuse interval: **10 s** (por defecto).
   - Inactivity timeout: **30 días** (si tu plan lo permite). Time-box: vacío (no forzar cierre).
   - JWT expiry (Project Settings → JWT Keys / Auth): **3600 s** (1 h, por defecto).
4. **Límites de intentos.** Authentication → Rate Limits: deja los valores por defecto o bájalos. Con solo Google, los
   relevantes son «Token refreshes» (por defecto 150 / 5 min por IP) y «Sign-ups and sign-ins» (30 / 5 min por IP).
5. **Google Cloud** (pendiente de antes): pantalla de consentimiento en **Externo**, estado «En producción» cuando
   publiques; en «Prueba» solo entran los usuarios de prueba que añadas.

Cuando lo hagas, avísame y compruebo desde fuera: que `/auth/v1/settings` ya no muestra email, que `/auth/v1/signup`
responde «Email signups are disabled» y que los advisors ya no avisan de contraseñas filtradas.

## Administradores y MFA
- **No hay rol de administrador** (decisión del usuario). Cuando se cree, irá en `auth.users.raw_app_meta_data`
  (no editable por el usuario) o en una tabla protegida, con MFA obligatorio comprobado en RLS
  (`(select auth.jwt()->>'aal') = 'aal2'`).
- **MFA (TOTP) para usuarios**: con inicio de sesión solo por Google, la verificación en dos pasos la da la propia cuenta
  de Google. Añadir TOTP de Supabase supone pantallas nuevas de alta, verificación y recuperación. Propuesta: no hacerlo
  ahora y recomendar en la ayuda activar la verificación en dos pasos de Google.

## En la app (ya está así)
- Solo botón «Continuar con Google»; sin formularios de contraseña.
- Flujo PKCE; móvil vuelve por `io.plobby.app://login-callback/`, web por su propio dominio.
- Cerrar sesión borra la sesión del dispositivo. En la Fase 8 se añade «Cerrar sesión en todos los dispositivos»
  (`signOut(scope: global)`) en Ajustes.
- Guardado seguro de la sesión en Android: Fase 5.
