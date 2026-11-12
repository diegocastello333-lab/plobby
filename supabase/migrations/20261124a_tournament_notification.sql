-- Plobby · Torneos: tipo de notificación propio (en su migración: un valor nuevo de enum no se puede usar en la misma
-- transacción en la que se crea). No afecta a Ligas.
alter type public.notification_type add value if not exists 'tournament_added';
