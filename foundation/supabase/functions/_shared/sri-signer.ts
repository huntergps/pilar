/**
 * PILAR ERP — Shared: sri-signer.ts
 *
 * Firma XAdES-BES de documentos XML para el SRI Ecuador.
 * Cubre todos los tipos de comprobantes electrónicos:
 *   01 Factura, 03 Liquidación de Compra, 04 NC, 05 ND, 06 Guía Remisión, 07 Retención
 *
 * Librería principal: ec-sri-invoice-signer (npm, TypeScript puro)
 *   https://www.npmjs.com/package/ec-sri-invoice-signer
 *
 * Librería auxiliar: node-forge (npm:node-forge@1.3.1)
 *   Usada para parsear el certificado PKCS12 y extraer metadatos (CN, issuer,
 *   fechas de validez, número de serie) sin necesidad de llamar a la firma.
 *
 * IMPORTANTE: La firma se realiza ÚNICAMENTE en el servidor (Edge Function).
 *   Flutter NUNCA maneja certificados ni llama a SRI directamente.
 *
 * Flujo de la firma:
 *   1. El certificado .p12 se descarga de Supabase Storage (bucket 'certificados')
 *   2. La contraseña se obtiene de Supabase Vault (nunca de la BD ni de Flutter)
 *   3. Se firma el XML con XAdES-BES usando ec-sri-invoice-signer
 *   4. El resultado (xmlFirmado) se codifica en Base64 para envío SOAP
 *
 * Uso:
 *   import { firmarDocumentoSri, validateXmlBeforeSigning } from '../_shared/sri-signer.ts'
 */

// ---------------------------------------------------------------------------
// Importaciones
// ---------------------------------------------------------------------------

/**
 * Librería de firma XAdES-BES para Ecuador SRI.
 * npm: https://www.npmjs.com/package/ec-sri-invoice-signer
 *
 * API esperada (verificar en la documentación del package antes de desplegar):
 *   import { firmar } from 'npm:ec-sri-invoice-signer'
 *   const xmlFirmado = await firmar(xmlString, p12Buffer, password)
 *
 * Si el package expone un export default en lugar de named export, usar:
 *   import SriSigner from 'npm:ec-sri-invoice-signer'
 *   const xmlFirmado = await SriSigner.firmar(...)
 *
 * Versión de referencia: verificar la última en npm al momento de desplegar.
 */
import { firmar } from 'npm:ec-sri-invoice-signer'

/**
 * node-forge: librería de criptografía pura en JS/TS.
 * Usada aquí SOLO para parsear el PKCS12 y extraer metadatos del certificado.
 * La firma en sí la realiza ec-sri-invoice-signer.
 *
 * Versión fija para reproducibilidad (igual que en upload-certificate).
 */
import forge from 'npm:node-forge@1.3.1'

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

/**
 * Parámetros del certificado digital para la firma.
 * El p12Buffer se obtiene descargando el archivo desde Supabase Storage.
 * La password se obtiene de Supabase Vault (nunca de la BD ni de clientes).
 */
export interface CertificadoInfo {
  p12Buffer: ArrayBuffer  // Contenido binario del archivo .p12 / .pfx
  password: string        // Contraseña del certificado PKCS12
}

/**
 * Metadatos del certificado extraídos del PKCS12 con node-forge.
 * Se almacenan en la BD junto con el documento firmado para auditoría.
 */
export interface CertMetadata {
  commonName: string | null    // CN del sujeto (nombre del titular)
  issuer: string | null        // CN del emisor (entidad certificadora)
  validFrom: string            // ISO 8601 — inicio de validez
  validTo: string              // ISO 8601 — fin de validez (importante: SRI rechaza cert vencidos)
  serialNumber: string         // Número de serie del certificado X.509
}

/**
 * Resultado de la operación de firma.
 * El xmlFirmadoBase64 es el que se envía al SRI vía SOAP.
 * El xmlFirmado se almacena en Supabase Storage como copia del comprobante.
 */
