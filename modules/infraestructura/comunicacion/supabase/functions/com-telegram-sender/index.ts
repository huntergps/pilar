/**
 * PILAR ERP — Edge Function: com-telegram-sender
 *
 * Worker outbound para Telegram: procesa mensajes en com_mensajes con
 *   tipo = 'outbound', canal = 'telegram', estado = 'pendiente'
 * y los envía via Telegram Bot API usando el bot_token de la cuenta.
 *
 * Invocada por pg_cron cada 1 minuto:
 *   SELECT net.http_post(url := .../com-telegram-sender, ...)
 *
 * Procesa hasta 50 mensajes por run para evitar timeouts.
 * Actualiza estado a 'enviado' o 'fallido' según el resultado.
 *
 * Auth: verify_jwt: true (invocada con service_role key desde pg_cron)
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';

// ---------------------------------------------------------------------------
// Supabase admin client
// ---------------------------------------------------------------------------

function getAdminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
}

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface MensajePendiente {
  id: string;
  cuenta_id: string;
  conversacion_id: string;
  destinatario_ref: string;
  cuerpo: string;
  asunto: string | null;
}

interface CuentaTelegram {
  id: string;
  config_json: {
    bot_token?: string;
  };
}

// ---------------------------------------------------------------------------
// Enviar mensaje via Telegram Bot API
// ---------------------------------------------------------------------------

async function telegramSend(
  botToken: string,
  chatId: string,
  text: string,
): Promise<{ ok: boolean; message_id?: string; error?: string }> {
  try {
    const res = await fetch(
      `https://api.telegram.org/bot${botToken}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          text,
          parse_mode: 'Markdown',
        }),
      },
    );

    const data = await res.json();

    if (data.ok && data.result?.message_id) {
      return { ok: true, message_id: String(data.result.message_id) };
    }

    return { ok: false, error: data.description ?? `HTTP ${res.status}` };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (_req: Request): Promise<Response> => {
  const supabase = getAdminClient();

  // 1. Obtener mensajes pendientes de Telegram (máx 50 por run)
  const { data: mensajes, error: fetchError } = await supabase
    .from('com_mensajes')
    .select('id, cuenta_id, conversacion_id, destinatario_ref, cuerpo, asunto')
    .eq('tipo', 'outbound')
    .eq('canal', 'telegram')
    .eq('estado', 'pendiente')
    .lt('reintentos', 5)
    .order('creado_en', { ascending: true })
    .limit(50);

  if (fetchError) {
    console.error('[com-telegram-sender] Error al obtener mensajes:', fetchError.message);
    return new Response(JSON.stringify({ ok: false, error: fetchError.message }), { status: 500 });
  }

  if (!mensajes || mensajes.length === 0) {
    return new Response(JSON.stringify({ ok: true, procesados: 0 }), { status: 200 });
  }

  console.info(`[com-telegram-sender] Procesando ${mensajes.length} mensajes`);

  // 2. Cache de tokens por cuenta (evitar N+1 queries)
  const cuentaCache = new Map<string, CuentaTelegram | null>();

  async function getCuenta(cuentaId: string): Promise<CuentaTelegram | null> {
    if (cuentaCache.has(cuentaId)) return cuentaCache.get(cuentaId)!;

    const { data, error } = await supabase
      .from('com_cuentas')
      .select('id, config_json')
      .eq('id', cuentaId)
      .eq('tipo', 'telegram')
      .eq('activo', true)
      .single();

    const cuenta = error || !data ? null : (data as CuentaTelegram);
    cuentaCache.set(cuentaId, cuenta);
    return cuenta;
  }

  // 3. Procesar cada mensaje
  let enviados = 0;
  let fallidos = 0;

  for (const msg of mensajes as MensajePendiente[]) {
    const cuenta = await getCuenta(msg.cuenta_id);

    if (!cuenta?.config_json?.bot_token) {
      console.warn(`[com-telegram-sender] Cuenta ${msg.cuenta_id} sin bot_token`);
      await supabase
        .from('com_mensajes')
        .update({
          estado: 'fallido',
          tipo_fallo: 'config',
          razon_fallo: 'Cuenta Telegram sin bot_token configurado',
        })
        .eq('id', msg.id);
      fallidos++;
      continue;
    }

    const resultado = await telegramSend(
      cuenta.config_json.bot_token,
      msg.destinatario_ref,
      msg.cuerpo,
    );

    if (resultado.ok) {
      await supabase
        .from('com_mensajes')
        .update({
          estado: 'enviado',
          enviado_en: new Date().toISOString(),
          mensaje_uid: resultado.message_id,
        })
        .eq('id', msg.id);
      enviados++;
      console.info(`[com-telegram-sender] Enviado ${msg.id} → chat ${msg.destinatario_ref}`);
    } else {
      // Incrementar reintentos; si >= 5 marcar fallido definitivo
      const { data: actual } = await supabase
        .from('com_mensajes')
        .select('reintentos')
        .eq('id', msg.id)
        .single();

      const reintentos = (actual?.reintentos ?? 0) + 1;
      const esFinal = reintentos >= 5;

      await supabase
        .from('com_mensajes')
        .update({
          estado: esFinal ? 'fallido' : 'pendiente',
          reintentos,
          razon_fallo: resultado.error,
          tipo_fallo: 'api',
          proximo_reintento_en: esFinal
            ? null
            : new Date(Date.now() + reintentos * 60_000).toISOString(),
        })
        .eq('id', msg.id);

      fallidos++;
      console.warn(
        `[com-telegram-sender] Fallo msg ${msg.id} (intento ${reintentos}):`,
        resultado.error,
      );
    }
  }

  return new Response(
    JSON.stringify({ ok: true, procesados: mensajes.length, enviados, fallidos }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
