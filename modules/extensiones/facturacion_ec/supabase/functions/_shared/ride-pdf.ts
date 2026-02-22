/**
 * PILAR ERP — _shared/ride-pdf.ts
 *
 * Generador de RIDE (Representación Impresa del Documento Electrónico)
 * para el SRI Ecuador en formato PDF/A.
 *
 * Usa pdf-lib exclusivamente. No requiere bwip-js ni fuentes externas.
 * La clave de acceso se renderiza como texto monoespaciado (Courier) en
 * lugar de código de barras, para garantizar compatibilidad en Deno Edge Runtime.
 *
 * Exporta:
 *   generarRidePdf(data: RideData): Promise<Uint8Array>
 */

import {
  PDFDocument,
  PDFPage,
  PDFFont,
  StandardFonts,
  rgb,
  PageSizes,
  degrees,
  type RGB,
} from 'npm:pdf-lib@1.17.1';

// ---------------------------------------------------------------------------
// Interfaces de entrada (locales, compatibles con xml-parser.ts)
// ---------------------------------------------------------------------------

export interface AutorizacionSri {
  estado: string;
  numeroAutorizacion: string;
  fechaAutorizacion: string;
  ambiente: string;
}

export interface InfoTributaria {
  ambiente: string;
  razonSocial: string;
  nombreComercial: string;
  ruc: string;
  claveAcceso: string;
  codDoc: string;
  estab: string;
  ptoEmi: string;
  secuencial: string;
  dirMatriz: string;
  numeroDocumento: string; // '001-001-000000001'
}

export interface TotalImpuesto {
  codigo: string;
  codigoPorcentaje: string;
  descripcion: string;
  baseImponible: number;
  valor: number;
}

export interface Pago {
  formaPago: string;
  descripcion: string;
  total: number;
}

export interface DetalleLinea {
  codigoPrincipal: string;
  descripcion: string;
  cantidad: number;
  precioUnitario: number;
  descuento: number;
  precioTotalSinImpuesto: number;
  impuestos: Array<{ tarifa: number; valor: number }>;
}

export interface DetalleRetencion {
  codigoRetencion: string;
  descripcion: string;
  baseImponible: number;
  porcentajeRetener: number;
  valorRetenido: number;
  numDocSustento: string;
  fechaEmisionDocSustento: string;
}

export interface CampoAdicional {
  nombre: string;
  valor: string;
}

export interface EmisorInfo {
  razonSocial: string;
  nombreComercial: string;
  ruc: string;
  dirMatriz: string;
  dirEstablecimiento?: string;
  obligadoContabilidad?: string;
  contribuyenteEspecial?: string;
  logoBytes?: Uint8Array; // PNG o JPEG del logo
  logoMimeType?: 'image/png' | 'image/jpeg';
}

export interface ReceptorInfo {
  tipoId: string;       // 'RUC', 'CEDULA', etc. (ya como descripción)
  identificacion: string;
  razonSocial: string;
}

export interface RideData {
  autorizacion: AutorizacionSri;
  infoTributaria: InfoTributaria;
  emisor: EmisorInfo;
  receptor: ReceptorInfo;
  fechaEmision: string;        // 'DD/MM/YYYY'
  periodoFiscal?: string;      // Solo para retenciones
  codDocModificado?: string;   // NC/ND: código doc modificado
  numDocModificado?: string;   // NC/ND: número doc modificado
  motivoNC?: string;           // NC: motivo
  totalSinImpuestos?: number;
  totalDescuento?: number;
  propina?: number;
  importeTotal?: number;
  valorModificacion?: number;
  moneda?: string;
  totalConImpuestos: TotalImpuesto[];
  pagos?: Pago[];
  detalles?: DetalleLinea[];            // Factura, LC, NC, ND
  retenciones?: DetalleRetencion[];     // Solo retención
  infoAdicional: CampoAdicional[];
  guiaRemision?: {
    dirPartida: string;
    razonSocialTransportista: string;
    rucTransportista: string;
    placa: string;
    fechaIniTransporte: string;
    fechaFinTransporte: string;
  };
}

// ---------------------------------------------------------------------------
// Constantes de layout y paleta de colores
// ---------------------------------------------------------------------------

const MARGIN = 40;
const PAGE_WIDTH  = PageSizes.A4[0]; // 595.28
const PAGE_HEIGHT = PageSizes.A4[1]; // 841.89
const CONTENT_WIDTH = PAGE_WIDTH - MARGIN * 2;
const MARGIN_BOTTOM = 80;

const COLOR_PILAR_BLUE: RGB = rgb(0.094, 0.302, 0.604);
const COLOR_GRAY_BG:    RGB = rgb(0.95, 0.95, 0.95);
const COLOR_GRAY_TEXT:  RGB = rgb(0.3, 0.3, 0.3);
const COLOR_BLACK:      RGB = rgb(0, 0, 0);
const COLOR_WHITE:      RGB = rgb(1, 1, 1);
const COLOR_RED:        RGB = rgb(0.8, 0, 0);
const COLOR_LIGHT_BLUE: RGB = rgb(0.85, 0.9, 0.98); // Alternado filas

// Anchos de columnas de detalles (porcentajes * CONTENT_WIDTH)
const COL_WIDTHS_DETALLE = [0.10, 0.35, 0.10, 0.15, 0.10, 0.20].map(
  (p) => p * CONTENT_WIDTH,
);
// Anchos de columnas de retenciones
const COL_WIDTHS_RETENCION = [0.10, 0.25, 0.15, 0.10, 0.15, 0.25].map(
  (p) => p * CONTENT_WIDTH,
);

// ---------------------------------------------------------------------------
// Helpers auxiliares privados
// ---------------------------------------------------------------------------

/** Formatea un número como moneda: '$ 1,234.56' */
function formatMoney(n: number): string {
  return '$ ' + n.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/** Normaliza fecha a DD/MM/YYYY. Acepta DD/MM/YYYY, YYYY-MM-DD, ISO 8601. */
function formatFecha(fecha: string): string {
  if (!fecha) return '';
  // ISO 8601 con T o espacio
  const isoMatch = fecha.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}):(\d{2}))?/);
  if (isoMatch) {
    const [, y, m, d, hh, mm, ss] = isoMatch;
    const base = `${d}/${m}/${y}`;
    return (hh && mm && ss) ? `${base} ${hh}:${mm}:${ss}` : base;
  }
  // DD/MM/YYYY (con o sin hora)
  return fecha;
}

