/**
 * PILAR ERP — Edge Function: com-telegram-webhook
 *
 * Recibe webhooks de Telegram Bot API.
 * URL esperada: POST /com-telegram-webhook?account_id=UUID
 *
 * Auth: verify_jwt: false (Telegram no envia JWT)
 * Verificacion: X-Telegram-Bot-Api-Secret-Token debe coincidir con
 *               cuenta.config_json.webhook_secret
 *
 * Procesa:
 *   - update.message        → mensaje inbound
 *   - update.callback_query → callback de botones inline
 *
 * Responde 200 siempre (Telegram reinicia webhook si no recibe ACK <1s)
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';

// ---------------------------------------------------------------------------
// Supabase admin client (service_role — bypasses RLS)
// ---------------------------------------------------------------------------

function getAdminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const url = new URL(req.url);
  const accountId = url.searchParams.get('account_id');

  if (!accountId) {
    console.warn('[com-telegram-webhook] Missing account_id query param');
    return new Response('OK', { status: 200 });
  }

  // 1. Look up the account
  const supabase = getAdminClient();
  const { data: cuenta, error: cuentaError } = await supabase
    .from('com_cuentas')
    .select('*')
    .eq('id', accountId)
    .eq('tipo', 'telegram')
    .eq('activo', true)
    .single();

  if (cuentaError || !cuenta) {
    console.warn(`[com-telegram-webhook] No active telegram account: ${accountId}`);
    return new Response('OK', { status: 200 });
  }

  // 2. Verify secret token header
  const secretHeader = req.headers.get('x-telegram-bot-api-secret-token');
  const expectedSecret: string = cuenta.config_json?.webhook_secret ?? '';

  if (!expectedSecret || secretHeader !== expectedSecret) {
    console.warn('[com-telegram-webhook] Invalid or missing secret token');
    return new Response('Unauthorized', { status: 401 });
  }

  // 3. Parse body
  let update: any;
  try {
    update = await req.json();
  } catch {
    console.error('[com-telegram-webhook] Invalid JSON body');
    return new Response('OK', { status: 200 });
  }

  try {
    // 4. Process message
    if (update.message) {
      const msg = update.message;
      const firstName = msg.from?.first_name ?? '';
      const lastName = msg.from?.last_name ?? '';
      const nombre = `${firstName} ${lastName}`.trim();
      const cuerpo = msg.text ?? msg.caption ?? '[media]';

      await supabase.rpc('com_registrar_mensaje_inbound', {
        p_cuenta_id: cuenta.id,
        p_canal: 'telegram',
        p_destinatario_ref: String(msg.chat.id),
        p_destinatario_nombre: nombre || null,
        p_cuerpo: cuerpo,
        p_mensaje_uid: String(msg.message_id),
        p_padre_uid: msg.reply_to_message ? String(msg.reply_to_message.message_id) : null,
        p_meta_json: { chat_type: msg.chat.type, from_id: msg.from?.id },
      });
    }

    // 5. Process callback query
    if (update.callback_query) {
      const cq = update.callback_query;
      const chatId = cq.message?.chat?.id ?? cq.from.id;

      await supabase.rpc('com_registrar_mensaje_inbound', {
        p_cuenta_id: cuenta.id,
        p_canal: 'telegram',
        p_destinatario_ref: String(chatId),
        p_destinatario_nombre: cq.from.first_name || null,
        p_cuerpo: `[callback] ${cq.data}`,
        p_mensaje_uid: cq.id,
        p_padre_uid: cq.message ? String(cq.message.message_id) : null,
        p_meta_json: { callback_data: cq.data, from_id: cq.from.id },
      });
    }
  } catch (err) {
    // Log but always respond 200
    console.error(
      '[com-telegram-webhook] Error processing update:',
      err instanceof Error ? err.message : err,
    );
  }

  return new Response('OK', { status: 200 });
});
