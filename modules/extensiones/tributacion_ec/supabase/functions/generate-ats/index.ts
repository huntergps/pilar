/**
 * PILAR ERP — Edge Function: generate-ats
 *
 * Genera el ATS (Anexo Transaccional Simplificado) para un período mensual,
 * lo empaqueta como ZIP con el XML en ISO-8859-1, lo sube al bucket 'tributacion_ec'
 * de Supabase Storage y retorna una URL firmada con validez de 1 hora.
 *
 * Método:  POST
 * Auth:    JWT requerido (verify_jwt: true)
 * Permiso: tributacion.ats.generar
 *
 * Request body:
 *   {
 *     "empresa_id": "<uuid>",
 *     "anio": 2026,
 *     "mes": 2
 *   }
 *
 * Respuesta exitosa (200):
 *   {
 *     "success": true,
 *     "url": "https://...supabase.co/storage/v1/object/sign/tributacion/...",
 *     "nombre_archivo": "ATS_202602_1790016919.zip",
 *     "declaracion_id": "<uuid>",
 *     "totales": {
 *       "total_ventas": 50000.00,
 *       "total_compras": 10000.00,
 *       "num_registros_ventas": 3,
 *       "num_registros_compras": 5
 *     }
 *   }
 *
 * Errores:
 *   400  PARAMS_INVALIDOS       — empresa_id, anio o mes con formato incorrecto
 *   401  UNAUTHORIZED           — JWT ausente o inválido
 *   403  FORBIDDEN              — sin permiso tributacion.ats.generar
 *   405  METHOD_NOT_ALLOWED     — método distinto de POST
 *   422  SIN_DATOS_PERIODO      — no hay ventas ni compras para el período
 *   500  ATS_DATA_ERROR         — error al llamar get_ats_data
 *   500  STORAGE_ERROR          — error al subir el ZIP o generar URL firmada
 *   500  INTERNAL_ERROR         — error inesperado no clasificado
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { buildAtsXml, encodeIso88591, AtsData } from '../_shared/ats-xml.ts';
import { zipSync } from 'npm:fflate@0.8.2';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const BUCKET_TRIBUTACION = 'tributacion_ec';
const SIGNED_URL_EXPIRY_SECONDS = 3600; // 1 hora

/** Año mínimo aceptado para declaraciones (primer año del SRI electrónico). */
const ANIO_MINIMO = 2020;

// ---------------------------------------------------------------------------
// Helpers de respuesta HTTP
// ---------------------------------------------------------------------------

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(status: number, error: string, detail?: unknown): Response {
  return jsonResponse(status, { success: false, error, detail });
}

// ---------------------------------------------------------------------------
// Helper: valida formato UUID v4
// ---------------------------------------------------------------------------

function isValidUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

// ---------------------------------------------------------------------------
// Helper: valida y normaliza los parámetros del request
// ---------------------------------------------------------------------------

interface AtsParams {
  empresa_id: string;
  anio: number;
  mes: number;
}

function validateParams(body: unknown): { params: AtsParams } | { validationError: string } {
  if (typeof body !== 'object' || body === null) {
    return { validationError: 'El body debe ser un objeto JSON' };
  }

  const raw = body as Record<string, unknown>;

  // empresa_id
  if (typeof raw.empresa_id !== 'string' || !isValidUuid(raw.empresa_id)) {
    return { validationError: 'empresa_id debe ser un UUID válido' };
  }

  // anio
  const anio = Number(raw.anio);
  const anioActual = new Date().getFullYear();
  if (!Number.isInteger(anio) || anio < ANIO_MINIMO || anio > anioActual + 1) {
    return {
      validationError: `anio debe ser un número entero entre ${ANIO_MINIMO} y ${anioActual + 1}`,
    };
  }

  // mes
  const mes = Number(raw.mes);
  if (!Number.isInteger(mes) || mes < 1 || mes > 12) {
    return { validationError: 'mes debe ser un número entero entre 1 y 12' };
  }

  return {
    params: {
      empresa_id: raw.empresa_id,
      anio,
      mes,
    },
  };
}

// ---------------------------------------------------------------------------
// Helper: construye nombres de archivo y path en Storage
// ---------------------------------------------------------------------------

interface AtsFilenames {
  /** Nombre base sin extensión, ej. "ATS_202602_1790016919001". */
  nombre: string;
  /** Nombre del archivo XML dentro del ZIP, ej. "ATS_202602_1790016919001.xml". */
  xmlFilename: string;
  /** Nombre del archivo ZIP final, ej. "ATS_202602_1790016919001.zip". */
  zipFilename: string;
  /** Path en el bucket Storage, ej. "empresaUUID/ats/ATS_202602_1790016919001.zip". */
  storagePath: string;
}

