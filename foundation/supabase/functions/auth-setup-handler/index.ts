/**
 * PILAR ERP — Edge Function: auth-setup-handler
 *
 * Crea el bucket privado de Storage cuando se registra una nueva empresa.
 *
 * NOTA: Con la introducción del custom_access_token_hook (019_auth_hook.sql),
 * esta función ya NO necesita actualizar app_metadata del JWT. El hook lo hace
 * automáticamente en cada generación de token. Esta función solo gestiona el
 * efecto de infraestructura que PL/pgSQL no puede hacer directamente:
 *   → Crear el bucket privado de Storage para la empresa (Storage Admin API).
 *
 * ---------------------------------------------------------------------------
 * CÓMO SE INVOCA
 * ---------------------------------------------------------------------------
 * Database Webhook sobre empresas INSERT (configurar en Supabase Dashboard):
 *   Database → Webhooks → Create webhook
 *   Table: public.empresas | Event: INSERT
 *   URL: https://<project-ref>.supabase.co/functions/v1/auth-setup-handler
 *   Headers:
 *     Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
 *     Content-Type: application/json
 *
 * El webhook envía el payload estándar de Supabase:
 *   {
 *     "type":       "INSERT",
 *     "table":      "empresas",
 *     "schema":     "public",
 *     "record":     { "id": "<empresa_id>", "nombre": "...", ... },
 *     "old_record": null
 *   }
 *
 * También acepta llamadas manuales para testing o reintentos:
 *   curl -X POST .../functions/v1/auth-setup-handler \
 *     -H 'Authorization: Bearer <SERVICE_ROLE_KEY>' \
 *     -H 'Content-Type: application/json' \
 *     -d '{"empresa_id": "<uuid>"}'
 *
 * Método:   POST
 * Auth:     Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
 *           (verify_jwt: false — la función valida el token internamente)
 *
 * Respuesta (siempre 200 para evitar retries no deseados del webhook):
 *   { ok: true,  empresa_id: string, step: string }
 *   { ok: false, error: string, message: string }
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, handleCors } from '../_shared/cors.ts';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

/** Límite de tamaño por archivo en el bucket privado de cada empresa */
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
 * Verifica que la llamada provenga del sistema (Bearer = SERVICE_ROLE_KEY).
 * Los Database Webhooks de Supabase incluyen este header automáticamente
 * si se configura en el Dashboard.
 */
function verificarOrigen(req: Request): boolean {
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  return token === serviceRoleKey && serviceRoleKey.length > 0;
}

/**
 * Extrae empresa_id del payload. Acepta dos formatos:
 *   1. Database Webhook de Supabase: { type, table, schema, record: { id } }
 *   2. Llamada manual para testing:  { empresa_id }
 */
function extraerEmpresaId(payload: Record<string, unknown>): string | null {
  // Formato Database Webhook
  if (payload.record && typeof payload.record === 'object') {
    const record = payload.record as Record<string, unknown>;
    if (typeof record.id === 'string') return record.id;
  }
  // Formato manual
  if (typeof payload.empresa_id === 'string') return payload.empresa_id;
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

  // 2. Verificar origen
  if (!verificarOrigen(req)) {
    console.warn('[auth-setup-handler] Llamada rechazada — token inválido');
    return jsonResponse({ ok: false, error: 'UNAUTHORIZED', message: 'Token inválido' }, 401);
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
      message: 'No se encontró empresa_id en el payload (record.id o empresa_id)',
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
    allowedMimeTypes: null, // Sin restricción global; cada módulo filtra en su función
  });

  if (bucketError) {
    // Bucket ya existe → idempotente, no es error real
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
    // Retornamos 200 para que el webhook no reintente indefinidamente errores
    // permanentes (ej: nombre de bucket inválido). Los errores transitorios
    // sí deberían reintentarse — en ese caso cambiar a status 5xx.
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
