/**
 * PILAR ERP — Edge Function: sri-firma-envio
 *
 * Procesa UN item de la cola `cola_documentos_electronicos` por invocación:
 *   1. Obtiene el item de cola y los datos de la empresa (certificado, ambiente)
 *   2. Descarga el certificado .p12 desde Storage
 *   3. Obtiene la contraseña del certificado desde Supabase Vault
 *   4. Valida y firma el XML con XAdES-BES
 *   5. Guarda el XML firmado en Storage (sri-documents/)
 *   6. Envía al servicio SOAP de recepción del SRI
 *   7. Consulta autorización (poll, máx 3 intentos)
 *   8. Actualiza el estado final en la cola: AUTORIZADO | RECHAZADO | ENVIADO (EN_PROCESO)
 *
 * Puede llamarse desde:
 *   - Flutter (usuario autenticado con JWT)
 *   - pg_cron (con service_role key como Authorization header)
 *
 * Método:   POST
 * Auth:     verify_jwt = true
 * Body:     { cola_item_id: string }
 *
 * Respuestas:
 *   200  AUTORIZADO   → { ok: true, estado, numero_autorizacion, fecha_autorizacion, clave_acceso }
 *   202  EN_PROCESO   → { ok: true, estado, mensaje }
 *   409  CONFLICT     → item no encontrado, estado inválido o bloqueo optimista
 *   422  RECHAZADO    → { ok: false, estado, mensajes }
 *   4xx/5xx          → { ok: false, error: código, detail? }
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { firmarDocumentoSri, validateXmlBeforeSigning } from '../_shared/sri-signer.ts';
import {
  buildReceptionEnvelope,
  sendSoapRequest,
  parseReceptionResponse,
  pollAuthorization,
  SRI_ENDPOINTS,
  type AmbienteSri,
} from '../_shared/sri-soap.ts';

// ---------------------------------------------------------------------------
// Tipos locales
// ---------------------------------------------------------------------------

/** Estados válidos del item de cola para procesar en esta función. */
const ESTADOS_PROCESABLES = ['PENDIENTE', 'ERROR'] as const;

/** Datos que retorna el RPC get_cola_item_para_firma. */
interface ColaItemParaFirma {
  cola_item: {
    id: string;
    empresa_id: string;
    tipo_documento: string;
    clave_acceso: string;
    secuencial: string;
    ambiente: number;
    xml_sin_firma: string;
    estado: string;
    intentos: number;
    version: number;
  };
  empresa: {
    id: string;
    ambiente_sri: number;      // 1=PRUEBAS, 2=PRODUCCION
    certificado_path: string;  // Path en bucket 'certificados'
    certificado_vault_key_id: string;
  };
}

/** Mensaje SRI individual (recepción o autorización). */
interface MensajeSri {
  identificador: string;
  mensaje: string;
  tipo: string;
  informacionAdicional?: string;
}

/** Respuesta de éxito autorizado. */
interface RespuestaAutorizado {
  ok: true;
  estado: 'AUTORIZADO';
  numero_autorizacion: string;
  fecha_autorizacion: string;
  clave_acceso: string;
}

/** Respuesta de éxito en proceso (aún no autorizado). */
interface RespuestaEnProceso {
  ok: true;
  estado: 'EN_PROCESO';
  mensaje: string;
}

