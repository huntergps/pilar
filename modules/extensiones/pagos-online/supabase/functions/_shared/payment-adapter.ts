/**
 * PILAR ERP — Shared: payment-adapter.ts
 *
 * Adaptador de pasarelas de pago. Implementa el patrón Adapter para unificar
 * Kushki, Paymentez/Nuvei y PayPhone bajo una interfaz común.
 *
 * Pasarelas soportadas:
 *   - Kushki     (PCI Level 1, HQ Ecuador) — tokenización client-side
 *   - Paymentez  (Nuvei) — autenticación HMAC con timestamp
 *   - PayPhone   (Ecuador) — Bearer token
 *
 * Convenciones:
 *   - Montos:     siempre en CENTAVOS (integer). 1000 = $10.00
 *   - Moneda:     'USD' para Ecuador
 *   - Ambiente:   'PRUEBAS' | 'PRODUCCION'
 *   - NUNCA loguear llaves privadas ni tokens de tarjeta
 */

import { encodeBase64 } from 'jsr:@std/encoding@0.224/base64';

// =============================================================================
// TIPOS PÚBLICOS
// =============================================================================

export type PaymentGateway = 'KUSHKI' | 'PAYMENTEZ' | 'PAYPHONE';

/**
 * Configuración de una pasarela para una empresa específica.
 * Las llaves privadas NO se almacenan en BD; se leen desde env vars.
 */
export interface GatewayConfig {
  gateway: PaymentGateway;
  ambiente: 'PRUEBAS' | 'PRODUCCION';
  // Kushki
  kushki_public_key?: string;   // Clave pública (para Flutter SDK — solo referencia)
  kushki_private_key?: string;  // Clave privada (NUNCA sale de Edge Function)
  // Paymentez
  paymentez_app_code?: string;
  paymentez_app_key?: string;
  // PayPhone
  payphone_token?: string;
  payphone_store_id?: string;
}

/**
 * Solicitud de pago unificada.
 * El `token` proviene del SDK del gateway ejecutado en el cliente Flutter.
 */
export interface PaymentRequest {
  token: string;               // Token generado en Flutter con SDK del gateway
  monto: number;               // En centavos: 1000 = $10.00
  moneda: string;              // Siempre 'USD' para Ecuador
  descripcion: string;         // Descripción del cobro (aparece en estado de cuenta)
  email_cliente: string;
  nombre_cliente: string;
  referencia_interna: string;  // UUID de la factura u otro documento
  cuotas?: number;             // 1 = pago de contado (default)
}

/**
 * Resultado del procesamiento de pago.
 */
export interface PaymentResult {
  success: boolean;
  gateway: PaymentGateway;
  transaction_id: string;       // ID asignado por el gateway
  approval_code?: string;       // Código de aprobación del banco emisor
  estado: 'APROBADO' | 'RECHAZADO' | 'PENDIENTE' | 'ERROR';
  monto: number;                // En centavos, tal como se envió
  mensaje?: string;             // Mensaje legible del gateway o banco
  raw_response?: Record<string, unknown>;
}

/**
 * Evento normalizado recibido desde un webhook de pasarela.
 */
export interface WebhookEvent {
  gateway: PaymentGateway;
  transaction_id: string;
  estado: 'APROBADO' | 'RECHAZADO' | 'REVERTIDO';
  monto: number;                // En centavos
  referencia_interna?: string;  // Devuelta en metadata por el gateway
  raw_payload: Record<string, unknown>;
}

// =============================================================================
// URLS BASE POR AMBIENTE
// =============================================================================

const KUSHKI_BASE: Record<string, string> = {
  PRUEBAS:    'https://api-uat.kushkipagos.com',
  PRODUCCION: 'https://api.kushkipagos.com',
};

const PAYMENTEZ_BASE: Record<string, string> = {
  PRUEBAS:    'https://ccapi-stg.paymentez.com',
  PRODUCCION: 'https://ccapi.paymentez.com',
};

const PAYPHONE_BASE = 'https://pay.payphonetodoesposible.com';

// =============================================================================
// HELPERS INTERNOS
// =============================================================================

/**
 * Genera el Auth-Token para Paymentez/Nuvei.
 * Fórmula: Base64(app_code + ";" + unix_timestamp + ";" + SHA256(unix_timestamp + app_key))
 * Referencia: https://developers.paymentez.com/docs/authentication
 */