function buildFilenames(empresaId: string, anio: number, mes: number, ruc: string): AtsFilenames {
  const mesStr = String(mes).padStart(2, '0');
  const nombre = `ATS_${anio}${mesStr}_${ruc}`;
  const xmlFilename = `${nombre}.xml`;
  const zipFilename = `${nombre}.zip`;
  const storagePath = `${empresaId}/ats/${zipFilename}`;
  return { nombre, xmlFilename, zipFilename, storagePath };
}

// ---------------------------------------------------------------------------
// Helper: calcula totales de compras (suma de montoIva de todas las compras)
// ---------------------------------------------------------------------------

function calcularTotalCompras(compras: AtsData['compras']): number {
  return compras.reduce((acc, c) => acc + c.baseNoGraIva + c.baseImponible + c.baseImpGrav, 0);
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

  // 3. Header de autorización obligatorio (verify_jwt: true en deploy)
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse(401, 'UNAUTHORIZED', 'Token de autorización requerido');
  }

  // 4. Construir clientes Supabase
  //    supabaseClient: actúa con el JWT del llamador (RLS activo, auth.getUser, RPCs de negocio)
  //    supabaseAdmin:  service_role, para Storage y operaciones que requieren eludir RLS
  const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
  const anonKey        = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const supabaseClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const supabaseAdmin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

  // Variable para rastrear el declaracion_id en caso de error tardío
  let declaracionId: string | null = null;

  try {
    // 5. Verificar usuario autenticado
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !user) {
      return errorResponse(401, 'UNAUTHORIZED', 'Token inválido o expirado');
    }

    // 6. Parsear y validar body
    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      return errorResponse(400, 'PARAMS_INVALIDOS', 'El body debe ser JSON válido');
    }

    const validationResult = validateParams(rawBody);
    if ('validationError' in validationResult) {
      return errorResponse(400, 'PARAMS_INVALIDOS', validationResult.validationError);
    }
    const { empresa_id, anio, mes } = validationResult.params;

    // 7. Verificar permiso de tributación (RLS activo mediante supabaseClient)
    const { data: hasPerm, error: permError } = await supabaseClient.rpc(
      'check_permission',
      { p_permiso: 'tributacion.ats.generar' },
    );
    if (permError) {
      console.log('[generate-ats] Error al verificar permiso:', permError.message);
      return errorResponse(500, 'INTERNAL_ERROR', 'Error al verificar permisos');
    }
    if (!hasPerm) {
      return errorResponse(403, 'FORBIDDEN', 'No tiene permiso para generar el ATS');
    }

    // 8. Obtener datos del ATS via RPC (respeta RLS del empresa_id del usuario)
    console.log(`[generate-ats] Obteniendo datos ATS para empresa=${empresa_id}, ${anio}/${mes}`);
    const { data: atsData, error: atsError } = await supabaseClient.rpc('get_ats_data', {
      p_empresa_id: empresa_id,
      p_anio: anio,
      p_mes: mes,
    });

    if (atsError) {
      console.log('[generate-ats] Error en RPC get_ats_data:', atsError.message);
      // Intentar registrar el error en BD antes de responder
      await registrarDeclaracionError(
        supabaseClient,
        empresa_id,
        anio,
        mes,
        'Error al obtener datos del período: ' + atsError.message,
      );
      return errorResponse(500, 'ATS_DATA_ERROR', 'Error al obtener datos del período');
    }

    const data = atsData as AtsData;

    // 9. Validar que haya datos para el período
    const tieneVentas = data.ventas && data.ventas.length > 0;
    const tieneCompras = data.compras && data.compras.length > 0;

    if (!tieneVentas && !tieneCompras) {
      console.log('[generate-ats] Sin datos para el período solicitado');
      return errorResponse(
        422,
        'SIN_DATOS_PERIODO',
        `No hay ventas ni compras registradas para ${mes}/${anio}`,
      );
    }

    // Garantizar arrays inicializados aunque el RPC retorne null
    if (!data.ventas) data.ventas = [];
    if (!data.compras) data.compras = [];

    // 10. Construir nombres de archivo usando el RUC del informante
    const { xmlFilename, zipFilename, storagePath } = buildFilenames(
      empresa_id,
      anio,
      mes,
      data.IdInformante,
    );

    console.log(`[generate-ats] Generando XML: ${xmlFilename}`);

    // 11. Generar XML y codificar en ISO-8859-1 (requisito SRI)
    const xml = buildAtsXml(data);
    const xmlBytes = encodeIso88591(xml);

    // 12. Crear ZIP con un único archivo XML
    //     zipSync acepta Record<filename, Uint8Array> y retorna Uint8Array del ZIP
    const zipBytes = zipSync({ [xmlFilename]: xmlBytes });

    console.log(
      `[generate-ats] ZIP generado: ${zipFilename} (${zipBytes.length} bytes). Subiendo a Storage...`,
    );

    // 13. Subir ZIP a Storage bucket 'tributacion_ec'
    //     upsert: true → permite regenerar el ATS del mismo período sin error
    const { error: uploadError } = await supabaseAdmin.storage
      .from(BUCKET_TRIBUTACION)
      .upload(storagePath, zipBytes, {
        contentType: 'application/zip',
        upsert: true,
      });

    if (uploadError) {
      console.log('[generate-ats] Error al subir ZIP a Storage:', uploadError.message);
      // Intentar registrar el error
      const { data: errDecl } = await registrarDeclaracion(
        supabaseClient,
        empresa_id,
        anio,
        mes,
        'ERROR',
        null,
        zipFilename,
        null,
      );
      declaracionId = errDecl?.declaracion_id ?? null;
      return errorResponse(500, 'STORAGE_ERROR', 'No se pudo subir el ATS a Storage');
    }

    // 14. Crear URL firmada con validez de 1 hora
    const { data: signedData, error: signError } = await supabaseAdmin.storage
      .from(BUCKET_TRIBUTACION)
      .createSignedUrl(storagePath, SIGNED_URL_EXPIRY_SECONDS);

    if (signError || !signedData?.signedUrl) {
      const signMsg = signError?.message ?? 'No se pudo obtener URL firmada';
      console.log('[generate-ats] Error al generar URL firmada:', signMsg);
      const { data: errDecl } = await registrarDeclaracion(
        supabaseClient,
        empresa_id,
        anio,
        mes,
        'ERROR',
        null,
        zipFilename,
        null,
      );
      declaracionId = errDecl?.declaracion_id ?? null;
      return errorResponse(500, 'STORAGE_ERROR', 'ATS generado pero no se pudo obtener URL de descarga');
    }

    // 15. Calcular totales para el resumen
    const totalCompras = calcularTotalCompras(data.compras);
    const datosResumen = {
      total_ventas: data.totalVentas,
      total_compras: Number(totalCompras.toFixed(2)),
      num_registros_ventas: data.ventas.length,
      num_registros_compras: data.compras.length,
    };

    // 16. Registrar la declaración exitosa en BD
    //     Si falla, no bloquear la respuesta — el ZIP ya está en Storage
    const { data: declData } = await registrarDeclaracion(
      supabaseClient,
      empresa_id,
      anio,
      mes,
      'GENERADA',
      signedData.signedUrl,
      zipFilename,
      datosResumen,
    );
    declaracionId = declData?.declaracion_id ?? null;

    console.log(
      `[generate-ats] ATS generado correctamente. declaracion_id=${declaracionId ?? 'N/A'}`,
    );

    // 17. Respuesta exitosa
    return jsonResponse(200, {
      success: true,
      url: signedData.signedUrl,
      nombre_archivo: zipFilename,
      declaracion_id: declaracionId,
      totales: datosResumen,
    });

  } catch (err) {
    // Catch global: nunca exponer detalles internos al cliente
    const msg = err instanceof Error ? err.message : 'Error desconocido';
    console.log('[generate-ats] Error inesperado:', msg);
    return jsonResponse(500, {
      success: false,
      error: 'INTERNAL_ERROR',
      detail: 'Error procesando la solicitud',
      declaracion_id: declaracionId,
    });
  }
});