/** Respuesta de documento rechazado. */
interface RespuestaRechazado {
  ok: false;
  estado: 'RECHAZADO';
  mensajes: MensajeSri[];
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
// Helper: guardar XML en Storage
// Ruta: sri-documents/{empresaId}/{año}/{mes}/{claveAcceso}_{sufijo}.xml
// ---------------------------------------------------------------------------

async function saveXmlToStorage(
  supabaseAdmin: SupabaseClient,
  empresaId: string,
  claveAcceso: string,
  xmlContent: string,
  sufijo: 'firmado' | 'autorizado',
): Promise<string> {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const path = `${empresaId}/${year}/${month}/${claveAcceso}_${sufijo}.xml`;

  const { error } = await supabaseAdmin.storage
    .from('sri-documents')
    .upload(path, new TextEncoder().encode(xmlContent), {
      contentType: 'application/xml',
      upsert: true,
    });

  if (error) {
    throw new Error(`STORAGE_WRITE_ERROR: ${error.message}`);
  }

  return path;
}

// ---------------------------------------------------------------------------
// Helper: convertir número de ambiente a tipo AmbienteSri
// ---------------------------------------------------------------------------

function getAmbienteSri(ambienteNum: number): AmbienteSri {
  return ambienteNum === 2 ? 'PRODUCCION' : 'PRUEBAS';
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
    return errorResponse(405, 'METHOD_NOT_ALLOWED');
  }