/** Retorna el nombre en español del tipo de documento por código SRI. */
function getNombreTipoDoc(codDoc: string): string {
  const nombres: Record<string, string> = {
    '01': 'FACTURA',
    '03': 'LIQUIDACIÓN DE COMPRA',
    '04': 'NOTA DE CRÉDITO',
    '05': 'NOTA DE DÉBITO',
    '06': 'GUÍA DE REMISIÓN',
    '07': 'COMPROBANTE DE RETENCIÓN',
  };
  return nombres[codDoc] ?? `DOCUMENTO ${codDoc}`;
}

/** Dibuja una línea en la página. */
function drawLine(
  page: PDFPage,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  lineWidth = 0.5,
  color: RGB = COLOR_BLACK,
): void {
  page.drawLine({
    start: { x: x1, y: y1 },
    end:   { x: x2, y: y2 },
    thickness: lineWidth,
    color,
  });
}

/** Dibuja un rectángulo con relleno y/o borde opcional. */
function drawRect(
  page: PDFPage,
  x: number,
  y: number,
  width: number,
  height: number,
  fillColor?: RGB,
  borderColor?: RGB,
  borderWidth = 0.5,
): void {
  page.drawRectangle({
    x,
    y,
    width,
    height,
    color:       fillColor,
    borderColor: borderColor,
    borderWidth: borderColor ? borderWidth : undefined,
  });
}

/** Dibuja texto en coordenadas absolutas. */
function drawText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  font: PDFFont,
  size: number,
  color: RGB = COLOR_BLACK,
): void {
  page.drawText(text, { x, y, font, size, color });
}

/**
 * Trunca texto para que no supere maxWidth en pts, añadiendo '...' si es necesario.
 */
function truncateText(
  text: string,
  font: PDFFont,
  size: number,
  maxWidth: number,
): string {
  if (!text) return '';
  const ellipsis = '...';
  const ellipsisWidth = font.widthOfTextAtSize(ellipsis, size);
  if (font.widthOfTextAtSize(text, size) <= maxWidth) return text;

  let truncated = text;
  while (
    truncated.length > 0 &&
    font.widthOfTextAtSize(truncated, size) + ellipsisWidth > maxWidth
  ) {
    truncated = truncated.slice(0, -1);
  }
  return truncated + ellipsis;
}

/**
 * Calcula la altura que ocupará un bloque de texto con wrapping.
 * Retorna las líneas resultantes y la altura total.
 */
function wrapText(
  text: string,
  font: PDFFont,
  size: number,
  maxWidth: number,
): string[] {
  if (!text) return [''];
  const words = text.split(' ');
  const lines: string[] = [];
  let current = '';

  for (const word of words) {
    const test = current ? `${current} ${word}` : word;
    if (font.widthOfTextAtSize(test, size) <= maxWidth) {
      current = test;
    } else {
      if (current) lines.push(current);
      // Si la palabra sola es demasiado larga, truncarla
      current = font.widthOfTextAtSize(word, size) > maxWidth
        ? truncateText(word, font, size, maxWidth)
        : word;
    }
  }
  if (current) lines.push(current);
  return lines.length ? lines : [''];
}

/**
 * Alinea texto a la derecha dentro de un bloque de ancho 'colWidth' que comienza en 'x'.
 */
function drawTextRight(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  colWidth: number,
  font: PDFFont,
  size: number,
  color: RGB = COLOR_BLACK,
): void {
  const textWidth = font.widthOfTextAtSize(text, size);
  const xRight = x + colWidth - textWidth;
  drawText(page, text, Math.max(x, xRight), y, font, size, color);
}

/**
 * Centra texto dentro de un bloque que comienza en 'x' con ancho 'colWidth'.
 */
function drawTextCenter(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  colWidth: number,
  font: PDFFont,
  size: number,
  color: RGB = COLOR_BLACK,
): void {
  const textWidth = font.widthOfTextAtSize(text, size);
  const xCenter = x + (colWidth - textWidth) / 2;
  drawText(page, text, Math.max(x, xCenter), y, font, size, color);
}

// ---------------------------------------------------------------------------
// Contexto compartido entre páginas
// ---------------------------------------------------------------------------

interface RideFonts {
  regular: PDFFont;
  bold:    PDFFont;
  courier: PDFFont;
}

interface RideContext {
  pdfDoc: PDFDocument;
  fonts:  RideFonts;
  data:   RideData;
}

// ---------------------------------------------------------------------------
// Marca de agua PRUEBAS
// ---------------------------------------------------------------------------

function addWatermarkPruebas(page: PDFPage, fonts: RideFonts): void {
  const text = 'PRUEBA';
  const size = 72;
  const textWidth = fonts.bold.widthOfTextAtSize(text, size);
  const cx = PAGE_WIDTH  / 2 - textWidth / 2;
  const cy = PAGE_HEIGHT / 2 - size / 2;

  page.drawText(text, {
    x:        cx,
    y:        cy,
    font:     fonts.bold,
    size,
    color:    rgb(0.8, 0, 0),
    opacity:  0.12,
    rotate:   degrees(45),
  });
}

// ---------------------------------------------------------------------------
// Sección 1: Header del emisor (dos columnas)
// ---------------------------------------------------------------------------

/**
 * Dibuja el header del emisor.
 * Retorna el Y inferior del bloque (cursor para la siguiente sección).
 */
