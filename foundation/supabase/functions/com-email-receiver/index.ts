/**
 * PILAR ERP — Edge Function: com-email-receiver
 *
 * Polling IMAP para todas las cuentas email_smtp activas con imap_host configurado.
 * Descarga mensajes no leídos y los almacena en com_mensajes (tipo=inbound).
 *
 * Invocado por pg_cron cada 5 minutos.
 *
 * Estrategia: UID-based (guarda el último UID procesado en com_cuentas.meta_json)
 * para no volver a descargar mensajes ya procesados.
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';
import { ImapFlow } from 'npm:imapflow@1';
import { simpleParser } from 'npm:mailparser@3';
import { corsHeaders, handleCors } from '../_shared/cors.ts';

const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MAX_PER_ACCOUNT  = 50; // máx mensajes por cuenta por ciclo

interface CuentaEmail {
  id: string;
  empresa_id: string;
  nombre: string;
  config_json: Record<string, unknown>;
  meta_json: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  const cors = handleCors(req);
  if (cors) return cors;

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Obtener todas las cuentas email_smtp activas con IMAP configurado
  const { data: cuentas, error } = await admin
    .from('com_cuentas')
    .select('id, empresa_id, nombre, config_json, meta_json')
    .eq('tipo', 'email_smtp')
    .eq('activo', true);

  if (error) {
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const rows = (cuentas ?? []) as CuentaEmail[];
  const cuentasConImap = rows.filter(c =>
    c.config_json?.imap_host && c.config_json?.imap_port
  );

  console.log(`[com-email-receiver] Procesando ${cuentasConImap.length} cuentas IMAP`);

  const resultados: Array<{ cuenta: string; recibidos: number; error?: string }> = [];

  for (const cuenta of cuentasConImap) {
    try {
      const recibidos = await procesarCuenta(admin, cuenta);
      resultados.push({ cuenta: cuenta.nombre, recibidos });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[com-email-receiver] Error en cuenta ${cuenta.nombre}: ${msg}`);
      resultados.push({ cuenta: cuenta.nombre, recibidos: 0, error: msg });
    }
  }

  return new Response(JSON.stringify({ ok: true, resultados }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});

// ---------------------------------------------------------------------------
// Procesar una cuenta IMAP
// ---------------------------------------------------------------------------

async function procesarCuenta(
  admin: ReturnType<typeof createClient>,
  cuenta: CuentaEmail,
): Promise<number> {
  const cfg = cuenta.config_json;
  const meta = cuenta.meta_json ?? {};
  const lastUid = (meta.imap_last_uid as number) ?? 0;

  const client = new ImapFlow({
    host:   cfg.imap_host as string,
    port:   (cfg.imap_port as number) ?? 993,
    secure: cfg.imap_ssl !== false,
    auth: {
      user: cfg.username as string,
      pass: cfg.password as string,
    },
    logger: false,
    tls: { rejectUnauthorized: false },
  });

  await client.connect();
  let recibidos = 0;
  let maxUid = lastUid;

  try {
    const lock = await client.getMailboxLock('INBOX');
    try {
      // Buscar mensajes con UID > lastUid (o todos si primera vez)
      const searchCriteria = lastUid > 0
        ? { uid: `${lastUid + 1}:*` }
        : { seen: false };

      const messages = client.fetch(searchCriteria, {
        uid: true,
        envelope: true,
        source: true,
      }, { uid: true });

      let count = 0;
      for await (const msg of messages) {
        if (count >= MAX_PER_ACCOUNT) break;
        count++;

        try {
          const uid = msg.uid as number;
          if (uid <= lastUid) continue;

          // Parsear el email completo
          const parsed = await simpleParser(msg.source as Buffer);

          const de = parsed.from?.value?.[0];
          const deEmail = de?.address ?? 'unknown@unknown.com';
          const deNombre = de?.name ?? deEmail;
          const asunto = parsed.subject ?? '(Sin asunto)';
          const cuerpo = parsed.html ?? parsed.text ?? '';
          const messageId = parsed.messageId ?? `uid-${uid}`;

          // Idempotencia: verificar si ya existe
          const { data: existe } = await admin
            .from('com_mensajes')
            .select('id')
            .eq('mensaje_uid', messageId)
            .eq('empresa_id', cuenta.empresa_id)
            .maybeSingle();

          if (existe) {
            if (uid > maxUid) maxUid = uid;
            continue;
          }

          // Upsert conversación
          const { data: convRow } = await admin
            .from('com_conversaciones')
            .upsert({
              empresa_id:         cuenta.empresa_id,
              cuenta_id:          cuenta.id,
              canal:              'email_smtp',
              destinatario_ref:   deEmail,
              destinatario_nombre: deNombre,
              ultimo_mensaje_en:  new Date().toISOString(),
              activa:             true,
            }, {
              onConflict: 'empresa_id,cuenta_id,destinatario_ref',
              ignoreDuplicates: false,
            })
            .select('id')
            .single();

          const convId = (convRow as { id: string } | null)?.id ?? null;

          // Insertar mensaje inbound
          await admin.from('com_mensajes').insert({
            empresa_id:          cuenta.empresa_id,
            cuenta_id:           cuenta.id,
            conversacion_id:     convId,
            tipo:                'inbound',
            canal:               'email_smtp',
            destinatario_ref:    deEmail,
            destinatario_nombre: deNombre,
            asunto,
            cuerpo,
            estado:              'recibido',
            mensaje_uid:         messageId,
          });

          if (uid > maxUid) maxUid = uid;
          recibidos++;
        } catch (msgErr) {
          console.warn(`[com-email-receiver] Error procesando mensaje:`,
            msgErr instanceof Error ? msgErr.message : msgErr);
        }
      }
    } finally {
      lock.release();
    }
  } finally {
    await client.logout();
  }

  // Actualizar último UID en meta_json de la cuenta
  if (maxUid > lastUid) {
    await admin.from('com_cuentas')
      .update({ meta_json: { ...meta, imap_last_uid: maxUid } })
      .eq('id', cuenta.id);
  }

  console.log(`[com-email-receiver] ${cuenta.nombre}: ${recibidos} nuevos`);
  return recibidos;
}
