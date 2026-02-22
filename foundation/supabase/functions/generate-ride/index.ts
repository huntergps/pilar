/**
 * PILAR ERP — Edge Function: generate-ride
 *
 * Genera el RIDE PDF (Representación Impresa del Documento Electrónico)
 * de un documento SRI autorizado, lo sube a Supabase Storage en el bucket
 * privado 'ride-pdf' y retorna una URL firmada con validez de 1 hora.
 *
 * Puede ser llamada de dos formas:
 *   1. HTTP POST directo (desde Flutter o desde sri-firma-envio post-autorización):
 *        Body: { "cola_item_id": "<uuid>" }
 *   2. Internal call (desde cron batch con service_role):
 *        Body: { "cola_item_id": "<uuid>" }
 *        Authorization: Bearer <service_role_key>
 *
 * Método:  POST
 * Auth:    JWT requerido (verify_jwt: true)
 * Permiso: facturacion.documentos.ver
 *
 * Respuesta exitosa (200):
 *   { ok: true, url: string, path: string, cached: boolean }
 *   - url    → URL firmada privada (válida 1 hora) del RIDE PDF en Storage
 *   - path   → Path en Storage bucket 'ride-pdf'
 *   - cached → true si el RIDE ya existía y no fue regenerado
 *
 * Tabla de errores:
 *   400  BODY_INVALIDO           — body no es JSON válido
 *   400  COLA_ITEM_INVALIDO      — cola_item_id no es un UUID válido
 *   401  UNAUTHORIZED            — JWT ausente o inválido
 *   404  COLA_ITEM_NO_ENCONTRADO — el item no existe o no está AUTORIZADO
 *   405  METHOD_NOT_ALLOWED      — método distinto de POST
 *   409  ESTADO_INVALIDO         — el item existe pero no está AUTORIZADO
 *   422  XML_AUTORIZADO_INVALIDO — xml_autorizado es NULL, vacío o malformado
 *   500  PDF_GENERATION_ERROR    — error al generar el PDF con pdf-lib
 *   500  STORAGE_ERROR           — error al subir el PDF a Storage o generar URL
 *   500  INTERNAL_ERROR          — error inesperado no clasificado
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { parsearXmlAutorizado, DocumentoSriParseado } from '../_shared/xml-parser.ts';
import { generarRidePdf, RideData } from '../_shared/ride-pdf.ts';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const BUCKET_RIDE = 'ride-pdf';
const SIGNED_URL_EXPIRY_SECONDS = 3600; // 1 hora

// ---------------------------------------------------------------------------
// Tipos locales
// ---------------------------------------------------------------------------

/** Fila retornada por el RPC get_cola_item_para_ride. */
interface ColaItemParaRide {
  cola_id: string;
  empresa_id: string;
  clave_acceso: string;
  xml_autorizado: string | null;
  tabla_origen: string;
  estado: string;
  ride_pdf_path: string | null;
  ruc: string;
  razon_social: string;
  nombre_comercial: string | null;
  dir_matriz: string | null;
  logo_url: string | null;
  logo_path: string | null;
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

function errorResponse(status: number, code: string, detail?: unknown): Response {
  return jsonResponse(status, { ok: false, error: code, detail });
}

// ---------------------------------------------------------------------------
// Helper: valida que una cadena sea un UUID v4 en formato canónico
// ---------------------------------------------------------------------------

function isValidUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

// ---------------------------------------------------------------------------
// Helper: construye el path de Storage para el RIDE PDF
// Convención: ride-pdf/{empresa_id}/{año}/{mes}/{clave_acceso}.pdf
// Esta ruta es determinística: para la misma clave de acceso siempre produce
// el mismo path. Upsert en Storage sobreescribe el archivo si ya existe.
// ---------------------------------------------------------------------------

function getRidePath(empresaId: string, claveAcceso: string): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${empresaId}/${year}/${month}/${claveAcceso}.pdf`;
}

// ---------------------------------------------------------------------------
// Helper: descarga el logo desde Storage (fallo suave)
// Retorna los bytes del logo y su MIME type, o undefined si falla/no existe.
// Si el logo falla en descargarse, el RIDE se genera sin logo.
// ---------------------------------------------------------------------------

async function descargarLogo(
  supabaseAdmin: SupabaseClient,
  logoPath: string,
): Promise<{ bytes: Uint8Array; mimeType: 'image/png' | 'image/jpeg' } | undefined> {
  try {
    const { data: blob, error } = await supabaseAdmin.storage
      .from('logos')
      .download(logoPath);

    if (error || !blob) {
      console.log('[generate-ride] Logo no disponible en Storage, se continúa sin logo.');
      return undefined;
    }

    const arrayBuffer = await blob.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);

    // Detectar formato por extensión del path (el bucket 'logos' acepta PNG y JPEG)
    const lowerPath = logoPath.toLowerCase();
    const mimeType: 'image/png' | 'image/jpeg' = lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')
      ? 'image/jpeg'
      : 'image/png';

    return { bytes, mimeType };
  } catch {
    console.log('[generate-ride] Error al descargar logo, se continúa sin logo.');
    return undefined;
  }
}

// ---------------------------------------------------------------------------
// Helper: construye RideData a partir del item de cola y el documento parseado
//
// Mapea los campos de DocumentoSriParseado (union type discriminado por tipo
// '01'|'03'|'04'|'05'|'06'|'07') a los campos de RideData, incluyendo los
// datos del emisor (empresa) y del logo si está disponible.
//
// Cada rama del if corresponde a un tipo de documento SRI:
//   '01' Factura            → receptor=comprador, detalles=líneas, pagos, IVA totales
//   '03' Liquidación Compra → igual que factura (comprador = proveedor en liquidación)
//   '04' Nota de Crédito    → igual + codDocModificado, numDocModificado, motivoNC
//   '05' Nota de Débito     → igual que NC
//   '06' Guía de Remisión   → datos de transporte, receptor de destinatarios[0]
//   '07' Retención          → receptor=sujeto retenido, retenciones, periodoFiscal
// ---------------------------------------------------------------------------

function buildRideData(
  item: {
    empresa_id: string;
    ruc: string;
    razon_social: string;
    nombre_comercial: string | null;
    dir_matriz: string | null;
    logo_url: string | null;
  },
  doc: DocumentoSriParseado,
  logoBytes?: Uint8Array,
  logoMimeType?: 'image/png' | 'image/jpeg',
): RideData {
  // Datos del emisor — comunes a todos los tipos de documento
  const emisor = {
    ruc: item.ruc,
    razonSocial: item.razon_social,
    nombreComercial: item.nombre_comercial ?? item.razon_social,
    dirMatriz: item.dir_matriz ?? '',
    // Datos del establecimiento y punto de emisión desde infoTributaria del XML
    dirEstablecimiento: doc.infoTributaria.dirEstablecimiento ?? '',
    establecimiento: doc.infoTributaria.estab,
    puntoEmision: doc.infoTributaria.ptoEmi,
    secuencial: doc.infoTributaria.secuencial,
    ambiente: doc.autorizacion.ambiente,
    tipoEmision: doc.infoTributaria.tipoEmision,
  };

  // Logo — opcional
  const logo = logoBytes && logoMimeType
    ? { bytes: logoBytes, mimeType: logoMimeType }
    : (item.logo_url ? { url: item.logo_url } : undefined);

  // Metadatos de autorización SRI
  const autorizacion = {
    numero: doc.autorizacion.numeroAutorizacion,
    fechaHora: doc.autorizacion.fechaAutorizacion,
    ambiente: doc.autorizacion.ambiente,
    claveAcceso: doc.autorizacion.claveAcceso,
  };

  // Datos específicos por tipo de documento
  if (doc.tipo === '01') {
    // Factura
    return {
      tipo: '01',
      emisor,
      logo,
      autorizacion,
      receptor: {
        razonSocial: doc.info.razonSocialComprador,
        identificacion: doc.info.identificacionComprador,
        tipoIdentificacion: doc.info.tipoIdentificacionComprador,
        direccion: doc.info.direccionComprador ?? '',
      },
      fechaEmision: doc.info.fechaEmision,
      totalSinImpuestos: doc.info.totalSinImpuestos,
      totalDescuento: doc.info.totalDescuento,
      totalConImpuestos: doc.info.totalConImpuestos,
      importeTotal: doc.info.importeTotal,
      moneda: doc.info.moneda ?? 'DOLAR',
      pagos: doc.info.pagos ?? [],
      detalles: doc.detalles ?? [],
      infoAdicional: doc.infoAdicional ?? [],
    };
  }

  if (doc.tipo === '03') {
    // Liquidación de Compra
    return {
      tipo: '03',
      emisor,
      logo,
      autorizacion,
      receptor: {
        razonSocial: doc.info.razonSocialProveedor,
        identificacion: doc.info.identificacionProveedor,
        tipoIdentificacion: doc.info.tipoIdentificacionProveedor,
        direccion: doc.info.direccionProveedor ?? '',
      },
      fechaEmision: doc.info.fechaEmision,
      totalSinImpuestos: doc.info.totalSinImpuestos,
      totalDescuento: doc.info.totalDescuento,
      totalConImpuestos: doc.info.totalConImpuestos,
      importeTotal: doc.info.importeTotal,
      moneda: doc.info.moneda ?? 'DOLAR',
      pagos: doc.info.pagos ?? [],
      detalles: doc.detalles ?? [],
      infoAdicional: doc.infoAdicional ?? [],
    };
  }

  if (doc.tipo === '04') {
    // Nota de Crédito
    return {
      tipo: '04',
      emisor,
      logo,
      autorizacion,
      receptor: {
        razonSocial: doc.info.razonSocialComprador,
        identificacion: doc.info.identificacionComprador,
        tipoIdentificacion: doc.info.tipoIdentificacionComprador,
        direccion: doc.info.direccionComprador ?? '',
      },
      fechaEmision: doc.info.fechaEmision,
      totalSinImpuestos: doc.info.totalSinImpuestos,
      totalDescuento: doc.info.totalDescuento ?? '0.00',
      totalConImpuestos: doc.info.totalConImpuestos,
      valorModificacion: doc.info.valorModificacion,
      codDocModificado: doc.info.codDocModificado,
      numDocModificado: doc.info.numDocModificado,
      fechaEmisionDocSustento: doc.info.fechaEmisionDocSustento,
      motivo: doc.info.motivo,
      detalles: doc.detalles ?? [],
      infoAdicional: doc.infoAdicional ?? [],
    };
  }

  if (doc.tipo === '05') {
    // Nota de Débito
    return {
      tipo: '05',
      emisor,
      logo,
      autorizacion,
      receptor: {
        razonSocial: doc.info.razonSocialComprador,
        identificacion: doc.info.identificacionComprador,
        tipoIdentificacion: doc.info.tipoIdentificacionComprador,
        direccion: doc.info.direccionComprador ?? '',
      },
      fechaEmision: doc.info.fechaEmision,
      totalSinImpuestos: doc.info.totalSinImpuestos,
      totalConImpuestos: doc.info.totalConImpuestos,
      valorTotal: doc.info.valorTotal,
      codDocModificado: doc.info.codDocModificado,
      numDocModificado: doc.info.numDocModificado,
      fechaEmisionDocSustento: doc.info.fechaEmisionDocSustento,
      motivo: doc.info.motivo,
      impuestosAdicionales: doc.info.impuestosAdicionales ?? [],
      infoAdicional: doc.infoAdicional ?? [],
    };
  }

  if (doc.tipo === '06') {
    // Guía de Remisión — el receptor se extrae del primer destinatario
    const primerDestinatario = doc.destinatarios?.[0];
    return {
      tipo: '06',
      emisor,
      logo,
      autorizacion,
      receptor: primerDestinatario
        ? {
            razonSocial: primerDestinatario.razonSocialDestinatario,
            identificacion: primerDestinatario.identificacionDestinatario,
            tipoIdentificacion: primerDestinatario.tipoIdentificacionDestinatario ?? '04',
            direccion: primerDestinatario.dirDestinatario ?? '',
          }
        : {
            razonSocial: 'CONSUMIDOR FINAL',
            identificacion: '9999999999999',
            tipoIdentificacion: '07',
            direccion: '',
          },
      fechaEmision: doc.info.fechaIniTransporte,
      dirPartida: doc.info.dirPartida,
      dirEstablecimiento: doc.info.dirEstablecimiento ?? '',
      razonSocialTransportista: doc.info.razonSocialTransportista,
      tipoIdentificacionTransportista: doc.info.tipoIdentificacionTransportista,
      rucTransportista: doc.info.rucTransportista,
      placa: doc.info.placa,
      fechaIniTransporte: doc.info.fechaIniTransporte,
      fechaFinTransporte: doc.info.fechaFinTransporte,
      destinatarios: doc.destinatarios ?? [],
      infoAdicional: doc.infoAdicional ?? [],
    };
  }

  // doc.tipo === '07' → Comprobante de Retención
  return {
    tipo: '07',
    emisor,
    logo,
    autorizacion,
    receptor: {
      razonSocial: doc.info.razonSocialSujetoRetenido,
      identificacion: doc.info.identificacionSujetoRetenido,
      tipoIdentificacion: doc.info.tipoIdentificacionSujetoRetenido,
      direccion: '',
    },
    fechaEmision: doc.info.fechaEmision,
    periodoFiscal: doc.info.periodoFiscal,
    retenciones: doc.retenciones ?? [],
    infoAdicional: doc.infoAdicional ?? [],
  };
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
  //    supabaseClient: actúa con el JWT del llamador (para auth.getUser + check_permission)
  //    supabaseAdmin:  service_role, para Storage, RPCs admin y get_cola_item_para_ride
  const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
  const anonKey        = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const supabaseClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const supabaseAdmin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

  try {
    // 5. Parsear body JSON
    let body: { cola_item_id?: unknown };
    try {
      body = await req.json();
    } catch {
      return errorResponse(400, 'BODY_INVALIDO', 'El body debe ser JSON con { cola_item_id }');
    }

    // 6. Validar que cola_item_id sea un UUID válido
    const rawId = body.cola_item_id;
    if (typeof rawId !== 'string' || rawId.trim() === '') {
      return errorResponse(400, 'COLA_ITEM_INVALIDO', 'cola_item_id es requerido');
    }
    const colaItemId = rawId.trim();
    if (!isValidUuid(colaItemId)) {
      return errorResponse(400, 'COLA_ITEM_INVALIDO', 'cola_item_id debe ser un UUID válido');
    }

    // 7. Verificar usuario autenticado
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !user) {
      return errorResponse(401, 'UNAUTHORIZED', 'Token inválido o expirado');
    }

    // 8. Verificar permiso: lectura de documentos es suficiente para ver el RIDE
    const { data: hasPerm, error: permError } = await supabaseClient.rpc(
      'check_permission',
      { p_permiso: 'facturacion.documentos.ver' },
    );
    if (permError) {
      console.log('[generate-ride] Error al verificar permiso:', permError.message);
      return errorResponse(500, 'INTERNAL_ERROR', 'Error al verificar permisos');
    }
    if (!hasPerm) {
      return errorResponse(403, 'FORBIDDEN', 'No tiene permiso para ver documentos de facturación');
    }

    // 9. Obtener datos del item de cola via supabaseAdmin (service_role, elude RLS)
    console.log('[generate-ride] Obteniendo item de cola:', colaItemId);
    const { data: rows, error: rpcError } = await supabaseAdmin.rpc(
      'get_cola_item_para_ride',
      { p_cola_item_id: colaItemId },
    );

    if (rpcError) {
      console.log('[generate-ride] Error en RPC get_cola_item_para_ride:', rpcError.message);
      return errorResponse(500, 'INTERNAL_ERROR', 'Error al obtener datos del documento');
    }

    // El RPC retorna SETOF; si no hay fila, el item no existe o no está AUTORIZADO
    const itemRows = rows as ColaItemParaRide[] | null;
    if (!itemRows || itemRows.length === 0) {
      return errorResponse(404, 'COLA_ITEM_NO_ENCONTRADO', 'El item no existe o no está en estado AUTORIZADO');
    }

    const item = itemRows[0];

    // 10. Verificar estado explícitamente (defensa en profundidad; el RPC ya filtra AUTORIZADO)
    if (item.estado !== 'AUTORIZADO') {
      return errorResponse(409, 'ESTADO_INVALIDO', { estado: item.estado, esperado: 'AUTORIZADO' });
    }

    // 11. Si el RIDE ya fue generado, retornar URL firmada del PDF existente (cache)
    if (item.ride_pdf_path) {
      console.log('[generate-ride] RIDE ya existe, retornando URL firmada del caché:', item.ride_pdf_path);
      const { data: signedData, error: signError } = await supabaseAdmin.storage
        .from(BUCKET_RIDE)
        .createSignedUrl(item.ride_pdf_path, SIGNED_URL_EXPIRY_SECONDS);

      if (signError || !signedData?.signedUrl) {
        // El path existe en BD pero el archivo puede haber sido eliminado de Storage
        // Continuar para regenerar el RIDE en lugar de retornar error
        console.log('[generate-ride] No se pudo obtener URL del RIDE cacheado, regenerando...');
      } else {
        return jsonResponse(200, {
          ok: true,
          url: signedData.signedUrl,
          path: item.ride_pdf_path,
          cached: true,
        });
      }
    }

    // 12. Validar que xml_autorizado no sea NULL ni vacío
    if (!item.xml_autorizado || item.xml_autorizado.trim() === '') {
      console.log('[generate-ride] xml_autorizado es NULL o vacío para cola_item_id:', colaItemId);
      return errorResponse(422, 'XML_AUTORIZADO_INVALIDO', 'El item no tiene xml_autorizado');
    }

    // 13. Parsear XML autorizado
    // IMPORTANTE: nunca loguear el contenido del XML (puede contener datos fiscales sensibles)
    let doc: DocumentoSriParseado;
    try {
      console.log('[generate-ride] Parseando XML autorizado...');
      doc = parsearXmlAutorizado(item.xml_autorizado);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Error de parseo desconocido';
      console.log('[generate-ride] Error al parsear XML autorizado:', msg);
      return errorResponse(422, 'XML_AUTORIZADO_INVALIDO', msg);
    }

    // 14. Descargar logo (fallo suave: si falla, el RIDE se genera sin logo)
    let logoBytes: Uint8Array | undefined;
    let logoMimeType: 'image/png' | 'image/jpeg' | undefined;

    if (item.logo_path) {
      console.log('[generate-ride] Descargando logo desde Storage...');
      const logoResult = await descargarLogo(supabaseAdmin, item.logo_path);
      if (logoResult) {
        logoBytes = logoResult.bytes;
        logoMimeType = logoResult.mimeType;
        console.log('[generate-ride] Logo descargado correctamente.');
      }
    }

    // 15. Construir RideData mapeando DocumentoSriParseado → RideData
    console.log('[generate-ride] Construyendo RideData para tipo:', doc.tipo);
    const rideData = buildRideData(item, doc, logoBytes, logoMimeType);

    // 16. Generar PDF con pdf-lib (vía ride-pdf.ts)
    let pdfBytes: Uint8Array;
    try {
      console.log('[generate-ride] Generando PDF RIDE...');
      pdfBytes = await generarRidePdf(rideData);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Error de generación desconocido';
      console.log('[generate-ride] Error al generar PDF RIDE:', msg);
      return errorResponse(500, 'PDF_GENERATION_ERROR', msg);
    }

    // 17. Determinar ruta en Storage bucket 'ride-pdf'
    const ridePath = getRidePath(item.empresa_id, item.clave_acceso);
    console.log('[generate-ride] Subiendo PDF a Storage path:', ridePath);

    // 18. Subir PDF a Storage (upsert:true sobreescribe si ya existe, idempotente)
    const { error: uploadError } = await supabaseAdmin.storage
      .from(BUCKET_RIDE)
      .upload(ridePath, pdfBytes, {
        contentType: 'application/pdf',
        upsert: true,
      });

    if (uploadError) {
      console.log('[generate-ride] Error al subir PDF a Storage:', uploadError.message);
      return errorResponse(500, 'STORAGE_ERROR', 'No se pudo subir el RIDE PDF a Storage');
    }

    // 19. Actualizar cola_documentos_electronicos.ride_pdf_path via supabaseAdmin
    console.log('[generate-ride] Actualizando ride_pdf_path en cola...');
    const { data: updateResult, error: updateError } = await supabaseAdmin.rpc(
      'update_cola_ride_pdf',
      {
        p_cola_item_id:  colaItemId,
        p_ride_pdf_path: ridePath,
      },
    );

    if (updateError) {
      // El PDF ya fue subido a Storage; solo loguear el error de BD, no bloquear
      console.log('[generate-ride] Error al actualizar ride_pdf_path en cola:', updateError.message);
    } else if (updateResult && !updateResult.ok) {
      console.log('[generate-ride] update_cola_ride_pdf retornó NOT_FOUND para:', colaItemId);
    }

    // 20. Generar URL firmada privada (válida 1 hora)
    console.log('[generate-ride] Generando URL firmada del RIDE...');
    const { data: signedData, error: signError } = await supabaseAdmin.storage
      .from(BUCKET_RIDE)
      .createSignedUrl(ridePath, SIGNED_URL_EXPIRY_SECONDS);

    if (signError || !signedData?.signedUrl) {
      const msg = signError?.message ?? 'No se pudo obtener la URL firmada';
      console.log('[generate-ride] Error al generar URL firmada:', msg);
      return errorResponse(500, 'STORAGE_ERROR', 'PDF generado pero no se pudo obtener URL de descarga');
    }

    console.log('[generate-ride] RIDE generado y subido correctamente.');

    // 21. Respuesta exitosa
    return jsonResponse(200, {
      ok: true,
      url: signedData.signedUrl,
      path: ridePath,
      cached: false,
    });

  } catch (err) {
    // Catch global: nunca exponer detalles internos al cliente
    console.log('[generate-ride] Error inesperado:', err instanceof Error ? err.message : err);
    return errorResponse(500, 'INTERNAL_ERROR', 'Error procesando la solicitud');
  }
});
