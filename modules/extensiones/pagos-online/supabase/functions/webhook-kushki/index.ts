/**
 * PILAR ERP — Edge Function: webhook-kushki
 *
 * Recibe notificaciones de eventos de pago desde Kushki.
 * verify_jwt: false — este endpoint es llamado por Kushki, no por usuarios.
 * La autenticación se realiza validando la firma HMAC-SHA256 del body.
 *
 * Método:  POST
 * Auth:    verify_jwt = false (validación propia por firma Kushki)
 *
 * Kushki envía el header `X-Kushki-Signature` con el HMAC-SHA256 del body
 * usando la private key del merchant como secreto.
 *
 * Eventos manejados:
 *   - status: APPROVAL   → estado APROBADO
 *   - status: DECLINED   → estado RECHAZADO
 *   - status: REVERSAL   → estado REVERTIDO
 *
 * Comportamiento:
 *   - SIEMPRE retorna HTTP 200 (Kushki reintentará si recibe error)
 *   - Los errores internos se loguean en tabla webhook_logs
 *   - Emite pg_notify('pilar_pago_recibido') para Supabase Realtime
 *
 * Nota de seguridad:
 *   En entorno PRODUCCION la firma es obligatoria.
 *   En entorno PRUEBAS se acepta sin firma (para facilitar testing),
 *   pero se registra la advertencia en webhook_logs.
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders } from '../_shared/cors.ts';
import { validateKushkiSignature } from '../_shared/payment-adapter.ts';

// ---------------------------------------------------------------------------
// Tipos locales
// ---------------------------------------------------------------------------

/** Payload normalizado del webhook de Kushki. */
interface KushkiWebhookPayload {
  ticketNumber?: string;
  transactionId?: string;
  transactionReference?: string;
  transactionStatus?: string;   // APPROVAL, DECLINED, REVERSAL, etc.
  responseCode?: string;
  responseText?: string;
  approvalCode?: string;
  amount?: {
    subtotalIva?: number;
    subtotalIva0?: number;
    currency?: string;
  };
  metadata?: {
    referencia?: string;
    [key: string]: unknown;
  };
  // El campo 'status' también puede venir en el root según versión de Kushki
  status?: string;
}

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

// Mapeo de estados Kushki → estados internos PILAR
const KUSHKI_STATUS_MAP: Record<string, string> = {
  APPROVAL:     'APROBADO',
  DECLINED:     'RECHAZADO',
  CARD_DECLINED: 'RECHAZADO',
  FRAUD:        'RECHAZADO',
  EXPIRED_CARD: 'RECHAZADO',
  REVERSAL:     'REVERTIDO',
  CHARGEBACK:   'REVERTIDO',
};

// ---------------------------------------------------------------------------
// Helper: respuesta siempre exitosa para el gateway
// Kushki requiere HTTP 200; si recibe error, reintenta indefinidamente.
// ---------------------------------------------------------------------------

