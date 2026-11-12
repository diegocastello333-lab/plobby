-- Plobby · tipo de notificación para mensajes privados (va en su propia migración: un valor nuevo de enum no puede
-- usarse en la misma transacción en la que se crea).
alter type public.notification_type add value if not exists 'direct_message';