async function drawHeaderEmisor(
  page: PDFPage,
  ctx: RideContext,
  startY: number,
): Promise<number> {
  const { fonts, data } = ctx;
  const { emisor, infoTributaria, autorizacion } = data;
  const PADDING = 4;

  const leftWidth  = CONTENT_WIDTH * 0.58;
  const rightWidth = CONTENT_WIDTH * 0.40;
  const gap        = CONTENT_WIDTH - leftWidth - rightWidth;
  const rightX     = MARGIN + leftWidth + gap;

  // Altura estimada del bloque: mínimo 110pt
  const blockHeight = 120;
  const blockBottom = startY - blockHeight;

  // --- Columna izquierda ---
  let curY = startY - PADDING;

  // Logo
  let logoEmbedded = false;
  if (emisor.logoBytes && emisor.logoBytes.length > 0) {
    try {
      let embeddedImg;
      if (emisor.logoMimeType === 'image/jpeg') {
        embeddedImg = await ctx.pdfDoc.embedJpg(emisor.logoBytes);
      } else {
        embeddedImg = await ctx.pdfDoc.embedPng(emisor.logoBytes);
      }
      const MAX_LOGO_H = 60;
      const MAX_LOGO_W = leftWidth - PADDING * 2;
      const ratio      = embeddedImg.width / embeddedImg.height;
      let logoH = MAX_LOGO_H;
      let logoW = logoH * ratio;
      if (logoW > MAX_LOGO_W) {
        logoW = MAX_LOGO_W;
        logoH = logoW / ratio;
      }
      page.drawImage(embeddedImg, {
        x:      MARGIN + PADDING,
        y:      curY - logoH,
        width:  logoW,
        height: logoH,
      });
      curY -= logoH + 4;
      logoEmbedded = true;
    } catch {
      // Logo inválido → continuar sin logo
    }
  }

  if (!logoEmbedded) {
    // Nombre comercial como fallback
    const ncText = truncateText(
      emisor.nombreComercial || emisor.razonSocial,
      fonts.bold,
      11,
      leftWidth - PADDING * 2,
    );
    drawText(page, ncText, MARGIN + PADDING, curY - 11, fonts.bold, 11, COLOR_PILAR_BLUE);
    curY -= 16;
  }

  // Razón social
  const rsLines = wrapText(emisor.razonSocial, fonts.bold, 9, leftWidth - PADDING * 2);
  for (const line of rsLines) {
    drawText(page, line, MARGIN + PADDING, curY - 9, fonts.bold, 9, COLOR_BLACK);
    curY -= 12;
  }

  // Dirección matriz
  const dirLines = wrapText(emisor.dirMatriz, fonts.regular, 8, leftWidth - PADDING * 2);
  for (const line of dirLines) {
    drawText(page, line, MARGIN + PADDING, curY - 8, fonts.regular, 8, COLOR_GRAY_TEXT);
    curY -= 10;
  }

  // RUC
  drawText(
    page,
    `RUC: ${emisor.ruc}`,
    MARGIN + PADDING,
    curY - 8,
    fonts.regular,
    8,
    COLOR_BLACK,
  );
  curY -= 11;

  // Contribuyente especial
  if (emisor.contribuyenteEspecial) {
    drawText(
      page,
      `CONTRIBUYENTE ESPECIAL: ${emisor.contribuyenteEspecial}`,
      MARGIN + PADDING,
      curY - 8,
      fonts.regular,
      8,
      COLOR_BLACK,
    );
    curY -= 11;
  }

  // Obligado a llevar contabilidad
  const obligado = (emisor.obligadoContabilidad ?? '').toUpperCase();
  if (obligado === 'SI' || obligado === 'S' || obligado === 'TRUE' || obligado === '1') {
    drawText(
      page,
      'OBLIGADO A LLEVAR CONTABILIDAD: SI',
      MARGIN + PADDING,
      curY - 8,
      fonts.regular,
      8,
      COLOR_BLACK,
    );
    curY -= 11;
  }

  // Dirección de establecimiento (si aplica)
  if (emisor.dirEstablecimiento) {
    const estabLines = wrapText(
      `Estab.: ${emisor.dirEstablecimiento}`,
      fonts.regular,
      8,
      leftWidth - PADDING * 2,
    );
    for (const line of estabLines) {
      drawText(page, line, MARGIN + PADDING, curY - 8, fonts.regular, 8, COLOR_GRAY_TEXT);
      curY -= 10;
    }
  }

  // --- Columna derecha (recuadro con borde) ---
  const rBoxBottom = Math.min(blockBottom, curY - 6);
  const rBoxHeight = startY - rBoxBottom;
  drawRect(page, rightX, rBoxBottom, rightWidth, rBoxHeight, undefined, COLOR_PILAR_BLUE, 1);

  let rCurY = startY - PADDING;

  // Razón social centrada (bold, 9pt)
  const rsEmisTitle = truncateText(emisor.razonSocial, fonts.bold, 8, rightWidth - PADDING * 2);
  drawTextCenter(page, rsEmisTitle, rightX, rCurY - 8, rightWidth, fonts.bold, 8, COLOR_PILAR_BLUE);
  rCurY -= 12;

  // Tipo de documento
  const tipoDoc = getNombreTipoDoc(infoTributaria.codDoc);
  drawTextCenter(page, tipoDoc, rightX, rCurY - 11, rightWidth, fonts.bold, 11, COLOR_PILAR_BLUE);
  rCurY -= 15;

  // Número del documento
  drawTextCenter(
    page,
    infoTributaria.numeroDocumento,
    rightX,
    rCurY - 13,
    rightWidth,
    fonts.bold,
    13,
    COLOR_BLACK,
  );
  rCurY -= 18;

  // Separador fino
  drawLine(page, rightX + PADDING, rCurY, rightX + rightWidth - PADDING, rCurY, 0.5, COLOR_GRAY_TEXT);
  rCurY -= 6;

  // Número de autorización
  drawText(page, 'NÚMERO DE AUTORIZACIÓN:', rightX + PADDING, rCurY - 7, fonts.bold, 7, COLOR_GRAY_TEXT);
  rCurY -= 10;

  // El número de autorización puede ser largo → wrap
  const numAuthLines = wrapText(
    autorizacion.numeroAutorizacion,
    fonts.courier,
    7,
    rightWidth - PADDING * 2,
  );
  for (const line of numAuthLines) {
    drawText(page, line, rightX + PADDING, rCurY - 7, fonts.courier, 7, COLOR_BLACK);
    rCurY -= 9;
  }

  // Fecha de autorización
  drawText(
    page,
    `Fecha aut.: ${formatFecha(autorizacion.fechaAutorizacion)}`,
    rightX + PADDING,
    rCurY - 7,
    fonts.regular,
    7,
    COLOR_BLACK,
  );
  rCurY -= 10;

  // Ambiente
  const esPruebas = autorizacion.ambiente !== 'PRODUCCION';
  if (esPruebas) {
    // Fondo rojo, texto blanco
    const ambLabel = 'AMBIENTE: PRUEBAS';
    drawRect(
      page,
      rightX + PADDING,
      rCurY - 12,
      rightWidth - PADDING * 2,
      13,
      COLOR_RED,
      undefined,
    );
    drawTextCenter(page, ambLabel, rightX + PADDING, rCurY - 10, rightWidth - PADDING * 2, fonts.bold, 8, COLOR_WHITE);
  } else {
    drawText(
      page,
      'AMBIENTE: PRODUCCIÓN',
      rightX + PADDING,
      rCurY - 8,
      fonts.regular,
      8,
      COLOR_GRAY_TEXT,
    );
  }

  // Calcular bottom real del bloque
  const finalBottom = Math.min(rBoxBottom, blockBottom);
  return finalBottom - 6;
}

// ---------------------------------------------------------------------------
// Sección 2: Clave de acceso
// ---------------------------------------------------------------------------

