/**
 * PILAR ERP — Shared: sri-soap.ts
 *
 * Comunicación SOAP con el SRI Ecuador.
 * Cubre recepción (validarComprobante) y autorización (autorizacionComprobante)
 * para todos los documentos electrónicos:
 *   01 Factura, 03 Liquidación de Compra, 04 NC, 05 ND, 06 Guía Remisión, 07 Retención
 *
 * Implementación sin dependencias externas: parsing por regex/indexOf porque la
 * estructura SOAP del SRI es conocida y fija. Evita cargar un parser XML completo.
 *
 * Uso:
 *   import { enviarDocumento, consultarAutorizacion, pollAuthorization } from '../_shared/sri-soap.ts'
 */

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

/** Ambiente donde opera el documento electrónico. */
export type AmbienteSri = 'PRUEBAS' | 'PRODUCCION'

/**
 * Mensaje devuelto por el SRI dentro de la respuesta SOAP.
 * El SRI puede devolver múltiples mensajes por comprobante.
 */
export interface MensajeSri {
  identificador: string
  mensaje: string
  tipo: 'ERROR' | 'ADVERTENCIA' | 'INFORMATIVO'
  informacionAdicional?: string
}

/**
 * Respuesta del endpoint de recepción (validarComprobante).
 * Estado RECIBIDA = el SRI aceptó el comprobante para procesamiento.
 * Estado DEVUELTA = el SRI rechazó el comprobante (ver mensajes para causa).
 */
export interface RespuestaRecepcion {
  estado: 'RECIBIDA' | 'DEVUELTA'
  claveAcceso?: string
  mensajes: MensajeSri[]
}

/**
 * Respuesta del endpoint de autorización (autorizacionComprobante).
 * Estado AUTORIZADO          = comprobante válido, incluye xmlAutorizado y numeroAutorizacion.
 * Estado NO AUTORIZADO       = rechazado definitivamente (ver mensajes).
 * Estado EN PROCESO          = el SRI aún no termina de procesar (reintenta más tarde).
 * Estado ANULADO             = el comprobante fue anulado vía portal SRI por el usuario.
 * Estado PENDIENTE_DE_ANULAR = el SRI tiene pendiente procesar la anulación (seguir pollando).
 */
export interface RespuestaAutorizacion {
  estado: 'AUTORIZADO' | 'NO AUTORIZADO' | 'EN PROCESO' | 'ANULADO' | 'PENDIENTE_DE_ANULAR'
  numeroAutorizacion?: string
  fechaAutorizacion?: string   // ISO 8601 string (el SRI devuelve con offset -05:00)
  ambiente?: string
  xmlAutorizado?: string       // XML completo con nodo <autorizacion> envolvente
  mensajes: MensajeSri[]
}

// ---------------------------------------------------------------------------
// Endpoints del SRI
// ---------------------------------------------------------------------------

/**
 * URLs SOAP del SRI para cada ambiente.
 * Fuente: Ficha técnica comprobantes electrónicos SRI (versión vigente).
 */
export const SRI_ENDPOINTS: Record<AmbienteSri, { recepcion: string; autorizacion: string }> = {
  PRUEBAS: {
    recepcion:    'https://celcer.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline',
    autorizacion: 'https://celcer.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline',
  },
  PRODUCCION: {
    recepcion:    'https://cel.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline',
    autorizacion: 'https://cel.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline',
  },
}

// ---------------------------------------------------------------------------
// Constructores de envelopes SOAP
// ---------------------------------------------------------------------------

/**
 * Construye el SOAP envelope para enviar el XML firmado al endpoint de recepción.
 *
 * El SRI espera el XML firmado codificado en Base64 dentro del tag <xml>.
 * La codificación Base64 es obligatoria para proteger los caracteres especiales
 * del XML firmado (tildes, ñ, comillas, ángulos) dentro del SOAP body.
 *
 * @param xmlFirmadoBase64 - XML con firma XAdES-BES, codificado en Base64
 */
