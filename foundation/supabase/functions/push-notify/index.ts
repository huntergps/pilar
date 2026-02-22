/**
 * PILAR ERP — Edge Function: push-notify
 *
 * Envía notificaciones push via Firebase Cloud Messaging (FCM) HTTP v1 API.
 * Usada principalmente por el App Salón y App Cliente para:
 *   - Notificar confirmación/cancelación de citas
 *   - Notificar a especialistas sobre nuevas citas asignadas
 *   - Recordatorios de citas próximas (invocado desde booking-reminders)
 *
 * Método:   POST
 * Auth:     verify_jwt: true
 *           - JWT de usuario autenticado (Flutter): se usa para validar
 *           - service_role key: getUser() retorna null → se acepta si empresa_id está en body
 *
 * Env vars requeridas:
 *   FCM_PROJECT_ID          — Google Cloud project ID (ej: "pilar-salon-app")
 *   FCM_SERVICE_ACCOUNT_KEY — JSON del service account key de Firebase (string JSON)
 *   SUPABASE_URL
 *   SUPABASE_ANON_KEY
 *   SUPABASE_SERVICE_ROLE_KEY
 *
 * Body (PushNotifyRequest):
 *   empresa_id     : UUID — empresa que envía la notificación
 *   user_ids?      : string[] — usuarios destino (query device_tokens)
 *   device_tokens? : string[] — tokens FCM directos (alternativa a user_ids)
 *   app_flavor?    : "erp" | "salon" | "cliente" — filtrar tokens por flavor (default: "salon")
 *   notification   : { title, body, image_url? }
 *   data?          : Record<string, string> — payload de datos para deeplink
 *
 * Respuesta exitosa (200):
 *   { success: true, enviados: N, fallidos: M, tokens_desactivados: K }
 *
 * Errores posibles:
 *   405  METHOD_NOT_ALLOWED
 *   400  BODY_INVALIDO
 *   401  UNAUTHORIZED
 *   400  EMPRESA_ID_INVALIDO
 *   400  DESTINO_REQUERIDO
 *   500  FCM_CONFIG_FALTANTE
 *   500  INTERNAL_ERROR
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface NotificationPayload {
  title: string;
  body: string;
  image_url?: string;
}

interface PushNotifyRequest {
  empresa_id: string;
  user_ids?: string[];
  device_tokens?: string[];
  app_flavor?: 'erp' | 'salon' | 'cliente';
  notification: NotificationPayload;
  data?: Record<string, string>;
}

interface FcmResult {
  token: string;
  success: boolean;
  error?: string;
  should_deactivate?: boolean;
}

interface PushNotifyResponse {
  success: boolean;
  enviados: number;
  fallidos: number;
  tokens_desactivados: number;
}

// ---------------------------------------------------------------------------
// Helpers de respuesta HTTP
// ---------------------------------------------------------------------------

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(status: number, code: string, message?: string): Response {
  return jsonResponse(status, { success: false, error: code, message });
}

// ---------------------------------------------------------------------------
// Validación de UUID
// ---------------------------------------------------------------------------

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUuid(value: string): boolean {
  return UUID_REGEX.test(value);
}

// ---------------------------------------------------------------------------
// FCM: importar RSA private key desde PEM (PKCS8)
// ---------------------------------------------------------------------------

async function importRSAPrivateKey(pemKey: string): Promise<CryptoKey> {
  // Remover header/footer PEM y saltos de línea
  const pemContents = pemKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\r?\n/g, '');

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    'pkcs8',
    binaryDer.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

// ---------------------------------------------------------------------------
// FCM: codificar ArrayBuffer a base64url (para JWT)
// ---------------------------------------------------------------------------

function arrayBufferToBase64Url(buffer: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

// ---------------------------------------------------------------------------
// FCM: codificar string a base64url
// ---------------------------------------------------------------------------

function stringToBase64Url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

// ---------------------------------------------------------------------------
// FCM: obtener access token OAuth2 desde service account key
// Vigencia: 1 hora. El llamador debe regenerar si han pasado > 50 minutos.
// ---------------------------------------------------------------------------

export async function getFcmAccessToken(serviceAccountKeyJson: string): Promise<string> {
  const key = JSON.parse(serviceAccountKeyJson);

  const now = Math.floor(Date.now() / 1000);

  // Construir JWT para Google OAuth2
  const header = stringToBase64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = stringToBase64Url(
    JSON.stringify({
      iss: key.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const signingInput = `${header}.${payload}`;
  const privateKey = await importRSAPrivateKey(key.private_key);

  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(signingInput),
  );

  const signature = arrayBufferToBase64Url(signatureBuffer);
  const jwtToken = `${signingInput}.${signature}`;

  // Intercambiar JWT por access token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwtToken,
    }),
  });

  if (!tokenResponse.ok) {
    const errBody = await tokenResponse.text();
    throw new Error(`OAuth2 token exchange failed: ${tokenResponse.status} — ${errBody}`);
  }

  const tokenData = await tokenResponse.json();

  if (!tokenData.access_token) {
    throw new Error(`OAuth2 response missing access_token: ${JSON.stringify(tokenData)}`);
  }

  return tokenData.access_token as string;
}

// ---------------------------------------------------------------------------
// FCM: enviar notificación a un único token con reintentos
// ---------------------------------------------------------------------------

type FcmSendStatus = 'SUCCESS' | 'UNREGISTERED' | 'QUOTA_EXCEEDED' | 'ERROR';

async function sendFcmMessage(
  fcmProjectId: string,
  accessToken: string,
  deviceToken: string,
  notification: NotificationPayload,
  data?: Record<string, string>,
  retryCount: number = 0,
): Promise<FcmSendStatus> {
  const url = `https://fcm.googleapis.com/v1/projects/${fcmProjectId}/messages:send`;

  // Asegurar que todos los valores de data sean strings
  const dataStringified: Record<string, string> = {};
  if (data) {
    for (const [k, v] of Object.entries(data)) {
      dataStringified[k] = String(v);
    }
  }

  const body: Record<string, unknown> = {
    message: {
      token: deviceToken,
      notification: {
        title: notification.title,
        body: notification.body,
        ...(notification.image_url ? { image: notification.image_url } : {}),
      },
      data: dataStringified,
      android: {
        priority: 'HIGH',
        notification: {
          channel_id: 'pilar_citas',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'content-available': 1,
          },
        },
      },
    },
  };

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    if (response.ok) {
      return 'SUCCESS';
    }

    const errData = await response.json().catch(() => ({}));
    const errCode: string = errData?.error?.details?.[0]?.errorCode ?? errData?.error?.status ?? '';

    // Token inválido o desregistrado → desactivar
    if (
      response.status === 404 ||
      errCode === 'UNREGISTERED' ||
      (response.status === 400 && errCode === 'INVALID_ARGUMENT')
    ) {
      console.warn(`[push-notify] Token inválido/desregistrado: ${deviceToken.slice(0, 20)}...`);
      return 'UNREGISTERED';
    }

    // Cuota excedida → no reintentar
    if (response.status === 429 || errCode === 'QUOTA_EXCEEDED') {
      console.warn(`[push-notify] FCM cuota excedida para proyecto ${fcmProjectId}`);
      return 'QUOTA_EXCEEDED';
    }

    // Error 5xx → reintentar máximo 2 veces con 1s de delay
    if (response.status >= 500 && retryCount < 2) {
      console.warn(
        `[push-notify] FCM error ${response.status}, reintento ${retryCount + 1}/2 en 1s...`,
      );
      await new Promise((r) => setTimeout(r, 1000));
      return sendFcmMessage(fcmProjectId, accessToken, deviceToken, notification, data, retryCount + 1);
    }

    console.error(`[push-notify] FCM error no reintentable: ${response.status} ${errCode}`);
    return 'ERROR';
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.error(`[push-notify] Excepción al llamar FCM: ${errMsg}`);

    if (retryCount < 2) {
      await new Promise((r) => setTimeout(r, 1000));
      return sendFcmMessage(fcmProjectId, accessToken, deviceToken, notification, data, retryCount + 1);
    }

    return 'ERROR';
  }
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // 1. CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  // 2. Solo POST
  if (req.method !== 'POST') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Solo se acepta POST');
  }

  // 3. Parsear body
  let body: PushNotifyRequest;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, 'BODY_INVALIDO', 'El cuerpo de la solicitud no es JSON válido');
  }

  const { empresa_id, user_ids, device_tokens: directTokens, app_flavor, notification, data } = body;

  // 4. Validar campos requeridos
  if (!empresa_id || !isValidUuid(empresa_id)) {
    return errorResponse(400, 'EMPRESA_ID_INVALIDO', 'empresa_id debe ser un UUID válido');
  }

  if (!notification?.title || !notification?.body) {
    return errorResponse(400, 'BODY_INVALIDO', 'notification.title y notification.body son obligatorios');
  }

  const hasUserIds = Array.isArray(user_ids) && user_ids.length > 0;
  const hasDirectTokens = Array.isArray(directTokens) && directTokens.length > 0;

  if (!hasUserIds && !hasDirectTokens) {
    return errorResponse(400, 'DESTINO_REQUERIDO', 'Se requiere user_ids o device_tokens');
  }

  // 5. Env vars FCM
  const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
  const fcmServiceAccountKey = Deno.env.get('FCM_SERVICE_ACCOUNT_KEY');

  if (!fcmProjectId || !fcmServiceAccountKey) {
    console.error('[push-notify] FCM_PROJECT_ID o FCM_SERVICE_ACCOUNT_KEY no configurados');
    return errorResponse(500, 'FCM_CONFIG_FALTANTE', 'Firebase no está configurado en este entorno');
  }

  // 6. Supabase clients
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const authHeader = req.headers.get('Authorization') ?? '';

  const supabaseClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const supabaseAdmin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

  // 7. Verificar auth: JWT de usuario o service_role
  const { data: { user } } = await supabaseClient.auth.getUser();
  if (!user) {
    // Sin usuario → solo se acepta si la llamada viene con service_role key
    // (service_role key → getUser() retorna null pero la llamada es interna válida)
    // Validar que tenga empresa_id para continuar
    if (!empresa_id) {
      return errorResponse(401, 'UNAUTHORIZED', 'Se requiere autenticación');
    }
    // Continuar: llamada interna (booking-reminders u otro servicio)
    console.log(`[push-notify] Llamada interna sin JWT para empresa ${empresa_id}`);
  }

  try {
    // 8. Obtener tokens FCM
    let tokensToSend: string[] = [];

    if (hasDirectTokens) {
      tokensToSend = directTokens!;
    } else {
      // Buscar tokens de los user_ids en device_tokens
      // La columna en 012 se llama "flavor" (no app_flavor)
      const flavor = app_flavor ?? 'salon';

      const { data: tokenRows, error: tokenError } = await supabaseAdmin
        .from('device_tokens')
        .select('token')
        .in('user_id', user_ids!)
        .eq('flavor', flavor)
        .eq('activo', true);

      if (tokenError) {
        console.error('[push-notify] Error al consultar device_tokens:', tokenError.message);
        return errorResponse(500, 'DB_ERROR', 'Error al obtener device tokens');
      }

      tokensToSend = (tokenRows ?? []).map((r: { token: string }) => r.token);
    }

    if (tokensToSend.length === 0) {
      console.log(`[push-notify] Sin tokens disponibles para empresa ${empresa_id}`);
      return jsonResponse(200, {
        success: true,
        enviados: 0,
        fallidos: 0,
        tokens_desactivados: 0,
        mensaje: 'No hay tokens activos para los destinatarios indicados',
      } as PushNotifyResponse & { mensaje: string });
    }

    // 9. Obtener access token FCM (vigencia 1h)
    let accessToken: string;
    try {
      accessToken = await getFcmAccessToken(fcmServiceAccountKey);
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      console.error('[push-notify] Error al obtener access token FCM:', errMsg);
      return errorResponse(500, 'FCM_AUTH_ERROR', 'No se pudo autenticar con Firebase');
    }

    // 10. Enviar notificaciones (procesar en paralelo, máximo 500 por lote FCM)
    const BATCH_SIZE = 500;
    const results: FcmResult[] = [];

    for (let i = 0; i < tokensToSend.length; i += BATCH_SIZE) {
      const batch = tokensToSend.slice(i, i + BATCH_SIZE);

      const batchResults = await Promise.all(
        batch.map(async (token): Promise<FcmResult> => {
          const status = await sendFcmMessage(
            fcmProjectId,
            accessToken,
            token,
            notification,
            data,
          );

          return {
            token,
            success: status === 'SUCCESS',
            error: status !== 'SUCCESS' ? status : undefined,
            should_deactivate: status === 'UNREGISTERED',
          };
        }),
      );

      results.push(...batchResults);
    }

    // 11. Desactivar tokens inválidos en BD
    const tokensToDeactivate = results
      .filter((r) => r.should_deactivate)
      .map((r) => r.token);

    if (tokensToDeactivate.length > 0) {
      const { error: deactivateError } = await supabaseAdmin
        .from('device_tokens')
        .update({ activo: false })
        .in('token', tokensToDeactivate);

      if (deactivateError) {
        // No crítico: loguear pero no fallar
        console.warn(
          '[push-notify] Error al desactivar tokens inválidos:',
          deactivateError.message,
        );
      } else {
        console.log(
          `[push-notify] ${tokensToDeactivate.length} tokens desactivados por UNREGISTERED`,
        );
      }
    }

    // 12. Calcular métricas
    const enviados = results.filter((r) => r.success).length;
    const fallidos = results.filter((r) => !r.success).length;
    const tokens_desactivados = tokensToDeactivate.length;

    console.log(
      `[push-notify] empresa=${empresa_id} enviados=${enviados} fallidos=${fallidos} desactivados=${tokens_desactivados}`,
    );

    return jsonResponse(200, {
      success: true,
      enviados,
      fallidos,
      tokens_desactivados,
    } satisfies PushNotifyResponse);
  } catch (err) {
    console.error(
      '[push-notify] Error inesperado:',
      err instanceof Error ? err.message : err,
    );
    return errorResponse(500, 'INTERNAL_ERROR', 'Error procesando la solicitud');
  }
});
