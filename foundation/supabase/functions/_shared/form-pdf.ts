/**
 * PILAR ERP — _shared/form-pdf.ts
 *
 * Utilidades para generar PDFs de formularios gubernamentales (F-103, F-104, F-101).
 * Usa pdf-lib exclusivamente. No requiere fuentes externas ni dependencias adicionales.
 *
 * Convención de layout:
 *   - Tamaño de página: Letter (612 x 792 pts) por defecto.
 *   - Márgenes: 40 pts en todos los lados.
 *   - Header institucional SRI en cada página.
 *   - Fuentes estándar: Helvetica (regular) y Helvetica-Bold (bold).
 *
 * Exporta:
 *   createFormPdf(config)              → crea PDFDocument con header SRI
 *   drawSection(page, section, fonts)  → dibuja bloque de sección con campos
 *   drawTable(page, headers, rows, ...) → dibuja tabla simple con header azul
 *   fmtMonto(n)                        → formatea moneda ecuatoriana
 *   fmtPct(n)                          → formatea porcentaje
 *   finalizePdf(doc)                   → serializa a Uint8Array
 *
 * Tipos reexportados:
 *   FormField, FormSection, FormPageConfig
 */

import {
  PDFDocument,
  PDFPage,
  PDFFont,
  StandardFonts,
  rgb,
  type RGB,
} from 'npm:pdf-lib@1.17.1';

// ---------------------------------------------------------------------------
// Re-exportar tipos de pdf-lib que los archivos consumidores necesitan
// ---------------------------------------------------------------------------
export type { PDFDocument, PDFPage, PDFFont };

// ---------------------------------------------------------------------------
// Interfaces públicas
// ---------------------------------------------------------------------------

export interface FormField {
  label: string;
  value: string | number;
  x: number;
  y: number;
  width?: number;
  fontSize?: number;
  bold?: boolean;
  align?: 'left' | 'right' | 'center';
}

export interface FormSection {
  title: string;
  titleX: number;
  titleY: number;
  fields: FormField[];
}

export interface FormPageConfig {
  /** Título principal del formulario, ej: "FORMULARIO 103 - RETENCIONES EN LA FUENTE" */
  title: string;
  /** Subtítulo institucional, ej: "SRI - Servicio de Rentas Internas" */
  subtitle: string;
  /** Período de la declaración, ej: "Período: 02/2026" */
  periodo?: string;
  /** Ancho en puntos. Default: 612 (Letter portrait) */
  width?: number;
  /** Alto en puntos. Default: 792 (Letter portrait) */
  height?: number;
}

// ---------------------------------------------------------------------------
// Constantes de layout y paleta de colores
// ---------------------------------------------------------------------------

const DEFAULT_PAGE_WIDTH  = 612; // Letter
const DEFAULT_PAGE_HEIGHT = 792; // Letter
const MARGIN              = 40;

const COLOR_SRI_BLUE:  RGB = rgb(0.008, 0.329, 0.604); // #0255 — azul institucional SRI
const COLOR_DARK:      RGB = rgb(0.1,   0.1,   0.1);
const COLOR_GRAY:      RGB = rgb(0.4,   0.4,   0.4);
const COLOR_GRAY_BG:   RGB = rgb(0.94,  0.94,  0.94);
const COLOR_WHITE:     RGB = rgb(1,     1,     1);
const COLOR_BLACK:     RGB = rgb(0,     0,     0);
const COLOR_HIGHLIGHT: RGB = rgb(0.85,  0.92,  1.0);   // Fondo alternado tabla

/** Altura del header institucional en puntos. */
const HEADER_HEIGHT = 60;

// ---------------------------------------------------------------------------
// Helpers internos de renderizado
// ---------------------------------------------------------------------------

function drawRect(
  page: PDFPage,
  x: number,
  y: number,
  w: number,
  h: number,
  fill?: RGB,
  stroke?: RGB,
  strokeWidth = 0.5,
): void {
  page.drawRectangle({
    x, y, width: w, height: h,
    color:       fill,
    borderColor: stroke,
    borderWidth: stroke ? strokeWidth : undefined,
  });
}

