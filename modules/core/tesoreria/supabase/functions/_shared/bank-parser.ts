/**
 * PILAR ERP — Shared: bank-parser.ts
 *
 * Parser de estados de cuenta bancarios para el módulo de Tesorería.
 * Soporta los formatos:
 *   - OFX (Open Financial Exchange) — usado por bancos internacionales
 *   - QFX (Quicken Financial Exchange) — mismo formato que OFX
 *   - CSV — variantes de bancos ecuatorianos (Pichincha, Pacífico, Produbanco, etc.)
 *
 * Diseño:
 *   - NO usa DOMParser (no disponible en Deno Edge Runtime)
 *   - Todas las funciones son puras (sin efectos secundarios)
 *   - Los errores de parseo se acumulan en `errores` en lugar de lanzar excepciones
 *   - Los montos siempre retornan como números positivos (monto > 0 invariante)
 *
 * Uso:
 *   import { parseBankStatement } from '../_shared/bank-parser.ts'
 *   const result = parseBankStatement(fileContent, 'estado_cuenta.csv')
 */

// =============================================================================
// TIPOS PÚBLICOS
// =============================================================================

/** Representa un movimiento individual extraído del estado de cuenta. */
export interface BankTransaction {
  /** Fecha del movimiento en formato ISO: "2026-02-14" */
  fecha: string;
  /** Descripción del movimiento (memo, concepto, detalle) */
  descripcion: string;
  /** Número de referencia, cheque o comprobante */
  referencia: string;
  /** DEBITO = salida de dinero; CREDITO = entrada de dinero */
  tipo: 'DEBITO' | 'CREDITO';
  /** Monto del movimiento. Siempre positivo (> 0). */
  monto: number;
  /** Saldo acumulado tras el movimiento, si el banco lo incluye en el archivo. */
  saldo?: number;
  /** Código ISO de la moneda. Default 'USD'. */
  moneda?: string;
}

/** Resultado completo del parseo de un estado de cuenta. */
export interface BankStatementParseResult {
  /** Formato detectado del archivo. */
  formato: 'CSV' | 'OFX' | 'QFX' | 'DESCONOCIDO';
  /** Nombre del banco si se puede detectar desde el contenido. */
  banco_detectado?: string;
  /** Número de cuenta detectado en el archivo (si está presente). */
  cuenta_numero?: string;
  /** Inicio del período cubierto por el extracto (ISO date). */
  fecha_desde?: string;
  /** Fin del período cubierto por el extracto (ISO date). */
  fecha_hasta?: string;
  /** Moneda del estado de cuenta (ISO 4217). Default 'USD'. */
  moneda?: string;
  /** Lista de transacciones parseadas exitosamente. */
  transacciones: BankTransaction[];
  /** Líneas o registros que no se pudieron parsear (para log de errores). */
  errores: string[];
}

// =============================================================================
// CONSTANTES INTERNAS
// =============================================================================

/** Mapeo de patrones en el contenido/header del CSV al nombre del banco. */
const BANCO_PATTERNS: Array<[RegExp, string]> = [
  [/BANCO\s+PICHINCHA|PICHINCHA/i,    'Banco Pichincha'],
  [/BANCO\s+PAC[IÍ]FICO|PAC[IÍ]FICO/i, 'Banco del Pacífico'],
  [/PRODUBANCO|PRODU/i,               'Produbanco'],
  [/BANCO\s+GUAYAQUIL/i,              'Banco de Guayaquil'],
  [/BANCO\s+DEL\s+AUSTRO|AUSTRO/i,   'Banco del Austro'],
  [/BOLIVARIANO/i,                    'Banco Bolivariano'],
  [/BANCO\s+INTERNACIONAL|B\.\s*INTERNACIONAL/i, 'Banco Internacional'],
  [/BANCO\s+RUMIÑAHUI|RUMI[NÑ]AHUI/i, 'Banco Rumiñahui'],
  [/COOPERATIVA|COOPROGRESO|JEP|CACPECO/i, undefined as unknown as string],
];

/**
 * Cabeceras CSV que se mapean a columna "fecha".
 * Se comparan en minúsculas con trim().
 */
