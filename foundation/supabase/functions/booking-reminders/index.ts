/**
 * PILAR ERP — Edge Function: booking-reminders
 *
 * Batch job para enviar recordatorios de citas próximas.
 * Diseñado para ejecutarse cada hora via pg_cron.
 *
 * Busca citas CONFIRMADAS dentro de las próximas 24h (configurable) que no hayan
 * recibido recordatorio y envía notificaciones push FCM al cliente (app "cliente")
 * y/o al especialista (app "salon").
 *
 * Método:   POST
 * Auth:     verify_jwt: false — llamado por pg_cron
 *           Protección: header "Authorization: Bearer {CRON_SECRET}"
 *
 * Env vars requeridas:
 *   CRON_SECRET               — Secret compartido con pg_cron para autorizar llamadas
 *   FCM_PROJECT_ID            — Google Cloud project ID
 *   FCM_SERVICE_ACCOUNT_KEY   — JSON del service account key de Firebase
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *
 * Respuesta exitosa (200):
 *   { ok: true, procesadas: N, errores: M, push_enviados: K, duration_ms: D }
 *
 * Errores:
 *   401  UNAUTHORIZED — CRON_SECRET inválido o faltante
 *   500  FCM_CONFIG_FALTANTE
 *   500  INTERNAL_ERROR
 *
 * Registro en pg_cron (ejecutar en Supabase Dashboard → SQL Editor):
 *   SELECT cron.schedule(
 *     'booking-reminders',
 *     '0 * * * *',
 *     $$SELECT net.http_post(
 *       url    := 'https://{project_ref}.supabase.co/functions/v1/booking-reminders',
 *       headers := jsonb_build_object(
 *         'Authorization', 'Bearer ' || current_setting('app.cron_secret'),
 *         'Content-Type', 'application/json'
 *       ),
 *       body   := '{}'::jsonb
 *     )$$
 *   );
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

/**
 * Fila retornada por la RPC get_citas_para_recordatorio().
 * Mapeada desde el JSONB que retorna la función PostgreSQL.
 */
interface CitaParaRecordatorio {
  cita_id: string;
  empresa_id: string;
  // fecha_hora_inicio: ISO 8601 UTC (combinación de fecha + hora_inicio en zona del establecimiento)
  fecha_hora_inicio: string;
  nombre_servicio: string;
  duracion_minutos: number;
  cliente_id: string | null;
  cliente_nombre: string | null;
  cliente_whatsapp: string | null;
  cliente_email: string | null;
  especialista_id: string | null;
  especialista_nombre: string | null;
  nombre_salon: string;
  zona_horaria: string;
  // user_id del cliente en auth (para buscar device token)
  cliente_user_id: string | null;
  // user_id del especialista en auth (para buscar device token)
  especialista_user_id: string | null;
}

interface DeviceTokenRow {
  user_id: string;
  token: string;
  flavor: string;
}

interface BatchResult {
  procesadas: number;
  errores: number;
  push_enviados: number;
}

// ---------------------------------------------------------------------------
// Helpers de respuesta HTTP
// ---------------------------------------------------------------------------

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function errorResponse(status: number, code: string, message?: string): Response {
  return jsonResponse(status, { ok: false, error: code, message });
}

// ---------------------------------------------------------------------------
// FCM: importar RSA private key desde PEM (PKCS8)
// ---------------------------------------------------------------------------