function drawLine(
  page: PDFPage,
  x1: number, y1: number,
  x2: number, y2: number,
  thickness = 0.5,
  color: RGB = COLOR_GRAY,
): void {
  page.drawLine({
    start: { x: x1, y: y1 },
    end:   { x: x2, y: y2 },
    thickness, color,
  });
}

function drawText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  font: PDFFont,
  size: number,
  color: RGB = COLOR_DARK,
): void {
  if (!text) return;
  page.drawText(text, { x, y, font, size, color });
}

function textWidth(text: string, font: PDFFont, size: number): number {
  return font.widthOfTextAtSize(text, size);
}

function drawTextRight(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  colWidth: number,
  font: PDFFont,
  size: number,
  color: RGB = COLOR_DARK,
): void {
  const tw = textWidth(text, font, size);
  drawText(page, text, Math.max(x, x + colWidth - tw), y, font, size, color);
}

function drawTextCenter(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  colWidth: number,
  font: PDFFont,
  size: number,
  color: RGB = COLOR_DARK,
): void {
  const tw = textWidth(text, font, size);
  drawText(page, text, x + Math.max(0, (colWidth - tw) / 2), y, font, size, color);
}

// ---------------------------------------------------------------------------
// Función principal: createFormPdf
// ---------------------------------------------------------------------------

/**
 * Crea un nuevo PDFDocument con una primera página y dibuja el header
 * institucional del SRI.
 *
 * Retorna:
 *   doc   — el PDFDocument para añadir más páginas o finalizar
 *   page  — la primera página (ya con el header dibujado)
 *   fonts — { regular, bold } para usar en el resto del formulario
 *
 * El cursor de contenido debe comenzar en:
 *   y = pageHeight - margin - HEADER_HEIGHT - 8
 */
export async function createFormPdf(config: FormPageConfig): Promise<{
  doc: PDFDocument;
  page: PDFPage;
  fonts: { regular: PDFFont; bold: PDFFont };
  contentStartY: number;
  pageWidth: number;
  pageHeight: number;
  contentWidth: number;
  margin: number;
}> {
  const pageWidth  = config.width  ?? DEFAULT_PAGE_WIDTH;
  const pageHeight = config.height ?? DEFAULT_PAGE_HEIGHT;
  const contentWidth = pageWidth - MARGIN * 2;

  const doc = await PDFDocument.create();
  doc.setTitle(config.title);
  doc.setAuthor('PILAR ERP');
  doc.setSubject(config.subtitle);
  doc.setCreator('PILAR ERP — form-pdf.ts');
  doc.setProducer('pdf-lib 1.17.1');

  const regular = await doc.embedFont(StandardFonts.Helvetica);
  const bold    = await doc.embedFont(StandardFonts.HelveticaBold);
  const fonts   = { regular, bold };

  const page = doc.addPage([pageWidth, pageHeight]);

  // Dibuja el header en la primera página
  drawFormHeader(page, config, fonts, pageWidth, pageHeight, contentWidth);

  const contentStartY = pageHeight - MARGIN - HEADER_HEIGHT - 10;

  return { doc, page, fonts, contentStartY, pageWidth, pageHeight, contentWidth, margin: MARGIN };
}

// ---------------------------------------------------------------------------
// Header institucional SRI
// ---------------------------------------------------------------------------

/**
 * Dibuja el header del formulario:
 *   [SRI]  |  Título centrado  |  Período (derecha)
 *   ─────────────────────────────────────────────
 */
