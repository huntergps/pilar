/**
 * PILAR ERP — Edge Function: generate-declaracion-103
 *
 * Genera un PDF de resumen del Formulario 103 (Retenciones en la Fuente)
 * para el período indicado, lo sube al bucket 'tributacion_ec' de Supabase Storage
 * y retorna una URL firmada con validez de 1 hora.
 *
 * El PDF NO reproduce el formulario oficial del SRI. Es un resumen estructurado
 * que el contador usa como referencia al llenar el F-103 en el portal SRI en línea.
 *
 * Método:  POST
 * Auth:    JWT requerido (verify_jwt: true)
 * Permiso: tributacion.declaracion.generar
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
 *     "nombre_archivo": "F103_202602.pdf",
 *     "declaracion_id": "<uuid>",
 *     "totales": {
 *       "base_imponible_total": 5000.00,
 *       "valor_retenido_total": 500.00,
 *       "num_codigos": 3
 *     }
 *   }
 *
 * Errores:
 *   400  PARAMS_INVALIDOS       — empresa_id, anio o mes con formato incorrecto
 *   401  UNAUTHORIZED           — JWT ausente o inválido
 *   403  FORBIDDEN              — sin permiso tributacion.declaracion.generar
 *   405  METHOD_NOT_ALLOWED     — método distinto de POST
 *   422  SIN_DATOS_PERIODO      — módulo Compras no activo
 *   500  F103_DATA_ERROR        — error al llamar get_form_103_data
 *   500  PDF_ERROR              — error al generar el PDF
 *   500  STORAGE_ERROR          — error al subir el PDF o generar URL firmada
 *   500  INTERNAL_ERROR         — error inesperado no clasificado
 *
 * Storage path: tributacion/{empresa_id}/f103/F103_{YYYYMM}.pdf
 *
 * Estructura devuelta por get_form_103_data (migración 013):
 *   {
 *     "periodo": { "anio": 2026, "mes": 2 },
 *     "modulos_activos": { "compras": true },
 *     "retenciones_por_codigo": [
 *       {
 *         "codigo_retencion": "303",
 *         "descripcion": "Honorarios profesionales",
 *         "base_imponible": 5000.00,
 *         "porcentaje": 10.00,
 *         "valor_retenido": 500.00
 *       }
 *     ],
 *     "totales": {
 *       "base_imponible_total": 5000.00,
 *       "valor_retenido_total": 500.00
 *     }
 *   }
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { rgb } from 'npm:pdf-lib@1.17.1';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import {
  createFormPdf,
  drawTable,
  drawTotalesBox,
  drawNota,
  drawFooter,
  finalizePdf,
  fmtMonto,
  fmtPct,
  fmtPeriodo,
} from '../_shared/form-pdf.ts';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const BUCKET_TRIBUTACION        = 'tributacion_ec';
const SIGNED_URL_EXPIRY_SECONDS = 3600;
const ANIO_MINIMO               = 2020;

// Paleta de colores reutilizada en el PDF
const C_BLUE    = rgb(0.008, 0.329, 0.604);
const C_WHITE   = rgb(1,     1,     1);
const C_GRAY    = rgb(0.4,   0.4,   0.4);
const C_GRAY_BG = rgb(0.96,  0.96,  0.96);
const C_BORDER  = rgb(0.6,   0.6,   0.6);

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
// Tipos internos
// ---------------------------------------------------------------------------

interface F103Params {
  empresa_id: string;
  anio:       number;
  mes:        number;
}

interface RetencionPorCodigo {
  codigo_retencion: string;
  descripcion:      string;
  base_imponible:   number;
  porcentaje:       number;
  valor_retenido:   number;
}

interface F103Data {
  periodo: { anio: number; mes: number };
  modulos_activos: { compras: boolean };
  retenciones_por_codigo: RetencionPorCodigo[];
  totales: {
    base_imponible_total: number;
    valor_retenido_total: number;
  };
}

// ---------------------------------------------------------------------------
// Validación de parámetros
// ---------------------------------------------------------------------------

function isValidUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

function validateParams(body: unknown): { params: F103Params } | { validationError: string } {
  if (typeof body !== 'object' || body === null) {
    return { validationError: 'El body debe ser un objeto JSON' };
  }
  const raw = body as Record<string, unknown>;

  if (typeof raw.empresa_id !== 'string' || !isValidUuid(raw.empresa_id)) {
    return { validationError: 'empresa_id debe ser un UUID válido' };
  }

  const anio = Number(raw.anio);
  const anioActual = new Date().getFullYear();
  if (!Number.isInteger(anio) || anio < ANIO_MINIMO || anio > anioActual + 1) {
    return { validationError: `anio debe ser un número entero entre ${ANIO_MINIMO} y ${anioActual + 1}` };
  }

  const mes = Number(raw.mes);
  if (!Number.isInteger(mes) || mes < 1 || mes > 12) {
    return { validationError: 'mes debe ser un número entero entre 1 y 12' };
  }

  return { params: { empresa_id: raw.empresa_id, anio, mes } };
}

// ---------------------------------------------------------------------------
// Generación del PDF F-103
// ---------------------------------------------------------------------------

/**
 * Genera el PDF del Formulario 103 a partir de los datos de la RPC.
 *
 * Estructura:
 *   1. Header SRI "FORMULARIO 103" con período
 *   2. Bloque de identificación (RUC, razón social, período)
 *   3. Barra de título de sección + tabla de retenciones por código
 *   4. Caja de totales (alineada a la derecha)
 *   5. Nota informativa
 *   6. Pie de página
 */