async function importRSAPrivateKey(pemKey: string): Promise<CryptoKey> {
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
// FCM: codificar a base64url
// ---------------------------------------------------------------------------

function arrayBufferToBase64Url(buffer: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

function stringToBase64Url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

// ---------------------------------------------------------------------------
// FCM: Access token con soporte para renovación en batches largos
// ---------------------------------------------------------------------------

interface FcmTokenCache {
  access_token: string;
  obtained_at_ms: number;
}

/** Obtiene un access token FCM. El access token tiene vigencia de 1 hora. */
async function getFcmAccessToken(serviceAccountKeyJson: string): Promise<string> {
  const key = JSON.parse(serviceAccountKeyJson);
  const now = Math.floor(Date.now() / 1000);

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
// FCM: enviar push a un token
// Retorna: 'SUCCESS' | 'UNREGISTERED' | 'QUOTA_EXCEEDED' | 'ERROR'
// ---------------------------------------------------------------------------

type FcmSendStatus = 'SUCCESS' | 'UNREGISTERED' | 'QUOTA_EXCEEDED' | 'ERROR';

async function sendFcmDirect(
  fcmProjectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
  retryCount: number = 0,
): Promise<FcmSendStatus> {
  const url = `https://fcm.googleapis.com/v1/projects/${fcmProjectId}/messages:send`;

  const payload = {
    message: {
      token,
      notification: { title, body },
      data,
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
      body: JSON.stringify(payload),
    });

    if (response.ok) {
      return 'SUCCESS';
    }

    const errData = await response.json().catch(() => ({}));
    const errCode: string =
      errData?.error?.details?.[0]?.errorCode ?? errData?.error?.status ?? '';

    if (
      response.status === 404 ||
      errCode === 'UNREGISTERED' ||
      (response.status === 400 && errCode === 'INVALID_ARGUMENT')
    ) {
      return 'UNREGISTERED';
    }

    if (response.status === 429 || errCode === 'QUOTA_EXCEEDED') {
      console.warn(`[booking-reminders] FCM cuota excedida para proyecto ${fcmProjectId}`);
      return 'QUOTA_EXCEEDED';
    }

    if (response.status >= 500 && retryCount < 2) {
      await new Promise((r) => setTimeout(r, 1000));
      return sendFcmDirect(fcmProjectId, accessToken, token, title, body, data, retryCount + 1);
    }

    console.error(`[booking-reminders] FCM error ${response.status} ${errCode}`);
    return 'ERROR';
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.error(`[booking-reminders] Excepción FCM: ${errMsg}`);

    if (retryCount < 2) {
      await new Promise((r) => setTimeout(r, 1000));
      return sendFcmDirect(fcmProjectId, accessToken, token, title, body, data, retryCount + 1);
    }
    return 'ERROR';
  }
}

// ---------------------------------------------------------------------------
// Formatear fecha/hora para el mensaje de recordatorio (zona horaria local)
// ---------------------------------------------------------------------------

function formatFechaHora(isoUtc: string, zonaHoraria: string): { fecha: string; hora: string } {
  try {
    const dt = new Date(isoUtc);

    const fechaFmt = new Intl.DateTimeFormat('es-EC', {
      timeZone: zonaHoraria,
      weekday: 'long',
      day: 'numeric',
      month: 'long',
    }).format(dt);

    const horaFmt = new Intl.DateTimeFormat('es-EC', {
      timeZone: zonaHoraria,
      hour: '2-digit',
      minute: '2-digit',
      hour12: true,
    }).format(dt);

    return { fecha: fechaFmt, hora: horaFmt };
  } catch {
    // Fallback si la zona horaria no es válida
    return { fecha: isoUtc.split('T')[0], hora: isoUtc.split('T')[1]?.slice(0, 5) ?? '' };
  }
}

// ---------------------------------------------------------------------------
// Procesar una cita: enviar push al cliente y/o al especialista
// ---------------------------------------------------------------------------

async function procesarCita(
  cita: CitaParaRecordatorio,
  supabaseAdmin: SupabaseClient,
  fcmProjectId: string,
  tokenCache: FcmTokenCache | null,
  serviceAccountKey: string,
): Promise<{ push_enviados: number; token_cache: FcmTokenCache | null }> {
  let pushEnviados = 0;

  // Renovar access token si han pasado >50 minutos desde la última obtención
  const ahora = Date.now();
  const CINCUENTA_MINUTOS_MS = 50 * 60 * 1000;

  if (
    !tokenCache ||
    ahora - tokenCache.obtained_at_ms > CINCUENTA_MINUTOS_MS
  ) {
    try {
      const access_token = await getFcmAccessToken(serviceAccountKey);
      tokenCache = { access_token, obtained_at_ms: ahora };
      console.log('[booking-reminders] Access token FCM renovado');
    } catch (err) {
      console.error(
        '[booking-reminders] No se pudo obtener access token FCM:',
        err instanceof Error ? err.message : err,
      );
      // Sin token → no podemos enviar push, pero marcamos recordatorio igual
      return { push_enviados: 0, token_cache: null };
    }
  }

  const { fecha, hora } = formatFechaHora(
    cita.fecha_hora_inicio,
    cita.zona_horaria || 'America/Guayaquil',
  );

  const nombreCliente = cita.cliente_nombre ?? 'Cliente';
  const nombreSalon = cita.nombre_salon || 'el salón';

  // --- Notificar al CLIENTE (app "cliente") ---
  if (cita.cliente_user_id) {
    const { data: clienteTokens, error: tokenErr } = await supabaseAdmin
      .from('device_tokens')
      .select('token')
      .eq('user_id', cita.cliente_user_id)
      .eq('flavor', 'cliente')
      .eq('activo', true);

    if (tokenErr) {
      console.warn(
        `[booking-reminders] Error buscando tokens del cliente ${cita.cliente_user_id}: ${tokenErr.message}`,
      );
    } else if (clienteTokens && clienteTokens.length > 0) {
      const titulo = `Recordatorio de cita — ${nombreSalon}`;
      const mensajeBody =
        `Hola ${nombreCliente}, tu cita de ${cita.nombre_servicio}` +
        (cita.especialista_nombre ? ` con ${cita.especialista_nombre}` : '') +
        ` es el ${fecha} a las ${hora}.`;

      const datos: Record<string, string> = {
        tipo: 'recordatorio_cita',
        cita_id: cita.cita_id,
        ruta: `/citas/${cita.cita_id}`,
      };

      for (const row of clienteTokens as Array<{ token: string }>) {
        const status = await sendFcmDirect(
          fcmProjectId,
          tokenCache.access_token,
          row.token,
          titulo,
          mensajeBody,
          datos,
        );

        if (status === 'SUCCESS') {
          pushEnviados++;
        } else if (status === 'UNREGISTERED') {
          // Desactivar token inválido
          await supabaseAdmin
            .from('device_tokens')
            .update({ activo: false })
            .eq('token', row.token);
        }
      }
    }
  }

  // --- Notificar al ESPECIALISTA (app "salon") ---
  if (cita.especialista_user_id) {
    const { data: salonTokens, error: salonTokenErr } = await supabaseAdmin
      .from('device_tokens')
      .select('token')
      .eq('user_id', cita.especialista_user_id)
      .eq('flavor', 'salon')
      .eq('activo', true);

    if (salonTokenErr) {
      console.warn(
        `[booking-reminders] Error buscando tokens del especialista ${cita.especialista_user_id}: ${salonTokenErr.message}`,
      );
    } else if (salonTokens && salonTokens.length > 0) {
      const titulo = `Cita próxima — ${cita.nombre_servicio}`;
      const mensajeBody =
        `Tienes una cita con ${nombreCliente} el ${fecha} a las ${hora}` +
        ` (${cita.duracion_minutos} min).`;

      const datos: Record<string, string> = {
        tipo: 'recordatorio_cita_especialista',
        cita_id: cita.cita_id,
        ruta: `/agenda/${cita.cita_id}`,
      };

      for (const row of salonTokens as Array<{ token: string }>) {
        const status = await sendFcmDirect(
          fcmProjectId,
          tokenCache.access_token,
          row.token,
          titulo,
          mensajeBody,
          datos,
        );

        if (status === 'SUCCESS') {
          pushEnviados++;
        } else if (status === 'UNREGISTERED') {
          await supabaseAdmin
            .from('device_tokens')
            .update({ activo: false })
            .eq('token', row.token);
        }
      }
    }
  }

  return { push_enviados: pushEnviados, token_cache: tokenCache };
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  const startTime = Date.now();

  // 1. Verificar CRON_SECRET
  const cronSecret = Deno.env.get('CRON_SECRET');
  const authHeader = req.headers.get('Authorization') ?? '';
  const expectedAuth = `Bearer ${cronSecret}`;

  if (!cronSecret || authHeader !== expectedAuth) {
    console.warn('[booking-reminders] Acceso no autorizado — CRON_SECRET inválido');
    return errorResponse(401, 'UNAUTHORIZED', 'Token de autorización inválido');
  }

  // 2. Solo POST (pg_cron envía POST)
  if (req.method !== 'POST') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Solo se acepta POST');
  }

  // 3. Env vars FCM
  const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
  const fcmServiceAccountKey = Deno.env.get('FCM_SERVICE_ACCOUNT_KEY');

  if (!fcmProjectId || !fcmServiceAccountKey) {
    console.error('[booking-reminders] FCM_PROJECT_ID o FCM_SERVICE_ACCOUNT_KEY no configurados');
    return errorResponse(500, 'FCM_CONFIG_FALTANTE', 'Firebase no está configurado');
  }

  // 4. Supabase admin client (service_role — bypass RLS para batch global)
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabaseAdmin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

  // 5. Obtener citas que necesitan recordatorio via RPC
  console.log('[booking-reminders] Consultando citas para recordatorio...');

  let citas: CitaParaRecordatorio[];

  try {
    const { data, error } = await supabaseAdmin.rpc('get_citas_para_recordatorio', {
      p_horas_anticipacion: 24,
    });

    if (error) {
      console.error('[booking-reminders] Error al llamar get_citas_para_recordatorio:', error.message);
      return errorResponse(500, 'DB_ERROR', 'Error al consultar citas pendientes');
    }

    citas = Array.isArray(data) ? data : [];
  } catch (err) {
    console.error(
      '[booking-reminders] Excepción al consultar citas:',
      err instanceof Error ? err.message : err,
    );
    return errorResponse(500, 'INTERNAL_ERROR', 'Error consultando citas');
  }

  console.log(`[booking-reminders] ${citas.length} citas pendientes de recordatorio`);

  if (citas.length === 0) {
    return jsonResponse(200, {
      ok: true,
      procesadas: 0,
      errores: 0,
      push_enviados: 0,
      duration_ms: Date.now() - startTime,
    });
  }

  // 6. Procesar citas: enviar push + marcar recordatorio enviado
  const resultado: BatchResult = {
    procesadas: 0,
    errores: 0,
    push_enviados: 0,
  };

  // Cache del access token FCM (renovable si el batch dura >50 min)
  let tokenCache: FcmTokenCache | null = null;

  for (const cita of citas) {
    try {
      // 6a. Enviar push al cliente y/o especialista
      const { push_enviados, token_cache } = await procesarCita(
        cita,
        supabaseAdmin,
        fcmProjectId,
        tokenCache,
        fcmServiceAccountKey,
      );

      tokenCache = token_cache;
      resultado.push_enviados += push_enviados;

      // 6b. Marcar recordatorio como enviado (independiente de si el push fue exitoso)
      //     Si no hay tokens no significa error — la cita sigue marcada para no reintentar
      const { error: markError } = await supabaseAdmin.rpc('marcar_recordatorio_enviado', {
        p_cita_id: cita.cita_id,
      });

      if (markError) {
        console.error(
          `[booking-reminders] Error al marcar recordatorio para cita ${cita.cita_id}: ${markError.message}`,
        );
        resultado.errores++;
      } else {
        resultado.procesadas++;
      }
    } catch (err) {
      console.error(
        `[booking-reminders] Error procesando cita ${cita.cita_id}:`,
        err instanceof Error ? err.message : err,
      );
      resultado.errores++;
    }
  }

  const durationMs = Date.now() - startTime;

  console.log(
    `[booking-reminders] Finalizado: procesadas=${resultado.procesadas} errores=${resultado.errores} push=${resultado.push_enviados} duration=${durationMs}ms`,
  );

  return jsonResponse(200, {
    ok: true,
    procesadas: resultado.procesadas,
    errores: resultado.errores,
    push_enviados: resultado.push_enviados,
    duration_ms: durationMs,
  });
});