function drawClaveAcceso(
  page: PDFPage,
  ctx: RideContext,
  startY: number,
): number {
  const { fonts, data } = ctx;
  const PADDING = 4;
  const clave   = data.infoTributaria.claveAcceso;

  // Dividir en 2 líneas de ~24-25 chars
  const line1 = clave.slice(0, 24);
  const line2 = clave.slice(24, 49);
  const line3 = clave.slice(49);   // Si hubiera más

  const lines = [line1, line2, ...(line3 ? [line3] : [])].filter((l) => l.length > 0);

  const boxHeight = 8 + lines.length * 11 + PADDING;
  const boxBottom = startY - boxHeight;

  drawRect(page, MARGIN, boxBottom, CONTENT_WIDTH, boxHeight, COLOR_GRAY_BG, COLOR_GRAY_TEXT, 0.5);

  let curY = startY - PADDING;
  drawText(page, 'CLAVE DE ACCESO:', MARGIN + PADDING, curY - 7, fonts.bold, 7, COLOR_GRAY_TEXT);
  curY -= 10;

  for (const line of lines) {
    drawText(page, line, MARGIN + PADDING, curY - 9, fonts.courier, 9, COLOR_BLACK);
    curY -= 11;
  }

  return boxBottom - 6;
}

// ---------------------------------------------------------------------------
// Sección 3: Datos del receptor
// ---------------------------------------------------------------------------

function drawDatosReceptor(
  page: PDFPage,
  ctx: RideContext,
  startY: number,
): number {
  const { fonts, data } = ctx;
  const { receptor, fechaEmision, periodoFiscal, numDocModificado, codDocModificado } = data;
  const PADDING = 4;

  // Construir filas de la grilla
  type Row = [string, string, string, string]; // [labelL, valueL, labelR, valueR]
  const rows: Row[] = [];

  // Razón social (ocupa toda la fila)
  rows.push([
    'Razón Social:',
    receptor.razonSocial,
    `${receptor.tipoId}:`,
    receptor.identificacion,
  ]);

  rows.push(['Fecha Emisión:', data.fechaEmision, '', '']);

  if (periodoFiscal) {
    rows.push(['Período Fiscal:', periodoFiscal, '', '']);
  }

  if (numDocModificado && codDocModificado) {
    rows.push([
      'Doc. Modificado:',
      `${getNombreTipoDoc(codDocModificado)} ${numDocModificado}`,
      '',
      '',
    ]);
  }

  const rowH = 13;
  const boxHeight = rows.length * rowH + PADDING * 2;
  const boxBottom = startY - boxHeight;
  drawRect(page, MARGIN, boxBottom, CONTENT_WIDTH, boxHeight, COLOR_GRAY_BG, COLOR_GRAY_TEXT, 0.5);

  const halfW = CONTENT_WIDTH / 2;
  let curY = startY - PADDING;

  for (const [lLabel, lVal, rLabel, rVal] of rows) {
    const yText = curY - 9;

    // Label izquierda
    drawText(page, lLabel, MARGIN + PADDING, yText, fonts.bold, 8, COLOR_GRAY_TEXT);
    const lLabelW = fonts.bold.widthOfTextAtSize(lLabel, 8);

    // Valor izquierda
    const lValTrunc = truncateText(lVal, fonts.regular, 8, halfW - PADDING * 2 - lLabelW - 4);
    drawText(page, lValTrunc, MARGIN + PADDING + lLabelW + 4, yText, fonts.regular, 8, COLOR_BLACK);

    // Label y valor derecha
    if (rLabel) {
      drawText(page, rLabel, MARGIN + halfW + PADDING, yText, fonts.bold, 8, COLOR_GRAY_TEXT);
      const rLabelW = fonts.bold.widthOfTextAtSize(rLabel, 8);
      const rValTrunc = truncateText(rVal, fonts.regular, 8, halfW - PADDING * 2 - rLabelW - 4);
      drawText(
        page,
        rValTrunc,
        MARGIN + halfW + PADDING + rLabelW + 4,
        yText,
        fonts.regular,
        8,
        COLOR_BLACK,
      );
    }

    // Línea separadora fina entre filas
    if (curY - rowH > boxBottom) {
      drawLine(
        page,
        MARGIN,
        curY - rowH,
        MARGIN + CONTENT_WIDTH,
        curY - rowH,
        0.3,
        COLOR_GRAY_TEXT,
      );
    }

    curY -= rowH;
  }

  return boxBottom - 6;
}

// ---------------------------------------------------------------------------
// Sección especial: NC / ND — documento modificado y motivo
// ---------------------------------------------------------------------------

function drawSeccionDocModificado(
  page: PDFPage,
  ctx: RideContext,
  startY: number,
): number {
  const { fonts, data } = ctx;
  const { codDocModificado, numDocModificado, motivoNC } = data;
  if (!numDocModificado) return startY;

  const PADDING = 4;
  const lines: string[] = [];

  const nomDoc = codDocModificado ? getNombreTipoDoc(codDocModificado) : 'DOCUMENTO';
  lines.push(`Documento modificado: ${nomDoc} ${numDocModificado}`);
  if (motivoNC) lines.push(`Motivo: ${motivoNC}`);

  const boxH = lines.length * 12 + PADDING * 2;
  const boxBottom = startY - boxH;
  drawRect(page, MARGIN, boxBottom, CONTENT_WIDTH, boxH, COLOR_LIGHT_BLUE, COLOR_PILAR_BLUE, 0.5);

  let curY = startY - PADDING;
  for (const line of lines) {
    drawText(page, line, MARGIN + PADDING, curY - 8, fonts.bold, 8, COLOR_PILAR_BLUE);
    curY -= 12;
  }

  return boxBottom - 6;
}

// ---------------------------------------------------------------------------
// Sección 4: Tabla de detalles (Factura / LC / NC / ND)
// ---------------------------------------------------------------------------

/**
 * Dibuja la cabecera de la tabla de detalles.
 * Retorna el Y inferior del encabezado.
 */
function drawDetalleHeader(page: PDFPage, fonts: RideFonts, startY: number): number {
  const headerH = 14;
  const headers = ['CÓD.', 'DESCRIPCIÓN', 'CANT.', 'P. UNIT.', 'DESC.', 'P. TOTAL'];
  const aligns  = ['left', 'left', 'right', 'right', 'right', 'right'] as const;

  drawRect(page, MARGIN, startY - headerH, CONTENT_WIDTH, headerH, COLOR_PILAR_BLUE, undefined);

  let x = MARGIN;
  for (let i = 0; i < headers.length; i++) {
    const colW = COL_WIDTHS_DETALLE[i];
    const PADDING = 3;
    const yText  = startY - headerH + 3;
    if (aligns[i] === 'right') {
      drawTextRight(page, headers[i], x + PADDING, yText, colW - PADDING * 2, fonts.bold, 7, COLOR_WHITE);
    } else {
      drawText(page, headers[i], x + PADDING, yText, fonts.bold, 7, COLOR_WHITE);
    }
    x += colW;
  }

  return startY - headerH;
}

