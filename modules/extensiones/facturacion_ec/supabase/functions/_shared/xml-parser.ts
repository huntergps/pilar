/**
 * PILAR ERP — Shared: xml-parser.ts
 *
 * Parsea el XML autorizado por el SRI Ecuador para extraer los datos necesarios
 * para generar el RIDE (Representación Impresa del Documento Electrónico).
 *
 * Documentos soportados:
 *   01 Factura, 03 Liquidación de Compra, 04 NC, 05 ND, 06 Guía Remisión, 07 Retención
 *
 * Implementación sin DOMParser — el Deno Edge Runtime no lo incluye.
 * Todo el parsing se realiza con indexOf, substring y regex sobre texto.
 *
 * Uso:
 *   import { parsearXmlAutorizado } from '../_shared/xml-parser.ts'
 *   const doc = parsearXmlAutorizado(xmlAutorizadoStr)
 *   if (doc.tipo === '01') {
 *     console.log(doc.info.importeTotal)
 *     console.log(doc.detalles[0].descripcion)
 *   }
 */

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

export interface AutorizacionSri {
  estado: string
  numeroAutorizacion: string
  fechaAutorizacion: string
  ambiente: string
}

export interface InfoTributaria {
  ambiente: string
  razonSocial: string
  nombreComercial: string
  ruc: string
  claveAcceso: string
  codDoc: string
  estab: string
  ptoEmi: string
  secuencial: string
  dirMatriz: string
  numeroDocumento: string
}

export interface TotalImpuesto {
  codigo: string
  codigoPorcentaje: string
  descripcion: string
  baseImponible: number
  valor: number
}

export interface Pago {
  formaPago: string
  descripcion: string
  total: number
  plazo?: number
  unidadTiempo?: string
}

export interface DetalleLinea {
  codigoPrincipal: string
  codigoAuxiliar?: string
  descripcion: string
  cantidad: number
  precioUnitario: number
  descuento: number
  precioTotalSinImpuesto: number
  impuestos: Array<{
    codigo: string
    codigoPorcentaje: string
    tarifa: number
    baseImponible: number
    valor: number
  }>
}

export interface DetalleRetencion {
  codigo: string
  codigoRetencion: string
  descripcion: string
  baseImponible: number
  porcentajeRetener: number
  valorRetenido: number
  codDocSustento: string
  numDocSustento: string
  fechaEmisionDocSustento: string
}

export interface CampoAdicional {
  nombre: string
  valor: string
}

export interface InfoFactura {
  fechaEmision: string
  dirEstablecimiento: string
  obligadoContabilidad: string
  tipoIdentificacionComprador: string
  razonSocialComprador: string
  identificacionComprador: string
  guiaRemision?: string
  totalSinImpuestos: number
  totalDescuento: number
  propina: number
  importeTotal: number
  moneda: string
  totalConImpuestos: TotalImpuesto[]
  pagos: Pago[]
}

export interface InfoNotaCredito {
  fechaEmision: string
  dirEstablecimiento: string
  tipoIdentificacionComprador: string
  razonSocialComprador: string
  identificacionComprador: string
  obligadoContabilidad: string
  codDocModificado: string
  numDocModificado: string
  fechaEmisionDocSustento: string
  totalSinImpuestos: number
  valorModificacion: number
  moneda: string
  totalConImpuestos: TotalImpuesto[]
  motivo: string
}

export interface InfoRetencion {
  fechaEmision: string
  dirEstablecimiento: string
  obligadoContabilidad: string
  tipoIdentificacionSujetoRetenido: string
  razonSocialSujetoRetenido: string
  identificacionSujetoRetenido: string
  periodoFiscal: string
}

export type DocumentoSriParseado =
  | { tipo: '01'; autorizacion: AutorizacionSri; infoTributaria: InfoTributaria; info: InfoFactura; detalles: DetalleLinea[]; infoAdicional: CampoAdicional[] }
  | { tipo: '03'; autorizacion: AutorizacionSri; infoTributaria: InfoTributaria; info: InfoFactura; detalles: DetalleLinea[]; infoAdicional: CampoAdicional[] }
  | { tipo: '04'; autorizacion: AutorizacionSri; infoTributaria: InfoTributaria; info: InfoNotaCredito; detalles: DetalleLinea[]; infoAdicional: CampoAdicional[] }
  | { tipo: '05'; autorizacion: AutorizacionSri; infoTributaria: InfoTributaria; info: InfoNotaCredito; detalles: DetalleLinea[]; infoAdicional: CampoAdicional[] }
  | { tipo: '06'; autorizacion: AutorizacionSri; infoTributaria: InfoTributaria; info: Record<string, string>; detalles: DetalleLinea[]; infoAdicional: CampoAdicional[] }
  | { tipo: '07'; autorizacion: AutorizacionSri; infoTributaria: InfoTributaria; info: InfoRetencion; detalles: DetalleRetencion[]; infoAdicional: CampoAdicional[] }