async function generarF103Pdf(
  data:    F103Data,
  empresa: { ruc: string; razon_social: string },
): Promise<Uint8Array> {
  const periodo = fmtPeriodo(data.periodo.mes, data.periodo.anio);

  // Crear documento con header institucional SRI
  const {
    doc, page, fonts,
    contentStartY, pageWidth, contentWidth, margin,
  } = await createFormPdf({
    title:    'FORMULARIO 103 — RETENCIONES EN LA FUENTE',
    subtitle: 'SRI - Servicio de Rentas Internas',
    periodo:  `Período: ${periodo}`,
  });

  let curY = contentStartY;
  const SECTION_GAP = 10;
  const PAD         = 6;

  // ── Bloque de identificación ───────────────────────────────────────────────
  const identH = 38;
  page.drawRectangle({
    x: margin, y: curY - identH,
    width: contentWidth, height: identH,
    color: C_GRAY_BG,
    borderColor: C_BORDER,
    borderWidth: 0.5,
  });

  const identY1 = curY - 12;
  const identY2 = curY - 26;

  // RUC (izquierda)
  page.drawText('RUC:',     { x: margin + PAD, y: identY1, font: fonts.bold,    size: 7, color: C_GRAY });
  page.drawText(empresa.ruc, { x: margin + PAD + 30, y: identY1, font: fonts.regular, size: 8 });

  // Período (centro-derecha)
  const perLabel  = 'PERÍODO:';
  const perLabelW = fonts.bold.widthOfTextAtSize(perLabel, 7);
  page.drawText(perLabel, { x: margin + contentWidth / 2, y: identY1, font: fonts.bold, size: 7, color: C_GRAY });
  page.drawText(periodo,  { x: margin + contentWidth / 2 + perLabelW + 4, y: identY1, font: fonts.regular, size: 8 });

  // Razón social
  page.drawText('RAZÓN SOCIAL:', { x: margin + PAD, y: identY2, font: fonts.bold, size: 7, color: C_GRAY });
  page.drawText(empresa.razon_social, { x: margin + PAD + 80, y: identY2, font: fonts.regular, size: 8 });

  curY -= identH + SECTION_GAP;

  // ── Barra de sección ──────────────────────────────────────────────────────
  const TITLE_H = 16;
  page.drawRectangle({ x: margin, y: curY - TITLE_H, width: contentWidth, height: TITLE_H, color: C_BLUE });
  page.drawText(
    'RETENCIONES EN LA FUENTE — DETALLE POR CÓDIGO',
    { x: margin + PAD, y: curY - TITLE_H + 4, font: fonts.bold, size: 8, color: C_WHITE },
  );
  curY -= TITLE_H + 2;

  // ── Tabla de retenciones ──────────────────────────────────────────────────
  const retenciones = data.retenciones_por_codigo ?? [];

  if (retenciones.length === 0) {
    // Bloque informativo para declaración en cero / sin datos
    const zeroH = 24;
    page.drawRectangle({ x: margin, y: curY - zeroH, width: contentWidth, height: zeroH, color: C_GRAY_BG });
    page.drawText(
      'Sin retenciones registradas para el período. Se genera declaración en cero.',
      { x: margin + PAD + 2, y: curY - 15, font: fonts.regular, size: 8, color: C_GRAY },
    );
    curY -= zeroH + SECTION_GAP;
  } else {
    // Columnas: Código | Descripción | Base Imponible | % Retención | Valor Retenido
    // Total: 60 + 242 + 80 + 70 + 80 = 532 pts (contentWidth Letter)
    const COL_WIDTHS = [60, 242, 80, 70, 80];
    const HEADERS    = ['CÓDIGO', 'DESCRIPCIÓN', 'BASE IMPONIBLE', '% RETENCIÓN', 'VAL. RETENIDO'];

    const tableRows: string[][] = retenciones.map((r) => [
      r.codigo_retencion,
      r.descripcion,
      fmtMonto(r.base_imponible),
      fmtPct(r.porcentaje),
      fmtMonto(r.valor_retenido),
    ]);

    curY = drawTable(page, HEADERS, tableRows, margin, curY, COL_WIDTHS, fonts);
    curY -= SECTION_GAP;
  }

  // ── Caja de totales (alineada a la derecha) ───────────────────────────────
  const totales     = data.totales;
  const totalesBoxW = 280;
  const totalesBoxX = margin + contentWidth - totalesBoxW;

  const totalesRows: Array<[string, string]> = [
    ['Total base imponible:',  fmtMonto(totales.base_imponible_total)],
    ['TOTAL VALOR RETENIDO:',  fmtMonto(totales.valor_retenido_total)],
  ];

  curY = drawTotalesBox(page, totalesRows, totalesBoxX, curY, totalesBoxW, fonts);
  curY -= SECTION_GAP;

  // ── Nota informativa ──────────────────────────────────────────────────────
  const notaText =
    'Este documento es un RESUMEN generado por PILAR ERP para uso de referencia del contador. ' +
    'No constituye el formulario oficial del SRI. Debe ser ingresado manualmente en el portal ' +
    'SRI en línea (www.sri.gob.ec) en la sección Declaraciones → Formulario 103.';

  drawNota(page, notaText, margin, curY, contentWidth, fonts);

  // ── Pie de página ─────────────────────────────────────────────────────────
  drawFooter(page, fonts, 1, 1, pageWidth);

  // Metadatos del documento
  doc.setTitle(`F-103 ${periodo} — ${empresa.ruc}`);
  doc.setSubject(`Retenciones en la Fuente — Período ${periodo}`);

  return finalizePdf(doc);
}