const CSV_FECHA_HEADERS = [
  'fecha', 'date', 'f_proceso', 'fecha_proceso',
  'fecha_movimiento', 'fec', 'fecha_valor', 'dt',
];

/** Cabeceras CSV para la columna "descripcion". */
const CSV_DESC_HEADERS = [
  'descripcion', 'descripción', 'concepto', 'detalle',
  'memo', 'descripcion_movimiento', 'glosa', 'referencia_descripcion',
];

/** Cabeceras CSV para la columna "referencia". */
const CSV_REF_HEADERS = [
  'referencia', 'ref', 'comprobante', 'numero', 'número',
  'n_comprobante', 'num_referencia', 'nro', 'fitid',
];

/** Cabeceras CSV para la columna "debito" (egreso/cargo). */
const CSV_DEBITO_HEADERS = [
  'debito', 'débito', 'egreso', 'cargo', 'salida',
  'debitos', 'débitos', 'egresos', 'cargos', 'salidas',
];

/** Cabeceras CSV para la columna "credito" (ingreso/abono). */
const CSV_CREDITO_HEADERS = [
  'credito', 'crédito', 'ingreso', 'abono', 'entrada',
  'creditos', 'créditos', 'ingresos', 'abonos', 'entradas',
];

/** Cabeceras CSV para la columna "saldo". */
const CSV_SALDO_HEADERS = [
  'saldo', 'balance', 'saldo_disponible', 'saldo_actual',
  'saldo_contable', 'saldo_final',
];

/** Cabeceras CSV para columna "monto" único (positivo=crédito, negativo=débito). */
const CSV_MONTO_HEADERS = [
  'monto', 'importe', 'valor', 'amount', 'valor_movimiento',
];

/** Palabras que indican que una fila CSV es de totales/resumen (ignorar). */
const CSV_IGNORAR_PATRONES = [
  /^total/i, /^saldo\s+final/i, /^saldo\s+inicial/i,
  /^resumen/i, /^\*+/, /^-+/, /^=+/,
];

// =============================================================================
// FUNCIÓN PRINCIPAL
// =============================================================================

/**
 * Parsea el contenido de un estado de cuenta bancario.
 *
 * @param content  - Contenido completo del archivo como string UTF-8 (o Latin-1 decodificado)
 * @param filename - Nombre del archivo (con extensión) para ayudar a detectar el formato
 * @returns        - Resultado del parseo con transacciones y metadatos
 */
export function parseBankStatement(
  content: string,
  filename: string,
): BankStatementParseResult {
  const formato = detectarFormato(content, filename);

  if (formato === 'OFX' || formato === 'QFX') {
    return parsearOFX(content, formato);
  }

  // CSV / TXT / DESCONOCIDO: intentar parseo CSV
  return parsearCSV(content, formato === 'DESCONOCIDO' ? 'CSV' : formato);
}

// =============================================================================
// DETECCIÓN DE FORMATO
// =============================================================================

/**
 * Detecta el formato del archivo a partir de su contenido y nombre.
 * Orden de prioridad: contenido > extensión del archivo.
 */
function detectarFormato(
  content: string,
  filename: string,
): 'CSV' | 'OFX' | 'QFX' | 'DESCONOCIDO' {
  // Detección por contenido (más confiable que la extensión)
  const head = content.substring(0, 2000);
  if (head.includes('OFXHEADER') || head.includes('<OFX>') || head.includes('<ofx>')) {
    return 'OFX';
  }

  // Detección por extensión
  const ext = filename.toLowerCase().split('.').pop() ?? '';
  if (ext === 'ofx') return 'OFX';
  if (ext === 'qfx') return 'QFX';
  if (ext === 'csv' || ext === 'txt') return 'CSV';

  // Si hay comas o puntos y comas, asumir CSV
  if (content.includes(',') || content.includes(';') || content.includes('\t')) {
    return 'CSV';
  }

  return 'DESCONOCIDO';
}

// =============================================================================
// PARSER OFX / QFX
// =============================================================================

/**
 * Extrae el valor de un tag OFX del estilo <TAG>valor</TAG> o <TAG>valor (sin cierre).
 * El formato OFX legacy (SGML) no siempre usa tags de cierre.
 *
 * @param content - Contenido OFX completo
 * @param tag     - Nombre del tag (sin <>) a buscar, ej. "TRNAMT"
 * @returns       - Valor del tag como string, o null si no se encuentra
 */
