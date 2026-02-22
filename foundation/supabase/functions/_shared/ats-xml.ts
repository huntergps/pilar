/**
 * PILAR ERP — Shared: ats-xml.ts
 *
 * Builder de XML para el ATS (Anexo Transaccional Simplificado) del SRI Ecuador.
 *
 * Especificación:
 *   - Root element: <iva>
 *   - Encoding declarado en el header XML: ISO-8859-1
 *   - Montos: siempre 2 decimales
 *   - Secciones <ventas>, <compras>, <anulados>: solo se emiten si hay registros
 *   - Elemento <air> dentro de cada compra: solo si hay retenciones en la fuente
 *
 * Funciones exportadas:
 *   buildAtsXml(data: AtsData): string
 *   encodeIso88591(xml: string): Uint8Array
 *
 * Uso:
 *   import { buildAtsXml, encodeIso88591 } from '../_shared/ats-xml.ts';
 */

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

/** Detalle de retención en la fuente (AIR) dentro de una compra. */
export interface AtsDetalleAir {
  /** Código de retención, p.ej. '303', '311', '312'. */
  codRetAir: string;
  /** Base imponible para la retención. */
  baseImpAir: number;
  /** Porcentaje de retención (formato 5,2). */
  porcentajeAir: number;
  /** Valor retenido resultante. */
  valRetAir: number;
}

/** Registro de venta agrupado por cliente y tipo de comprobante. */
export interface AtsVenta {
  /** Tipo de identificación del cliente.
   *  '04'=RUC, '05'=Cédula, '06'=Pasaporte, '07'=Consumidor Final, '08'=Id exterior, '99'=Consumidor Final RISE */
  tpIdCliente: string;
  /** Número de identificación del cliente. */
  idCliente: string;
  /** Indica si el cliente es parte relacionada. 'SI' | 'NO'. Opcional. */
  parteRelVtas?: string;
  /** Tipo de comprobante: '01' Factura, '04' NC, '05' ND, '06' GR, '07' Retención. */
  tipoComprobante: string;
  /** Tipo de emisión: 'E' Electrónica, 'F' Física. */
  tipoEmision: string;
  /** Número total de comprobantes del grupo. */
  numeroComprobantes: number;
  /** Subtotal de ventas no grabadas con IVA (tarifa 0%). */
  baseNoGraIva: number;
  /** Subtotal de ventas exentas de IVA. */
  baseImponible: number;
  /** Subtotal de ventas gravadas con IVA. */
  baseImpGrav: number;
  /** Monto total del IVA generado. */
  montoIva: number;
  /** Valor total de retenciones de IVA que le hicieron al emisor. */
  valorRetIva: number;
  /** Valor total de retenciones en la fuente de renta que le hicieron al emisor. */
  valorRetRenta: number;
  /** Formas de pago utilizadas, p.ej. ['01', '16']. Opcional. */
  formasDePago?: string[];
}

/** Detalle de una compra individual. */
export interface AtsCompra {
  /** Código de sustento tributario, p.ej. '01'=Factura, '02'=LiquidaciónCompra. */
  codSustento: string;
  /** Tipo de identificación del proveedor. */
  tpIdProv: string;
  /** Número de identificación del proveedor. */
  idProv: string;
  /** Indica si el proveedor es parte relacionada. 'SI' | 'NO'. Opcional. */
  parteRel?: string;
  /** Tipo de proveedor. Opcional. */
  tipoProv?: string;
  /** Razón social del proveedor. Opcional. */
  denoProv?: string;
  /** Fecha de registro de la compra en el sistema. Formato: dd/mm/yyyy. */
  fechaRegistro: string;
  /** Tipo de comprobante: '01' Factura, '03' LiquidaciónCompra, '05' ND, '06' GR. */
  tipoComprobante: string;
  /** Número del establecimiento del proveedor (3 dígitos). */
  establecimiento: string;
  /** Punto de emisión del proveedor (3 dígitos). */
  puntoEmision: string;
  /** Número secuencial del comprobante (hasta 9 dígitos). */
  secuencial: string;
  /** Fecha de emisión del comprobante. Formato: dd/mm/yyyy. */
  fechaEmision: string;
  /** Número de autorización del comprobante (3 a 49 caracteres). */
  autorizacion: string;
  /** Base sin IVA (tarifa 0%). */
  baseNoGraIva: number;
  /** Base imponible (exenta). */
  baseImponible: number;
  /** Base gravada con IVA. */
  baseImpGrav: number;
  /** Base exenta de IVA. */
  baseImpExe: number;
  /** Monto de ICE. */
  montoIce: number;
  /** Monto total de IVA. */
  montoIva: number;
  /** Retención IVA 10% en bienes. Opcional. */
  valRetBien10?: number;
  /** Retención IVA 20% en servicios. Opcional. */
  valRetServ20?: number;
  /** Retención total de IVA en bienes. */
  valorRetBienes: number;
  /** Retención IVA 50% en servicios. Opcional. */
  valRetServ50?: number;
  /** Retención total de IVA en servicios. */
  valorRetServicios: number;
  /** Retención IVA 100%. */
  valRetServ100: number;
  /** Valor de retención IVA por nota de crédito. Opcional. */
  valorRetencionNc?: number;
  /** Retenciones en la fuente (renta). Opcional: emite bloque <air> solo si hay valores. */
  detalleAirValues?: AtsDetalleAir[];
  // Datos del comprobante de retención vinculado (todos opcionales)
  /** Establecimiento del comprobante de retención. */
  estabRetencion1?: string;
  /** Punto de emisión del comprobante de retención. */
  ptoEmiRetencion1?: string;
  /** Secuencial del comprobante de retención. */
  secRetencion1?: string;
  /** Autorización del comprobante de retención. */
  autRetencion1?: string;
  /** Fecha de emisión del comprobante de retención. Formato: dd/mm/yyyy. */
  fechaEmiRet1?: string;
  /** Formas de pago del comprobante de compra. Opcional. */
  formasDePago?: string[];
}

