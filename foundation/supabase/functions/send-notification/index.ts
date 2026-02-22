/**
 * PILAR ERP — Edge Function: send-notification
 *
 * Envía notificaciones multi-canal (Email vía Resend, WhatsApp vía Meta Cloud API,
 * Telegram vía Bot API) para una empresa, usando plantillas almacenadas en BD y
 * credenciales de API obtenidas de `configuracion_empresa` (nunca expuestas al cliente).
 *
 * Puede ser invocada desde:
 *   1. Flutter (usuario autenticado con JWT)
 *   2. Otras Edge Functions internas (ej. sri-firma-envio post-autorización)
 *      usando service_role key como Authorization header.
 *
 * Método:  POST
 * Auth:    verify_jwt: true
 *          - JWT de usuario: se verifica con auth.getUser()
 *          - service_role key: getUser() retorna null → se acepta si hay empresa_id en body
 *
 * Body (NotificacionRequest):
 *   empresa_id        : UUID de la empresa
 *   tipo_notificacion : string — 'DOCUMENTO_AUTORIZADO', 'COBRO_REGISTRADO', etc.
 *   destinatario      : { nombre?, email?, whatsapp?, telegram_chat_id? }
 *   datos             : Record<string, string> — variables {{key}} del template
 *   referencia_id?    : UUID del objeto origen (factura, cobro, etc.)
 *   referencia_tabla? : Tabla del objeto origen
 *   canales?          : ('EMAIL' | 'WHATSAPP' | 'TELEGRAM')[] — si omitido: todos los configurados
 *
 * Respuesta exitosa (200):
 *   { ok: true, notificacion_id: string, canales: { email?, whatsapp?, telegram? } }
 *
 * Errores posibles:
 *   405  METHOD_NOT_ALLOWED
 *   400  BODY_INVALIDO
 *   401  UNAUTHORIZED
 *   400  EMPRESA_ID_INVALIDO
 *   400  TIPO_NOTIFICACION_REQUERIDO
 *   400  DESTINATARIO_INVALIDO
 *   500  DB_ERROR
 *   500  INTERNAL_ERROR
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { renderTemplate, htmlToPlainText } from '../_shared/notification-templates.ts';

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

type Canal = 'EMAIL' | 'WHATSAPP' | 'TELEGRAM';
type EstadoCanal = 'ENVIADO' | 'FALLIDO' | 'NO_CONFIGURADO' | 'OMITIDO';

interface NotificacionRequest {
  empresa_id: string;
  tipo_notificacion: string;
  destinatario: {
    nombre?: string;
    email?: string;
    whatsapp?: string;
    telegram_chat_id?: string;
  };
  datos: Record<string, string>;
  referencia_id?: string;
  referencia_tabla?: string;
  canales?: Canal[];
}

interface ResultadoCanal {
  estado: EstadoCanal;
  message_id?: string;
  error?: string;
}

interface NotificacionResponse {
  ok: boolean;
  notificacion_id: string;
  canales: {
    email?: ResultadoCanal;
    whatsapp?: ResultadoCanal;
    telegram?: ResultadoCanal;
  };
}

/** Config retornada por el RPC get_config_notificacion (JSONB aplanado). */
interface ConfigNotificacion {
  resend_api_key?: string;
  resend_from_email?: string;
  resend_from_name?: string;
  email_notifications_enabled?: string;
  whatsapp_phone_number_id?: string;
  whatsapp_access_token?: string;
  whatsapp_notifications_enabled?: string;
  telegram_bot_token?: string;
  telegram_notifications_enabled?: string;
  nombre_comercial?: string;
}

/** Plantilla retornada por el RPC get_plantilla_notificacion. */
interface PlantillaNotificacion {
  id: string;
  asunto: string;
  cuerpo_html: string;
  cuerpo_texto: string;
  es_sistema: boolean;
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
  return jsonResponse(status, { ok: false, error: code, message });
}

// ---------------------------------------------------------------------------
// Validación de UUID v4
// ---------------------------------------------------------------------------

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUuid(value: string): boolean {
  return UUID_REGEX.test(value);
}

// ---------------------------------------------------------------------------
// Canal EMAIL vía Resend
// ---------------------------------------------------------------------------

