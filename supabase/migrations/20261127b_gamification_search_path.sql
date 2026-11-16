-- Plobby · Endurecimiento: search_path fijo en 3 funciones de la gamificación (asesor de seguridad de Supabase).
-- No cambia su comportamiento: solo impide que un search_path manipulado resuelva otros objetos.
alter function public._g_backfill() set search_path = public;
alter function public.xp_for_level(int) set search_path = public;
alter function public.level_for_xp(int) set search_path = public;
