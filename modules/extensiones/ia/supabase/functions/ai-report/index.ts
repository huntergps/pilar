/**
 * PILAR ERP — Edge Function: ai-report
 *
 * Genera reportes e insights analíticos usando IA sobre los datos del ERP.
 * El sistema consulta la base de datos del período indicado, estructura los
 * datos como contexto y llama al LLM para generar análisis, tendencias y
 * recomendaciones de negocio.
 *
 * Método:  POST
 * Auth:    verify_jwt: true
 *
 * Body:
 *   empresa_id    : UUID de la empresa
 *   tipo_reporte  : Tipo de reporte (ver TipoReporte)
 *   parametros    : Parámetros específicos del reporte (fechas, límites, etc.)
 *
 * Tipos de reporte:
 *   resumen_ventas        → Análisis de ventas del período
 *   top_clientes          → Top 10 clientes por facturación
 *   top_productos         → Top 10 productos más vendidos
 *   cash_flow_proyeccion  → Proyección de flujo de caja próximos 30 días
 *   anomalias_ventas      → Detectar ventas inusuales (picos, caídas, patrones)
 *   recomendaciones_crm   → Clientes que no han comprado en N días
 *
 * Respuesta exitosa (200):
 *   {
 *     tipo: string,
 *     periodo: string,
 *     analisis: string,
 *     puntos_clave: string[],
 *     recomendaciones: string[],
 *     datos_raw: Record<string, unknown>
 *   }
 *
 * Errores posibles:
 *   405  METHOD_NOT_ALLOWED
 *   400  BODY_INVALIDO
 *   400  CAMPOS_REQUERIDOS
 *   400  TIPO_REPORTE_INVALIDO
 *   401  UNAUTHORIZED
 *   500  OPENAI_ERROR
 *   500  DB_ERROR
 *   500  INTERNAL_ERROR
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { chatCompletion, fmtUSD } from '../_shared/ai-helpers.ts';

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

type TipoReporte =
  | 'resumen_ventas'
  | 'top_clientes'
  | 'top_productos'
  | 'cash_flow_proyeccion'
  | 'anomalias_ventas'
  | 'recomendaciones_crm';

const TIPOS_REPORTE_VALIDOS: TipoReporte[] = [
  'resumen_ventas',
  'top_clientes',
  'top_productos',
  'cash_flow_proyeccion',
  'anomalias_ventas',
  'recomendaciones_crm',
];

interface ReportRequest {
  empresa_id: string;
  tipo_reporte: TipoReporte;
  parametros: {
    fecha_desde?: string;     // ISO date string: '2026-01-01'
    fecha_hasta?: string;     // ISO date string: '2026-02-28'
    dias_sin_compra?: number; // Para recomendaciones_crm, default: 60
    limite?: number;          // Para top_X, default: 10
  };
}

interface ReportResponse {
  tipo: string;
  periodo: string;
  analisis: string;
  puntos_clave: string[];
  recomendaciones: string[];
  datos_raw: Record<string, unknown>;
}

interface DatosReporte {
  datos: Record<string, unknown>;
  contextoTexto: string;
  periodoDescripcion: string;
  promptEspecifico: string;
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

/**
 * Formatea un período de fechas para mostrarlo en el reporte.
 * Ej: '2026-01-01' / '2026-02-28' → 'Enero - Febrero 2026'
 */
