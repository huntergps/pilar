/**
 * PILAR ERP — Edge Function: upload-certificate
 *
 * Sube un certificado digital .p12/.pfx a Supabase Storage (bucket privado
 * 'certificados'), parsea la fecha de vencimiento con node-forge, almacena
 * la contraseña en Supabase Vault y actualiza la tabla `empresas`.
 *
 * Requiere: verify_jwt = true
 * Permiso:  administracion.empresa.certificado
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from '@supabase/supabase-js'
import forge from 'node-forge'
import { corsHeaders, handleCors } from '../_shared/cors.ts'

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024 // 10 MB
const ALLOWED_EXTENSIONS = ['.p12', '.pfx']
const STORAGE_BUCKET = 'certificados'
const STORAGE_FILENAME = 'firma.p12'
const CERT_CONTENT_TYPE = 'application/x-pkcs12'

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface CertInfo {
  expiresAt: Date | null
  commonName: string | null
  issuer: string | null
  isValid: boolean
  error?: string
}

interface SuccessResponse {
  ok: true
  empresa_id: string
  vence: string | null
  common_name: string | null
  issuer: string | null
  is_expired: boolean
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function errorResponse(status: number, code: string): Response {
  return new Response(
    JSON.stringify({ ok: false, error: code }),
    {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  )
}

function getFileExtension(filename: string): string {
  const lastDot = filename.lastIndexOf('.')
  if (lastDot === -1) return ''
  return filename.slice(lastDot).toLowerCase()
}

// ---------------------------------------------------------------------------
// Parser PKCS12
// ---------------------------------------------------------------------------

function parsePkcs12(p12Buffer: ArrayBuffer, password: string): CertInfo {
  try {
    const p12Bytes = new Uint8Array(p12Buffer)
    const p12BinaryStr = Array.from(p12Bytes)
      .map((b) => String.fromCharCode(b))
      .join('')

    const p12DerBuffer = forge.util.createBuffer(p12BinaryStr, 'binary')
    const p12Asn1 = forge.asn1.fromDer(p12DerBuffer)
    const p12 = forge.pkcs12.pkcs12FromAsn1(p12Asn1, password)

    const certBags = p12.getBags({ bagType: forge.pki.oids.certBag })
    const certBagArray = certBags[forge.pki.oids.certBag]

    if (!certBagArray || certBagArray.length === 0) {
      return {
        expiresAt: null,
        commonName: null,
        issuer: null,
        isValid: false,
        error: 'FORMATO_INVALIDO',
      }
    }

    const cert = certBagArray[0]?.cert
    if (!cert) {
      return {
        expiresAt: null,
        commonName: null,
        issuer: null,
        isValid: false,
        error: 'FORMATO_INVALIDO',
      }
    }

    const expiresAt = new Date(cert.validity.notAfter)
    const commonName = cert.subject.getField('CN')?.value ?? null
    const issuerCN = cert.issuer.getField('CN')?.value ?? null
    const isValid = expiresAt > new Date()

    return { expiresAt, commonName, issuer: issuerCN, isValid }
  } catch (err) {
    const msg = err instanceof Error ? err.message : ''

    // mac verify failure = contraseña incorrecta en node-forge
    if (
      msg.includes('mac verify') ||
      msg.includes('PKCS#12') ||
      msg.includes('Invalid password') ||
      msg.includes('invalid password')
    ) {
      return {
        expiresAt: null,
        commonName: null,
        issuer: null,
        isValid: false,
        error: 'CONTRASENA_INCORRECTA',
      }
    }

    return {
      expiresAt: null,
      commonName: null,
      issuer: null,
      isValid: false,
      error: 'FORMATO_INVALIDO',
    }
  }
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // 1. CORS preflight
  const corsResponse = handleCors(req)
  if (corsResponse) return corsResponse

  // 2. Solo POST
  if (req.method !== 'POST') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED')
  }

  // 3. Construir clientes Supabase
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return errorResponse(401, 'UNAUTHORIZED')
  }

  const supabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey)

  // 4. Verificar usuario autenticado y obtener empresa_id
  const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
  if (authError || !user) {
    return errorResponse(401, 'UNAUTHORIZED')
  }

  const empresaId = user.app_metadata?.empresa_id as string | undefined
  if (!empresaId) {
    return errorResponse(400, 'NO_EMPRESA_CONTEXT')
  }

  // 5. Verificar permiso
  const { data: hasPerm, error: permError } = await supabaseClient.rpc(
    'check_permission',
    { p_permiso: 'administracion.empresa.certificado' },
  )
  if (permError || !hasPerm) {
    return errorResponse(403, 'FORBIDDEN')
  }

  // 6. Parsear FormData
  let formData: FormData
  try {
    formData = await req.formData()
  } catch {
    return errorResponse(400, 'ARCHIVO_REQUERIDO')
  }

  const file = formData.get('file') as File | null
  const password = formData.get('password') as string | null

  // 7. Validaciones de entrada
  if (!file) {
    return errorResponse(400, 'ARCHIVO_REQUERIDO')
  }

  if (!password || password.trim() === '') {
    return errorResponse(400, 'CONTRASENA_REQUERIDA')
  }

  const ext = getFileExtension(file.name)
  if (!ALLOWED_EXTENSIONS.includes(ext)) {
    return errorResponse(400, 'EXTENSION_NO_PERMITIDA')
  }

  if (file.size > MAX_FILE_SIZE_BYTES) {
    return errorResponse(400, 'ARCHIVO_DEMASIADO_GRANDE')
  }

  // 8. Leer bytes del archivo
  let fileBuffer: ArrayBuffer
  try {
    fileBuffer = await file.arrayBuffer()
  } catch {
    return errorResponse(500, 'INTERNAL_ERROR')
  }

  // 9. Parsear PKCS12 y extraer metadatos del certificado
  const certInfo = parsePkcs12(fileBuffer, password)

  if (certInfo.error === 'CONTRASENA_INCORRECTA') {
    return errorResponse(400, 'CONTRASENA_INCORRECTA')
  }
  if (certInfo.error === 'FORMATO_INVALIDO') {
    return errorResponse(400, 'FORMATO_INVALIDO')
  }

  // 10. Determinar si el certificado ya está vencido (advertencia, no bloqueo)
  const isExpired = certInfo.expiresAt ? certInfo.expiresAt < new Date() : false

  // 11. Subir archivo a Storage (bucket privado, upsert reemplaza el anterior)
  const storagePath = `${empresaId}/${STORAGE_FILENAME}`

  const { error: storageError } = await supabaseAdmin.storage
    .from(STORAGE_BUCKET)
    .upload(storagePath, fileBuffer, {
      contentType: CERT_CONTENT_TYPE,
      upsert: true,
    })

  if (storageError) {
    console.error('[upload-certificate] Storage error:', storageError.message)
    return errorResponse(500, 'STORAGE_ERROR')
  }

  // 12. Almacenar contraseña en Vault (sin loguearla nunca)
  const { data: vaultKeyId, error: vaultError } = await supabaseAdmin.rpc(
    'store_certificate_password',
    {
      p_empresa_id: empresaId,
      p_password: password,
    },
  )

  if (vaultError || !vaultKeyId) {
    console.error('[upload-certificate] Vault error:', vaultError?.message ?? 'no vault_key_id returned')
    return errorResponse(500, 'VAULT_ERROR')
  }

  // 13. Actualizar tabla empresas via RPC
  const venceFecha = certInfo.expiresAt
    ? certInfo.expiresAt.toISOString().split('T')[0]
    : null

  const { error: dbError } = await supabaseAdmin.rpc(
    'update_empresa_certificado',
    {
      p_empresa_id: empresaId,
      p_certificado_path: storagePath,
      p_certificado_vence: venceFecha,
      p_vault_key_id: vaultKeyId,
    },
  )

  if (dbError) {
    console.error('[upload-certificate] DB error:', dbError.message)
    return errorResponse(500, 'DB_ERROR')
  }

  // 14. Respuesta exitosa
  // NUNCA incluir: password, vault_key_id, contenido del archivo
  const responseBody: SuccessResponse = {
    ok: true,
    empresa_id: empresaId,
    vence: venceFecha,
    common_name: certInfo.commonName,
    issuer: certInfo.issuer,
    is_expired: isExpired,
  }

  return new Response(JSON.stringify(responseBody), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