/** Registro de documento anulado. */
export interface AtsAnulado {
  /** Tipo de comprobante anulado. */
  tipoComprobante: string;
  /** Establecimiento (3 dígitos). */
  establecimiento: string;
  /** Punto de emisión (3 dígitos). */
  puntoEmision: string;
  /** Secuencial inicial del rango anulado (9 dígitos, rellenado con ceros). */
  secuencialInicio: string;
  /** Secuencial final del rango anulado (9 dígitos, rellenado con ceros). */
  secuencialFin: string;
  /** Número de autorización del documento anulado. */
  autorizacion: string;
}

/** Estructura principal de datos para construir el ATS. */
export interface AtsData {
  /** Tipo de identificación del informante. 'R' = RUC. */
  TipoIDInformante: string;
  /** RUC del informante (13 dígitos). */
  IdInformante: string;
  /** Razón social del informante. */
  razonSocial: string;
  /** Año del período declarado. */
  Anio: number;
  /** Mes del período declarado. '01' a '12' (siempre 2 dígitos). */
  Mes: string;
  /** Número de establecimiento. Default: '001'. */
  numEstabRuc: string;
  /** Total de ventas del período. */
  totalVentas: number;
  /** Código operativo. Siempre 'IVA'. */
  codigoOperativo: string;
  /** Lista de ventas del período. */
  ventas: AtsVenta[];
  /** Lista de compras del período. */
  compras: AtsCompra[];
  /** Lista de documentos anulados del período. Opcional. */
  anulados?: AtsAnulado[];
}

// ---------------------------------------------------------------------------
// Helpers internos
// ---------------------------------------------------------------------------

/**
 * Escapa entidades XML en un valor de texto.
 * Solo escapa los 5 entidades predefinidas de XML.
 */
function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * Emite un elemento XML simple: <tag>value</tag>.
 * El valor de texto es escapado automáticamente.
 */
function e(tag: string, value: string | number): string {
  const strValue = typeof value === 'number' ? String(value) : value;
  return `<${tag}>${escapeXml(strValue)}</${tag}>`;
}

/**
 * Elemento opcional: emite <tag>value</tag> solo si value no es
 * null, undefined ni cadena vacía. Nunca emite un elemento vacío.
 */
function eo(tag: string, value: string | number | null | undefined): string {
  if (value === null || value === undefined) return '';
  const strValue = typeof value === 'number' ? String(value) : value;
  if (strValue.trim() === '') return '';
  return `<${tag}>${escapeXml(strValue)}</${tag}>`;
}

/**
 * Formatea un número como string con exactamente 2 decimales.
 * Usado para todos los montos monetarios del ATS.
 */
function fmt(n: number): string {
  return n.toFixed(2);
}

// ---------------------------------------------------------------------------
// Constructores de secciones XML
// ---------------------------------------------------------------------------

/**
 * Construye el bloque <detalleVentas> para un registro de venta.
 */