export function extractOFXField(content: string, tag: string): string | null {
  // Intentar con tag de apertura y cierre: <TAG>valor</TAG>
  const tagUpper = tag.toUpperCase();
  const openTag = `<${tagUpper}>`;
  const closeTag = `</${tagUpper}>`;

  const startIdx = content.toUpperCase().indexOf(openTag);
  if (startIdx === -1) return null;

  const valueStart = startIdx + openTag.length;
  const closeIdx = content.toUpperCase().indexOf(closeTag, valueStart);

  if (closeIdx !== -1) {
    // Tiene tag de cierre
    return content.substring(valueStart, closeIdx).trim();
  }

  // OFX SGML legacy: sin tag de cierre — el valor termina en el siguiente tag o newline
  const nextTagIdx = content.indexOf('<', valueStart);
  const nextNewlineIdx = content.indexOf('\n', valueStart);

  let endIdx: number;
  if (nextTagIdx === -1 && nextNewlineIdx === -1) {
    endIdx = content.length;
  } else if (nextTagIdx === -1) {
    endIdx = nextNewlineIdx;
  } else if (nextNewlineIdx === -1) {
    endIdx = nextTagIdx;
  } else {
    endIdx = Math.min(nextTagIdx, nextNewlineIdx);
  }

  return content.substring(valueStart, endIdx).trim() || null;
}

/**
 * Convierte una fecha OFX (YYYYMMDDHHMMSS o YYYYMMDD) a formato ISO (YYYY-MM-DD).
 * Retorna null si el formato es inválido.
 */
function ofxFechaAIso(dtposted: string): string | null {
  // Remover zona horaria si existe (ej: [−5:EST])
  const limpio = dtposted.replace(/\[.*\]/, '').trim();

  // Debe tener al menos 8 caracteres (YYYYMMDD)
  if (limpio.length < 8) return null;

  const anio = limpio.substring(0, 4);
  const mes  = limpio.substring(4, 6);
  const dia  = limpio.substring(6, 8);

  // Validar rangos básicos
  const mesN = parseInt(mes, 10);
  const diaN = parseInt(dia, 10);
  if (mesN < 1 || mesN > 12 || diaN < 1 || diaN > 31) return null;

  return `${anio}-${mes}-${dia}`;
}

/**
 * Parsea un bloque OFX/QFX completo y extrae todas las transacciones.
 */