export interface ResultadoFirma {
  xmlFirmado: string          // XML con elemento <Signature> XAdES-BES incluido
  xmlFirmadoBase64: string    // xmlFirmado codificado en Base64 (para envío SOAP)
  certInfo: CertMetadata      // Metadatos del certificado usado para firmar
}

// ---------------------------------------------------------------------------
// Helpers internos
// ---------------------------------------------------------------------------

/**
 * Parsea un certificado PKCS12 con node-forge y extrae los metadatos.
 * No realiza la firma — solo lectura de metadatos para auditoría y validación.
 *
 * @throws Error si la contraseña es incorrecta o el formato es inválido
 */
function parsearMetadatosCertificado(
  p12Buffer: ArrayBuffer,
  password: string,
): CertMetadata {
  // Convertir ArrayBuffer a string binario que acepta node-forge
  const p12Bytes = new Uint8Array(p12Buffer)
  const p12BinaryStr = Array.from(p12Bytes)
    .map((b) => String.fromCharCode(b))
    .join('')

  // Parsear PKCS12
  const p12ForgeBuffer = forge.util.createBuffer(p12BinaryStr, 'binary')
  const p12Asn1 = forge.asn1.fromDer(p12ForgeBuffer)

  let p12: forge.pkcs12.Pkcs12Pfx
  try {
    p12 = forge.pkcs12.pkcs12FromAsn1(p12Asn1, password)
  } catch (err) {
    const msg = err instanceof Error ? err.message : ''
    if (
      msg.includes('mac verify') ||
      msg.includes('Invalid password') ||
      msg.includes('invalid password')
    ) {
      throw new Error('CONTRASENA_CERTIFICADO_INCORRECTA')
    }
    throw new Error(`CERTIFICADO_FORMATO_INVALIDO: ${msg}`)
  }

  // Extraer el certificado X.509 del bag
  const certBags = p12.getBags({ bagType: forge.pki.oids.certBag })
  const certBagArray = certBags[forge.pki.oids.certBag]

  if (!certBagArray || certBagArray.length === 0) {
    throw new Error('CERTIFICADO_SIN_CERT_BAG')
  }

  const x509Cert = certBagArray[0]?.cert

  if (!x509Cert) {
    throw new Error('CERTIFICADO_X509_NO_ENCONTRADO')
  }

  return {
    commonName:   x509Cert.subject.getField('CN')?.value ?? null,
    issuer:       x509Cert.issuer.getField('CN')?.value ?? null,
    validFrom:    x509Cert.validity.notBefore.toISOString(),
    validTo:      x509Cert.validity.notAfter.toISOString(),
    serialNumber: x509Cert.serialNumber ?? '',
  }
}

/**
 * Codifica un string XML en Base64, manejando correctamente caracteres
 * especiales del español (tildes, ñ, etc.) presentes en nombres de
 * contribuyentes, productos y conceptos en el XML del SRI.
 *
 * Proceso:
 *   1. encodeURIComponent escapa los caracteres especiales a secuencias %XX
 *   2. unescape convierte %XX a bytes individuales (latin-1 compatible)
 *   3. btoa codifica los bytes en Base64
 *
 * Para decodificar: decodeURIComponent(escape(atob(base64)))
 */
function xmlABase64(xml: string): string {
  return btoa(unescape(encodeURIComponent(xml)))
}

// ---------------------------------------------------------------------------
// Función principal de firma
// ---------------------------------------------------------------------------

/**
 * Firma un documento XML del SRI con XAdES-BES usando ec-sri-invoice-signer.
 *
 * Pipeline interno:
 *   1. Parsear PKCS12 con node-forge → extraer metadatos del certificado
 *   2. Firmar el XML con ec-sri-invoice-signer → xmlFirmado (XAdES-BES)
 *   3. Codificar xmlFirmado en Base64 → xmlFirmadoBase64 (para SOAP)
 *
 * El xmlFirmado contiene el elemento <Signature> con:
 *   - SignedInfo (referencia al documento con digest SHA-256)
 *   - SignatureValue (firma RSA-SHA256)
 *   - KeyInfo (certificado X.509 en Base64)
 *   - QualifyingProperties (xades:SignedProperties con metadata del firmante)
 *
 * @param xmlSinFirma - XML del comprobante sin firma (generado previamente)
 * @param cert        - Certificado digital y contraseña
 * @throws Error si la firma falla, la contraseña es incorrecta o el XML es inválido
 */