// ---------------------------------------------------------------------------
// Helper: obtener datos básicos de la empresa
// ---------------------------------------------------------------------------

async function getEmpresaData(
  supabaseClient: SupabaseClient,
  empresaId:      string,
): Promise<{ ruc: string; razon_social: string } | null> {
  const { data, error } = await supabaseClient
    .from('empresas')
    .select('ruc, razon_social, nombre')
    .eq('id', empresaId)
    .single();

  if (error || !data) return null;

  return {
    ruc:          data.ruc ?? '',
    razon_social: data.razon_social ?? data.nombre ?? 'Sin nombre',
  };
}

// ---------------------------------------------------------------------------
// Helpers para registrar la declaración en BD
// ---------------------------------------------------------------------------

/**
 * Registra o actualiza una declaración F_103 en declaraciones_tributarias.
 * Usa supabaseClient (RLS activo) para que el registro quede bajo el contexto
 * del usuario que solicitó la generación.
 */
async function registrarDeclaracion(
  supabaseClient: SupabaseClient,
  empresaId:      string,
  anio:           number,
  mes:            number,
  estado:         string,
  archivoUrl:     string | null,
  archivoNombre:  string | null,
  datosResumen:   Record<string, unknown> | null,
): Promise<{ data: string | null; error: unknown }> {
  try {
    const { data, error } = await supabaseClient.rpc('save_declaracion', {
      p_empresa_id:     empresaId,
      p_tipo:           'F_103',
      p_anio:           anio,
      p_mes:            mes,
      p_estado:         estado,
      p_archivo_url:    archivoUrl,
      p_archivo_nombre: archivoNombre,
      p_datos_resumen:  datosResumen,
    });

    if (error) {
      console.log('[generate-declaracion-103] Error al registrar declaración en BD:', error.message);
    }

    return { data: data as string | null, error };
  } catch (err) {
    console.log('[generate-declaracion-103] Excepción al registrar declaración:', err);
    return { data: null, error: err };
  }
}