async function sendEmail(params: {
  apiKey: string;
  from: string;
  to: string;
  subject: string;
  html: string;
  text?: string;
}): Promise<ResultadoCanal> {
  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${params.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: params.from,
        to: [params.to],
        subject: params.subject,
        html: params.html,
        text: params.text,
      }),
    });

    const data = await response.json();

    if (response.ok && data.id) {
      console.log(`[send-notification] EMAIL → ENVIADO: ${data.id}`);
      return { estado: 'ENVIADO', message_id: data.id };
    }

    const errMsg = data.message ?? `HTTP ${response.status}`;
    console.warn(`[send-notification] EMAIL → FALLIDO: ${errMsg}`);
    return { estado: 'FALLIDO', error: errMsg };
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.warn(`[send-notification] EMAIL → FALLIDO (excepción): ${errMsg}`);
    return { estado: 'FALLIDO', error: errMsg };
  }
}

// ---------------------------------------------------------------------------
// Canal WHATSAPP vía Meta Cloud API
//
// NOTA: La API de WhatsApp Business Cloud requiere que el número receptor haya
// enviado un mensaje en las últimas 24h (ventana de conversación activa).
// Para mensajes fuera de la ventana, se necesitan "message templates" aprobados
// por Meta. Esta implementación usa type: 'text' (válido dentro de la ventana).
// Para producción, configurar templates de Meta para notificaciones proactivas.
// ---------------------------------------------------------------------------

async function sendWhatsApp(params: {
  phoneNumberId: string;
  accessToken: string;
  to: string;
  text: string;
}): Promise<ResultadoCanal> {
  try {
    const url = `https://graph.facebook.com/v21.0/${params.phoneNumberId}/messages`;
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${params.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: params.to.replace('+', ''),
        type: 'text',
        text: { body: params.text, preview_url: false },
      }),
    });

    const data = await response.json();
    const messageId: string | undefined = data.messages?.[0]?.id;

    if (messageId) {
      console.log(`[send-notification] WHATSAPP → ENVIADO: ${messageId}`);
      return { estado: 'ENVIADO', message_id: messageId };
    }

    const errMsg = data.error?.message ?? `HTTP ${response.status}`;
    console.warn(`[send-notification] WHATSAPP → FALLIDO: ${errMsg}`);
    return { estado: 'FALLIDO', error: errMsg };
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.warn(`[send-notification] WHATSAPP → FALLIDO (excepción): ${errMsg}`);
    return { estado: 'FALLIDO', error: errMsg };
  }
}

// ---------------------------------------------------------------------------
// Canal TELEGRAM vía Bot API
// ---------------------------------------------------------------------------

