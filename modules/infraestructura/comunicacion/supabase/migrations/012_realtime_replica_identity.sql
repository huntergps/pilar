-- Realtime con filtros por columna no-PK requiere REPLICA IDENTITY FULL.
-- Sin esto, el servidor Realtime no puede evaluar filtros como
-- conversacion_id=eq.UUID en eventos UPDATE/DELETE.
ALTER TABLE public.com_mensajes       REPLICA IDENTITY FULL;
ALTER TABLE public.com_conversaciones REPLICA IDENTITY FULL;