export function buildReceptionEnvelope(xmlFirmadoBase64: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope
  xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:ec="http://ec.gob.sri.ws.recepcion">
  <soapenv:Header/>
  <soapenv:Body>
    <ec:validarComprobante>
      <xml>${xmlFirmadoBase64}</xml>
    </ec:validarComprobante>
  </soapenv:Body>
</soapenv:Envelope>`
}

/**
 * Construye el SOAP envelope para consultar el estado de autorización
 * de un comprobante por su clave de acceso (49 dígitos).
 *
 * @param claveAcceso - Clave de acceso del comprobante (49 dígitos)
 */
export function buildAuthorizationEnvelope(claveAcceso: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope
  xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:ec="http://ec.gob.sri.ws.autorizacion">
  <soapenv:Header/>
  <soapenv:Body>
    <ec:autorizacionComprobante>
      <claveAccesoComprobante>${claveAcceso}</claveAccesoComprobante>
    </ec:autorizacionComprobante>
  </soapenv:Body>
</soapenv:Envelope>`
}

/**
 * Construye el SOAP envelope para consultar en lote el estado de autorización
 * de múltiples comprobantes en una sola llamada.
 *
 * El SRI acepta las claves de acceso separadas por comas en un único string.
 * El SRI retorna las autorizaciones en el mismo orden que las claves enviadas.
 *
 * Fuente: AutorizacionComprobantesOffline WSDL — operación autorizacionComprobanteLote,
 * tipo autorizacionComprobanteLote { claveAccesoLote: xs:string }.
 *
 * @param claves - Array de claves de acceso (49 dígitos cada una). Mínimo 1.
 */
export function buildBatchAuthorizationEnvelope(claves: string[]): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope
  xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:ec="http://ec.gob.sri.ws.autorizacion">
  <soapenv:Header/>
  <soapenv:Body>
    <ec:autorizacionComprobanteLote>
      <claveAccesoLote>${claves.join(',')}</claveAccesoLote>
    </ec:autorizacionComprobanteLote>
  </soapenv:Body>
