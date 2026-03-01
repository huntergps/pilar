-- Cron job: com-telegram-sender
-- Procesa mensajes outbound Telegram pendientes cada 1 minuto
SELECT cron.schedule(
  'com-telegram-sender',
  '* * * * *',
  $$
    SELECT net.http_post(
      url     := current_setting('app.supabase_url') || '/functions/v1/com-telegram-sender',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_key')
      ),
      body    := '{}'::jsonb
    );
  $$
);
