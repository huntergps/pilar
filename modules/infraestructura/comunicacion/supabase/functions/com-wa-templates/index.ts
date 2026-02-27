/**
 * PILAR ERP — Edge Function: com-wa-templates
 *
 * Gestiona plantillas de WhatsApp Business (Message Templates):
 *   - sync:   sincroniza plantillas desde Meta → com_wa_plantillas
 *   - submit: envia nueva plantilla a Meta para aprobacion
 *   - update: actualiza plantilla existente en Meta
 *
 * Auth: verify_jwt: true (requiere JWT de usuario autenticado)
 *
 * Body: { action: 'sync' | 'submit' | 'update', cuenta_id: string, ...extra }
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../../../../../foundation/supabase/functions/_shared/cors.ts';
import {
  type WaAccount,
  waGetTemplates,
  waSubmitTemplate,
  waUpdateTemplate,
} from '../../../../../foundation/supabase/functions/_shared/whatsapp-api.ts';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface TemplateRequest {
  action: 'sync' | 'submit' | 'update';
  cuenta_id: string;
  plantilla_id?: string;
  changes?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// HTTP helpers
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
// Get account helper
// ---------------------------------------------------------------------------

async function getCuenta(supabase: ReturnType<typeof createClient>, cuentaId: string) {
  const { data, error } = await supabase
    .from('com_cuentas')
    .select('*')
    .eq('id', cuentaId)
    .eq('tipo', 'whatsapp')
    .eq('activo', true)
    .single();

  if (error || !data) throw new Error(`Cuenta no encontrada: ${cuentaId}`);
  return data;
}

/** Builds a WaAccount from the config_json stored in com_cuentas. */
function toWaAccount(cuenta: any): WaAccount {
  const cfg = cuenta.config_json ?? {};
  return {
    app_uid: cfg.app_uid ?? '',
    account_uid: cfg.account_uid ?? '',
    phone_uid: cfg.phone_uid ?? '',
    phone_number: cfg.phone_number ?? '',
    token: cfg.token ?? '',
    app_secret: cfg.app_secret ?? '',
    webhook_verify_token: cfg.webhook_verify_token ?? '',
  };
}

// ---------------------------------------------------------------------------
// Build Meta components array from plantilla record
// ---------------------------------------------------------------------------

