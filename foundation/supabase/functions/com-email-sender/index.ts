/**
 * PILAR ERP — Edge Function: com-email-sender
 *
 * Procesa la cola de mensajes de email pendientes en com_mensajes.
 * Soporta email_smtp (nodemailer) y email_api (Resend/ElasticMail/SendGrid).
 *
 * Invocado por pg_cron cada 2 minutos vía HTTP interno.
 * También puede ser invocado manualmente desde Flutter para envío inmediato.
 *
 * Auth: service_role key (invocación interna por pg_cron)
 *       o JWT de usuario autenticado (test manual desde UI)
 *
 * Body (opcional): { empresa_id?: string, mensaje_id?: string }
 *   - Si se pasa mensaje_id: procesa solo ese mensaje
 *   - Si se pasa empresa_id: procesa solo mensajes de esa empresa
 *   - Sin parámetros: procesa todos los pendientes (máx 50)
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';
import nodemailer from 'npm:nodemailer@6';
import { corsHeaders, handleCors } from '../_shared/cors.ts';

const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MAX_BATCH         = 50;

interface MensajePendiente {
  id: string;
  empresa_id: string;
  cuenta_id: string;
  canal: string;
  destinatario_ref: string;
  destinatario_nombre: string | null;
  asunto: string | null;
  cuerpo: string | null;
  conversacion_id: string | null;
}

interface CuentaConfig {
  tipo: string;
  config_json: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  const cors = handleCors(req);
  if (cors) return cors;

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  let filtroMensajeId: string | undefined;
  let filtroEmpresaId: string | undefined;

  if (req.method === 'POST' && req.headers.get('content-type')?.includes('application/json')) {
    try {
      const body = await req.json();
      filtroMensajeId = body?.mensaje_id;
      filtroEmpresaId = body?.empresa_id;
    } catch { /* ignorar body vacío */ }
  }

  // Obtener mensajes pendientes
  let query = admin
    .from('com_mensajes')
    .select('id, empresa_id, cuenta_id, canal, destinatario_ref, destinatario_nombre, asunto, cuerpo, conversacion_id')
    .in('canal', ['email_smtp', 'email_api'])
    .eq('tipo', 'outbound')
    .eq('estado', 'pendiente')
    .or('proximo_reintento_en.is.null,proximo_reintento_en.lte.' + new Date().toISOString())
    .order('creado_en', { ascending: true })
    .limit(MAX_BATCH);

  if (filtroMensajeId) query = query.eq('id', filtroMensajeId);
  if (filtroEmpresaId) query = query.eq('empresa_id', filtroEmpresaId);

  const { data: mensajes, error: fetchError } = await query;
  if (fetchError) {
    console.error('[com-email-sender] Error fetching mensajes:', fetchError.message);
    return new Response(JSON.stringify({ ok: false, error: fetchError.message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const rows = (mensajes ?? []) as MensajePendiente[];
  console.log(`[com-email-sender] Procesando ${rows.length} mensajes`);

  const resultados: Array<{ id: string; estado: string; error?: string }> = [];

  for (const msg of rows) {
    // Marcar como encolado para evitar doble procesamiento
    await admin.from('com_mensajes').update({ estado: 'encolado' }).eq('id', msg.id);

    try {
      // Obtener config de la cuenta
      const { data: cuentaRow } = await admin
        .from('com_cuentas')
        .select('tipo, config_json')
        .eq('id', msg.cuenta_id)
        .single();

      if (!cuentaRow) throw new Error(`Cuenta ${msg.cuenta_id} no encontrada`);

      const cuenta = cuentaRow as CuentaConfig;
      const cfg = cuenta.config_json as Record<string, unknown>;

      let messageId: string;

      if (msg.canal === 'email_smtp') {
        messageId = await sendViaSmtp(cfg, msg);
      } else {
        // email_api → Resend / ElasticMail / SendGrid
        messageId = await sendViaApi(cfg, msg);
      }

      // Éxito
      await admin.from('com_mensajes').update({
        estado: 'enviado',
        mensaje_uid: messageId,
        enviado_en: new Date().toISOString(),
        reintentos: 0,
      }).eq('id', msg.id);

      // Actualizar ultimo_mensaje_en en la conversación
      if (msg.conversacion_id) {
        await admin.from('com_conversaciones')
          .update({ ultimo_mensaje_en: new Date().toISOString() })
          .eq('id', msg.conversacion_id);
      }

      resultados.push({ id: msg.id, estado: 'enviado' });
      console.log(`[com-email-sender] ✓ ${msg.id} → ${msg.destinatario_ref}`);
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      console.error(`[com-email-sender] ✗ ${msg.id}: ${errMsg}`);

      // Calcular próximo reintento (backoff exponencial: 5m, 15m, 1h, 4h, 24h)
      const reintentos = await getReintentos(admin, msg.id);
      const delays = [5, 15, 60, 240, 1440]; // minutos
      const delayMin = delays[Math.min(reintentos, delays.length - 1)];
      const proximo = new Date(Date.now() + delayMin * 60_000).toISOString();

      await admin.from('com_mensajes').update({
        estado: reintentos >= 4 ? 'fallido' : 'pendiente',
        razon_fallo: errMsg,
        reintentos: reintentos + 1,
        proximo_reintento_en: reintentos >= 4 ? null : proximo,
      }).eq('id', msg.id);

      resultados.push({ id: msg.id, estado: 'fallido', error: errMsg });
    }
  }

  return new Response(JSON.stringify({ ok: true, procesados: rows.length, resultados }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});

// ---------------------------------------------------------------------------
// SMTP via nodemailer
// ---------------------------------------------------------------------------

async function sendViaSmtp(cfg: Record<string, unknown>, msg: MensajePendiente): Promise<string> {
  const transport = nodemailer.createTransport({
    host:   cfg.host as string,
    port:   (cfg.port as number) ?? 587,
    secure: cfg.use_tls === false ? false : ((cfg.port as number) === 465),
    requireTLS: cfg.use_tls !== false,
    auth: {
      user: cfg.username as string,
      pass: cfg.password as string,
    },
    connectionTimeout: 15_000,
    greetingTimeout:   10_000,
    socketTimeout:     30_000,
  });

  const from = cfg.from_name
    ? `"${cfg.from_name}" <${cfg.from_email}>`
    : (cfg.from_email as string);

  const info = await transport.sendMail({
    from,
    to:      msg.destinatario_ref,
    subject: msg.asunto ?? '(Sin asunto)',
    html:    msg.cuerpo ?? '',
    text:    stripHtml(msg.cuerpo ?? ''),
  });

  transport.close();
  return info.messageId ?? 'sent';
}

// ---------------------------------------------------------------------------
// API (Resend / ElasticMail / SendGrid)
// ---------------------------------------------------------------------------

async function sendViaApi(cfg: Record<string, unknown>, msg: MensajePendiente): Promise<string> {
  const provider = (cfg.provider as string) ?? 'resend';
  const from = cfg.from_name
    ? `${cfg.from_name} <${cfg.from_email}>`
    : (cfg.from_email as string);

  if (provider === 'resend') {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${cfg.api_key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from, to: [msg.destinatario_ref],
        subject: msg.asunto ?? '(Sin asunto)',
        html: msg.cuerpo ?? '',
      }),
    });
    if (!res.ok) throw new Error(`Resend ${res.status}: ${await res.text()}`);
    const data: { id: string } = await res.json();
    return data.id;
  }

  if (provider === 'sendgrid') {
    const res = await fetch('https://api.sendgrid.com/v3/mail/send', {
      method: 'POST',
      headers: { Authorization: `Bearer ${cfg.api_key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: { email: cfg.from_email as string, name: cfg.from_name as string },
        personalizations: [{ to: [{ email: msg.destinatario_ref }] }],
        subject: msg.asunto ?? '(Sin asunto)',
        content: [{ type: 'text/html', value: msg.cuerpo ?? '' }],
      }),
    });
    if (!res.ok) throw new Error(`SendGrid ${res.status}: ${await res.text()}`);
    return res.headers.get('x-message-id') ?? 'sent';
  }

  throw new Error(`Proveedor no soportado: ${provider}`);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function getReintentos(admin: ReturnType<typeof createClient>, id: string): Promise<number> {
  const { data } = await admin
    .from('com_mensajes').select('reintentos').eq('id', id).single();
  return (data as { reintentos: number } | null)?.reintentos ?? 0;
}

function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
}