// ---------------------------------------------------------------------------
// Helpers de extracción de texto (sin DOMParser)
// ---------------------------------------------------------------------------

/**
 * Extrae el contenido de texto del primer elemento con el tag indicado.
 * Maneja tags con atributos: `<tag attr="val">contenido</tag>`.
 * Retorna '' si el tag no existe.
 */
export function extraerTexto(xml: string, tag: string): string {
  const openPattern = `<${tag}`
  const closeTag = `</${tag}>`
  const start = xml.indexOf(openPattern)
  if (start === -1) return ''
  const tagEnd = xml.indexOf('>', start)
  if (tagEnd === -1) return ''
  // Self-closing tag: <tag ... />
  if (xml[tagEnd - 1] === '/') return ''
  const end = xml.indexOf(closeTag, tagEnd)
  if (end === -1) return ''
  return xml.substring(tagEnd + 1, end).trim()
}

/**
 * Extrae el contenido del primer elemento con el tag indicado.
 * Retorna undefined si el tag no existe en el XML.
 */
export function extraerTextoOpcional(xml: string, tag: string): string | undefined {
  const openPattern = `<${tag}`
  const start = xml.indexOf(openPattern)
  if (start === -1) return undefined
  return extraerTexto(xml, tag)
}

/**
 * Retorna todos los bloques `<tag>...</tag>` encontrados en el XML,
 * incluyendo el tag de apertura y cierre. Útil para iterar elementos repetidos.
 */
export function extraerBloques(xml: string, tag: string): string[] {
  const results: string[] = []
  let searchFrom = 0
  const openPattern = `<${tag}`
  const closeTag = `</${tag}>`

  while (true) {
    const startTag = xml.indexOf(openPattern, searchFrom)
    if (startTag === -1) break
    const end = xml.indexOf(closeTag, startTag)
    if (end === -1) break
    results.push(xml.substring(startTag, end + closeTag.length))
    searchFrom = end + closeTag.length
  }

  return results
}

/**
 * Extrae el valor de un atributo de un tag XML.
 * Por ejemplo, `nombre` en `<campoAdicional nombre="Correo">`.
 * Retorna '' si el atributo no existe.
 */
export function extraerAtributo(xml: string, tag: string, attr: string): string {
  const openPattern = `<${tag}`
  const start = xml.indexOf(openPattern)
  if (start === -1) return ''
  const tagEnd = xml.indexOf('>', start)
  if (tagEnd === -1) return ''
  const tagDecl = xml.substring(start, tagEnd + 1)

  // Buscar attr="valor" o attr='valor'
  const attrPatternDouble = `${attr}="`
  const attrPatternSingle = `${attr}='`

  let attrStart = tagDecl.indexOf(attrPatternDouble)
  if (attrStart !== -1) {
    const valueStart = attrStart + attrPatternDouble.length
    const valueEnd = tagDecl.indexOf('"', valueStart)
    if (valueEnd !== -1) return tagDecl.substring(valueStart, valueEnd)
  }

  attrStart = tagDecl.indexOf(attrPatternSingle)
  if (attrStart !== -1) {
    const valueStart = attrStart + attrPatternSingle.length
    const valueEnd = tagDecl.indexOf("'", valueStart)
    if (valueEnd !== -1) return tagDecl.substring(valueStart, valueEnd)
  }

  return ''
}

/**
 * Convierte un string numérico a number. Retorna 0 si la conversión falla.
 */
export function parsearDecimal(s: string): number {
  const n = parseFloat(s)
  return isNaN(n) ? 0 : n
}

/**
 * Extrae el contenido CDATA del tag indicado.
 * Intenta `<tag><![CDATA[...]]>` primero y hace fallback a extracción simple.
 */