/**
 * Dibuja las filas de detalle, gestionando multi-página.
 * Retorna el Y final (cursor después de la última fila).
 */
async function drawDetalleRows(
  ctx: RideContext,
  pages: PDFPage[],
  currentPage: PDFPage,
  startY: number,
  addWatermark: boolean,
): Promise<{ page: PDFPage; curY: number }> {
  const { fonts, data, pdfDoc } = ctx;
  const detalles = data.detalles ?? [];

  let page = currentPage;
  let curY = startY;

  const ROW_H = 13;
  const PADDING = 3;

  for (let i = 0; i < detalles.length; i++) {
    const det = detalles[i];

    // ¿Necesitamos nueva página?
    if (curY - ROW_H < MARGIN_BOTTOM) {
      page = await addNewPage(ctx, pages, addWatermark);
      curY = PAGE_HEIGHT - MARGIN - 10;
      // Redibujar header de la tabla en la nueva página
      curY = drawDetalleHeader(page, fonts, curY);
    }

    const isEven = i % 2 === 0;
    drawRect(
      page,
      MARGIN,
      curY - ROW_H,
      CONTENT_WIDTH,
      ROW_H,
      isEven ? COLOR_WHITE : COLOR_GRAY_BG,
      undefined,
    );

    const yText = curY - ROW_H + 3;
    let x = MARGIN;

    // Cód.
    const cod = truncateText(det.codigoPrincipal, fonts.regular, 7, COL_WIDTHS_DETALLE[0] - PADDING * 2);
    drawText(page, cod, x + PADDING, yText, fonts.regular, 7, COLOR_BLACK);
    x += COL_WIDTHS_DETALLE[0];

    // Descripción
    const desc = truncateText(det.descripcion, fonts.regular, 7, COL_WIDTHS_DETALLE[1] - PADDING * 2);
    drawText(page, desc, x + PADDING, yText, fonts.regular, 7, COLOR_BLACK);
    x += COL_WIDTHS_DETALLE[1];

    // Cantidad
    drawTextRight(
      page,
      det.cantidad.toFixed(2),
      x + PADDING,
      yText,
      COL_WIDTHS_DETALLE[2] - PADDING * 2,
      fonts.regular,
      7,
    );
    x += COL_WIDTHS_DETALLE[2];

    // Precio unitario
    drawTextRight(
      page,
      formatMoney(det.precioUnitario),
      x + PADDING,
      yText,
      COL_WIDTHS_DETALLE[3] - PADDING * 2,
      fonts.regular,
      7,
    );
    x += COL_WIDTHS_DETALLE[3];

    // Descuento
    drawTextRight(
      page,
      formatMoney(det.descuento),
      x + PADDING,
      yText,
      COL_WIDTHS_DETALLE[4] - PADDING * 2,
      fonts.regular,
      7,
    );
    x += COL_WIDTHS_DETALLE[4];

    // Precio total
    drawTextRight(
      page,
      formatMoney(det.precioTotalSinImpuesto),
      x + PADDING,
      yText,
      COL_WIDTHS_DETALLE[5] - PADDING * 2,
      fonts.bold,
      7,
    );

    // Línea inferior de fila
    drawLine(page, MARGIN, curY - ROW_H, MARGIN + CONTENT_WIDTH, curY - ROW_H, 0.2, COLOR_GRAY_TEXT);

    curY -= ROW_H;
  }

  // Borde exterior de la tabla
  const tableTop    = startY;
  const tableBottom = curY;
  drawRect(page, MARGIN, tableBottom, CONTENT_WIDTH, tableTop - tableBottom, undefined, COLOR_GRAY_TEXT, 0.5);

  return { page, curY };
}

// ---------------------------------------------------------------------------
// Sección 4b: Tabla de retenciones
// ---------------------------------------------------------------------------

function drawRetencionHeader(page: PDFPage, fonts: RideFonts, startY: number): number {
  const headerH = 14;
  const headers = ['CÓD.', 'DESCRIPCIÓN', 'BASE IMPON.', '% RET.', 'VAL. RETENIDO', 'DOC. SUSTENTO'];
  const aligns  = ['left', 'left', 'right', 'right', 'right', 'left'] as const;

  drawRect(page, MARGIN, startY - headerH, CONTENT_WIDTH, headerH, COLOR_PILAR_BLUE, undefined);

  let x = MARGIN;
  for (let i = 0; i < headers.length; i++) {
    const colW   = COL_WIDTHS_RETENCION[i];
    const PADDING = 3;
    const yText  = startY - headerH + 3;
    if (aligns[i] === 'right') {
      drawTextRight(page, headers[i], x + PADDING, yText, colW - PADDING * 2, fonts.bold, 7, COLOR_WHITE);
    } else {
      drawText(page, headers[i], x + PADDING, yText, fonts.bold, 7, COLOR_WHITE);
    }
    x += colW;
  }

  return startY - headerH;
}

async function drawRetencionRows(
  ctx: RideContext,
  pages: PDFPage[],
  currentPage: PDFPage,
  startY: number,
  addWatermark: boolean,
): Promise<{ page: PDFPage; curY: number }> {
  const { fonts, data } = ctx;
  const retenciones = data.retenciones ?? [];

  let page = currentPage;
  let curY = startY;
  const ROW_H  = 13;
  const PADDING = 3;

  for (let i = 0; i < retenciones.length; i++) {
    const ret = retenciones[i];

    if (curY - ROW_H < MARGIN_BOTTOM) {
      page = await addNewPage(ctx, pages, addWatermark);
      curY = PAGE_HEIGHT - MARGIN - 10;
      curY = drawRetencionHeader(page, fonts, curY);
    }

    const isEven = i % 2 === 0;
    drawRect(
      page,
      MARGIN,
      curY - ROW_H,
      CONTENT_WIDTH,
      ROW_H,
      isEven ? COLOR_WHITE : COLOR_GRAY_BG,
      undefined,
    );

    const yText = curY - ROW_H + 3;
    let x = MARGIN;

    drawText(page, truncateText(ret.codigoRetencion, fonts.regular, 7, COL_WIDTHS_RETENCION[0] - PADDING * 2), x + PADDING, yText, fonts.regular, 7, COLOR_BLACK);
    x += COL_WIDTHS_RETENCION[0];

    drawText(page, truncateText(ret.descripcion, fonts.regular, 7, COL_WIDTHS_RETENCION[1] - PADDING * 2), x + PADDING, yText, fonts.regular, 7, COLOR_BLACK);
    x += COL_WIDTHS_RETENCION[1];

    drawTextRight(page, formatMoney(ret.baseImponible),  x + PADDING, yText, COL_WIDTHS_RETENCION[2] - PADDING * 2, fonts.regular, 7);
    x += COL_WIDTHS_RETENCION[2];

    drawTextRight(page, `${ret.porcentajeRetener.toFixed(2)}%`, x + PADDING, yText, COL_WIDTHS_RETENCION[3] - PADDING * 2, fonts.regular, 7);
    x += COL_WIDTHS_RETENCION[3];

    drawTextRight(page, formatMoney(ret.valorRetenido), x + PADDING, yText, COL_WIDTHS_RETENCION[4] - PADDING * 2, fonts.bold, 7);
    x += COL_WIDTHS_RETENCION[4];

    drawText(
      page,
      truncateText(`${ret.numDocSustento} (${formatFecha(ret.fechaEmisionDocSustento)})`, fonts.regular, 6, COL_WIDTHS_RETENCION[5] - PADDING * 2),
      x + PADDING,
      yText,
      fonts.regular,
      6,
      COLOR_GRAY_TEXT,
    );

    drawLine(page, MARGIN, curY - ROW_H, MARGIN + CONTENT_WIDTH, curY - ROW_H, 0.2, COLOR_GRAY_TEXT);
    curY -= ROW_H;
  }

  drawRect(page, MARGIN, curY, CONTENT_WIDTH, startY - curY, undefined, COLOR_GRAY_TEXT, 0.5);
  return { page, curY };
}

