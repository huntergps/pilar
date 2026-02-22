/**
 * PILAR ERP — Edge Function: ai-embed
 *
 * Genera y almacena embeddings semánticos para registros del ERP.
 * Los embeddings son vectores de 1536 dimensiones (text-embedding-3-small)
 * que permiten búsqueda semántica y contexto para el chat NLP.
 *
 * Método:  POST
 * Auth:    verify_jwt: true
 *
 * Body (modo individual):
 *   empresa_id   : UUID de la empresa
 *   tabla_origen : 'facturas' | 'contactos' | 'productos' | ... (ver TablaOrigen)
 *   registro_id  : UUID del registro en la tabla origen
 *   contenido?   : Texto a embeder. Si se omite, se construye desde metadata.
 *   metadata?    : Datos del registro para construir el texto (si no hay contenido)
 *
 * Body (modo batch):
 *   items: Array<{ empresa_id, tabla_origen, registro_id, contenido?, metadata? }>
 *
 * Respuesta (modo individual, 200):
 *   { success: true, embedding_id: string, tokens_used: number }
 *
 * Respuesta (modo batch, 200):
 *   { success: true, procesados: number, fallidos: number, resultados: EmbedResult[] }
 *
 * Errores posibles:
 *   405  METHOD_NOT_ALLOWED
 *   400  BODY_INVALIDO
 *   400  CAMPOS_REQUERIDOS
 *   401  UNAUTHORIZED
 *   500  OPENAI_ERROR
 *   500  DB_ERROR
 *   500  INTERNAL_ERROR
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import {
  generateEmbedding,
  prepareTextForEmbedding,
  truncateToTokens,
  TablaOrigen,
} from '../_shared/ai-helpers.ts';

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface EmbedItem {
  empresa_id: string;
  tabla_origen: TablaOrigen;
  registro_id: string;
  contenido?: string;
  metadata?: Record<string, unknown>;
}

interface EmbedResult {
  registro_id: string;
  tabla_origen: string;
  embedding_id?: string;
  tokens_used?: number;
  error?: string;
}

interface EmbedBatchBody {
  items: EmbedItem[];
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

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function isValidUuid(v: string): boolean {
  return UUID_REGEX.test(v);
}

// ---------------------------------------------------------------------------
// Procesamiento de un item individual
// ---------------------------------------------------------------------------

async function processItem(
  item: EmbedItem,
  apiKey: string,
  supabaseAdmin: SupabaseClient,
): Promise<EmbedResult> {
  const { empresa_id, tabla_origen, registro_id } = item;

  try {
    // 1. Construir texto a embeder
    let texto: string;
    if (item.contenido?.trim()) {
      texto = item.contenido.trim();
    } else if (item.metadata && Object.keys(item.metadata).length > 0) {
      texto = prepareTextForEmbedding(tabla_origen, item.metadata);
    } else {
      return {
        registro_id,
        tabla_origen,
        error: 'Se requiere contenido o metadata para generar el embedding',
      };
    }

    // 2. Truncar a límite seguro de tokens (8000)
    const textoTruncado = truncateToTokens(texto, 8000);

    // 3. Generar embedding vía OpenAI
    const { vector, model, tokens } = await generateEmbedding(textoTruncado, apiKey);

    // 4. Upsert en tabla embeddings (usar supabaseAdmin para escribir sin RLS)
    // El vector se envía como string en formato pgvector: '[n1,n2,...,n1536]'
    const vectorStr = `[${vector.join(',')}]`;

    const { data: upsertData, error: upsertError } = await supabaseAdmin.rpc(
      'upsert_embedding',
      {
        p_empresa_id: empresa_id,
        p_tabla_origen: tabla_origen,
        p_registro_id: registro_id,
        p_contenido: textoTruncado,
        p_vector: vectorStr,
        p_metadata: item.metadata ?? {},
        p_modelo: model,
      },
    );

    if (upsertError) {
      // Fallback: upsert directo si el RPC no existe aún
      const { data: directData, error: directError } = await supabaseAdmin
        .from('embeddings')
        .upsert(
          {
            empresa_id,
            tabla_origen,
            registro_id,
            contenido: textoTruncado,
            vector: vectorStr,
            metadata: item.metadata ?? {},
            modelo: model,
            updated_at: new Date().toISOString(),
          },
          {
            onConflict: 'empresa_id,tabla_origen,registro_id',
          },
        )
        .select('id')
        .single();

      if (directError) {
        console.error(`[ai-embed] DB upsert error para ${registro_id}:`, directError.message);
        return { registro_id, tabla_origen, error: `DB error: ${directError.message}` };
      }

      return {
        registro_id,
        tabla_origen,
        embedding_id: directData?.id as string | undefined,
        tokens_used: tokens,
      };
    }

    return {
      registro_id,
      tabla_origen,
      embedding_id: (upsertData as string) || undefined,
      tokens_used: tokens,
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[ai-embed] Error procesando ${registro_id}:`, msg);
    return { registro_id, tabla_origen, error: msg };
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
  let rawBody: Record<string, unknown>;
  try {
    rawBody = await req.json();
  } catch {
    return errorResponse(400, 'BODY_INVALIDO', 'El cuerpo de la solicitud no es JSON válido');
  }

  // 4. Obtener OPENAI_API_KEY
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  if (!apiKey) {
    console.error('[ai-embed] OPENAI_API_KEY no configurada');
    return errorResponse(500, 'OPENAI_ERROR', 'Configuración de OpenAI no disponible');
  }

  // 5. Crear clientes Supabase
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const authHeader = req.headers.get('Authorization') ?? '';

  // Cliente con JWT del usuario (para verificar auth)
  const supabaseClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // Cliente admin (service_role) para escrituras sin RLS
  const supabaseAdmin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

  // 6. Verificar autenticación
  const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
  if (!user || authError) {
    return errorResponse(401, 'UNAUTHORIZED', 'Se requiere autenticación válida');
  }

  try {
    // 7. Determinar modo: batch o individual
    if (Array.isArray(rawBody.items)) {
      // -----------------------------------------------------------------------
      // MODO BATCH
      // -----------------------------------------------------------------------
      const batchBody = rawBody as unknown as EmbedBatchBody;
      const items = batchBody.items;

      if (items.length === 0) {
        return errorResponse(400, 'CAMPOS_REQUERIDOS', 'El array items no puede estar vacío');
      }

      if (items.length > 100) {
        return errorResponse(400, 'BODY_INVALIDO', 'El modo batch acepta máximo 100 items por solicitud');
      }

      // Validar campos requeridos en todos los items antes de procesar
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (!item.empresa_id || !isValidUuid(item.empresa_id)) {
          return errorResponse(400, 'CAMPOS_REQUERIDOS', `items[${i}].empresa_id inválido`);
        }
        if (!item.tabla_origen) {
          return errorResponse(400, 'CAMPOS_REQUERIDOS', `items[${i}].tabla_origen es requerido`);
        }
        if (!item.registro_id || !isValidUuid(item.registro_id)) {
          return errorResponse(400, 'CAMPOS_REQUERIDOS', `items[${i}].registro_id inválido`);
        }
      }

      const resultados: EmbedResult[] = [];
      let procesados = 0;
      let fallidos = 0;

      for (const item of items) {
        const result = await processItem(item, apiKey, supabaseAdmin);
        resultados.push(result);

        if (result.error) {
          fallidos++;
        } else {
          procesados++;
        }

        // Rate limiting: 100ms entre llamadas a OpenAI para no exceder límites
        if (items.indexOf(item) < items.length - 1) {
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      }

      console.log(
        `[ai-embed] Batch completado: ${procesados} procesados, ${fallidos} fallidos de ${items.length}`,
      );

      return jsonResponse(200, {
        success: true,
        procesados,
        fallidos,
        resultados,
      });
    } else {
      // -----------------------------------------------------------------------
      // MODO INDIVIDUAL
      // -----------------------------------------------------------------------
      const item = rawBody as unknown as EmbedItem;

      // Validar campos requeridos
      if (!item.empresa_id || !isValidUuid(item.empresa_id)) {
        return errorResponse(400, 'CAMPOS_REQUERIDOS', 'empresa_id es requerido y debe ser un UUID válido');
      }
      if (!item.tabla_origen) {
        return errorResponse(400, 'CAMPOS_REQUERIDOS', 'tabla_origen es requerido');
      }
      if (!item.registro_id || !isValidUuid(item.registro_id)) {
        return errorResponse(400, 'CAMPOS_REQUERIDOS', 'registro_id es requerido y debe ser un UUID válido');
      }
      if (!item.contenido?.trim() && (!item.metadata || Object.keys(item.metadata).length === 0)) {
        return errorResponse(
          400,
          'CAMPOS_REQUERIDOS',
          'Se requiere al menos contenido o metadata para generar el embedding',
        );
      }

      const result = await processItem(item, apiKey, supabaseAdmin);

      if (result.error) {
        // Determinar si es error de OpenAI o de BD
        const code = result.error.startsWith('OpenAI') ? 'OPENAI_ERROR' : 'DB_ERROR';
        return errorResponse(500, code, result.error);
      }

      console.log(
        `[ai-embed] Embedding generado para ${item.tabla_origen}/${item.registro_id}: ` +
        `${result.tokens_used} tokens`,
      );

      return jsonResponse(200, {
        success: true,
        embedding_id: result.embedding_id,
        tokens_used: result.tokens_used,
      });
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[ai-embed] Error inesperado:', msg);
    return errorResponse(500, 'INTERNAL_ERROR', 'Error procesando la solicitud');
  }
});