function parsearOFX(
  content: string,
  formato: 'OFX' | 'QFX',
): BankStatementParseResult {
  const errores: string[] = [];
  const transacciones: BankTransaction[] = [];

  // Extraer metadatos del estado de cuenta
  const cuentaNumero = extractOFXField(content, 'ACCTID') ?? undefined;
  const moneda       = extractOFXField(content, 'CURDEF') ?? 'USD';

  // Fechas del período
  const dtStartRaw = extractOFXField(content, 'DTSTART');
  const dtEndRaw   = extractOFXField(content, 'DTEND');
  const fechaDesde = dtStartRaw ? (ofxFechaAIso(dtStartRaw) ?? undefined) : undefined;
  const fechaHasta = dtEndRaw   ? (ofxFechaAIso(dtEndRaw)   ?? undefined) : undefined;

  // Extraer todos los bloques <STMTTRN>...</STMTTRN>
  // Algunos archivos OFX legacy no tienen tag de cierre, así que usamos
  // el inicio del siguiente <STMTTRN> como delimitador
  const contentUpper = content.toUpperCase();
  const openTrn  = '<STMTTRN>';
  const closeTrn = '</STMTTRN>';

  let pos = 0;
  let bloqueIdx = 0;

  while (true) {
    const inicio = contentUpper.indexOf(openTrn, pos);
    if (inicio === -1) break;

    bloqueIdx++;
    const despuesDeAbrir = inicio + openTrn.length;

    // Buscar cierre del bloque
    let fin = contentUpper.indexOf(closeTrn, despuesDeAbrir);
    if (fin === -1) {
      // Sin tag de cierre: el bloque termina en el siguiente <STMTTRN> o <BANKTRANLIST> de cierre
      const sigBloque = contentUpper.indexOf(openTrn, despuesDeAbrir);
      const cierreList = contentUpper.indexOf('</BANKTRANLIST>', despuesDeAbrir);

      if (sigBloque !== -1 && (cierreList === -1 || sigBloque < cierreList)) {
        fin = sigBloque;
      } else if (cierreList !== -1) {
        fin = cierreList;
      } else {
        fin = content.length;
      }
    }

    const bloque = content.substring(inicio, fin + (fin < content.length ? closeTrn.length : 0));

    // Parsear campos del bloque
    const trnType  = extractOFXField(bloque, 'TRNTYPE');
    const dtPosted = extractOFXField(bloque, 'DTPOSTED');
    const trnAmt   = extractOFXField(bloque, 'TRNAMT');
    const fitId    = extractOFXField(bloque, 'FITID');
    const memo     = extractOFXField(bloque, 'MEMO') ?? extractOFXField(bloque, 'NAME') ?? '';
    const checkNum = extractOFXField(bloque, 'CHECKNUM') ?? fitId ?? '';

    // Validar campos obligatorios
    if (!dtPosted || !trnAmt) {
      errores.push(`Bloque STMTTRN #${bloqueIdx}: falta DTPOSTED o TRNAMT`);
      pos = despuesDeAbrir;
      continue;
    }

    const fecha = ofxFechaAIso(dtPosted);
    if (!fecha) {
      errores.push(`Bloque STMTTRN #${bloqueIdx}: fecha inválida "${dtPosted}"`);
      pos = despuesDeAbrir;
      continue;
    }

    const montoRaw = parseFloat(trnAmt.replace(',', '.'));
    if (isNaN(montoRaw)) {
      errores.push(`Bloque STMTTRN #${bloqueIdx}: monto inválido "${trnAmt}"`);
      pos = despuesDeAbrir;
      continue;
    }

    // Determinar tipo: combinación de TRNTYPE + signo del monto
    let tipo: 'DEBITO' | 'CREDITO';
    const typeUpper = (trnType ?? '').toUpperCase();

    if (typeUpper === 'CREDIT' || typeUpper === 'DEP' || typeUpper === 'DIRECTDEP') {
      // Si el monto es negativo con CREDIT → es en realidad un débito
      tipo = montoRaw >= 0 ? 'CREDITO' : 'DEBITO';
    } else if (typeUpper === 'DEBIT' || typeUpper === 'CHECK' || typeUpper === 'PAYMENT' || typeUpper === 'ATM') {
      tipo = montoRaw <= 0 ? 'DEBITO' : 'CREDITO';
    } else {
      // Tipo desconocido: inferir por signo
      tipo = montoRaw >= 0 ? 'CREDITO' : 'DEBITO';
    }

    transacciones.push({
      fecha,
      descripcion: memo || `Movimiento ${fitId ?? bloqueIdx}`,
      referencia:  checkNum ?? fitId ?? '',
      tipo,
      monto:       Math.abs(montoRaw),
      moneda:      moneda ?? 'USD',
    });

    pos = despuesDeAbrir;
  }

  return {
    formato,
    cuenta_numero: cuentaNumero,
    fecha_desde:   fechaDesde,
    fecha_hasta:   fechaHasta,
    moneda:        moneda ?? 'USD',
    transacciones,
    errores,
  };
}

// =============================================================================
// PARSER CSV
// =============================================================================

/**
 * Detecta el separador más probable de un archivo CSV/TXT.
 * Evalúa las primeras 5 líneas y elige el separador más consistente.
 */
function detectarSeparador(lineas: string[]): string {
  const candidatos = [',', ';', '\t', '|'];
  const muestras = lineas.slice(0, 5).filter(l => l.trim().length > 0);

  if (muestras.length === 0) return ',';

  // Contar ocurrencias de cada separador en cada línea de muestra
  const conteos = candidatos.map(sep => {
    const counts = muestras.map(l => l.split(sep).length - 1);
    const promedio = counts.reduce((a, b) => a + b, 0) / counts.length;
    const consistencia = counts.every(c => c === counts[0]) ? 1 : 0;
    return { sep, promedio, consistencia };
  });

  // Preferir el separador con mayor promedio Y consistente
  const mejor = conteos
    .filter(c => c.promedio >= 1)
    .sort((a, b) => {
      if (b.consistencia !== a.consistencia) return b.consistencia - a.consistencia;
      return b.promedio - a.promedio;
    })[0];

  return mejor?.sep ?? ',';
}

