-- Fix: GRANT service_role en tablas de comunicación
--
-- Edge Functions (com-telegram-webhook, com-whatsapp-webhook, com-email-sender)
-- usan un admin client con service_role JWT. PostgREST requiere GRANT explícito
-- a nivel de tabla incluso para service_role — RLS bypass NO implica GRANT de tabla.
--
-- Sin estos GRANTs la consulta a com_cuentas falla con:
--   "permission denied for table com_cuentas" (user=authenticator, role=service_role)

GRANT SELECT, INSERT, UPDATE, DELETE ON public.com_cuentas        TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.com_conversaciones TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.com_mensajes       TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.com_blacklist      TO service_role;

-- anon: solo lectura en com_cuentas para el verify-GET de WhatsApp webhook
GRANT SELECT ON public.com_cuentas TO anon;