function drawFormHeader(
  page: PDFPage,
  config: FormPageConfig,
  fonts: { regular: PDFFont; bold: PDFFont },
  pageWidth: number,
  pageHeight: number,
  contentWidth: number,
): void {
  const top    = pageHeight - MARGIN;
  const left   = MARGIN;
  const PADDING = 6;

  // Fondo azul del header
  drawRect(page, left, top - HEADER_HEIGHT, contentWidth, HEADER_HEIGHT, COLOR_SRI_BLUE);

  // Logo "SRI" texto (columna izquierda, ~18% del ancho)
  const logoColW = contentWidth * 0.18;
  drawText(page, 'SRI', left + PADDING, top - 22, fonts.bold, 22, COLOR_WHITE);
  drawText(
    page,
    'Servicio de',
    left + PADDING,
    top - 34,
    fonts.regular,
    7,
    COLOR_WHITE,
  );
  drawText(
    page,
    'Rentas Internas',
    left + PADDING,
    top - 43,
    fonts.regular,
    7,
    COLOR_WHITE,
  );

  // Separador vertical
  drawLine(
    page,
    left + logoColW, top - HEADER_HEIGHT + 8,
    left + logoColW, top - 8,
    0.5,
    COLOR_WHITE,
  );

  // Columna derecha para período (~22% del ancho)
  const periodoColW = contentWidth * 0.22;
  const periodoX    = left + contentWidth - periodoColW;

  // Separador vertical derecho
  drawLine(
    page,
    periodoX - 4, top - HEADER_HEIGHT + 8,
    periodoX - 4, top - 8,
    0.5,
    COLOR_WHITE,
  );

  // Período (derecha del header)
  if (config.periodo) {
    const periodoFontSize = 8;
    const periodoY = top - 20;
    drawText(page, 'PERÍODO:', periodoX + PADDING, periodoY, fonts.bold, 7, COLOR_WHITE);
    drawText(page, config.periodo, periodoX + PADDING, periodoY - 12, fonts.regular, 8, COLOR_WHITE);
  }

  // Título principal (columna central)
  const titleAreaX = left + logoColW + 8;
  const titleAreaW = contentWidth - logoColW - periodoColW - 16;

  // Subtítulo arriba
  const subtitleY = top - 14;
  drawTextCenter(page, config.subtitle, titleAreaX, subtitleY, titleAreaW, fonts.regular, 7, COLOR_WHITE);

  // Título principal (grande, negrita)
  const titleY = subtitleY - 14;
  const titleFontSize = 11;
  drawTextCenter(page, config.title, titleAreaX, titleY, titleAreaW, fonts.bold, titleFontSize, COLOR_WHITE);

  // Línea separadora bajo el header
  const lineY = top - HEADER_HEIGHT - 2;
  drawLine(page, left, lineY, left + contentWidth, lineY, 1.0, COLOR_SRI_BLUE);
}

// ---------------------------------------------------------------------------
// drawSection — bloque de sección con título y lista de campos clave-valor
// ---------------------------------------------------------------------------

/**
 * Dibuja una sección de formulario con:
 *   - Barra de título azul
 *   - Lista de campos en grid de 2 columnas (label: value)
 *
 * Los campos se renderizan en el orden dado por `section.fields`.
 * La posición (x, y) de cada campo es relativa a la página.
 */
export function drawSection(
  page: PDFPage,
  section: FormSection,
  fonts: { regular: PDFFont; bold: PDFFont },
): void {
  const PADDING   = 5;
  const TITLE_H   = 16;
  const FIELD_H   = 14;
  const titleBarW = 532; // ancho fijo para barra de título (contentWidth típico)

  // Barra de título
  drawRect(page, section.titleX, section.titleY - TITLE_H, titleBarW, TITLE_H, COLOR_SRI_BLUE);
  drawText(
    page,
    section.title.toUpperCase(),
    section.titleX + PADDING,
    section.titleY - TITLE_H + 4,
    fonts.bold,
    8,
    COLOR_WHITE,
  );

  // Campos
  let fieldCursor = section.titleY - TITLE_H - PADDING;
  for (const field of section.fields) {
    const fs   = field.fontSize ?? 8;
    const font = field.bold ? fonts.bold : fonts.regular;
    const colW = field.width ?? 250;

    // Label (gris)
    const labelStr = `${field.label}:`;
    drawText(page, labelStr, field.x, fieldCursor, fonts.bold, 7, COLOR_GRAY);

    // Value
    const labelW  = textWidth(labelStr, fonts.bold, 7);
    const valueStr = typeof field.value === 'number' ? fmtMonto(field.value) : field.value;
    const valueX   = field.x + labelW + 4;

    if (field.align === 'right') {
      drawTextRight(page, valueStr, field.x, fieldCursor, colW, font, fs, COLOR_DARK);
    } else if (field.align === 'center') {
      drawTextCenter(page, valueStr, valueX, fieldCursor, colW - labelW - 4, font, fs, COLOR_DARK);
    } else {
      drawText(page, valueStr, valueX, fieldCursor, font, fs, COLOR_DARK);
    }

    fieldCursor -= FIELD_H;
  }
}