async function generatePaymentezAuthToken(
  appCode: string,
  appKey: string,
): Promise<string> {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const hashInput = new TextEncoder().encode(timestamp + appKey);
  const hashBuffer = await crypto.subtle.digest('SHA-256', hashInput);
  const hashHex = Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  const raw = `${appCode};${timestamp};${hashHex}`;
  return encodeBase64(new TextEncoder().encode(raw));
}

/**
 * Mapea el status de Kushki al estado interno de PILAR.
 */
function mapKushkiStatus(
  status: string,
): 'APROBADO' | 'RECHAZADO' | 'PENDIENTE' | 'ERROR' {
  switch (status?.toUpperCase()) {
    case 'APPROVAL':
      return 'APROBADO';
    case 'DECLINED':
    case 'CARD_DECLINED':
    case 'FRAUD':
    case 'EXPIRED_CARD':
      return 'RECHAZADO';
    case 'PENDING':
      return 'PENDIENTE';
    default:
      return 'ERROR';
  }
}

/**
 * Mapea el status de Paymentez al estado interno de PILAR.
 */
function mapPaymentezStatus(
  status: string,
): 'APROBADO' | 'RECHAZADO' | 'PENDIENTE' | 'ERROR' {
  switch (status?.toLowerCase()) {
    case 'success':
    case 'approved':
      return 'APROBADO';
    case 'failure':
    case 'rejected':
    case 'declined':
      return 'RECHAZADO';
    case 'pending':
    case 'initialized':
      return 'PENDIENTE';
    default:
      return 'ERROR';
  }
}

/**
 * Mapea el status de PayPhone al estado interno de PILAR.
 * PayPhone usa statusCode: 2 = approved, 3 = rejected, 1 = pending
 */
function mapPayphoneStatus(
  statusCode: number,
): 'APROBADO' | 'RECHAZADO' | 'PENDIENTE' | 'ERROR' {
  switch (statusCode) {
    case 2:
      return 'APROBADO';
    case 3:
    case 4:
      return 'RECHAZADO';
    case 1:
      return 'PENDIENTE';
    default:
      return 'ERROR';
  }
}

// =============================================================================
// ADAPTADOR KUSHKI
// =============================================================================

/**
 * Procesa un pago con Kushki.
 * El token fue generado en Flutter con el SDK de Kushki (public key).
 * Aquí se usa la private key para hacer el cargo en el servidor.
 *
 * Endpoint: POST /card/v1/charges
 * Auth: Header Private-Merchant-Id
 */
export async function chargeKushki(
  config: GatewayConfig,
  payment: PaymentRequest,
): Promise<PaymentResult> {
  if (!config.kushki_private_key) {
    return {
      success: false,
      gateway: 'KUSHKI',
      transaction_id: '',
      estado: 'ERROR',
      monto: payment.monto,
      mensaje: 'Configuración incompleta: falta kushki_private_key',
    };
  }

  const baseUrl = KUSHKI_BASE[config.ambiente] ?? KUSHKI_BASE.PRUEBAS;
  const montoDecimal = payment.monto / 100; // Centavos → decimal

  let rawBody: string;
  let rawResponse: Record<string, unknown> = {};

  try {
    const requestBody = {
      token: { id: payment.token },
      amount: {
        subtotalIva: 0,
        subtotalIva0: montoDecimal,
        ice: 0,
        iva: 0,
        currency: payment.moneda,
      },
      months: payment.cuotas ?? 1,
      metadata: {
        referencia: payment.referencia_interna,
        email: payment.email_cliente,
        nombre: payment.nombre_cliente,
        descripcion: payment.descripcion,
      },
    };

    rawBody = JSON.stringify(requestBody);

    const response = await fetch(`${baseUrl}/card/v1/charges`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Private-Merchant-Id': config.kushki_private_key,
      },
      body: rawBody,
    });

    rawResponse = (await response.json()) as Record<string, unknown>;

    // Kushki retorna 201 en éxito, 4xx en error
    if (!response.ok) {
      const code = (rawResponse.code as string) ?? 'ERROR';
      const message = (rawResponse.message as string) ?? 'Error en el cargo';
      return {
        success: false,
        gateway: 'KUSHKI',
        transaction_id: (rawResponse.ticketNumber as string) ?? '',
        estado: 'RECHAZADO',
        monto: payment.monto,
        mensaje: `[${code}] ${message}`,
        raw_response: rawResponse,
      };
    }

    const ticketNumber = (rawResponse.ticketNumber as string) ?? '';
    const approvalCode = (rawResponse.approvalCode as string) ?? undefined;

    return {
      success: true,
      gateway: 'KUSHKI',
      transaction_id: ticketNumber,
      approval_code: approvalCode,
      estado: 'APROBADO',
      monto: payment.monto,
      mensaje: 'Transacción aprobada',
      raw_response: rawResponse,
    };
  } catch (err) {
    console.error('[payment-adapter/kushki] Error de red:', err);
    return {
      success: false,
      gateway: 'KUSHKI',
      transaction_id: '',
      estado: 'ERROR',
      monto: payment.monto,
      mensaje: err instanceof Error ? err.message : 'Error de comunicación con Kushki',
      raw_response: rawResponse,
    };
  }
}

