/**
 * PILAR ERP — Edge Function: import-bank-statement
 *
 * Parsea un estado de cuenta bancario (CSV, OFX o QFX) descargado del banco
 * y retorna las transacciones detectadas para que Flutter las muestre al usuario
 * y éste las concilie manualmente.
 *
 * IMPORTANTE: Esta función SOLO parsea y retorna. No persiste nada en la base
 * de datos. El guardado en `movimientos_bancarios` se realiza en una llamada
 * posterior desde Flutter, usando la RPC `save_movimientos_importados` una vez
 * que el usuario confirma los movimientos a importar.
 *
 * Método:   POST
 * Auth:     JWT requerido (verify_jwt: true)
 * Body:     multipart/form-data
 *   - file              : File — archivo CSV/OFX/QFX/TXT (max 5 MB)
 *   - cuenta_bancaria_id: string (UUID) — cuenta bancaria destino
 *   - empresa_id        : string (UUID) — empresa del usuario
 *
 * Respuesta exitosa (200):
 * {
 *   "success": true,
 *   "formato": "CSV",
 *   "banco_detectado": "Banco Pichincha",
 *   "periodo": { "desde": "2026-02-01", "hasta": "2026-02-28" },
 *   "total_transacciones": 45,
 *   "total_debitos": 12500.00,
 *   "total_creditos": 18000.00,
 *   "transacciones": [...],
 *   "duplicados_detectados": 2,
 *   "errores": []
 * }
 *
 * Códigos de error posibles:
 *   405  METHOD_NOT_ALLOWED
 *   401  UNAUTHORIZED
 *   400  NO_EMPRESA_CONTEXT
 *   400  ARCHIVO_REQUERIDO
 *   400  ARCHIVO_DEMASIADO_GRANDE
 *   400  EXTENSION_NO_PERMITIDA
 *   400  CUENTA_BANCARIA_REQUERIDA
 *   400  SIN_TRANSACCIONES
 *   403  FORBIDDEN
 *   500  INTERNAL_ERROR
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import {
  parseBankStatement,
  BankTransaction,
  BankStatementParseResult,
} from '../_shared/bank-parser.ts';

// =============================================================================
// CONSTANTES
// =============================================================================

const MAX_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB

/** Extensiones de archivo permitidas (en minúsculas, sin punto). */
const EXTENSIONES_PERMITIDAS = new Set(['csv', 'ofx', 'qfx', 'txt']);

// =============================================================================
// TIPOS INTERNOS
// =============================================================================

/** Transacción enriquecida con información de duplicado. */
interface TransaccionConDuplicado extends BankTransaction {
  /** true si ya existe un movimiento bancario con los mismos datos en la BD. */
  duplicado: boolean;
}

// =============================================================================
// HELPERS
// =============================================================================