// ---------------------------------------------------------------------------
// drawTable — tabla genérica con header azul y filas alternadas
// ---------------------------------------------------------------------------

/**
 * Dibuja una tabla simple.
 *
 * @param page      — página donde dibujar
 * @param headers   — textos del encabezado
 * @param rows      — filas de datos (array de arrays de strings)
 * @param x         — coordenada X izquierda de la tabla
 * @param y         — coordenada Y superior de la tabla (se dibuja hacia abajo)
 * @param colWidths — ancho de cada columna en puntos
 * @param fonts     — { regular, bold }
 * @param rowHeight — alto de cada fila (default: 14)
 * @returns         Y final (cursor para continuar debajo de la tabla)
 */
export function drawTable(
  page: PDFPage,
  headers: string[],
  rows: string[][],
  x: number,
  y: number,
  colWidths: number[],
  fonts: { regular: PDFFont; bold: PDFFont },
  rowHeight = 14,
): number {
  const PADDING    = 4;
  const HEADER_H   = 16;
  const totalWidth = colWidths.reduce((s, w) => s + w, 0);

  // ---- Header ----
  drawRect(page, x, y - HEADER_H, totalWidth, HEADER_H, COLOR_SRI_BLUE);

  let hx = x;
  for (let i = 0; i < headers.length; i++) {
    const colW  = colWidths[i];
    const isNum = isNumericHeader(headers[i]);

    if (isNum) {
      drawTextRight(page, headers[i], hx + PADDING, y - HEADER_H + 4, colW - PADDING * 2, fonts.bold, 7, COLOR_WHITE);
    } else {
      drawText(page, headers[i], hx + PADDING, y - HEADER_H + 4, fonts.bold, 7, COLOR_WHITE);
    }
    hx += colW;
  }

  // ---- Filas ----
  let curY = y - HEADER_H;

  for (let r = 0; r < rows.length; r++) {
    const row    = rows[r];
    const isEven = r % 2 === 0;
    drawRect(page, x, curY - rowHeight, totalWidth, rowHeight, isEven ? COLOR_WHITE : COLOR_GRAY_BG);

    let rx = x;
    for (let c = 0; c < colWidths.length; c++) {
      const colW   = colWidths[c];
      const cell   = row[c] ?? '';
      const isNum  = isNumericCell(cell);
      const yText  = curY - rowHeight + 4;

      if (isNum) {
        drawTextRight(page, cell, rx + PADDING, yText, colW - PADDING * 2, fonts.regular, 7, COLOR_DARK);
      } else {
        // Truncar si excede el ancho de columna
        const maxW  = colW - PADDING * 2;
        const disp  = truncate(cell, fonts.regular, 7, maxW);
        drawText(page, disp, rx + PADDING, yText, fonts.regular, 7, COLOR_DARK);
      }

      rx += colW;
    }

    // Línea inferior de fila
    drawLine(page, x, curY - rowHeight, x + totalWidth, curY - rowHeight, 0.3, COLOR_GRAY);
    curY -= rowHeight;
  }

  // Borde exterior de la tabla
  drawRect(page, x, curY, totalWidth, y - curY, undefined, COLOR_SRI_BLUE, 0.5);

  return curY - 6; // cursor con pequeño gap
}

