-- Plobby · 13 nov 2026: nuevo tipo de publicación del feed «tournament» (campeones de torneo).
-- Va sola: un valor nuevo de enum no puede usarse en la misma transacción en la que se crea.
alter type public.feed_activity_type add value if not exists 'tournament';
