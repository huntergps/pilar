-- Habilitar Realtime en com_conversaciones
-- (com_mensajes ya estaba en la publicación)
-- Necesario para que el conversaciones_provider reciba eventos en tiempo real.
ALTER PUBLICATION supabase_realtime ADD TABLE public.com_conversaciones;
