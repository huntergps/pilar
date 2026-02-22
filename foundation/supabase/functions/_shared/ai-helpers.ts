/**
 * PILAR ERP — Shared AI Helpers
 *
 * Utilidades compartidas para las Edge Functions del módulo IA/Chat:
 *   - ai-embed   : Indexar documentos del ERP para búsqueda semántica
 *   - ai-query   : Chat NLP con búsqueda semántica
 *   - ai-report  : Generación de reportes e insights
 *
 * Modelos por defecto (configurables vía env vars):
 *   OPENAI_EMBEDDING_MODEL → text-embedding-3-small (1536 dimensiones)
 *   OPENAI_CHAT_MODEL      → gpt-4o-mini
 */

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

export interface EmbeddingVector {
  vector: number[];
  model: string;
  tokens: number;
}

export interface SearchResult {
  id: string;
  tabla_origen: string;
  registro_id: string;
  contenido: string;
  metadata: Record<string, unknown>;
  similarity: number;
}

export type TablaOrigen =
  | 'facturas'
  | 'facturas_proveedor'
  | 'contactos'
  | 'productos'
  | 'ordenes_venta'
  | 'ordenes_compra'
  | 'asientos_contables'
  | 'oportunidades'
  | 'chat_mensajes'
  | 'manual';

export type ChatMessage = {
  role: 'system' | 'user' | 'assistant';
  content: string;
};

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

/** Dimensión del vector de text-embedding-3-small. */
export const EMBEDDING_DIMENSIONS = 1536;

/**
 * Tokens máximos seguros para enviar a la API de embeddings.
 * El límite real de text-embedding-3-small es 8191 tokens, pero usamos
 * 8000 como margen para tokens de overhead del tokenizador.
 */
const MAX_EMBEDDING_TOKENS = 8000;

/**
 * Estimación conservadora: ~4 caracteres UTF-8 por token.
 * No requiere un tokenizador real en el servidor.
 */
const CHARS_PER_TOKEN = 4;

// ---------------------------------------------------------------------------
// Formateo de moneda Ecuador
// ---------------------------------------------------------------------------

/**
 * Formatea un número como moneda ecuatoriana (USD).
 * Ejemplo: 1234567.89 → "$1.234.567,89"
 */