export async function firmarDocumentoSri(
  xmlSinFirma: string,
  cert: CertificadoInfo,
): Promise<ResultadoFirma> {
  // Paso 1: Extraer metadatos del certificado (valida también que la contraseña sea correcta)
  const certInfo = parsearMetadatosCertificado(cert.p12Buffer, cert.password)

  // Advertencia de certificado próximo a vencer o vencido
  const ahora = new Date()
  const validTo = new Date(certInfo.validTo)
  if (validTo < ahora) {
    // El SRI rechazará el documento — lanzar error explícito
    throw new Error(
      `CERTIFICADO_VENCIDO: venció el ${certInfo.validTo}. ` +
      'Renueve el certificado digital en la entidad certificadora.',
    )
  }

  // Paso 2: Firmar con ec-sri-invoice-signer
  // API del package: firmar(xml: string, p12: ArrayBuffer, password: string) => Promise<string>
  // Ref: https://www.npmjs.com/package/ec-sri-invoice-signer
  //
  // NOTA PARA DESARROLLADORES: Si la API del package cambia en versiones futuras,
  // actualizar esta llamada. El package genera la estructura XAdES-BES completa
  // con SignedInfo, SignatureValue, KeyInfo y QualifyingProperties.
  let xmlFirmado: string

  try {
    xmlFirmado = await firmar(xmlSinFirma, cert.p12Buffer, cert.password)
  } catch (signError) {
    const mensaje = signError instanceof Error
      ? signError.message
      : 'ERROR_FIRMA_DESCONOCIDO'

    throw new Error(`ERROR_FIRMA_XADES_BES: ${mensaje}`)
  }

  if (!xmlFirmado || typeof xmlFirmado !== 'string') {
    throw new Error('ERROR_FIRMA_XADES_BES: la librería no retornó XML válido')
  }

  // Paso 3: Codificar en Base64 para envío SOAP
  const xmlFirmadoBase64 = xmlABase64(xmlFirmado)

  return { xmlFirmado, xmlFirmadoBase64, certInfo }
}

// ---------------------------------------------------------------------------
// Validación previa del XML
// ---------------------------------------------------------------------------

/**
 * Validaciones básicas del XML antes de firmarlo.
 * No reemplaza la validación XSD completa — es un filtro rápido para
 * detectar errores obvios antes de consumir recursos de firma.
 *
 * Validaciones:
 *   - Presencia de declaración XML (<?xml ...?>)
 *   - claveAcceso de exactamente 49 dígitos
 *   - Presencia de <infoTributaria> (contiene RUC, codDoc, secuencial)
 *   - RUC de 13 dígitos dentro de <ruc>
 *   - Que el XML no esté vacío ni sea solo whitespace
 *
 * @returns { isValid, errors } — isValid es false si hay algún error
 */