function extraerCdata(xml: string, tag: string): string {
  const cdataOpen = `<${tag}><![CDATA[`
  const cdataClose = ']]>'
  const start = xml.indexOf(cdataOpen)

  if (start !== -1) {
    const contentStart = start + cdataOpen.length
    const end = xml.indexOf(cdataClose, contentStart)
    if (end !== -1) return xml.substring(contentStart, end).trim()
  }

  // Fallback: sin CDATA (algunos ambientes lo omiten)
  return extraerTexto(xml, tag)
}

// ---------------------------------------------------------------------------
// Catálogos y helpers de descripción
// ---------------------------------------------------------------------------

/**
 * Formatea el número de documento en el formato `001-001-000000001`.
 */
export function formatearNumeroDocumento(estab: string, ptoEmi: string, sec: string): string {
  return `${estab}-${ptoEmi}-${sec}`
}

/**
 * Retorna el nombre del tipo de documento según el código SRI.
 */
export function descripcionTipoDoc(codDoc: string): string {
  const catalogo: Record<string, string> = {
    '01': 'FACTURA',
    '03': 'LIQUIDACIÓN DE COMPRA',
    '04': 'NOTA DE CRÉDITO',
    '05': 'NOTA DE DÉBITO',
    '06': 'GUÍA DE REMISIÓN',
    '07': 'COMPROBANTE DE RETENCIÓN',
  }
  return catalogo[codDoc] ?? `DOCUMENTO ${codDoc}`
}

/**
 * Retorna la descripción del impuesto según código y código de porcentaje SRI.
 *
 * Códigos de impuesto:
 *   2 = IVA, 3 = ICE, 5 = IRBPNR
 *
 * Códigos de porcentaje IVA (vigentes Ecuador 2024+):
 *   0 = IVA 0%, 4 = IVA 15%, 5 = IVA 5%, 6 = NO OBJETO IVA, 7 = EXENTO IVA
 *
 * Compatibilidad esquemas anteriores:
 *   2 = IVA 12% (código porcentaje antiguo, ya no vigente pero puede aparecer en docs históricos)
 */
export function descripcionTotalImpuesto(codigo: string, codigoPorcentaje: string): string {
  if (codigo === '2') {
    const ivaMap: Record<string, string> = {
      '0': 'IVA 0%',
      '2': 'IVA 12%',
      '3': 'IVA 14%',
      '4': 'IVA 15%',
      '5': 'IVA 5%',
      '6': 'NO OBJETO IVA',
      '7': 'EXENTO IVA',
    }
    return ivaMap[codigoPorcentaje] ?? `IVA (${codigoPorcentaje})`
  }
  if (codigo === '3') return 'ICE'
  if (codigo === '5') return 'IRBPNR'
  return `IMPUESTO ${codigo}`
}

/**
 * Retorna la descripción de la forma de pago según el catálogo SRI Ecuador.
 */
export function descripcionFormaPago(codigoFormaPago: string): string {
  const catalogo: Record<string, string> = {
    '01': 'SIN UTILIZACIÓN DEL SISTEMA FINANCIERO',
    '15': 'COMPENSACIÓN DE DEUDAS',
    '16': 'TARJETA DE DÉBITO',
    '17': 'DINERO ELECTRÓNICO',
    '18': 'TARJETA PREPAGO',
    '19': 'TARJETA DE CRÉDITO',
    '20': 'OTROS CON UTILIZACIÓN DEL SISTEMA FINANCIERO',
    '21': 'ENDOSO DE TÍTULOS',
  }
  return catalogo[codigoFormaPago] ?? `FORMA PAGO ${codigoFormaPago}`
}

/**
 * Retorna la descripción del tipo de identificación según catálogo SRI.
 */
export function descripcionTipoId(codigo: string): string {
  const catalogo: Record<string, string> = {
    '04': 'RUC',
    '05': 'CEDULA',
    '06': 'PASAPORTE',
    '07': 'CONSUMIDOR FINAL',
    '08': 'IDENTIFICACION DEL EXTERIOR',
  }
  return catalogo[codigo] ?? `TIPO ID ${codigo}`
}

// ---------------------------------------------------------------------------
// Parsers de bloques específicos
// ---------------------------------------------------------------------------

/**
 * Parsea el bloque `<autorizacion>` del XML externo del SRI.
 * Este bloque envuelve el comprobante autorizado y contiene el número de autorización.
 */