// ---------------------------------------------------------------------------
// Sección 5: Resumen de impuestos y totales
// ---------------------------------------------------------------------------

function drawResumenTotales(
  page: PDFPage,
  ctx: RideContext,
  startY: number,
  esRetencion: boolean,
): number {
  const { fonts, data } = ctx;
  const PADDING = 4;
  const rightW  = CONTENT_WIDTH * 0.42;
  const rightX  = MARGIN + CONTENT_WIDTH - rightW;

  type TRow = [string, number, boolean]; // [label, value, isBold]
  const rows: TRow[] = [];

  if (esRetencion) {
    // Totales por tipo de retención
    const totalIR  = (data.retenciones ?? [])
      .filter((r) => r.codigoRetencion.startsWith('3') || r.codigoRetencion.startsWith('1'))
      .reduce((s, r) => s + r.valorRetenido, 0);
    const totalIVA = (data.retenciones ?? [])
      .filter((r) => r.codigoRetencion.startsWith('7') || r.codigoRetencion.startsWith('9'))
      .reduce((s, r) => s + r.valorRetenido, 0);
    const totalRet = (data.retenciones ?? []).reduce((s, r) => s + r.valorRetenido, 0);

    if (totalIR  > 0) rows.push(['Total Retenido IR:', totalIR, false]);
    if (totalIVA > 0) rows.push(['Total Retenido IVA:', totalIVA, false]);
    rows.push(['TOTAL RETENIDO:', totalRet, true]);
  } else {
    // Impuestos por código
    for (const imp of data.totalConImpuestos) {
      const label = imp.descripcion
        ? `${imp.descripcion}:`
        : `IVA (${imp.codigoPorcentaje}):`;
      rows.push([label, imp.valor, false]);
    }

    if (data.totalSinImpuestos !== undefined) {
      rows.unshift(['Subtotal sin imp.:', data.totalSinImpuestos, false]);
    }
    if (data.totalDescuento !== undefined && data.totalDescuento > 0) {
      rows.push(['Descuento:', data.totalDescuento, false]);
    }
    if (data.propina !== undefined && data.propina > 0) {
      rows.push(['Propina:', data.propina, false]);
    }
    if (data.importeTotal !== undefined) {
      rows.push(['TOTAL:', data.importeTotal, true]);
    }
  }

  const ROW_H   = 13;
  const boxH    = rows.length * ROW_H + PADDING * 2;
  const boxBottom = startY - boxH;

  drawRect(page, rightX, boxBottom, rightW, boxH, COLOR_GRAY_BG, COLOR_GRAY_TEXT, 0.5);

  let curY = startY - PADDING;
  for (const [label, value, isBold] of rows) {
    const font  = isBold ? fonts.bold : fonts.regular;
    const yText = curY - 8;

    drawText(page, label, rightX + PADDING, yText, font, 8, COLOR_GRAY_TEXT);
    drawTextRight(
      page,
      formatMoney(value),
      rightX + PADDING,
      yText,
      rightW - PADDING * 2,
      isBold ? fonts.bold : fonts.regular,
      8,
      isBold ? COLOR_PILAR_BLUE : COLOR_BLACK,
    );

    if (isBold) {
      drawLine(page, rightX + PADDING, curY - ROW_H + 1, rightX + rightW - PADDING, curY - ROW_H + 1, 0.5, COLOR_PILAR_BLUE);
    }

    curY -= ROW_H;
  }

  return boxBottom - 4;
}

// ---------------------------------------------------------------------------
// Sección 6: Forma de pago
// ---------------------------------------------------------------------------

function drawFormasPago(
  page: PDFPage,
  ctx: RideContext,
  startY: number,
): number {
  const { fonts, data } = ctx;
  const pagos = data.pagos ?? [];
  if (pagos.length === 0) return startY;

  const PADDING   = 4;
  const leftW     = CONTENT_WIDTH * 0.56;
  const leftX     = MARGIN;
  const headerH   = 13;
  const ROW_H     = 12;
  const boxH      = headerH + pagos.length * ROW_H + PADDING;
  const boxBottom = startY - boxH;

  // Encabezado
  drawRect(page, leftX, startY - headerH, leftW, headerH, COLOR_PILAR_BLUE, undefined);
  drawText(page, 'FORMA DE PAGO', leftX + PADDING, startY - headerH + 3, fonts.bold, 7, COLOR_WHITE);
  drawTextRight(
    page,
    'TOTAL',
    leftX + PADDING,
    startY - headerH + 3,
    leftW - PADDING * 2,
    fonts.bold,
    7,
    COLOR_WHITE,
  );

  let curY = startY - headerH;
  for (let i = 0; i < pagos.length; i++) {
    const pago  = pagos[i];
    const isEven = i % 2 === 0;
    drawRect(page, leftX, curY - ROW_H, leftW, ROW_H, isEven ? COLOR_WHITE : COLOR_GRAY_BG, undefined);

    const yText = curY - ROW_H + 2;
    const desc  = truncateText(pago.descripcion || pago.formaPago, fonts.regular, 7, leftW * 0.7 - PADDING);
    drawText(page, desc, leftX + PADDING, yText, fonts.regular, 7, COLOR_BLACK);
    drawTextRight(page, formatMoney(pago.total), leftX + PADDING, yText, leftW - PADDING * 2, fonts.bold, 7);

    drawLine(page, leftX, curY - ROW_H, leftX + leftW, curY - ROW_H, 0.2, COLOR_GRAY_TEXT);
    curY -= ROW_H;
  }

  drawRect(page, leftX, boxBottom, leftW, boxH, undefined, COLOR_GRAY_TEXT, 0.5);
  return boxBottom - 6;
}