/**
 * Divide una línea CSV respetando campos entre comillas.
 * Maneja: "campo con, coma", 'campo con; punto y coma', campo sin comillas.
 */
function dividirLineaCSV(linea: string, sep: string): string[] {
  const campos: string[] = [];
  let actual = '';
  let enComillas = false;
  let charComilla = '';

  for (let i = 0; i < linea.length; i++) {
    const c = linea[i];

    if (!enComillas && (c === '"' || c === "'")) {
      enComillas = true;
      charComilla = c;
      continue;
    }

    if (enComillas && c === charComilla) {
      // Verificar si es comilla de escape doble ("" dentro de campo entre comillas)
      if (i + 1 < linea.length && linea[i + 1] === charComilla) {
        actual += c;
        i++; // saltar la comilla extra
        continue;
      }
      enComillas = false;
      continue;
    }

    if (!enComillas && linea.substring(i, i + sep.length) === sep) {
      campos.push(actual.trim());
      actual = '';
      i += sep.length - 1;
      continue;
    }

    actual += c;
  }

  campos.push(actual.trim());
  return campos;
}

/**
 * Busca el índice de columna en el header CSV dado un conjunto de nombres posibles.
 * Comparación case-insensitive con trim().
 *
 * @param headerCols - Array de nombres de columnas del header normalizado
 * @param nombres    - Lista de nombres posibles para la columna buscada
 * @returns          - Índice de la columna, o -1 si no se encuentra
 */
function encontrarColumna(headerCols: string[], nombres: string[]): number {
  for (let i = 0; i < headerCols.length; i++) {
    const col = headerCols[i].toLowerCase().replace(/[^a-z0-9_áéíóúñ]/gi, '_').trim();
    for (const nombre of nombres) {
      if (col === nombre || col.includes(nombre) || nombre.includes(col)) {
        return i;
      }
    }
  }
  return -1;
}

/**
 * Parsea un monto en string al formato numérico.
 * Maneja formatos como: "1.234,56", "1,234.56", "$1234.56", "1234", "(150.00)"
 *
 * @returns número positivo, o null si no es parseable
 */
function parsearMonto(raw: string): number | null {
  if (!raw) return null;

  let limpio = raw
    .replace(/\$/g, '')      // quitar símbolo dólar
    .replace(/\s/g, '')      // quitar espacios
    .trim();

  if (!limpio || limpio === '-' || limpio === '') return null;

  // Monto entre paréntesis = negativo: (150.00) → -150.00
  let negativo = false;
  if (limpio.startsWith('(') && limpio.endsWith(')')) {
    negativo = true;
    limpio = limpio.slice(1, -1);
  }

  // Detectar formato de miles: si hay PUNTO Y COMA, el punto es miles y la coma es decimal
  // Ejemplos: "1.234,56" (Ecuador) o "1,234.56" (USA)
  const tienesPunto = limpio.includes('.');
  const tieneComa   = limpio.includes(',');

  if (tienesPunto && tieneComa) {
    const idxPunto = limpio.lastIndexOf('.');
    const idxComa  = limpio.lastIndexOf(',');

    if (idxComa > idxPunto) {
      // Formato ecuatoriano: 1.234,56 → punto=miles, coma=decimal
      limpio = limpio.replace(/\./g, '').replace(',', '.');
    } else {
      // Formato USA: 1,234.56 → coma=miles, punto=decimal
      limpio = limpio.replace(/,/g, '');
    }
  } else if (tieneComa) {
    // Solo comas: puede ser decimal (1234,56) o miles (1,234)
    // Si hay exactamente 3 dígitos después de la última coma, es miles
    const partes = limpio.split(',');
    const ultima = partes[partes.length - 1];
    if (partes.length === 2 && ultima.length === 3) {
      // Ambiguo: preferir tratar como decimal en contexto bancario ecuatoriano
      limpio = limpio.replace(',', '.');
    } else {
      limpio = limpio.replace(/,/g, '').replace(',', '.');
    }
  }
  // Solo puntos: ya está en formato correcto (ej: "1234.56")

  const num = parseFloat(limpio);
  if (isNaN(num)) return null;

  return negativo ? -num : num;
}

