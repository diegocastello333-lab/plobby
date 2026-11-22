# Plobby · Fase 2: Storage

Migración `supabase/migrations/20261129a_storage_hardening.sql`. Validada en la BD real con ROLLBACK: **15 de 15** pruebas OK.

| Bucket | Antes | Después |
|---|---|---|
| `avatars` (fotos de perfil y portadas de torneo) | público; escritura en la carpeta propia con cualquier extensión y subcarpetas; UPDATE sin WITH CHECK | **sigue público** (ver decisión); solo `<uid>/<fichero>.jpg|jpeg|png|webp`, un nivel de carpeta; UPDATE con WITH CHECK (no se puede mover un fichero a la carpeta de otro); 5 MB; solo JPEG/PNG/WebP |
| `group-avatars` (imagen de grupos) | privado; 5 MB; URL firmada de **1 año** guardada en la BD | privado; **2 MB**; solo admins del grupo suben, cambian o **borran** (antes no podían borrar); solo miembros leen; la app firma una URL de **1 hora** al leer y las nuevas subidas guardan una de 7 días |

Pruebas: A sube su avatar y su portada ✔ · no sube `.html` ni `.svg` ✔ · no crea subcarpetas ✔ · no sube a la carpeta de B ✔ · no mueve
su fichero a la carpeta de B ✔ · el admin sube la imagen del grupo ✔ · un miembro la ve ✔ · un miembro que no es admin no sube ni modifica ✔ ·
B no lista la carpeta de A ✔ · un ajeno no ve imágenes de grupos ✔ · anon no sube ✔ · bucket privado y 2 MB ✔.
(El borrado no se puede probar desde SQL: Supabase bloquea `DELETE` directo en `storage.objects`; se prueba desde la app.)

Metadatos: las 6 fotos actuales no tienen GPS, cámara ni fecha en EXIF (comprobado sin abrir las imágenes).
La app reduce la foto a 768 px con calidad 85 antes de subirla.

## Decisión: ¿`avatars` público o privado?
- **Público (recomendado y aplicado en esta migración):** la foto de perfil está pensada para que la vea cualquier usuario
  (búsqueda, feed, chats, notificaciones, imágenes para compartir). Riesgo residual: quien tenga la URL exacta (contiene
  el id del usuario y un número aleatorio) puede verla sin sesión. No se puede listar ni adivinar.
- **Privado con URLs firmadas:** habría que cambiar ~40 puntos de la app y las funciones del servidor que devuelven
  `avatar_url`, y firmar en el cliente. Los APK antiguos dejarían de ver fotos. Es posible, pero es una fase aparte.