function parsearAutorizacion(xml: string): AutorizacionSri {
  return {
    estado:               extraerTexto(xml, 'estado'),
    numeroAutorizacion:   extraerTexto(xml, 'numeroAutorizacion'),
    fechaAutorizacion:    extraerTexto(xml, 'fechaAutorizacion'),
    ambiente:             extraerTexto(xml, 'ambiente'),
  }
}

/**
 * Parsea el bloque `<infoTributaria>` presente en todos los comprobantes SRI.
 * El `nombreComercial` usa `razonSocial` como fallback cuando está vacío.
 */
function parsearInfoTributaria(comprobante: string): InfoTributaria {
  const bloque = extraerBloques(comprobante, 'infoTributaria')[0] ?? comprobante
  const razonSocial       = extraerTexto(bloque, 'razonSocial')
  const nombreComercialRaw = extraerTexto(bloque, 'nombreComercial')
  const estab             = extraerTexto(bloque, 'estab')
  const ptoEmi            = extraerTexto(bloque, 'ptoEmi')
  const secuencial        = extraerTexto(bloque, 'secuencial')

  return {
    ambiente:         extraerTexto(bloque, 'ambiente'),
    razonSocial,
    nombreComercial:  nombreComercialRaw || razonSocial,
    ruc:              extraerTexto(bloque, 'ruc'),
    claveAcceso:      extraerTexto(bloque, 'claveAcceso'),
    codDoc:           extraerTexto(bloque, 'codDoc'),
    estab,
    ptoEmi,
    secuencial,
    dirMatriz:        extraerTexto(bloque, 'dirMatriz'),
    numeroDocumento:  formatearNumeroDocumento(estab, ptoEmi, secuencial),
  }
}

/**
 * Parsea los bloques `<totalImpuesto>` dentro de `<totalConImpuestos>`.
 */
function parsearTotalConImpuestos(xml: string): TotalImpuesto[] {
  const bloqueTotales = extraerBloques(xml, 'totalConImpuestos')[0] ?? ''
  return extraerBloques(bloqueTotales, 'totalImpuesto').map((bloque): TotalImpuesto => {
    const codigo             = extraerTexto(bloque, 'codigo')
    const codigoPorcentaje   = extraerTexto(bloque, 'codigoPorcentaje')
    return {
      codigo,
      codigoPorcentaje,
      descripcion:    descripcionTotalImpuesto(codigo, codigoPorcentaje),
      baseImponible:  parsearDecimal(extraerTexto(bloque, 'baseImponible')),
      valor:          parsearDecimal(extraerTexto(bloque, 'valor')),
    }
  })
}

/**
 * Parsea los bloques `<pago>` dentro de `<pagos>`.
 */
function parsearPagos(xml: string): Pago[] {
  const bloquePagos = extraerBloques(xml, 'pagos')[0] ?? ''
  return extraerBloques(bloquePagos, 'pago').map((bloque): Pago => {
    const formaPago    = extraerTexto(bloque, 'formaPago')
    const plazoStr     = extraerTextoOpcional(bloque, 'plazo')
    const unidadTiempo = extraerTextoOpcional(bloque, 'unidadTiempo')
    return {
      formaPago,
      descripcion:  descripcionFormaPago(formaPago),
      total:        parsearDecimal(extraerTexto(bloque, 'total')),
      plazo:        plazoStr !== undefined ? parsearDecimal(plazoStr) : undefined,
      unidadTiempo: unidadTiempo || undefined,
    }
  })
}

/**
 * Parsea los impuestos de una línea de detalle `<impuestos><impuesto>...</impuesto></impuestos>`.
 */
function parsearImpuestosDetalle(bloqueDetalle: string): DetalleLinea['impuestos'] {
  const bloqueImpuestos = extraerBloques(bloqueDetalle, 'impuestos')[0] ?? ''
  return extraerBloques(bloqueImpuestos, 'impuesto').map((bloque) => ({
    codigo:           extraerTexto(bloque, 'codigo'),
    codigoPorcentaje: extraerTexto(bloque, 'codigoPorcentaje'),
    tarifa:           parsearDecimal(extraerTexto(bloque, 'tarifa')),
    baseImponible:    parsearDecimal(extraerTexto(bloque, 'baseImponible')),
    valor:            parsearDecimal(extraerTexto(bloque, 'valor')),
  }))
}

