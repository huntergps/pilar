/**
 * PILAR ERP — Edge Function: com-whatsapp-sender
 *
 * Worker outbound para WhatsApp: procesa mensajes en com_mensajes con
 *   tipo = 'outbound', canal = 'whatsapp', estado = 'pendiente'
 * y los envía via el BSP configurado en la cuenta (Meta, 360dialog, Twilio).
 *
 * Invocada por pg_cron cada 1 minuto:
 *   SELECT net.http_post(url := .../com-whatsapp-sender, ...)
 *
 * Procesa hasta 50 mensajes por run para evitar timeouts.
 * Actualiza estado a 'enviado' o 'fallido' según el resultado.
 *
 * Auth: verify_jwt: false — usa service_role internamente; no valida JWT del caller.
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';
import { type WaAccount, type WaMessagePayload, waSend } from './whatsapp-api.ts';

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
  meta_json: Record<string, unknown> | null;
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (_req: Request): Promise<Response> => {
  const supabase = getAdminClient();

  // 1. Obtener mensajes pendientes de WhatsApp (máx 50 por run)
  const { data: mensajes, error: fetchError } = await supabase
    .from('com_mensajes')
    .select('id, cuenta_id, conversacion_id, destinatario_ref, cuerpo, asunto, meta_json')
    .eq('tipo', 'outbound')
    .eq('canal', 'whatsapp')
    .eq('estado', 'pendiente')
    .lt('reintentos', 5)
    .order('creado_en', { ascending: true })
    .limit(50);

  if (fetchError) {
    console.error('[com-whatsapp-sender] Error al obtener mensajes:', fetchError.message);
    return new Response(JSON.stringify({ ok: false, error: fetchError.message }), { status: 500 });
  }

  if (!mensajes || mensajes.length === 0) {
    return new Response(JSON.stringify({ ok: true, procesados: 0 }), { status: 200 });
  }

  console.info(`[com-whatsapp-sender] Procesando ${mensajes.length} mensajes`);

  // 2. Cache de cuentas (evitar N+1 queries)
  const cuentaCache = new Map<string, any | null>();

  async function getCuenta(cuentaId: string): Promise<any | null> {
    if (cuentaCache.has(cuentaId)) return cuentaCache.get(cuentaId)!;

    const { data, error } = await supabase
      .from('com_cuentas')
      .select('id, config_json')
      .eq('id', cuentaId)
      .eq('tipo', 'whatsapp')
      .eq('activo', true)
      .single();

    const cuenta = error || !data ? null : data;
    cuentaCache.set(cuentaId, cuenta);
    return cuenta;
  }

  // 3. Procesar cada mensaje
  let enviados = 0;
  let fallidos = 0;

  for (const msg of mensajes as MensajePendiente[]) {
    const cuenta = await getCuenta(msg.cuenta_id);

    if (!cuenta) {
      console.warn(`[com-whatsapp-sender] Cuenta ${msg.cuenta_id} no encontrada o inactiva`);
      await supabase
        .from('com_mensajes')
        .update({
          estado: 'fallido',
          tipo_fallo: 'config',
          razon_fallo: 'Cuenta WhatsApp no encontrada o inactiva',
        })
        .eq('id', msg.id);
      fallidos++;
      continue;
    }

    const acct = cuenta.config_json as WaAccount;
    const bsp = acct.bsp ?? 'meta';

    // Validate required credentials per BSP
    const credError = _validateCredentials(acct, bsp);
    if (credError) {
      console.warn(`[com-whatsapp-sender] Cuenta ${msg.cuenta_id}: ${credError}`);
      await supabase
        .from('com_mensajes')
        .update({
          estado: 'fallido',
          tipo_fallo: 'config',
          razon_fallo: credError,
        })
        .eq('id', msg.id);
      fallidos++;
      continue;
    }

    // Build payload — try to use template if meta_json has template info
    const payload = _buildPayload(msg);

    try {
      const messageId = await waSend(acct, msg.destinatario_ref, payload);

      await supabase
        .from('com_mensajes')
        .update({
          estado: 'enviado',
          enviado_en: new Date().toISOString(),
          mensaje_uid: messageId,
        })
        .eq('id', msg.id);

      enviados++;
      console.info(`[com-whatsapp-sender] Enviado ${msg.id} (${bsp}) → ${msg.destinatario_ref}`);
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);

      // Increment retries; if >= 5 mark as permanent failure
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
          razon_fallo: errorMsg,
          tipo_fallo: 'api',
          proximo_reintento_en: esFinal
            ? null
            : new Date(Date.now() + reintentos * 60_000).toISOString(),
        })
        .eq('id', msg.id);

      fallidos++;
      console.warn(
        `[com-whatsapp-sender] Fallo msg ${msg.id} (${bsp}, intento ${reintentos}):`,
        errorMsg,
      );
    }
  }

  return new Response(
    JSON.stringify({ ok: true, procesados: mensajes.length, enviados, fallidos }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function _validateCredentials(acct: WaAccount, bsp: string): string | null {
  switch (bsp) {
    case 'meta':
      if (!acct.phone_uid || !acct.token) return 'Cuenta Meta sin phone_uid o token';
      break;
    case '360dialog':
      if (!acct.api_key) return 'Cuenta 360dialog sin api_key';
      break;
    case 'twilio':
      if (!acct.account_sid || !acct.auth_token || !acct.phone_number) {
        return 'Cuenta Twilio sin account_sid, auth_token o phone_number';
      }
      break;
  }
  return null;
}

function _buildPayload(msg: MensajePendiente): WaMessagePayload {
  // If meta_json contains a pre-built WhatsApp payload, use it
  if (msg.meta_json?.wa_payload) {
    return msg.meta_json.wa_payload as WaMessagePayload;
  }

  // Default: plain text
  return {
    type: 'text',
    text: { body: msg.cuerpo },
  };
}
