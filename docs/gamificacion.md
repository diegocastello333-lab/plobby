# Gamificación de Plobby: Head to Head, Friends Ranking, Plobby Wrapped, logros y niveles

## 1. Arquitectura: una sola fuente de datos

```
matches (status = confirmed) + match_players + match_sets
        │  triggers del servidor (nunca la app)
        ▼
player_match_stats   ← UNA fila por jugador y partido confirmado (PK match_id + user_id: imposible contar dos veces)
        │
        ├── head_to_head(p_other)          → comparativa
        ├── friends_ranking(period, offset) → clasificaciones (+ temporadas congeladas)
        ├── wrapped(kind, start)            → resúmenes
        └── _g_evaluate / xp_events          → logros, XP y nivel
```

- **Qué cuenta:** solo partidos `confirmed` con un ganador válido (más sets ganados que perdidos). Los cancelados,
  pendientes o en disputa no generan filas.
- **Correcciones:** si un partido deja de estar confirmado o cambian sus sets, el trigger recalcula sus filas. Con ellas
  se recalculan la XP (se retira o se mueve), los logros (se conceden o se retiran) y todo lo que se lee después. Hoy un
  partido confirmado no se puede modificar desde la app; el sistema ya está preparado para cuando exista esa vía.
- **Fecha de un partido:** `played_at` (inicio real), no la de confirmación.
- **Seguridad:**
  - ninguna tabla nueva se puede escribir desde la app (sin permisos de escritura y con RLS de solo lectura);
  - las funciones internas `_g_*` no se pueden ejecutar desde la app;
  - las RPC públicas comprueban la sesión y la amistad.
- **Rendimiento:**
  - índices por `(user_id, played_at)`, por rivales y por pareja;
  - cada consulta lee las filas de un jugador o de su grupo de amigos, nunca el historial completo de todos;
  - las temporadas cerradas se guardan como foto, sin recalcular.

## 2. Head to Head

- **Estadísticas generales de cada jugador** (todas sus partidas):
  - partidos, victorias, derrotas y %;
  - sets ganados y perdidos, y su diferencia;
  - racha actual (positiva = victorias, negativa = derrotas) y mejor racha;
  - forma (últimos 5);
  - % de victorias por mes en los últimos 6 meses.
- **Enfrentamientos directos:** partidos en los que estuvieron en equipos **contrarios**. Incluye total, victorias de
  cada uno, último enfrentamiento, resultados con sets y saldo acumulado.
- **Como pareja:** partidos jugados juntos. No cuentan como enfrentamientos.
- **Conclusión (nunca se inventa):**
  - con 2 o más enfrentamientos y ventaja, *«X domina el cara a cara»*;
  - con 2 o más y empate, *«Empate»*;
  - con menos de 2, *«Mejor momento»* si los dos tienen al menos 5 partidos y el % difiere en 10 puntos o más;
  - en cualquier otro caso, *«Todavía no hay un dominador»*.
- **Permisos:** solo con amigos (`not_friends` en otro caso).

## 3. Friends Ranking

Grupo = tú + tus amigos aceptados. Periodos: semana (lunes a domingo), mes, año e histórico, en la zona horaria
`gamification_config.timezone` (Europe/Madrid).

| Clasificación | Orden | Empates |
|---|---|---|
| Victorias | más victorias | mejor % → más partidos → mismo puesto |
| % victorias | mejor % (solo con el mínimo de partidos) | más victorias → mismo puesto |
| Actividad | más partidos | más victorias → mismo puesto |

- **Mínimo de partidos para el ranking de %** (configurable en `gamification_config.min_rate_matches`): semana 2,
  mes 4, año 10, histórico 10. Quien no llega aparece en «Por debajo del mínimo».