// ---------------------------------------------------------------------------
// Helpers para registrar la declaración en BD
// ---------------------------------------------------------------------------

/**
 * Registra o actualiza una declaración ATS en la tabla declaraciones_tributarias.
 * Usa supabaseClient (RLS activo) para que el registro quede bajo el contexto
 * del usuario que solicitó la generación.
 *
 * Retorna { data, error } — el llamador decide si bloquear o no ante un error.
 */
async function registrarDeclaracion(
  supabaseClient: SupabaseClient,
  empresaId: string,
  anio: number,
  mes: number,
  estado: string,
  archivoUrl: string | null,
  archivoNombre: string | null,
  datosResumen: Record<string, unknown> | null,
): Promise<{ data: { declaracion_id: string } | null; error: unknown }> {
  try {
    const { data, error } = await supabaseClient.rpc('save_declaracion', {
      p_empresa_id: empresaId,
      p_tipo: 'ATS',
      p_anio: anio,
      p_mes: mes,
      p_estado: estado,
      p_archivo_url: archivoUrl,
      p_archivo_nombre: archivoNombre,
      p_datos_resumen: datosResumen,
    });

    if (error) {
      console.log('[generate-ats] Error al registrar declaración en BD:', error.message);
    }

    return { data: data as { declaracion_id: string } | null, error };
  } catch (err) {
    console.log('[generate-ats] Excepción al registrar declaración:', err);
    return { data: null, error: err };
  }
}

/**
 * Variante simplificada para registrar errores durante la generación.
 * No retorna el id de la declaración (se usa cuando no se necesita).
 */
async function registrarDeclaracionError(
  supabaseClient: SupabaseClient,
  empresaId: string,
  anio: number,
  mes: number,
  mensajeError: string,
): Promise<void> {
  await registrarDeclaracion(
    supabaseClient,
    empresaId,
    anio,
    mes,
    'ERROR',
    null,
    null,
    { mensaje_error: mensajeError },
  );
}
