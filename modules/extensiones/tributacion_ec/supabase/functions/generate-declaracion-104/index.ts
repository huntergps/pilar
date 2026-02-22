/**
 * PILAR ERP — Edge Function: generate-declaracion-104
 *
 * Genera un PDF de resumen del Formulario 104 (Declaración del IVA)
 * para el período indicado, lo sube al bucket 'tributacion_ec' de Supabase Storage
 * y retorna una URL firmada con validez de 1 hora.
 *
 * El PDF NO reproduce el formulario oficial del SRI. Es un resumen estructurado
 * que el contador usa como referencia al llenar el F-104 en el portal SRI en línea.
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
 *     "nombre_archivo": "F104_202602.pdf",
 *     "declaracion_id": "<uuid>",
 *     "totales": {
 *       "iva_causado": 7500.00,
 *       "credito_tributario": 3000.00,
 *       "impuesto_pagar": 4500.00,
 *       "credito_proximo_mes": 0.00
 *     }
 *   }
 *
 * Errores:
 *   400  PARAMS_INVALIDOS       — empresa_id, anio o mes con formato incorrecto
 *   401  UNAUTHORIZED           — JWT ausente o inválido
 *   403  FORBIDDEN              — sin permiso tributacion.declaracion.generar
 *   405  METHOD_NOT_ALLOWED     — método distinto de POST
 *   422  SIN_DATOS_PERIODO      — módulos Facturación y Compras inactivos
 *   500  F104_DATA_ERROR        — error al llamar get_form_104_data
 *   500  PDF_ERROR              — error al generar el PDF
 *   500  STORAGE_ERROR          — error al subir el PDF o generar URL firmada
 *   500  INTERNAL_ERROR         — error inesperado no clasificado
 *
 * Storage path: tributacion/{empresa_id}/f104/F104_{YYYYMM}.pdf
 *
 * Estructura devuelta por get_form_104_data (migración 013):
 *   {
 *     "periodo": { "anio": 2026, "mes": 2 },
 *     "modulos_activos": { "facturacion": true, "compras": true },
 *     "ventas": {
 *       "base_iva0":   5000.00,
 *       "base_iva5":   0.00,
 *       "base_iva15":  50000.00,
 *       "iva_cobrado": 7500.00
 *     },
 *     "compras": {
 *       "base_iva0":          2000.00,
 *       "base_iva5":          0.00,
 *       "base_iva15":         20000.00,
 *       "iva_pagado":         3000.00,
 *       "credito_tributario": 3000.00
 *     },
 *     "liquidacion": {
 *       "iva_causado":          7500.00,
 *       "credito_mes_anterior": 0.00,
 *       "impuesto_pagar":       4500.00,
 *       "credito_proximo_mes":  0.00
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
  fmtPeriodo,
} from '../_shared/form-pdf.ts';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const BUCKET_TRIBUTACION        = 'tributacion_ec';
const SIGNED_URL_EXPIRY_SECONDS = 3600;
const ANIO_MINIMO               = 2020;

// ---------------------------------------------------------------------------
// Paleta de colores del PDF
// ---------------------------------------------------------------------------

const C_BLUE        = rgb(0.008, 0.329, 0.604); // Azul institucional SRI
const C_WHITE       = rgb(1,     1,     1);
const C_GRAY        = rgb(0.4,   0.4,   0.4);
const C_GRAY_BG     = rgb(0.96,  0.96,  0.96);
const C_BORDER      = rgb(0.6,   0.6,   0.6);
const C_GREEN_LIGHT = rgb(0.9,   0.97,  0.9);   // Fondo crédito tributario (saldo a favor)
const C_RED_LIGHT   = rgb(1.0,   0.93,  0.93);  // Fondo impuesto a pagar (deuda fiscal)
const C_RED_DARK    = rgb(0.5,   0.0,   0.0);
const C_GREEN_DARK  = rgb(0.0,   0.4,   0.0);
const C_RED_BORDER  = rgb(0.7,   0.1,   0.1);
const C_GREEN_BORDER = rgb(0.1,  0.5,   0.1);

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

interface F104Params {
  empresa_id: string;
  anio:       number;
  mes:        number;
}

interface F104Ventas {
  base_iva0:   number;
  base_iva5:   number;
  base_iva15:  number;
  iva_cobrado: number;
}

interface F104Compras {
  base_iva0:          number;
  base_iva5:          number;
  base_iva15:         number;
  iva_pagado:         number;
  credito_tributario: number;
}

interface F104Liquidacion {
  iva_causado:          number;
  credito_mes_anterior: number;
  impuesto_pagar:       number;
  credito_proximo_mes:  number;
}

interface F104Data {
  periodo: { anio: number; mes: number };
  modulos_activos: { facturacion: boolean; compras: boolean };
  ventas:      F104Ventas;
  compras:     F104Compras;
  liquidacion: F104Liquidacion;
}

// ---------------------------------------------------------------------------
// Validación de parámetros
// ---------------------------------------------------------------------------

function isValidUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

function validateParams(body: unknown): { params: F104Params } | { validationError: string } {
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
// Generación del PDF F-104
// ---------------------------------------------------------------------------

/**
 * Genera el PDF del Formulario 104 a partir de los datos de la RPC.
 *
 * Estructura:
 *   1. Header SRI "FORMULARIO 104" con período
 *   2. Bloque de identificación (RUC, razón social, período)
 *   3. Sección A: Ventas y IVA generado
 *   4. Sección B: Compras y Crédito Tributario
 *   5. Sección C: Liquidación del IVA
 *   6. Resultado final (impuesto a pagar o crédito siguiente mes)
 *   7. Resumen ejecutivo para trasladar al portal SRI
 *   8. Nota informativa
 *   9. Pie de página
 */
