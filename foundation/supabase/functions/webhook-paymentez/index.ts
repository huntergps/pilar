/**
 * PILAR ERP — Edge Function: webhook-paymentez
 *
 * Recibe notificaciones de eventos de pago desde Paymentez/Nuvei.
 * verify_jwt: false — este endpoint es llamado por Paymentez, no por usuarios.
 *
 * Método:  POST
 * Auth:    verify_jwt = false (validación propia con app_key)
 *
 * Payload esperado de Paymentez:
 * {
 *   "transaction": {
 *     "status":             "success" | "failure" | "rejected" | "pending",
 *     "id":                 "TRX123",
 *     "amount":             100.00,
 *     "authorization_code": "ABC123",
 *     "message":            "APROBADO",
 *     "carrier_code":       "00",
 *     "dev_reference":      "factura_uuid",
 *     "status_detail":      "hash_sha256" (firma opcional)
 *   }
 * }
 *
 * Comportamiento:
 *   - SIEMPRE retorna HTTP 200 (Paymentez reintentará si recibe error)
 *   - Los errores internos se loguean en tabla webhook_logs
 *   - Emite pg_notify('pilar_pago_recibido') para Supabase Realtime
 *
 * Nota sobre firma:
 *   Paymentez no garantiza el header de firma en todas las versiones.
 *   La validación se hace con SHA256(app_key + transaction.id) vs status_detail.
 *   Si status_detail no viene en el payload, el webhook se acepta pero
 *   se marca firma_valida = false en webhook_logs.
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders } from '../_shared/cors.ts';
import { validatePaymentezWebhook } from '../_shared/payment-adapter.ts';

// ---------------------------------------------------------------------------
// Tipos locales
// ---------------------------------------------------------------------------

/** Estructura del objeto transaction dentro del payload Paymentez. */
interface PaymentezTransaction {
  status:              string;       // 'success', 'failure', 'rejected', 'pending'
  id:                  string;       // ID de transacción en Paymentez
  amount:              number;       // Monto en decimal (ej: 100.00)
  authorization_code?: string;       // Código de aprobación del banco
  message?:            string;       // Mensaje legible
  carrier_code?:       string;       // Código del adquiriente (00 = aprobado)
  dev_reference?:      string;       // Referencia interna enviada al cobrar (factura_uuid)
  status_detail?:      string;       // Hash SHA256 para validación de firma
  current_status?:     string;       // Estado actual (redundante con status en algunos eventos)
  installments?:       number;       // Número de cuotas
  [key: string]: unknown;
}

