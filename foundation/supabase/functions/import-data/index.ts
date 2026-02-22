/**
 * PILAR ERP — Edge Function: import-data
 *
 * Recibe un archivo CSV o XLSX, lo parsea, valida cada fila contra el template
 * definido en `import_templates`, y llama la RPC destino para cada fila válida.
 * Equivalente al importador de Odoo pero data-driven y sin código ad-hoc por módulo.
 *
 * ---------------------------------------------------------------------------
 * CONTRATO HTTP
 * ---------------------------------------------------------------------------
 * POST /functions/v1/import-data
 * Authorization: Bearer <user_jwt>
 * Content-Type: multipart/form-data
 *
 * Campos del form:
 *   file        : File   — archivo CSV o XLSX (máx. 10 MB)
 *   template_id : string — UUID del template en import_templates
 *   dry_run     : string — "true" | "false" (default "false")
 *                          Si true: valida todo pero NO llama la RPC destino
 *
 * Respuesta exitosa (200):
 * {
 *   "ok":             true,
 *   "job_id":         "uuid",
 *   "total":          100,
 *   "exitosas":       95,
 *   "errores":        5,
 *   "detalle_errores": [{ "fila": 3, "campo": "ruc_cedula", "error": "RUC inválido" }]
 * }
 *
 * Códigos de error posibles:
 *   405  METHOD_NOT_ALLOWED
 *   401  UNAUTHORIZED
 *   400  NO_EMPRESA_CONTEXT
 *   400  FORM_DATA_INVALIDO
 *   400  ARCHIVO_REQUERIDO
 *   400  TEMPLATE_ID_REQUERIDO
 *   400  ARCHIVO_DEMASIADO_GRANDE
 *   400  EXCEDE_MAXIMO_FILAS
 *   400  ARCHIVO_VACIO
 *   400  EXTENSION_NO_SOPORTADA
 *   400  HEADERS_FALTANTES
 *   404  TEMPLATE_NO_ENCONTRADO
 *   500  JOB_CREATE_ERROR
 *   500  INTERNAL_ERROR
 *
 * ---------------------------------------------------------------------------
 * TABLA DE ORIGEN (foundation/supabase/migrations/022_data_importer.sql)
 * ---------------------------------------------------------------------------
 * import_templates  — define campos, tipos, validaciones y rpc_destino
 * import_jobs       — historial de importaciones por empresa/usuario
 *
 * RPC finalizar_import_job(job_id, filas_ok, filas_error, errores_json, estado)
 * RPC destino del template: (p_empresa_id UUID, p_fila JSONB) → JSONB
 *   Retorno esperado de la RPC: { ok: true, id: uuid } | { ok: false, error: "msg" }
 *
 * ---------------------------------------------------------------------------
 * TIPOS DE CAMPO SOPORTADOS
 * ---------------------------------------------------------------------------
 * text      — trim, max_longitud, patron (regex), valores_permitidos
 * integer   — parseInt, falla si NaN
 * decimal   — parseFloat, falla si NaN
 * boolean   — S/SI/Y/YES/TRUE/1 → true; N/NO/FALSE/0 → false
 * date      — parsear según "formato" (default YYYY-MM-DD), falla si inválido
 * uuid_ref  — dejar como string; la RPC destino resuelve la referencia
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import * as XLSX from 'npm:xlsx@0.18.5';

// =============================================================================
// CONSTANTES
// =============================================================================

const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024; // 10 MB
const MAX_ROWS            = 5_000;             // máximo de filas de datos por importación

// =============================================================================
// TIPOS
// =============================================================================

/** Definición de un campo de importación tal como viene en import_templates.campos */
interface CampoTemplate {
  nombre:            string;
  etiqueta:          string;
  tipo:              'text' | 'integer' | 'decimal' | 'boolean' | 'date' | 'uuid_ref';
  requerido:         boolean;
  patron?:           string;
  max_longitud?:     number;
  valores_permitidos?: string[];
  valor_defecto?:    string;
  formato?:          string;  // solo tipo date, ej: "YYYY-MM-DD"
  tabla_ref?:        string;  // solo tipo uuid_ref
  campo_busqueda?:   string;  // solo tipo uuid_ref
}