/**
 * Detecta si una fila CSV es una fila de totales/resumen que debe ignorarse.
 */
function esFilaResumen(campos: string[]): boolean {
  // Fila vacía o con un solo campo significativo
  const noVacios = campos.filter(c => c.trim().length > 0);
  if (noVacios.length <= 1) return true;

  // Primera celda contiene palabras clave de totales
  const primera = campos[0]?.trim() ?? '';
  return CSV_IGNORAR_PATRONES.some(p => p.test(primera));
}

/**
 * Intenta detectar el nombre del banco a partir de las primeras líneas del CSV
 * (que a menudo contienen información del banco en formato libre).
 */
function detectarBancoCSV(contenidoCabecera: string): string | undefined {
  for (const [patron, nombre] of BANCO_PATTERNS) {
    if (nombre && patron.test(contenidoCabecera)) {
      return nombre;
    }
  }
  return undefined;
}

/**
 * Parsea un archivo en formato CSV/TXT.
 * Detecta automáticamente el separador, mapea columnas por nombre y
 * genera BankTransaction[] desde las filas de datos.
 */
function parsearCSV(
  content: string,
  formato: 'CSV' | 'OFX' | 'QFX' | 'DESCONOCIDO',
): BankStatementParseResult {
  const errores: string[] = [];
  const transacciones: BankTransaction[] = [];

  // Normalizar saltos de línea (Windows CRLF → LF)
  const lineas = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');

  if (lineas.length === 0) {
    return {
      formato: formato === 'DESCONOCIDO' ? 'CSV' : formato as 'CSV',
      transacciones: [],
      errores: ['Archivo vacío'],
    };
  }

  // Intentar detectar banco en las primeras líneas (cabecera libre antes del header)
  const cabecera = lineas.slice(0, 10).join('\n');
  const bancoDetectado = detectarBancoCSV(cabecera);

  // Detectar separador en base a las primeras líneas no vacías
  const lineasNoVacias = lineas.filter(l => l.trim().length > 0);
  const separador = detectarSeparador(lineasNoVacias);

  // Encontrar la fila de header (primera fila que contenga palabras clave de columnas)
  let headerIdx = -1;
  let headerCols: string[] = [];

  for (let i = 0; i < Math.min(lineas.length, 20); i++) {
    const linea = lineas[i];
    if (!linea.trim()) continue;

    const cols = dividirLineaCSV(linea, separador).map(c =>
      c.toLowerCase().replace(/[^a-z0-9_áéíóúñ]/gi, '_').trim()
    );

    // Verificar si alguna columna coincide con nuestros headers conocidos
    const todasLasColumnas = [
      ...CSV_FECHA_HEADERS, ...CSV_DESC_HEADERS, ...CSV_REF_HEADERS,
      ...CSV_DEBITO_HEADERS, ...CSV_CREDITO_HEADERS, ...CSV_SALDO_HEADERS,
      ...CSV_MONTO_HEADERS,
    ];

    const coincidencias = cols.filter(col =>
      todasLasColumnas.some(h => col === h || col.includes(h) || h.includes(col))
    );

    if (coincidencias.length >= 2) {
      headerIdx = i;
      headerCols = dividirLineaCSV(linea, separador).map(c => c.trim());
      break;
    }
  }

  if (headerIdx === -1) {
    // No se encontró header: usar primera línea no vacía como header
    const primerLinea = lineasNoVacias[0];
    headerIdx = lineas.indexOf(primerLinea);
    headerCols = dividirLineaCSV(primerLinea, separador).map(c => c.trim());
    errores.push('No se detectó header estándar. Usando primera línea como header.');
  }

  // Normalizar nombres de columnas para búsqueda
  const headerColsNorm = headerCols.map(c =>
    c.toLowerCase().replace(/[^a-z0-9_áéíóúñ]/gi, '_').trim()
  );

  // Mapear índices de columnas
  const idxFecha   = encontrarColumna(headerColsNorm, CSV_FECHA_HEADERS);
  const idxDesc    = encontrarColumna(headerColsNorm, CSV_DESC_HEADERS);
  const idxRef     = encontrarColumna(headerColsNorm, CSV_REF_HEADERS);
  const idxDebito  = encontrarColumna(headerColsNorm, CSV_DEBITO_HEADERS);
  const idxCredito = encontrarColumna(headerColsNorm, CSV_CREDITO_HEADERS);
  const idxSaldo   = encontrarColumna(headerColsNorm, CSV_SALDO_HEADERS);
  const idxMonto   = encontrarColumna(headerColsNorm, CSV_MONTO_HEADERS);

  // Verificar que tenemos las columnas mínimas
  if (idxFecha === -1) {
    errores.push(`No se encontró columna de fecha. Columnas detectadas: ${headerCols.join(', ')}`);
  }
  const tieneMontoUnico  = idxMonto >= 0;
  const tieneDebitoCredi = idxDebito >= 0 || idxCredito >= 0;

  if (!tieneMontoUnico && !tieneDebitoCredi) {
    errores.push(
      `No se encontró columna de monto. Se necesita una de: ` +
      `[${CSV_MONTO_HEADERS.join(',')}] o [${CSV_DEBITO_HEADERS.join(',')}]/[${CSV_CREDITO_HEADERS.join(',')}]`
    );
  }

  // Extraer fechas del período de las filas de datos
  let fechaMin: string | undefined;
  let fechaMax: string | undefined;

  // Parsear filas de datos
  for (let i = headerIdx + 1; i < lineas.length; i++) {
    const linea = lineas[i];
    if (!linea.trim()) continue;

    const campos = dividirLineaCSV(linea, separador);
    if (campos.length < 2) continue;

    // Ignorar filas de totales/resumen
    if (esFilaResumen(campos)) continue;

    const numLinea = i + 1;

    // Fecha
    let fecha = '';
    if (idxFecha >= 0 && idxFecha < campos.length) {
      fecha = normalizarFechaCSV(campos[idxFecha].trim());
    }

    if (!fecha) {
      errores.push(`Línea ${numLinea}: fecha inválida o no encontrada "${campos[idxFecha] ?? ''}"`);
      continue;
    }

    // Descripción
    const descripcion = idxDesc >= 0 && idxDesc < campos.length
      ? campos[idxDesc].trim()
      : `Movimiento línea ${numLinea}`;

    // Referencia
    const referencia = idxRef >= 0 && idxRef < campos.length
      ? campos[idxRef].trim()
      : '';

    // Saldo (opcional)
    let saldo: number | undefined;
    if (idxSaldo >= 0 && idxSaldo < campos.length) {
      const s = parsearMonto(campos[idxSaldo]);
      if (s !== null) saldo = Math.abs(s);
    }

    // Monto y tipo
    let monto: number | undefined;
    let tipo: 'DEBITO' | 'CREDITO' | undefined;

    if (tieneMontoUnico && idxMonto >= 0 && idxMonto < campos.length) {
      // Columna única de monto: positivo = crédito, negativo = débito
      const m = parsearMonto(campos[idxMonto]);
      if (m !== null && m !== 0) {
        tipo  = m > 0 ? 'CREDITO' : 'DEBITO';
        monto = Math.abs(m);
      }
    } else {
      // Columnas separadas de débito y crédito
      let montoDebito: number | null  = null;
      let montoCredito: number | null = null;

      if (idxDebito >= 0 && idxDebito < campos.length) {
        const d = parsearMonto(campos[idxDebito]);
        if (d !== null && d !== 0) montoDebito = Math.abs(d);
      }
      if (idxCredito >= 0 && idxCredito < campos.length) {
        const c = parsearMonto(campos[idxCredito]);
        if (c !== null && c !== 0) montoCredito = Math.abs(c);
      }

      if (montoDebito && montoDebito > 0) {
        tipo  = 'DEBITO';
        monto = montoDebito;
      } else if (montoCredito && montoCredito > 0) {
        tipo  = 'CREDITO';
        monto = montoCredito;
      }
      // Si ambos tienen valor (no debería pasar), priorizar débito
      else if (montoDebito && montoCredito) {
        tipo  = 'DEBITO';
        monto = montoDebito;
      }
    }

    if (!monto || !tipo || monto <= 0) {
      // Fila sin monto válido: probablemente fila de cabecera secundaria o vacía
      errores.push(`Línea ${numLinea}: monto inválido o cero (campos: ${campos.join(' | ')})`);
      continue;
    }

    // Actualizar rango de fechas del período
    if (!fechaMin || fecha < fechaMin) fechaMin = fecha;
    if (!fechaMax || fecha > fechaMax) fechaMax = fecha;

    transacciones.push({
      fecha,
      descripcion: descripcion || `Movimiento línea ${numLinea}`,
      referencia,
      tipo,
      monto,
      saldo,
      moneda: 'USD',
    });
  }

  return {
    formato: 'CSV',
    banco_detectado: bancoDetectado,
    fecha_desde: fechaMin,
    fecha_hasta: fechaMax,
    moneda: 'USD',
    transacciones,
    errores,
  };
}