// ---------------------------------------------------------------------------
// drawTotalesBox — caja de totales (alineada a la derecha)
// ---------------------------------------------------------------------------

/**
 * Dibuja una caja de totales alineada a la derecha con filas label-valor.
 * La última fila se resalta con fondo azul claro y texto bold.
 *
 * @param page      — página
 * @param rows      — [['Label', '1.234,56'], ...]
 * @param x         — X inicial de la caja
 * @param y         — Y superior de la caja
 * @param boxWidth  — ancho total de la caja
 * @param fonts     — { regular, bold }
 * @returns         Y final (cursor debajo de la caja)
 */
export function drawTotalesBox(
  page: PDFPage,
  rows: Array<[string, string]>,
  x: number,
  y: number,
  boxWidth: number,
  fonts: { regular: PDFFont; bold: PDFFont },
): number {
  const PADDING  = 5;
  const ROW_H    = 14;
  const boxH     = rows.length * ROW_H + PADDING;

  drawRect(page, x, y - boxH, boxWidth, boxH, COLOR_GRAY_BG, COLOR_SRI_BLUE, 0.5);

  let curY = y - PADDING;
  for (let i = 0; i < rows.length; i++) {
    const [label, value] = rows[i];
    const isLast = i === rows.length - 1;
    const yText  = curY - ROW_H + 4;
    const font   = isLast ? fonts.bold : fonts.regular;
    const fg     = isLast ? COLOR_SRI_BLUE : COLOR_DARK;

    if (isLast) {
      drawRect(page, x + 1, curY - ROW_H, boxWidth - 2, ROW_H - 1, COLOR_HIGHLIGHT);
    }

    drawText(page, label, x + PADDING, yText, font, 8, COLOR_GRAY);
    drawTextRight(page, value, x + PADDING, yText, boxWidth - PADDING * 2, font, 8, fg);

    drawLine(page, x, curY - ROW_H, x + boxWidth, curY - ROW_H, 0.3, COLOR_GRAY);
    curY -= ROW_H;
  }

  return y - boxH - 6;
}

// ---------------------------------------------------------------------------
// drawNota — nota informativa al pie del formulario
// ---------------------------------------------------------------------------

/**
 * Dibuja un bloque de nota informativa con fondo gris claro.
 *
 * @param page   — página
 * @param nota   — texto de la nota
 * @param x      — X inicial
 * @param y      — Y superior
 * @param width  — ancho del bloque
 * @param fonts  — { regular, bold }
 * @returns      Y final (cursor debajo del bloque)
 */
export function drawNota(
  page: PDFPage,
  nota: string,
  x: number,
  y: number,
  width: number,
  fonts: { regular: PDFFont; bold: PDFFont },
): number {
  const PADDING  = 6;
  const FS       = 7;
  const lineH    = 10;

  // Wrap automático
  const lines = wrapText(nota, fonts.regular, FS, width - PADDING * 2);
  const boxH  = PADDING * 2 + lines.length * lineH;

  drawRect(page, x, y - boxH, width, boxH, COLOR_GRAY_BG, COLOR_GRAY, 0.5);

  // Prefijo "NOTA:"
  drawText(page, 'NOTA:', x + PADDING, y - PADDING - FS, fonts.bold, FS, COLOR_GRAY);
  const notaLabelW = textWidth('NOTA: ', fonts.bold, FS);

  let firstLine = true;
  let curY = y - PADDING;
  for (const line of lines) {
    const lx = firstLine ? x + PADDING + notaLabelW : x + PADDING;
    drawText(page, line, lx, curY - FS - 1, fonts.regular, FS, COLOR_GRAY);
    curY -= lineH;
    firstLine = false;
  }

  return y - boxH - 6;
}

// ---------------------------------------------------------------------------
// drawFooter — pie de página
// ---------------------------------------------------------------------------

/**
 * Dibuja el pie de página en la posición estándar.
 * Llamar al final, antes de finalizar el PDF.
 */
