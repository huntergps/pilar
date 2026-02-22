/**
 * PILAR ERP — Edge Function: ai-query
 *
 * Chat NLP para el ERP: el usuario hace preguntas en lenguaje natural sobre
 * sus datos y el sistema responde con contexto semántico obtenido de embeddings.
 *
 * Flujo RAG (Retrieval-Augmented Generation):
 *   1. Generar embedding de la pregunta del usuario
 *   2. Buscar los K registros semánticamente más similares en la tabla embeddings
 *   3. Construir prompt con el contexto recuperado
 *   4. Llamar a GPT para generar la respuesta
 *   5. Guardar la interacción en ia_chat_historial
 *
 * Método:  POST
 * Auth:    verify_jwt: true
 *
 * Body:
 *   empresa_id      : UUID de la empresa
 *   pregunta        : Pregunta en lenguaje natural
 *   contexto_extra? : Contexto adicional sobre el usuario (ej. "gerente de ventas")
 *   historial?      : Array<{ role, content }> — turnos anteriores de conversación
 *   tablas_buscar?  : string[] — limitar búsqueda a estas tablas. Null = todas.
 *   top_k?          : Número de resultados similares a usar como contexto (default: 5)
 *
 * Respuesta exitosa (200):
 *   {
 *     respuesta: string,
 *     fuentes: Array<{ tabla: string, id: string, similarity: number }>,
 *     tokens_usados: number
 *   }
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
  chatCompletion,
  SearchResult,
  ChatMessage,
} from '../_shared/ai-helpers.ts';

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface QueryRequest {
  empresa_id: string;
  pregunta: string;
  contexto_extra?: string;
  historial?: Array<{ role: 'user' | 'assistant'; content: string }>;
  tablas_buscar?: string[];
  top_k?: number;
}

interface QueryResponse {
  respuesta: string;
  fuentes: Array<{ tabla: string; id: string; similarity: number }>;
  tokens_usados: number;
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
// Construcción del prompt del sistema
// ---------------------------------------------------------------------------

function buildSystemPrompt(
  resultados: SearchResult[],
  nombreEmpresa: string,
  contextoExtra?: string,
): string {
  const fechaActual = new Date().toLocaleDateString('es-EC', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'America/Guayaquil',
  });

  // Formatear contexto recuperado como texto legible
  let contextoERP = '';
  if (resultados.length > 0) {
    contextoERP = resultados
      .map((r, idx) => {
        const similarity = (r.similarity * 100).toFixed(1);
        return `[${idx + 1}] (${r.tabla_origen}, similitud: ${similarity}%)\n${r.contenido}`;
      })
      .join('\n\n');
  } else {
    contextoERP = 'No se encontró información relevante en el ERP para esta consulta.';
  }

  const contextoUsuarioPart = contextoExtra
    ? `\nCONTEXTO DEL USUARIO: ${contextoExtra}\n`
    : '';

  return `Eres PILAR IA, el asistente inteligente del ERP PILAR para Ecuador.
${contextoUsuarioPart}
CONTEXTO DEL ERP (información relevante recuperada para responder):
${contextoERP}

INSTRUCCIONES:
- Responde en español, de forma concisa y profesional
- Basa tu respuesta en los datos del contexto del ERP cuando sea posible
- Si la información no está disponible en el contexto, indícalo claramente y sugiere dónde encontrarla
- Para montos monetarios, usa el formato $X.XXX,XX (ej: $1.234,56)
- Para porcentajes, usa el formato X% (ej: 15%)
- Sé preciso con los números — no inventes cifras que no estén en el contexto
- Si el contexto tiene información parcial, úsala y aclara qué falta
- Fecha actual: ${fechaActual}
- Empresa: ${nombreEmpresa}`;
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
  let body: QueryRequest;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, 'BODY_INVALIDO', 'El cuerpo de la solicitud no es JSON válido');
  }

  // 4. Validar campos requeridos
  const { empresa_id, pregunta, contexto_extra, historial, tablas_buscar, top_k } = body;

  if (!empresa_id || !isValidUuid(empresa_id)) {
    return errorResponse(400, 'CAMPOS_REQUERIDOS', 'empresa_id es requerido y debe ser un UUID válido');
  }
  if (!pregunta?.trim()) {
    return errorResponse(400, 'CAMPOS_REQUERIDOS', 'pregunta es requerida');
  }
  if (pregunta.trim().length > 2000) {
    return errorResponse(400, 'BODY_INVALIDO', 'La pregunta no puede exceder 2000 caracteres');
  }

  const topK = Math.min(Math.max(top_k ?? 5, 1), 20); // Entre 1 y 20

  // 5. Obtener OPENAI_API_KEY
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  if (!apiKey) {
    console.error('[ai-query] OPENAI_API_KEY no configurada');
    return errorResponse(500, 'OPENAI_ERROR', 'Configuración de OpenAI no disponible');
  }

  // 6. Crear clientes Supabase
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const authHeader = req.headers.get('Authorization') ?? '';

  const supabaseClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const supabaseAdmin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

  // 7. Verificar autenticación y obtener usuario
  const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
  if (!user || authError) {
    return errorResponse(401, 'UNAUTHORIZED', 'Se requiere autenticación válida');
  }

  try {
    // 8. Obtener nombre de la empresa para el prompt
    const { data: empresaData } = await supabaseAdmin
      .from('empresas')
      .select('nombre_comercial, razon_social')
      .eq('id', empresa_id)
      .single();

    const nombreEmpresa: string =
      (empresaData?.nombre_comercial as string) ||
      (empresaData?.razon_social as string) ||
      'Tu empresa';

    // 9. Generar embedding de la pregunta
    let preguntaEmbedding: number[];
    try {
      const { vector } = await generateEmbedding(pregunta.trim(), apiKey);
      preguntaEmbedding = vector;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error('[ai-query] Error generando embedding de pregunta:', msg);
      return errorResponse(500, 'OPENAI_ERROR', `Error generando embedding: ${msg}`);
    }

    // 10. Buscar registros similares en la tabla embeddings
    // Usar RPC search_embeddings con el vector de la pregunta
    const vectorStr = `[${preguntaEmbedding.join(',')}]`;

    const { data: searchData, error: searchError } = await supabaseAdmin.rpc(
      'search_embeddings',
      {
        p_empresa_id: empresa_id,
        p_vector: vectorStr,
        p_top_k: topK,
        p_tablas: tablas_buscar ?? null,
        p_threshold: 0.5,
      },
    );

    if (searchError) {
      console.error('[ai-query] Error en search_embeddings:', searchError.message);
      return errorResponse(500, 'DB_ERROR', `Error en búsqueda semántica: ${searchError.message}`);
    }

    const resultados: SearchResult[] = (searchData as SearchResult[]) ?? [];

    console.log(
      `[ai-query] Búsqueda semántica para empresa ${empresa_id}: ` +
      `${resultados.length} resultados (top_k=${topK})`,
    );

    // 11. Construir mensajes para el LLM
    const systemPrompt = buildSystemPrompt(resultados, nombreEmpresa, contexto_extra);

    // Construir array de mensajes: system + historial previo + pregunta actual
    const messages: ChatMessage[] = [
      { role: 'system', content: systemPrompt },
    ];

    // Agregar historial de conversación (limitar a los últimos 10 turnos para no exceder tokens)
    if (historial && historial.length > 0) {
      const historialReciente = historial.slice(-10);
      for (const turno of historialReciente) {
        messages.push({ role: turno.role, content: turno.content });
      }
    }

    // Agregar la pregunta actual
    messages.push({ role: 'user', content: pregunta.trim() });

    // 12. Llamar al LLM para generar la respuesta
    let respuesta: string;
    let tokensUsados: number;
    try {
      const result = await chatCompletion(messages, apiKey);
      respuesta = result.content;
      tokensUsados = result.tokens_used;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error('[ai-query] Error en chat completion:', msg);
      return errorResponse(500, 'OPENAI_ERROR', `Error generando respuesta: ${msg}`);
    }

    // 13. Guardar interacción en ia_chat_historial
    const fuentes = resultados.map((r) => ({
      tabla: r.tabla_origen,
      id: r.registro_id,
      similarity: r.similarity,
    }));

    const { error: historialError } = await supabaseAdmin
      .from('ia_chat_historial')
      .insert({
        empresa_id,
        usuario_id: user.id,
        pregunta: pregunta.trim(),
        respuesta,
        fuentes,
        tokens_usados: tokensUsados,
        modelo_chat: Deno.env.get('OPENAI_CHAT_MODEL') ?? 'gpt-4o-mini',
        modelo_embed: Deno.env.get('OPENAI_EMBEDDING_MODEL') ?? 'text-embedding-3-small',
      });

    if (historialError) {
      // No interrumpir la respuesta por un fallo en el historial
      console.warn('[ai-query] Error guardando historial (no fatal):', historialError.message);
    }

    console.log(
      `[ai-query] Respuesta generada para empresa ${empresa_id}: ` +
      `${tokensUsados} tokens, ${fuentes.length} fuentes`,
    );

    // 14. Respuesta al cliente
    const response: QueryResponse = {
      respuesta,
      fuentes,
      tokens_usados: tokensUsados,
    };

    return jsonResponse(200, response);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[ai-query] Error inesperado:', msg);
    return errorResponse(500, 'INTERNAL_ERROR', 'Error procesando la solicitud');
  }
});