/** Payload completo del webhook de Paymentez. */
interface PaymentezWebhookPayload {
  transaction?: PaymentezTransaction;
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

// Mapeo de estados Paymentez → estados internos PILAR
const PAYMENTEZ_STATUS_MAP: Record<string, string> = {
  success:      'APROBADO',
  approved:     'APROBADO',
  failure:      'RECHAZADO',
  rejected:     'RECHAZADO',
  declined:     'RECHAZADO',
  pending:      'PENDIENTE',
  initialized:  'PENDIENTE',
  reversed:     'REVERTIDO',
  chargeback:   'REVERTIDO',
};

// ---------------------------------------------------------------------------
// Helper: respuesta siempre exitosa para el gateway
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
      gateway: 'PAYMENTEZ',
      payload,
      headers,
      firma_valida: firmaValida,
      procesado,
      error: error ?? null,
      received_at: new Date().toISOString(),
    });
  } catch (logErr) {
    console.error('[webhook-paymentez] Error al guardar webhook_log:', logErr);
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

  // 3. Cliente admin (service_role)
  const supabaseAdmin: SupabaseClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // 4. Leer body
  let payload: PaymentezWebhookPayload;
  try {
    const rawBody = await req.text();
    payload = JSON.parse(rawBody) as PaymentezWebhookPayload;
  } catch {
    await logWebhook(supabaseAdmin, {}, {}, false, false, 'Body JSON inválido');
    return gatewayResponse({ error: 'BODY_INVALIDO' });
  }

  // 5. Extraer headers para el log
  const headerSnapshot: Record<string, string> = {
    'content-type': req.headers.get('Content-Type') ?? '',
    'user-agent':   req.headers.get('User-Agent') ?? '',
  };

  // 6. Validar estructura mínima: debe tener transaction.id
  const transaction = payload.transaction;
  if (!transaction || !transaction.id) {
    const errMsg = 'Payload sin transaction.id';
    await logWebhook(
      supabaseAdmin,
      payload as Record<string, unknown>,
      headerSnapshot,
      false,
      false,
      errMsg,
    );
    return gatewayResponse({ warning: errMsg });
  }

  // 7. Validar firma con app_key
  //    La app_key se obtiene de env vars (global o específica)
  const paymentezAppKey = Deno.env.get('PAYMENTEZ_APP_KEY') ?? '';
  let firmaValida = false;

  if (!paymentezAppKey) {
    console.warn('[webhook-paymentez] PAYMENTEZ_APP_KEY no configurada, omitiendo validación de firma');
    firmaValida = true; // Permisivo en desarrollo
  } else {
    firmaValida = await validatePaymentezWebhook(
      payload as Record<string, unknown>,
      paymentezAppKey,
    );
    if (!firmaValida) {
      console.warn('[webhook-paymentez] Firma no válida o ausente para transaction.id:', transaction.id);
      // Continuamos con firma inválida para no perder el evento,
      // pero lo registramos en webhook_logs para auditoría
    }
  }

  // 8. Mapear estado Paymentez → estado PILAR
  const statusRaw = (
    transaction.current_status ??
    transaction.status ??
    'unknown'
  ).toLowerCase();

  const estadoPilar = PAYMENTEZ_STATUS_MAP[statusRaw] ?? null;

  if (!estadoPilar) {
    const errMsg = `Status desconocido: ${statusRaw}`;
    await logWebhook(
      supabaseAdmin,
      payload as Record<string, unknown>,
      headerSnapshot,
      firmaValida,
      false,
      errMsg,
    );
    return gatewayResponse({ warning: errMsg });
  }

  const transactionId    = transaction.id;
  const approvalCode     = transaction.authorization_code ?? null;
  const referencia       = transaction.dev_reference ?? null;
  const montoDecimal     = transaction.amount ?? 0;

  // 9. Actualizar estado del pago en BD
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
    console.error('[webhook-paymentez] Error al actualizar pago:', updateError);
    await logWebhook(
      supabaseAdmin,
      payload as Record<string, unknown>,
      headerSnapshot,
      firmaValida,
      false,
      `DB error: ${updateError.message}`,
    );
    return gatewayResponse({ warning: 'DB_ERROR' });
  }

  // 10. Si el pago no existía (webhook huérfano) e APROBADO, insertar registro
  if (!actualizado && estadoPilar === 'APROBADO' && referencia) {
    const { error: insertError } = await supabaseAdmin.rpc(
      'register_pago_online',
      {
        p_empresa_id:              null,
        p_gateway:                 'PAYMENTEZ',
        p_gateway_transaction_id:  transactionId,
        p_referencia_interna:      referencia,
        p_tipo_referencia:         'factura',
        p_monto:                   montoDecimal,
        p_estado:                  estadoPilar,
        p_ambiente:                'PRODUCCION',
        p_approval_code:           approvalCode,
        p_respuesta_gateway:       payload as unknown as Record<string, unknown>,
      },
    );
    if (insertError) {
      console.warn('[webhook-paymentez] Error al insertar pago huérfano:', insertError);
    }
  }

  // 11. Emitir pg_notify para Realtime
  if (estadoPilar === 'APROBADO' || estadoPilar === 'RECHAZADO') {
    try {
      await supabaseAdmin.rpc('pg_notify_pago', {
        p_canal:   'pilar_pago_recibido',
        p_payload: JSON.stringify({
          gateway:        'PAYMENTEZ',
          transaction_id: transactionId,
          estado:         estadoPilar,
          monto_decimal:  montoDecimal,
          referencia,
        }),
      });
    } catch (notifyErr) {
      console.warn('[webhook-paymentez] Error al emitir pg_notify:', notifyErr);
    }
  }

  // 12. Registrar log de auditoría exitoso
  await logWebhook(
    supabaseAdmin,
    payload as Record<string, unknown>,
    headerSnapshot,
    firmaValida,
    true,
  );

  return gatewayResponse({
    transaction_id: transactionId,
    estado:         estadoPilar,
  });
});
