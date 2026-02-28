/**
 * PILAR ERP — Edge Function: com-telegram-setup
 *
 * Registra (o actualiza) el webhook de un bot de Telegram contra la
 * cuenta guardada en com_cuentas.
 *
 * Llamar desde la app después de crear o editar una cuenta Telegram.
 * También válido para re-registrar manualmente si la URL cambia.
 *
 * Método: POST
 * Body:   { "account_id": "<UUID de com_cuentas>" }
 * Auth:   Bearer JWT del usuario (verify_jwt: true)
 *
 * Responde:
 *   200  { ok: true,  webhook_url: "...", description: "..." }
 *   4xx  { ok: false, error: "..." }
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  // ── 1. Parse body ─────────────────────────────────────────────────────────
  let body: { account_id?: string };
  try {
    body = await req.json();
  } catch {
    return Response.json({ ok: false, error: 'Invalid JSON' }, { status: 400 });
  }

  const { account_id } = body;
  if (!account_id) {
    return Response.json(
      { ok: false, error: 'account_id requerido en el cuerpo del request' },
      { status: 400 },
    );
  }

  // ── 2. Leer cuenta usando el JWT del usuario (respeta RLS) ────────────────
  const authHeader = req.headers.get('Authorization') ?? '';
  const authClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: cuenta, error: cuentaError } = await authClient
    .from('com_cuentas')
    .select('id, config_json, meta_json')
    .eq('id', account_id)
    .eq('tipo', 'telegram')
    .single();

  if (cuentaError || !cuenta) {
    return Response.json(
      { ok: false, error: `Cuenta no encontrada: ${cuentaError?.message ?? ''}` },
      { status: 404 },
    );
  }

  const cfg = (cuenta.config_json ?? {}) as {
    bot_token?: string;
    webhook_secret?: string;
    bot_username?: string;
  };

  if (!cfg.bot_token) {
    return Response.json(
      { ok: false, error: 'bot_token no configurado en la cuenta' },
      { status: 422 },
    );
  }

  // ── 3. Construir la URL del webhook ───────────────────────────────────────
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const webhookUrl =
    `${supabaseUrl}/functions/v1/com-telegram-webhook?account_id=${account_id}`;

  // ── 4. Llamar setWebhook en la Bot API de Telegram ────────────────────────
  const tgBody: Record<string, unknown> = {
    url: webhookUrl,
    allowed_updates: ['message', 'callback_query'],
    drop_pending_updates: false,
  };
  if (cfg.webhook_secret) {
    tgBody['secret_token'] = cfg.webhook_secret;
  }

  let tgResult: { ok: boolean; result?: boolean; description?: string };
  try {
    const tgRes = await fetch(
      `https://api.telegram.org/bot${cfg.bot_token}/setWebhook`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(tgBody),
      },
    );
    tgResult = (await tgRes.json()) as typeof tgResult;
  } catch (fetchErr) {
    return Response.json(
      { ok: false, error: `Error de red al contactar Telegram: ${fetchErr}` },
      { status: 503 },
    );
  }

  // ── 5. Actualizar meta_json con el resultado (admin client, bypass RLS) ───
  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const newMeta = {
    ...(cuenta.meta_json ?? {}),
    webhook_url: webhookUrl,
    webhook_registered_at: new Date().toISOString(),
    webhook_ok: tgResult.ok,
    webhook_description: tgResult.description ?? null,
  };

  await adminClient
    .from('com_cuentas')
    .update({ meta_json: newMeta })
    .eq('id', account_id);

  // ── 6. Responder ──────────────────────────────────────────────────────────
  if (!tgResult.ok) {
    console.error(
      `[com-telegram-setup] Telegram rechazó el webhook: ${tgResult.description}`,
    );
    return Response.json(
      {
        ok: false,
        error: tgResult.description ?? 'Telegram rechazó el registro del webhook',
        webhook_url: webhookUrl,
      },
      { status: 422 },
    );
  }

  console.info(
    `[com-telegram-setup] Webhook registrado: ${webhookUrl} — ${tgResult.description}`,
  );
  return Response.json({
    ok: true,
    webhook_url: webhookUrl,
    description: tgResult.description ?? 'Webhook was set',
  });
});