function formatearPeriodo(desde?: string, hasta?: string): string {
  if (!desde && !hasta) return 'Período no especificado';

  const meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  const formatFecha = (iso: string): string => {
    const d = new Date(iso + 'T00:00:00Z');
    return `${meses[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
  };

  if (desde && hasta) {
    const dDesde = formatFecha(desde);
    const dHasta = formatFecha(hasta);
    return dDesde === dHasta ? dDesde : `${dDesde} - ${dHasta}`;
  }
  return desde ? `Desde ${formatFecha(desde)}` : `Hasta ${formatFecha(hasta!)}`;
}

// ---------------------------------------------------------------------------
// Obtención de datos por tipo de reporte
// ---------------------------------------------------------------------------

async function obtenerDatosResumenVentas(
  supabaseAdmin: SupabaseClient,
  empresaId: string,
  params: ReportRequest['parametros'],
): Promise<DatosReporte> {
  const fechaDesde = params.fecha_desde ?? new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0];
  const fechaHasta = params.fecha_hasta ?? new Date().toISOString().split('T')[0];

  const { data, error } = await supabaseAdmin
    .from('facturas')
    .select('total, subtotal, impuesto_total, estado, fecha_emision')
    .eq('empresa_id', empresaId)
    .gte('fecha_emision', fechaDesde)
    .lte('fecha_emision', fechaHasta)
    .in('estado', ['AUTORIZADA', 'COBRADA']);

  if (error) throw new Error(`DB error resumen_ventas: ${error.message}`);

  const facturas = (data ?? []) as Array<{ total: number; subtotal: number; impuesto_total: number; estado: string; fecha_emision: string }>;

  const totalVentas = facturas.reduce((sum, f) => sum + Number(f.total), 0);
  const totalSubtotal = facturas.reduce((sum, f) => sum + Number(f.subtotal), 0);
  const totalImpuesto = facturas.reduce((sum, f) => sum + Number(f.impuesto_total), 0);
  const numFacturas = facturas.length;
  const ticketPromedio = numFacturas > 0 ? totalVentas / numFacturas : 0;

  // Agrupar por mes para tendencia
  const porMes: Record<string, number> = {};
  for (const f of facturas) {
    const mes = f.fecha_emision.slice(0, 7); // 'YYYY-MM'
    porMes[mes] = (porMes[mes] ?? 0) + Number(f.total);
  }

  const datos = {
    total_ventas: totalVentas,
    total_subtotal: totalSubtotal,
    total_impuesto: totalImpuesto,
    num_facturas: numFacturas,
    ticket_promedio: ticketPromedio,
    ventas_por_mes: porMes,
    periodo: { desde: fechaDesde, hasta: fechaHasta },
  };

  const lineasMes = Object.entries(porMes)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([mes, total]) => `  ${mes}: ${fmtUSD(total)}`)
    .join('\n');

  const contextoTexto = `RESUMEN DE VENTAS (${fechaDesde} al ${fechaHasta}):
- Total facturado: ${fmtUSD(totalVentas)}
- Subtotal (sin IVA): ${fmtUSD(totalSubtotal)}
- IVA cobrado: ${fmtUSD(totalImpuesto)}
- Número de facturas: ${numFacturas}
- Ticket promedio: ${fmtUSD(ticketPromedio)}
Ventas por mes:
${lineasMes || '  (sin datos por mes)'}`;

  return {
    datos,
    contextoTexto,
    periodoDescripcion: formatearPeriodo(fechaDesde, fechaHasta),
    promptEspecifico: 'Analiza el desempeño de ventas del período. Identifica tendencias, variaciones mes a mes y el ticket promedio. Da recomendaciones para mejorar.',
  };
}

async function obtenerDatosTopClientes(
  supabaseAdmin: SupabaseClient,
  empresaId: string,
  params: ReportRequest['parametros'],
): Promise<DatosReporte> {
  const fechaDesde = params.fecha_desde ?? new Date(new Date().getFullYear(), 0, 1).toISOString().split('T')[0];
  const fechaHasta = params.fecha_hasta ?? new Date().toISOString().split('T')[0];
  const limite = params.limite ?? 10;

  const { data, error } = await supabaseAdmin
    .from('facturas')
    .select('contacto_id, total, contactos(nombre)')
    .eq('empresa_id', empresaId)
    .gte('fecha_emision', fechaDesde)
    .lte('fecha_emision', fechaHasta)
    .in('estado', ['AUTORIZADA', 'COBRADA']);

  if (error) throw new Error(`DB error top_clientes: ${error.message}`);

  // Agregar por cliente
  const porCliente: Record<string, { nombre: string; total: number; facturas: number }> = {};
  for (const f of (data ?? []) as Array<{ contacto_id: string; total: number; contactos?: { nombre: string } }>) {
    const id = f.contacto_id;
    if (!porCliente[id]) {
      porCliente[id] = { nombre: f.contactos?.nombre ?? 'Desconocido', total: 0, facturas: 0 };
    }
    porCliente[id].total += Number(f.total);
    porCliente[id].facturas++;
  }

  const topClientes = Object.entries(porCliente)
    .map(([id, v]) => ({ id, ...v }))
    .sort((a, b) => b.total - a.total)
    .slice(0, limite);

  const totalGeneral = topClientes.reduce((s, c) => s + c.total, 0);

  const datos = {
    top_clientes: topClientes,
    total_general: totalGeneral,
    periodo: { desde: fechaDesde, hasta: fechaHasta },
  };

  const lineas = topClientes
    .map((c, i) => {
      const pct = totalGeneral > 0 ? ((c.total / totalGeneral) * 100).toFixed(1) : '0.0';
      return `  ${i + 1}. ${c.nombre}: ${fmtUSD(c.total)} (${c.facturas} facturas, ${pct}% del total)`;
    })
    .join('\n');

  const contextoTexto = `TOP ${limite} CLIENTES POR FACTURACIÓN (${fechaDesde} al ${fechaHasta}):
${lineas || '  (sin datos)'}
Total del período: ${fmtUSD(totalGeneral)}`;

  return {
    datos,
    contextoTexto,
    periodoDescripcion: formatearPeriodo(fechaDesde, fechaHasta),
    promptEspecifico: 'Analiza la concentración de clientes, identifica los más valiosos y recomienda estrategias de retención y upselling.',
  };
}

async function obtenerDatosTopProductos(
  supabaseAdmin: SupabaseClient,
  empresaId: string,
  params: ReportRequest['parametros'],
): Promise<DatosReporte> {
  const fechaDesde = params.fecha_desde ?? new Date(new Date().getFullYear(), 0, 1).toISOString().split('T')[0];
  const fechaHasta = params.fecha_hasta ?? new Date().toISOString().split('T')[0];
  const limite = params.limite ?? 10;

  const { data, error } = await supabaseAdmin
    .from('factura_lineas')
    .select('producto_id, cantidad, subtotal, descripcion, facturas!inner(empresa_id, fecha_emision, estado)')
    .eq('facturas.empresa_id', empresaId)
    .gte('facturas.fecha_emision', fechaDesde)
    .lte('facturas.fecha_emision', fechaHasta)
    .in('facturas.estado', ['AUTORIZADA', 'COBRADA']);

  if (error) throw new Error(`DB error top_productos: ${error.message}`);

  // Agregar por producto
  const porProducto: Record<string, { descripcion: string; cantidad: number; subtotal: number; ventas: number }> = {};
  for (const l of (data ?? []) as Array<{ producto_id: string | null; cantidad: number; subtotal: number; descripcion: string }>) {
    const key = l.producto_id ?? `desc:${l.descripcion}`;
    if (!porProducto[key]) {
      porProducto[key] = { descripcion: l.descripcion, cantidad: 0, subtotal: 0, ventas: 0 };
    }
    porProducto[key].cantidad += Number(l.cantidad);
    porProducto[key].subtotal += Number(l.subtotal);
    porProducto[key].ventas++;
  }

  const topProductos = Object.entries(porProducto)
    .map(([id, v]) => ({ id, ...v }))
    .sort((a, b) => b.subtotal - a.subtotal)
    .slice(0, limite);

  const datos = { top_productos: topProductos, periodo: { desde: fechaDesde, hasta: fechaHasta } };

  const lineas = topProductos
    .map((p, i) =>
      `  ${i + 1}. ${p.descripcion}: ${fmtUSD(p.subtotal)} (${p.cantidad} unidades, ${p.ventas} ventas)`
    )
    .join('\n');

  const contextoTexto = `TOP ${limite} PRODUCTOS MÁS VENDIDOS (${fechaDesde} al ${fechaHasta}):
${lineas || '  (sin datos)'}`;

  return {
    datos,
    contextoTexto,
    periodoDescripcion: formatearPeriodo(fechaDesde, fechaHasta),
    promptEspecifico: 'Analiza los productos más vendidos, identifica patrones de demanda y recomienda estrategias de inventario y promoción.',
  };
}

async function obtenerDatosCashFlow(
  supabaseAdmin: SupabaseClient,
  empresaId: string,
  _params: ReportRequest['parametros'],
): Promise<DatosReporte> {
  const hoy = new Date();
  const en30Dias = new Date(hoy);
  en30Dias.setDate(en30Dias.getDate() + 30);

  const fechaHoy = hoy.toISOString().split('T')[0];
  const fecha30 = en30Dias.toISOString().split('T')[0];

  // Cuentas por cobrar próximas 30 días
  const { data: cxcData, error: cxcError } = await supabaseAdmin
    .from('cuentas_por_cobrar')
    .select('saldo_pendiente, fecha_vencimiento')
    .eq('empresa_id', empresaId)
    .eq('estado', 'PENDIENTE')
    .lte('fecha_vencimiento', fecha30)
    .gte('fecha_vencimiento', fechaHoy);

  if (cxcError) throw new Error(`DB error cash_flow CxC: ${cxcError.message}`);

  // Cuentas por pagar próximas 30 días
  const { data: cxpData, error: cxpError } = await supabaseAdmin
    .from('cuentas_por_pagar')
    .select('saldo_pendiente, fecha_vencimiento')
    .eq('empresa_id', empresaId)
    .eq('estado', 'PENDIENTE')
    .lte('fecha_vencimiento', fecha30)
    .gte('fecha_vencimiento', fechaHoy);

  if (cxpError) throw new Error(`DB error cash_flow CxP: ${cxpError.message}`);

  const totalCxC = ((cxcData ?? []) as Array<{ saldo_pendiente: number }>)
    .reduce((s, r) => s + Number(r.saldo_pendiente), 0);
  const totalCxP = ((cxpData ?? []) as Array<{ saldo_pendiente: number }>)
    .reduce((s, r) => s + Number(r.saldo_pendiente), 0);
  const flujoNeto = totalCxC - totalCxP;

  const datos = {
    cxc_proximos_30_dias: totalCxC,
    cxp_proximos_30_dias: totalCxP,
    flujo_neto_proyectado: flujoNeto,
    num_cobros_pendientes: (cxcData ?? []).length,
    num_pagos_pendientes: (cxpData ?? []).length,
    periodo: { desde: fechaHoy, hasta: fecha30 },
  };

  const contextoTexto = `PROYECCIÓN FLUJO DE CAJA — PRÓXIMOS 30 DÍAS (${fechaHoy} al ${fecha30}):
- Cobros esperados (CxC): ${fmtUSD(totalCxC)} (${(cxcData ?? []).length} facturas pendientes)
- Pagos comprometidos (CxP): ${fmtUSD(totalCxP)} (${(cxpData ?? []).length} obligaciones)
- Flujo neto proyectado: ${fmtUSD(flujoNeto)} ${flujoNeto >= 0 ? '(POSITIVO)' : '(NEGATIVO — riesgo de liquidez)'}`;

  return {
    datos,
    contextoTexto,
    periodoDescripcion: `Próximos 30 días (${fechaHoy} al ${fecha30})`,
    promptEspecifico: 'Analiza la liquidez proyectada. Identifica riesgos de flujo de caja negativo y recomienda acciones para mejorar la posición de liquidez.',
  };
}

async function obtenerDatosAnomaliasVentas(
  supabaseAdmin: SupabaseClient,
  empresaId: string,
  params: ReportRequest['parametros'],
): Promise<DatosReporte> {
  const fechaDesde = params.fecha_desde ?? new Date(new Date().getFullYear(), 0, 1).toISOString().split('T')[0];
  const fechaHasta = params.fecha_hasta ?? new Date().toISOString().split('T')[0];

  const { data, error } = await supabaseAdmin
    .from('facturas')
    .select('total, fecha_emision, estado')
    .eq('empresa_id', empresaId)
    .gte('fecha_emision', fechaDesde)
    .lte('fecha_emision', fechaHasta)
    .in('estado', ['AUTORIZADA', 'COBRADA'])
    .order('fecha_emision');

  if (error) throw new Error(`DB error anomalias_ventas: ${error.message}`);

  const facturas = (data ?? []) as Array<{ total: number; fecha_emision: string }>;

  // Agrupar por semana para detectar anomalías
  const porSemana: Record<string, { total: number; count: number }> = {};
  for (const f of facturas) {
    const d = new Date(f.fecha_emision + 'T00:00:00Z');
    // Número de semana del año
    const inicio = new Date(d.getUTCFullYear(), 0, 1);
    const semana = Math.ceil(((d.getTime() - inicio.getTime()) / 86400000 + inicio.getUTCDay() + 1) / 7);
    const key = `${d.getUTCFullYear()}-S${String(semana).padStart(2, '0')}`;
    if (!porSemana[key]) porSemana[key] = { total: 0, count: 0 };
    porSemana[key].total += Number(f.total);
    porSemana[key].count++;
  }

  const semanasOrdenadas = Object.entries(porSemana).sort(([a], [b]) => a.localeCompare(b));
  const totalesSemana = semanasOrdenadas.map(([, v]) => v.total);

  // Calcular media y desviación estándar para detectar anomalías
  const media = totalesSemana.length > 0
    ? totalesSemana.reduce((s, v) => s + v, 0) / totalesSemana.length
    : 0;
  const desviacion = totalesSemana.length > 1
    ? Math.sqrt(totalesSemana.reduce((s, v) => s + Math.pow(v - media, 2), 0) / totalesSemana.length)
    : 0;

  const anomalias = semanasOrdenadas
    .filter(([, v]) => Math.abs(v.total - media) > 2 * desviacion)
    .map(([semana, v]) => ({
      semana,
      total: v.total,
      facturas: v.count,
      desviacion_std: desviacion > 0 ? ((v.total - media) / desviacion).toFixed(2) : '0',
      tipo: v.total > media ? 'PICO' : 'CAIDA',
    }));

  const datos = {
    ventas_por_semana: Object.fromEntries(semanasOrdenadas),
    media_semanal: media,
    desviacion_std: desviacion,
    anomalias_detectadas: anomalias,
    periodo: { desde: fechaDesde, hasta: fechaHasta },
  };

  const contextoTexto = `ANÁLISIS DE ANOMALÍAS EN VENTAS (${fechaDesde} al ${fechaHasta}):
- Media semanal: ${fmtUSD(media)}
- Desviación estándar: ${fmtUSD(desviacion)}
- Anomalías detectadas (>2σ): ${anomalias.length}
${anomalias.length > 0
    ? anomalias.map((a) =>
      `  ${a.semana}: ${fmtUSD(a.total)} [${a.tipo}, ${a.desviacion_std}σ, ${a.facturas} facturas]`
    ).join('\n')
    : '  (no se detectaron anomalías estadísticas)'}`;

  return {
    datos,
    contextoTexto,
    periodoDescripcion: formatearPeriodo(fechaDesde, fechaHasta),
    promptEspecifico: 'Analiza las anomalías detectadas en las ventas semanales. Explica posibles causas (estacionalidad, eventos, descuentos, problemas) y recomienda acciones.',
  };
}

async function obtenerDatosRecomendacionesCrm(
  supabaseAdmin: SupabaseClient,
  empresaId: string,
  params: ReportRequest['parametros'],
): Promise<DatosReporte> {
  const diasSinCompra = params.dias_sin_compra ?? 60;
  const fechaCorte = new Date();
  fechaCorte.setDate(fechaCorte.getDate() - diasSinCompra);
  const fechaCorteStr = fechaCorte.toISOString().split('T')[0];

  // Obtener la última compra por cliente
  const { data, error } = await supabaseAdmin
    .from('facturas')
    .select('contacto_id, fecha_emision, total, contactos(nombre, email, telefono)')
    .eq('empresa_id', empresaId)
    .in('estado', ['AUTORIZADA', 'COBRADA'])
    .order('fecha_emision', { ascending: false });

  if (error) throw new Error(`DB error recomendaciones_crm: ${error.message}`);

  // Última compra por cliente
  const ultimaCompra: Record<string, {
    nombre: string; email?: string; telefono?: string;
    ultima_fecha: string; total_historico: number; num_compras: number;
  }> = {};

  for (const f of (data ?? []) as Array<{
    contacto_id: string; fecha_emision: string; total: number;
    contactos?: { nombre: string; email?: string; telefono?: string };
  }>) {
    const id = f.contacto_id;
    if (!ultimaCompra[id]) {
      ultimaCompra[id] = {
        nombre: f.contactos?.nombre ?? 'Desconocido',
        email: f.contactos?.email,
        telefono: f.contactos?.telefono,
        ultima_fecha: f.fecha_emision,
        total_historico: 0,
        num_compras: 0,
      };
    }
    ultimaCompra[id].total_historico += Number(f.total);
    ultimaCompra[id].num_compras++;
  }

  // Filtrar clientes que no han comprado desde la fecha de corte
  const clientesInactivos = Object.entries(ultimaCompra)
    .filter(([, v]) => v.ultima_fecha < fechaCorteStr)
    .map(([id, v]) => ({
      id,
      ...v,
      dias_inactivo: Math.floor(
        (new Date().getTime() - new Date(v.ultima_fecha + 'T00:00:00Z').getTime()) / 86400000,
      ),
    }))
    .sort((a, b) => b.total_historico - a.total_historico)
    .slice(0, 20); // Top 20 para el reporte

  const datos = {
    clientes_inactivos: clientesInactivos,
    dias_umbral: diasSinCompra,
    total_inactivos: clientesInactivos.length,
    fecha_corte: fechaCorteStr,
  };

  const lineas = clientesInactivos
    .slice(0, 10)
    .map((c) =>
      `  - ${c.nombre}: última compra ${c.ultima_fecha} (${c.dias_inactivo} días), ` +
      `historial: ${fmtUSD(c.total_historico)} en ${c.num_compras} compras`
    )
    .join('\n');

  const contextoTexto = `CLIENTES INACTIVOS (sin comprar en +${diasSinCompra} días, corte: ${fechaCorteStr}):
Total clientes inactivos: ${clientesInactivos.length}
Top 10 por valor histórico:
${lineas || '  (sin clientes inactivos en el período)'}`;

  return {
    datos,
    contextoTexto,
    periodoDescripcion: `Clientes sin compra en ${diasSinCompra}+ días`,
    promptEspecifico: `Analiza los clientes que no han comprado en más de ${diasSinCompra} días. Sugiere estrategias de reactivación personalizadas según su valor histórico.`,
  };
}

// ---------------------------------------------------------------------------
// Parsing de respuesta del LLM (extrae estructura del texto libre)
// ---------------------------------------------------------------------------

function parsearRespuestaLLM(texto: string): {
  analisis: string;
  puntos_clave: string[];
  recomendaciones: string[];
} {
  // El LLM devuelve texto libre. Intentamos extraer secciones si las hay,
  // de lo contrario tratamos el texto completo como análisis.
  const puntosMatch = texto.match(/(?:puntos clave|hallazgos|conclusiones)[:\s]*\n((?:[-•*\d]+\.?\s+.+\n?)+)/i);
  const recomendacionesMatch = texto.match(/(?:recomendaciones?|acciones?|sugerencias?)[:\s]*\n((?:[-•*\d]+\.?\s+.+\n?)+)/i);

  const extractItems = (block: string): string[] =>
    block
      .split('\n')
      .map((l) => l.replace(/^[-•*\d]+\.?\s+/, '').trim())
      .filter((l) => l.length > 0);

  const puntos_clave = puntosMatch ? extractItems(puntosMatch[1]) : [];
  const recomendaciones = recomendacionesMatch ? extractItems(recomendacionesMatch[1]) : [];

  // El análisis principal es el texto sin las secciones de puntos/recomendaciones
  let analisis = texto;
  if (puntosMatch) analisis = analisis.replace(puntosMatch[0], '').trim();
  if (recomendacionesMatch) analisis = analisis.replace(recomendacionesMatch[0], '').trim();

  return { analisis: analisis.trim(), puntos_clave, recomendaciones };
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
  let body: ReportRequest;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, 'BODY_INVALIDO', 'El cuerpo de la solicitud no es JSON válido');
  }

  // 4. Validar campos requeridos
  const { empresa_id, tipo_reporte, parametros } = body;

  if (!empresa_id || !isValidUuid(empresa_id)) {
    return errorResponse(400, 'CAMPOS_REQUERIDOS', 'empresa_id es requerido y debe ser un UUID válido');
  }
  if (!tipo_reporte) {
    return errorResponse(400, 'CAMPOS_REQUERIDOS', 'tipo_reporte es requerido');
  }
  if (!TIPOS_REPORTE_VALIDOS.includes(tipo_reporte)) {
    return errorResponse(
      400,
      'TIPO_REPORTE_INVALIDO',
      `tipo_reporte debe ser uno de: ${TIPOS_REPORTE_VALIDOS.join(', ')}`,
    );
  }

  // 5. Obtener OPENAI_API_KEY
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  if (!apiKey) {
    console.error('[ai-report] OPENAI_API_KEY no configurada');
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

  // 7. Verificar autenticación
  const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
  if (!user || authError) {
    return errorResponse(401, 'UNAUTHORIZED', 'Se requiere autenticación válida');
  }

  try {
    // 8. Obtener datos específicos del tipo de reporte
    let datosReporte: DatosReporte;

    try {
      switch (tipo_reporte) {
        case 'resumen_ventas':
          datosReporte = await obtenerDatosResumenVentas(supabaseAdmin, empresa_id, parametros ?? {});
          break;
        case 'top_clientes':
          datosReporte = await obtenerDatosTopClientes(supabaseAdmin, empresa_id, parametros ?? {});
          break;
        case 'top_productos':
          datosReporte = await obtenerDatosTopProductos(supabaseAdmin, empresa_id, parametros ?? {});
          break;
        case 'cash_flow_proyeccion':
          datosReporte = await obtenerDatosCashFlow(supabaseAdmin, empresa_id, parametros ?? {});
          break;
        case 'anomalias_ventas':
          datosReporte = await obtenerDatosAnomaliasVentas(supabaseAdmin, empresa_id, parametros ?? {});
          break;
        case 'recomendaciones_crm':
          datosReporte = await obtenerDatosRecomendacionesCrm(supabaseAdmin, empresa_id, parametros ?? {});
          break;
        default:
          return errorResponse(400, 'TIPO_REPORTE_INVALIDO', 'Tipo de reporte no implementado');
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[ai-report] Error obteniendo datos para ${tipo_reporte}:`, msg);
      return errorResponse(500, 'DB_ERROR', `Error consultando datos: ${msg}`);
    }

    // 9. Obtener nombre de la empresa
    const { data: empresaData } = await supabaseAdmin
      .from('empresas')
      .select('nombre_comercial, razon_social')
      .eq('id', empresa_id)
      .single();

    const nombreEmpresa: string =
      (empresaData?.nombre_comercial as string) ||
      (empresaData?.razon_social as string) ||
      'Tu empresa';

    const fechaActual = new Date().toLocaleDateString('es-EC', {
      year: 'numeric', month: 'long', day: 'numeric',
      timeZone: 'America/Guayaquil',
    });

    // 10. Construir prompt y llamar al LLM
    const systemPrompt = `Eres PILAR IA, el analista de negocios del ERP PILAR para Ecuador.
Generas reportes ejecutivos concisos y accionables para gerentes y dueños de negocio.

Empresa: ${nombreEmpresa}
Fecha del reporte: ${fechaActual}

DATOS DEL REPORTE:
${datosReporte.contextoTexto}

INSTRUCCIONES:
- Responde en español, tono ejecutivo y profesional
- Sé específico con los números del contexto (no inventes cifras)
- Para montos, usa el formato $X.XXX,XX
- Estructura tu respuesta en: análisis principal, puntos clave y recomendaciones
- Las recomendaciones deben ser concretas y aplicables al contexto Ecuador
- ${datosReporte.promptEspecifico}`;

    let respuestaLLM: string;
    let tokensUsados: number;

    try {
      const result = await chatCompletion(
        [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: `Genera el reporte de tipo "${tipo_reporte}" para el período: ${datosReporte.periodoDescripcion}` },
        ],
        apiKey,
      );
      respuestaLLM = result.content;
      tokensUsados = result.tokens_used;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error('[ai-report] Error en chat completion:', msg);
      return errorResponse(500, 'OPENAI_ERROR', `Error generando reporte: ${msg}`);
    }

    // 11. Parsear respuesta del LLM en estructura
    const { analisis, puntos_clave, recomendaciones } = parsearRespuestaLLM(respuestaLLM);

    // 12. Guardar reporte en ia_reportes
    const reporteGuardado = {
      empresa_id,
      tipo: tipo_reporte,
      parametros: parametros ?? {},
      resultado: {
        periodo: datosReporte.periodoDescripcion,
        analisis,
        puntos_clave,
        recomendaciones,
        datos_raw: datosReporte.datos,
      },
      tokens_usados: tokensUsados,
    };

    const { error: insertError } = await supabaseAdmin
      .from('ia_reportes')
      .insert(reporteGuardado);

    if (insertError) {
      console.warn('[ai-report] Error guardando reporte (no fatal):', insertError.message);
    }

    console.log(
      `[ai-report] Reporte ${tipo_reporte} generado para empresa ${empresa_id}: ${tokensUsados} tokens`,
    );

    // 13. Respuesta al cliente
    const response: ReportResponse = {
      tipo: tipo_reporte,
      periodo: datosReporte.periodoDescripcion,
      analisis,
      puntos_clave,
      recomendaciones,
      datos_raw: datosReporte.datos,
    };

    return jsonResponse(200, response);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[ai-report] Error inesperado:', msg);
    return errorResponse(500, 'INTERNAL_ERROR', 'Error procesando la solicitud');
  }
});
