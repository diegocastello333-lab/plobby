-- Plobby · Gamificación (1/2): tipos de aviso nuevos. Va sola: un valor de enum no puede usarse en la misma
-- transacción en la que se crea.
alter type public.notification_type add value if not exists 'ranking';
alter type public.notification_type add value if not exists 'level_up';
alter type public.notification_type add value if not exists 'wrapped';