</soapenv:Envelope>`
}

// ---------------------------------------------------------------------------
// Transporte HTTP
// ---------------------------------------------------------------------------

/**
 * Ejecuta un POST SOAP al URL indicado y retorna el cuerpo de la respuesta
 * como string.
 *
 * Manejo de errores:
 * - Timeout controlado con AbortController (default 30 s).
 * - Lanza Error si el status HTTP != 200 (incluye el body en el mensaje
 *   para facilitar diagnóstico del error SOAP Fault).
 *
 * @param url        - Endpoint SOAP del SRI
 * @param soapBody   - Envelope SOAP completo como string
 * @param soapAction - Valor del header SOAPAction (sin comillas)
 * @param timeoutMs  - Timeout en milisegundos (default: 30_000)
 */
export async function sendSoapRequest(
  url: string,
  soapBody: string,
  soapAction: string,
  timeoutMs = 30_000,
): Promise<string> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/xml; charset=utf-8',
        'SOAPAction': soapAction,
      },
      body: soapBody,
      signal: controller.signal,
    })

    const responseBody = await response.text()

    if (!response.ok) {
      throw new Error(
        `SRI SOAP error HTTP ${response.status} [${soapAction}]: ${responseBody.slice(0, 500)}`,
      )
    }

    return responseBody
  } catch (err) {
    if (err instanceof Error && err.name === 'AbortError') {
      throw new Error(`SRI SOAP timeout (${timeoutMs}ms) [${soapAction}]`)
    }
    throw err
  } finally {
    clearTimeout(timer)
  }
}

// ---------------------------------------------------------------------------
// Helpers de extracción XML por texto (sin parser DOM)
// ---------------------------------------------------------------------------

/**
 * Extrae el contenido de texto del primer elemento con el tag indicado.
 * Busca `<tag>contenido</tag>`. Retorna null si no lo encuentra.
 *
 * Se usa extracción textual (no DOM parser) porque la estructura SOAP del SRI
 * es conocida y fija, y Deno Edge Runtime no incluye DOMParser nativo.
 */
function extractXmlValue(xml: string, tag: string): string | null {
  const openTag = `<${tag}>`
  const closeTag = `</${tag}>`
  const start = xml.indexOf(openTag)
  if (start === -1) return null
  const end = xml.indexOf(closeTag, start)
  if (end === -1) return null
  return xml.substring(start + openTag.length, end).trim()
}

/**
 * Extrae todos los valores de un tag repetido en el XML.
 * Útil para extraer múltiples bloques <mensaje>, <comprobante>, etc.
 */
function extractXmlValues(xml: string, tag: string): string[] {
  const results: string[] = []
  let searchFrom = 0
  const openTag = `<${tag}>`
  const closeTag = `</${tag}>`

  while (true) {
    const start = xml.indexOf(openTag, searchFrom)
    if (start === -1) break
    const end = xml.indexOf(closeTag, start)
    if (end === -1) break
    results.push(xml.substring(start + openTag.length, end).trim())
    searchFrom = end + closeTag.length
  }

  return results
}

/**
 * Extrae el contenido de un elemento que puede estar envuelto en CDATA.
 * Intenta primero `<tag><![CDATA[...]]>` y hace fallback a extracción simple.
 *
 * El SRI envuelve el XML del comprobante autorizado en CDATA:
 *   <comprobante><![CDATA[<?xml version="1.0"...]]></comprobante>
 */
function extractCdataContent(xml: string, tag: string): string | null {
  const cdataTag = `<${tag}><![CDATA[`
  const cdataEnd = ']]>'
  const start = xml.indexOf(cdataTag)

  if (start !== -1) {
    const contentStart = start + cdataTag.length
    const end = xml.indexOf(cdataEnd, contentStart)
    if (end !== -1) {
      return xml.substring(contentStart, end).trim()
    }
  }

  // Fallback: el SRI a veces omite el CDATA en algunos ambientes
  return extractXmlValue(xml, tag)
}

/**
 * Parsea los bloques <mensaje> dentro de una sección de mensajes SRI.
 * Cada bloque tiene: identificador, mensaje, tipo, informacionAdicional (opcional).
 */
function parseMensajesSri(xml: string): MensajeSri[] {
  const bloques = extractXmlValues(xml, 'mensaje')
  return bloques.map((bloque): MensajeSri => {
    const tipo = extractXmlValue(bloque, 'tipo') ?? 'INFORMATIVO'
    return {
      identificador: extractXmlValue(bloque, 'identificador') ?? '',
      mensaje: extractXmlValue(bloque, 'mensaje') ?? '',
      tipo: (tipo === 'ERROR' || tipo === 'ADVERTENCIA' || tipo === 'INFORMATIVO')
        ? tipo
        : 'INFORMATIVO',
      informacionAdicional: extractXmlValue(bloque, 'informacionAdicional') ?? undefined,
    }
  })
}

// ---------------------------------------------------------------------------
// Parsers de respuesta SOAP
// ---------------------------------------------------------------------------

/**
 * Parsea la respuesta XML del endpoint de recepción del SRI.
 *
 * Estructura esperada del body SOAP:
 * ```xml
 * <ns2:validarComprobanteResponse ...>
 *   <RespuestaRecepcionComprobante>
 *     <estado>RECIBIDA</estado>
 *     <comprobantes>
 *       <comprobante>
 *         <claveAcceso>...</claveAcceso>
 *         <mensajes>
 *           <mensaje>
 *             <identificador>35</identificador>
 *             <mensaje>CLAVE ACCESO REGISTRADA</mensaje>
 *             <tipo>INFORMATIVO</tipo>
 *             <informacionAdicional>...</informacionAdicional>
 *           </mensaje>
 *         </mensajes>
 *       </comprobante>
 *     </comprobantes>
 *   </RespuestaRecepcionComprobante>
 * </ns2:validarComprobanteResponse>
 * ```
 *
 * @param soapXml - Respuesta SOAP completa del SRI como string
 * @throws Error si no puede determinar el estado de la respuesta
 */
export function parseReceptionResponse(soapXml: string): RespuestaRecepcion {
  // Extraer estado principal de la recepción
  const estadoRaw = extractXmlValue(soapXml, 'estado')

  if (!estadoRaw) {
    // Puede ser un SOAP Fault — intentar extraer el faultstring
    const faultString = extractXmlValue(soapXml, 'faultstring')
    throw new Error(
      `Respuesta de recepción SRI sin estado. ${faultString ? `Fault: ${faultString}` : 'XML inesperado.'}`,
    )
  }

  const estado = estadoRaw.toUpperCase() as 'RECIBIDA' | 'DEVUELTA'

  // La claveAcceso se devuelve dentro del bloque <comprobante>
  const claveAcceso = extractXmlValue(soapXml, 'claveAcceso') ?? undefined

  // Mensajes del SRI (pueden estar en el comprobante o en la raíz)
  const mensajes = parseMensajesSri(soapXml)

  return { estado, claveAcceso, mensajes }
}

/**
 * Parsea la respuesta XML del endpoint de autorización del SRI.
 *
 * Estructura esperada:
 * ```xml
 * <RespuestaAutorizacionComprobante>
 *   <claveAccesoConsultada>...</claveAccesoConsultada>
 *   <numeroComprobantes>1</numeroComprobantes>
 *   <autorizaciones>
 *     <autorizacion>
 *       <estado>AUTORIZADO</estado>
 *       <numeroAutorizacion>...</numeroAutorizacion>
 *       <fechaAutorizacion>2024-01-15T10:30:00.000-05:00</fechaAutorizacion>
 *       <ambiente>PRODUCCION</ambiente>
 *       <comprobante><![CDATA[<?xml version="1.0"...]]></comprobante>
 *       <mensajes>...</mensajes>
 *     </autorizacion>
 *   </autorizaciones>
 * </RespuestaAutorizacionComprobante>
 * ```
 *
 * Nota: cuando el SRI aún procesa el comprobante, el bloque <autorizacion>
 * puede estar vacío o devolver estado "EN PROCESO".
 *
 * @param soapXml - Respuesta SOAP completa del SRI como string
 */
export function parseAuthorizationResponse(soapXml: string): RespuestaAutorizacion {
  // Buscar el bloque de la primera autorización
  const bloqueAutorizacion = extractXmlValue(soapXml, 'autorizacion')

  // Si no hay bloque de autorización, el comprobante puede estar en proceso
  // o nunca fue recibido
  if (!bloqueAutorizacion) {
    // Verificar si es un Fault
    const faultString = extractXmlValue(soapXml, 'faultstring')
    if (faultString) {
      throw new Error(`SRI SOAP Fault (autorización): ${faultString}`)
    }
    // Sin autorizaciones = EN PROCESO o clave no encontrada
    return { estado: 'EN PROCESO', mensajes: [] }
  }

  const estadoRaw = extractXmlValue(bloqueAutorizacion, 'estado') ?? ''
  let estado: RespuestaAutorizacion['estado']

  switch (estadoRaw.toUpperCase()) {
    case 'AUTORIZADO':
      estado = 'AUTORIZADO'
      break
    case 'NO AUTORIZADO':
      estado = 'NO AUTORIZADO'
      break
    case 'ANULADO':
      estado = 'ANULADO'
      break
    case 'PENDIENTE DE ANULAR':
      // El SRI puede devolver este estado con espacio; lo normalizamos con guion bajo
      estado = 'PENDIENTE_DE_ANULAR'
      break
    default:
      // Incluye 'EN PROCESO' y cualquier valor no reconocido
      estado = 'EN PROCESO'
  }

  const numeroAutorizacion = extractXmlValue(bloqueAutorizacion, 'numeroAutorizacion') ?? undefined
  const fechaAutorizacion  = extractXmlValue(bloqueAutorizacion, 'fechaAutorizacion') ?? undefined
  const ambiente           = extractXmlValue(bloqueAutorizacion, 'ambiente') ?? undefined

  // El comprobante autorizado viene en CDATA — contiene el XML completo con
  // nodo <autorizacion> y el comprobante original incrustado
  const xmlAutorizado = extractCdataContent(bloqueAutorizacion, 'comprobante') ?? undefined

  const mensajes = parseMensajesSri(bloqueAutorizacion)

  return {
    estado,
    numeroAutorizacion,
    fechaAutorizacion,
    ambiente,
    xmlAutorizado,
    mensajes,
  }
}

/**
 * Parsea la respuesta XML del endpoint de autorización en lote del SRI.
 *
 * Estructura esperada:
 * ```xml
 * <autorizacionComprobanteLoteResponse>
 *   <RespuestaAutorizacionLote>
 *     <claveAccesoLoteConsultada>key1,key2,...</claveAccesoLoteConsultada>
 *     <numeroComprobantesLote>2</numeroComprobantesLote>
 *     <autorizaciones>
 *       <autorizacion>...</autorizacion>   <!-- mismo schema que respuesta individual -->
 *       <autorizacion>...</autorizacion>
 *     </autorizaciones>
 *   </RespuestaAutorizacionLote>
 * </autorizacionComprobanteLoteResponse>
 * ```
 *
 * El SRI no incluye `claveAcceso` dentro de cada `<autorizacion>` del lote.
 * Las autorizaciones se empareja por posición con el array `clavesSolicitadas`.
 * Si el SRI retorna menos autorizaciones que claves solicitadas, las restantes
 * se marcan como EN PROCESO.
 *
 * @param soapXml         - Respuesta SOAP completa del SRI como string
 * @param clavesSolicitadas - Array de claves en el mismo orden enviado al SRI
 * @returns Map de claveAcceso → RespuestaAutorizacion para búsqueda O(1)
 */
export function parseBatchAuthorizationResponse(
  soapXml: string,
  clavesSolicitadas: string[],
): Map<string, RespuestaAutorizacion> {
  const result = new Map<string, RespuestaAutorizacion>()

  // Fault check
  const faultString = extractXmlValue(soapXml, 'faultstring')
  if (faultString) {
    throw new Error(`SRI SOAP Fault (autorizaciónLote): ${faultString}`)
  }

  // Extraer todos los bloques <autorizacion> en orden
  const bloques = extractXmlValues(soapXml, 'autorizacion')

  // Emparejar por posición con las claves solicitadas
  for (let i = 0; i < clavesSolicitadas.length; i++) {
    const claveAcceso = clavesSolicitadas[i]
    const bloque = bloques[i]

    if (!bloque) {
      // El SRI no devolvió autorización para esta clave → seguir reintentando
      result.set(claveAcceso, { estado: 'EN PROCESO', mensajes: [] })
      continue
    }

    const estadoRaw = extractXmlValue(bloque, 'estado') ?? ''
    let estado: RespuestaAutorizacion['estado']

    switch (estadoRaw.toUpperCase()) {
      case 'AUTORIZADO':        estado = 'AUTORIZADO';        break
      case 'NO AUTORIZADO':     estado = 'NO AUTORIZADO';     break
      case 'ANULADO':           estado = 'ANULADO';           break
      case 'PENDIENTE DE ANULAR':
        estado = 'PENDIENTE_DE_ANULAR'
        break
      default:
        estado = 'EN PROCESO'
    }

    result.set(claveAcceso, {
      estado,
      numeroAutorizacion: extractXmlValue(bloque, 'numeroAutorizacion') ?? undefined,
      fechaAutorizacion:  extractXmlValue(bloque, 'fechaAutorizacion')  ?? undefined,
      ambiente:           extractXmlValue(bloque, 'ambiente')            ?? undefined,
      xmlAutorizado:      extractCdataContent(bloque, 'comprobante')     ?? undefined,
      mensajes:           parseMensajesSri(bloque),
    })
  }

  return result
}

// ---------------------------------------------------------------------------
// Flujo completo: recepción + polling de autorización
// ---------------------------------------------------------------------------

/**
 * Envía el XML firmado al SRI (endpoint recepción) y retorna la respuesta.
 *
 * Este es el paso 1 del pipeline SRI. Tras recibir RECIBIDA, se debe
 * llamar a pollAuthorization con la claveAcceso para obtener la autorización.
 *
 * @param xmlFirmadoBase64 - XML con firma XAdES-BES codificado en Base64
 * @param ambiente         - Ambiente SRI (PRUEBAS o PRODUCCION)
 * @param timeoutMs        - Timeout HTTP (default: 30_000 ms)
 */
export async function enviarDocumento(
  xmlFirmadoBase64: string,
  ambiente: AmbienteSri,
  timeoutMs = 30_000,
): Promise<RespuestaRecepcion> {
  const envelope = buildReceptionEnvelope(xmlFirmadoBase64)
  const soapXml = await sendSoapRequest(
    SRI_ENDPOINTS[ambiente].recepcion,
    envelope,
    'validarComprobante',
    timeoutMs,
  )
  return parseReceptionResponse(soapXml)
}

/**
 * Consulta el estado de autorización de un comprobante por su clave de acceso.
 * Llama al endpoint de autorización una sola vez.
 *
 * Para reintentos automáticos usar `pollAuthorization`.
 *
 * @param claveAcceso - Clave de acceso del comprobante (49 dígitos)
 * @param ambiente    - Ambiente SRI
 * @param timeoutMs   - Timeout HTTP (default: 30_000 ms)
 */
export async function consultarAutorizacion(
  claveAcceso: string,
  ambiente: AmbienteSri,
  timeoutMs = 30_000,
): Promise<RespuestaAutorizacion> {
  const envelope = buildAuthorizationEnvelope(claveAcceso)
  const soapXml = await sendSoapRequest(
    SRI_ENDPOINTS[ambiente].autorizacion,
    envelope,
    'autorizacionComprobante',
    timeoutMs,
  )
  return parseAuthorizationResponse(soapXml)
}

/**
 * Consulta en lote el estado de autorización de múltiples comprobantes
 * en una sola llamada SOAP.
 *
 * Preferir esta función sobre múltiples llamadas a `consultarAutorizacion`
 * cuando se procesan lotes desde `poll-autorizacion` para reducir latencia
 * y carga sobre los servidores del SRI.
 *
 * Ejemplo de uso en poll-autorizacion:
 * ```ts
 * const resultados = await consultarAutorizacionLote(claves, ambiente)
 * for (const [clave, resp] of resultados) {
 *   if (resp.estado === 'AUTORIZADO') { ... }
 * }
 * ```
 *
 * @param claves    - Array de claves de acceso a consultar (máx. recomendado: 50)
 * @param ambiente  - Ambiente SRI
 * @param timeoutMs - Timeout HTTP (default: 30_000 ms)
 * @returns Map de claveAcceso → RespuestaAutorizacion
 */
export async function consultarAutorizacionLote(
  claves: string[],
  ambiente: AmbienteSri,
  timeoutMs = 30_000,
): Promise<Map<string, RespuestaAutorizacion>> {
  if (claves.length === 0) return new Map()

  const envelope = buildBatchAuthorizationEnvelope(claves)
  const soapXml = await sendSoapRequest(
    SRI_ENDPOINTS[ambiente].autorizacion,
    envelope,
    'autorizacionComprobanteLote',
    timeoutMs,
  )
  return parseBatchAuthorizationResponse(soapXml, claves)
}

/**
 * Polling de autorización con reintentos automáticos.
 *
 * Espera `delayMs` ms entre cada intento (excepto el primero).
 * Retorna inmediatamente si el estado es AUTORIZADO o NO AUTORIZADO.
 * Si agota los intentos con estado EN PROCESO, retorna ese último resultado.
 *
 * Uso típico en el pipeline SRI:
 *   1. enviarDocumento() → estado RECIBIDA
 *   2. pollAuthorization(claveAcceso, ambiente)  → estado AUTORIZADO
 *   3. Guardar xmlAutorizado en Storage y numeroAutorizacion en BD
 *
 * Para documentos que toman más tiempo (carga alta en SRI) se recomienda
 * usar la cola de reintentos de la tabla `cola_documentos_electronicos`
 * en lugar de aumentar maxAttempts aquí.
 *
 * @param claveAcceso - Clave de acceso del comprobante (49 dígitos)
 * @param ambiente    - Ambiente SRI
 * @param maxAttempts - Número máximo de intentos (default: 3)
 * @param delayMs     - Espera entre intentos en ms (default: 5_000)
 */
export async function pollAuthorization(
  claveAcceso: string,
  ambiente: AmbienteSri,
  maxAttempts = 3,
  delayMs = 5_000,
): Promise<RespuestaAutorizacion> {
  let lastResult: RespuestaAutorizacion = { estado: 'EN PROCESO', mensajes: [] }

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    // Esperar antes del 2do intento en adelante
    if (attempt > 0) {
      await new Promise<void>((resolve) => setTimeout(resolve, delayMs))
    }

    try {
      const envelope = buildAuthorizationEnvelope(claveAcceso)
      const soapXml = await sendSoapRequest(
        SRI_ENDPOINTS[ambiente].autorizacion,
        envelope,
        'autorizacionComprobante',
      )
      lastResult = parseAuthorizationResponse(soapXml)
    } catch (err) {
      // Error de red/timeout: loguear y continuar con el siguiente intento
      console.error(
        `[sri-soap] pollAuthorization intento ${attempt + 1}/${maxAttempts} falló:`,
        err instanceof Error ? err.message : err,
      )
      continue
    }

    // Salir si ya hay resolución definitiva.
    // EN PROCESO y PENDIENTE_DE_ANULAR son estados transitorios → seguir reintentando.
    if (lastResult.estado !== 'EN PROCESO' && lastResult.estado !== 'PENDIENTE_DE_ANULAR') {
      return lastResult
    }
  }

  // Retorna EN PROCESO si agotó los intentos — la cola reintentará luego
  return lastResult
}