/**
 * Parsea los bloques `<detalle>` dentro de `<detalles>`.
 * Funciona para factura (01), liquidación de compra (03), nota de crédito (04) y nota de débito (05).
 */
function parsearDetalles(comprobante: string): DetalleLinea[] {
  // NC puede usar <motivos><motivo> en lugar de <detalles><detalle>
  // Intentamos <detalles> primero y hacemos fallback a <motivos>
  let bloqueContenedor = extraerBloques(comprobante, 'detalles')[0]
  let tagItem = 'detalle'

  if (!bloqueContenedor) {
    bloqueContenedor = extraerBloques(comprobante, 'motivos')[0] ?? ''
    tagItem = 'motivo'
  }

  return extraerBloques(bloqueContenedor, tagItem).map((bloque): DetalleLinea => {
    const codigoAuxiliar = extraerTextoOpcional(bloque, 'codigoAuxiliar')
    return {
      codigoPrincipal:          extraerTexto(bloque, 'codigoPrincipal'),
      codigoAuxiliar:           codigoAuxiliar || undefined,
      descripcion:              extraerTexto(bloque, 'descripcion'),
      cantidad:                 parsearDecimal(extraerTexto(bloque, 'cantidad')),
      precioUnitario:           parsearDecimal(extraerTexto(bloque, 'precioUnitario')),
      descuento:                parsearDecimal(extraerTexto(bloque, 'descuento')),
      precioTotalSinImpuesto:   parsearDecimal(extraerTexto(bloque, 'precioTotalSinImpuesto')),
      impuestos:                parsearImpuestosDetalle(bloque),
    }
  })
}

/**
 * Parsea los bloques `<impuesto>` de una retención (07).
 * La estructura es distinta a los impuestos de detalle — tiene `codigoRetencion`,
 * `porcentajeRetener`, `valorRetenido`, `codDocSustento`, `numDocSustento`.
 */
function parsearDetallesRetencion(comprobante: string): DetalleRetencion[] {
  const bloqueImpuestos = extraerBloques(comprobante, 'impuestos')[0] ?? ''
  return extraerBloques(bloqueImpuestos, 'impuesto').map((bloque): DetalleRetencion => {
    const codigo          = extraerTexto(bloque, 'codigo')
    const codigoRetencion = extraerTexto(bloque, 'codigoRetencion')
    return {
      codigo,
      codigoRetencion,
      descripcion:                descripcionTipoImpuestoRetencion(codigo, codigoRetencion),
      baseImponible:              parsearDecimal(extraerTexto(bloque, 'baseImponible')),
      porcentajeRetener:          parsearDecimal(extraerTexto(bloque, 'porcentajeRetener')),
      valorRetenido:              parsearDecimal(extraerTexto(bloque, 'valorRetenido')),
      codDocSustento:             extraerTexto(bloque, 'codDocSustento'),
      numDocSustento:             extraerTexto(bloque, 'numDocSustento'),
      fechaEmisionDocSustento:    extraerTexto(bloque, 'fechaEmisionDocSustento'),
    }
  })
}

/**
 * Retorna la descripción del tipo de retención.
 * Código 1 = IR (Impuesto a la Renta), código 2 = IVA.
 * El `codigoRetencion` identifica el porcentaje específico (303, 312, etc.).
 */
function descripcionTipoImpuestoRetencion(codigo: string, codigoRetencion: string): string {
  const prefijo = codigo === '1' ? 'IR' : codigo === '2' ? 'IVA' : `IMP ${codigo}`
  return `${prefijo} - ${codigoRetencion}`
}

/**
 * Parsea los bloques `<campoAdicional nombre="...">valor</campoAdicional>`
 * del elemento `<infoAdicional>` presente en todos los comprobantes (opcional).
 */
function parsearInfoAdicional(comprobante: string): CampoAdicional[] {
  const bloqueInfo = extraerBloques(comprobante, 'infoAdicional')[0] ?? ''
  if (!bloqueInfo) return []

  return extraerBloques(bloqueInfo, 'campoAdicional').map((bloque): CampoAdicional => ({
    nombre: extraerAtributo(bloque, 'campoAdicional', 'nombre'),
    valor:  extraerTexto(bloque, 'campoAdicional'),
  }))
}

