/**
 * PILAR ERP — Edge Function: com-whatsapp-webhook
 *
 * Recibe webhooks de WhatsApp Business API (Meta, 360dialog, Twilio):
 *   - GET:  verificacion del webhook (hub.challenge) — Meta & 360dialog
 *   - POST: mensajes inbound, status updates, template status/quality updates
 *
 * Deteccion automatica de BSP:
 *   - Content-Type: application/x-www-form-urlencoded → Twilio
 *   - x-360dialog-signature header presente → 360dialog
 *   - Default → Meta Cloud API
 *
 * Auth: verify_jwt: false (los BSPs no envian JWT)
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';
import { verifyWaSignature, verifyTwilioSignature } from './whatsapp-api.ts';

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
// Status mapping: Meta/360dialog status → PILAR estado
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
  // GET — Meta/360dialog webhook verification
  // =========================================================================
  if (req.method === 'GET') {
    const mode = url.searchParams.get('hub.mode');
    const challenge = url.searchParams.get('hub.challenge');
    const verifyToken = url.searchParams.get('hub.verify_token');

    if (mode !== 'subscribe' || !challenge || !verifyToken) {
      return new Response('Bad Request', { status: 400 });
    }

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
  // POST — Webhook events
  // =========================================================================
  if (req.method === 'POST') {
    const contentType = req.headers.get('content-type') ?? '';
    const rawBody = await req.text();
    const supabase = getAdminClient();

    // --- Twilio: form-encoded payload ---
    if (contentType.includes('application/x-www-form-urlencoded')) {
      try {
        await _processTwilioWebhook(supabase, req, rawBody, url.toString());
      } catch (err) {
        console.error('[com-whatsapp-webhook] Twilio error:', err instanceof Error ? err.message : err);
      }
      // Twilio expects empty 200 (TwiML) or plain 200
      return new Response('', { status: 200, headers: { 'Content-Type': 'text/xml' } });
    }

    // --- Meta / 360dialog: JSON payload ---
    const sigMeta = req.headers.get('x-hub-signature-256') ?? '';
    const sig360 = req.headers.get('x-360dialog-signature') ?? '';

    let payload: any;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      console.error('[com-whatsapp-webhook] Invalid JSON body');
      return new Response('OK', { status: 200 });
    }

    // Extract phone_number_id to find the account
    const phoneNumberId: string | undefined =
      payload?.entry?.[0]?.changes?.[0]?.value?.metadata?.phone_number_id;

    if (!phoneNumberId) {
      console.warn('[com-whatsapp-webhook] No phone_number_id in payload');
      return new Response('OK', { status: 200 });
    }

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

    // Verify signature based on BSP
    const bsp = cuenta.config_json?.bsp ?? 'meta';
    let sigVerified = false;

    if (bsp === '360dialog') {
      const apiKey: string = cuenta.config_json?.api_key ?? '';
      if (!apiKey) {
        console.warn(`[com-whatsapp-webhook] 360dialog: api_key not configured for cuenta ${cuenta.id}`);
      } else {
        // 360dialog signature header may be x-360dialog-signature or x-hub-signature-256
        const sigToCheck = sig360 || sigMeta;
        sigVerified = await verifyWaSignature(rawBody, sigToCheck, apiKey);
        if (!sigVerified) {
          console.warn('[com-whatsapp-webhook] 360dialog: Invalid signature — request rejected');
          return new Response('Unauthorized', { status: 401 });
        }
      }
    } else {
      // Meta
      const appSecret: string = cuenta.config_json?.app_secret ?? '';
      if (!appSecret) {
        console.warn(
          `[com-whatsapp-webhook] SECURITY: app_secret not configured for cuenta ${cuenta.id}. ` +
          'Accepting unverified payloads. Configure app_secret to reject unauthorized requests.',
        );
      } else {
        sigVerified = await verifyWaSignature(rawBody, sigMeta, appSecret);
        if (!sigVerified) {
          console.warn('[com-whatsapp-webhook] Meta: Invalid HMAC signature — request rejected');
          return new Response('Unauthorized', { status: 401 });
        }
      }
    }

    // Process all entries/changes
    const entries: any[] = payload.entry ?? [];
    for (const entry of entries) {
      const changes: any[] = entry.changes ?? [];
      for (const change of changes) {
        try {
          await _processMetaChange(supabase, cuenta, change);
        } catch (err) {
          console.error(
            '[com-whatsapp-webhook] Error processing change:',
            err instanceof Error ? err.message : err,
          );
        }
      }
    }

    return new Response('OK', { status: 200 });
  }

  return new Response('Method Not Allowed', { status: 405 });
});

// ---------------------------------------------------------------------------
// Process a Meta/360dialog change object (identical format)
// ---------------------------------------------------------------------------

async function _processMetaChange(
  supabase: ReturnType<typeof createClient>,
  cuenta: any,
  change: any,
): Promise<void> {
  const { field, value } = change;

  if (field === 'messages') {
    const messages: any[] = value.messages ?? [];
    const contacts: any[] = value.contacts ?? [];

    for (const msg of messages) {
      try {
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
          p_meta_json: {
            bsp: cuenta.config_json?.bsp ?? 'meta',
            type: msg.type,
            timestamp: msg.timestamp,
          },
        });
      } catch (err) {
        console.error(
          `[com-whatsapp-webhook] Error registering inbound msg ${msg.id}:`,
          err instanceof Error ? err.message : err,
        );
      }
    }

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

// ---------------------------------------------------------------------------
// Process a Twilio webhook (form-encoded)
// ---------------------------------------------------------------------------

async function _processTwilioWebhook(
  supabase: ReturnType<typeof createClient>,
  req: Request,
  rawBody: string,
  requestUrl: string,
): Promise<void> {
  const params = Object.fromEntries(new URLSearchParams(rawBody)) as Record<string, string>;

  const toField = params.To ?? '';        // "whatsapp:+14155238886"
  const fromField = params.From ?? '';    // "whatsapp:+15005550006"
  const msgBody = params.Body ?? '';
  const messageSid = params.MessageSid ?? '';
  const profileName = params.ProfileName ?? null;
  const numMedia = parseInt(params.NumMedia ?? '0', 10);

  if (!messageSid) {
    console.warn('[com-whatsapp-webhook] Twilio: missing MessageSid');
    return;
  }

  // Strip "whatsapp:+" prefix
  const toNumber = toField.replace(/^whatsapp:\+?/, '');
  const fromNumber = fromField.replace(/^whatsapp:\+?/, '');

  // Find account by phone_number (match suffix to handle with/without country code)
  const { data: cuentas } = await supabase
    .from('com_cuentas')
    .select('*')
    .eq('activo', true)
    .eq('tipo', 'whatsapp')
    .filter('config_json->>bsp', 'eq', 'twilio');

  const cuenta = (cuentas ?? []).find((c: any) => {
    const phone = (c.config_json?.phone_number ?? '').replace(/[^\d]/g, '');
    return phone.endsWith(toNumber) || toNumber.endsWith(phone);
  });

  if (!cuenta) {
    console.warn(`[com-whatsapp-webhook] Twilio: no account for To=${toField}`);
    return;
  }

  // Verify Twilio signature
  const twilioSig = req.headers.get('x-twilio-signature') ?? '';
  const authToken: string = cuenta.config_json?.auth_token ?? '';

  if (authToken && twilioSig) {
    const valid = await verifyTwilioSignature(authToken, twilioSig, requestUrl, params);
    if (!valid) {
      console.warn('[com-whatsapp-webhook] Twilio: invalid X-Twilio-Signature — request rejected');
      return;
    }
  } else if (!authToken) {
    console.warn(`[com-whatsapp-webhook] Twilio: auth_token not configured for cuenta ${cuenta.id}`);
  }

  const messageType = numMedia > 0 ? 'media' : 'text';

  await supabase.rpc('com_registrar_mensaje_inbound', {
    p_cuenta_id: cuenta.id,
    p_canal: 'whatsapp',
    p_destinatario_ref: fromNumber,
    p_destinatario_nombre: profileName,
    p_cuerpo: msgBody || (numMedia > 0 ? `[media x${numMedia}]` : ''),
    p_mensaje_uid: messageSid,
    p_padre_uid: null,
    p_meta_json: {
      bsp: 'twilio',
      type: messageType,
      from: fromField,
      to: toField,
      num_media: numMedia,
    },
  });

  console.info(`[com-whatsapp-webhook] Twilio inbound from ${fromNumber} → cuenta ${cuenta.id}`);
}