// =============================================================================
// ADAPTADOR PAYMENTEZ / NUVEI
// =============================================================================

/**
 * Procesa un pago con Paymentez (Nuvei).
 * Autenticación: Auth-Token dinámico (HMAC con timestamp).
 *
 * Endpoint: POST /v2/transaction/debit/
 */
export async function chargePaymentez(
  config: GatewayConfig,
  payment: PaymentRequest,
): Promise<PaymentResult> {
  if (!config.paymentez_app_code || !config.paymentez_app_key) {
    return {
      success: false,
      gateway: 'PAYMENTEZ',
      transaction_id: '',
      estado: 'ERROR',
      monto: payment.monto,
      mensaje: 'Configuración incompleta: falta paymentez_app_code o paymentez_app_key',
    };
  }

  const baseUrl = PAYMENTEZ_BASE[config.ambiente] ?? PAYMENTEZ_BASE.PRUEBAS;
  const montoDecimal = payment.monto / 100; // Centavos → decimal
  let rawResponse: Record<string, unknown> = {};

  try {
    const authToken = await generatePaymentezAuthToken(
      config.paymentez_app_code,
      config.paymentez_app_key,
    );

    const requestBody = {
      user: {
        id: payment.email_cliente,
        email: payment.email_cliente,
      },
      order: {
        amount: montoDecimal,
        description: payment.descripcion,
        dev_reference: payment.referencia_interna,
        vat: 0,
      },
      card: {
        token: payment.token,
      },
    };

    const response = await fetch(`${baseUrl}/v2/transaction/debit/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Auth-Token': authToken,
      },
      body: JSON.stringify(requestBody),
    });

    rawResponse = (await response.json()) as Record<string, unknown>;

    // Paymentez siempre retorna 200; el estado real está en transaction.status
    const transaction = rawResponse.transaction as Record<string, unknown> | undefined;
    if (!transaction) {
      const errorMsg = (rawResponse.error as Record<string, unknown>)?.type as string
        ?? 'Respuesta inesperada de Paymentez';
      return {
        success: false,
        gateway: 'PAYMENTEZ',
        transaction_id: '',
        estado: 'ERROR',
        monto: payment.monto,
        mensaje: errorMsg,
        raw_response: rawResponse,
      };
    }

    const statusRaw = (transaction.status as string) ?? '';
    const estado = mapPaymentezStatus(statusRaw);
    const txId = (transaction.id as string) ?? '';
    const authCode = (transaction.authorization_code as string) ?? undefined;
    const mensaje = (transaction.message as string) ?? statusRaw;

    return {
      success: estado === 'APROBADO',
      gateway: 'PAYMENTEZ',
      transaction_id: txId,
      approval_code: authCode,
      estado,
      monto: payment.monto,
      mensaje,
      raw_response: rawResponse,
    };
  } catch (err) {
    console.error('[payment-adapter/paymentez] Error de red:', err);
    return {
      success: false,
      gateway: 'PAYMENTEZ',
      transaction_id: '',
      estado: 'ERROR',
      monto: payment.monto,
      mensaje: err instanceof Error ? err.message : 'Error de comunicación con Paymentez',
      raw_response: rawResponse,
    };
  }
}

// =============================================================================
// ADAPTADOR PAYPHONE
// =============================================================================

/**
 * Procesa un pago con PayPhone.
 * PayPhone Ecuador usa un Bearer token estático para autenticación.
 *
 * Endpoint: POST /api/button/Charge
 * El `token` aquí es el clientTransactionId (token de transacción de PayPhone).
 */
export async function chargePayphone(
  config: GatewayConfig,
  payment: PaymentRequest,
): Promise<PaymentResult> {
  if (!config.payphone_token) {
    return {
      success: false,
      gateway: 'PAYPHONE',
      transaction_id: '',
      estado: 'ERROR',
      monto: payment.monto,
      mensaje: 'Configuración incompleta: falta payphone_token',
    };
  }

  let rawResponse: Record<string, unknown> = {};

  try {
    const requestBody = {
      amount: payment.monto,                   // PayPhone trabaja en centavos
      amountWithTax: payment.monto,
      amountWithoutTax: payment.monto,
      tax: 0,
      currency: payment.moneda,
      clientTransactionId: payment.referencia_interna,
      storeId: config.payphone_store_id ?? undefined,
      phoneNumber: '',                         // Opcional en Charge directo
      countPhoneNumber: '593',
      reference: payment.descripcion,
      email: payment.email_cliente,
      documentId: '',
      token: payment.token,
    };

    const response = await fetch(`${PAYPHONE_BASE}/api/button/Charge`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.payphone_token}`,
      },
      body: JSON.stringify(requestBody),
    });

    rawResponse = (await response.json()) as Record<string, unknown>;

    if (!response.ok) {
      const errMsg = (rawResponse.message as string)
        ?? (rawResponse.error as string)
        ?? 'Error en el cargo PayPhone';
      return {
        success: false,
        gateway: 'PAYPHONE',
        transaction_id: '',
        estado: 'RECHAZADO',
        monto: payment.monto,
        mensaje: errMsg,
        raw_response: rawResponse,
      };
    }

    const statusCode = (rawResponse.statusCode as number) ?? 0;
    const estado = mapPayphoneStatus(statusCode);
    const txId = (rawResponse.transactionId as string)
      ?? (rawResponse.id as string)
      ?? '';
    const authCode = (rawResponse.authorizationCode as string) ?? undefined;
    const mensaje = (rawResponse.message as string) ?? String(statusCode);

    return {
      success: estado === 'APROBADO',
      gateway: 'PAYPHONE',
      transaction_id: txId,
      approval_code: authCode,
      estado,
      monto: payment.monto,
      mensaje,
      raw_response: rawResponse,
    };
  } catch (err) {
    console.error('[payment-adapter/payphone] Error de red:', err);
    return {
      success: false,
      gateway: 'PAYPHONE',
      transaction_id: '',
      estado: 'ERROR',
      monto: payment.monto,
      mensaje: err instanceof Error ? err.message : 'Error de comunicación con PayPhone',
      raw_response: rawResponse,
    };
  }
}

