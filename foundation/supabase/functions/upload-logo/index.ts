/**
 * PILAR ERP — Edge Function: upload-logo
 *
 * Sube el logo de una empresa a Supabase Storage (bucket 'logos', público)
 * y actualiza `configuracion_empresa` vía RPC `update_empresa_logo`.
 *
 * Método:  POST
 * Auth:    JWT requerido (verify_jwt: true en config de deploy)
 * Body:    multipart/form-data
 *   - file  : File  — imagen a subir (PNG / JPEG / WEBP / SVG)
 *   - tipo  : string — 'principal' | 'secundario' | 'login'  (default: 'principal')
 *
 * Respuesta exitosa (200):
 *   { ok: true, url: string, tipo: string, empresa_id: string }
 *
 * Errores posibles:
 *   405  METHOD_NOT_ALLOWED
 *   401  UNAUTHORIZED
 *   400  NO_EMPRESA_CONTEXT
 *   400  ARCHIVO_REQUERIDO
 *   400  TIPO_INVALIDO
 *   400  MIME_NO_PERMITIDO
 *   400  ARCHIVO_DEMASIADO_GRANDE
 *   403  FORBIDDEN
 *   500  STORAGE_ERROR
 *   500  DB_ERROR
 *   500  INTERNAL_ERROR
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, handleCors } from '../_shared/cors.ts';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const BUCKET = 'logos';
const MAX_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB

const TIPOS_LOGO = ['principal', 'secundario', 'login'] as const;
type TipoLogo = typeof TIPOS_LOGO[number];

const MIME_PERMITIDOS = [
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/svg+xml',
] as const;
type MimePermitido = typeof MIME_PERMITIDOS[number];

/** Mapeo MIME → extensión de archivo (siempre lowercase). */
const MIME_A_EXT: Record<MimePermitido, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/webp': 'webp',
  'image/svg+xml': 'svg',
};

// ---------------------------------------------------------------------------
// Helper: respuesta de error con CORS headers
// ---------------------------------------------------------------------------

function errorResponse(
  status: number,
  code: string,
  message?: string,
): Response {
  return new Response(
    JSON.stringify({ ok: false, error: code, message }),
    {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
}

// ---------------------------------------------------------------------------
// Helper: construye el path en Storage
// Resultado: logos/{empresaId}/logo_{tipo}.{ext}
// ---------------------------------------------------------------------------

function buildStoragePath(empresaId: string, tipo: TipoLogo, mimeType: MimePermitido): string {
  const ext = MIME_A_EXT[mimeType];
  return `${empresaId}/logo_${tipo}.${ext}`;
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

  try {
    // 3. Clientes Supabase
    //    - supabaseClient: actúa en nombre del usuario (JWT propagado) — para auth + RPC con RLS
    //    - supabaseAdmin:  service role — para Storage y RPC admin (update_empresa_logo)
    const supabaseClient: SupabaseClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      },
    );

    const supabaseAdmin: SupabaseClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // 4. Autenticación: obtener usuario desde JWT
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return errorResponse(401, 'UNAUTHORIZED', 'Token inválido o expirado');
    }

    // 5. Obtener empresa_id desde app_metadata del JWT
    const empresaId = user.app_metadata?.empresa_id as string | undefined;
    if (!empresaId) {
      return errorResponse(400, 'NO_EMPRESA_CONTEXT', 'El usuario no tiene empresa_id en app_metadata');
    }

    // 6. Verificar permiso vía RPC (respeta RLS del usuario autenticado)
    const { data: hasPerm, error: permError } = await supabaseClient.rpc(
      'check_permission',
      { p_permiso: 'administracion.empresa.editar' },
    );
    if (permError) {
      console.error('[upload-logo] Error al verificar permiso:', permError);
      return errorResponse(500, 'INTERNAL_ERROR', 'Error al verificar permisos');
    }
    if (!hasPerm) {
      return errorResponse(403, 'FORBIDDEN', 'No tiene permiso para editar la empresa');
    }

    // 7. Parsear FormData
    const formData = await req.formData();
    const file = formData.get('file') as File | null;
    const tipoRaw = (formData.get('tipo') as string | null) ?? 'principal';

    // 8. Validación: archivo requerido
    if (!file) {
      return errorResponse(400, 'ARCHIVO_REQUERIDO', 'El campo "file" es obligatorio');
    }

    // 9. Validación: tipo de logo
    if (!TIPOS_LOGO.includes(tipoRaw as TipoLogo)) {
      return errorResponse(
        400,
        'TIPO_INVALIDO',
        `El tipo debe ser uno de: ${TIPOS_LOGO.join(', ')}`,
      );
    }
    const tipo = tipoRaw as TipoLogo;

    // 10. Validación: MIME type
    if (!MIME_PERMITIDOS.includes(file.type as MimePermitido)) {
      return errorResponse(
        400,
        'MIME_NO_PERMITIDO',
        `Tipo de archivo no permitido: ${file.type}. Se aceptan: ${MIME_PERMITIDOS.join(', ')}`,
      );
    }
    const mimeType = file.type as MimePermitido;

    // 11. Validación: tamaño máximo (5 MB)
    if (file.size > MAX_SIZE_BYTES) {
      return errorResponse(
        400,
        'ARCHIVO_DEMASIADO_GRANDE',
        `El archivo supera el tamaño máximo de ${MAX_SIZE_BYTES / 1024 / 1024} MB`,
      );
    }

    // 12. Construir path en Storage: logos/{empresaId}/logo_{tipo}.{ext}
    const storagePath = buildStoragePath(empresaId, tipo, mimeType);

    // 13. Subir a Storage (upsert=true reemplaza si ya existe)
    const fileBuffer = await file.arrayBuffer();
    const { error: uploadError } = await supabaseAdmin.storage
      .from(BUCKET)
      .upload(storagePath, fileBuffer, {
        contentType: mimeType,
        upsert: true,       // Reemplaza el archivo si ya existe
        cacheControl: '3600', // Cache de 1 hora en CDN
      });

    if (uploadError) {
      console.error('[upload-logo] Error al subir a Storage:', uploadError);
      return errorResponse(500, 'STORAGE_ERROR', 'No se pudo subir el archivo');
    }

    // 14. Obtener URL pública del bucket (bucket 'logos' debe ser público en Supabase)
    const { data: { publicUrl } } = supabaseAdmin.storage
      .from(BUCKET)
      .getPublicUrl(storagePath);

    // 15. Actualizar BD vía RPC con service role (no sujeto a RLS en esta operación)
    const { error: rpcError } = await supabaseAdmin.rpc('update_empresa_logo', {
      p_empresa_id: empresaId,
      p_tipo: tipo,
      p_url: publicUrl,
    });

    if (rpcError) {
      console.error('[upload-logo] Error al actualizar BD:', rpcError);
      return errorResponse(500, 'DB_ERROR', 'No se pudo actualizar la configuración de la empresa');
    }

    // 16. Respuesta exitosa
    return new Response(
      JSON.stringify({
        ok: true,
        url: publicUrl,
        tipo,
        empresa_id: empresaId,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (err) {
    // Catch global: nunca exponer detalles internos al cliente
    console.error('[upload-logo] Error inesperado:', err);
    return errorResponse(500, 'INTERNAL_ERROR', 'Error procesando la solicitud');
  }
});
