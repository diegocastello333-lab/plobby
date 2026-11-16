# Plobby Web (PWA para iPhone)

Es la misma app Flutter compilada para el navegador: mismas pantallas, misma lógica y la misma base de datos de
Supabase (proyecto `niwognkvoifrvlizcdvb`). No hay datos de prueba ni base de datos paralela.

## 1. Por qué Vercel

| | Vercel | Netlify | Firebase Hosting |
|---|---|---|---|
| Conectar el repositorio privado de GitHub desde el navegador | Sí (también desde el iPhone) | Sí | No: hace falta la CLI en un ordenador o una cuenta de servicio |
| Compila Flutter en su servidor | Sí, con `scripts/build_web.sh` (descarga Flutter 3.50.0) | Sí, igual | Hace falta GitHub Actions |
| Despliegue automático en cada `git push` | Sí | Sí | Con Actions |
| HTTPS, cabeceras y rutas de SPA | `vercel.json` | `netlify.toml` | `firebase.json` |
| Gratis | Plan Hobby | Plan Starter (300 min de compilación/mes) | Plan Spark |

Vercel es lo más directo: se configura entero desde la web, compila en cada push y el plan gratuito sobra para
pruebas. Netlify valdría igual (bastaría un `netlify.toml` con el mismo comando); Firebase exige más pasos con
herramientas de ordenador.

## 2. Desplegar (una vez, unos 10 minutos)

1. Entra en <https://vercel.com> → **Sign Up** → **Continue with GitHub**.
2. **Add New… → Project** → importa `diegocastello333-lab/plobby` (autoriza el acceso al repositorio privado).
3. En la pantalla de configuración:
   - **Branch**: el despliegue de producción sale de la rama por defecto (`main`). Mientras la versión web viva en
     `web-version`, cambia la rama de producción a `web-version` (en Vercel: *Settings → Environments → Production → Branch Tracking*; en versiones anteriores del panel, *Settings → Git → Production Branch*).
   - **Framework Preset**: *Other*. Build, Output e Install ya vienen de `vercel.json` (no los cambies).
   - **Environment Variables** (Production y Preview):
     - `SUPABASE_URL` = `https://niwognkvoifrvlizcdvb.supabase.co`
     - `SUPABASE_PUBLISHABLE_KEY` = la clave **publishable** (Supabase → Project Settings → API Keys). Nunca la
       `service_role` / `sb_secret_…`: el script de compilación la rechaza.
4. **Deploy**. La primera compilación tarda unos 5–8 minutos (descarga Flutter); las siguientes, parecido.
5. Te dará una URL como `https://plobby-xxxx.vercel.app`. En *Settings → Domains* puedes cambiarla por otra
   `algo.vercel.app` libre (p. ej. `plobby-app.vercel.app`).

### Supabase (imprescindible para entrar con Google)

Supabase → **Authentication → URL Configuration → Redirect URLs** → añade:

```
https://TU-PROYECTO.vercel.app/**
https://*-diegocastello333-labs-projects.vercel.app/**
```

(La segunda cubre las vistas previas de cada rama; ajusta el nombre de tu cuenta de Vercel). Sin esto, tras elegir la
cuenta de Google volverías a otra dirección. No hace falta tocar Google Cloud: Google vuelve a Supabase, y Supabase a
Plobby. La pantalla de consentimiento de Google debe estar en «Externo» (ver CLAUDE.md, «Login con Google»).

## 3. Abrirla en el iPhone y añadirla a la pantalla de inicio

1. Abre la URL de Vercel en **Safari**.
2. Inicia sesión con Google.
3. Pulsa **Compartir** (cuadrado con flecha) → **Añadir a pantalla de inicio** → **Añadir**.
4. Abre Plobby desde el icono: se abre a pantalla completa, sin barras de Safari, con el icono y el nombre de Plobby.
   La sesión se conserva.

## 4. Generar la versión de producción en local

```bash
export SUPABASE_URL=https://niwognkvoifrvlizcdvb.supabase.co
export SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
bash scripts/build_web.sh          # resultado en build/web
cd build/web && python3 -m http.server 8080   # http://localhost:8080
```

## 5. Acceso privado durante las pruebas

- Los datos ya son privados: sin sesión no se ve nada y RLS limita cada consulta a lo que ese usuario puede ver.
- La web no aparece en buscadores (`noindex` en la página y en la cabecera `X-Robots-Tag`).
- Para que solo entren tus probadores: Supabase → **Authentication → Sign In / Providers → Allow new users to sign
  up = OFF** cuando ya se hayan registrado. Para añadir a alguien después: **Authentication → Users → Invite user** con
  su correo de Google (Supabase vincula la cuenta de Google con el mismo correo). Es el control real, en el servidor:
  una contraseña o filtro dentro de la web se podría saltar.
- Vercel protege por defecto las URL de vista previa (solo tu cuenta de Vercel); la de producción es pública, pero
  sin sesión no muestra datos.

## 6. Qué se guarda en caché (PWA) y qué no

- `web/sw.js` guarda **solo la app** (código, motor, fuentes e imágenes de la app) en una caché con el commit del
  despliegue. Abre al instante y aguanta mala cobertura.
- **Nunca** guarda nada de Supabase (partidos, resultados, rankings, mensajes, fotos, tiempo real): todo va siempre a la
  red. Si no hay conexión, las pantallas muestran su aviso de «sin conexión».
- Al desplegar una versión nueva aparece abajo «Hay una versión nueva de Plobby · Actualizar». Al volver a la app desde
  otra se comprueba si hay versión nueva.

## 7. Diferencias con la app nativa

| Función | Web en iPhone |
|---|---|
| Guardar imagen | Abre la hoja de iOS: «Guardar imagen» la manda a Fotos (la web no puede escribir en Fotos directamente). En ordenador, descarga el PNG. |
| Compartir imagen | Hoja de iOS con el PNG (WhatsApp, Instagram, Mensajes, AirDrop…). Si Safari lo bloquea por haber tardado en generar la imagen, aparece «Tu imagen está lista» con un botón para compartirla de un toque. |
| Copiar imagen | Disponible en la web (portapapeles). En la app nativa sigue sin estar y el botón ya no aparece. |
| Foto de perfil / portada | Selector de iOS (fototeca, cámara o archivos). |
| Vibración (hápticos) | Safari en iPhone no permite vibrar: no hay vibración; la respuesta visual se mantiene. |
| Notificaciones con la app cerrada | No (tampoco en la app nativa: falta Firebase/APNs). Dentro de la app, los avisos llegan en tiempo real. iOS 16.4+ admitiría Web Push en la PWA instalada; requiere un servidor de envío que aún no existe. |
| Iniciar sesión | Google, igual que en el móvil. No hay registro con correo y contraseña ni recuperación de contraseña: la app solo tiene Google. |

## 8. Problemas frecuentes al desplegar

- **`404 DEPLOYMENT_NOT_FOUND`**: la URL no corresponde a ningún despliegue (por ejemplo, se abrió la de ejemplo
  `plobby-xxxx.vercel.app`). Usa la URL que muestra Vercel en *Deployments* / *Domains*.
- **«No deployments found for "web-version"»** al elegir esa rama como producción: Vercel solo compila una rama cuando
  recibe un `push` después de conectar el proyecto. Basta con un commit nuevo en `web-version`: aparecerá en
  *Deployments* como «Preview»; cuando termine, ya se puede elegir la rama (o pulsar *⋯ → Promote to Production* en ese
  despliegue).