function buildDetalleVentas(venta: AtsVenta): string {
  const lineas: string[] = [
    e('tpIdCliente', venta.tpIdCliente),
    e('idCliente', venta.idCliente),
  ];

  // parteRelVtas: opcional
  if (venta.parteRelVtas) {
    lineas.push(e('parteRelVtas', venta.parteRelVtas));
  }

  lineas.push(
    e('tipoComprobante', venta.tipoComprobante),
    e('tipoEmision', venta.tipoEmision),
    e('numeroComprobantes', venta.numeroComprobantes),
    e('baseNoGraIva', fmt(venta.baseNoGraIva)),
    e('baseImponible', fmt(venta.baseImponible)),
    e('baseImpGrav', fmt(venta.baseImpGrav)),
    e('montoIva', fmt(venta.montoIva)),
    e('valorRetIva', fmt(venta.valorRetIva)),
    e('valorRetRenta', fmt(venta.valorRetRenta)),
  );

  // formasDePago: opcional — solo emitir si hay valores
  if (venta.formasDePago && venta.formasDePago.length > 0) {
    const pagos = venta.formasDePago
      .map((fp) => e('formaPago', fp))
      .join('');
    lineas.push(`<formasDePago>${pagos}</formasDePago>`);
  }

  return `<detalleVentas>${lineas.join('')}</detalleVentas>`;
}

/**
 * Construye el bloque <detalleAir> para retenciones en la fuente de una compra.
 */
function buildDetalleAir(det: AtsDetalleAir): string {
  return `<detalleAir>${[
    e('codRetAir', det.codRetAir),
    e('baseImpAir', fmt(det.baseImpAir)),
    e('porcentajeAir', fmt(det.porcentajeAir)),
    e('valRetAir', fmt(det.valRetAir)),
  ].join('')}</detalleAir>`;
}

/**
 * Construye el bloque <detalleCompras> para un registro de compra.
 */
function buildDetalleCompras(compra: AtsCompra): string {
  const lineas: string[] = [
    e('codSustento', compra.codSustento),
    e('tpIdProv', compra.tpIdProv),
    e('idProv', compra.idProv),
  ];

  // Campos opcionales previos a la fecha
  if (compra.parteRel) lineas.push(e('parteRel', compra.parteRel));
  if (compra.tipoProv) lineas.push(e('tipoProv', compra.tipoProv));
  if (compra.denoProv) lineas.push(e('denoProv', compra.denoProv));

  lineas.push(
    e('fechaRegistro', compra.fechaRegistro),
    e('tipoComprobante', compra.tipoComprobante),
    e('establecimiento', compra.establecimiento),
    e('puntoEmision', compra.puntoEmision),
    e('secuencial', compra.secuencial),
    e('fechaEmision', compra.fechaEmision),
    e('autorizacion', compra.autorizacion),
    e('baseNoGraIva', fmt(compra.baseNoGraIva)),
    e('baseImponible', fmt(compra.baseImponible)),
    e('baseImpGrav', fmt(compra.baseImpGrav)),
    e('baseImpExe', fmt(compra.baseImpExe)),
    e('montoIce', fmt(compra.montoIce)),
    e('montoIva', fmt(compra.montoIva)),
  );

  // Retenciones IVA opcionales por porcentaje específico
  if (compra.valRetBien10 !== undefined && compra.valRetBien10 !== null) {
    lineas.push(e('valRetBien10', fmt(compra.valRetBien10)));
  }
  if (compra.valRetServ20 !== undefined && compra.valRetServ20 !== null) {
    lineas.push(e('valRetServ20', fmt(compra.valRetServ20)));
  }

  lineas.push(e('valorRetBienes', fmt(compra.valorRetBienes)));

  if (compra.valRetServ50 !== undefined && compra.valRetServ50 !== null) {
    lineas.push(e('valRetServ50', fmt(compra.valRetServ50)));
  }

  lineas.push(
    e('valorRetServicios', fmt(compra.valorRetServicios)),
    e('valRetServ100', fmt(compra.valRetServ100)),
  );

  // valorRetencionNc: opcional
  if (compra.valorRetencionNc !== undefined && compra.valorRetencionNc !== null) {
    lineas.push(e('valorRetencionNc', fmt(compra.valorRetencionNc)));
  }

  // Bloque <air>: solo si hay retenciones en la fuente
  if (compra.detalleAirValues && compra.detalleAirValues.length > 0) {
    const airItems = compra.detalleAirValues.map(buildDetalleAir).join('');
    lineas.push(`<air>${airItems}</air>`);
  }

  // Datos del comprobante de retención vinculado (todos opcionales)
  lineas.push(eo('estabRetencion1', compra.estabRetencion1));
  lineas.push(eo('ptoEmiRetencion1', compra.ptoEmiRetencion1));
  lineas.push(eo('secRetencion1', compra.secRetencion1));
  lineas.push(eo('autRetencion1', compra.autRetencion1));
  lineas.push(eo('fechaEmiRet1', compra.fechaEmiRet1));

  // formasDePago: opcional
  if (compra.formasDePago && compra.formasDePago.length > 0) {
    const pagos = compra.formasDePago
      .map((fp) => e('formaPago', fp))
      .join('');
    lineas.push(`<formasDePago>${pagos}</formasDePago>`);
  }

  return `<detalleCompras>${lineas.join('')}</detalleCompras>`;
}