// ---------------------------------------------------------------------------
// Parsers por tipo de documento
// ---------------------------------------------------------------------------

/**
 * Parsea `<infoFactura>` (tipo 01) o `<infoLiquidacion>` (tipo 03).
 * Ambos tienen la misma estructura de campos.
 */
function parsearInfoFactura(comprobante: string, codDoc: string): InfoFactura {
  const tagInfo = codDoc === '03' ? 'infoLiquidacionCompra' : 'infoFactura'
  const bloque  = extraerBloques(comprobante, tagInfo)[0] ?? comprobante

  return {
    fechaEmision:                   extraerTexto(bloque, 'fechaEmision'),
    dirEstablecimiento:             extraerTexto(bloque, 'dirEstablecimiento'),
    obligadoContabilidad:           extraerTexto(bloque, 'obligadoContabilidad'),
    tipoIdentificacionComprador:    extraerTexto(bloque, 'tipoIdentificacionComprador'),
    razonSocialComprador:           extraerTexto(bloque, 'razonSocialComprador'),
    identificacionComprador:        extraerTexto(bloque, 'identificacionComprador'),
    guiaRemision:                   extraerTextoOpcional(bloque, 'guiaRemision') || undefined,
    totalSinImpuestos:              parsearDecimal(extraerTexto(bloque, 'totalSinImpuestos')),
    totalDescuento:                 parsearDecimal(extraerTexto(bloque, 'totalDescuento')),
    propina:                        parsearDecimal(extraerTexto(bloque, 'propina')),
    importeTotal:                   parsearDecimal(extraerTexto(bloque, 'importeTotal')),
    moneda:                         extraerTexto(bloque, 'moneda') || 'DOLAR',
    totalConImpuestos:              parsearTotalConImpuestos(bloque),
    pagos:                          parsearPagos(bloque),
  }
}

/**
 * Parsea `<infoNotaCredito>` (tipo 04) o `<infoNotaDebito>` (tipo 05).
 */
function parsearInfoNotaCredito(comprobante: string, codDoc: string): InfoNotaCredito {
  const tagInfo = codDoc === '05' ? 'infoNotaDebito' : 'infoNotaCredito'
  const bloque  = extraerBloques(comprobante, tagInfo)[0] ?? comprobante

  return {
    fechaEmision:               extraerTexto(bloque, 'fechaEmision'),
    dirEstablecimiento:         extraerTexto(bloque, 'dirEstablecimiento'),
    tipoIdentificacionComprador: extraerTexto(bloque, 'tipoIdentificacionComprador'),
    razonSocialComprador:       extraerTexto(bloque, 'razonSocialComprador'),
    identificacionComprador:    extraerTexto(bloque, 'identificacionComprador'),
    obligadoContabilidad:       extraerTexto(bloque, 'obligadoContabilidad'),
    codDocModificado:           extraerTexto(bloque, 'codDocModificado'),
    numDocModificado:           extraerTexto(bloque, 'numDocModificado'),
    fechaEmisionDocSustento:    extraerTexto(bloque, 'fechaEmisionDocSustento'),
    totalSinImpuestos:          parsearDecimal(extraerTexto(bloque, 'totalSinImpuestos')),
    valorModificacion:          parsearDecimal(extraerTexto(bloque, 'valorModificacion')),
    moneda:                     extraerTexto(bloque, 'moneda') || 'DOLAR',
    totalConImpuestos:          parsearTotalConImpuestos(bloque),
    motivo:                     extraerTexto(bloque, 'motivo'),
  }
}

/**
 * Parsea `<infoGuiaRemision>` (tipo 06) como mapa genérico de campos.
 * La guía de remisión tiene destinatarios en lugar de detalles — la extracción
 * completa de destinatarios se deja al consumer de este parser si la necesita.
 */
function parsearInfoGuiaRemision(comprobante: string): Record<string, string> {
  const bloque = extraerBloques(comprobante, 'infoGuiaRemision')[0] ?? ''
  if (!bloque) return {}

  const campos = [
    'dirPartida',
    'razonSocialTransportista',
    'tipoIdentificacionTransportista',
    'rucTransportista',
    'obligadoContabilidad',
    'fechaIniTransporte',
    'fechaFinTransporte',
    'placa',
  ]

  const result: Record<string, string> = {}
  for (const campo of campos) {
    const valor = extraerTexto(bloque, campo)
    if (valor) result[campo] = valor
  }
  return result
}

