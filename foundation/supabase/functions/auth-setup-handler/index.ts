/**
 * PILAR ERP — Edge Function: auth-setup-handler
 *
 * Crea el bucket privado de Storage cuando se registra una nueva empresa.
 *
 * Invocada por:
 *   1. Trigger pg_net (migración 025): AFTER INSERT ON empresas
 *   2. GitHub Actions catch-up step
 *   3. Llamada manual para testing/reintentos
 *
 * Auth: verify_jwt = true — Supabase valida el JWT.
 *       La función verifica además que role == 'service_role'.
 *
 * Payload acepta dos formatos:
 *   Trigger pg_net / manual: { empresa_id: "<uuid>" }
 *   Database Webhook legacy: { type, table, schema, record: { id } }
 *
 * Respuesta (siempre 200 para evitar retries innecesarios):
 *   { ok: true,  empresa_id: string, step: string }
 *   { ok: false, error: string, message: string }
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, handleCors } from '../_shared/cors.ts';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const BUCKET_FILE_SIZE_LIMIT = 50 * 1024 * 1024; // 50 MB

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/**
 * Verifica que la llamada provenga de un service_role.
 * Con verify_jwt = true, Supabase ya validó la firma del JWT.
 * Aquí solo verificamos que el rol en el payload sea 'service_role'.
 */
function verificarOrigen(req: Request): boolean {
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return false;

  try {
    // Decodificar payload del JWT (sin reverificar firma — Supabase ya lo hizo)
    const parts = token.split('.');
    if (parts.length !== 3) return false;
    // Padding Base64URL → Base64 standard
    const padded = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(atob(padded));
    return payload.role === 'service_role';
  } catch {
    return false;
  }
}

/**
 * Extrae empresa_id del payload.
 *   Manual/pg_net:      { empresa_id: "<uuid>" }
 *   Database Webhook:   { record: { id: "<uuid>", ... } }
 */
function extraerEmpresaId(payload: Record<string, unknown>): string | null {
  if (typeof payload.empresa_id === 'string') return payload.empresa_id;
  if (payload.record && typeof payload.record === 'object') {
    const record = payload.record as Record<string, unknown>;
    if (typeof record.id === 'string') return record.id;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // 1. CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, error: 'METHOD_NOT_ALLOWED' }, 405);
  }

  // 2. Verificar que el llamador tiene rol service_role
  if (!verificarOrigen(req)) {
    console.warn('[auth-setup-handler] Llamada rechazada — se requiere service_role JWT');
    return jsonResponse({
      ok: false,
      error: 'UNAUTHORIZED',
      message: 'Se requiere service_role JWT',
    }, 401);
  }

  // 3. Parsear payload
  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ ok: false, error: 'INVALID_JSON', message: 'Body debe ser JSON' });
  }

  const empresaId = extraerEmpresaId(payload);
  if (!empresaId) {
    return jsonResponse({
      ok: false,
      error: 'EMPRESA_ID_REQUERIDO',
      message: 'No se encontró empresa_id en el payload',
    });
  }

  // 4. Crear bucket privado de Storage para la empresa
  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const { error: bucketError } = await adminClient.storage.createBucket(empresaId, {
    public: false,
    fileSizeLimit: BUCKET_FILE_SIZE_LIMIT,
    allowedMimeTypes: null,
  });

  if (bucketError) {
    const yaExiste =
      bucketError.message?.toLowerCase().includes('already exists') ||
      bucketError.message?.toLowerCase().includes('duplicate');

    if (yaExiste) {
      console.warn(`[auth-setup-handler] Bucket ${empresaId} ya existía (idempotente)`);
      return jsonResponse({
        ok: true,
        empresa_id: empresaId,
        step: 'bucket ya existía (idempotente)',
      });
    }

    console.error(`[auth-setup-handler] Error al crear bucket ${empresaId}:`, bucketError);
    return jsonResponse({
      ok: false,
      error: 'BUCKET_CREATE_ERROR',
      message: bucketError.message,
      empresa_id: empresaId,
    });
  }

  console.log(`[auth-setup-handler] Bucket creado: ${empresaId}`);

  return jsonResponse({
    ok: true,
    empresa_id: empresaId,
    step: 'bucket de Storage creado',
  });
});
