# Torneos — diseño técnico (Plobby)

Sistema **independiente de Ligas**: tablas, funciones, rutas y código Flutter propios. De Ligas solo se reutilizan
componentes visuales; de la app, el sistema de amigos y la búsqueda de jugadores. Ninguna tabla, función o pantalla de
Ligas se modifica.

## Navegación
- La pestaña «Ligas» pasa a llamarse **Competiciones** (misma ruta `/leagues`, así los enlaces existentes siguen
  funcionando). Dentro, un selector **Ligas | Torneos**:
  - **Ligas**: la pantalla de ligas de siempre (mismos datos, acciones y rutas `/leagues/...`).
  - **Torneos**: mis torneos + «Crear torneo». Rutas nuevas `/tournaments/new` y `/tournaments/:id`.

## Base de datos (migración `20261124_tournaments.sql`)
| Tabla | Para qué | Claves y restricciones |
|---|---|---|
| `tournaments` | Datos del torneo, formato y estado | `max_teams` 2–64, `format` ∈ {knockout, groups_knockout, round_robin}, `status` ∈ {scheduled, in_progress, finished}, `ends_on ≥ starts_on`, campeón |
| `tournament_admins` | Organizador y futuros coorganizadores | PK (torneo, usuario), `role` ∈ {owner, admin} |
| `tournament_teams` | Parejas (2 jugadores, semilla, grupo) | `unique (torneo, semilla)`, `player1 ≠ player2` |
| `tournament_players` | Un jugador → una pareja por torneo | PK (torneo, usuario): **imposible duplicar** a una persona |
| `tournament_matches` | Partidos de grupo y de cuadro | ronda/posición únicas, `next_match_id` + `next_slot` (a dónde avanza el ganador), `slot*_source` (p. ej. «A1»), `sets` jsonb, `version` (control de concurrencia) |

- **Lectura (RLS)**: solo organizadores y jugadores del torneo (`_t_can_view`).
- **Escritura**: ninguna directa; todo por funciones RPC `security definer` (cada una es una transacción: o se
  aplica entera o nada).
- **Tiempo real**: triggers por sentencia → Broadcast `tournament` al canal privado `user:<uid>` de cada organizador
  y jugador (el mismo canal por usuario que ya usa la app).
- **Aviso**: tipo de notificación nuevo `tournament_added` (te han añadido a un torneo).

## Funciones
- `create_tournament(jsonb)`: valida, crea torneo, organizador, parejas y jugadores y **genera la estructura**.
- `replace_tournament_teams(id, jsonb)`: cambia parejas/formato **antes de que haya resultados** y regenera.
- `update_tournament_info(id, jsonb)`: nombre, descripción, fechas, horario, ubicación, portada, máximo.
- `record_tournament_result(match, sets, version)`: valida sets (al mejor de 3), decide ganador, avanza en el
  cuadro, recalcula grupos/cruces y campeón. Bloquea el torneo (`for update`) y exige la `version` que vio el
  cliente: dos resultados simultáneos no pueden pisarse (`result_conflict`).
- `clear_tournament_result(match, version)`, `set_tournament_match_live(match, bool)`, `finish_tournament(id)`.
- `my_tournaments()`, `tournament_standings(id)`.

## Lógica de competición
- **Eliminación directa**: cuadro de tamaño potencia de 2 (P ≥ N), siembra estándar (1 vs P, 2 vs P−1…); las
  P−N mejores semillas pasan sin jugar (**BYE**). El ganador ocupa su hueco en el partido siguiente.
- **Grupos + eliminatoria**: reparto en serpiente por semilla (A B C D D C B A…), todos contra todos en cada grupo,
  clasificación (puntos → diferencia de sets → diferencia de juegos → victorias → semilla). Pasan Q por grupo; los
  cruces se siembran 1.º de cada grupo, luego 2.º… (A1 vs D2, B1 vs C2…) y se rellenan solos al terminar los grupos.
- **Liguilla (todos contra todos)**: un grupo; campeón = 1.º cuando terminan todos los partidos.
- **Correcciones**: si cambia el ganador de un partido, se actualiza el hueco siguiente y **se anulan en cascada**
  los partidos posteriores que ya no son válidos; si cambia una clasificación de grupo, se re-siembran los cruces
  (solo se anulan los que cambian de pareja). Nunca quedan resultados incoherentes.
- La misma lógica existe en Dart (`TournamentEngine`) para el modo demo y los tests, con los mismos casos.