/** Template completo leído desde la BD */
interface ImportTemplate {
  id:          string;
  campos:      CampoTemplate[];
  rpc_destino: string;
  nombre:      string;
}

/** Error de validación en una fila específica */
interface ErrorFila {
  fila:   number;
  campo:  string;
  error:  string;
}

/** Resultado interno del procesamiento de una fila */
interface ResultadoFila {
  exito:  boolean;
  error?: ErrorFila;
}

// =============================================================================
// HELPERS — respuestas HTTP
// =============================================================================

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(status: number, code: string, message?: string): Response {
  return jsonResponse({ ok: false, error: code, message }, status);
}

// =============================================================================
// HELPER — obtener extensión de archivo
// =============================================================================

function obtenerExtension(filename: string): string {
  const parts = filename.toLowerCase().split('.');
  return parts.length > 1 ? parts[parts.length - 1] : '';
}

// =============================================================================
// PARSING CSV
// =============================================================================

/**
 * Parsea un campo CSV individual respetando comillas dobles (RFC 4180).
 * Soporta campos entre comillas con comas internas y saltos de línea escapados.
 */
function parsearCampoCsv(valor: string): string {
  const trimmed = valor.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    // Quitar comillas externas y desdoblar "" → "
    return trimmed.slice(1, -1).replace(/""/g, '"');
  }
  return trimmed;
}

/**
 * Parsea una línea CSV en un array de campos, respetando comillas dobles.
 * Soporta coma y punto y coma como separador (auto-detectado por la primera fila).
 */
function parsearLineaCsv(linea: string, separador: string): string[] {
  const campos: string[]  = [];
  let   campo             = '';
  let   dentroDeComillas  = false;
  let   i                 = 0;

  while (i < linea.length) {
    const char = linea[i];

    if (char === '"') {
      if (dentroDeComillas && linea[i + 1] === '"') {
        // Comilla escapada ("")
        campo += '"';
        i += 2;
        continue;
      }
      dentroDeComillas = !dentroDeComillas;
      i++;
      continue;
    }

    if (!dentroDeComillas && linea[i] === separador) {
      campos.push(campo.trim());
      campo = '';
      i++;
      continue;
    }

    campo += char;
    i++;
  }

  campos.push(campo.trim());
  return campos;
}

/**
 * Detecta el separador más probable de un CSV (coma o punto y coma)
 * analizando la primera línea.
 */
function detectarSeparador(primeraLinea: string): string {
  const contarComas     = (primeraLinea.match(/,/g) ?? []).length;
  const contarPuntoComa = (primeraLinea.match(/;/g) ?? []).length;
  return contarPuntoComa > contarComas ? ';' : ',';
}

/**
 * Parsea el contenido de un archivo CSV y retorna un array de objetos
 * donde las claves son los encabezados de la primera fila.
 */
function parsearCsv(contenido: string): Record<string, string>[] {
  // Normalizar saltos de línea (Windows/Mac/Unix)
  const lineas = contenido
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .split('\n')
    .filter(l => l.trim().length > 0);

  if (lineas.length < 2) return [];

  const separador = detectarSeparador(lineas[0]);
  const headers   = lineas[0].split(separador).map(h => parsearCampoCsv(h));
  const filas: Record<string, string>[] = [];

  for (let i = 1; i < lineas.length; i++) {
    const valores = parsearLineaCsv(lineas[i], separador);
    const fila: Record<string, string> = {};
    for (let j = 0; j < headers.length; j++) {
      fila[headers[j]] = valores[j] ?? '';
    }
    filas.push(fila);
  }

  return filas;
}

// =============================================================================
// PARSING XLSX
// =============================================================================