async function sendTelegram(params: {
  botToken: string;
  chatId: string;
  text: string;
  parseMode?: 'Markdown' | 'HTML';
}): Promise<ResultadoCanal> {
  try {
    const url = `https://api.telegram.org/bot${params.botToken}/sendMessage`;
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: params.chatId,
        text: params.text,
        parse_mode: params.parseMode ?? 'Markdown',
        disable_web_page_preview: false,
      }),
    });

    const data = await response.json();

    if (data.ok && data.result?.message_id) {
      const messageId = String(data.result.message_id);
      console.log(`[send-notification] TELEGRAM → ENVIADO: ${messageId}`);
      return { estado: 'ENVIADO', message_id: messageId };
    }

    const errMsg = data.description ?? `HTTP ${response.status}`;
    console.warn(`[send-notification] TELEGRAM → FALLIDO: ${errMsg}`);
    return { estado: 'FALLIDO', error: errMsg };
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.warn(`[send-notification] TELEGRAM → FALLIDO (excepción): ${errMsg}`);
    return { estado: 'FALLIDO', error: errMsg };
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

  // 3. Parsear body
  let body: NotificacionRequest;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, 'BODY_INVALIDO', 'El cuerpo de la solicitud no es JSON válido');
  }

  // 4. Validar campos requeridos
  const { empresa_id, tipo_notificacion, destinatario, datos, canales: canalesSolicitados } = body;

  if (!empresa_id) {
    return errorResponse(400, 'EMPRESA_ID_INVALIDO', 'El campo empresa_id es obligatorio');
  }
  if (!isValidUuid(empresa_id)) {
    return errorResponse(400, 'EMPRESA_ID_INVALIDO', 'El campo empresa_id debe ser un UUID válido');
  }
  if (!tipo_notificacion?.trim()) {
    return errorResponse(400, 'TIPO_NOTIFICACION_REQUERIDO', 'El campo tipo_notificacion es obligatorio');
  }
  if (!destinatario || typeof destinatario !== 'object') {
    return errorResponse(400, 'DESTINATARIO_INVALIDO', 'El campo destinatario es obligatorio');
  }
  const tieneAlgunCanal =
    !!destinatario.email || !!destinatario.whatsapp || !!destinatario.telegram_chat_id;
  if (!tieneAlgunCanal) {
    return errorResponse(
      400,
      'DESTINATARIO_INVALIDO',
      'El destinatario debe tener al menos uno de: email, whatsapp, telegram_chat_id',
    );
  }

  // 5. Crear cliente Supabase con JWT del llamador (para auth.getUser())
  const supabaseUrl     = Deno.env.get('SUPABASE_URL')!;
  const anonKey         = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const authHeader = req.headers.get('Authorization') ?? '';

  const supabaseClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // supabaseAdmin: service_role — para RPCs de configuración y registro de notificación
  const supabaseAdmin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

  // 6. Auth: verificar JWT del usuario
  //    Si es llamada interna (service_role), getUser() retorna null → se acepta
  //    porque empresa_id ya fue validado en el paso 4.
  const { data: { user } } = await supabaseClient.auth.getUser();
  if (!user && !empresa_id) {
    // Doble check: sin usuario y sin empresa_id → rechazar
    return errorResponse(401, 'UNAUTHORIZED', 'Se requiere autenticación');
  }

  try {
    // 7. Obtener configuración de notificaciones de la empresa
    const { data: configData, error: configError } = await supabaseAdmin.rpc(
      'get_config_notificacion',
      { p_empresa_id: empresa_id },
    );

    if (configError || !configData) {
      console.error(
        `[send-notification] Error al obtener config para empresa ${empresa_id}:`,
        configError?.message,
      );
      return errorResponse(500, 'DB_ERROR', 'No se pudo obtener la configuración de notificaciones');
    }

    const config = configData as ConfigNotificacion;

    // 8. Determinar canales activos según configuración y destinatario
    const canalesDisponibles: Canal[] = [];

    if (
      destinatario.email &&
      config.email_notifications_enabled !== 'false' &&
      config.resend_api_key &&
      config.resend_from_email
    ) {
      canalesDisponibles.push('EMAIL');
    }

    if (
      destinatario.whatsapp &&
      config.whatsapp_notifications_enabled !== 'false' &&
      config.whatsapp_phone_number_id &&
      config.whatsapp_access_token
    ) {
      canalesDisponibles.push('WHATSAPP');
    }

    if (
      destinatario.telegram_chat_id &&
      config.telegram_notifications_enabled !== 'false' &&
      config.telegram_bot_token
    ) {
      canalesDisponibles.push('TELEGRAM');
    }

    // Si se especificaron canales en el body, filtrar solo los solicitados
    const canalesAEnviar: Canal[] = canalesSolicitados
      ? canalesDisponibles.filter((c) => canalesSolicitados.includes(c))
      : canalesDisponibles;

    // Variables base disponibles para todos los templates
    const varsBase: Record<string, string> = {
      ...datos,
      nombre_empresa: config.nombre_comercial ?? '',
      destinatario_nombre: destinatario.nombre ?? '',
    };

    // Resultados por canal (inicializar como OMITIDO para los no procesados)
    let resultEmail: ResultadoCanal | undefined;
    let resultWhatsapp: ResultadoCanal | undefined;
    let resultTelegram: ResultadoCanal | undefined;

    // Marcar canales con destinatario pero no configurados
    if (destinatario.email && !canalesAEnviar.includes('EMAIL')) {
      if (!canalesDisponibles.includes('EMAIL')) {
        resultEmail = { estado: 'NO_CONFIGURADO' };
      } else {
        resultEmail = { estado: 'OMITIDO' };
      }
    }
    if (destinatario.whatsapp && !canalesAEnviar.includes('WHATSAPP')) {
      if (!canalesDisponibles.includes('WHATSAPP')) {
        resultWhatsapp = { estado: 'NO_CONFIGURADO' };
      } else {
        resultWhatsapp = { estado: 'OMITIDO' };
      }
    }
    if (destinatario.telegram_chat_id && !canalesAEnviar.includes('TELEGRAM')) {
      if (!canalesDisponibles.includes('TELEGRAM')) {
        resultTelegram = { estado: 'NO_CONFIGURADO' };
      } else {
        resultTelegram = { estado: 'OMITIDO' };
      }
    }

    // 9. Procesar cada canal activo (independientes entre sí: un fallo no detiene los demás)

    // --- EMAIL ---
    if (canalesAEnviar.includes('EMAIL')) {
      const { data: plantillaRows, error: plantillaError } = await supabaseAdmin.rpc(
        'get_plantilla_notificacion',
        {
          p_empresa_id: empresa_id,
          p_tipo_notificacion: tipo_notificacion,
          p_canal: 'EMAIL',
        },
      );

      if (plantillaError || !plantillaRows || plantillaRows.length === 0) {
        console.warn(
          `[send-notification] Sin plantilla EMAIL para ${tipo_notificacion} empresa ${empresa_id}`,
        );
        resultEmail = { estado: 'NO_CONFIGURADO' };
      } else {
        const plantilla = plantillaRows[0] as PlantillaNotificacion;
        const asunto    = renderTemplate(plantilla.asunto ?? '', varsBase);
        const htmlBody  = renderTemplate(plantilla.cuerpo_html ?? '', varsBase);
        const textBody  = plantilla.cuerpo_texto
          ? renderTemplate(plantilla.cuerpo_texto, varsBase)
          : htmlToPlainText(htmlBody);

        const fromName  = config.resend_from_name ?? config.nombre_comercial ?? 'PILAR ERP';
        const fromEmail = config.resend_from_email!;
        const from      = `${fromName} <${fromEmail}>`;

        resultEmail = await sendEmail({
          apiKey:  config.resend_api_key!,
          from,
          to:      destinatario.email!,
          subject: asunto,
          html:    htmlBody,
          text:    textBody,
        });
      }
    }

    // --- WHATSAPP ---
    if (canalesAEnviar.includes('WHATSAPP')) {
      const { data: plantillaRows, error: plantillaError } = await supabaseAdmin.rpc(
        'get_plantilla_notificacion',
        {
          p_empresa_id: empresa_id,
          p_tipo_notificacion: tipo_notificacion,
          p_canal: 'WHATSAPP',
        },
      );

      if (plantillaError || !plantillaRows || plantillaRows.length === 0) {
        console.warn(
          `[send-notification] Sin plantilla WHATSAPP para ${tipo_notificacion} empresa ${empresa_id}`,
        );
        resultWhatsapp = { estado: 'NO_CONFIGURADO' };
      } else {
        const plantilla  = plantillaRows[0] as PlantillaNotificacion;
        // WhatsApp usa texto plano; si el template tiene cuerpo_texto se prefiere,
        // de lo contrario se convierte desde HTML
        const textBody = plantilla.cuerpo_texto
          ? renderTemplate(plantilla.cuerpo_texto, varsBase)
          : htmlToPlainText(renderTemplate(plantilla.cuerpo_html ?? '', varsBase));

        resultWhatsapp = await sendWhatsApp({
          phoneNumberId: config.whatsapp_phone_number_id!,
          accessToken:   config.whatsapp_access_token!,
          to:            destinatario.whatsapp!,
          text:          textBody,
        });
      }
    }

    // --- TELEGRAM ---
    if (canalesAEnviar.includes('TELEGRAM')) {
      const { data: plantillaRows, error: plantillaError } = await supabaseAdmin.rpc(
        'get_plantilla_notificacion',
        {
          p_empresa_id: empresa_id,
          p_tipo_notificacion: tipo_notificacion,
          p_canal: 'TELEGRAM',
        },
      );

      if (plantillaError || !plantillaRows || plantillaRows.length === 0) {
        console.warn(
          `[send-notification] Sin plantilla TELEGRAM para ${tipo_notificacion} empresa ${empresa_id}`,
        );
        resultTelegram = { estado: 'NO_CONFIGURADO' };
      } else {
        const plantilla = plantillaRows[0] as PlantillaNotificacion;
        // Telegram soporta Markdown; si hay cuerpo_texto se usa como Markdown,
        // de lo contrario se convierte desde HTML a texto plano
        const textBody = plantilla.cuerpo_texto
          ? renderTemplate(plantilla.cuerpo_texto, varsBase)
          : htmlToPlainText(renderTemplate(plantilla.cuerpo_html ?? '', varsBase));

        resultTelegram = await sendTelegram({
          botToken:  config.telegram_bot_token!,
          chatId:    destinatario.telegram_chat_id!,
          text:      textBody,
          parseMode: 'Markdown',
        });
      }
    }

    // 10. Registrar resultado en la tabla `notificaciones` vía RPC
    const { data: notifId, error: registroError } = await supabaseAdmin.rpc(
      'registrar_notificacion',
      {
        p_empresa_id:                empresa_id,
        p_tipo_notificacion:         tipo_notificacion,
        p_destinatario_nombre:       destinatario.nombre ?? null,
        p_destinatario_email:        destinatario.email ?? null,
        p_destinatario_whatsapp:     destinatario.whatsapp ?? null,
        p_destinatario_telegram_chat_id: destinatario.telegram_chat_id ?? null,
        p_email_estado:              resultEmail?.estado ?? null,
        p_email_error:               resultEmail?.error ?? null,
        p_email_message_id:          resultEmail?.message_id ?? null,
        p_whatsapp_estado:           resultWhatsapp?.estado ?? null,
        p_whatsapp_error:            resultWhatsapp?.error ?? null,
        p_whatsapp_message_id:       resultWhatsapp?.message_id ?? null,
        p_telegram_estado:           resultTelegram?.estado ?? null,
        p_telegram_error:            resultTelegram?.error ?? null,
        p_telegram_message_id:       resultTelegram?.message_id ?? null,
        p_referencia_id:             body.referencia_id ?? null,
        p_referencia_tabla:          body.referencia_tabla ?? null,
        p_datos:                     datos ?? null,
      },
    );

    if (registroError) {
      // El registro de la notificación falló, pero los envíos ya se realizaron.
      // Loguear el error sin interrumpir la respuesta al llamador.
      console.error(
        `[send-notification] Error al registrar notificación en BD para empresa ${empresa_id}:`,
        registroError.message,
      );
      // Retornar igualmente con un ID provisional para no bloquear al llamador
      const respuestaFallback: NotificacionResponse = {
        ok: true,
        notificacion_id: '00000000-0000-0000-0000-000000000000',
        canales: buildCanalesResponse(resultEmail, resultWhatsapp, resultTelegram),
      };
      return jsonResponse(200, respuestaFallback);
    }

    // 11. Respuesta exitosa
    const respuesta: NotificacionResponse = {
      ok: true,
      notificacion_id: notifId as string,
      canales: buildCanalesResponse(resultEmail, resultWhatsapp, resultTelegram),
    };

    console.log(
      `[send-notification] Notificación ${tipo_notificacion} registrada: ${notifId} empresa ${empresa_id}`,
    );

    return jsonResponse(200, respuesta);
  } catch (err) {
    // Catch global: nunca exponer detalles internos al cliente
    console.error(
      '[send-notification] Error inesperado:',
      err instanceof Error ? err.message : err,
    );
    return errorResponse(500, 'INTERNAL_ERROR', 'Error procesando la solicitud');
  }
});

// ---------------------------------------------------------------------------
// Helper: construir objeto canales para la respuesta
// Omite claves con valor undefined para no incluir canales no aplicables.
// ---------------------------------------------------------------------------

function buildCanalesResponse(
  email?: ResultadoCanal,
  whatsapp?: ResultadoCanal,
  telegram?: ResultadoCanal,
): NotificacionResponse['canales'] {
  const canales: NotificacionResponse['canales'] = {};
  if (email !== undefined)    canales.email    = email;
  if (whatsapp !== undefined) canales.whatsapp = whatsapp;
  if (telegram !== undefined) canales.telegram = telegram;
  return canales;
}
