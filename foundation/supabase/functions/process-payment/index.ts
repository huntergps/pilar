/**
 * PILAR ERP — Edge Function: process-payment
 *
 * Procesa un pago con la pasarela configurada para la empresa.
 * Soporta Kushki, Paymentez/Nuvei y PayPhone.
 *
 * Método:  POST
 * Auth:    JWT requerido (verify_jwt: true)
 *
 * Request body:
 * {
 *   "empresa_id":        "uuid",
 *   "gateway":           "KUSHKI" | "PAYMENTEZ" | "PAYPHONE",
 *   "token":             "...",          // Token del cliente (generado en Flutter)
 *   "monto":             10000,          // En centavos: 10000 = $100.00
 *   "moneda":            "USD",
 *   "descripcion":       "Factura 001-001-000000123",
 *   "email_cliente":     "cliente@empresa.com",
 *   "nombre_cliente":    "Juan Pérez",
 *   "referencia_interna": "factura_uuid",
 *   "cuotas":            1              // Opcional, default 1
 * }
 *
 * Respuesta exitosa (200):
 * {
 *   "success": true,
 *   "pago_id": "uuid",
 *   "transaction_id": "...",
 *   "estado": "APROBADO",
 *   "approval_code": "...",
 *   "monto": 10000,
 *   "mensaje": "Pago procesado correctamente"
 * }
 *
 * Errores posibles:
 *   400  PARAMS_INVALIDOS          — campos requeridos faltantes o inválidos
 *   401  UNAUTHORIZED              — JWT ausente o inválido
 *   400  NO_EMPRESA_CONTEXT        — usuario sin empresa_id en app_metadata
 *   403  EMPRESA_MISMATCH          — empresa_id del body no coincide con el contexto RLS
 *   404  GATEWAY_NO_CONFIGURADO    — no hay config_pasarela activa para el gateway
 *   422  GATEWAY_CONFIG_INCOMPLETA — configuración del gateway sin las llaves necesarias
 *   402  PAGO_RECHAZADO            — el gateway rechazó el pago
 *   500  DB_ERROR                  — error al guardar en BD
 *   500  INTERNAL_ERROR            — error inesperado
 *
 * Nota sobre llaves del gateway:
 *   Las llaves privadas se obtienen desde variables de entorno de Supabase.
 *   Se intentará primero la llave específica por empresa, luego la global:
 *     KUSHKI_PRIVATE_KEY_{EMPRESA_ID_SIN_GUIONES}  (específica)
 *     KUSHKI_PRIVATE_KEY                            (global fallback)
 *   Mismo patrón para Paymentez (_APP_CODE, _APP_KEY) y PayPhone (_TOKEN).
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import {
  type GatewayConfig,
  type PaymentRequest,
  type PaymentGateway,
  chargeKushki,
  chargePaymentez,
  chargePayphone,
} from '../_shared/payment-adapter.ts';

// ---------------------------------------------------------------------------
// Tipos locales
// ---------------------------------------------------------------------------

interface ProcessPaymentBody {
  empresa_id: string;
  gateway: PaymentGateway;
  token: string;
  monto: number;
  moneda: string;
  descripcion: string;
  email_cliente: string;
  nombre_cliente: string;
  referencia_interna: string;
  cuotas?: number;
}

interface ConfigPasarelaRow {
  gateway: PaymentGateway;
  ambiente: 'PRUEBAS' | 'PRODUCCION';
  activa: boolean;
  kushki_public_key?: string;
  kushki_merchant_id?: string;
  paymentez_app_code?: string;
  payphone_store_id?: string;
}

// ---------------------------------------------------------------------------
// Helper: respuesta de error
// ---------------------------------------------------------------------------

function errorResponse(
  status: number,
  code: string,
  message?: string,
): Response {
  return new Response(
    JSON.stringify({ success: false, error: code, message }),
    {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
}

// ---------------------------------------------------------------------------
// Helper: obtener llave privada desde env vars
// Patrón: prefijo_{EMPRESA_ID_SIN_GUIONES} | prefijo (global)
// ---------------------------------------------------------------------------

function getEnvKey(prefix: string, empresaId: string): string | undefined {
  const empresaSuffix = empresaId.replace(/-/g, '').toUpperCase();
  return Deno.env.get(`${prefix}_${empresaSuffix}`) ?? Deno.env.get(prefix) ?? undefined;
}

// ---------------------------------------------------------------------------
// Helper: construir GatewayConfig con llaves desde env vars
// ---------------------------------------------------------------------------

function buildGatewayConfig(
  row: ConfigPasarelaRow,
  empresaId: string,
): GatewayConfig {
  const base: GatewayConfig = {
    gateway: row.gateway,
    ambiente: row.ambiente,
  };

  switch (row.gateway) {
    case 'KUSHKI':
      return {
        ...base,
        kushki_public_key: row.kushki_public_key,
        kushki_private_key: getEnvKey('KUSHKI_PRIVATE_KEY', empresaId),
      };
    case 'PAYMENTEZ':
      return {
        ...base,
        paymentez_app_code: row.paymentez_app_code
          ?? getEnvKey('PAYMENTEZ_APP_CODE', empresaId),
        paymentez_app_key: getEnvKey('PAYMENTEZ_APP_KEY', empresaId),
      };
    case 'PAYPHONE':
      return {
        ...base,
        payphone_token: getEnvKey('PAYPHONE_TOKEN', empresaId),
        payphone_store_id: row.payphone_store_id,
      };
    default:
      return base;
  }
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // 1. CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  // 2. Solo POST permitido
  if (req.method !== 'POST') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Solo se acepta POST');
  }

  try {
    // 3. Clientes Supabase
    //    supabaseClient: actúa en nombre del usuario (JWT + RLS)
    //    supabaseAdmin:  service_role para operaciones que omiten RLS (register_pago_online)
    const supabaseClient: SupabaseClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization') ?? '' },
        },
      },
    );

    const supabaseAdmin: SupabaseClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // 4. Autenticación: validar JWT
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return errorResponse(401, 'UNAUTHORIZED', 'Token inválido o expirado');
    }

    // 5. Obtener empresa_id del contexto JWT
    const empresaCtx = user.app_metadata?.empresa_id as string | undefined;
    if (!empresaCtx) {
      return errorResponse(400, 'NO_EMPRESA_CONTEXT', 'El usuario no tiene empresa_id en app_metadata');
    }

    // 6. Parsear body
    let body: ProcessPaymentBody;
    try {
      body = (await req.json()) as ProcessPaymentBody;
    } catch {
      return errorResponse(400, 'PARAMS_INVALIDOS', 'Body JSON inválido');
    }

    // 7. Validar campos requeridos
    const camposRequeridos: (keyof ProcessPaymentBody)[] = [
      'empresa_id',
      'gateway',
      'token',
      'monto',
      'moneda',
      'descripcion',
      'email_cliente',
      'nombre_cliente',
      'referencia_interna',
    ];
    const faltantes = camposRequeridos.filter((c) => !body[c] && body[c] !== 0);
    if (faltantes.length > 0) {
      return errorResponse(
        400,
        'PARAMS_INVALIDOS',
        `Campos requeridos faltantes: ${faltantes.join(', ')}`,
      );
    }

    if (!['KUSHKI', 'PAYMENTEZ', 'PAYPHONE'].includes(body.gateway)) {
      return errorResponse(400, 'PARAMS_INVALIDOS', `Gateway inválido: ${body.gateway}`);
    }

    if (typeof body.monto !== 'number' || body.monto <= 0) {
      return errorResponse(400, 'PARAMS_INVALIDOS', 'El monto debe ser un número positivo en centavos');
    }

    // 8. Verificar que empresa_id del body coincide con el contexto RLS del JWT
    if (body.empresa_id !== empresaCtx) {
      return errorResponse(
        403,
        'EMPRESA_MISMATCH',
        'El empresa_id no coincide con el contexto de sesión',
      );
    }

    // 9. Obtener configuración del gateway para la empresa
    //    Usamos supabaseClient (con JWT) para que RLS filtre por empresa automáticamente
    const { data: configRow, error: configError } = await supabaseClient
      .from('config_pasarela')
      .select(
        'gateway, ambiente, activa, kushki_public_key, kushki_merchant_id, paymentez_app_code, payphone_store_id',
      )
      .eq('empresa_id', body.empresa_id)
      .eq('gateway', body.gateway)
      .eq('activa', true)
      .maybeSingle();

    if (configError) {
      console.error('[process-payment] Error al leer config_pasarela:', configError);
      return errorResponse(500, 'DB_ERROR', 'Error al obtener configuración del gateway');
    }

    if (!configRow) {
      return errorResponse(
        404,
        'GATEWAY_NO_CONFIGURADO',
        `No hay configuración activa para el gateway ${body.gateway}`,
      );
    }

    // 10. Construir GatewayConfig con llaves desde env vars
    const gatewayConfig = buildGatewayConfig(configRow as ConfigPasarelaRow, body.empresa_id);

    // 11. Verificar que las llaves necesarias están presentes
    const configIncompleta = ((): string | null => {
      switch (body.gateway) {
        case 'KUSHKI':
          return gatewayConfig.kushki_private_key ? null : 'kushki_private_key no configurada en env vars';
        case 'PAYMENTEZ':
          if (!gatewayConfig.paymentez_app_code) return 'paymentez_app_code no configurada';
          if (!gatewayConfig.paymentez_app_key) return 'paymentez_app_key no configurada en env vars';
          return null;
        case 'PAYPHONE':
          return gatewayConfig.payphone_token ? null : 'payphone_token no configurado en env vars';
        default:
          return 'Gateway no soportado';
      }
    })();

    if (configIncompleta) {
      console.error(`[process-payment] Config incompleta para ${body.gateway}:`, configIncompleta);
      return errorResponse(
        422,
        'GATEWAY_CONFIG_INCOMPLETA',
        `Configuración incompleta del gateway: ${configIncompleta}`,
      );
    }

    // 12. Construir solicitud de pago
    const paymentRequest: PaymentRequest = {
      token: body.token,
      monto: body.monto,
      moneda: body.moneda,
      descripcion: body.descripcion,
      email_cliente: body.email_cliente,
      nombre_cliente: body.nombre_cliente,
      referencia_interna: body.referencia_interna,
      cuotas: body.cuotas ?? 1,
    };

    // 13. Ejecutar cargo con el adaptador correspondiente
    let result;
    switch (body.gateway) {
      case 'KUSHKI':
        result = await chargeKushki(gatewayConfig, paymentRequest);
        break;
      case 'PAYMENTEZ':
        result = await chargePaymentez(gatewayConfig, paymentRequest);
        break;
      case 'PAYPHONE':
        result = await chargePayphone(gatewayConfig, paymentRequest);
        break;
      default:
        return errorResponse(400, 'PARAMS_INVALIDOS', 'Gateway no soportado');
    }

    // 14. Registrar resultado en BD usando RPC (service_role para omitir RLS)
    const { data: pagoId, error: rpcError } = await supabaseAdmin.rpc(
      'register_pago_online',
      {
        p_empresa_id:              body.empresa_id,
        p_gateway:                 body.gateway,
        p_gateway_transaction_id:  result.transaction_id,
        p_referencia_interna:      body.referencia_interna,
        p_tipo_referencia:         'factura',
        p_monto:                   body.monto / 100, // Centavos → DECIMAL(14,2)
        p_estado:                  result.estado,
        p_ambiente:                configRow.ambiente,
        p_email_cliente:           body.email_cliente,
        p_nombre_cliente:          body.nombre_cliente,
        p_descripcion:             body.descripcion,
        p_respuesta_gateway:       result.raw_response ?? null,
        p_approval_code:           result.approval_code ?? null,
        p_creado_por:              user.id,
      },
    );

    if (rpcError) {
      // El pago ya fue procesado por el gateway. Logueamos el error pero
      // retornamos el resultado del cargo para no dejar al cliente sin respuesta.
      console.error('[process-payment] Error al registrar pago en BD:', rpcError);
    }

    // 15. Si APROBADO, notificar al Module Service Bus de Tesorería
    if (result.estado === 'APROBADO') {
      const { error: busError } = await supabaseAdmin.rpc(
        'module_bus_pagos_register_payment',
        {
          p_empresa_id:    body.empresa_id,
          p_gateway:       body.gateway,
          p_transaction_id: result.transaction_id,
          p_referencia:    body.referencia_interna,
          p_monto:         body.monto / 100,
          p_estado:        result.estado,
        },
      );
      if (busError) {
        // No es crítico: el pago fue registrado. Solo logueamos.
        console.warn('[process-payment] module_bus_pagos_register_payment error:', busError);
      }
    }

    // 16. Retornar respuesta al cliente
    if (result.estado === 'RECHAZADO' || result.estado === 'ERROR') {
      return new Response(
        JSON.stringify({
          success: false,
          pago_id: pagoId ?? null,
          transaction_id: result.transaction_id,
          estado: result.estado,
          monto: body.monto,
          mensaje: result.mensaje ?? 'Pago rechazado por el gateway',
        }),
        {
          status: 402,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        pago_id: pagoId ?? null,
        transaction_id: result.transaction_id,
        estado: result.estado,
        approval_code: result.approval_code ?? null,
        monto: body.monto,
        mensaje: result.mensaje ?? 'Pago procesado correctamente',
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (err) {
    console.error('[process-payment] Error inesperado:', err);
    return errorResponse(500, 'INTERNAL_ERROR', 'Error procesando la solicitud');
  }
});
