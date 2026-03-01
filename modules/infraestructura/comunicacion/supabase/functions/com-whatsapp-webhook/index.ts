/**
 * PILAR ERP — Edge Function: com-whatsapp-webhook
 *
 * Recibe webhooks de Meta (WhatsApp Business Cloud API):
 *   - GET:  verificacion del webhook (hub.challenge)
 *   - POST: mensajes inbound, status updates, template status/quality updates
 *
 * Auth: verify_jwt: false (Meta no envia JWT)
 *
 * Flujo POST:
 *   1. Lee raw body para validar HMAC-SHA256
 *   2. Identifica la cuenta por phone_number_id del payload
 *   3. Verifica firma con app_secret de la cuenta
 *   4. Procesa messages[], statuses[], template updates
 *   5. Responde 200 siempre (Meta requiere <5s)
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';
import { verifyWaSignature } from './whatsapp-api.ts';

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
// Status mapping: Meta status → PILAR estado
// ---------------------------------------------------------------------------

const ESTADO_MAP: Record<string, string> = {
  sent: 'enviado',
  delivered: 'entregado',
  read: 'leido',
  failed: 'fallido',
};

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  const url = new URL(req.url);

  // =========================================================================
  // GET — Meta webhook verification
  // =========================================================================
  if (req.method === 'GET') {
    const mode = url.searchParams.get('hub.mode');
    const challenge = url.searchParams.get('hub.challenge');
    const verifyToken = url.searchParams.get('hub.verify_token');

    if (mode !== 'subscribe' || !challenge || !verifyToken) {
      return new Response('Bad Request', { status: 400 });
    }

    // Look up the account by webhook_verify_token
    const supabase = getAdminClient();
    const { data: cuentas, error } = await supabase
      .from('com_cuentas')
      .select('id')
      .eq('activo', true)
      .eq('tipo', 'whatsapp')
      .filter('config_json->>webhook_verify_token', 'eq', verifyToken);

    if (error || !cuentas || cuentas.length === 0) {
      console.warn('[com-whatsapp-webhook] Verification failed: no matching account for token');
      return new Response('Forbidden', { status: 403 });
    }

    return new Response(challenge, { status: 200 });
  }

  // =========================================================================
  // POST — Meta webhook events
  // =========================================================================
  if (req.method === 'POST') {
    // 1. Read raw body for HMAC validation
    const rawBody = await req.text();
    const signature = req.headers.get('x-hub-signature-256') ?? '';

    // 2. Parse payload
    let payload: any;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      console.error('[com-whatsapp-webhook] Invalid JSON body');
      return new Response('OK', { status: 200 });
    }

    // 3. Extract phone_number_id from the first entry
    const phoneNumberId: string | undefined =
      payload?.entry?.[0]?.changes?.[0]?.value?.metadata?.phone_number_id;

    if (!phoneNumberId) {
      // Cannot identify account — acknowledge to Meta but do nothing
      console.warn('[com-whatsapp-webhook] No phone_number_id in payload');
      return new Response('OK', { status: 200 });
    }

    // 4. Look up the account
    const supabase = getAdminClient();
    const { data: cuenta, error: cuentaError } = await supabase
      .from('com_cuentas')
      .select('*')
      .eq('activo', true)
      .eq('tipo', 'whatsapp')
      .filter('config_json->>phone_uid', 'eq', phoneNumberId)
      .single();

    if (cuentaError || !cuenta) {
      console.warn(`[com-whatsapp-webhook] No account for phone_uid=${phoneNumberId}`);
      return new Response('OK', { status: 200 });
    }

    // 5. Verify HMAC signature
    const appSecret: string = cuenta.config_json?.app_secret ?? '';
    if (!appSecret) {
      console.warn(
        `[com-whatsapp-webhook] SECURITY: app_secret no configurado para cuenta ${cuenta.id}. ` +
        'El webhook acepta payloads sin validar firma HMAC. ' +
        'Configura app_secret en la cuenta para rechazar peticiones no autorizadas.',
      );
    } else {
      const valid = await verifyWaSignature(rawBody, signature, appSecret);
      if (!valid) {
        console.warn('[com-whatsapp-webhook] Invalid HMAC signature — request rejected');
        return new Response('Unauthorized', { status: 401 });
      }
    }

    // 6. Process all entries/changes
    const entries: any[] = payload.entry ?? [];
    for (const entry of entries) {
      const changes: any[] = entry.changes ?? [];
      for (const change of changes) {
        try {
          await processChange(supabase, cuenta, change);
        } catch (err) {
          // Log but never fail the whole request
          console.error(
            '[com-whatsapp-webhook] Error processing change:',
            err instanceof Error ? err.message : err,
          );
        }
      }
    }

    return new Response('OK', { status: 200 });
  }

  // Other methods
  return new Response('Method Not Allowed', { status: 405 });
});

// ---------------------------------------------------------------------------
// Process a single change object
// ---------------------------------------------------------------------------

async function processChange(
  supabase: ReturnType<typeof createClient>,
  cuenta: any,
  change: any,
): Promise<void> {
  const { field, value } = change;

  if (field === 'messages') {
    // --- Inbound messages ---
    const messages: any[] = value.messages ?? [];
    const contacts: any[] = value.contacts ?? [];

    for (const msg of messages) {
      try {
        // Match contact by wa_id to get the correct name for each message sender
        const contactForMsg = contacts.find((c: any) => c.wa_id === msg.from);
        const contactName = contactForMsg?.profile?.name ?? contacts[0]?.profile?.name ?? null;
        const body = msg.text?.body ?? `[${msg.type}]`;

        await supabase.rpc('com_registrar_mensaje_inbound', {
          p_cuenta_id: cuenta.id,
          p_canal: 'whatsapp',
          p_destinatario_ref: msg.from,
          p_destinatario_nombre: contactName,
          p_cuerpo: body,
          p_mensaje_uid: msg.id,
          p_padre_uid: msg.context?.id ?? null,
          p_meta_json: { type: msg.type, timestamp: msg.timestamp },
        });
      } catch (err) {
        console.error(
          `[com-whatsapp-webhook] Error registering inbound msg ${msg.id}:`,
          err instanceof Error ? err.message : err,
        );
      }
    }

    // --- Status updates ---
    const statuses: any[] = value.statuses ?? [];
    for (const status of statuses) {
      try {
        const estado = ESTADO_MAP[status.status] ?? status.status;
        const razonFallo = status.errors?.[0]?.title ?? null;

        await supabase.rpc('com_actualizar_estado_mensaje', {
          p_mensaje_uid: status.id,
          p_estado: estado,
          p_razon_fallo: razonFallo,
        });
      } catch (err) {
        console.error(
          `[com-whatsapp-webhook] Error updating status ${status.id}:`,
          err instanceof Error ? err.message : err,
        );
      }
    }
  }

  // --- Template status / quality updates ---
  if (
    field === 'message_template_status_update' ||
    field === 'message_template_quality_update'
  ) {
    const update = value;
    await supabase.rpc('com_wa_actualizar_estado_plantilla', {
      p_wa_template_uid: update.message_template_id?.toString() ?? null,
      p_estado: update.event?.toLowerCase() ?? update.status?.toLowerCase() ?? null,
      p_calidad: update.message_template_quality_score ?? null,
    });
  }
}