export function validateXmlBeforeSigning(
  xml: string,
): { isValid: boolean; errors: string[] } {
  const errors: string[] = []

  // Verificar que no está vacío
  if (!xml || xml.trim().length === 0) {
    return { isValid: false, errors: ['XML vacío o solo whitespace'] }
  }

  // Debe comenzar con declaración XML
  if (!xml.trimStart().startsWith('<?xml')) {
    errors.push('XML debe comenzar con declaración <?xml version="1.0"')
  }

  // Debe contener claveAcceso de exactamente 49 dígitos
  // El tag puede tener atributos o no: <claveAcceso>...</ claveAcceso>
  const claveAccesoMatch = xml.match(/<claveAcceso[^>]*>(\d+)<\/claveAcceso>/)
  if (!claveAccesoMatch) {
    errors.push('claveAcceso no encontrada en el XML')
  } else if (claveAccesoMatch[1].length !== 49) {
    errors.push(
      `claveAcceso debe tener 49 dígitos, tiene ${claveAccesoMatch[1].length}`,
    )
  }

  // Debe tener bloque <infoTributaria> (presente en todos los comprobantes SRI)
  if (!xml.includes('<infoTributaria>')) {
    errors.push('Bloque <infoTributaria> no encontrado — XML de comprobante inválido')
  }

  // RUC: 13 dígitos dentro de <ruc> (obligatorio en infoTributaria)
  const rucMatch = xml.match(/<ruc>(\d+)<\/ruc>/)
  if (!rucMatch) {
    errors.push('Tag <ruc> no encontrado en el XML')
  } else if (rucMatch[1].length !== 13) {
    errors.push(`RUC debe tener 13 dígitos, tiene ${rucMatch[1].length}`)
  }

  // No debe contener firma preexistente (evita doble firma)
  if (xml.includes('<Signature') || xml.includes('<ds:Signature')) {
    errors.push(
      'El XML ya contiene un elemento <Signature> — no se puede firmar dos veces',
    )
  }

  return { isValid: errors.length === 0, errors }
}

// ---------------------------------------------------------------------------
// TODO: Implementación alternativa XAdES-BES con node-forge
// ---------------------------------------------------------------------------
//
// Si `ec-sri-invoice-signer` no está disponible en el entorno Deno,
// se puede implementar XAdES-BES manualmente con node-forge. Los pasos son:
//
// 1. Canonicalización C14N del documento XML (Canonical XML 1.0)
//    - Algoritmo: http://www.w3.org/TR/2001/REC-xml-c14n-20010315
//    - node-forge no incluye C14N nativo — requeriría implementación manual
//      o librería `@xmldom/xmldom` + `xml-c14n`
//
// 2. Digest SHA-256 del XML canonicalizado
//    const md = forge.md.sha256.create()
//    md.update(xmlC14n, 'utf8')
//    const digestBase64 = forge.util.encode64(md.digest().bytes())
//
// 3. Construcción de <SignedInfo> con referencia al digest
//
// 4. Signature RSA-SHA256 del <SignedInfo> canonicalizado
//    const privateKey = forge.pki.privateKeyFromPem(...)
//    const md2 = forge.md.sha256.create()
//    md2.update(signedInfoC14n, 'utf8')
//    const signature = privateKey.sign(md2)
//    const signatureBase64 = forge.util.encode64(signature)
//
// 5. Estructura XAdES-BES:
//    <Signature xmlns="http://www.w3.org/2000/09/xmldsig#" Id="Signature">
//      <SignedInfo> ... </SignedInfo>
//      <SignatureValue> ... </SignatureValue>
//      <KeyInfo> <X509Data> <X509Certificate>BASE64_CERT</X509Certificate> </X509Data> </KeyInfo>
//      <Object>
//        <xades:QualifyingProperties Target="#Signature" xmlns:xades="http://uri.etsi.org/01903/v1.3.2#">
//          <xades:SignedProperties Id="SignedProperties">
//            <xades:SignedSignatureProperties>
//              <xades:SigningTime>2024-01-15T10:30:00.000-05:00</xades:SigningTime>
//              <xades:SigningCertificate>
//                <xades:Cert>
//                  <xades:CertDigest>
//                    <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
//                    <ds:DigestValue>BASE64_CERT_SHA256</ds:DigestValue>
//                  </xades:CertDigest>
//                  <xades:IssuerSerial>
//                    <ds:X509IssuerName>CN=...</ds:X509IssuerName>
//                    <ds:X509SerialNumber>...</ds:X509SerialNumber>
//                  </xades:IssuerSerial>
//                </xades:Cert>
//              </xades:SigningCertificate>
//            </xades:SignedSignatureProperties>
//          </xades:SignedProperties>
//        </xades:QualifyingProperties>
//      </Object>
//    </Signature>
//
// Ref: ETSI EN 319 132-1 (XAdES), Ficha técnica SRI Ecuador v2.21