// ---------------------------------------------------------------------------
// Sección 7: Información adicional
// ---------------------------------------------------------------------------

function drawInfoAdicional(
  page: PDFPage,
  ctx: RideContext,
  startY: number,
): number {
  const { fonts, data } = ctx;
  const campos = data.infoAdicional ?? [];
  if (campos.length === 0) return startY;

  const PADDING = 4;
  const ROW_H   = 11;
  const headerH = 12;
  const boxH    = headerH + campos.length * ROW_H + PADDING;
  const boxBottom = startY - boxH;

  drawRect(page, MARGIN, startY - headerH, CONTENT_WIDTH, headerH, COLOR_GRAY_BG, undefined);
  drawText(page, 'INFORMACIÓN ADICIONAL', MARGIN + PADDING, startY - headerH + 3, fonts.bold, 7, COLOR_GRAY_TEXT);

  let curY = startY - headerH;
  const halfW = CONTENT_WIDTH / 2;
  for (let i = 0; i < campos.length; i++) {
    const campo  = campos[i];
    const isEven = i % 2 === 0;
    drawRect(page, MARGIN, curY - ROW_H, CONTENT_WIDTH, ROW_H, isEven ? COLOR_WHITE : COLOR_GRAY_BG, undefined);

    const yText = curY - ROW_H + 2;
    drawText(page, truncateText(campo.nombre, fonts.bold, 7, halfW - PADDING * 2 - 2), MARGIN + PADDING, yText, fonts.bold, 7, COLOR_GRAY_TEXT);
    drawText(
      page,
      truncateText(campo.valor, fonts.regular, 7, halfW - PADDING * 2),
      MARGIN + halfW,
      yText,
      fonts.regular,
      7,
      COLOR_BLACK,
    );

    drawLine(page, MARGIN, curY - ROW_H, MARGIN + CONTENT_WIDTH, curY - ROW_H, 0.2, COLOR_GRAY_TEXT);
    curY -= ROW_H;
  }

  drawRect(page, MARGIN, boxBottom, CONTENT_WIDTH, boxH, undefined, COLOR_GRAY_TEXT, 0.5);
  return boxBottom - 6;
}

// ---------------------------------------------------------------------------
// Sección especial: Guía de remisión
// ---------------------------------------------------------------------------

function drawGuiaRemision(
  page: PDFPage,
  ctx: RideContext,
  startY: number,
): number {
  const { fonts, data } = ctx;
  const guia = data.guiaRemision;
  if (!guia) return startY;

  const PADDING = 4;
  type Row = [string, string, string, string];
  const rows: Row[] = [
    ['Dir. partida:',        guia.dirPartida,               'Transportista:',         guia.razonSocialTransportista],
    ['RUC Transportista:',   guia.rucTransportista,         'Placa:',                 guia.placa],
    ['Fecha inicio transp.:', formatFecha(guia.fechaIniTransporte), 'Fecha fin transp.:', formatFecha(guia.fechaFinTransporte)],
  ];

  const ROW_H   = 13;
  const headerH = 12;
  const boxH    = headerH + rows.length * ROW_H + PADDING;
  const boxBottom = startY - boxH;
  const halfW   = CONTENT_WIDTH / 2;

  drawRect(page, MARGIN, startY - headerH, CONTENT_WIDTH, headerH, COLOR_PILAR_BLUE, undefined);
  drawText(page, 'DATOS DE TRANSPORTE', MARGIN + PADDING, startY - headerH + 3, fonts.bold, 7, COLOR_WHITE);

  let curY = startY - headerH;
  for (const [lLabel, lVal, rLabel, rVal] of rows) {
    drawRect(page, MARGIN, curY - ROW_H, CONTENT_WIDTH, ROW_H, COLOR_GRAY_BG, undefined);

    const yText  = curY - ROW_H + 2;
    const lLabelW = fonts.bold.widthOfTextAtSize(lLabel, 7);

    drawText(page, lLabel, MARGIN + PADDING, yText, fonts.bold, 7, COLOR_GRAY_TEXT);
    drawText(
      page,
      truncateText(lVal, fonts.regular, 7, halfW - lLabelW - PADDING * 3),
      MARGIN + PADDING + lLabelW + 4,
      yText,
      fonts.regular,
      7,
      COLOR_BLACK,
    );

    if (rLabel) {
      const rLabelW = fonts.bold.widthOfTextAtSize(rLabel, 7);
      drawText(page, rLabel, MARGIN + halfW + PADDING, yText, fonts.bold, 7, COLOR_GRAY_TEXT);
      drawText(
        page,
        truncateText(rVal, fonts.regular, 7, halfW - rLabelW - PADDING * 3),
        MARGIN + halfW + PADDING + rLabelW + 4,
        yText,
        fonts.regular,
        7,
        COLOR_BLACK,
      );
    }

    drawLine(page, MARGIN, curY - ROW_H, MARGIN + CONTENT_WIDTH, curY - ROW_H, 0.2, COLOR_GRAY_TEXT);
    curY -= ROW_H;
  }

  drawRect(page, MARGIN, boxBottom, CONTENT_WIDTH, boxH, undefined, COLOR_GRAY_TEXT, 0.5);
  return boxBottom - 6;
}

// ---------------------------------------------------------------------------
// Pie de página
// ---------------------------------------------------------------------------

function drawFooter(page: PDFPage, fonts: RideFonts, pageNum: number, totalPages: number): void {
  const text = totalPages > 1
    ? `Documento electrónico generado por PILAR ERP  |  Página ${pageNum} de ${totalPages}`
    : 'Documento electrónico generado por PILAR ERP';

  const textW = fonts.regular.widthOfTextAtSize(text, 6);
  const xCenter = MARGIN + (CONTENT_WIDTH - textW) / 2;

  drawText(page, text, Math.max(MARGIN, xCenter), MARGIN - 6, fonts.regular, 6, COLOR_GRAY_TEXT);

  // Línea separadora del pie
  drawLine(page, MARGIN, MARGIN + 4, MARGIN + CONTENT_WIDTH, MARGIN + 4, 0.5, COLOR_GRAY_TEXT);
}

// ---------------------------------------------------------------------------
// Helper: añadir nueva página y redibujar header compacto
// ---------------------------------------------------------------------------