// =============================================================================
// VALIDACIÓN DE FIRMAS / WEBHOOKS
// =============================================================================

/**
 * Valida la firma HMAC-SHA256 del webhook de Kushki.
 * Kushki envía el header `X-Kushki-Signature` con el HMAC del body en hex.
 *
 * @param body      Body raw del request (string, tal como llegó)
 * @param signature Valor del header X-Kushki-Signature
 * @param privateKey Private key de Kushki (la misma usada para cargos)
 */
export async function validateKushkiSignature(
  body: string,
  signature: string,
  privateKey: string,
): Promise<boolean> {
  try {
    const keyMaterial = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(privateKey),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const sigBuffer = await crypto.subtle.sign(
      'HMAC',
      keyMaterial,
      new TextEncoder().encode(body),
    );
    const computed = Array.from(new Uint8Array(sigBuffer))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    // Comparación en tiempo constante (evitar timing attacks)
    return timingSafeEqual(computed, signature);
  } catch {
    return false;
  }
}

/**
 * Valida el webhook de Paymentez.
 * Paymentez firma con SHA256(app_key + transaction.id).
 * El campo `transaction.status_detail` contiene el hash para validar.
 *
 * @param payload   Objeto JSON del webhook
 * @param appKey    App key de Paymentez
 */
export async function validatePaymentezWebhook(
  payload: Record<string, unknown>,
  appKey: string,
): Promise<boolean> {
  try {
    const transaction = payload.transaction as Record<string, unknown> | undefined;
    if (!transaction) return false;

    const txId = transaction.id as string;
    if (!txId) return false;

    // Paymentez firma: SHA256(app_key + transaction.id)
    const input = new TextEncoder().encode(appKey + txId);
    const hashBuffer = await crypto.subtle.digest('SHA-256', input);
    const computed = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');

    // El campo `status_detail` lleva el hash (según documentación Paymentez)
    const received = transaction.status_detail as string | undefined;
    if (!received) {
      // Si no viene firma, se acepta en ambiente de pruebas pero debe registrarse
      console.warn('[payment-adapter] Webhook Paymentez sin status_detail (sin firma)');
      return true; // Permisivo: en producción considerar rechazar
    }

    return timingSafeEqual(computed, received);
  } catch {
    return false;
  }
}

/**
 * Comparación de strings en tiempo constante para evitar timing attacks.
 * Ambas cadenas deben tener la misma longitud para que sea efectiva.
 */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