export function fmtUSD(n: number): string {
  // Usar Intl solo está disponible en Deno, y el locale 'es-EC' formatea
  // con punto de miles y coma decimal, que es la convención Ecuador.
  return new Intl.NumberFormat('es-EC', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(n);
}

// ---------------------------------------------------------------------------
// Truncado de texto
// ---------------------------------------------------------------------------

/**
 * Trunca un texto al número aproximado de tokens indicado.
 * Usa la estimación de 4 caracteres por token (no requiere tokenizador real).
 * Si el texto cabe completo, lo retorna sin modificación.
 */
export function truncateToTokens(text: string, maxTokens: number = MAX_EMBEDDING_TOKENS): string {
  const maxChars = maxTokens * CHARS_PER_TOKEN;
  if (text.length <= maxChars) return text;
  // Cortar en límite de palabra para no romper en medio de un token
  const truncated = text.slice(0, maxChars);
  const lastSpace = truncated.lastIndexOf(' ');
  return lastSpace > maxChars * 0.8 ? truncated.slice(0, lastSpace) : truncated;
}

// ---------------------------------------------------------------------------
// Preparación de texto para embedding
// ---------------------------------------------------------------------------

/**
 * Convierte un registro del ERP en un texto descriptivo legible para embedding.
 *
 * El texto resultante debe ser lo más informativo posible para que el modelo
 * de embeddings capture el significado semántico del registro.
 *
 * Para tablas no mapeadas explícitamente, serializa el objeto como JSON.
 */
export function prepareTextForEmbedding(
  tabla: TablaOrigen,
  data: Record<string, unknown>,
): string {
  const str = (key: string, fallback = ''): string =>
    data[key] != null ? String(data[key]) : fallback;

  const num = (key: string, fallback = 0): number =>
    data[key] != null ? Number(data[key]) : fallback;

  switch (tabla) {
    case 'facturas': {
      const items = str('descripcion_items') || str('items');
      const itemsPart = items ? ` Productos: ${items}.` : '';
      return (
        `Factura ${str('numero')} del ${str('fecha')} a cliente ${str('cliente')} ` +
        `por ${fmtUSD(num('total'))}.${itemsPart} Estado: ${str('estado')}.`
      ).trim();
    }

    case 'facturas_proveedor': {
      const items = str('descripcion_items') || str('items');
      const itemsPart = items ? ` Productos: ${items}.` : '';
      return (
        `Factura de proveedor ${str('numero')} del ${str('fecha')} de ${str('proveedor')} ` +
        `por ${fmtUSD(num('total'))}.${itemsPart} Estado: ${str('estado')}.`
      ).trim();
    }

    case 'contactos': {
      const tipo = str('tipo') || str('tipo_identificacion');
      const identificacion = str('identificacion') || str('ruc') || str('cedula');
      const idPart = tipo && identificacion ? `(${tipo}: ${identificacion})` : '';
      const emailPart = str('email') ? ` Email: ${str('email')}.` : '';
      const telPart = str('telefono') ? ` Teléfono: ${str('telefono')}.` : '';
      const ciudadPart = str('ciudad') ? ` Ciudad: ${str('ciudad')}.` : '';
      return (
        `Contacto ${str('nombre')} ${idPart}.${emailPart}${telPart}${ciudadPart}`
      ).trim();
    }

    case 'productos': {
      const catPart = str('categoria') ? ` Categoría: ${str('categoria')}.` : '';
      const precioPart = num('precio') ? ` Precio: ${fmtUSD(num('precio'))}.` : '';
      const stockPart = data['stock'] != null ? ` Stock: ${num('stock')} unidades.` : '';
      return (
        `Producto ${str('nombre')} (código ${str('codigo')}).${catPart}${precioPart}${stockPart}`
      ).trim();
    }

    case 'ordenes_venta': {
      const itemsPart = str('descripcion_items') ? ` Items: ${str('descripcion_items')}.` : '';
      return (
        `Orden de Venta ${str('numero')} para ${str('cliente')}. ` +
        `Fecha: ${str('fecha')}. Total: ${fmtUSD(num('total'))}.${itemsPart} Estado: ${str('estado')}.`
      ).trim();
    }

    case 'ordenes_compra': {
      const itemsPart = str('descripcion_items') ? ` Items: ${str('descripcion_items')}.` : '';
      return (
        `Orden de Compra ${str('numero')} a proveedor ${str('proveedor')}. ` +
        `Fecha: ${str('fecha')}. Total: ${fmtUSD(num('total'))}.${itemsPart} Estado: ${str('estado')}.`
      ).trim();
    }

    case 'asientos_contables': {
      const descripcionPart = str('descripcion') ? ` ${str('descripcion')}.` : '';
      return (
        `Asiento contable ${str('numero')} del ${str('fecha')} en diario ${str('diario')}.` +
        `${descripcionPart} Debe: ${fmtUSD(num('total_debe'))}. Haber: ${fmtUSD(num('total_haber'))}.`
      ).trim();
    }

    case 'oportunidades': {
      const etapaPart = str('etapa') ? ` Etapa: ${str('etapa')}.` : '';
      const probabilidadPart = data['probabilidad'] != null
        ? ` Probabilidad: ${num('probabilidad')}%.`
        : '';
      return (
        `Oportunidad CRM: ${str('nombre')} para ${str('cliente')}. ` +
        `Valor estimado: ${fmtUSD(num('valor_esperado'))}.${etapaPart}${probabilidadPart}`
      ).trim();
    }

    case 'chat_mensajes': {
      const autorPart = str('autor') ? `[${str('autor')}] ` : '';
      return `${autorPart}${str('contenido')}`.trim();
    }

    case 'manual': {
      // Para documentos manuales el campo 'contenido' se usa directamente
      return str('contenido');
    }

    default: {
      // Fallback: serializar el objeto sin campos de infraestructura
      const filtrado = { ...data };
      for (const k of ['id', 'empresa_id', 'created_at', 'updated_at', 'version']) {
        delete filtrado[k];
      }
      return JSON.stringify(filtrado);
    }
  }
}

// ---------------------------------------------------------------------------
// Generación de embeddings vía OpenAI
// ---------------------------------------------------------------------------

/**
 * Genera un vector de embedding para el texto dado usando la API de OpenAI.
 *
 * @param text    Texto a embeder (ya truncado si es necesario)
 * @param apiKey  Clave de API de OpenAI
 * @param model   Modelo de embeddings (default: text-embedding-3-small)
 * @throws Error si la API retorna un código de estado no exitoso
 */
export async function generateEmbedding(
  text: string,
  apiKey: string,
  model?: string,
): Promise<EmbeddingVector> {
  const modelName = model ?? Deno.env.get('OPENAI_EMBEDDING_MODEL') ?? 'text-embedding-3-small';

  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: modelName,
      input: text,
      encoding_format: 'float',
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(
      `OpenAI Embeddings API error ${response.status}: ${errorBody}`,
    );
  }

  const data = await response.json();

  const vector: number[] = data.data?.[0]?.embedding;
  if (!Array.isArray(vector) || vector.length === 0) {
    throw new Error('OpenAI Embeddings API: respuesta inválida — vector vacío');
  }

  const tokens: number = data.usage?.total_tokens ?? 0;

  return { vector, model: modelName, tokens };
}

// ---------------------------------------------------------------------------
// Chat completion vía OpenAI
// ---------------------------------------------------------------------------

/**
 * Llama a la API de chat completions de OpenAI con el historial de mensajes dado.
 *
 * @param messages  Array de mensajes en formato { role, content }
 * @param apiKey    Clave de API de OpenAI
 * @param model     Modelo de chat (default: gpt-4o-mini)
 * @returns         Contenido de la respuesta del asistente y tokens consumidos
 * @throws Error si la API retorna un código de estado no exitoso
 */
export async function chatCompletion(
  messages: ChatMessage[],
  apiKey: string,
  model?: string,
): Promise<{ content: string; tokens_used: number }> {
  const modelName = model ?? Deno.env.get('OPENAI_CHAT_MODEL') ?? 'gpt-4o-mini';

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: modelName,
      messages,
      temperature: 0.3,
      max_tokens: 1000,
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(
      `OpenAI Chat API error ${response.status}: ${errorBody}`,
    );
  }

  const data = await response.json();

  const content: string = data.choices?.[0]?.message?.content ?? '';
  if (!content) {
    throw new Error('OpenAI Chat API: respuesta vacía del asistente');
  }

  const tokens_used: number = data.usage?.total_tokens ?? 0;

  return { content, tokens_used };
}