// =============================================================================
// HELPERS FECHA CSV
// =============================================================================

/**
 * Normaliza una fecha en varios formatos al formato ISO YYYY-MM-DD.
 * Soporta los formatos más comunes en bancos ecuatorianos:
 *   - DD/MM/YYYY (formato Ecuador más común)
 *   - DD-MM-YYYY
 *   - YYYY-MM-DD (ISO, ya correcto)
 *   - YYYY/MM/DD
 *   - DD/MM/YY  (año de 2 dígitos)
 *   - YYYYMMDD  (compacto OFX-style en CSVs de algunos bancos)
 *
 * @returns Fecha en formato ISO "YYYY-MM-DD" o cadena vacía si no parseable.
 */
function normalizarFechaCSV(raw: string): string {
  if (!raw) return '';
  const s = raw.trim();

  // Ya está en formato ISO: YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;

  // Formato compacto YYYYMMDD
  if (/^\d{8}$/.test(s)) {
    const anio = s.substring(0, 4);
    const mes  = s.substring(4, 6);
    const dia  = s.substring(6, 8);
    if (validarPartesFecha(anio, mes, dia)) return `${anio}-${mes}-${dia}`;
  }

  // DD/MM/YYYY o DD-MM-YYYY o DD.MM.YYYY
  const mDmy = s.match(/^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})$/);
  if (mDmy) {
    const dia  = mDmy[1].padStart(2, '0');
    const mes  = mDmy[2].padStart(2, '0');
    const anio = mDmy[3];
    if (validarPartesFecha(anio, mes, dia)) return `${anio}-${mes}-${dia}`;
  }

  // YYYY/MM/DD o YYYY.MM.DD
  const mYmd = s.match(/^(\d{4})[\/\.](\d{2})[\/\.](\d{2})$/);
  if (mYmd) {
    const anio = mYmd[1];
    const mes  = mYmd[2];
    const dia  = mYmd[3];
    if (validarPartesFecha(anio, mes, dia)) return `${anio}-${mes}-${dia}`;
  }

  // DD/MM/YY (año de 2 dígitos → asumir 20YY)
  const mDmy2 = s.match(/^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2})$/);
  if (mDmy2) {
    const dia  = mDmy2[1].padStart(2, '0');
    const mes  = mDmy2[2].padStart(2, '0');
    const anio = `20${mDmy2[3]}`;
    if (validarPartesFecha(anio, mes, dia)) return `${anio}-${mes}-${dia}`;
  }

  // Fecha con hora: "DD/MM/YYYY HH:MM:SS" → extraer solo la fecha
  const mConHora = s.match(/^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})\s+\d{1,2}:\d{2}/);
  if (mConHora) {
    const dia  = mConHora[1].padStart(2, '0');
    const mes  = mConHora[2].padStart(2, '0');
    const anio = mConHora[3];
    if (validarPartesFecha(anio, mes, dia)) return `${anio}-${mes}-${dia}`;
  }

  return '';
}

/**
 * Valida que las partes de una fecha sean numéricamente válidas.
 */
function validarPartesFecha(anio: string, mes: string, dia: string): boolean {
  const a = parseInt(anio, 10);
  const m = parseInt(mes, 10);
  const d = parseInt(dia, 10);
  return a >= 2000 && a <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
}