/**
 * Parsea el contenido de un archivo XLSX/XLS y retorna un array de objetos
 * usando SheetJS. Toma la primera hoja del workbook.
 */
function parsearXlsx(buffer: ArrayBuffer): Record<string, string>[] {
  const workbook = XLSX.read(new Uint8Array(buffer), { type: 'array', cellText: true });
  const primeraHoja = workbook.SheetNames[0];
  if (!primeraHoja) return [];

  const sheet = workbook.Sheets[primeraHoja];
  // sheet_to_json retorna cada fila como objeto { header: valor }
  const filas = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, {
    defval: '',   // valor por defecto para celdas vacías
    raw:    false, // todo como string (cellText)
  });

  // Convertir todos los valores a string para homogeneizar con el parser CSV
  return filas.map(fila => {
    const filaStr: Record<string, string> = {};
    for (const [clave, valor] of Object.entries(fila)) {
      filaStr[clave] = valor == null ? '' : String(valor).trim();
    }
    return filaStr;
  });
}

// =============================================================================
// VALIDACIÓN DE CAMPOS
// =============================================================================

/**
 * Parsea y valida un valor de celda según la definición del campo en el template.
 *
 * @returns { valor: unknown } si es válido, o { error: string } si falla.
 */
function validarCampo(
  campo: CampoTemplate,
  valorRaw: string | undefined,
): { valor: unknown; error?: never } | { valor?: never; error: string } {

  // Determinar valor efectivo: celda o valor_defecto
  let valorStr = (valorRaw ?? '').trim();
  if (valorStr === '' && campo.valor_defecto !== undefined) {
    valorStr = campo.valor_defecto;
  }

  // Verificar campo requerido
  if (campo.requerido && valorStr === '') {
    return { error: 'Campo requerido' };
  }

  // Si está vacío y no es requerido → null (no incluir en JSONB)
  if (valorStr === '') {
    return { valor: null };
  }

  // ── tipo: text ────────────────────────────────────────────────────────────
  if (campo.tipo === 'text') {
    if (campo.max_longitud && valorStr.length > campo.max_longitud) {
      return { error: `Excede longitud máxima de ${campo.max_longitud} caracteres` };
    }
    if (campo.patron) {
      const re = new RegExp(campo.patron);
      if (!re.test(valorStr)) {
        return { error: `No cumple el formato esperado (${campo.patron})` };
      }
    }
    if (campo.valores_permitidos && campo.valores_permitidos.length > 0) {
      const permitidos = campo.valores_permitidos.map(v => v.toLowerCase());
      if (!permitidos.includes(valorStr.toLowerCase())) {
        return { error: `Valor "${valorStr}" no permitido. Debe ser uno de: ${campo.valores_permitidos.join(', ')}` };
      }
      // Normalizar al valor canónico (igual al permitido)
      const idx = permitidos.indexOf(valorStr.toLowerCase());
      return { valor: campo.valores_permitidos[idx] };
    }
    return { valor: valorStr };
  }

  // ── tipo: integer ─────────────────────────────────────────────────────────
  if (campo.tipo === 'integer') {
    const num = parseInt(valorStr, 10);
    if (isNaN(num)) {
      return { error: `"${valorStr}" no es un número entero válido` };
    }
    return { valor: num };
  }

  // ── tipo: decimal ─────────────────────────────────────────────────────────
  if (campo.tipo === 'decimal') {
    // Normalizar separador decimal: coma → punto (Ecuador usa coma en Excel)
    const normalizado = valorStr.replace(',', '.');
    const num = parseFloat(normalizado);
    if (isNaN(num)) {
      return { error: `"${valorStr}" no es un número decimal válido` };
    }
    return { valor: num };
  }

  // ── tipo: boolean ─────────────────────────────────────────────────────────
  if (campo.tipo === 'boolean') {
    const upper = valorStr.toUpperCase();
    if (['S', 'SI', 'Y', 'YES', 'TRUE', '1', 'VERDADERO'].includes(upper)) {
      return { valor: true };
    }
    if (['N', 'NO', 'FALSE', '0', 'FALSO'].includes(upper)) {
      return { valor: false };
    }
    return { error: `"${valorStr}" no es un booleano válido. Use S/N, SI/NO, TRUE/FALSE, 1/0` };
  }

  // ── tipo: date ────────────────────────────────────────────────────────────
  if (campo.tipo === 'date') {
    // Intentar parsear según el formato declarado (por defecto YYYY-MM-DD)
    const formato = campo.formato ?? 'YYYY-MM-DD';
    const fechaParseada = parsearFecha(valorStr, formato);
    if (!fechaParseada) {
      return { error: `"${valorStr}" no es una fecha válida con formato ${formato}` };
    }
    // Retornar siempre como ISO 8601 (YYYY-MM-DD) para la BD
    return { valor: fechaParseada };
  }

  // ── tipo: uuid_ref ────────────────────────────────────────────────────────
  if (campo.tipo === 'uuid_ref') {
    // Solo pasamos el string tal como vino; la RPC destino resuelve la referencia
    return { valor: valorStr };
  }

  // Tipo desconocido: pasar como string sin validar
  return { valor: valorStr };
}

