# Plobby · Catálogo de clubes y «club base» — plan, migraciones e informes (23 nov 2026)

Estado: **APLICADAS EN PRODUCCIÓN el 23 nov 2026** (con autorización): 245 clubes verificados, 79 alias, migración de
textos hecha (1 asignado, 3 para revisar). Pruebas en producción (siempre con ROLLBACK): **41/41 funcionales**.
Rendimiento en producción con el catálogo real: **6–10 ms** por búsqueda. Con 10.000 clubes simulados el servidor de
Supabase (más lento que la réplica local) da 38–106 ms: por encima de 50 ms en 4 de 7 búsquedas; habrá que revisarlo si
el catálogo crece mucho (p. ej. limitar candidatos por zona o subir de plan). Advisors: sin errores nuevos.

## Situación encontrada
- `clubs`: 0 filas, lectura abierta a cualquier usuario con sesión. `courts`: 0. Extensiones `unaccent` y `pg_trgm`
  disponibles pero sin instalar.
- La app solo tiene un campo **«Club habitual»** (texto libre, `profiles.habitual_club`). `home_club` no se usa (0 filas).
- Datos reales con club escrito a mano: 3 perfiles y 1 partido (ver informe de migración).
- No existe rol de administrador (decisión de la fase de seguridad).

## Migraciones (en `supabase/migrations/`)
| Fichero | Qué hace |
|---|---|
| `20261202a_clubs_catalog.sql` | Extensiones; `normalize_club_name`; columnas nuevas de `clubs` (slug, municipio, zona, área, CP, tipo, estado, fusión, autor, origen, nº de jugadores, geocodificación) + columnas generadas normalizadas e índices trigram/prefijo; `club_aliases`; RLS; `profiles.home_club_id`/`habitual_club_id`; `search_clubs`, `nearby_clubs`, `propose_club`, `club_page`; administración (`admin_pending_clubs`, `admin_review_club`, `admin_add_club_alias`). |
| `20261202b_clubs_seed.sql` | Los 245 clubes (verified, `seed_2026_11`) y 79 alias. Generado por `supabase/seed/build_clubs_seed.py` desde el CSV. Idempotente (upsert por slug). |
| `20261202c_clubs_text_migration.sql` | Pasa el texto antiguo a id solo si la coincidencia es clara; el resto queda en el informe `private.club_text_migration`. No borra las columnas de texto. |

Pruebas: `supabase/tests/clubs_test.sql` (termina siempre en ROLLBACK).

## Decisiones de diseño (y por qué)
- **Normalización**: minúsculas, sin tildes ni signos, padel/pádel/paddle → `padel`, sin palabras vacías (las pedidas +
  `los`, `las`, `y`, `e`, `deportiva`, que también estorbaban). Ej.: «Real Club de Pádel La Moraleja» → «padel moraleja».
- **Puntuación**: exacto 1,0 · prefijo 0,85 · todas las palabras están en nombre/alias/barrio/municipio 0,75 · parecido
  trigram hasta 0,7. Bonus de cercanía (≤ 0,15, cuando haya coordenadas) y de popularidad (≤ 0,1). Umbral 0,3.
  `confident = true` solo si el primero es ≥ 0,9 y le saca ≥ 0,2 al segundo: la app solo dice «¿Te refieres a…?» entonces.
- **Rendimiento**: con RLS, Postgres no puede usar los índices trigram antes de aplicar la política (los operadores de
  pg_trgm no son «leakproof») y recorría la tabla (≈ 60 ms con 10.000 clubes). Solución: una función interna
  (`private.club_candidates`, no expuesta en la API) obtiene **solo los ids** candidatos por índice, y `search_clubs`
  (SECURITY INVOKER, como pediste) lee esos clubes **con la RLS del usuario**. Resultado: **6–31 ms con 10.000 clubes**.
- **Fusionados**: al fusionar, los alias (y el nombre antiguo) pasan al club definitivo, así que buscar el nombre viejo
  devuelve el club correcto, y los perfiles, partidos, ligas y pistas se reasignan.
- **Propuestas**: `pending`, solo las ve su autor, que puede usarla al momento; antes de crearla se avisa de duplicados
  probables. Máximo 5 propuestas al día por usuario. El servidor fija estado, autor y origen aunque el cliente mande otros.
- **Texto antiguo sincronizado**: al guardar `home_club_id`, `home_club` se rellena con el nombre oficial (las versiones
  antiguas de la app lo siguen viendo). Las columnas de texto no se borran.
- **Administración**: cuenta con `app_metadata.plobby_admin = true` (solo se puede poner desde el servidor). Todas las
  acciones quedan en `audit_log` (tipo `admin_action`, con la operación en los detalles).

## Pruebas (réplica local, 62/62)
- Los 22 casos de búsqueda de la sección 3, incluidos «mirasierra» (Club Mirasierra primero), «puerta de hierro» (los tres,
  sin sugerir uno) y «moraleja» (los cuatro, sin sugerir uno), y texto sin coincidencias → vacío.