/**
 * Parsea `<infoCompRetencion>` (tipo 07).
 */
function parsearInfoRetencion(comprobante: string): InfoRetencion {
  const bloque = extraerBloques(comprobante, 'infoCompRetencion')[0] ?? comprobante

  return {
    fechaEmision:                   extraerTexto(bloque, 'fechaEmision'),
    dirEstablecimiento:             extraerTexto(bloque, 'dirEstablecimiento'),
    obligadoContabilidad:           extraerTexto(bloque, 'obligadoContabilidad'),
    tipoIdentificacionSujetoRetenido: extraerTexto(bloque, 'tipoIdentificacionSujetoRetenido'),
    razonSocialSujetoRetenido:      extraerTexto(bloque, 'razonSocialSujetoRetenido'),
    identificacionSujetoRetenido:   extraerTexto(bloque, 'identificacionSujetoRetenido'),
    periodoFiscal:                  extraerTexto(bloque, 'periodoFiscal'),
  }
}

// ---------------------------------------------------------------------------
// Función principal
// ---------------------------------------------------------------------------

/**
 * Parsea el XML autorizado completo del SRI y retorna un `DocumentoSriParseado`
 * con tipo discriminado según `codDoc`.
 *
 * Flujo interno:
 *   1. Extrae el bloque `<autorizacion>` del XML externo
 *   2. Extrae los metadatos de autorización (estado, numeroAutorizacion, etc.)
 *   3. Extrae el comprobante del CDATA de `<comprobante>`
 *   4. Parsea `<infoTributaria>` del comprobante
 *   5. Determina el tipo por `codDoc`
 *   6. Extrae la info específica del tipo (infoFactura, infoNotaCredito, etc.)
 *   7. Extrae los detalles o retenciones según el tipo
 *   8. Extrae `<infoAdicional>` (campos extra como email, teléfono, dirección)
 *   9. Retorna el objeto tipado con la unión discriminada
 *
 * @param xmlAutorizado - XML completo con el nodo `<autorizacion>` envolvente
 * @throws Error si el `codDoc` no es reconocido o si el XML no tiene la estructura esperada
 */
export function parsearXmlAutorizado(xmlAutorizado: string): DocumentoSriParseado {
  // Paso 1-2: Extraer y parsear el bloque de autorización
  const bloqueAutorizacion = extraerBloques(xmlAutorizado, 'autorizacion')[0] ?? xmlAutorizado
  const autorizacion = parsearAutorizacion(bloqueAutorizacion)

  // Paso 3: Extraer el comprobante desde el CDATA
  const comprobante = extraerCdata(bloqueAutorizacion, 'comprobante')
  if (!comprobante) {
    throw new Error('XML autorizado no contiene bloque <comprobante> ni CDATA válido')
  }

  // Paso 4: Parsear infoTributaria (común a todos los tipos)
  const infoTributaria = parsearInfoTributaria(comprobante)

  // Paso 5: Determinar tipo por codDoc
  const { codDoc } = infoTributaria

  // Paso 6-9: Extraer info específica, detalles e infoAdicional según tipo
  const infoAdicional = parsearInfoAdicional(comprobante)

  switch (codDoc) {
    case '01':
    case '03':
      return {
        tipo: codDoc,
        autorizacion,
        infoTributaria,
        info: parsearInfoFactura(comprobante, codDoc),
        detalles: parsearDetalles(comprobante),
        infoAdicional,
      }

    case '04':
    case '05':
      return {
        tipo: codDoc,
        autorizacion,
        infoTributaria,
        info: parsearInfoNotaCredito(comprobante, codDoc),
        detalles: parsearDetalles(comprobante),
        infoAdicional,
      }

    case '06':
      return {
        tipo: '06',
        autorizacion,
        infoTributaria,
        info: parsearInfoGuiaRemision(comprobante),
        detalles: parsearDetalles(comprobante),
        infoAdicional,
      }

    case '07':
      return {
        tipo: '07',
        autorizacion,
        infoTributaria,
        info: parsearInfoRetencion(comprobante),
        detalles: parsearDetallesRetencion(comprobante),
        infoAdicional,
      }

    default:
      throw new Error(
        `codDoc '${codDoc}' no reconocido. Tipos válidos: 01, 03, 04, 05, 06, 07`,
      )
  }
}