  // 3. Header de autorización obligatorio
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse(401, 'UNAUTHORIZED');
  }

  // 4. Construir clientes Supabase
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey     = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // supabaseClient: actúa con el JWT del llamador (usuario o pg_cron con service_role)
  const supabaseClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // supabaseAdmin: service role, para Storage, Vault y RPCs admin
  const supabaseAdmin: SupabaseClient = createClient(supabaseUrl, serviceKey);

  try {
    // 5. Verificar autenticación
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !user) {
      return errorResponse(401, 'UNAUTHORIZED');
    }

    // 6. Parsear body y validar cola_item_id
    let body: { cola_item_id?: string };
    try {
      body = await req.json();
    } catch {
      return errorResponse(400, 'BODY_INVALIDO');
    }

    const colaItemId = body.cola_item_id?.trim();
    if (!colaItemId) {
      return errorResponse(400, 'COLA_ITEM_REQUERIDO');
    }

    // -----------------------------------------------------------------------
    // PASO 1: Obtener item de cola + datos de empresa
    // -----------------------------------------------------------------------
    const { data: rpcData, error: rpcError } = await supabaseAdmin.rpc(
      'get_cola_item_para_firma',
      { p_cola_item_id: colaItemId },
    );

    if (rpcError || !rpcData) {
      console.warn('[sri-firma-envio] Cola item no encontrado:', colaItemId, rpcError?.message);
      return errorResponse(409, 'COLA_ITEM_NO_ENCONTRADO');
    }

    const { cola_item: item, empresa } = rpcData as ColaItemParaFirma;

    // Verificar que el estado permita procesamiento
    if (!ESTADOS_PROCESABLES.includes(item.estado as typeof ESTADOS_PROCESABLES[number])) {
      return errorResponse(409, 'ESTADO_INVALIDO', {
        estado_actual: item.estado,
        estados_permitidos: ESTADOS_PROCESABLES,
      });
    }

    const ambiente: AmbienteSri = getAmbienteSri(empresa.ambiente_sri);
    const claveAcceso = item.clave_acceso;
    const empresaId   = item.empresa_id;

    // -----------------------------------------------------------------------
    // PASO 2: Descargar certificado .p12 desde Storage
    // -----------------------------------------------------------------------
    let certificadoBytes: ArrayBuffer;
    try {
      const { data: certBlob, error: certError } = await supabaseAdmin.storage
        .from('certificados')
        .download(empresa.certificado_path);

      if (certError || !certBlob) {
        throw new Error(certError?.message ?? 'blob vacío');
      }
      certificadoBytes = await certBlob.arrayBuffer();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error('[sri-firma-envio] Error al obtener certificado:', msg);
      await marcarError(supabaseAdmin, colaItemId, 'CERT_NOT_FOUND: ' + msg, item.version);
      return errorResponse(500, 'CERT_NOT_FOUND');
    }

    // -----------------------------------------------------------------------
    // PASO 3: Obtener contraseña del certificado desde Vault
    // -----------------------------------------------------------------------
    let certPassword: string;
    try {
      const { data: pwd, error: vaultError } = await supabaseAdmin.rpc(
        'get_certificate_password',
        { p_empresa_id: empresaId },
      );

      if (vaultError || !pwd) {
        throw new Error(vaultError?.message ?? 'contraseña vacía');
      }
      certPassword = pwd as string;
    } catch (err) {
      // NUNCA loguear la contraseña ni detalles del Vault
      console.error('[sri-firma-envio] Error al obtener contraseña de Vault');
      await marcarError(supabaseAdmin, colaItemId, 'VAULT_ERROR', item.version);
      return errorResponse(500, 'VAULT_ERROR');
    }

    // -----------------------------------------------------------------------
    // PASO 4: Validar XML antes de firmar
    // -----------------------------------------------------------------------
    try {
      validateXmlBeforeSigning(item.xml_sin_firma);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error('[sri-firma-envio] XML inválido:', msg);
      await marcarError(supabaseAdmin, colaItemId, 'XML_INVALIDO: ' + msg, item.version);
      return errorResponse(422, 'XML_INVALIDO', msg);
    }

    // -----------------------------------------------------------------------
    // PASO 5: Firmar XML con XAdES-BES
    // -----------------------------------------------------------------------
    let xmlFirmado: string;
    try {
      xmlFirmado = await firmarDocumentoSri(
        item.xml_sin_firma,
        certificadoBytes,
        certPassword,
      );
    } catch (err) {
      // NUNCA loguear certPassword ni el contenido del certificado
      const msg = err instanceof Error ? err.message : 'error desconocido';
      console.error('[sri-firma-envio] Error al firmar XML:', msg);
      await marcarError(supabaseAdmin, colaItemId, 'SIGNING_ERROR: ' + msg, item.version);
      return errorResponse(500, 'SIGNING_ERROR');
    }

    // -----------------------------------------------------------------------
    // PASO 6: Guardar XML firmado en Storage
    // -----------------------------------------------------------------------
    let xmlFirmadoPath: string;
    try {
      xmlFirmadoPath = await saveXmlToStorage(
        supabaseAdmin,
        empresaId,
        claveAcceso,
        xmlFirmado,
        'firmado',
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error('[sri-firma-envio] Error al guardar XML firmado en Storage:', msg);
      await marcarError(supabaseAdmin, colaItemId, msg, item.version);
      return errorResponse(500, 'STORAGE_ERROR');
    }

    // -----------------------------------------------------------------------
    // PASO 7: Actualizar cola → FIRMADO (bloqueo optimista con version)
    // -----------------------------------------------------------------------
    const { error: firmadoError } = await supabaseAdmin.rpc('update_cola_firmado', {
      p_cola_item_id:   colaItemId,
      p_xml_firmado:    xmlFirmado,
      p_xml_firmado_path: xmlFirmadoPath,
      p_version:        item.version,
    });

    if (firmadoError) {
      console.error('[sri-firma-envio] Version conflict al marcar FIRMADO:', firmadoError.message);
      return errorResponse(409, 'VERSION_CONFLICT');
    }

    // La version se incrementó en BD; la RPC devuelve la nueva version
    // Para los siguientes RPCs usamos version + 1
    const versionFirmado = item.version + 1;

    // -----------------------------------------------------------------------
    // PASO 8: Enviar al SRI — SOAP recepción
    // -----------------------------------------------------------------------
    const xmlBase64 = btoa(unescape(encodeURIComponent(xmlFirmado)));
    const soapEnvelope = buildReceptionEnvelope(xmlBase64);
    const endpointRecepcion = SRI_ENDPOINTS[ambiente].recepcion;

    let soapResponse: string;
    try {
      soapResponse = await sendSoapRequest(endpointRecepcion, soapEnvelope);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const isTimeout = msg.toLowerCase().includes('timeout');
      console.error('[sri-firma-envio] Error SOAP recepción:', msg);
      await marcarError(
        supabaseAdmin,
        colaItemId,
        (isTimeout ? 'SRI_TIMEOUT' : 'SRI_COMMUNICATION_ERROR') + ': ' + msg,
        versionFirmado,
      );
      return errorResponse(isTimeout ? 504 : 502, isTimeout ? 'SRI_TIMEOUT' : 'SRI_COMMUNICATION_ERROR');
    }

    // -----------------------------------------------------------------------
    // PASO 9: Parsear respuesta de recepción
    // -----------------------------------------------------------------------
    const recepcionResult = parseReceptionResponse(soapResponse);

    if (recepcionResult.estado === 'DEVUELTA') {
      // El SRI rechazó el documento en la recepción
      const mensajes: MensajeSri[] = recepcionResult.mensajes ?? [];
      console.warn('[sri-firma-envio] Documento DEVUELTO por SRI:', JSON.stringify(mensajes));

      await supabaseAdmin.rpc('update_cola_rechazado', {
        p_cola_item_id: colaItemId,
        p_mensajes:     mensajes,
        p_version:      versionFirmado,
      });

      const respuesta: RespuestaRechazado = {
        ok: false,
        estado: 'RECHAZADO',
        mensajes,
      };
      return jsonResponse(422, respuesta);
    }

    // Estado RECIBIDA → continuar con autorización
    if (recepcionResult.estado !== 'RECIBIDA') {
      // Estado inesperado de recepción
      const msg = `Estado de recepción inesperado: ${recepcionResult.estado}`;
      console.error('[sri-firma-envio]', msg);
      await marcarError(supabaseAdmin, colaItemId, msg, versionFirmado);
      return errorResponse(502, 'SRI_COMMUNICATION_ERROR', msg);
    }

    // -----------------------------------------------------------------------
    // PASO 10: Actualizar cola → ENVIADO
    // -----------------------------------------------------------------------
    const { error: enviadoError } = await supabaseAdmin.rpc('update_cola_enviado', {
      p_cola_item_id: colaItemId,
      p_version:      versionFirmado,
    });

    if (enviadoError) {
      console.error('[sri-firma-envio] Version conflict al marcar ENVIADO:', enviadoError.message);
      return errorResponse(409, 'VERSION_CONFLICT');
    }

    const versionEnviado = versionFirmado + 1;

    // -----------------------------------------------------------------------
    // PASO 11: Poll de autorización (máx 3 intentos, 5 s entre cada uno)
    // -----------------------------------------------------------------------
    const endpointAutorizacion = SRI_ENDPOINTS[ambiente].autorizacion;

    let autorizacionResult: Awaited<ReturnType<typeof pollAuthorization>>;
    try {
      autorizacionResult = await pollAuthorization(
        endpointAutorizacion,
        claveAcceso,
        { maxIntentos: 3, intervaloMs: 5000 },
      );
    } catch (err) {
      // Timeout o error de comunicación durante el poll de autorización
      // Se deja el item en estado ENVIADO para que pg_cron reintente
      const msg = err instanceof Error ? err.message : String(err);
      const isTimeout = msg.toLowerCase().includes('timeout');
      console.warn('[sri-firma-envio] Error al consultar autorización, se reintentará:', msg);
      // No marcamos ERROR: el item queda en ENVIADO y pg_cron lo reintentará
      const respuesta: RespuestaEnProceso = {
        ok: true,
        estado: 'EN_PROCESO',
        mensaje: 'Documento recibido por SRI, pendiente de autorización (error en consulta)',
      };
      return jsonResponse(isTimeout ? 202 : 202, respuesta);
    }

    // -----------------------------------------------------------------------
    // PASO 12: Procesar resultado de autorización
    // -----------------------------------------------------------------------

    if (autorizacionResult.estado === 'EN_PROCESO') {
      // SRI aún no ha procesado el documento — pg_cron reintentará
      const respuesta: RespuestaEnProceso = {
        ok: true,
        estado: 'EN_PROCESO',
        mensaje: 'Documento recibido por SRI, pendiente autorización',
      };
      return jsonResponse(202, respuesta);
    }

    if (autorizacionResult.estado === 'NO_AUTORIZADO') {
      const mensajes: MensajeSri[] = autorizacionResult.mensajes ?? [];
      console.warn('[sri-firma-envio] Documento NO AUTORIZADO por SRI:', JSON.stringify(mensajes));

      await supabaseAdmin.rpc('update_cola_rechazado', {
        p_cola_item_id: colaItemId,
        p_mensajes:     mensajes,
        p_version:      versionEnviado,
      });

      const respuesta: RespuestaRechazado = {
        ok: false,
        estado: 'RECHAZADO',
        mensajes,
      };
      return jsonResponse(422, respuesta);
    }

    // Estado AUTORIZADO
    if (autorizacionResult.estado === 'AUTORIZADO') {
      const numeroAutorizacion = autorizacionResult.numero_autorizacion!;
      const fechaAutorizacion  = autorizacionResult.fecha_autorizacion!;
      const xmlAutorizado      = autorizacionResult.xml_autorizado!;

      // Guardar XML autorizado en Storage
      let xmlAutorizadoPath: string;
      try {
        xmlAutorizadoPath = await saveXmlToStorage(
          supabaseAdmin,
          empresaId,
          claveAcceso,
          xmlAutorizado,
          'autorizado',
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error('[sri-firma-envio] Error al guardar XML autorizado en Storage:', msg);
        // El documento fue autorizado por SRI aunque no pudo guardarse en Storage.
        // Marcamos igualmente como AUTORIZADO para no perder la autorización;
        // el XML autorizado se pasa en la RPC directamente.
        xmlAutorizadoPath = '';
      }

      // Actualizar cola → AUTORIZADO
      const { error: autorizadoError } = await supabaseAdmin.rpc('update_cola_autorizado', {
        p_cola_item_id:       colaItemId,
        p_numero_autorizacion: numeroAutorizacion,
        p_fecha_autorizacion:  fechaAutorizacion,
        p_xml_autorizado:      xmlAutorizado,
        p_xml_autorizado_path: xmlAutorizadoPath,
        p_version:             versionEnviado,
      });

      if (autorizadoError) {
        // Aunque el SRI autorizó el documento, hubo un conflict de versión en BD.
        // Es seguro retornar el número de autorización; el estado real está en SRI.
        console.error('[sri-firma-envio] Version conflict al marcar AUTORIZADO:', autorizadoError.message);
        return errorResponse(409, 'VERSION_CONFLICT');
      }

      const respuesta: RespuestaAutorizado = {
        ok: true,
        estado: 'AUTORIZADO',
        numero_autorizacion: numeroAutorizacion,
        fecha_autorizacion:  fechaAutorizacion,
        clave_acceso:        claveAcceso,
      };
      return jsonResponse(200, respuesta);
    }

    // Estado no contemplado
    const msgInesperado = `Estado de autorización no contemplado: ${autorizacionResult.estado}`;
    console.error('[sri-firma-envio]', msgInesperado);
    await marcarError(supabaseAdmin, colaItemId, msgInesperado, versionEnviado);
    return errorResponse(502, 'SRI_COMMUNICATION_ERROR', msgInesperado);

  } catch (err) {
    // Catch global: nunca exponer detalles internos al cliente
    console.error('[sri-firma-envio] Error inesperado:', err instanceof Error ? err.message : err);
    return errorResponse(500, 'INTERNAL_ERROR');
  }
});

// ---------------------------------------------------------------------------
// Helper: marcar item de cola como ERROR con backoff exponencial
// Solo actualiza intentos + error_message + proximo_intento; no lanza excepción.
// ---------------------------------------------------------------------------

async function marcarError(
  supabaseAdmin: SupabaseClient,
  colaItemId: string,
  errorMessage: string,
  version: number,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc('update_cola_error', {
    p_cola_item_id:  colaItemId,
    p_error_message: errorMessage,
    p_version:       version,
  });

  if (error) {
    // Solo loguear; si falla la actualización de error, no es crítico para el flujo
    console.error('[sri-firma-envio] No se pudo marcar ERROR en cola:', error.message);
  }
}