export function drawFooter(
  page: PDFPage,
  fonts: { regular: PDFFont; bold: PDFFont },
  pageNum: number,
  totalPages: number,
  pageWidth: number,
): void {
  const FOOTER_Y = 28;
  const left     = MARGIN;
  const width    = pageWidth - MARGIN * 2;

  drawLine(page, left, FOOTER_Y + 8, left + width, FOOTER_Y + 8, 0.5, COLOR_GRAY);

  const label = totalPages > 1
    ? `Resumen generado por PILAR ERP  |  Página ${pageNum} de ${totalPages}`
    : 'Resumen generado por PILAR ERP — para uso de referencia del contador';

  const lw = textWidth(label, fonts.regular, 6);
  drawText(page, label, left + (width - lw) / 2, FOOTER_Y, fonts.regular, 6, COLOR_GRAY);
}

// ---------------------------------------------------------------------------
// finalizePdf — serializa el documento
// ---------------------------------------------------------------------------

/**
 * Serializa el PDFDocument a Uint8Array listo para subir a Storage.
 */
export async function finalizePdf(doc: PDFDocument): Promise<Uint8Array> {
  return doc.save();
}

// ---------------------------------------------------------------------------
// Formatters públicos
// ---------------------------------------------------------------------------

/**
 * Formatea un número como monto en estilo ecuatoriano: 1234567.89 → "1.234.567,89"
 */
export function fmtMonto(n: number): string {
  if (n === undefined || n === null || isNaN(n)) return '0,00';
  // toFixed garantiza 2 decimales
  const fixed = n.toFixed(2);
  const [intPart, decPart] = fixed.split('.');
  // Separador de miles: punto
  const intFormatted = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${intFormatted},${decPart}`;
}

/**
 * Formatea un número como porcentaje: 12.5 → "12,50%"
 */
export function fmtPct(n: number): string {
  if (n === undefined || n === null || isNaN(n)) return '0,00%';
  return `${n.toFixed(2).replace('.', ',')}%`;
}

/**
 * Formatea mes/año como "MM/YYYY": (2, 2026) → "02/2026"
 */
export function fmtPeriodo(mes: number, anio: number): string {
  return `${String(mes).padStart(2, '0')}/${anio}`;
}

// ---------------------------------------------------------------------------
// Helpers internos
// ---------------------------------------------------------------------------

/** Heurística: si el header termina con '.', contiene '$' o empieza con número → numérico */
function isNumericHeader(h: string): boolean {
  return /(\$|%|total|base|valor|monto|importe|saldo|pagar)/i.test(h);
}

/** Heurística: si la celda es un número formateado con coma o punto → numérico */
function isNumericCell(cell: string): boolean {
  return /^-?[\d.,]+%?$/.test(cell.trim()) && cell.trim().length > 0;
}

/** Trunca texto para que no supere maxWidth en pts. */
function truncate(text: string, font: PDFFont, size: number, maxWidth: number): string {
  if (!text) return '';
  if (textWidth(text, font, size) <= maxWidth) return text;

  const ellipsis = '...';
  const ellW = textWidth(ellipsis, font, size);
  let t = text;
  while (t.length > 0 && textWidth(t, font, size) + ellW > maxWidth) {
    t = t.slice(0, -1);
  }
  return t + ellipsis;
}

/** Divide texto en líneas que caben en maxWidth. */
function wrapText(text: string, font: PDFFont, size: number, maxWidth: number): string[] {
  if (!text) return [''];
  const words   = text.split(' ');
  const lines: string[] = [];
  let current   = '';

  for (const word of words) {
    const test = current ? `${current} ${word}` : word;
    if (textWidth(test, font, size) <= maxWidth) {
      current = test;
    } else {
      if (current) lines.push(current);
      current = textWidth(word, font, size) > maxWidth
        ? truncate(word, font, size, maxWidth)
        : word;
    }
  }
  if (current) lines.push(current);
  return lines.length ? lines : [''];
}