- RLS: un usuario no puede verificar, editar ni borrar clubes, ni añadir alias, ni aprobar; no ve ni puede usar las
  propuestas de otros; `anon` no lee ni busca. Insertar «verified» a mano se rechaza.
- Propuestas: aviso de duplicado («Club de Campo»), creación, uso inmediato, límite de 5 al día.
- Administración: cola, aprobar, fusionar (perfil reasignado, alias trasladado, contador recalculado), alias nuevo, audit_log.
- Rendimiento con 10.000 clubes (peor caso medido tras calentar): ccvm 6,6 ms · moraleja 7,0 · puerta de hierro 8,6 ·
  padel spirit vicalvaro 14,3 · padel 28,1 · ciudad raqueta 31,1 · sin resultados 7,7.

## Informe 1 · Posibles duplicados en el CSV (decides tú; no he fusionado nada)
**Probables duplicados (revisar):**
1. «Escuela de Tenis y Pádel Somosaguas» (Húmera) ↔ «Somosaguas Pádel Club Escuela» (Somosaguas) — Pozuelo.
2. «Santo Padel Torrejón» ↔ «Pádel Soto Torrejón» — Torrejón de Ardoz (¿errata Santo/Soto?).
3. «Euroindoor Alcorcón» ↔ «Padel Indoor Alcorcón» — Alcorcón.
4. «Las Tablas Sports Club» ↔ «Momo Sports Club Las Tablas» ↔ «Padel Space (Las Tablas)» — Madrid, Las Tablas.
5. «Rozas Club» ↔ «Las Rozas Padel Center» / «Club Monte Rozas» — Las Rozas («Rozas Club» es muy genérico).
6. «Padel Yoofit Chamartín» (alias «Yoofit Castellana») ↔ «Castellana Sport Club» — Madrid.
7. «Club de Pádel Fuenlabrada» ↔ «X7 Padel Madrid Fuenlabrada» — Fuenlabrada.

**Misma marca, distinta sede (los dejo separados salvo que digas lo contrario):** Padel Indoor Alcalá ↔ Padel Indoor
Alcalá Cisneros (direcciones distintas) · X3 ↔ X7 Pádel Majadahonda (direcciones distintas) · Pádel Padre Damián (alias
«School Pádel Center Padre Damián») ↔ School Padel Center M30 · Santo Pádel Madrid ↔ Santo Padel Torrejón.

**Descartados (solo comparten barrio o una palabra):** Puerta de Hierro (Real Club / Parque Deportivo / Guisando),
La Moraleja (Real Club / Club de Pádel / Club de Tenis), Somontes ↔ El Tejar de Somontes, La Garena ↔ Espacio Garena,
Chamartín, Hortaleza, Pradillo, Villaverde, IDMB Los Caprichos ↔ IDMB Briviesca, BamVolea Get Indoor ↔ MG Indoor / Padel
Sport Indoor Getafe.

Datos del CSV: 245 clubes, 79 alias, sin slugs repetidos; 156 sin dirección y 175 sin CP (se guardan como NULL).

## Informe 2 · Migración de los clubes escritos a mano (simulada con los datos reales)
| Dónde | Texto | Mejor coincidencia | Segunda | Resultado |
|---|---|---|---|---|
| perfil (club habitual) | Club de Tenis Chamartín | Club de Tenis Chamartín (1,0) | Blue Padel Chamartín (0,44) | **Se asigna** |
| perfil (club habitual) | Puerta de Hierro | Real Club Puerta de Hierro (1,0) | CD Puerta de Hierro Guisando (0,85) | Para revisar (ambiguo) |
| perfil (club habitual) | RCGLM | — | — | Para revisar (¿Real Club de Golf La Moraleja?) |
| partido | Club La Moraleja | Real Club La Moraleja (1,0) | Euroindoor Moraleja (0,85) | Para revisar (ambiguo) |

## Informe 3 · Geocodificación
Pendiente: necesito que apruebes el proveedor (ver decisiones). Hasta entonces `lat/lng` vacíos, `geocode_status =
'pending'`, la búsqueda funciona sin el bonus de cercanía y «Clubes cerca de ti» no muestra nada.

## Decisiones del 23 nov 2026 (aplicadas)
- **Un solo campo**: «Club habitual» = club base. `20261202d_clubs_single_field` (APLICADA): guardar `habitual_club_id`
  copia el valor en `home_club_id` y viceversa; el contador de jugadores salta en ambos casos (corregido: un trigger
  «UPDATE OF columna» no veía el valor puesto por otro trigger). Datos existentes igualados.
- **Administrador**: tu cuenta tiene `app_metadata.plobby_admin = true` (se aplica al renovar la sesión, como mucho 1 h,
  o al volver a entrar).
- **Geocodificación**: Nominatim (OpenStreetMap), desde una Edge Function. Pendiente de implementar.
- **Página del club**: todos los jugadores con ese club (nombre, usuario, foto, nivel y ELO).
- Pendiente de tu respuesta: los 7 posibles duplicados del CSV y si «RCGLM» es el Real Club de Golf La Moraleja.