function buildComponents(plantilla: any): object[] {
  const components: any[] = [];

  if (plantilla.header_tipo && plantilla.header_tipo !== 'none') {
    const header: any = {
      type: 'HEADER',
      format: plantilla.header_tipo.toUpperCase(),
    };
    if (plantilla.header_tipo === 'text' && plantilla.header_texto) {
      header.text = plantilla.header_texto;
    }
    components.push(header);
  }

  components.push({ type: 'BODY', text: plantilla.cuerpo });

  if (plantilla.footer_texto) {
    components.push({ type: 'FOOTER', text: plantilla.footer_texto });
  }

  const buttons = plantilla.botones_json ?? [];
  if (buttons.length > 0) {
    const btnList = buttons.map((btn: any) => {
      const b: any = {
        type: btn.type.toUpperCase(),
        text: btn.text,
      };
      if (btn.type === 'url') b.url = btn.url;
      if (btn.type === 'phone_number') b.phone_number = btn.call_number;
      return b;
    });
    components.push({ type: 'BUTTONS', buttons: btnList });
  }

  return components;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

async function handleSync(
  supabase: ReturnType<typeof createClient>,
  cuenta: any,
  acct: WaAccount,
): Promise<Response> {
  // Fetch all templates from Meta
  const metaTemplates = await waGetTemplates(acct, true);

  let synced = 0;
  let updated = 0;
  let created = 0;

  for (const tmpl of metaTemplates as any[]) {
    const bodyComponent = (tmpl.components ?? []).find((c: any) => c.type === 'BODY');

    const row = {
      cuenta_id: cuenta.id,
      empresa_id: cuenta.empresa_id,
      template_name: tmpl.name,
      wa_template_uid: String(tmpl.id),
      categoria: tmpl.category?.toLowerCase() ?? null,
      idioma: tmpl.language ?? 'es',
      estado: tmpl.status?.toLowerCase() ?? 'unknown',
      calidad: tmpl.quality_score ?? null,
      cuerpo: bodyComponent?.text ?? null,
      actualizado_en: new Date().toISOString(),
    };

    // Upsert: ON CONFLICT (cuenta_id, template_name)
    const { error, status } = await supabase
      .from('com_wa_plantillas')
      .upsert(row, { onConflict: 'cuenta_id,template_name' });

    if (error) {
      console.error(`[com-wa-templates] Upsert error for ${tmpl.name}:`, error.message);
    } else {
      synced++;
      // status 201 = created, 200 = updated
      if (status === 201) {
        created++;
      } else {
        updated++;
      }
    }
  }

  return jsonResponse(200, { ok: true, synced, updated, new: created });
}

async function handleSubmit(
  supabase: ReturnType<typeof createClient>,
  acct: WaAccount,
  plantillaId: string,
): Promise<Response> {
  // Read plantilla from DB
  const { data: plantilla, error: plantillaError } = await supabase
    .from('com_wa_plantillas')
    .select('*')
    .eq('id', plantillaId)
    .single();

  if (plantillaError || !plantilla) {
    return errorResponse(404, 'PLANTILLA_NO_ENCONTRADA', `Plantilla ${plantillaId} no existe`);
  }

  // Build Meta payload
  const metaPayload = {
    name: plantilla.template_name,
    category: (plantilla.categoria ?? 'MARKETING').toUpperCase(),
    language: plantilla.idioma ?? 'es',
    components: buildComponents(plantilla),
  };

  // Submit to Meta
  const waTemplateUid = await waSubmitTemplate(acct, metaPayload);

  // Update local record
  await supabase
    .from('com_wa_plantillas')
    .update({
      wa_template_uid: waTemplateUid,
      estado: 'pending',
      actualizado_en: new Date().toISOString(),
    })
    .eq('id', plantillaId);

  return jsonResponse(200, { ok: true, wa_template_uid: waTemplateUid, estado: 'pending' });
}

async function handleUpdate(
  supabase: ReturnType<typeof createClient>,
  acct: WaAccount,
  plantillaId: string,
  changes: Record<string, unknown>,
): Promise<Response> {
  // Read plantilla from DB
  const { data: plantilla, error: plantillaError } = await supabase
    .from('com_wa_plantillas')
    .select('*')
    .eq('id', plantillaId)
    .single();

  if (plantillaError || !plantilla) {
    return errorResponse(404, 'PLANTILLA_NO_ENCONTRADA', `Plantilla ${plantillaId} no existe`);
  }

  if (!plantilla.wa_template_uid) {
    return errorResponse(400, 'SIN_TEMPLATE_UID', 'La plantilla no tiene wa_template_uid (no fue enviada a Meta)');
  }

  // Update on Meta
  await waUpdateTemplate(acct, plantilla.wa_template_uid, changes);

  // Update local record with changes
  const updateData: Record<string, unknown> = {
    actualizado_en: new Date().toISOString(),
  };
  // Mirror known fields if provided
  if (changes.cuerpo !== undefined) updateData.cuerpo = changes.cuerpo;
  if (changes.header_texto !== undefined) updateData.header_texto = changes.header_texto;
  if (changes.footer_texto !== undefined) updateData.footer_texto = changes.footer_texto;

  await supabase
    .from('com_wa_plantillas')
    .update(updateData)
    .eq('id', plantillaId);

  return jsonResponse(200, { ok: true, updated: true });
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Solo se acepta POST');
  }

  // Parse body
  let body: TemplateRequest;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, 'BODY_INVALIDO', 'El cuerpo no es JSON valido');
  }

  const { action, cuenta_id, plantilla_id, changes } = body;

  if (!action || !cuenta_id) {
    return errorResponse(400, 'PARAMS_REQUERIDOS', 'Se requiere action y cuenta_id');
  }

  // Create clients
  // Use the user's JWT for auth context via anon key + Authorization header
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Admin client for DB operations (templates may be read/written by admins)
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  try {
    const cuenta = await getCuenta(supabase, cuenta_id);
    const acct = toWaAccount(cuenta);

    switch (action) {
      case 'sync':
        return await handleSync(supabase, cuenta, acct);

      case 'submit':
        if (!plantilla_id) {
          return errorResponse(400, 'PLANTILLA_ID_REQUERIDO', 'Se requiere plantilla_id para submit');
        }
        return await handleSubmit(supabase, acct, plantilla_id);

      case 'update':
        if (!plantilla_id) {
          return errorResponse(400, 'PLANTILLA_ID_REQUERIDO', 'Se requiere plantilla_id para update');
        }
        if (!changes || typeof changes !== 'object') {
          return errorResponse(400, 'CHANGES_REQUERIDOS', 'Se requiere changes para update');
        }
        return await handleUpdate(supabase, acct, plantilla_id, changes);

      default:
        return errorResponse(400, 'ACCION_INVALIDA', `Accion no soportada: ${action}`);
    }
  } catch (err) {
    console.error(
      '[com-wa-templates] Error:',
      err instanceof Error ? err.message : err,
    );
    return errorResponse(500, 'INTERNAL_ERROR', err instanceof Error ? err.message : 'Error interno');
  }
});