// =============================================================================
// HELPER — parseo de fechas
// =============================================================================

/**
 * Intenta parsear un string de fecha según el formato declarado.
 * Soporta: YYYY-MM-DD, DD/MM/YYYY, DD-MM-YYYY, MM/DD/YYYY.
 * Retorna el string ISO 8601 (YYYY-MM-DD) o null si falla.
 */
function parsearFecha(valorStr: string, formato: string): string | null {
  // Intentar parseo directo si ya es ISO 8601
  if (/^\d{4}-\d{2}-\d{2}$/.test(valorStr)) {
    const d = new Date(valorStr + 'T00:00:00');
    return isNaN(d.getTime()) ? null : valorStr;
  }

  let anio: number, mes: number, dia: number;

  // DD/MM/YYYY o DD-MM-YYYY
  if (formato === 'DD/MM/YYYY' || formato === 'DD-MM-YYYY') {
    const sep  = formato === 'DD/MM/YYYY' ? '/' : '-';
    const p    = valorStr.split(sep);
    if (p.length !== 3) return null;
    [dia, mes, anio] = p.map(Number);
  }
  // MM/DD/YYYY
  else if (formato === 'MM/DD/YYYY') {
    const p = valorStr.split('/');
    if (p.length !== 3) return null;
    [mes, dia, anio] = p.map(Number);
  }
  // Formato desconocido: intentar Date.parse como fallback
  else {
    const d = new Date(valorStr);
    if (isNaN(d.getTime())) return null;
    anio = d.getFullYear();
    mes  = d.getMonth() + 1;
    dia  = d.getDate();
  }

  if (!anio || !mes || !dia) return null;
  if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;

  const isoStr = `${String(anio).padStart(4,'0')}-${String(mes).padStart(2,'0')}-${String(dia).padStart(2,'0')}`;
  const d = new Date(isoStr + 'T00:00:00');
  return isNaN(d.getTime()) ? null : isoStr;
}

// =============================================================================
// LÓGICA CENTRAL — procesar una fila
// =============================================================================

/**
 * Mapea los valores de una fila (por etiqueta del encabezado) a un objeto JSONB
 * usando los campos del template, y valida cada uno.
 *
 * @returns { filaJsonb, errores[] } — errores vacío si toda la fila es válida.
 */