async function generarF104Pdf(
  data:    F104Data,
  empresa: { ruc: string; razon_social: string },
): Promise<Uint8Array> {
  const periodo = fmtPeriodo(data.periodo.mes, data.periodo.anio);

  // Crear documento con header institucional SRI
  const {
    doc, page, fonts,
    contentStartY, pageWidth, contentWidth, margin,
  } = await createFormPdf({
    title:    'FORMULARIO 104 — DECLARACIÓN DEL IMPUESTO AL VALOR AGREGADO',
    subtitle: 'SRI - Servicio de Rentas Internas',
    periodo:  `Período: ${periodo}`,
  });

  let curY = contentStartY;
  const SECTION_GAP = 10;
  const TITLE_H     = 16;
  const PAD         = 6;

  // ── Bloque de identificación ───────────────────────────────────────────────
  const identH = 38;
  page.drawRectangle({
    x: margin, y: curY - identH,
    width: contentWidth, height: identH,
    color: C_GRAY_BG, borderColor: C_BORDER, borderWidth: 0.5,
  });

  const identY1 = curY - 12;
  const identY2 = curY - 26;

  page.drawText('RUC:',      { x: margin + PAD, y: identY1, font: fonts.bold,    size: 7, color: C_GRAY });
  page.drawText(empresa.ruc, { x: margin + PAD + 30, y: identY1, font: fonts.regular, size: 8 });

  const perLabel  = 'PERÍODO:';
  const perLabelW = fonts.bold.widthOfTextAtSize(perLabel, 7);
  page.drawText(perLabel, { x: margin + contentWidth / 2, y: identY1, font: fonts.bold, size: 7, color: C_GRAY });
  page.drawText(periodo,  { x: margin + contentWidth / 2 + perLabelW + 4, y: identY1, font: fonts.regular, size: 8 });

  page.drawText('RAZÓN SOCIAL:', { x: margin + PAD, y: identY2, font: fonts.bold, size: 7, color: C_GRAY });
  page.drawText(empresa.razon_social, { x: margin + PAD + 80, y: identY2, font: fonts.regular, size: 8 });

  curY -= identH + SECTION_GAP;

  // ── SECCIÓN A: Ventas y IVA generado ─────────────────────────────────────
  page.drawRectangle({ x: margin, y: curY - TITLE_H, width: contentWidth, height: TITLE_H, color: C_BLUE });
  page.drawText('A. VENTAS Y IVA GENERADO', { x: margin + PAD, y: curY - TITLE_H + 4, font: fonts.bold, size: 8, color: C_WHITE });

  if (!data.modulos_activos.facturacion) {
    page.drawText('[módulo Facturación no activo — valores en cero]', {
      x: margin + PAD + 210, y: curY - TITLE_H + 4,
      font: fonts.regular, size: 7, color: C_WHITE,
    });
  }
  curY -= TITLE_H + 2;

  const ventas = data.ventas ?? { base_iva0: 0, base_iva5: 0, base_iva15: 0, iva_cobrado: 0 };

  // Tabla ventas por tarifa — columnas: Tarifa | Base Imponible | IVA Generado
  // Totales: 220 + 160 + 152 = 532 pts
  const colWVentas    = [220, 160, 152];
  const ventasHeaders = ['TARIFA IVA', 'BASE IMPONIBLE', 'IVA GENERADO'];
  const ventasRows: string[][] = [
    ['IVA 0% (ventas no gravadas)',  fmtMonto(ventas.base_iva0),  fmtMonto(0)],
    ['IVA 15% (tarifa general)',     fmtMonto(ventas.base_iva15), fmtMonto(ventas.iva_cobrado)],
  ];
  if (ventas.base_iva5 > 0) {
    // Insertar tarifa 5% entre la fila de 0% y 15%
    ventasRows.splice(1, 0, [
      'IVA 5% (tarifa reducida)',
      fmtMonto(ventas.base_iva5),
      fmtMonto(ventas.base_iva5 * 0.05),
    ]);
  }

  curY = drawTable(page, ventasHeaders, ventasRows, margin, curY, colWVentas, fonts);
  curY -= SECTION_GAP / 2;

  // Sub-caja totales ventas (alineada al lado derecho, ancho de las dos últimas columnas)
  const subTotVentasW = 312; // colWVentas[1] + colWVentas[2]
  const subTotVentasX = margin + colWVentas[0];
  curY = drawTotalesBox(page, [
    ['Total base imponible ventas:', fmtMonto(ventas.base_iva0 + ventas.base_iva5 + ventas.base_iva15)],
    ['IVA COBRADO EN VENTAS:',       fmtMonto(ventas.iva_cobrado)],
  ], subTotVentasX, curY, subTotVentasW, fonts);
  curY -= SECTION_GAP;

  // ── SECCIÓN B: Compras y Crédito Tributario ───────────────────────────────
  page.drawRectangle({ x: margin, y: curY - TITLE_H, width: contentWidth, height: TITLE_H, color: C_BLUE });
  page.drawText('B. COMPRAS Y CRÉDITO TRIBUTARIO', { x: margin + PAD, y: curY - TITLE_H + 4, font: fonts.bold, size: 8, color: C_WHITE });

  if (!data.modulos_activos.compras) {
    page.drawText('[módulo Compras no activo — valores en cero]', {
      x: margin + PAD + 230, y: curY - TITLE_H + 4,
      font: fonts.regular, size: 7, color: C_WHITE,
    });
  }
  curY -= TITLE_H + 2;

  const compras = data.compras ?? { base_iva0: 0, base_iva5: 0, base_iva15: 0, iva_pagado: 0, credito_tributario: 0 };

  const colWCompras    = [220, 160, 152];
  const comprasHeaders = ['TARIFA IVA', 'BASE COMPRAS', 'IVA PAGADO'];
  const comprasRows: string[][] = [
    ['IVA 0% (compras no gravadas)', fmtMonto(compras.base_iva0),  fmtMonto(0)],
    ['IVA 15% (tarifa general)',     fmtMonto(compras.base_iva15), fmtMonto(compras.iva_pagado)],
  ];
  if (compras.base_iva5 > 0) {
    comprasRows.splice(1, 0, [
      'IVA 5% (tarifa reducida)',
      fmtMonto(compras.base_iva5),
      fmtMonto(compras.base_iva5 * 0.05),
    ]);
  }

  curY = drawTable(page, comprasHeaders, comprasRows, margin, curY, colWCompras, fonts);
  curY -= SECTION_GAP / 2;

  const subTotComprasW = 312;
  const subTotComprasX = margin + colWCompras[0];
  curY = drawTotalesBox(page, [
    ['Total base imponible compras:', fmtMonto(compras.base_iva0 + compras.base_iva5 + compras.base_iva15)],
    ['IVA PAGADO EN COMPRAS:',        fmtMonto(compras.iva_pagado)],
    ['CRÉDITO TRIBUTARIO DISPONIBLE:', fmtMonto(compras.credito_tributario)],
  ], subTotComprasX, curY, subTotComprasW, fonts);
  curY -= SECTION_GAP;

  // ── SECCIÓN C: Liquidación del IVA ────────────────────────────────────────
  page.drawRectangle({ x: margin, y: curY - TITLE_H, width: contentWidth, height: TITLE_H, color: C_BLUE });
  page.drawText('C. LIQUIDACIÓN DEL IVA', { x: margin + PAD, y: curY - TITLE_H + 4, font: fonts.bold, size: 8, color: C_WHITE });
  curY -= TITLE_H + 2;

  const liq = data.liquidacion ?? { iva_causado: 0, credito_mes_anterior: 0, impuesto_pagar: 0, credito_proximo_mes: 0 };

  // Tabla de liquidación: proceso de cálculo paso a paso
  curY = drawTable(
    page,
    ['CONCEPTO', 'MONTO'],
    [
      ['(+) IVA causado (IVA cobrado en ventas)',    fmtMonto(liq.iva_causado)],
      ['(-) Crédito tributario período actual',      fmtMonto(compras.credito_tributario)],
      ['(-) Crédito tributario mes anterior',        fmtMonto(liq.credito_mes_anterior)],
    ],
    margin, curY,
    [280, 252],
    fonts,
  );
  curY -= SECTION_GAP / 2;

  // ── Resultado final (caja con color según si hay impuesto o crédito) ───────
  const hayImpuesto    = liq.impuesto_pagar    > 0;
  const hayCreditoNext = liq.credito_proximo_mes > 0;

  const RESULT_BOX_W = 320;
  const RESULT_BOX_H = 24;
  const RESULT_BOX_X = margin + contentWidth - RESULT_BOX_W;

  if (hayImpuesto) {
    // Deuda fiscal: fondo rojo
    page.drawRectangle({
      x: RESULT_BOX_X, y: curY - RESULT_BOX_H,
      width: RESULT_BOX_W, height: RESULT_BOX_H,
      color: C_RED_LIGHT, borderColor: C_RED_BORDER, borderWidth: 1.0,
    });
    page.drawText('IMPUESTO A PAGAR:', { x: RESULT_BOX_X + PAD, y: curY - 15, font: fonts.bold, size: 9, color: C_RED_DARK });
    const valW = fonts.bold.widthOfTextAtSize(fmtMonto(liq.impuesto_pagar), 11);
    page.drawText(fmtMonto(liq.impuesto_pagar), {
      x: RESULT_BOX_X + RESULT_BOX_W - valW - PAD, y: curY - 15,
      font: fonts.bold, size: 11, color: C_RED_DARK,
    });
  } else if (hayCreditoNext) {
    // Saldo a favor: fondo verde
    page.drawRectangle({
      x: RESULT_BOX_X, y: curY - RESULT_BOX_H,
      width: RESULT_BOX_W, height: RESULT_BOX_H,
      color: C_GREEN_LIGHT, borderColor: C_GREEN_BORDER, borderWidth: 1.0,
    });
    page.drawText('CRÉDITO PARA SIGUIENTE MES:', { x: RESULT_BOX_X + PAD, y: curY - 15, font: fonts.bold, size: 9, color: C_GREEN_DARK });
    const valW = fonts.bold.widthOfTextAtSize(fmtMonto(liq.credito_proximo_mes), 11);
    page.drawText(fmtMonto(liq.credito_proximo_mes), {
      x: RESULT_BOX_X + RESULT_BOX_W - valW - PAD, y: curY - 15,
      font: fonts.bold, size: 11, color: C_GREEN_DARK,
    });
  } else {
    // Declaración en cero
    page.drawRectangle({
      x: RESULT_BOX_X, y: curY - RESULT_BOX_H,
      width: RESULT_BOX_W, height: RESULT_BOX_H,
      color: C_GRAY_BG, borderColor: C_BORDER, borderWidth: 0.5,
    });
    page.drawText('DECLARACIÓN EN CERO:', { x: RESULT_BOX_X + PAD, y: curY - 15, font: fonts.bold, size: 9, color: C_GRAY });
    page.drawText('$ 0,00', { x: RESULT_BOX_X + RESULT_BOX_W - 45, y: curY - 15, font: fonts.bold, size: 9, color: C_GRAY });
  }

  curY -= RESULT_BOX_H + SECTION_GAP;

  // ── Resumen para trasladar al portal SRI ──────────────────────────────────
  const creditoAplicado = compras.credito_tributario + liq.credito_mes_anterior;
  const resultadoLabel  = hayImpuesto
    ? `PAGAR: ${fmtMonto(liq.impuesto_pagar)}`
    : `CRÉDITO: ${fmtMonto(liq.credito_proximo_mes)}`;

  curY = drawTable(
    page,
    ['VALORES A TRASLADAR AL PORTAL SRI EN LÍNEA', 'MONTO'],
    [
      ['(=) IVA causado',                            fmtMonto(liq.iva_causado)],
      ['(-) Crédito tributario total aplicado',      fmtMonto(creditoAplicado)],
      ['(=) Resultado: impuesto a pagar / crédito',  resultadoLabel],
    ],
    margin, curY,
    [320, 212],
    fonts,
  );
  curY -= SECTION_GAP;

  // ── Nota informativa ──────────────────────────────────────────────────────
  const notaText =
    'Este documento es un RESUMEN generado por PILAR ERP para uso de referencia del contador. ' +
    'No constituye el formulario oficial del SRI. Los valores deben ser ingresados en el portal ' +
    'SRI en línea (www.sri.gob.ec) en la sección Declaraciones → Formulario 104. ' +
    'Verifique el crédito del mes anterior con la declaración del período previo.';

  drawNota(page, notaText, margin, curY, contentWidth, fonts);

  // ── Pie de página ─────────────────────────────────────────────────────────
  drawFooter(page, fonts, 1, 1, pageWidth);

  // Metadatos del documento
  doc.setTitle(`F-104 ${periodo} — ${empresa.ruc}`);
  doc.setSubject(`Declaración IVA — Período ${periodo}`);

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
 * Registra o actualiza una declaración F_104 en declaraciones_tributarias.
 * Usa supabaseClient (RLS activo) para que el registro quede bajo el contexto
 * del usuario que solicitó la generación.
 *
 * El campo credito_proximo_mes en datos_resumen es leído por get_form_104_data
 * del período siguiente para calcular el crédito acumulado.
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
      p_tipo:           'F_104',
      p_anio:           anio,
      p_mes:            mes,
      p_estado:         estado,
      p_archivo_url:    archivoUrl,
      p_archivo_nombre: archivoNombre,
      p_datos_resumen:  datosResumen,
    });

    if (error) {
      console.log('[generate-declaracion-104] Error al registrar declaración en BD:', error.message);
    }

    return { data: data as string | null, error };
  } catch (err) {
    console.log('[generate-declaracion-104] Excepción al registrar declaración:', err);
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
      console.log('[generate-declaracion-104] Error al verificar permiso:', permError.message);
      return errorResponse(500, 'INTERNAL_ERROR', 'Error al verificar permisos');
    }
    if (!hasPerm) {
      return errorResponse(403, 'FORBIDDEN', 'No tiene permiso para generar declaraciones');
    }

    // 8. Obtener datos F-104 via RPC (respeta RLS del empresa_id del usuario)
    console.log(`[generate-declaracion-104] Obteniendo datos F-104 para empresa=${empresa_id}, ${anio}/${mes}`);
    const { data: f104Data, error: f104Error } = await supabaseClient.rpc('get_form_104_data', {
      p_empresa_id: empresa_id,
      p_anio:       anio,
      p_mes:        mes,
    });

    if (f104Error) {
      console.log('[generate-declaracion-104] Error en RPC get_form_104_data:', f104Error.message);
      await registrarDeclaracionError(
        supabaseClient, empresa_id, anio, mes,
        'Error al obtener datos F-104: ' + f104Error.message,
      );
      return errorResponse(500, 'F104_DATA_ERROR', 'Error al obtener datos del período');
    }

    const data = f104Data as F104Data;

    // 9. Validar que al menos uno de los módulos esté activo
    const { facturacion: facturacionActiva, compras: comprasActiva } = data.modulos_activos ?? {};
    if (!facturacionActiva && !comprasActiva) {
      return errorResponse(
        422,
        'SIN_DATOS_PERIODO',
        'Los módulos Facturación y Compras no están activos. ' +
        'Habilite al menos uno de ellos para generar el F-104.',
      );
    }

    // 10. Obtener datos de la empresa para el PDF
    const empresa = await getEmpresaData(supabaseClient, empresa_id);
    if (!empresa) {
      return errorResponse(500, 'INTERNAL_ERROR', 'No se pudo obtener información de la empresa');
    }

    // 11. Construir nombre y path de archivo
    const mesStr      = String(mes).padStart(2, '0');
    const pdfFilename = `F104_${anio}${mesStr}.pdf`;
    const storagePath = `${empresa_id}/f104/${pdfFilename}`;

    console.log(`[generate-declaracion-104] Generando PDF: ${pdfFilename}`);

    // 12. Generar PDF
    let pdfBytes: Uint8Array;
    try {
      pdfBytes = await generarF104Pdf(data, empresa);
    } catch (pdfErr) {
      const msg = pdfErr instanceof Error ? pdfErr.message : 'Error desconocido';
      console.log('[generate-declaracion-104] Error al generar PDF:', msg);
      await registrarDeclaracionError(supabaseClient, empresa_id, anio, mes, 'Error PDF: ' + msg);
      return errorResponse(500, 'PDF_ERROR', 'Error al generar el PDF del F-104');
    }

    console.log(`[generate-declaracion-104] PDF generado (${pdfBytes.length} bytes). Subiendo a Storage...`);

    // 13. Subir PDF a Storage (upsert: true → permite regenerar el mismo período)
    const { error: uploadError } = await supabaseAdmin.storage
      .from(BUCKET_TRIBUTACION)
      .upload(storagePath, pdfBytes, {
        contentType: 'application/pdf',
        upsert: true,
      });

    if (uploadError) {
      console.log('[generate-declaracion-104] Error al subir PDF a Storage:', uploadError.message);
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
      console.log('[generate-declaracion-104] Error al generar URL firmada:', signMsg);
      const { data: errDecl } = await registrarDeclaracion(
        supabaseClient, empresa_id, anio, mes,
        'ERROR', null, pdfFilename, null,
      );
      declaracionId = errDecl ?? null;
      return errorResponse(500, 'STORAGE_ERROR', 'PDF generado pero no se pudo obtener URL de descarga');
    }

    // 15. Datos de resumen para persistir en declaraciones_tributarias
    //     credito_proximo_mes es leído por get_form_104_data del mes siguiente
    const liq = data.liquidacion;
    const datosResumen: Record<string, unknown> = {
      iva_causado:          liq.iva_causado,
      credito_tributario:   data.compras?.credito_tributario ?? 0,
      credito_mes_anterior: liq.credito_mes_anterior,
      impuesto_pagar:       liq.impuesto_pagar,
      credito_proximo_mes:  liq.credito_proximo_mes, // Leído por el período siguiente
      facturacion_activa:   facturacionActiva,
      compras_activa:       comprasActiva,
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
      `[generate-declaracion-104] F-104 generado correctamente. declaracion_id=${declaracionId ?? 'N/A'}`,
    );

    // 17. Respuesta exitosa
    return jsonResponse(200, {
      success:        true,
      url:            signedData.signedUrl,
      nombre_archivo: pdfFilename,
      declaracion_id: declaracionId,
      totales: {
        iva_causado:         liq.iva_causado,
        credito_tributario:  data.compras?.credito_tributario ?? 0,
        impuesto_pagar:      liq.impuesto_pagar,
        credito_proximo_mes: liq.credito_proximo_mes,
      },
    });

  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Error desconocido';
    console.log('[generate-declaracion-104] Error inesperado:', msg);
    return jsonResponse(500, {
      success:        false,
      error:          'INTERNAL_ERROR',
      detail:         'Error procesando la solicitud',
      declaracion_id: declaracionId,
    });
  }
});