async function addNewPage(
  ctx: RideContext,
  pages: PDFPage[],
  addWatermark: boolean,
): Promise<PDFPage> {
  const page = ctx.pdfDoc.addPage(PageSizes.A4);
  pages.push(page);

  if (addWatermark) {
    addWatermarkPruebas(page, ctx.fonts);
  }

  // Header compacto: solo tipo de documento y número
  const { fonts, data } = ctx;
  const tipoDoc = getNombreTipoDoc(data.infoTributaria.codDoc);
  const label   = `${tipoDoc} ${data.infoTributaria.numeroDocumento} — continuación`;
  drawText(
    page,
    label,
    MARGIN,
    PAGE_HEIGHT - MARGIN - 4,
    fonts.bold,
    8,
    COLOR_PILAR_BLUE,
  );
  drawLine(
    page,
    MARGIN,
    PAGE_HEIGHT - MARGIN - 14,
    MARGIN + CONTENT_WIDTH,
    PAGE_HEIGHT - MARGIN - 14,
    0.5,
    COLOR_PILAR_BLUE,
  );

  return page;
}

// ---------------------------------------------------------------------------
// Función principal exportada
// ---------------------------------------------------------------------------

/**
 * Genera el RIDE (Representación Impresa del Documento Electrónico) como PDF.
 *
 * @param data - Datos completos para generar el RIDE (autorizacion, emisor, receptor, detalles, etc.)
 * @returns Uint8Array con el PDF generado, listo para subir a Supabase Storage.
 */
export async function generarRidePdf(data: RideData): Promise<Uint8Array> {
  // Crear documento PDF
  const pdfDoc = await PDFDocument.create();
  pdfDoc.setTitle(`RIDE ${getNombreTipoDoc(data.infoTributaria.codDoc)} ${data.infoTributaria.numeroDocumento}`);
  pdfDoc.setAuthor('PILAR ERP');
  pdfDoc.setSubject(`RUC: ${data.infoTributaria.ruc}`);
  pdfDoc.setCreator('PILAR ERP — ride-pdf.ts');
  pdfDoc.setProducer('pdf-lib 1.17.1');

  // Incrustar fuentes estándar
  const fontRegular = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold    = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  const fontCourier = await pdfDoc.embedFont(StandardFonts.Courier);

  const fonts: RideFonts = {
    regular: fontRegular,
    bold:    fontBold,
    courier: fontCourier,
  };

  const ctx: RideContext = { pdfDoc, fonts, data };

  // Determinar si es ambiente de pruebas (para marca de agua)
  const esPruebas = data.autorizacion.ambiente !== 'PRODUCCION' ||
                    data.infoTributaria.ambiente !== '2';
  const esRetencion   = data.infoTributaria.codDoc === '07';
  const tieneDetalles = (data.detalles ?? []).length > 0;

  // Primera página
  const firstPage = pdfDoc.addPage(PageSizes.A4);
  const pages: PDFPage[] = [firstPage];

  if (esPruebas) {
    addWatermarkPruebas(firstPage, fonts);
  }

  // --- Cursor Y inicial ---
  let curY = PAGE_HEIGHT - MARGIN;

  // Sección 1: Header emisor
  curY = await drawHeaderEmisor(firstPage, ctx, curY);
  curY -= 6;

  // Sección 2: Clave de acceso
  curY = drawClaveAcceso(firstPage, ctx, curY);
  curY -= 6;

  // Sección 3: Datos del receptor
  curY = drawDatosReceptor(firstPage, ctx, curY);
  curY -= 6;

  // Guía de remisión (datos de transporte) si aplica
  if (data.guiaRemision) {
    curY = drawGuiaRemision(firstPage, ctx, curY);
    curY -= 6;
  }

  // Sección NC/ND: documento modificado y motivo
  if (data.numDocModificado) {
    curY = drawSeccionDocModificado(firstPage, ctx, curY);
    curY -= 6;
  }

  // -------------------------------------------------------------------------
  // Sección 4: Tabla de detalles o retenciones
  // -------------------------------------------------------------------------

  let lastPage = firstPage;

  if (esRetencion && (data.retenciones ?? []).length > 0) {
    // Header de tabla retenciones
    curY = drawRetencionHeader(firstPage, fonts, curY);

    // Filas de retenciones (con paginación automática)
    const retResult = await drawRetencionRows(ctx, pages, firstPage, curY, esPruebas);
    lastPage = retResult.page;
    curY     = retResult.curY - 6;

  } else if (tieneDetalles) {
    // Header de tabla detalles
    curY = drawDetalleHeader(firstPage, fonts, curY);

    // Filas de detalles (con paginación automática)
    const detResult = await drawDetalleRows(ctx, pages, firstPage, curY, esPruebas);
    lastPage = detResult.page;
    curY     = detResult.curY - 6;
  }

  // -------------------------------------------------------------------------
  // Secciones 5 y 6: Totales + Forma de pago (en la última página)
  // -------------------------------------------------------------------------

  // Verificar que quede espacio suficiente; si no, nueva página
  const TOTALES_EST_H = (data.totalConImpuestos.length + 4) * 13 + 20;
  const PAGOS_EST_H   = ((data.pagos ?? []).length + 1) * 13 + 20;
  const MINIMO_REQUERIDO = Math.max(TOTALES_EST_H, PAGOS_EST_H) + 30;

  if (curY - MINIMO_REQUERIDO < MARGIN_BOTTOM) {
    lastPage = await addNewPage(ctx, pages, esPruebas);
    curY = PAGE_HEIGHT - MARGIN - 30;
  }

  const totalesBottom = drawResumenTotales(lastPage, ctx, curY, esRetencion);
  drawFormasPago(lastPage, ctx, curY);

  curY = totalesBottom - 6;

  // -------------------------------------------------------------------------
  // Sección 7: Información adicional
  // -------------------------------------------------------------------------

  if ((data.infoAdicional ?? []).length > 0) {
    const infoH = (data.infoAdicional.length + 1) * 12 + 20;
    if (curY - infoH < MARGIN_BOTTOM) {
      lastPage = await addNewPage(ctx, pages, esPruebas);
      curY = PAGE_HEIGHT - MARGIN - 30;
    }
    curY = drawInfoAdicional(lastPage, ctx, curY);
  }

  // -------------------------------------------------------------------------
  // Pie de página en todas las páginas
  // -------------------------------------------------------------------------

  const totalPages = pages.length;
  for (let i = 0; i < pages.length; i++) {
    drawFooter(pages[i], fonts, i + 1, totalPages);
  }

  // -------------------------------------------------------------------------
  // Serializar y retornar
  // -------------------------------------------------------------------------

  const pdfBytes = await pdfDoc.save();
  return pdfBytes;
}