function procesarFila(
  filaRaw:     Record<string, string>,
  campos:      CampoTemplate[],
  numeroFila:  number,
): { filaJsonb: Record<string, unknown>; errores: ErrorFila[] } {
  const filaJsonb: Record<string, unknown> = {};
  const errores:   ErrorFila[]             = [];

  for (const campo of campos) {
    // Buscar el valor por la etiqueta (header del CSV/XLSX)
    const valorRaw = filaRaw[campo.etiqueta];

    const resultado = validarCampo(campo, valorRaw);

    if ('error' in resultado) {
      errores.push({ fila: numeroFila, campo: campo.nombre, error: resultado.error });
    } else {
      // Solo incluir en JSONB si no es null
      if (resultado.valor !== null && resultado.valor !== undefined) {
        filaJsonb[campo.nombre] = resultado.valor;
      }
    }
  }

  return { filaJsonb, errores };
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
    // 3. Clientes Supabase
    //    - supabaseClient: JWT del usuario → respeta RLS → para auth + RPCs tenant-scoped
    //    - supabaseAdmin:  service role → bypass RLS → para INSERT en import_jobs
    //      y llamadas a RPCs SECURITY DEFINER que requieren empresa_id explícito
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

    const supabaseAdmin: SupabaseClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    // -------------------------------------------------------------------------
    // 4. Autenticación: verificar JWT y obtener usuario
    // -------------------------------------------------------------------------
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return errorResponse(401, 'UNAUTHORIZED', 'Token inválido o expirado');
    }

    // 5. Obtener empresa_id desde app_metadata del JWT (inyectado por custom_access_token_hook)
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

    const file       = formData.get('file')        as File   | null;
    const templateId = (formData.get('template_id') as string | null)?.trim();
    const dryRunRaw  = (formData.get('dry_run')      as string | null)?.trim().toLowerCase();
    const dryRun     = dryRunRaw === 'true';

    // 7. Validaciones básicas de campos del form
    if (!file) {
      return errorResponse(400, 'ARCHIVO_REQUERIDO', 'El campo "file" es obligatorio');
    }
    if (!templateId) {
      return errorResponse(400, 'TEMPLATE_ID_REQUERIDO', 'El campo "template_id" es obligatorio');
    }

    // 8. Validar tamaño máximo (10 MB)
    if (file.size > MAX_FILE_SIZE_BYTES) {
      return errorResponse(
        400,
        'ARCHIVO_DEMASIADO_GRANDE',
        `El archivo supera el máximo de ${MAX_FILE_SIZE_BYTES / 1024 / 1024} MB ` +
        `(tamaño recibido: ${(file.size / 1024 / 1024).toFixed(2)} MB)`,
      );
    }

    // -------------------------------------------------------------------------
    // 9. Obtener template de la BD
    //    Usamos el cliente del usuario (RLS: templates globales + propios de empresa)
    // -------------------------------------------------------------------------
    const { data: templateData, error: templateError } = await supabaseClient
      .from('import_templates')
      .select('id, nombre, campos, rpc_destino')
      .eq('id', templateId)
      .eq('activo', true)
      .maybeSingle();

    if (templateError) {
      console.error('[import-data] Error al obtener template:', templateError);
      return errorResponse(500, 'INTERNAL_ERROR', 'Error al obtener el template de la BD');
    }
    if (!templateData) {
      return errorResponse(
        404,
        'TEMPLATE_NO_ENCONTRADO',
        `No se encontró un template activo con id ${templateId}`,
      );
    }

    const template: ImportTemplate = {
      id:          templateData.id,
      nombre:      templateData.nombre,
      campos:      templateData.campos as CampoTemplate[],
      rpc_destino: templateData.rpc_destino,
    };

    // -------------------------------------------------------------------------
    // 10. Parsear el archivo según su extensión
    // -------------------------------------------------------------------------
    const extension = obtenerExtension(file.name);
    let filas: Record<string, string>[];

    if (extension === 'xlsx' || extension === 'xls') {
      // Excel: leer como ArrayBuffer → SheetJS
      const buffer = await file.arrayBuffer();
      try {
        filas = parsearXlsx(buffer);
      } catch (xlsxErr) {
        return errorResponse(
          400,
          'EXTENSION_NO_SOPORTADA',
          `Error al parsear el archivo Excel: ${xlsxErr instanceof Error ? xlsxErr.message : String(xlsxErr)}`,
        );
      }
    } else if (extension === 'csv' || extension === 'txt') {
      // CSV/TXT: leer como texto con soporte UTF-8 y Latin-1 (bancos ecuatorianos)
      let contenido: string;
      try {
        contenido = await file.text();
      } catch {
        // Fallback: Latin-1 / ISO-8859-1 (algunos exports bancarios/contables)
        const buffer  = await file.arrayBuffer();
        const decoder = new TextDecoder('iso-8859-1');
        contenido = decoder.decode(buffer);
      }
      if (!contenido.trim()) {
        return errorResponse(400, 'ARCHIVO_VACIO', 'El archivo está vacío');
      }
      filas = parsearCsv(contenido);
    } else {
      return errorResponse(
        400,
        'EXTENSION_NO_SOPORTADA',
        `Extensión ".${extension}" no soportada. Se aceptan: .csv, .xlsx, .xls, .txt`,
      );
    }

    // 11. Validar que haya datos
    if (filas.length === 0) {
      return errorResponse(
        400,
        'ARCHIVO_VACIO',
        'El archivo no contiene filas de datos (solo encabezados o vacío)',
      );
    }

    // 12. Validar límite de filas
    if (filas.length > MAX_ROWS) {
      return errorResponse(
        400,
        'EXCEDE_MAXIMO_FILAS',
        `El archivo contiene ${filas.length} filas, superando el máximo de ${MAX_ROWS}. ` +
        `Divida el archivo en lotes más pequeños.`,
      );
    }

    // -------------------------------------------------------------------------
    // 13. Verificar que los headers del archivo contengan las columnas requeridas
    // -------------------------------------------------------------------------
    const headersFila   = Object.keys(filas[0]);
    const camposRequeridos = template.campos.filter(c => c.requerido && c.valor_defecto === undefined);
    const headersFaltantes: string[] = [];

    for (const campo of camposRequeridos) {
      if (!headersFila.includes(campo.etiqueta)) {
        headersFaltantes.push(`"${campo.etiqueta}"`);
      }
    }

    if (headersFaltantes.length > 0) {
      return errorResponse(
        400,
        'HEADERS_FALTANTES',
        `El archivo no contiene las columnas requeridas: ${headersFaltantes.join(', ')}. ` +
        `Columnas encontradas: ${headersFila.map(h => `"${h}"`).join(', ')}`,
      );
    }

    // -------------------------------------------------------------------------
    // 14. Crear job en la BD con estado PROCESANDO
    //     Usamos supabaseAdmin para el INSERT porque import_jobs requiere
    //     empresa_id y usuario_id explícitos, y la política RLS solo permite
    //     operaciones donde empresa_id = get_empresa_id() del JWT.
    //     Sin embargo, con el JWT del usuario la política sí se cumple,
    //     así que usamos el cliente del usuario directamente.
    // -------------------------------------------------------------------------
    const { data: jobData, error: jobError } = await supabaseClient
      .from('import_jobs')
      .insert({
        empresa_id:    empresaId,
        template_id:   template.id,
        usuario_id:    user.id,
        nombre_archivo: file.name,
        estado:        'PROCESANDO',
        total_filas:   filas.length,
      })
      .select('id')
      .single();

    if (jobError || !jobData) {
      console.error('[import-data] Error al crear import_job:', jobError);
      return errorResponse(500, 'JOB_CREATE_ERROR', 'No se pudo crear el registro de importación');
    }

    const jobId: string = jobData.id;
    console.log(`[import-data] Job creado: ${jobId} | template: ${template.nombre} | filas: ${filas.length} | dry_run: ${dryRun}`);

    // -------------------------------------------------------------------------
    // 15. Procesar cada fila: validar → (si válida y no dry_run) llamar RPC
    // -------------------------------------------------------------------------
    let    filasExitosas  = 0;
    let    filasConError  = 0;
    const  detalleErrores: ErrorFila[] = [];

    for (let i = 0; i < filas.length; i++) {
      const numeroFila = i + 2; // +2: fila 1 = encabezados, filas de datos desde fila 2

      const { filaJsonb, errores: erroresValidacion } = procesarFila(
        filas[i],
        template.campos,
        numeroFila,
      );

      // Si hay errores de validación, registrar y continuar
      if (erroresValidacion.length > 0) {
        filasConError++;
        detalleErrores.push(...erroresValidacion);
        continue;
      }

      // Fila válida: si es dry_run solo contar como exitosa
      if (dryRun) {
        filasExitosas++;
        continue;
      }

      // Llamar la RPC destino del template
      // La RPC debe aceptar (p_empresa_id UUID, p_fila JSONB) → JSONB
      // Retorno esperado: { ok: true, id: uuid } | { ok: false, error: "mensaje" }
      try {
        const { data: rpcResult, error: rpcError } = await supabaseClient.rpc(
          template.rpc_destino,
          {
            p_empresa_id: empresaId,
            p_fila:       filaJsonb,
          },
        );

        if (rpcError) {
          filasConError++;
          detalleErrores.push({
            fila:  numeroFila,
            campo: '_rpc',
            error: `Error en RPC ${template.rpc_destino}: ${rpcError.message}`,
          });
          continue;
        }

        // La RPC puede retornar { ok: false, error: "mensaje" } para errores de negocio
        if (rpcResult && typeof rpcResult === 'object' && rpcResult.ok === false) {
          filasConError++;
          detalleErrores.push({
            fila:  numeroFila,
            campo: '_negocio',
            error: rpcResult.error ?? 'Error de negocio no especificado',
          });
          continue;
        }

        filasExitosas++;

      } catch (rpcException) {
        filasConError++;
        detalleErrores.push({
          fila:  numeroFila,
          campo: '_exception',
          error: `Excepción al llamar RPC: ${rpcException instanceof Error ? rpcException.message : String(rpcException)}`,
        });
      }
    }

    // -------------------------------------------------------------------------
    // 16. Determinar estado final del job
    // -------------------------------------------------------------------------
    let estadoFinal: 'COMPLETADO' | 'ERROR_PARCIAL' | 'FALLIDO';

    if (filasConError === 0) {
      estadoFinal = 'COMPLETADO';
    } else if (filasExitosas === 0) {
      estadoFinal = 'FALLIDO';
    } else {
      estadoFinal = 'ERROR_PARCIAL';
    }

    // -------------------------------------------------------------------------
    // 17. Actualizar job con resultado final
    //     Usamos la RPC finalizar_import_job (SECURITY DEFINER) que verifica
    //     empresa_id via get_empresa_id() del JWT del usuario.
    // -------------------------------------------------------------------------
    const { error: finalizarError } = await supabaseClient.rpc('finalizar_import_job', {
      p_job_id:      jobId,
      p_filas_ok:    filasExitosas,
      p_filas_error: filasConError,
      p_errores:     detalleErrores,
      p_estado:      estadoFinal,
    });

    if (finalizarError) {
      // No crítico: el resultado ya fue procesado, solo falló la actualización del historial
      console.error('[import-data] Error al finalizar job en BD:', finalizarError);
    }

    console.log(
      `[import-data] Job ${jobId} finalizado: ${estadoFinal} | ` +
      `exitosas=${filasExitosas} | errores=${filasConError}`,
    );

    // -------------------------------------------------------------------------
    // 18. Retornar resumen al cliente
    // -------------------------------------------------------------------------
    return jsonResponse({
      ok:              true,
      job_id:          jobId,
      dry_run:         dryRun,
      estado:          estadoFinal,
      total:           filas.length,
      exitosas:        filasExitosas,
      errores:         filasConError,
      detalle_errores: detalleErrores,
    });

  } catch (err) {
    // Catch global: nunca exponer stack traces al cliente
    console.error('[import-data] Error inesperado:', err);
    return errorResponse(
      500,
      'INTERNAL_ERROR',
      `Error procesando la solicitud: ${err instanceof Error ? err.message : 'Error desconocido'}`,
    );
  }
});