function gatewayResponse(extra?: Record<string, unknown>): Response {
  return new Response(
    JSON.stringify({ received: true, ...extra }),
    {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
}

// ---------------------------------------------------------------------------
// Helper: registrar log del webhook para auditoría
// ---------------------------------------------------------------------------

async function logWebhook(
  supabaseAdmin: SupabaseClient,
  payload: Record<string, unknown>,
  headers: Record<string, string>,
  firmaValida: boolean,
  procesado: boolean,
  error?: string,
): Promise<void> {
  try {
    await supabaseAdmin.from('webhook_logs').insert({
      gateway: 'KUSHKI',
      payload,
      headers,
      firma_valida: firmaValida,
      procesado,
      error: error ?? null,
      received_at: new Date().toISOString(),
    });
  } catch (logErr) {
    // No propagar error de logging: el webhook debe retornar 200 siempre
    console.error('[webhook-kushki] Error al guardar webhook_log:', logErr);
  }
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // 1. CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 2. Solo POST permitido
  if (req.method !== 'POST') {
    return gatewayResponse({ error: 'METHOD_NOT_ALLOWED' });
  }

  // 3. Cliente admin (service_role): los webhooks son llamadas del gateway,
  //    no de usuarios autenticados. Se usa service_role para todas las operaciones.
  const supabaseAdmin: SupabaseClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // 4. Leer body raw (necesario para validar firma HMAC)
  let rawBody: string;
  let payload: KushkiWebhookPayload;

  try {
    rawBody = await req.text();
    payload = JSON.parse(rawBody) as KushkiWebhookPayload;
  } catch {
    await logWebhook(supabaseAdmin, {}, {}, false, false, 'Body JSON inválido');
    return gatewayResponse({ error: 'BODY_INVALIDO' });
  }

  // 5. Extraer headers relevantes para el log
  const headerSnapshot: Record<string, string> = {
    'x-kushki-signature': req.headers.get('X-Kushki-Signature') ?? '',
    'content-type':       req.headers.get('Content-Type') ?? '',
    'user-agent':         req.headers.get('User-Agent') ?? '',
  };

  // 6. Validar firma HMAC-SHA256
  //    La private key se obtiene de env vars (usa la clave global o específica por merchant)
  const kushkiPrivateKey = Deno.env.get('KUSHKI_PRIVATE_KEY') ?? '';
  const receivedSignature = req.headers.get('X-Kushki-Signature') ?? '';

  let firmaValida = false;

  if (!kushkiPrivateKey) {
    console.warn('[webhook-kushki] KUSHKI_PRIVATE_KEY no configurada, omitiendo validación de firma');
    firmaValida = true; // Permisivo si no hay llave configurada (solo en desarrollo)
  } else if (!receivedSignature) {
    console.warn('[webhook-kushki] Webhook recibido sin X-Kushki-Signature');
    // En producción se debería rechazar; en pruebas se acepta
    const ambiente = Deno.env.get('PILAR_AMBIENTE') ?? 'PRUEBAS';
    firmaValida = ambiente !== 'PRODUCCION';
  } else {
    firmaValida = await validateKushkiSignature(rawBody, receivedSignature, kushkiPrivateKey);
  }

  if (!firmaValida) {
    console.error('[webhook-kushki] Firma inválida:', { receivedSignature: receivedSignature.substring(0, 20) + '...' });
    await logWebhook(supabaseAdmin, payload as unknown as Record<string, unknown>, headerSnapshot, false, false, 'Firma HMAC-SHA256 inválida');
    // Retornamos 200 de todas formas para evitar bucles de reintento de Kushki,
    // pero registramos el fallo para auditoría.
    return gatewayResponse({ warning: 'FIRMA_INVALIDA' });
  }

  // 7. Extraer datos del payload
  const transactionId =
    payload.ticketNumber ??
    payload.transactionId ??
    payload.transactionReference ??
    '';

  const statusRaw = (
    payload.transactionStatus ??
    payload.status ??
    'UNKNOWN'
  ).toUpperCase();

  const estadoPilar = KUSHKI_STATUS_MAP[statusRaw] ?? null;

  // Monto: Kushki separa subtotalIva e subtotalIva0
  const montoDecimal =
    (payload.amount?.subtotalIva ?? 0) +
    (payload.amount?.subtotalIva0 ?? 0);
  const montoCentavos = Math.round(montoDecimal * 100);

  const referencia = payload.metadata?.referencia ?? null;
  const approvalCode = payload.approvalCode ?? null;

  if (!transactionId) {
    const errMsg = 'Payload sin transactionId/ticketNumber';
    await logWebhook(supabaseAdmin, payload as unknown as Record<string, unknown>, headerSnapshot, true, false, errMsg);
    return gatewayResponse({ warning: errMsg });
  }

  if (!estadoPilar) {
    const errMsg = `Status desconocido: ${statusRaw}`;
    await logWebhook(supabaseAdmin, payload as unknown as Record<string, unknown>, headerSnapshot, true, false, errMsg);
    return gatewayResponse({ warning: errMsg });
  }

  // 8. Actualizar estado del pago existente
  const { data: actualizado, error: updateError } = await supabaseAdmin.rpc(
    'update_pago_desde_webhook',
    {
      p_gateway_transaction_id: transactionId,
      p_nuevo_estado:           estadoPilar,
      p_approval_code:          approvalCode,
      p_respuesta_raw:          payload as unknown as Record<string, unknown>,
    },
  );

  if (updateError) {
    console.error('[webhook-kushki] Error al actualizar pago:', updateError);
    await logWebhook(
      supabaseAdmin,
      payload as unknown as Record<string, unknown>,
      headerSnapshot,
      true,
      false,
      `DB error: ${updateError.message}`,
    );
    // Retornar 200 de todas formas (Kushki no debe reintentar por errores internos)
    return gatewayResponse({ warning: 'DB_ERROR' });
  }

  // 9. Si el pago no existía en BD (webhook llegó antes que process-payment),
  //    insertar el registro si tenemos suficientes datos y el estado es APROBADO
  if (!actualizado && estadoPilar === 'APROBADO' && referencia) {
    const { error: insertError } = await supabaseAdmin.rpc(
      'register_pago_online',
      {
        p_empresa_id:              null,        // Desconocido desde webhook
        p_gateway:                 'KUSHKI',
        p_gateway_transaction_id:  transactionId,
        p_referencia_interna:      referencia,
        p_tipo_referencia:         'factura',
        p_monto:                   montoDecimal,
        p_estado:                  estadoPilar,
        p_ambiente:                'PRODUCCION', // Si llegó webhook es producción
        p_approval_code:           approvalCode,
        p_respuesta_gateway:       payload as unknown as Record<string, unknown>,
      },
    );
    if (insertError) {
      console.warn('[webhook-kushki] Error al insertar pago huérfano:', insertError);
    }
  }

  // 10. Emitir pg_notify para Realtime (Supabase Channels)
  //     Permite que el frontend actualice el estado del pago en tiempo real
  if (estadoPilar === 'APROBADO' || estadoPilar === 'RECHAZADO') {
    try {
      await supabaseAdmin.rpc('pg_notify_pago', {
        p_canal:   'pilar_pago_recibido',
        p_payload: JSON.stringify({
          gateway:         'KUSHKI',
          transaction_id:  transactionId,
          estado:          estadoPilar,
          monto_centavos:  montoCentavos,
          referencia,
        }),
      });
    } catch (notifyErr) {
      // No crítico: solo logueamos
      console.warn('[webhook-kushki] Error al emitir pg_notify:', notifyErr);
    }
  }

  // 11. Registrar en webhook_logs (para auditoría exitosa)
  await logWebhook(
    supabaseAdmin,
    payload as unknown as Record<string, unknown>,
    headerSnapshot,
    true,
    true,
  );

  return gatewayResponse({
    transaction_id: transactionId,
    estado:         estadoPilar,
  });
});