/**
 * Construye el bloque <detalleAnulados> para un documento anulado.
 */
function buildDetalleAnulados(anulado: AtsAnulado): string {
  return `<detalleAnulados>${[
    e('tipoComprobante', anulado.tipoComprobante),
    e('establecimiento', anulado.establecimiento),
    e('puntoEmision', anulado.puntoEmision),
    e('secuencialInicio', anulado.secuencialInicio),
    e('secuencialFin', anulado.secuencialFin),
    e('autorizacion', anulado.autorizacion),
  ].join('')}</detalleAnulados>`;
}

// ---------------------------------------------------------------------------
// Función principal exportada
// ---------------------------------------------------------------------------

/**
 * Construye el XML completo del ATS para el período indicado.
 *
 * El string resultante usa encoding UTF-8 (JavaScript string nativo).
 * Para obtener los bytes en ISO-8859-1 que el SRI requiere, pasar el
 * resultado a `encodeIso88591()`.
 *
 * @param data  Datos del ATS a serializar.
 * @returns     String XML con header ISO-8859-1.
 */
export function buildAtsXml(data: AtsData): string {
  const partes: string[] = [];

  // Header XML con encoding ISO-8859-1 (requisito SRI Ecuador)
  partes.push('<?xml version="1.0" encoding="ISO-8859-1"?>');

  // Apertura del root <iva>
  partes.push('<iva>');

  // Cabecera del informante
  partes.push(e('TipoIDInformante', data.TipoIDInformante));
  partes.push(e('IdInformante', data.IdInformante));
  partes.push(e('razonSocial', data.razonSocial));
  partes.push(e('Anio', data.Anio));
  partes.push(e('Mes', data.Mes));
  partes.push(e('numEstabRuc', data.numEstabRuc));
  partes.push(e('totalVentas', fmt(data.totalVentas)));
  partes.push(e('codigoOperativo', data.codigoOperativo));

  // Sección <ventas>: solo si hay registros de ventas
  if (data.ventas.length > 0) {
    const detalles = data.ventas.map(buildDetalleVentas).join('');
    partes.push(`<ventas>${detalles}</ventas>`);
  }

  // Sección <compras>: solo si hay registros de compras
  if (data.compras.length > 0) {
    const detalles = data.compras.map(buildDetalleCompras).join('');
    partes.push(`<compras>${detalles}</compras>`);
  }

  // Sección <anulados>: solo si hay documentos anulados
  if (data.anulados && data.anulados.length > 0) {
    const detalles = data.anulados.map(buildDetalleAnulados).join('');
    partes.push(`<anulados>${detalles}</anulados>`);
  }

  // Cierre del root
  partes.push('</iva>');

  return partes.join('');
}

// ---------------------------------------------------------------------------
// Codificación ISO-8859-1
// ---------------------------------------------------------------------------

/**
 * Convierte un string UTF-16 (JavaScript) a bytes ISO-8859-1.
 *
 * El SRI Ecuador REQUIERE que los archivos XML del ATS estén codificados
 * en ISO-8859-1. Los caracteres cuyo code point supera 0xFF (fuera del
 * rango de ISO-8859-1, p.ej. emojis o caracteres CJK) se reemplazan con
 * el carácter '?' (0x3F) para evitar corrupción silenciosa.
 *
 * Nota: los caracteres típicos del español (á é í ó ú ü ñ Á É Í Ó Ú Ü Ñ ¿ ¡)
 * están dentro del rango ISO-8859-1 (<=0xFF) y se codifican correctamente.
 *
 * @param xml  String XML en UTF-16 (resultado de buildAtsXml).
 * @returns    Uint8Array con los bytes en ISO-8859-1.
 */
export function encodeIso88591(xml: string): Uint8Array {
  const bytes = new Uint8Array(xml.length);
  for (let i = 0; i < xml.length; i++) {
    const code = xml.charCodeAt(i);
    // Caracteres dentro del rango ISO-8859-1 (0x00–0xFF): codificar directamente.
    // Caracteres fuera del rango (>0xFF): sustituir por '?' (0x3F).
    bytes[i] = code <= 0xFF ? code : 0x3F;
  }
  return bytes;
}