/** Genera una respuesta de error JSON con CORS headers. */
function errorResponse(
  status: number,
  code: string,
  message?: string,
): Response {
  return new Response(
    JSON.stringify({ success: false, error: code, message }),
    {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
}

/** Genera una respuesta exitosa JSON con CORS headers. */
function okResponse(data: Record<string, unknown>): Response {
  return new Response(
    JSON.stringify({ success: true, ...data }),
    {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
}

/**
 * Extrae la extensión de un nombre de archivo (sin punto, en minúsculas).
 * Retorna '' si el archivo no tiene extensión.
 */
function obtenerExtension(filename: string): string {
  const parts = filename.toLowerCase().split('.');
  return parts.length > 1 ? parts[parts.length - 1] : '';
}

/**
 * Intenta leer el contenido del archivo como texto.
 * Primero intenta UTF-8. Si falla por caracteres inválidos, intenta Latin-1 (ISO-8859-1).
 * Los bancos ecuatorianos a veces generan CSVs en Latin-1.
 */
async function leerArchivoComoTexto(file: File): Promise<string> {
  try {
    // Primer intento: UTF-8 (Deno File.text() usa UTF-8 por defecto)
    return await file.text();
  } catch {
    // Fallback: Latin-1 / ISO-8859-1
    const buffer = await file.arrayBuffer();
    const decoder = new TextDecoder('iso-8859-1');
    return decoder.decode(buffer);
  }
}

/**
 * Verifica si un movimiento ya existe en la base de datos llamando a la
 * RPC check_movimiento_duplicado. Retorna false ante cualquier error de BD
 * para no bloquear el flujo de importación.
 */
async function verificarDuplicado(
  supabaseClient: SupabaseClient,
  cuentaId: string,
  fecha: string,
  monto: number,
  referencia: string,
): Promise<boolean> {
  try {
    const { data, error } = await supabaseClient.rpc('check_movimiento_duplicado', {
      p_cuenta_id:  cuentaId,
      p_fecha:      fecha,
      p_monto:      monto,
      p_referencia: referencia || null,
    });

    if (error) {
      console.warn('[import-bank-statement] check_movimiento_duplicado error:', error.message);
      return false;
    }

    return Boolean(data);
  } catch (err) {
    console.warn('[import-bank-statement] Error verificando duplicado:', err);
    return false;
  }
}

/**
 * Calcula totales de débitos y créditos a partir de la lista de transacciones.
 */
function calcularTotales(
  transacciones: TransaccionConDuplicado[],
): { totalDebitos: number; totalCreditos: number } {
  let totalDebitos  = 0;
  let totalCreditos = 0;

  for (const t of transacciones) {
    if (t.tipo === 'DEBITO') {
      totalDebitos  = +(totalDebitos  + t.monto).toFixed(2);
    } else {
      totalCreditos = +(totalCreditos + t.monto).toFixed(2);
    }
  }

  return { totalDebitos, totalCreditos };
}

// =============================================================================
// HANDLER PRINCIPAL
// =============================================================================

Deno.serve(async (req: Request): Promise<Response> => {

  // 1. CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  // 2. Solo POST permitido
  if (req.method !== 'POST') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Solo se acepta POST');
  }

  try {
    // -------------------------------------------------------------------------
    // 3. Crear clientes Supabase
    //    - supabaseClient: actúa con JWT del usuario (respeta RLS)
    //      → Para auth.getUser() y RPCs que verifican empresa_id via RLS
    //    - supabaseAdmin:  service_role (bypass RLS)
    //      → Para verificar duplicados sin restricciones de empresa_id
    //        cuando la función SECURITY DEFINER ya lo maneja
    // -------------------------------------------------------------------------
    const supabaseClient: SupabaseClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization') ?? '' },
        },
      },
    );

    // 4. Autenticación: verificar JWT y obtener usuario
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return errorResponse(401, 'UNAUTHORIZED', 'Token inválido o expirado');
    }

    // 5. Obtener empresa_id desde app_metadata del JWT (establecido por Supabase Auth)
    const empresaId = user.app_metadata?.empresa_id as string | undefined;
    if (!empresaId) {
      return errorResponse(
        400,
        'NO_EMPRESA_CONTEXT',
        'El usuario no tiene empresa_id en app_metadata. Seleccione una empresa activa.',
      );
    }

    // -------------------------------------------------------------------------
    // 6. Parsear multipart/form-data
    // -------------------------------------------------------------------------
    let formData: FormData;
    try {
      formData = await req.formData();
    } catch (err) {
      return errorResponse(
        400,
        'FORM_DATA_INVALIDO',
        `No se pudo parsear el form-data: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    const file              = formData.get('file') as File | null;
    const cuentaBancariaId  = (formData.get('cuenta_bancaria_id') as string | null)?.trim();
    const empresaIdForm     = (formData.get('empresa_id') as string | null)?.trim();

    // 7. Validar: archivo requerido
    if (!file) {
      return errorResponse(400, 'ARCHIVO_REQUERIDO', 'El campo "file" es obligatorio');
    }

    // 8. Validar: cuenta_bancaria_id requerida
    if (!cuentaBancariaId) {
      return errorResponse(
        400,
        'CUENTA_BANCARIA_REQUERIDA',
        'El campo "cuenta_bancaria_id" es obligatorio',
      );
    }

    // 9. Verificar consistencia empresa_id (form vs JWT)
    // Si se envía empresa_id en el form, debe coincidir con el JWT para evitar
    // que un usuario intente importar movimientos a cuentas de otra empresa.
    if (empresaIdForm && empresaIdForm !== empresaId) {
      return errorResponse(
        403,
        'FORBIDDEN',
        'El empresa_id del formulario no coincide con el contexto de sesión',
      );
    }

    // 10. Validar extensión del archivo
    const extension = obtenerExtension(file.name);
    if (!EXTENSIONES_PERMITIDAS.has(extension)) {
      return errorResponse(
        400,
        'EXTENSION_NO_PERMITIDA',
        `Extensión ".${extension}" no permitida. Se aceptan: ${[...EXTENSIONES_PERMITIDAS].map(e => `.${e}`).join(', ')}`,
      );
    }

    // 11. Validar tamaño máximo (5 MB)
    if (file.size > MAX_SIZE_BYTES) {
      return errorResponse(
        400,
        'ARCHIVO_DEMASIADO_GRANDE',
        `El archivo supera el máximo de ${MAX_SIZE_BYTES / 1024 / 1024} MB (tamaño: ${(file.size / 1024 / 1024).toFixed(2)} MB)`,
      );
    }

    // -------------------------------------------------------------------------
    // 12. Leer contenido del archivo como texto (UTF-8 con fallback Latin-1)
    // -------------------------------------------------------------------------
    const content = await leerArchivoComoTexto(file);

    if (!content.trim()) {
      return errorResponse(400, 'ARCHIVO_VACIO', 'El archivo está vacío');
    }

    // -------------------------------------------------------------------------
    // 13. Parsear el estado de cuenta
    // -------------------------------------------------------------------------
    const parseResult: BankStatementParseResult = parseBankStatement(content, file.name);

    if (parseResult.transacciones.length === 0) {
      return errorResponse(
        400,
        'SIN_TRANSACCIONES',
        `No se encontraron transacciones en el archivo. ` +
        (parseResult.errores.length > 0
          ? `Errores: ${parseResult.errores.slice(0, 3).join(' | ')}`
          : 'Verifique que el archivo sea un estado de cuenta bancario válido.'),
      );
    }

    // -------------------------------------------------------------------------
    // 14. Verificar duplicados para cada transacción
    //     Se llama la RPC check_movimiento_duplicado con el cliente autenticado
    //     (que respeta el RLS de la empresa via JWT).
    //     Para optimizar, se hacen las verificaciones en paralelo.
    // -------------------------------------------------------------------------
    const verificaciones = await Promise.all(
      parseResult.transacciones.map(trx =>
        verificarDuplicado(
          supabaseClient,
          cuentaBancariaId,
          trx.fecha,
          trx.monto,
          trx.referencia,
        )
      )
    );

    const transaccionesConDuplicado: TransaccionConDuplicado[] = parseResult.transacciones.map(
      (trx, idx) => ({ ...trx, duplicado: verificaciones[idx] })
    );

    const duplicadosDetectados = verificaciones.filter(Boolean).length;

    // -------------------------------------------------------------------------
    // 15. Calcular totales
    // -------------------------------------------------------------------------
    const { totalDebitos, totalCreditos } = calcularTotales(transaccionesConDuplicado);

    // -------------------------------------------------------------------------
    // 16. Retornar resultado completo
    //     Flutter mostrará la lista y el usuario confirmará cuáles importar.
    // -------------------------------------------------------------------------
    return okResponse({
      formato:               parseResult.formato,
      banco_detectado:       parseResult.banco_detectado ?? null,
      cuenta_numero_archivo: parseResult.cuenta_numero ?? null,
      periodo: {
        desde: parseResult.fecha_desde ?? null,
        hasta: parseResult.fecha_hasta ?? null,
      },
      total_transacciones:  transaccionesConDuplicado.length,
      total_debitos:        totalDebitos,
      total_creditos:       totalCreditos,
      transacciones:        transaccionesConDuplicado,
      duplicados_detectados: duplicadosDetectados,
      errores_parseo:       parseResult.errores,
      // Metadatos para que Flutter pueda llamar save_movimientos_importados
      _meta: {
        cuenta_bancaria_id: cuentaBancariaId,
        empresa_id:         empresaId,
        archivo_nombre:     file.name,
        archivo_tamanio:    file.size,
      },
    });

  } catch (err) {
    // Catch global: nunca exponer detalles internos al cliente
    console.error('[import-bank-statement] Error inesperado:', err);
    return errorResponse(
      500,
      'INTERNAL_ERROR',
      `Error procesando la solicitud: ${err instanceof Error ? err.message : 'Error desconocido'}`,
    );
  }
});