/**
 * Variante simplificada para registrar errores durante la generación.
 */
async function registrarDeclaracionError(
  supabaseClient: SupabaseClient,
  empresaId:      string,
  anio:           number,
  mes:            number,
  mensajeError:   string,
): Promise<void> {
  await registrarDeclaracion(
    supabaseClient, empresaId, anio, mes,
    'ERROR', null, null,
    { mensaje_error: mensajeError },
  );
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // 1. CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  // 2. Solo POST
  if (req.method !== 'POST') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Solo se acepta POST');
  }

  // 3. Header de autorización obligatorio (verify_jwt: true en deploy)
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse(401, 'UNAUTHORIZED', 'Token de autorización requerido');
  }

  // 4. Construir clientes Supabase
  //    supabaseClient: actúa con el JWT del llamador (RLS activo, RPCs de negocio)
  //    supabaseAdmin:  service_role, para Storage
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
      { p_permiso: 'tributacion.declaracion.generar' },
    );
    if (permError) {
      console.log('[generate-declaracion-103] Error al verificar permiso:', permError.message);
      return errorResponse(500, 'INTERNAL_ERROR', 'Error al verificar permisos');
    }
    if (!hasPerm) {
      return errorResponse(403, 'FORBIDDEN', 'No tiene permiso para generar declaraciones');
    }

    // 8. Obtener datos F-103 via RPC (respeta RLS del empresa_id del usuario)
    console.log(`[generate-declaracion-103] Obteniendo datos F-103 para empresa=${empresa_id}, ${anio}/${mes}`);
    const { data: f103Data, error: f103Error } = await supabaseClient.rpc('get_form_103_data', {
      p_empresa_id: empresa_id,
      p_anio:       anio,
      p_mes:        mes,
    });

    if (f103Error) {
      console.log('[generate-declaracion-103] Error en RPC get_form_103_data:', f103Error.message);
      await registrarDeclaracionError(
        supabaseClient, empresa_id, anio, mes,
        'Error al obtener datos F-103: ' + f103Error.message,
      );
      return errorResponse(500, 'F103_DATA_ERROR', 'Error al obtener datos del período');
    }

    const data = f103Data as F103Data;

    // 9. Validar que el módulo Compras esté activo
    if (!data.modulos_activos?.compras) {
      return errorResponse(
        422,
        'SIN_DATOS_PERIODO',
        'El módulo Compras no está activo. Habilite Compras para generar el F-103.',
      );
    }

    // Nota: se permite generar el PDF aunque no haya retenciones (declaración en cero)
    const retenciones = data.retenciones_por_codigo ?? [];
    if (retenciones.length === 0) {
      console.log('[generate-declaracion-103] Sin retenciones para el período — se genera declaración en cero');
    }

    // 10. Obtener datos de la empresa para el PDF
    const empresa = await getEmpresaData(supabaseClient, empresa_id);
    if (!empresa) {
      return errorResponse(500, 'INTERNAL_ERROR', 'No se pudo obtener información de la empresa');
    }

    // 11. Construir nombre y path de archivo
    const mesStr      = String(mes).padStart(2, '0');
    const pdfFilename = `F103_${anio}${mesStr}.pdf`;
    const storagePath = `${empresa_id}/f103/${pdfFilename}`;

    console.log(`[generate-declaracion-103] Generando PDF: ${pdfFilename}`);

    // 12. Generar PDF
    let pdfBytes: Uint8Array;
    try {
      pdfBytes = await generarF103Pdf(data, empresa);
    } catch (pdfErr) {
      const msg = pdfErr instanceof Error ? pdfErr.message : 'Error desconocido';
      console.log('[generate-declaracion-103] Error al generar PDF:', msg);
      await registrarDeclaracionError(supabaseClient, empresa_id, anio, mes, 'Error PDF: ' + msg);
      return errorResponse(500, 'PDF_ERROR', 'Error al generar el PDF del F-103');
    }

    console.log(`[generate-declaracion-103] PDF generado (${pdfBytes.length} bytes). Subiendo a Storage...`);

    // 13. Subir PDF a Storage (upsert: true → permite regenerar el mismo período)
    const { error: uploadError } = await supabaseAdmin.storage
      .from(BUCKET_TRIBUTACION)
      .upload(storagePath, pdfBytes, {
        contentType: 'application/pdf',
        upsert: true,
      });

    if (uploadError) {
      console.log('[generate-declaracion-103] Error al subir PDF a Storage:', uploadError.message);
      const { data: errDecl } = await registrarDeclaracion(
        supabaseClient, empresa_id, anio, mes,
        'ERROR', null, pdfFilename, null,
      );
      declaracionId = errDecl ?? null;
      return errorResponse(500, 'STORAGE_ERROR', 'No se pudo subir el PDF a Storage');
    }

    // 14. Crear URL firmada (1 hora)
    const { data: signedData, error: signError } = await supabaseAdmin.storage
      .from(BUCKET_TRIBUTACION)
      .createSignedUrl(storagePath, SIGNED_URL_EXPIRY_SECONDS);

    if (signError || !signedData?.signedUrl) {
      const signMsg = signError?.message ?? 'No se pudo obtener URL firmada';
      console.log('[generate-declaracion-103] Error al generar URL firmada:', signMsg);
      const { data: errDecl } = await registrarDeclaracion(
        supabaseClient, empresa_id, anio, mes,
        'ERROR', null, pdfFilename, null,
      );
      declaracionId = errDecl ?? null;
      return errorResponse(500, 'STORAGE_ERROR', 'PDF generado pero no se pudo obtener URL de descarga');
    }

    // 15. Datos de resumen para persistir en declaraciones_tributarias
    const datosResumen = {
      base_imponible_total: data.totales.base_imponible_total,
      valor_retenido_total: data.totales.valor_retenido_total,
      num_codigos:          retenciones.length,
    };

    // 16. Registrar la declaración exitosa en BD
    //     Si falla, no bloquear la respuesta — el PDF ya está en Storage
    const { data: declId } = await registrarDeclaracion(
      supabaseClient, empresa_id, anio, mes,
      'GENERADA', signedData.signedUrl, pdfFilename,
      datosResumen,
    );
    declaracionId = declId ?? null;

    console.log(
      `[generate-declaracion-103] F-103 generado correctamente. declaracion_id=${declaracionId ?? 'N/A'}`,
    );

    // 17. Respuesta exitosa
    return jsonResponse(200, {
      success:        true,
      url:            signedData.signedUrl,
      nombre_archivo: pdfFilename,
      declaracion_id: declaracionId,
      totales:        datosResumen,
    });

  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Error desconocido';
    console.log('[generate-declaracion-103] Error inesperado:', msg);
    return jsonResponse(500, {
      success:        false,
      error:          'INTERNAL_ERROR',
      detail:         'Error procesando la solicitud',
      declaracion_id: declaracionId,
    });
  }
});