- **Movimiento:** puesto en el periodo anterior menos el puesto actual. No se calcula si no jugaste en el periodo anterior.
- **Temporadas:**
  - la semana y el mes se cierran solos la primera vez que alguien consulta el ranking o el Wrapped tras el cambio de
    periodo (`_g_close_periods`, idempotente y con bloqueo);
  - al cerrar se guarda la clasificación final de cada jugador (`ranking_snapshots`), se conceden las insignias de
    campeón (puesto 1 con al menos 1 victoria y al menos 2 jugadores activos) y de Top 3 (al menos 4 jugadores activos),
    y se avisa;
  - un partido de un periodo ya cerrado que se confirme tarde no cambia esa temporada.

## 4. Plobby Wrapped

- **Mensual y anual:** solo periodos con al menos 1 partido. El mes en curso aparece como «En curso». Un mes recién
  cerrado aparece como «Nuevo» durante 7 días y se avisa al cerrarse.
- **Contenido** (cada diapositiva solo si hay datos):
  - partidos y sets;
  - victorias y %;
  - compañero más habitual y rival más frecuente;
  - mejor balance contra un rival (al menos 2 partidos);
  - mejor racha;
  - mes más activo (año) o día de la semana favorito (mes);
  - comparación con el periodo anterior y mejor mes o semana;
  - partido más memorable (victoria a 3 sets con más juegos);
  - ELO máximo y si es récord;
  - logros del periodo.
- **Imágenes:** resumen en 1080×1920 (Story) y 1080×1350 (publicación).

## 5. Logros, XP y niveles

- **XP:**
  - 100 por partido confirmado;
  - +50 por victoria;
  - la recompensa de cada logro (de 50 a 500).
  - Se guarda en `xp_events` con clave única (usuario, origen, id): cada recompensa se concede una sola vez y se retira
    si su origen desaparece.
- **Nivel:**
  - pasar del nivel L al L+1 cuesta 300 + 100·L XP (nivel 2: 400 XP, nivel 3: 900, nivel 4: 1.500…), con un máximo de 100;
  - mide actividad, no habilidad.
- **Catálogo:** 20 logros (`achievement_catalog`):
  - actividad: 1, 10, 25, 50 y 100 partidos;
  - victorias: 1, 5, 10, 25 y 50;
  - rachas: 3, 5 y 10;
  - social: 5 y 10 compañeros, 10 rivales;
  - competición: campeón semanal, campeón mensual, podio y campeón de torneo.
- **Separación:** XP y nivel son progresión personal; el ranking es competición entre amigos; las estadísticas son rendimiento.

## 6. Avisos

- **Tipos:** `ranking`, `level_up`, `wrapped` y `achievement`.
- **Preferencias:** en `notification_prefs`, una fila por usuario editable solo por él (Logros → campana).
- **Límite:** como mucho 3 avisos de ranking por persona y día (`daily_notification_limit`), con clave de deduplicación.
- **Carga histórica:** no genera avisos ni publicaciones.
- **Push con la app cerrada:** no implementado. Los avisos se guardan en `notifications`; cuando exista Firebase/APNs,
  bastará con enviarlos desde ahí.

## 7. Despliegue

1. **Validar en local** (opcional):
   ```bash
   supabase/tests/run_local.sh <host> <puerto>
   ```
   Aplica todas las migraciones y ejecuta 55 comprobaciones.
2. **Aplicar en Supabase, en este orden** (SQL Editor o `apply_migration`, nunca `supabase db push`):
   1. `supabase/migrations/20261126a_gamification_notification_types.sql`
   2. `supabase/migrations/20261126b_gamification.sql`

   La segunda carga el histórico: crea las estadísticas de los partidos ya confirmados, concede la XP y los logros que
   correspondan (sin avisos ni publicaciones) y reconoce a los campeones de torneos terminados.
3. **Comprobar** como usuario autenticado: `select public.my_achievements();` y `select public.friends_ranking('all');`.
4. **Publicar la app** (APK 1.6.0 o la siguiente compilación de iOS).

> Mientras las migraciones no estén aplicadas, las pantallas nuevas mostrarán «No se pudo cargar» con Supabase real.
> El resto de la app no se ve afectado.
